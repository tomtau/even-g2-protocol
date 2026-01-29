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
        print("\nLanguage: \(G2Languages[source] ?? source) → \(G2Languages[target] ?? target)")
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
}

// MARK: - Send Mode Manager

class G2TranslationSendManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    
    private let original: String
    private let translation: String
    
    private let semaphore = DispatchSemaphore(value: 0)
    private var isScanning = false
    
    init(original: String, translation: String) {
        self.original = original
        self.translation = translation
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func run() {
        print("Even G2 Translation - Send Mode")
        print(String(repeating: "=", count: 40))
        print("\nOriginal:    \(original)")
        print("Translation: \(translation)")
        print("\nScanning for G2 glasses...")
        
        _ = semaphore.wait(timeout: .distantFuture)
    }
    
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
            sendTranslation()
        }
    }
    
    private func sendTranslation() {
        guard let peripheral = peripheral, let writeChar = writeChar else { return }
        
        print("\nAuthenticating...")
        for packet in buildAuthPackets() {
            peripheral.writeValue(packet, for: writeChar, type: .withoutResponse)
            usleep(100_000)
        }
        usleep(500_000)
        print("  Authenticated!")
        
        // Enable translation mode first
        // Note: The language pair here doesn't affect display when sending custom text
        print("\nEnabling translation display...")
        let enablePacket = buildTranslationEnable(seq: 0x10, msgId: 0x50, source: "EN", target: "EN")
        peripheral.writeValue(enablePacket, for: writeChar, type: .withoutResponse)
        usleep(500_000)
        
        // Send custom translation text
        print("\nSending translation text...")
        let sendPacket = buildTranslationResult(seq: 0x11, msgId: 0x51, original: original, translation: translation, isFinal: true)
        peripheral.writeValue(sendPacket, for: writeChar, type: .withoutResponse)
        
        print("\nTranslation sent! Check your glasses.")
        sleep(5)
        
        // Disable translation
        let disablePacket = buildTranslationDisable(seq: 0x12, msgId: 0x52)
        peripheral.writeValue(disablePacket, for: writeChar, type: .withoutResponse)
        usleep(300_000)
        print("Done!")
        
        semaphore.signal()
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        // Ignore notifications in send mode
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
            for (code, name) in G2Languages.sorted(by: { $0.key < $1.key }) {
                print("  \(code): \(name)")
            }
            print("\nUsage: swift run translation SOURCE TARGET")
            print("       swift run translation --send ORIGINAL TRANSLATION")
            print("Example: swift run translation CS EN")
            return
        }
        
        // Send mode: send custom translation text to glasses
        if let sendIdx = args.firstIndex(of: "--send") {
            guard args.count >= sendIdx + 3 else {
                print("Usage: swift run translation --send ORIGINAL TRANSLATION")
                print("Example: swift run translation --send 'Bonjour' 'Hello'")
                return
            }
            let original = args[sendIdx + 1]
            let translation = args[sendIdx + 2]
            
            let manager = G2TranslationSendManager(original: original, translation: translation)
            
            signal(SIGINT) { _ in
                print("\nInterrupted")
                exit(0)
            }
            
            manager.run()
            return
        }
        
        guard args.count >= 3 else {
            print("Even G2 Translation")
            print(String(repeating: "=", count: 40))
            print("\nUsage:")
            print("  swift run translation SOURCE TARGET        # Listen mode")
            print("  swift run translation --send ORIG TRANS    # Send custom text")
            print("  swift run translation --list               # Show languages")
            print("\nExamples:")
            print("  swift run translation CS EN                # Czech to English")
            print("  swift run translation HK EN                # Cantonese to English")
            print("  swift run translation --send 'Bonjour' 'Hello'")
            return
        }
        
        let source = args[1]
        let target = args[2]
        
        let manager = G2TranslationManager(source: source, target: target)
        
        // Handle Ctrl+C - note: signal handlers have limited functionality in Swift
        // The clean shutdown happens when the run loop completes
        signal(SIGINT) { _ in
            print("\nInterrupted")
            exit(0)
        }
        
        manager.run()
    }
}
