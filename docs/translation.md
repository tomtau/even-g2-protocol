# Translation Protocol

This document describes the real-time speech translation feature for Even G2 glasses, including language pair configuration and translation result display.

## Overview

Translation is transmitted on Service `0x0520` via the control channel. The feature supports multiple language pairs (e.g., Czech→English, Cantonese→English) with real-time streaming results showing both original speech and translation.

## BLE Characteristics

| Handle | Direction | Purpose |
|--------|-----------|---------|
| `0x5401` | Phone → Glasses | Translation commands (Write) |
| `0x5402` | Glasses → Phone | Translation results (Notify) |

## Packet Structure

### Standard G2 Packet Format

```
[AA 21] [Seq] [Len] [01 01] [05 20] [Payload...] [CRC:2 LE]
```

Service ID: `0x0520` (Translation)

## Message Types

### Type 0x01: Mode Control

Controls translation enable/disable with language pair selection.

#### Enable Translation

```
08 01                    - Type: Mode Control
10 XX                    - Message ID (varint)
1A YY                    - Field 3, length YY
  08 01                  - Mode: Enable
  12 ZZ                  - Language pair, length ZZ
  [language_pair_utf8]   - e.g., "CS>EN", "HK>EN"
  18 01                  - Action: Enable
```

#### Disable Translation

```
08 01                    - Type: Mode Control
10 XX                    - Message ID (varint)
1A YY                    - Field 3, length YY
  08 02                  - Mode: Disable
```

### Type 0x02: Translation Result

Contains original speech text and translated text.

```
08 02                    - Type: Translation Result
10 XX                    - Message ID (varint)
22 YY                    - Content field, length YY
  0A ZZ                  - Original text field, length ZZ
  [original_utf8]        - Original speech in source language
  12 WW                  - Translation field, length WW
  [translation_utf8]     - Translated text in target language
18 00                    - Unknown field
20 XX                    - Final flag (00=interim, 01=final)
2A 14                    - Speaker info field, length 20
  FE FF                  - UTF-16 BOM
  [speaker_utf16]        - Speaker name in UTF-16 BE
```

### Type 0xFF: Marker

Sync/marker packet sent during streaming.

```
08 FF 01                 - Type: Marker
10 XX                    - Message ID (varint)
42 00                    - Marker data
```

## Language Pair Format

Language pairs are specified as `SOURCE>TARGET` strings:

| Code | Language | Region |
|------|----------|--------|
| `CS` | Czech | Czech Republic |
| `HK` | Cantonese | Hong Kong |
| `EN` | English | - |
| `ZH` | Mandarin Chinese | China |
| `JA` | Japanese | Japan |
| `KO` | Korean | Korea |
| `ES` | Spanish | Spain |
| `FR` | French | France |
| `DE` | German | Germany |

*Note: Language codes follow ISO 639-1 or regional codes used by the Even app.*

## Example Packets

### Enable Czech→English Translation

```
Raw: AA 21 21 13 01 01 05 20 08 01 10 5F 1A 0B 08 01 12 05 43 53 3E 45 4E 18 01 [CRC]

Decoded:
  Sequence: 0x21
  Service: 0x0520 (Translation)
  Type: 0x01 (Mode Control)
  MsgID: 0x5F
  Language: CS>EN
  Action: Enable
```

### Translation Result

```
Raw: AA 21 24 55 01 01 05 20 08 02 10 62 22 4D 0A 19 
     "Dobrý den, jak se máte?" 
     12 16 
     "Good day, how are you?"
     18 00 20 00 2A 14 FE FF "Speaker 1" [CRC]

Decoded:
  Sequence: 0x24
  Service: 0x0520 (Translation)
  Type: 0x02 (Result)
  MsgID: 0x62
  Original: "Dobrý den, jak se máte?"
  Translation: "Good day, how are you?"
  Final: false
  Speaker: "Speaker 1"
```

### Disable Translation

```
Raw: AA 21 28 0A 01 01 05 20 08 01 10 66 1A 02 08 02 [CRC]

Decoded:
  Sequence: 0x28
  Service: 0x0520 (Translation)
  Type: 0x01 (Mode Control)
  MsgID: 0x66
  Action: Disable
```

## Implementation

### Building Translation Packets (Python)

```python
def build_translation_enable(seq: int, msg_id: int, language_pair: str) -> bytes:
    """Build packet to enable translation with specified language pair."""
    lang_bytes = language_pair.encode('utf-8')
    
    # Mode data: 08 01 12 len lang 18 01
    mode_data = bytes([0x08, 0x01, 0x12, len(lang_bytes)]) + lang_bytes + bytes([0x18, 0x01])
    
    # Payload: 08 01 10 msg_id 1A len mode_data
    payload = bytes([0x08, 0x01, 0x10, msg_id, 0x1A, len(mode_data)]) + mode_data
    
    return build_packet(seq, 0x05, 0x20, payload)


def build_translation_disable(seq: int, msg_id: int) -> bytes:
    """Build packet to disable translation."""
    # Mode data: 08 02
    mode_data = bytes([0x08, 0x02])
    
    # Payload: 08 01 10 msg_id 1A len mode_data
    payload = bytes([0x08, 0x01, 0x10, msg_id, 0x1A, len(mode_data)]) + mode_data
    
    return build_packet(seq, 0x05, 0x20, payload)
```

### Parsing Translation Results (Python)

```python
def parse_translation_result(payload: bytes) -> dict | None:
    """Parse translation result from service 0x0520 payload."""
    if len(payload) < 4 or payload[0] != 0x08 or payload[1] != 0x02:
        return None
    
    result = {}
    idx = 2
    
    while idx < len(payload):
        tag = payload[idx]
        
        if tag == 0x10:  # Message ID
            idx += 1
            result['msg_id'] = payload[idx]
            idx += 1
        
        elif tag == 0x22:  # Translation content
            idx += 1
            content_len = payload[idx]
            idx += 1
            content = payload[idx:idx + content_len]
            idx += content_len
            
            # Parse content: 0A len original 12 len translation
            cidx = 0
            if content[cidx] == 0x0A:
                cidx += 1
                orig_len = content[cidx]
                cidx += 1
                result['original'] = content[cidx:cidx + orig_len].decode('utf-8')
                cidx += orig_len
                
                if cidx < len(content) and content[cidx] == 0x12:
                    cidx += 1
                    trans_len = content[cidx]
                    cidx += 1
                    result['translation'] = content[cidx:cidx + trans_len].decode('utf-8')
        
        elif tag == 0x18:
            idx += 2  # Skip unknown field
        
        elif tag == 0x20:  # Final flag
            idx += 1
            result['is_final'] = payload[idx] == 0x01
            idx += 1
        
        elif tag == 0x2A:  # Speaker info
            idx += 1
            spk_len = payload[idx]
            idx += 1
            # Skip speaker data (UTF-16 encoded)
            idx += spk_len
        
        else:
            idx += 1
    
    return result
```

### Rust Implementation

```rust
/// Translation language pair
pub struct TranslationConfig {
    pub source: String,  // e.g., "CS"
    pub target: String,  // e.g., "EN"
}

impl TranslationConfig {
    pub fn new(source: &str, target: &str) -> Self {
        Self {
            source: source.to_string(),
            target: target.to_string(),
        }
    }
    
    pub fn language_pair(&self) -> String {
        format!("{}>{}", self.source, self.target)
    }
}

/// Build translation enable packet
pub fn build_translation_enable(seq: u8, msg_id: u8, config: &TranslationConfig) -> Vec<u8> {
    let lang = config.language_pair();
    let lang_bytes = lang.as_bytes();
    
    // Mode data: 08 01 12 len lang 18 01
    let mut mode_data = vec![0x08, 0x01, 0x12, lang_bytes.len() as u8];
    mode_data.extend_from_slice(lang_bytes);
    mode_data.extend_from_slice(&[0x18, 0x01]);
    
    // Payload: 08 01 10 msg_id 1A len mode_data
    let mut payload = vec![0x08, 0x01, 0x10, msg_id, 0x1A, mode_data.len() as u8];
    payload.extend(mode_data);
    
    build_packet(seq, 0x05, 0x20, &payload)
}

/// Build translation disable packet
pub fn build_translation_disable(seq: u8, msg_id: u8) -> Vec<u8> {
    let mode_data = vec![0x08, 0x02];
    let mut payload = vec![0x08, 0x01, 0x10, msg_id, 0x1A, mode_data.len() as u8];
    payload.extend(mode_data);
    
    build_packet(seq, 0x05, 0x20, &payload)
}
```

### Swift Implementation

```swift
/// Translation configuration
public struct TranslationConfig {
    public let source: String  // e.g., "CS"
    public let target: String  // e.g., "EN"
    
    public var languagePair: String {
        "\(source)>\(target)"
    }
}

/// Build translation enable packet
public func buildTranslationEnable(seq: UInt8, msgId: UInt8, config: TranslationConfig) -> Data {
    let lang = config.languagePair.utf8
    
    // Mode data: 08 01 12 len lang 18 01
    var modeData = Data([0x08, 0x01, 0x12, UInt8(lang.count)])
    modeData.append(contentsOf: lang)
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
```

## Translation Flow

1. **Enable Translation**: Send mode control packet with language pair
2. **Receive Results**: Listen for translation result packets
   - Interim results (`is_final=false`): Partial transcription/translation
   - Final results (`is_final=true`): Complete sentence
3. **Disable Translation**: Send mode control disable packet

## Display Behavior

When translation is enabled:
- Original speech appears in source language
- Translation appears below in target language
- Speaker identification shows who is speaking
- Results update in real-time as speech is detected

## Capture Method

Translation packets were captured using:
- iOS device with Bluetooth logging profile
- Apple PacketLogger during active translation session
- Handle filter: `btatt.handle == 0x0844` (notify characteristic)

## Contributing

If you capture additional language pairs or discover new translation features, please contribute packet dumps with:
- Source and target languages used
- Sample sentences spoken
- Whether results were interim or final
