import Foundation
import CoreBluetooth
import UserNotifications
import AVFoundation

/// A nearby heart-rate sensor found during a compatibility scan.
struct CompatDevice: Identifiable {
    let id: UUID
    var name: String
    var rssi: Int
    var rrSupported: Bool? = nil   // nil = not yet tested
    var testing: Bool = false
}

/// Connects to a standard BLE heart-rate strap (service 0x180D), streams BPM,
/// and fires local notifications when the wearer leaves their target band —
/// below `floorBpm` (too easy) or above `ceilingBpm` (too hard) — continuing to
/// work while the app is backgrounded or the screen is locked.
final class HeartRateManager: NSObject, ObservableObject {

    @Published var bpm: Int? = nil
    @Published var connected = false
    @Published var statusText = "Idle"
    @Published var deviceName: String? = nil
    @Published var bluetoothReady = false
    /// The strap we're locked to. Once paired, we ignore every other HR device.
    @Published private(set) var pinnedID: String?
    @Published private(set) var pinnedName: String?
    /// True once the pinned strap has been confirmed to send R-R (HRV) data.
    @Published private(set) var pinnedRRSupported = false

    /// Alert band, in bpm. Set from the view model based on Max HR + chosen zones.
    var floorBpm: Int = 0          // never drop below this
    var ceilingBpm: Int = 1000     // never go above this
    var alertsEnabled = true
    var voiceEnabled = false
    private let speaker = AVSpeechSynthesizer()

    private func speak(_ text: String) {
        guard voiceEnabled else { return }
        say(text)
    }

    /// Speak unconditionally (used by the interval timer cues).
    func say(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        u.rate = 0.5
        speaker.speak(u)
    }

    // Compatibility scan (list nearby HR sensors without auto-connecting)
    @Published var compatDevices: [CompatDevice] = []
    private enum ScanMode { case normal, compat }
    private var scanMode: ScanMode = .normal
    private var compatPeripherals: [UUID: CBPeripheral] = [:]
    private var testingID: UUID?

    /// Called on every heart-rate reading (used by the workout view model).
    var onReading: ((Int) -> Void)?
    /// Called with any R-R intervals (in milliseconds) included in a reading — used
    /// for HRV / OwnZone-style aerobic-threshold detection.
    var onRR: (([Double]) -> Void)?
    /// Called when the strap drops the connection (may auto-reconnect after).
    var onDisconnect: (() -> Void)?
    /// Called when the strap (re)connects.
    var onReconnect: (() -> Void)?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private let hrService = CBUUID(string: "180D")
    private let hrMeasurement = CBUUID(string: "2A37")
    private let restoreID = "com.pimpcats.zonealert.central"
    private var lastLowNotify = Date.distantPast
    private var lastHighNotify = Date.distantPast
    private let keepAlive = KeepAlive()

    override init() {
        super.init()
        pinnedID = UserDefaults.standard.string(forKey: "pinnedStrapID")
        pinnedName = UserDefaults.standard.string(forKey: "pinnedStrapName")
        pinnedRRSupported = UserDefaults.standard.bool(forKey: "pinnedRRSupported")
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: restoreID]
        )
    }

    /// Forget the paired strap so the next connect pairs a fresh one.
    func forgetDevice() {
        pinnedID = nil
        pinnedName = nil
        pinnedRRSupported = false
        UserDefaults.standard.removeObject(forKey: "pinnedStrapID")
        UserDefaults.standard.removeObject(forKey: "pinnedStrapName")
        UserDefaults.standard.removeObject(forKey: "pinnedRRSupported")
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        connected = false
        bpm = nil
        statusText = "Strap forgotten — tap Connect to pair a new one"
    }

    // MARK: - Controls

    func startScanning() {
        guard central.state == .poweredOn else {
            statusText = "Turn on Bluetooth to connect"
            return
        }
        // 1. Reconnect directly to our pinned strap (works even if it's already
        //    connected at the OS level and therefore not advertising).
        if let pid = pinnedID, let uuid = UUID(uuidString: pid),
           let known = central.retrievePeripherals(withIdentifiers: [uuid]).first {
            connectTo(known)
            return
        }
        // 2. Grab an HR strap already connected to the system (no pin yet).
        if pinnedID == nil,
           let conn = central.retrieveConnectedPeripherals(withServices: [hrService]).first {
            pinIfNeeded(conn)
            connectTo(conn)
            return
        }
        // 3. Otherwise scan for advertising straps.
        statusText = pinnedName != nil ? "Searching for \(pinnedName!)…" : "Searching for your strap…"
        central.scanForPeripherals(withServices: [hrService], options: nil)
    }

    private func pinIfNeeded(_ peripheral: CBPeripheral) {
        guard pinnedID == nil else { return }
        pinnedID = peripheral.identifier.uuidString
        pinnedName = peripheral.name ?? "Heart rate strap"
        UserDefaults.standard.set(pinnedID, forKey: "pinnedStrapID")
        UserDefaults.standard.set(pinnedName, forKey: "pinnedStrapName")
    }

    private func connectTo(_ peripheral: CBPeripheral) {
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        deviceName = peripheral.name ?? pinnedName ?? "Heart rate strap"
        statusText = "Connecting to \(deviceName ?? "strap")…"
        keepAlive.start()      // keep alerts firing while backgrounded / screen locked
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        central.stopScan()
        connected = false
        statusText = "Disconnected"
        keepAlive.stop()
    }

    // MARK: - Compatibility scan

    func startCompatScan() {
        guard central.state == .poweredOn else { statusText = "Turn on Bluetooth"; return }
        scanMode = .compat
        compatDevices = []
        compatPeripherals = [:]
        central.scanForPeripherals(withServices: [hrService], options: nil)
    }

    func stopCompatScan() {
        if scanMode == .compat { central.stopScan() }
        scanMode = .normal
        if let id = testingID, let p = compatPeripherals[id] { central.cancelPeripheralConnection(p) }
        testingID = nil
    }

    /// Briefly connect to a discovered device to confirm it streams R-R (HRV) data.
    func testRR(id: UUID) {
        guard let p = compatPeripherals[id] else { return }
        central.stopScan()
        testingID = id
        if let i = compatDevices.firstIndex(where: { $0.id == id }) { compatDevices[i].testing = true }
        p.delegate = self
        central.connect(p, options: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self = self, self.testingID == id else { return }
            self.finishTest(id: id, rr: false)
        }
    }

    private func finishTest(id: UUID, rr: Bool) {
        if let i = compatDevices.firstIndex(where: { $0.id == id }) {
            compatDevices[i].rrSupported = rr
            compatDevices[i].testing = false
        }
        if pinnedID == id.uuidString {       // tested our own strap → record the badge
            pinnedRRSupported = rr
            UserDefaults.standard.set(rr, forKey: "pinnedRRSupported")
        }
        if let p = compatPeripherals[id] { central.cancelPeripheralConnection(p) }
        if testingID == id { testingID = nil }
        if scanMode == .compat { central.scanForPeripherals(withServices: [hrService], options: nil) }
    }

    // MARK: - Demo mode (simulated sensor — works with no hardware)

    @Published private(set) var demoMode = false
    private var demoTimer: Timer?
    private var demoStart = Date()

    func startDemo() {
        stopCompatScan()
        demoMode = true
        connected = true
        bluetoothReady = true
        deviceName = "Demo sensor"
        statusText = "Demo sensor (simulated)"
        demoStart = Date()
        keepAlive.start()      // lets demo run (and alert) in the background too
        demoTimer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.demoTick() }
        RunLoop.main.add(t, forMode: .common)
        demoTimer = t
    }

    func stopDemo() {
        demoMode = false
        demoTimer?.invalidate()
        demoTimer = nil
        connected = false
        bpm = nil
        statusText = "Demo stopped"
        keepAlive.stop()
    }

    private func demoTick() {
        let elapsed = Date().timeIntervalSince(demoStart)
        let base = 120.0 + 30.0 * sin(elapsed / 45.0)               // drift 90–150
        let value = max(55, Int(base) + Int.random(in: -3...3))
        // HRV shrinks as effort rises (so the threshold test can react)
        let hrv = max(2.0, 55.0 * (1.0 - Double(value - 70) / 95.0))
        let mean = 60000.0 / Double(value)
        let rr = [mean + Double.random(in: -hrv...hrv), mean + Double.random(in: -hrv...hrv)]
        onRR?(rr)
        bpm = value
        evaluate(value)
        onReading?(value)
    }

    func sendTestAlert() {
        notify(title: "🔔 Zone Alert test",
               body: "Alerts are working. You'll be buzzed if you drop below \(floorBpm) or go above \(ceilingBpm) bpm.")
    }

    /// Schedules a test alert a few seconds out so you can lock the screen and confirm
    /// the banner appears while the app is in the background.
    func scheduleBackgroundTest() {
        let content = UNMutableNotificationContent()
        content.title = "🔔 Background alert works"
        content.body = "If you can see this on your lock screen, zone alerts will reach you in the background."
        content.sound = .default
        if #available(iOS 15.0, *) { content.interruptionLevel = .timeSensitive }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 6, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger))
    }

    // MARK: - Alert evaluation

    private func evaluate(_ value: Int) {
        guard alertsEnabled else { return }
        let now = Date()
        if value < floorBpm {
            if now.timeIntervalSince(lastLowNotify) > 25 {
                lastLowNotify = now
                notify(title: "⬇️ Heart rate too low",
                       body: "\(value) bpm — below your Zone 2 floor of \(floorBpm). Pick up the pace.",
                       kind: "zone")
                speak("Heart rate low. Pick it up.")
            }
            lastHighNotify = .distantPast
        } else if value > ceilingBpm {
            if now.timeIntervalSince(lastHighNotify) > 25 {
                lastHighNotify = now
                notify(title: "⬆️ Heart rate too high",
                       body: "\(value) bpm — above your Zone 3 ceiling of \(ceilingBpm). Ease off.",
                       kind: "zone")
                speak("Heart rate high. Ease off.")
            }
            lastLowNotify = .distantPast
        } else {
            lastLowNotify = .distantPast
            lastHighNotify = .distantPast
        }
    }

    private func notify(title: String, body: String, kind: String = "general") {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["kind": kind]
        if #available(iOS 15.0, *) { content.interruptionLevel = .timeSensitive }
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    private func handle(bpm value: Int) {
        DispatchQueue.main.async {
            self.bpm = value
            self.evaluate(value)
            self.onReading?(value)
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension HeartRateManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async { self.bluetoothReady = (central.state == .poweredOn) }
        switch central.state {
        case .poweredOn:
            if let p = peripheral { central.connect(p, options: nil) }
        case .poweredOff:
            DispatchQueue.main.async { self.statusText = "Bluetooth is off"; self.connected = false }
        case .unauthorized:
            DispatchQueue.main.async { self.statusText = "Bluetooth permission denied" }
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let p = peripherals.first {
            peripheral = p
            p.delegate = self
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // Compatibility scan: just list devices, don't connect.
        if scanMode == .compat {
            let id = peripheral.identifier
            compatPeripherals[id] = peripheral
            if let i = compatDevices.firstIndex(where: { $0.id == id }) {
                compatDevices[i].rssi = RSSI.intValue
            } else {
                compatDevices.append(CompatDevice(id: id,
                                                  name: peripheral.name ?? "Unknown HR device",
                                                  rssi: RSSI.intValue))
            }
            return
        }
        // Normal: if already paired to a specific strap, ignore every other one.
        if let pid = pinnedID, pid != peripheral.identifier.uuidString { return }
        pinIfNeeded(peripheral)
        connectTo(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if peripheral.identifier == testingID {       // compatibility R-R test connection
            peripheral.discoverServices([hrService])
            return
        }
        DispatchQueue.main.async {
            self.connected = true
            self.statusText = "Connected to \(peripheral.name ?? "strap")"
            self.onReconnect?()
        }
        peripheral.discoverServices([hrService])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if peripheral.identifier == testingID { return }   // test connection closing
        guard peripheral == self.peripheral else { return } // ignore non-primary devices
        DispatchQueue.main.async {
            self.connected = false
            self.bpm = nil
            self.statusText = "Strap disconnected — retrying…"
            self.onDisconnect?()
        }
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if peripheral.identifier == testingID { finishTest(id: peripheral.identifier, rr: false); return }
        guard peripheral == self.peripheral else { return }
        DispatchQueue.main.async { self.statusText = "Connection failed — retrying…" }
        central.connect(peripheral, options: nil)
    }
}

// MARK: - CBPeripheralDelegate

extension HeartRateManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for s in services where s.uuid == hrService {
            peripheral.discoverCharacteristics([hrMeasurement], for: s)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for c in chars where c.uuid == hrMeasurement {
            peripheral.setNotifyValue(true, for: c)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == hrMeasurement,
              let data = characteristic.value, data.count >= 2 else { return }
        let bytes = [UInt8](data)
        let flags = bytes[0]

        // Compatibility R-R test: report whether this device includes R-R data.
        if peripheral.identifier == testingID {
            if flags & 0x10 != 0 { finishTest(id: peripheral.identifier, rr: true) }
            return
        }

        // Passive confirmation: our pinned strap is sending R-R during normal use.
        if flags & 0x10 != 0 && !pinnedRRSupported {
            pinnedRRSupported = true
            UserDefaults.standard.set(true, forKey: "pinnedRRSupported")
        }

        var idx = 1
        let value: Int
        if flags & 0x01 == 0 {
            value = Int(bytes[idx]); idx += 1
        } else {
            value = Int(bytes[idx]) | (Int(bytes[idx + 1]) << 8); idx += 2
        }
        if flags & 0x08 != 0 { idx += 2 }   // skip energy-expended field if present
        // R-R intervals (uint16 LE, units of 1/1024 s) when bit 4 is set
        if flags & 0x10 != 0 {
            var rrs: [Double] = []
            while idx + 1 < bytes.count {
                let raw = Int(bytes[idx]) | (Int(bytes[idx + 1]) << 8)
                rrs.append(Double(raw) / 1024.0 * 1000.0)   // → milliseconds
                idx += 2
            }
            if !rrs.isEmpty { let out = rrs; DispatchQueue.main.async { self.onRR?(out) } }
        }
        handle(bpm: value)
    }
}
