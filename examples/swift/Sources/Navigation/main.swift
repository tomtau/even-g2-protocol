/// Even G2 Navigation - Send Turn-by-Turn Navigation to Glasses
///
/// Sends navigation updates with distance, instructions, ETA, and maneuver icons.
///
/// Usage:
///     swift run navigation "86 m" "Turn left" "7 min" "701 m" "ETA: 13:07"
///     swift run navigation --demo
///
/// Requirements:
///     - macOS 12+ or iOS 15+
///     - Bluetooth permission

import CoreBluetooth
import Foundation
import Shared

// MARK: - BLE Manager

class G2NavigationManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    
    private var distance: String
    private var instruction: String
    private var timeRemaining: String
    private var totalDistance: String
    private var eta: String
    private var demoMode: Bool
    
    private let semaphore = DispatchSemaphore(value: 0)
    private var isScanning = false
    
    init(distance: String, instruction: String, timeRemaining: String,
         totalDistance: String, eta: String, demoMode: Bool = false) {
        self.distance = distance
        self.instruction = instruction
        self.timeRemaining = timeRemaining
        self.totalDistance = totalDistance
        self.eta = eta
        self.demoMode = demoMode
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func run() {
        print("Even G2 Navigation")
        print(String(repeating: "=", count: 40))
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
        
        // Prefer left eye for navigation
        if name.contains("_L_") {
            self.peripheral = peripheral
            print("  Found: \(name)")
            central.stopScan()
            isScanning = false
            
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
        } else if self.peripheral == nil && name.contains("_R_") {
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
        
        if demoMode {
            runDemo()
        } else {
            sendNavigation()
        }
    }
    
    // MARK: - Send Navigation
    
    private func sendNavigation() {
        guard let peripheral = peripheral, let writeChar = writeChar else { return }
        
        print("\nSending navigation update...")
        
        let nav = G2Navigation(
            distance: distance,
            instruction: instruction,
            timeRemaining: timeRemaining,
            totalDistance: totalDistance,
            eta: eta
        )
        
        let packet = nav.buildPacket(sequence: 0x10)
        peripheral.writeValue(packet, for: writeChar, type: .withoutResponse)
        
        print("  Sent: \(instruction) in \(distance)")
        print("\nDone! Check your glasses.")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.centralManager.cancelPeripheralConnection(peripheral)
            self.semaphore.signal()
        }
    }
    
    // MARK: - Demo Mode
    
    private func runDemo() {
        guard let peripheral = peripheral, let writeChar = writeChar else { return }
        
        print("\nRunning navigation demo...")
        
        let demoSteps: [(String, String, String, String, String, ManeuverIcon)] = [
            ("200 m", "Turn left onto Main St", "12 min", "2.1 km", "ETA: 14:32", .turnLeft),
            ("150 m", "Turn left onto Main St", "12 min", "2.0 km", "ETA: 14:32", .turnLeft),
            ("100 m", "Turn left onto Main St", "11 min", "1.9 km", "ETA: 14:32", .turnLeft),
            ("50 m", "Turn left onto Main St", "11 min", "1.85 km", "ETA: 14:32", .turnLeft),
            ("300 m", "Continue straight", "10 min", "1.8 km", "ETA: 14:32", .straight),
            ("250 m", "Continue straight", "10 min", "1.75 km", "ETA: 14:32", .straight),
            ("200 m", "Turn right onto Oak Ave", "9 min", "1.5 km", "ETA: 14:32", .turnRight),
            ("100 m", "Turn right onto Oak Ave", "9 min", "1.4 km", "ETA: 14:32", .turnRight),
            ("50 m", "Turn right onto Oak Ave", "8 min", "1.35 km", "ETA: 14:32", .turnRight),
            ("500 m", "Your destination is ahead", "5 min", "500 m", "ETA: 14:30", .straight),
        ]
        
        var seq: UInt8 = 0x10
        
        func sendStep(_ index: Int) {
            guard index < demoSteps.count else {
                print("\nDemo complete!")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.centralManager.cancelPeripheralConnection(peripheral)
                    self.semaphore.signal()
                }
                return
            }
            
            let (dist, inst, time, total, eta, icon) = demoSteps[index]
            let nav = G2Navigation(
                distance: dist,
                instruction: inst,
                timeRemaining: time,
                totalDistance: total,
                eta: eta,
                iconType: icon
            )
            
            let packet = nav.buildPacket(sequence: seq)
            peripheral.writeValue(packet, for: writeChar, type: .withoutResponse)
            print("  Sent: \(inst) in \(dist)")
            
            seq &+= 1
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                sendStep(index + 1)
            }
        }
        
        sendStep(0)
    }
}

// MARK: - Main

@main
struct NavigationApp {
    static func main() {
        let args = CommandLine.arguments
        
        let demoMode = args.contains("--demo")
        
        if !demoMode && args.count < 6 {
            print("Usage:")
            print("  swift run navigation \"86 m\" \"Turn left\" \"7 min\" \"701 m\" \"ETA: 13:07\"")
            print("  swift run navigation --demo")
            return
        }
        
        let manager: G2NavigationManager
        
        if demoMode {
            manager = G2NavigationManager(
                distance: "",
                instruction: "",
                timeRemaining: "",
                totalDistance: "",
                eta: "",
                demoMode: true
            )
        } else {
            manager = G2NavigationManager(
                distance: args[1],
                instruction: args[2],
                timeRemaining: args[3],
                totalDistance: args[4],
                eta: args[5]
            )
        }
        
        manager.run()
    }
}
