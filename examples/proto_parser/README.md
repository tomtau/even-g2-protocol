# Proto Parser Example

This directory contains tools for parsing G2 BLE packets using the official protobuf definitions.

## Setup

First, compile the protobuf files:

```bash
# Install protobuf compiler
pip install protobuf grpcio-tools

# Compile all protos
cd proto/g2_re
protoc --python_out=../../examples/proto_parser *.proto
```

## Usage

### Parse a packet from hex string

```bash
# Parse health packet
python parse_packet.py aa21209301010e200802105e228a01...

# Or provide a file with xxd-style output
cat packet.txt | python parse_packet.py
```

### Example output

```
Raw data (153 bytes): aa21209301010e20...

=== Transport Header ===
  Prefix: 0xAA
  Type: 0x21
  Sync ID: 32
  Length: 147
  Packet: 1/1
  Service: UI_HEALTH_APP_ID (ID: 14)
  CRC: 0x4956 (✓ Valid)

=== Payload ===
  Hex: 0802105e228a01...

=== Protobuf Fields (Generic Parse) ===
  field_1: 2
  field_2: 94
  field_4: ...
```

## Service IDs

| ID | Service Name |
|----|-------------|
| 5 | UI_TRANSLATE_APP_ID |
| 6 | UI_TELEPROMPT_APP_ID |
| 7 | UI_FOREGROUND_EVEN_AI_ID |
| 8 | UI_BACKGROUND_NAVIGATION_ID |
| 10 | UI_TRANSCRIBE_APP_ID |
| 11 | UI_CONVERSATE_APP_ID |
| 14 | UI_HEALTH_APP_ID |

## Using Compiled Protos

Once you've compiled the protos, you can use them for type-safe parsing:

```python
from translate_pb2 import TranslateDataPackage

# Parse translation packet
payload = bytes.fromhex("0802105e22...")
msg = TranslateDataPackage()
msg.ParseFromString(payload)

print(f"Command: {msg.commandId}")
if msg.result:
    print(f"Original: {msg.result.srcText.decode()}")
    print(f"Translation: {msg.result.dstText.decode()}")
```
