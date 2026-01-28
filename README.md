# Even Realities G2 Smart Glasses - Protocol Documentation

I have been reverse engineering the Even Realities G2 smart glasses BLE protocol. If you are interersted in joining this effort, please do!

## What the hell does that even mean???

The G2 glasses use a custom protocol created by EvenRealities. This BLE (bluetooth) protocol is used to transmit data in packets to and from the glasses. Currently, the G2 glasses are restricted to the functionality offered in the Even app - reverse engineering the BLE protocol removes this restriction.



## Status

| Feature | Status | Notes |
|---------|--------|-------|
| BLE Connection | Working | Standard BLE, no special pairing |
| Authentication | Working | 7-packet handshake sequence |
| Teleprompter | Working | Custom text display confirmed |
| Calendar Widget | Working | Display events on glasses |
| Notifications | Working | Custom text with CRC32C checksum |
| Gestures | Working | Tap, swipe, long press detection |
| Navigation | Working | Turn-by-turn navigation display |
| Even AI | Research | Protocol identified |

## Quick Start

```bash
# Install dependencies (from repo root)
pip install -r requirements.txt
```

### Notifications

```bash
# Send custom notification to glasses
python examples/notif/notification.py "Sender" "Subject Line" "Message body"

# Size-limited version (guaranteed single-packet delivery)
python examples/notif/notification_trunc.py "Sender" "Subject" "Long message..."
```

See [examples/notif/README.md](examples/notif/README.md) for details.

### Teleprompter

```bash
# Display custom text on glasses
python examples/teleprompter/teleprompter.py "Hello from Python!"

# Multi-line text
python examples/teleprompter/teleprompter.py "Line one
Line two
Line three"
```

### Gestures

```bash
# Listen for gesture events
python examples/gesture/gesture_handler.py
```

Detected gestures: tap, double-tap, swipe forward, swipe backward, long press.

### Navigation

```bash
# Send navigation update
python examples/navigation/navigation.py "86 m" "Turn left" "7 min" "701 m" "ETA: 13:07"

# Run demo sequence
python examples/navigation/navigation.py --demo
```

## Documentation

- [BLE Services & UUIDs](docs/ble-uuids.md) - Complete characteristic mapping
- [Packet Structure](docs/packet-structure.md) - Transport layer format
- [Service Reference](docs/services.md) - All known service IDs
- [Notification Protocol (File)](docs/notification-file.md) - Push notification via file transfer
- [Notification Protocol (ANCS)](docs/notification-ancs.md) - ANCS-like notification format
- [Teleprompter Protocol](docs/teleprompter.md) - Text display implementation
- [Gesture Callbacks](docs/gesture-callbacks.md) - Tap, swipe, long press detection
- [Navigation Protocol](docs/navigation.md) - Turn-by-turn navigation

## Protocol Files

- [proto/](proto/) - Protobuf definitions for payload encoding

## Key Findings

### Packet CRC (CRC-16/CCITT)
- **Type**: CRC-16/CCITT
- **Init**: 0xFFFF
- **Polynomial**: 0x1021
- **Scope**: Calculated over payload bytes only (skip 8-byte header)
- **Format**: Little-endian

### File Checksum (CRC-32C)
Used for notification/file transfers to validate content integrity:
- **Type**: CRC-32C (Castagnoli)
- **Polynomial**: 0x1EDC6F41
- **Init**: 0
- **Mode**: Non-reflected (MSB-first)

The checksum is split across two fields in the file check header:
```
checksum = (CRC32C << 8) & 0xFFFFFFFF   # Lower 24 bits, 0x00 in low byte
extra    = (CRC32C >> 24) & 0xFF        # High byte of CRC
```
Glasses reconstruct: `full_crc = (extra << 24) | (checksum >> 8)`

### Packet Structure
```
[AA] [21] [seq] [len] [01] [01] [svc_hi] [svc_lo] [payload...] [crc_lo] [crc_hi]
```

### Architecture
The G2 uses a multi-channel design:
- **Control Channel** (0x5401/0x5402): Auth, protobuf commands (teleprompter, dashboard)
- **Rendering Channel** (0x6402): Display positioning, binary commands
- **File Channel** (0x7401/0x7402): File transfers (notifications as JSON)

## Contributing

Pull requests welcome! Areas needing research:
- Even AI request/response format
- Translation feature
- Display rendering commands (0x6402)
- Multi-packet file transfers (notifications >234 bytes)
- Additional maneuver icons for navigation

## Credits

- Protocol research by the Even Realities community


## Disclaimer

This is an unofficial community project for educational purposes. Not affiliated with Even Realities.

## Discord
For all communications, I recommend Discord. Join the [EvenRealities Discord Server](https://discord.gg/arDkX3pr), which contains a reverse engineering channel containing many threads, including G2 RE.
