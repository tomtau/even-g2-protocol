# Rust Examples

Rust implementations of the Even G2 protocol examples.

## Setup

### Prerequisites

- Rust toolchain (1.70+)
- Bluetooth adapter with BLE support
- Even G2 glasses

### Build

```bash
cd examples/rust
cargo build --release
```

## Examples

### Notification

Send custom push notifications to G2 glasses.

```bash
# Send notification with all fields
cargo run --bin notification -- "Title" "Subtitle" "Message body"

# Send with title and subtitle only
cargo run --bin notification -- "Sender" "Hello there!"

# Quick message (uses defaults)
cargo run --bin notification
```

### Teleprompter

Display custom scrollable text on glasses.

```bash
# Simple text
cargo run --bin teleprompter -- "Hello world!"

# Multi-line (use \n for newlines)
cargo run --bin teleprompter -- "Line one\nLine two\nLine three"

# Use right eye instead of left (default)
cargo run --bin teleprompter -- "Hello" --right
```

### Even AI

Display custom questions and answers on the Even AI card.

```bash
# Positional arguments
cargo run --bin even-ai -- "What is 2+2?" "The answer is 4!"

# Named arguments
cargo run --bin even-ai -- --question "Hello" --answer "Hi there!"
cargo run --bin even-ai -- -q "Hello" -a "Hi there!"

# Use left eye instead of right (default)
cargo run --bin even-ai -- "Question" "Answer" --left
```

### Gesture

Listen for and handle gesture events from the glasses.

```bash
cargo run --bin gesture
```

Detects: tap, double-tap (software), swipe forward, swipe backward, long press.

### Navigation

Send turn-by-turn navigation updates to glasses.

```bash
# Single navigation update
cargo run --bin navigation -- "86 m" "Turn left" "7 min" "701 m" "ETA: 13:07"

# Run demo sequence
cargo run --bin navigation -- --demo
```

## Dependencies

The examples use the following Rust crates:

- `btleplug` - Cross-platform Bluetooth Low Energy library
- `tokio` - Async runtime
- `uuid` - UUID handling
- `futures` - Async utilities
- `chrono` - Date/time handling
- `serde` / `serde_json` - JSON serialization
- `hex` - Hex encoding/decoding

## Platform Notes

### Linux

Requires BlueZ and may need root privileges or `cap_net_admin` capability:

```bash
sudo setcap cap_net_admin+eip target/release/notification
```

### macOS

Uses CoreBluetooth. No special permissions needed beyond Bluetooth access.

### Windows

Uses WinRT Bluetooth APIs. May need to run as administrator.
