# Navigation Example

Send turn-by-turn navigation updates to Even G2 glasses.

## Setup

```bash
pip install bleak
```

## Usage

```bash
# Single navigation update
python navigation.py "86 m" "Turn left" "7 min" "701 m" "ETA: 13:07"

# Run demo sequence
python navigation.py --demo
```

## Arguments

| Position | Field | Example |
|----------|-------|---------|
| 1 | Distance to maneuver | "86 m" |
| 2 | Instruction | "Turn left" |
| 3 | Time remaining | "7 min" |
| 4 | Total distance | "701 m" |
| 5 | ETA | "ETA: 13:07" |

## Demo Mode

The `--demo` flag runs a simulated navigation sequence that shows:
- Turn left onto Main St
- Continue straight
- Turn right onto Oak Ave
- Arrive at destination

Each step updates every 2 seconds with decreasing distances.

## Maneuver Icons

The script supports the following maneuver types:

| Icon | Value | Usage |
|------|-------|-------|
| Turn Left | 1 | Default for "Turn left" |
| Turn Right | 2 | For "Turn right" |
| Straight | 3 | For "Continue straight" |
| U-Turn | 4 | For "Make a U-turn" |

## Protocol Details

Navigation uses Service `0x0820` with protobuf encoding:

```
Packet: [AA 21] [Seq] [Len] [01 01] [08 20] [Payload] [CRC16]

Payload:
  08 07         - State: Active navigation
  2a XX         - Container: length XX
    08 04       - Distance marker
    12 XX data  - Distance string
    1a XX data  - Instruction string
    22 XX data  - Time remaining
    2a XX data  - Total distance
    32 XX data  - ETA string
    3a XX data  - Speed string
    40 XX       - Icon type
```

## Integration Example

```python
from navigation import build_navigation_packet, ManeuverIcon

# Build packet for turn instruction
packet = build_navigation_packet(
    distance="100 m",
    instruction="Turn right onto Oak Ave",
    time_remaining="5 min",
    total_distance="1.2 km",
    eta="ETA: 15:30",
    speed="25 km/h",
    icon_type=ManeuverIcon.TURN_RIGHT,
    sequence=0x10
)

# Send via your BLE connection
await client.write_gatt_char(CHAR_WRITE, packet, response=False)
```

## See Also

- [Navigation Protocol Documentation](../../docs/navigation.md) - Full protocol details
