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

    /// Alert band, in bpm. Set from the view model based on Max HR + chosen zones.
    var floorBpm: Int = 0          // never drop below this
    var ceilingBpm: Int = 1000     // never go above this
    var alertsEnabled = true

    /// Called on every heart-rate reading (used by the workout view model).
    var onReading: ((Int) -> Void)?
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
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: restoreID]
        )
    }

    // MARK: - Controls

    func startScanning() {
        guard central.state == .poweredOn else {
            statusText = "Turn on Bluetooth to connect"
            return
        }
        statusText = "Searching for strap…"
        central.scanForPeripherals(withServices: [hrService], options: nil)
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
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        DispatchQueue.main.async {
            self.deviceName = peripheral.name ?? "Heart rate strap"
            self.statusText = "Connecting to \(self.deviceName ?? "strap")…"
        }
        central.connect(peripheral, options: nil)
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
        let value: Int
        if flags & 0x01 == 0 {
            value = Int(bytes[1])
        } else {
            value = Int(bytes[1]) | (Int(bytes[2]) << 8)
        }
        handle(bpm: value)
    }
}
