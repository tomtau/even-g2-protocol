/// Even G2 Gesture Handler - Detect and Handle Touch Gestures
///
/// Listens for gesture events from G2 glasses and handles tap, swipe, and long press.
///
/// Usage:
///     swift run gesture
///
/// Requirements:
///     - macOS 12+ or iOS 15+
///     - Bluetooth permission

import CoreBluetooth
import Foundation
import Shared

// MARK: - Double Tap Detector

class DoubleTapDetector {
    private var lastTapTime: Date?
    private let doubleTapThreshold: TimeInterval = 0.3
    
    var onSingleTap: (() -> Void)?
    var onDoubleTap: (() -> Void)?
    
    func handleTap() {
        let now = Date()
        
        if let lastTap = lastTapTime,
           now.timeIntervalSince(lastTap) < doubleTapThreshold {
            // Double tap detected
            lastTapTime = nil
            onDoubleTap?()
        } else {
            // Potential single tap
            lastTapTime = now
            DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapThreshold) { [weak self] in
                if self?.lastTapTime != nil {
                    self?.onSingleTap?()
                    self?.lastTapTime = nil
                }
            }
        }
    }
}

// MARK: - BLE Manager

class G2GestureManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var notifyChar: CBCharacteristic?
    
    private let doubleTapDetector = DoubleTapDetector()
    private var gestureCounter = 0
    
    private let semaphore = DispatchSemaphore(value: 0)
    private var isScanning = false
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        
        doubleTapDetector.onSingleTap = { [weak self] in
            print("  → Single Tap detected!")
        }
        doubleTapDetector.onDoubleTap = { [weak self] in
            print("  → Double Tap detected!")
        }
    }
    
    func run() {
        print("Even G2 Gesture Handler")
        print(String(repeating: "=", count: 40))
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
        
        if name.contains("_L_") || name.contains("_R_") {
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
            if uuid.contains("5402") {
                notifyChar = char
                peripheral.setNotifyValue(true, for: char)
            }
        }
        
        if notifyChar != nil {
            print("\nListening for gestures...")
            print("  - Tap: Touch sensor briefly")
            print("  - Double Tap: Tap twice quickly")
            print("  - Swipe Forward: Swipe towards temple")
            print("  - Swipe Backward: Swipe towards nose")
            print("  - Long Press: Hold touch sensor")
            print("\nPress Ctrl+C to exit.\n")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
        if let gesture = detectGesture(from: data) {
            gestureCounter += 1
            
            let hexPreview = data.prefix(30).map { String(format: "%02x", $0) }.joined()
            print("\n[\(gestureCounter)] Gesture: \(gesture.rawValue)")
            print("    Raw: \(hexPreview)...")
            
            switch gesture {
            case .tap:
                doubleTapDetector.handleTap()
            case .swipeForward:
                print("  → Swipe Forward detected!")
            case .swipeBackward:
                print("  → Swipe Backward detected!")
            case .longPress:
                print("  → Long Press detected!")
            }
        }
    }
}

// MARK: - Main

@main
struct GestureApp {
    static func main() {
        let manager = G2GestureManager()
        
        // Handle Ctrl+C
        signal(SIGINT) { _ in
            print("\nInterrupted")
            exit(0)
        }
        
        manager.run()
    }
}
