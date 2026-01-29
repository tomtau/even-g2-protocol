# Translation Example

Real-time speech translation on Even G2 glasses with two modes:
- **Listen Mode**: Uses glasses microphone for speech recognition and translation
- **Send Mode**: Send custom text directly to the glasses display

## Setup

```bash
pip install bleak
```

## Usage

### Listen Mode (Glasses Microphone)

```bash
# Czech to English
python translation.py CS EN

# Cantonese to English
python translation.py HK EN

# List available languages
python translation.py --list
```

### Send Mode (Custom Text)

```bash
# Send custom translation text to display
python translation.py --send "Bonjour" "Hello"

# Send with non-ASCII characters
python translation.py --send "你好" "Hello"

# Send multi-word text (use quotes)
python translation.py --send "Comment ça va?" "How are you?"
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

### Listen Mode

1. **Enable Translation**: Send mode control packet with language pair
2. **Receive Results**: Listen for translation result packets
   - Interim results: Partial transcription while speaking
   - Final results: Complete sentence when pause detected
3. **Display**: Shows original text and translation in real-time
4. **Disable**: Clean shutdown when Ctrl+C pressed

### Send Mode

1. **Enable Translation Display**: Initialize translation UI on glasses
2. **Send Text**: Push custom original/translation text to display
3. **Disable**: Clean up when done

## Example Output

### Listen Mode

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

### Send Mode

```
Even G2 Translation - Send Mode
========================================

Original:    Bonjour
Translation: Hello

Scanning for G2 glasses...
  Found: Even G2_L_XXXX

Connected!

Authenticating...
  Authenticated!

Enabling translation display...

Sending translation text...

Translation sent! Check your glasses.
Done!
```

## Protocol Details

Translation uses Service `0x0520` with protobuf-encoded messages:

- **Type 0x01**: Mode control (enable/disable)
- **Type 0x02**: Translation results (receive from mic OR send custom text)
- **Type 0xFF**: Marker/sync packets

See [docs/translation.md](../../docs/translation.md) for full protocol documentation.

## API Usage

```python
from translation import (
    build_translation_enable,
    build_translation_disable, 
    build_translation_result,
    parse_translation_result
)

# Enable Czech to English (listen mode)
packet = build_translation_enable(seq=0x10, msg_id=0x50, source="CS", target="EN")

# Send custom text to display
packet = build_translation_result(
    seq=0x11, 
    msg_id=0x51, 
    original="Bonjour", 
    translation="Hello",
    is_final=True,
    speaker="Speaker 1"
)

# Disable translation
packet = build_translation_disable(seq=0x12, msg_id=0x52)

# Parse result from notification (listen mode)
result = parse_translation_result(notification_data)
if result:
    print(f"Original: {result['original']}")
    print(f"Translation: {result['translation']}")
    print(f"Final: {result['is_final']}")
```

## Use Cases

### Third-Party Translation

Use your own translation service:

```python
# Get translation from your service
original = recognize_speech(audio)  # Your ASR
translation = translate(original, "fr", "en")  # Your translation

# Display on glasses
packet = build_translation_result(seq, msg_id, original, translation, is_final=True)
await client.write_gatt_char(CHAR_WRITE, packet)
```

### Live Captioning

Display same text in both fields for captioning:

```python
text = "Hello, welcome to the meeting"
packet = build_translation_result(seq, msg_id, text, text, is_final=True)
```
