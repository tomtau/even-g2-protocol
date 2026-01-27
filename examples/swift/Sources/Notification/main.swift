/// Even G2 Push Notification - Send Custom Notifications
///
/// Sends push notifications with custom text to Even G2 glasses.
///
/// Usage:
///     swift run notification "Title" "Subtitle" "Message"
///     swift run notification "Sender" "Hello there!"
///
/// Requirements:
///     - macOS 12+ or iOS 15+
///     - Bluetooth permission

import CoreBluetooth
import Foundation
import Shared

// MARK: - Notification Payload

struct AndroidNotification: Codable {
    let msgId: Int
    let action: Int
    let appIdentifier: String
    let title: String
    let subtitle: String
    let message: String
    let timeS: Int
    let date: String
    let displayName: String
    
    enum CodingKeys: String, CodingKey {
        case msgId = "msg_id"
        case action
        case appIdentifier = "app_identifier"
        case title
        case subtitle
        case message
        case timeS = "time_s"
        case date
        case displayName = "display_name"
    }
}

struct NotificationPayload: Codable {
    let androidNotification: AndroidNotification
    
    enum CodingKeys: String, CodingKey {
        case androidNotification = "android_notification"
    }
}

/// Build notification JSON payload.
func buildNotificationJSON(
    title: String,
    subtitle: String,
    message: String,
    appId: String = "com.google.android.gm",
    displayName: String = "Gmail"
) -> Data {
    let ts = Int(Date().timeIntervalSince1970)
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss"
    
    let notification = NotificationPayload(
        androidNotification: AndroidNotification(
            msgId: 10000 + (ts % 10000),
            action: 0,
            appIdentifier: appId,
            title: title,
            subtitle: subtitle,
            message: message,
            timeS: ts,
            date: dateFormatter.string(from: Date()),
            displayName: displayName
        )
    )
    
    let encoder = JSONEncoder()
    encoder.outputFormatting = [] // Compact output
    return try! encoder.encode(notification)
}

// MARK: - BLE Manager

class G2NotificationManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var centralManager: CBCentralManager!
    private var leftPeripheral: CBPeripheral?
    private var rightPeripheral: CBPeripheral?
    private var leftWriteChar: CBCharacteristic?
    private var rightWriteChar: CBCharacteristic?
    private var rightNotifWriteChar: CBCharacteristic?
    
    private var title: String
    private var subtitle: String
    private var message: String
    
    private let semaphore = DispatchSemaphore(value: 0)
    private var isScanning = false
    private var connectedCount = 0
    private var discoveredCount = 0
    
    init(title: String, subtitle: String, message: String) {
        self.title = title
        self.subtitle = subtitle
        self.message = message
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func run() {
        print("Even G2 Custom Notification")
        print(String(repeating: "=", count: 40))
        
        // Wait for Bluetooth to be ready
        _ = semaphore.wait(timeout: .now() + 30)
    }
    
    // MARK: - CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("\nScanning for G2 glasses...")
            isScanning = true
            central.scanForPeripherals(withServices: nil, options: nil)
            
            // Stop scan after 10 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                if self.isScanning {
                    central.stopScan()
                    if self.leftPeripheral == nil || self.rightPeripheral == nil {
                        print("ERROR: Need both G2 eyes!")
                        self.semaphore.signal()
                    }
                }
            }
        case .poweredOff:
            print("Bluetooth is powered off")
            semaphore.signal()
        case .unauthorized:
            print("Bluetooth permission denied")
            semaphore.signal()
        case .unsupported:
            print("Bluetooth not supported")
            semaphore.signal()
        default:
            break
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                       advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name, name.contains("G2") else { return }
        
        if name.contains("_L_") && leftPeripheral == nil {
            leftPeripheral = peripheral
            print("  LEFT:  \(name)")
        } else if name.contains("_R_") && rightPeripheral == nil {
            rightPeripheral = peripheral
            print("  RIGHT: \(name)")
        }
        
        if leftPeripheral != nil && rightPeripheral != nil {
            central.stopScan()
            isScanning = false
            connectPeripherals()
        }
    }
    
    private func connectPeripherals() {
        guard let left = leftPeripheral, let right = rightPeripheral else { return }
        
        left.delegate = self
        right.delegate = self
        
        centralManager.connect(left, options: nil)
        centralManager.connect(right, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedCount += 1
        if connectedCount == 2 {
            print("\nConnected!")
            leftPeripheral?.discoverServices(nil)
            rightPeripheral?.discoverServices(nil)
        }
    }
    
    // MARK: - CBPeripheralDelegate
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for char in characteristics {
            let uuid = char.uuid.uuidString.lowercased()
            
            if peripheral == leftPeripheral {
                if uuid.contains("5401") {
                    leftWriteChar = char
                }
                if uuid.contains("5402") || uuid.contains("7402") {
                    peripheral.setNotifyValue(true, for: char)
                }
            } else if peripheral == rightPeripheral {
                if uuid.contains("5401") {
                    rightWriteChar = char
                }
                if uuid.contains("7401") {
                    rightNotifWriteChar = char
                }
                if uuid.contains("5402") || uuid.contains("7402") {
                    peripheral.setNotifyValue(true, for: char)
                }
            }
        }
        
        discoveredCount += 1
        if discoveredCount >= 2 && leftWriteChar != nil && rightWriteChar != nil && rightNotifWriteChar != nil {
            startAuthentication()
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        // Handle notifications (ignored for now)
    }
    
    // MARK: - Protocol Implementation
    
    private func startAuthentication() {
        print("\nAuthenticating...")
        
        let authPackets = buildAuthPackets()
        
        // Authenticate left eye
        for (i, packet) in authPackets.enumerated() {
            leftPeripheral?.writeValue(packet, for: leftWriteChar!, type: .withoutResponse)
            usleep(100_000) // 100ms
        }
        print("  LEFT: Authenticated")
        
        // Authenticate right eye
        for packet in authPackets {
            rightPeripheral?.writeValue(packet, for: rightWriteChar!, type: .withoutResponse)
            usleep(100_000) // 100ms
        }
        print("  RIGHT: Authenticated")
        
        usleep(500_000) // 500ms
        sendNotification()
    }
    
    private func sendNotification() {
        let jsonBytes = buildNotificationJSON(title: title, subtitle: subtitle, message: message)
        let (size, checksum, extra) = calcFileCheckFields(jsonBytes)
        
        print("\nSending: \(title) / \(subtitle)")
        print("  \(jsonBytes.count) bytes, checksum: 0x\(String(format: "%08X", checksum))")
        
        guard let notifChar = rightNotifWriteChar else { return }
        
        // FILE_CHECK
        let filename = "user/notify_whitelist.json".data(using: .utf8)!
        var fcPayload = Data()
        fcPayload.append(contentsOf: withUnsafeBytes(of: UInt32(0x100).littleEndian) { Array($0) })
        fcPayload.append(contentsOf: withUnsafeBytes(of: size.littleEndian) { Array($0) })
        fcPayload.append(contentsOf: withUnsafeBytes(of: checksum.littleEndian) { Array($0) })
        fcPayload.append(extra)
        fcPayload.append(filename)
        fcPayload.append(Data(count: 80 - filename.count))
        
        rightPeripheral?.writeValue(
            buildPacket(seq: 0x10, svcHi: 0xC4, svcLo: 0x00, payload: fcPayload),
            for: notifChar,
            type: .withoutResponse
        )
        usleep(300_000) // 300ms
        
        // START
        rightPeripheral?.writeValue(
            buildPacket(seq: 0x49, svcHi: 0xC4, svcLo: 0x00, payload: Data([0x01])),
            for: notifChar,
            type: .withoutResponse
        )
        usleep(100_000) // 100ms
        
        // DATA chunks
        let chunkSize = 234
        var chunks: [Data] = []
        var offset = 0
        while offset < jsonBytes.count {
            let end = min(offset + chunkSize, jsonBytes.count)
            chunks.append(jsonBytes.subdata(in: offset..<end))
            offset = end
        }
        
        for (i, chunk) in chunks.enumerated() {
            let pkt = buildPacket(
                seq: 0x49,
                svcHi: 0xC5,
                svcLo: 0x00,
                payload: chunk,
                totalPkts: UInt8(chunks.count),
                pktNum: UInt8(i + 1)
            )
            rightPeripheral?.writeValue(pkt, for: notifChar, type: .withoutResponse)
            usleep(50_000) // 50ms
        }
        usleep(300_000) // 300ms
        
        // END
        rightPeripheral?.writeValue(
            buildPacket(seq: 0xDA, svcHi: 0xC4, svcLo: 0x00, payload: Data([0x02])),
            for: notifChar,
            type: .withoutResponse
        )
        
        // Heartbeat to left eye
        usleep(200_000) // 200ms
        if let leftChar = leftWriteChar {
            let heartbeat = Data([0xaa, 0x21, 0x0e, 0x06, 0x01, 0x01, 0x80, 0x20,
                                  0x08, 0x0e, 0x10, 0x6b, 0x6a, 0x00, 0xe1, 0x74])
            leftPeripheral?.writeValue(heartbeat, for: leftChar, type: .withoutResponse)
        }
        
        print("\nNotification sent!")
        
        // Wait a bit then clean up
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.centralManager.cancelPeripheralConnection(self.leftPeripheral!)
            self.centralManager.cancelPeripheralConnection(self.rightPeripheral!)
            self.semaphore.signal()
        }
    }
}

// MARK: - Main

@main
struct NotificationApp {
    static func main() {
        let args = CommandLine.arguments
        
        let title: String
        let subtitle: String
        let message: String
        
        switch args.count {
        case 1:
            title = "Swift"
            subtitle = "Test Notification"
            message = "Hello from Swift!"
        case 2:
            title = "Message"
            subtitle = args[1]
            message = ""
        case 3:
            title = args[1]
            subtitle = args[2]
            message = ""
        default:
            title = args[1]
            subtitle = args[2]
            message = args[3]
        }
        
        let manager = G2NotificationManager(title: title, subtitle: subtitle, message: message)
        manager.run()
    }
}
