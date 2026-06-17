import Foundation
import CoreBluetooth
import UserNotifications

/// Connects to a standard BLE heart-rate strap (service 0x180D), streams BPM,
/// and fires local notifications when the wearer drops below their target zone —
/// continuing to work while the app is backgrounded or the screen is locked,
/// thanks to the `bluetooth-central` background mode + state restoration.
final class HeartRateManager: NSObject, ObservableObject {

    // Published UI state
    @Published var bpm: Int? = nil
    @Published var currentZone: Int? = nil
    @Published var connected = false
    @Published var statusText = "Idle"
    @Published var deviceName: String? = nil
    @Published var bluetoothReady = false

    // Settings (mirrored from the UI / UserDefaults)
    var age: Int = 40 { didSet { recomputeZone() } }
    var targetZone: Int = 2 { didSet { recomputeZone() } }

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private let hrService = CBUUID(string: "180D")
    private let hrMeasurement = CBUUID(string: "2A37")
    private let restoreID = "com.pimpcats.zonealert.central"
    private var lastBelowNotify = Date.distantPast
    private var wasBelow = false

    override init() {
        super.init()
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: restoreID]
        )
    }

    // MARK: - Public controls

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
        notifyBelow(currentZoneNumber: 0, force: true)
    }

    // MARK: - Zone evaluation

    private func mhr() -> Int { Zones.mhr(age: age) }

    private func recomputeZone() {
        guard let b = bpm else { return }
        let z = Zones.zone(forBpm: b, mhr: mhr())
        currentZone = z
        evaluate(zone: z)
    }

    private func handle(bpm value: Int) {
        DispatchQueue.main.async {
            self.bpm = value
            let z = Zones.zone(forBpm: value, mhr: self.mhr())
            self.currentZone = z
            self.evaluate(zone: z)
        }
    }

    private func evaluate(zone: Int) {
        let below = zone < targetZone
        if below {
            // Notify on entry, then re-notify periodically while still below.
            let now = Date()
            if !wasBelow || now.timeIntervalSince(lastBelowNotify) > 25 {
                lastBelowNotify = now
                notifyBelow(currentZoneNumber: zone, force: false)
            }
        }
        wasBelow = below
    }

    private func notifyBelow(currentZoneNumber zone: Int, force: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "⬇️ Below Zone \(targetZone)"
        let where_ = zone == 0 ? "below Zone 1" : "Zone \(zone)"
        content.body = "You're in \(where_) — pick up the pace to get back to Zone \(targetZone)."
        content.sound = .default
        if #available(iOS 15.0, *) { content.interruptionLevel = .timeSensitive }
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}

// MARK: - CBCentralManagerDelegate

extension HeartRateManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async {
            self.bluetoothReady = (central.state == .poweredOn)
        }
        switch central.state {
        case .poweredOn:
            // Reconnect to a known peripheral after restore, else start scanning.
            if let p = peripheral {
                central.connect(p, options: nil)
            } else {
                startScanning()
            }
        case .poweredOff:
            DispatchQueue.main.async { self.statusText = "Bluetooth is off"; self.connected = false }
        case .unauthorized:
            DispatchQueue.main.async { self.statusText = "Bluetooth permission denied" }
        default:
            break
        }
    }

    // Required for state restoration (background relaunch).
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
        }
        peripheral.discoverServices([hrService])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        DispatchQueue.main.async {
            self.connected = false
            self.bpm = nil
            self.currentZone = nil
            self.statusText = "Strap disconnected — retrying…"
        }
        // Auto-reconnect (works in background too).
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
            value = Int(bytes[1])                                   // 8-bit bpm
        } else {
            value = Int(bytes[1]) | (Int(bytes[2]) << 8)           // 16-bit bpm
        }
        handle(bpm: value)
    }
}
