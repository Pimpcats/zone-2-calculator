import Foundation
import CoreBluetooth
import UserNotifications

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

    /// Alert band, in bpm. Set from the view model based on Max HR + chosen zones.
    var floorBpm: Int = 0          // never drop below this
    var ceilingBpm: Int = 1000     // never go above this
    var alertsEnabled = true

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

    override init() {
        super.init()
        pinnedID = UserDefaults.standard.string(forKey: "pinnedStrapID")
        pinnedName = UserDefaults.standard.string(forKey: "pinnedStrapName")
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
        UserDefaults.standard.removeObject(forKey: "pinnedStrapID")
        UserDefaults.standard.removeObject(forKey: "pinnedStrapName")
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
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        central.stopScan()
        connected = false
        statusText = "Disconnected"
    }

    func sendTestAlert() {
        notify(title: "🔔 Zone Alert test",
               body: "Alerts are working. You'll be buzzed if you drop below \(floorBpm) or go above \(ceilingBpm) bpm.")
    }

    // MARK: - Alert evaluation

    private func evaluate(_ value: Int) {
        guard alertsEnabled else { return }
        let now = Date()
        if value < floorBpm {
            if now.timeIntervalSince(lastLowNotify) > 25 {
                lastLowNotify = now
                notify(title: "⬇️ Heart rate too low",
                       body: "\(value) bpm — below your Zone 2 floor of \(floorBpm). Pick up the pace.")
            }
            lastHighNotify = .distantPast
        } else if value > ceilingBpm {
            if now.timeIntervalSince(lastHighNotify) > 25 {
                lastHighNotify = now
                notify(title: "⬆️ Heart rate too high",
                       body: "\(value) bpm — above your Zone 3 ceiling of \(ceilingBpm). Ease off.")
            }
            lastLowNotify = .distantPast
        } else {
            lastLowNotify = .distantPast
            lastHighNotify = .distantPast
        }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
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
        // If we're already paired to a specific strap, ignore every other one.
        if let pid = pinnedID, pid != peripheral.identifier.uuidString { return }
        pinIfNeeded(peripheral)
        connectTo(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        DispatchQueue.main.async {
            self.connected = true
            self.statusText = "Connected to \(peripheral.name ?? "strap")"
            self.onReconnect?()
        }
        peripheral.discoverServices([hrService])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        DispatchQueue.main.async {
            self.connected = false
            self.bpm = nil
            self.statusText = "Strap disconnected — retrying…"
            self.onDisconnect?()
        }
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
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
