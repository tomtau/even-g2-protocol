/// Even G2 Translation - Real-time Speech Translation
///
/// Enables translation mode on G2 glasses and displays translation results.
///
/// Usage:
///     swift run translation CS EN     # Czech to English
///     swift run translation HK EN     # Cantonese to English
///     swift run translation --list    # Show available languages
///
/// Requirements:
///     - macOS 12+ or iOS 15+
///     - Bluetooth permission

import CoreBluetooth
import Foundation
import Shared

// MARK: - Language Codes

let languages: [String: String] = [
    "EN": "English",
    "CS": "Czech",
    "HK": "Cantonese (Hong Kong)",
    "ZH": "Mandarin Chinese",
    "JA": "Japanese",
    "KO": "Korean",
    "ES": "Spanish",
    "FR": "French",
    "DE": "German",
    "IT": "Italian",
    "PT": "Portuguese",
    "RU": "Russian",
    "AR": "Arabic",
]

// MARK: - Translation Protocol

/// Build translation enable packet
public func buildTranslationEnable(seq: UInt8, msgId: UInt8, source: String, target: String) -> Data {
    let langPair = "\(source)>\(target)"
    let langBytes = Data(langPair.utf8)
    
    // Mode data: 08 01 12 len lang 18 01
    var modeData = Data([0x08, 0x01, 0x12, UInt8(langBytes.count)])
    modeData.append(langBytes)
    modeData.append(contentsOf: [0x18, 0x01])
    
    // Payload: 08 01 10 msg_id 1A len mode_data
    var payload = Data([0x08, 0x01, 0x10, msgId, 0x1A, UInt8(modeData.count)])
    payload.append(modeData)
    
    return buildPacket(seq: seq, svcHi: 0x05, svcLo: 0x20, payload: payload)
}

/// Build translation disable packet
public func buildTranslationDisable(seq: UInt8, msgId: UInt8) -> Data {
    let modeData = Data([0x08, 0x02])
    var payload = Data([0x08, 0x01, 0x10, msgId, 0x1A, UInt8(modeData.count)])
    payload.append(modeData)
    
    return buildPacket(seq: seq, svcHi: 0x05, svcLo: 0x20, payload: payload)
}

/// Translation result
public struct TranslationResult {
    public let original: String
    public let translation: String
    public let isFinal: Bool
}

/// Parse translation result from notification data
public func parseTranslationResult(data: Data) -> TranslationResult? {
    // Find service 05 20 in data
    var serviceIdx: Int?
    for i in 0..<(data.count - 1) {
        if data[i] == 0x05 && data[i + 1] == 0x20 {
            serviceIdx = i + 2
            break
        }
    }
    
    guard let payloadStart = serviceIdx, payloadStart + 4 <= data.count else {
        return nil
    }
    
    let payload = data.subdata(in: payloadStart..<(data.count - 2))
    
    guard payload.count >= 4, payload[0] == 0x08, payload[1] == 0x02 else {
        return nil
    }
    
    var original = ""
    var translation = ""
    var isFinal = false
    var idx = 2
    
    while idx < payload.count {
        let tag = payload[idx]
        
        if tag == 0x10 {
            idx += 2 // Skip msg_id
        } else if tag == 0x22 {
            idx += 1
            guard idx < payload.count else { break }
            let contentLen = Int(payload[idx])
            idx += 1
            guard idx + contentLen <= payload.count else { break }
            let content = payload.subdata(in: idx..<(idx + contentLen))
            idx += contentLen
            
            // Parse content: 0A len original 12 len translation
            var cidx = 0
            if cidx < content.count && content[cidx] == 0x0A {
                cidx += 1
                if cidx < content.count {
                    let origLen = Int(content[cidx])
                    cidx += 1
                    if cidx + origLen <= content.count {
                        original = String(data: content.subdata(in: cidx..<(cidx + origLen)), encoding: .utf8) ?? ""
                        cidx += origLen
                    }
                }
                
                if cidx < content.count && content[cidx] == 0x12 {
                    cidx += 1
                    if cidx < content.count {
                        let transLen = Int(content[cidx])
                        cidx += 1
                        if cidx + transLen <= content.count {
                            translation = String(data: content.subdata(in: cidx..<(cidx + transLen)), encoding: .utf8) ?? ""
                        }
                    }
                }
            }
        } else if tag == 0x18 {
            idx += 2
        } else if tag == 0x20 {
            idx += 1
            if idx < payload.count {
                isFinal = payload[idx] == 0x01
            }
            idx += 1
        } else if tag == 0x2A {
            idx += 1
            if idx < payload.count {
                let spkLen = Int(payload[idx])
                idx += 1 + spkLen
            }
        } else {
            idx += 1
        }
    }
    
    guard !original.isEmpty else { return nil }
    
    return TranslationResult(original: original, translation: translation, isFinal: isFinal)
}

// MARK: - BLE Manager

class G2TranslationManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    
    private var source: String
    private var target: String
    private var seq: UInt8 = 0x10
    private var msgId: UInt8 = 0x50
    private var translationCount = 0
    
    private let semaphore = DispatchSemaphore(value: 0)
    private var isScanning = false
    
    init(source: String, target: String) {
        self.source = source.uppercased()
        self.target = target.uppercased()
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func run() {
        print("Even G2 Translation")
        print(String(repeating: "=", count: 40))
        print("\nLanguage: \(languages[source] ?? source) → \(languages[target] ?? target)")
        print("\nScanning for G2 glasses...")
        
        _ = semaphore.wait(timeout: .distantFuture)
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
                        print("ERROR: No G2 glasses found!")
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
        
        if name.contains("_L_") || (self.peripheral == nil && name.contains("_R_")) {
            self.peripheral = peripheral
            print("  Found: \(name)")
            central.stopScan()
            isScanning = false
            
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("\nConnected!")
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
            authenticate()
        }
    }
    
    // MARK: - Authentication
    
    private func authenticate() {
        guard let peripheral = peripheral, let writeChar = writeChar else { return }
        
        print("\nAuthenticating...")
        for packet in buildAuthPackets() {
            peripheral.writeValue(packet, for: writeChar, type: .withoutResponse)
            usleep(100_000)
        }
        usleep(500_000)
        print("  Authenticated!")
        
        enableTranslation()
    }
    
    // MARK: - Translation Control
    
    private func enableTranslation() {
        guard let peripheral = peripheral, let writeChar = writeChar else { return }
        
        print("\nEnabling \(source)>\(target) translation...")
        let packet = buildTranslationEnable(seq: seq, msgId: msgId, source: source, target: target)
        peripheral.writeValue(packet, for: writeChar, type: .withoutResponse)
        seq &+= 1
        msgId &+= 1
        
        print("\nTranslation active! Speak to see results.")
        print("Press Ctrl+C to stop.\n")
    }
    
    private func disableTranslation() {
        guard let peripheral = peripheral, let writeChar = writeChar else { return }
        
        print("\n\nDisabling translation...")
        let packet = buildTranslationDisable(seq: seq, msgId: msgId)
        peripheral.writeValue(packet, for: writeChar, type: .withoutResponse)
        usleep(500_000)
        print("Done! Received \(translationCount) translation(s).")
        semaphore.signal()
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
        if let result = parseTranslationResult(data: data) {
            translationCount += 1
            
            let finalMarker = result.isFinal ? "[FINAL]" : "[...]"
            print("\n\(finalMarker) Original: \(result.original)")
            print("      Translation: \(result.translation)")
        }
    }
    
    func shutdown() {
        disableTranslation()
    }
}

// MARK: - Main

@main
struct TranslationApp {
    static func main() {
        let args = CommandLine.arguments
        
        if args.contains("--list") || args.contains("-l") {
            print("Available language codes:")
            print(String(repeating: "-", count: 40))
            for (code, name) in languages.sorted(by: { $0.key < $1.key }) {
                print("  \(code): \(name)")
            }
            print("\nUsage: swift run translation SOURCE TARGET")
            print("Example: swift run translation CS EN")
            return
        }
        
        guard args.count >= 3 else {
            print("Even G2 Translation")
            print(String(repeating: "=", count: 40))
            print("\nUsage:")
            print("  swift run translation SOURCE TARGET")
            print("  swift run translation --list")
            print("\nExamples:")
            print("  swift run translation CS EN    # Czech to English")
            print("  swift run translation HK EN    # Cantonese to English")
            return
        }
        
        let source = args[1]
        let target = args[2]
        
        let manager = G2TranslationManager(source: source, target: target)
        
        // Handle Ctrl+C
        signal(SIGINT) { _ in
            print("\nInterrupted")
            exit(0)
        }
        
        manager.run()
    }
}
