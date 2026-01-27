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

- `Sources/Shared/G2Protocol.swift` - Common protocol utilities (CRC, packets, auth)
- `Sources/Notification/main.swift` - Push notification example
- `Sources/Teleprompter/main.swift` - Teleprompter example
- `Sources/EvenAI/main.swift` - Even AI Q&A example

All examples use CoreBluetooth for BLE communication and follow the same protocol patterns as the Python examples.
