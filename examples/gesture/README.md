# Gesture Handler Example

Listen for and handle gesture events from Even G2 glasses.

## Setup

```bash
pip install bleak
```

## Usage

```bash
python gesture_handler.py
```

## Supported Gestures

| Gesture | How to Perform | Detection |
|---------|----------------|-----------|
| Tap | Touch sensor briefly | Protocol-level |
| Double Tap | Tap twice quickly (<300ms) | Software-level |
| Swipe Forward | Swipe towards temple | Protocol-level |
| Swipe Backward | Swipe towards nose | Protocol-level |
| Long Press | Hold touch sensor (~500ms) | Protocol-level |

## How It Works

The script connects to your G2 glasses via BLE and listens for notification packets on the control characteristic (`0x5402`). Gesture events are embedded within status packets and identified by specific byte patterns:

- **Tap**: Service `0x0101`, pattern `320b...08011202`
- **Swipe Forward**: Service `0x0101`, pattern `320d...12040801`
- **Swipe Backward**: Service `0x0101`, pattern `320d...12040802`
- **Long Press**: Service `0x0D01`, pattern `1a0408011003`

## Double-Tap Detection

Single and double taps are identical at the protocol level. This script implements software-based double-tap detection using a 300ms threshold:

1. On first tap, start a timer
2. If second tap arrives within 300ms → double tap
3. Otherwise → single tap

## Example Output

```
Even G2 Gesture Handler
========================================

Scanning for G2 glasses...
  Found: Even G2_L_XXXX

Connected!

Listening for gestures...
  - Tap: Touch sensor briefly
  - Double Tap: Tap twice quickly
  - Swipe Forward: Swipe towards temple
  - Swipe Backward: Swipe towards nose
  - Long Press: Hold touch sensor

Press Ctrl+C to exit.

[1] Gesture: tap
    Raw: aa12170f01010101...320b...08011202...
  → Single Tap detected!

[2] Gesture: swipe_forward
    Raw: aa12170f01010101...320d...12040801...
  → Swipe Forward detected!

[3] Gesture: tap
    Raw: aa12170f01010101...320b...08011202...
[4] Gesture: tap
    Raw: aa12170f01010101...320b...08011202...
  → Double Tap detected!
```

## API Usage

You can also use the gesture detection functions in your own code:

```python
from gesture_handler import detect_gesture, G2Gesture, DoubleTapDetector

# Detect gesture from raw packet
gesture = detect_gesture(packet_data)
if gesture == G2Gesture.TAP:
    print("Tap!")
elif gesture == G2Gesture.SWIPE_FORWARD:
    print("Swipe forward!")

# Double-tap detection
detector = DoubleTapDetector(
    on_single_tap=lambda: print("Single tap"),
    on_double_tap=lambda: print("Double tap")
)
await detector.handle_tap()
```

## See Also

- [Gesture Callbacks Documentation](../../docs/gesture-callbacks.md) - Full protocol details
