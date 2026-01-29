# Swift Examples

Swift implementations of the Even G2 protocol examples.

## Setup

### Prerequisites

- Swift 5.9+
- macOS 12+ or iOS 15+
- Bluetooth permission
- Even G2 glasses

### Build

```bash
cd examples/swift
swift build
```

## Examples

### Notification

Send custom push notifications to G2 glasses.

```bash
# Send notification with all fields
swift run notification "Title" "Subtitle" "Message body"

# Send with title and subtitle only
swift run notification "Sender" "Hello there!"

# Quick message (uses defaults)
swift run notification
```

### Teleprompter

Display custom scrollable text on glasses.

```bash
# Simple text
swift run teleprompter "Hello world!"

# Multi-line (use \n for newlines)
swift run teleprompter "Line one\nLine two\nLine three"

# Use right eye instead of left (default)
swift run teleprompter "Hello" --right
```

### Even AI

Display custom questions and answers on the Even AI card.

```bash
# Positional arguments
swift run even-ai "What is 2+2?" "The answer is 4!"

# Named arguments
swift run even-ai --question "Hello" --answer "Hi there!"
swift run even-ai -q "Hello" -a "Hi there!"

# Use left eye instead of right (default)
swift run even-ai "Question" "Answer" --left
```

### Gesture

Listen for and handle gesture events from the glasses.

```bash
swift run gesture
```

Detects: tap, double-tap (software), swipe forward, swipe backward, long press.

### Navigation

Send turn-by-turn navigation updates to glasses.

```bash
# Single navigation update
swift run navigation "86 m" "Turn left" "7 min" "701 m" "ETA: 13:07"

# Run demo sequence
swift run navigation --demo
```

### Translation

Real-time speech translation.

```bash
# Listen mode: Czech to English
swift run translation CS EN

# Listen mode: Cantonese to English
swift run translation HK EN

# Send mode: display custom text on glasses
swift run translation --send "Bonjour" "Hello"

# List available languages
swift run translation --list
```

## Platform Notes

### macOS

The examples use CoreBluetooth. You may need to grant Bluetooth permission in System Preferences > Security & Privacy > Privacy > Bluetooth.

For command-line apps, you may also need to add a `Info.plist` with `NSBluetoothAlwaysUsageDescription`.

### iOS

To build for iOS, create an Xcode project and add the Swift files. Ensure the `Info.plist` includes:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>App needs Bluetooth to communicate with Even G2 glasses</string>
```

## Architecture

The Swift examples are organized as follows:

- `Sources/Shared/G2Protocol.swift` - Common protocol utilities (CRC, packets, auth, gestures, navigation, translation)
- `Sources/Notification/main.swift` - Push notification example
- `Sources/Teleprompter/main.swift` - Teleprompter example
- `Sources/EvenAI/main.swift` - Even AI Q&A example
- `Sources/Gesture/main.swift` - Gesture detection example
- `Sources/Navigation/main.swift` - Navigation example
- `Sources/Translation/main.swift` - Translation example

All examples use CoreBluetooth for BLE communication and follow the same protocol patterns as the Python examples.

## Library Usage

The `Shared` module can be imported and used as a library in your own Swift projects:

```swift
import Shared

// Build authentication packets
let authPackets = buildAuthPackets()

// Build translation packets
let enablePacket = buildTranslationEnable(seq: 0x10, msgId: 0x50, source: "CS", target: "EN")
let disablePacket = buildTranslationDisable(seq: 0x11, msgId: 0x51)

// Send custom translation text to display on glasses
let resultPacket = buildTranslationResult(
    seq: 0x12, 
    msgId: 0x52,
    original: "Bonjour",
    translation: "Hello",
    isFinal: true
)

// Parse incoming translation notifications
if let result = parseTranslationResult(data: notificationData) {
    print("Original: \(result.original)")
    print("Translation: \(result.translation)")
    print("Final: \(result.isFinal)")
}

// Build navigation packets
let nav = G2Navigation(
    distance: "86 m",
    instruction: "Turn left",
    timeRemaining: "7 min",
    totalDistance: "701 m",
    eta: "ETA: 13:07"
)
let navPacket = nav.buildPacket(sequence: 0x20)

// Detect gestures from notifications
if let gesture = detectGesture(from: notificationData) {
    switch gesture {
    case .tap: print("Tap detected")
    case .swipeForward: print("Swipe forward")
    case .swipeBackward: print("Swipe backward")
    case .longPress: print("Long press")
    }
}

// Access language codes
for (code, name) in G2Languages {
    print("\(code): \(name)")
}
```

### Available Functions

| Function | Description |
|----------|-------------|
| `buildAuthPackets()` | Build 7-packet authentication sequence |
| `buildTranslationEnable(seq:msgId:source:target:)` | Enable translation mode |
| `buildTranslationDisable(seq:msgId:)` | Disable translation mode |
| `buildTranslationResult(seq:msgId:original:translation:isFinal:speaker:)` | Send custom text to display |
| `parseTranslationResult(data:)` | Parse translation from notification |
| `detectGesture(from:)` | Detect gesture type from packet |
| `buildPacket(seq:svcHi:svcLo:payload:)` | Build a G2 protocol packet |
| `crc16CCITT(_:)` | Calculate CRC-16 for packet framing |
| `calcCRC32C(_:)` | Calculate CRC32C for file operations |

### Available Types

| Type | Description |
|------|-------------|
| `G2TranslationResult` | Parsed translation result (original, translation, isFinal) |
| `G2Navigation` | Navigation data with packet building |
| `G2Gesture` | Gesture enum (tap, swipeForward, swipeBackward, longPress) |
| `G2AncsNotification` | Parsed ANCS-style notification |
| `ManeuverIcon` | Navigation icon types |
| `G2Languages` | Dictionary of supported language codes |
