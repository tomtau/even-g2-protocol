/// Even AI Display - Send Custom Q&A to G2 Glasses
///
/// Displays custom questions and answers on the Even AI card.
/// No Even app or cloud service required.
///
/// Usage:
///     swift run even-ai "What is 2+2?" "The answer is 4!"
///     swift run even-ai --question "Hello" --answer "Hi there!"
///
/// Requirements:
///     - macOS 12+ or iOS 15+
///     - Bluetooth permission

import CoreBluetooth
import Foundation
import Shared

// MARK: - Even AI Protocol

/// CTRL(ENTER) - Enter Even AI mode.
/// REQUIRED before ASK/REPLY will display!
func buildCtrlEnter(seq: UInt8, magic: UInt8) -> Data {
    let payload = Data([
        0x08, 0x01,     // commandId = 1 (CTRL)
        0x10, magic,    // magicRandom
        0x1a, 0x02,     // ctrl field (field 3)
        0x08, 0x02      // status = 2 (EVEN_AI_ENTER)
    ])
    return buildPacket(seq: seq, svcHi: 0x07, svcLo: 0x20, payload: payload)
}

/// CTRL(EXIT) - Exit Even AI mode.
func buildCtrlExit(seq: UInt8, magic: UInt8) -> Data {
    let payload = Data([
        0x08, 0x01,     // commandId = 1 (CTRL)
        0x10, magic,    // magicRandom
        0x1a, 0x02,     // ctrl field
        0x08, 0x03      // status = 3 (EVEN_AI_EXIT)
    ])
    return buildPacket(seq: seq, svcHi: 0x07, svcLo: 0x20, payload: payload)
}

/// ASK - Display question text on glasses.
func buildAsk(seq: UInt8, magic: UInt8, text: String) -> Data {
    let textBytes = text.data(using: .utf8)!
    let textLenVarint = encodeVarint(UInt64(textBytes.count))
    
    var askInfo = Data([
        0x08, 0x00,     // cmdCnt = 0
        0x10, 0x00,     // streamEnable = 0
        0x18, 0x00,     // textMode = 0
        0x22            // text field (field 4)
    ])
    askInfo.append(textLenVarint)
    askInfo.append(textBytes)
    
    let askInfoLenVarint = encodeVarint(UInt64(askInfo.count))
    var payload = Data([
        0x08, 0x03,     // commandId = 3 (ASK)
        0x10, magic,    // magicRandom
        0x2a            // askInfo field (field 5)
    ])
    payload.append(askInfoLenVarint)
    payload.append(askInfo)
    
    return buildPacket(seq: seq, svcHi: 0x07, svcLo: 0x20, payload: payload)
}

/// REPLY - Display answer text on glasses.
func buildReply(seq: UInt8, magic: UInt8, text: String) -> Data {
    let textBytes = text.data(using: .utf8)!
    let textLenVarint = encodeVarint(UInt64(textBytes.count))
    
    var replyInfo = Data([
        0x08, 0x00,     // cmdCnt = 0
        0x10, 0x00,     // streamEnable = 0
        0x18, 0x00,     // textMode = 0
        0x22            // text field (field 4)
    ])
    replyInfo.append(textLenVarint)
    replyInfo.append(textBytes)
    
    let replyInfoLenVarint = encodeVarint(UInt64(replyInfo.count))
    var payload = Data([
        0x08, 0x05,     // commandId = 5 (REPLY)
        0x10, magic,    // magicRandom
        0x3a            // replyInfo field (field 7)
    ])
    payload.append(replyInfoLenVarint)
    payload.append(replyInfo)
    
    return buildPacket(seq: seq, svcHi: 0x07, svcLo: 0x20, payload: payload)
}

// MARK: - BLE Manager

class G2EvenAIManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    
    private var question: String
    private var answer: String
    private var useLeft: Bool
    
    private let semaphore = DispatchSemaphore(value: 0)
    private var isScanning = false
    
    init(question: String, answer: String, useLeft: Bool) {
        self.question = question
        self.answer = answer
        self.useLeft = useLeft
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func run() {
        print("Even G2 - Custom AI Display")
        print(String(repeating: "=", count: 50))
        print("\nScanning for G2 glasses...")
        
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
                        print("ERROR: No G2 glasses found")
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
        
        let pattern = useLeft ? "_L_" : "_R_"
        if name.contains(pattern) {
            self.peripheral = peripheral
            print("  Using: \(name)")
            central.stopScan()
            isScanning = false
            
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("  Connected!")
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
    
    // MARK: - Protocol Implementation
    
    private func authenticate() {
        guard let peripheral = peripheral, let writeChar = writeChar else { return }
        
        print("\nAuthenticating...")
        for packet in buildAuthPackets() {
            peripheral.writeValue(packet, for: writeChar, type: .withoutResponse)
            usleep(100_000)
        }
        usleep(500_000)
        print("  Authenticated!")
        
        displayQA()
    }
    
    private func displayQA() {
        guard let peripheral = peripheral, let writeChar = writeChar else { return }
        
        print("\nDisplaying Q&A...")
        
        var seq: UInt8 = 0x08
        var magic: UInt8 = 100
        
        // 1. Enter AI mode (REQUIRED!)
        print("  Entering AI mode...")
        peripheral.writeValue(buildCtrlEnter(seq: seq, magic: magic), for: writeChar, type: .withoutResponse)
        seq &+= 1
        magic &+= 1
        usleep(300_000)
        
        // 2. Display question
        print("  Displaying question: \(question)")
        peripheral.writeValue(buildAsk(seq: seq, magic: magic, text: question), for: writeChar, type: .withoutResponse)
        seq &+= 1
        magic &+= 1
        sleep(1)
        
        // 3. Display answer
        print("  Displaying answer: \(answer)")
        peripheral.writeValue(buildReply(seq: seq, magic: magic, text: answer), for: writeChar, type: .withoutResponse)
        
        print("\n\(String(repeating: "=", count: 50))")
        print("Done! Check your glasses.")
        print(String(repeating: "=", count: 50))
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            self.centralManager.cancelPeripheralConnection(peripheral)
            self.semaphore.signal()
        }
    }
}

// MARK: - Main

@main
struct EvenAIApp {
    static func main() {
        let args = CommandLine.arguments
        
        var question = "What is 2 + 2?"
        var answer = "The answer is 4!"
        var useLeft = false
        
        var i = 1
        while i < args.count {
            switch args[i] {
            case "-q", "--question":
                if i + 1 < args.count {
                    question = args[i + 1]
                    i += 2
                } else {
                    i += 1
                }
            case "-a", "--answer":
                if i + 1 < args.count {
                    answer = args[i + 1]
                    i += 2
                } else {
                    i += 1
                }
            case "--left":
                useLeft = true
                i += 1
            default:
                // Positional arguments
                if i == 1 && !args[i].hasPrefix("-") {
                    question = args[i]
                } else if i == 2 && !args[i].hasPrefix("-") {
                    answer = args[i]
                }
                i += 1
            }
        }
        
        let manager = G2EvenAIManager(question: question, answer: answer, useLeft: useLeft)
        manager.run()
    }
}
