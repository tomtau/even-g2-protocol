# Translation Example

Real-time speech translation on Even G2 glasses.

## Setup

```bash
pip install bleak
```

## Usage

```bash
# Czech to English
python translation.py CS EN

# Cantonese to English
python translation.py HK EN

# List available languages
python translation.py --list
```

## Supported Languages

| Code | Language |
|------|----------|
| EN | English |
| CS | Czech |
| HK | Cantonese (Hong Kong) |
| ZH | Mandarin Chinese |
| JA | Japanese |
| KO | Korean |
| ES | Spanish |
| FR | French |
| DE | German |
| IT | Italian |
| PT | Portuguese |
| RU | Russian |
| AR | Arabic |

*Note: Actual language support depends on the Even app and glasses firmware.*

## How It Works

1. **Enable Translation**: Send mode control packet with language pair
2. **Receive Results**: Listen for translation result packets
   - Interim results: Partial transcription while speaking
   - Final results: Complete sentence when pause detected
3. **Display**: Shows original text and translation in real-time
4. **Disable**: Clean shutdown when Ctrl+C pressed

## Example Output

```
Even G2 Translation
========================================

Language: Czech → English

Scanning for G2 glasses...
  Found: Even G2_L_XXXX

Connected!

Authenticating...
  Authenticated!

Enabling CS>EN translation...

Translation active! Speak to see results.
Press Ctrl+C to stop.

[...] Original: Dobrý den
      Translation: Good day

[...] Original: Dobrý den, jak se máte?
      Translation: Good day, how are you?

[FINAL] Original: Dobrý den, jak se máte? Mám se dobře.
        Translation: Good day, how are you? I'm doing well.

^C

Disabling translation...
Done! Received 3 translation(s).
```

## Protocol Details

Translation uses Service `0x0520` with protobuf-encoded messages:

- **Type 0x01**: Mode control (enable/disable)
- **Type 0x02**: Translation results
- **Type 0xFF**: Marker/sync packets

See [docs/translation.md](../../docs/translation.md) for full protocol documentation.

## API Usage

```python
from translation import build_translation_enable, build_translation_disable, parse_translation_result

# Enable Czech to English
packet = build_translation_enable(seq=0x10, msg_id=0x50, source="CS", target="EN")

# Disable translation
packet = build_translation_disable(seq=0x11, msg_id=0x51)

# Parse result from notification
result = parse_translation_result(notification_data)
if result:
    print(f"Original: {result['original']}")
    print(f"Translation: {result['translation']}")
    print(f"Final: {result['is_final']}")
```
