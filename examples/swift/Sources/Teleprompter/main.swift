/// Even G2 Teleprompter - Display Custom Text
///
/// Usage:
///     swift run teleprompter "Your text here"
///     swift run teleprompter "Line one\nLine two\nLine three"
///     swift run teleprompter "Use right eye" --right
///
/// Requirements:
///     - macOS 12+ or iOS 15+
///     - Bluetooth permission

import CoreBluetooth
import Foundation
import Shared

// MARK: - Teleprompter Protocol

/// Service 0x0E-20: Display configuration
func buildDisplayConfig(seq: UInt8, msgId: UInt32) -> Data {
    let configHex = "0801121308021090" + "4E1D00E094442500" + "000000280030001213" +
                    "0803100D0F1D0040" + "8D44250000000028" + "0030001212080410" +
                    "001D0000884225" + "00000000280030" + "001212080510001D" +
                    "00009242250000" + "A242280030001212" + "080610001D0000C6" +
                    "42250000C4422800" + "30001800"
    let config = Data(hexString: configHex)!
    
    let msgIdVarint = encodeVarint(UInt64(msgId))
    var payload = Data([0x08, 0x02, 0x10])
    payload.append(msgIdVarint)
    payload.append(0x22)
    payload.append(0x6A)
    payload.append(config)
    
    return buildPacket(seq: seq, svcHi: 0x0E, svcLo: 0x20, payload: payload)
}

/// Service 0x06-20 type=1: Initialize teleprompter
func buildTeleprompterInit(seq: UInt8, msgId: UInt32, totalLines: Int, manualMode: Bool = true) -> Data {
    let mode: UInt8 = manualMode ? 0x00 : 0x01
    
    // Scale content height based on line count (Bee Movie: 140 lines = 2665)
    let contentHeight = max(1, (totalLines * 2665) / 140)
    let contentHeightVarint = encodeVarint(UInt64(contentHeight))
    
    var display = Data([0x08, 0x01, 0x10, 0x00, 0x18, 0x00, 0x20, 0x8B, 0x02]) // Fixed settings
    display.append(0x28)
    display.append(contentHeightVarint) // Content height
    display.append(contentsOf: [0x30, 0xE6, 0x01]) // Line height = 230
    display.append(contentsOf: [0x38, 0x8E, 0x0A]) // Viewport = 1294
    display.append(contentsOf: [0x40, 0x05, 0x48, mode]) // Font size + mode
    
    var settings = Data([0x08, 0x01, 0x12, UInt8(display.count)])
    settings.append(display)
    
    let msgIdVarint = encodeVarint(UInt64(msgId))
    var payload = Data([0x08, 0x01, 0x10])
    payload.append(msgIdVarint)
    payload.append(0x1A)
    payload.append(UInt8(settings.count))
    payload.append(settings)
    
    return buildPacket(seq: seq, svcHi: 0x06, svcLo: 0x20, payload: payload)
}

/// Service 0x06-20 type=3: Content page
func buildContentPage(seq: UInt8, msgId: UInt32, pageNum: UInt8, text: String) -> Data {
    let textBytes = ("\n" + text).data(using: .utf8)!
    let textLenVarint = encodeVarint(UInt64(textBytes.count))
    
    let pageNumVarint = encodeVarint(UInt64(pageNum))
    var inner = Data([0x08])
    inner.append(pageNumVarint)
    inner.append(contentsOf: [0x10, 0x0A]) // 10 lines
    inner.append(0x1A)
    inner.append(textLenVarint)
    inner.append(textBytes)
    
    let innerLenVarint = encodeVarint(UInt64(inner.count))
    var content = Data([0x2A])
    content.append(innerLenVarint)
    content.append(inner)
    
    let msgIdVarint = encodeVarint(UInt64(msgId))
    var payload = Data([0x08, 0x03, 0x10])
    payload.append(msgIdVarint)
    payload.append(content)
    
    return buildPacket(seq: seq, svcHi: 0x06, svcLo: 0x20, payload: payload)
}

/// Service 0x06-20 type=255: Mid-stream marker
func buildMarker(seq: UInt8, msgId: UInt32) -> Data {
    let msgIdVarint = encodeVarint(UInt64(msgId))
    var payload = Data([0x08, 0xFF, 0x01, 0x10])
    payload.append(msgIdVarint)
    payload.append(contentsOf: [0x6A, 0x04, 0x08, 0x00, 0x10, 0x06])
    return buildPacket(seq: seq, svcHi: 0x06, svcLo: 0x20, payload: payload)
}

/// Service 0x80-00 type=14: Sync/trigger
func buildSync(seq: UInt8, msgId: UInt32) -> Data {
    let msgIdVarint = encodeVarint(UInt64(msgId))
    var payload = Data([0x08, 0x0E, 0x10])
    payload.append(msgIdVarint)
    payload.append(contentsOf: [0x6A, 0x00])
    return buildPacket(seq: seq, svcHi: 0x80, svcLo: 0x00, payload: payload)
}

// MARK: - Text Formatting

/// Format text into pages of wrapped lines
func formatText(_ text: String, charsPerLine: Int = 25, linesPerPage: Int = 10) -> [String] {
    // Handle escaped newlines
    let text = text.replacingOccurrences(of: "\\n", with: "\n")
    
    // Split and wrap lines
    var wrapped: [String] = []
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let lineStr = String(line)
        if lineStr.trimmingCharacters(in: .whitespaces).isEmpty {
            wrapped.append("")
            continue
        }
        
        let words = lineStr.split(separator: " ")
        var current = ""
        for word in words {
            if current.count + word.count + 1 > charsPerLine {
                if !current.isEmpty {
                    wrapped.append(current.trimmingCharacters(in: .whitespaces))
                }
                current = String(word) + " "
            } else {
                current += String(word) + " "
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            wrapped.append(current.trimmingCharacters(in: .whitespaces))
        }
    }
    
    if wrapped.isEmpty {
        wrapped.append(text)
    }
    
    // Pad to at least 10 lines
    while wrapped.count < linesPerPage {
        wrapped.append(" ")
    }
    
    // Split into pages
    var pages: [String] = []
    for i in stride(from: 0, to: wrapped.count, by: linesPerPage) {
        var pageLines = Array(wrapped[i..<min(i + linesPerPage, wrapped.count)])
        while pageLines.count < linesPerPage {
            pageLines.append(" ")
        }
        pages.append(pageLines.joined(separator: "\n") + " \n")
    }
    
    // Pad to minimum 14 pages
    while pages.count < 14 {
        let emptyPage = Array(repeating: " ", count: linesPerPage).joined(separator: "\n")
        pages.append(emptyPage + " \n")
    }
    
    return pages
}

// MARK: - Hex String Extension

extension Data {
    init?(hexString: String) {
        let hex = hexString.filter { !$0.isWhitespace }
        guard hex.count % 2 == 0 else { return nil }
        
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            if let byte = UInt8(hex[index..<nextIndex], radix: 16) {
                data.append(byte)
            } else {
                return nil
            }
            index = nextIndex
        }
        self = data
    }
}

// MARK: - BLE Manager

class G2TeleprompterManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    
    private var text: String
    private var useRight: Bool
    
    private let semaphore = DispatchSemaphore(value: 0)
    private var isScanning = false
    
    init(text: String, useRight: Bool) {
        self.text = text
        self.useRight = useRight
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func run() {
        print("Scanning for Even G2 glasses...")
        _ = semaphore.wait(timeout: .now() + 60)
    }
    
    // MARK: - CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            isScanning = true
            central.scanForPeripherals(withServices: nil, options: nil)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                if self.isScanning {
                    central.stopScan()
                    if self.peripheral == nil {
                        print("No G2 glasses found!")
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
        
        let pattern = useRight ? "_R_" : "_L_"
        if name.contains(pattern) {
            self.peripheral = peripheral
            print("Using: \(name)")
            central.stopScan()
            isScanning = false
            
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected!")
        peripheral.discoverServices(nil)
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
            if uuid.contains("5401") {
                writeChar = char
            }
            if uuid.contains("5402") {
                peripheral.setNotifyValue(true, for: char)
            }
        }
        
        if writeChar != nil {
            sendText()
        }
    }
    
    // MARK: - Send Text
    
    private func sendText() {
        guard let peripheral = peripheral, let writeChar = writeChar else { return }
        
        // Send auth sequence
        print("Authenticating...")
        for packet in buildAuthPackets() {
            peripheral.writeValue(packet, for: writeChar, type: .withoutResponse)
            usleep(100_000)
        }
        usleep(500_000)
        
        // Format text into pages
        let pages = formatText(text)
        let totalLines = text.replacingOccurrences(of: "\\n", with: "\n").split(separator: "\n").count
        
        var seq: UInt8 = 0x08
        var msgId: UInt32 = 0x14
        
        // Display config
        print("Configuring display...")
        peripheral.writeValue(buildDisplayConfig(seq: seq, msgId: msgId), for: writeChar, type: .withoutResponse)
        seq &+= 1
        msgId += 1
        usleep(300_000)
        
        // Teleprompter init
        print("Initializing teleprompter...")
        peripheral.writeValue(buildTeleprompterInit(seq: seq, msgId: msgId, totalLines: totalLines), for: writeChar, type: .withoutResponse)
        seq &+= 1
        msgId += 1
        usleep(500_000)
        
        // Send content pages 0-9
        print("Sending \(pages.count) pages...")
        for i in 0..<min(10, pages.count) {
            peripheral.writeValue(buildContentPage(seq: seq, msgId: msgId, pageNum: UInt8(i), text: pages[i]), for: writeChar, type: .withoutResponse)
            seq &+= 1
            msgId += 1
            usleep(100_000)
        }
        
        // Mid-stream marker
        peripheral.writeValue(buildMarker(seq: seq, msgId: msgId), for: writeChar, type: .withoutResponse)
        seq &+= 1
        msgId += 1
        usleep(100_000)
        
        // Pages 10-11
        for i in 10..<min(12, pages.count) {
            peripheral.writeValue(buildContentPage(seq: seq, msgId: msgId, pageNum: UInt8(i), text: pages[i]), for: writeChar, type: .withoutResponse)
            seq &+= 1
            msgId += 1
            usleep(100_000)
        }
        
        // Sync trigger
        peripheral.writeValue(buildSync(seq: seq, msgId: msgId), for: writeChar, type: .withoutResponse)
        seq &+= 1
        msgId += 1
        usleep(100_000)
        
        // Remaining pages
        for i in 12..<pages.count {
            peripheral.writeValue(buildContentPage(seq: seq, msgId: msgId, pageNum: UInt8(i), text: pages[i]), for: writeChar, type: .withoutResponse)
            seq &+= 1
            msgId += 1
            usleep(100_000)
        }
        
        print("Done! Check your glasses.")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            self.centralManager.cancelPeripheralConnection(peripheral)
            self.semaphore.signal()
        }
    }
}

// MARK: - Main

@main
struct TeleprompterApp {
    static func main() {
        let args = CommandLine.arguments
        
        let text = args.count > 1 ? args[1] : "Hello from Swift!\nThis is a test."
        let useRight = args.contains("--right")
        
        let manager = G2TeleprompterManager(text: text, useRight: useRight)
        manager.run()
    }
}
