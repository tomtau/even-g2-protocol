# Health Data Example

This example demonstrates displaying health data on the Even G2 glasses using
the official `health.proto` definitions.

## Protocol Reference

Based on `proto/g2_re/health.proto`:

```protobuf
enum eHealthDataType {
    UNKNOWN_TYPE = 0;
    ALL = 1;
    STEPS = 2;
    CALORIES = 3;
    SLEEP = 4;
    HEART_RATE = 5;
    BLOOD_OXYGEN = 6;
    TEMPERATURE = 7;
    HRV = 8;
    PRODUCTIVITY = 9;
}

message HealthDataPackage {
    eHealthCommandId commandId = 1;
    int32 magicRandom = 2;
    optional HealthSingleData singleData = 3;
    optional HealthMultData multData = 4;
    optional HealthSingleHighlight singleHighlight = 5;
    optional HealthMultHighlight multHighlight = 6;
}
```

## Usage

```bash
# Install dependencies
pip install bleak

# Run with default example data
python health.py

# Display specific health metrics
python health.py --steps 5000
python health.py --steps 8000 --goal 10000
python health.py --calories 1500
python health.py --heart-rate 72
```

## Service ID

Health uses Service ID 14 (`UI_HEALTH_APP_ID = 0x0E`).

## Example Packet Structure

From captured traffic (health status update):

```
Header: aa 21 20 93 01 01 0e 20
        ^prefix ^len ^pkt ^service

Payload (HealthDataPackage):
  08 02       - commandId = 2 (MULT_DATA)
  10 5e       - magicRandom = 94
  22 8a 01    - multHighlight field (length 138)
    08 01     - enabled = 1
    12 15     - first highlight (21 bytes)
      08 02   - dataType = STEPS
      10 90 4e - goal = 10000
      1d 00 00 00 00 - value (float)
      25 00 00 00 00 - avgValue (float)
      28 00   - duration = 0
      30 00   - errorCode = SUCCESS
      38 00   - extra field
    12 15     - second highlight (21 bytes)
      08 03   - dataType = CALORIES
      ...

CRC: 56 49
```

## Data Types

| Type | Value | Description |
|------|-------|-------------|
| STEPS | 2 | Step count |
| CALORIES | 3 | Calories burned |
| SLEEP | 4 | Sleep duration/quality |
| HEART_RATE | 5 | Heart rate (bpm) |
| BLOOD_OXYGEN | 6 | SpO2 percentage |
| TEMPERATURE | 7 | Body temperature |
| HRV | 8 | Heart Rate Variability |
| PRODUCTIVITY | 9 | Productivity score |

## Integration with Health Apps

To integrate with Apple Health or Google Fit:
1. Query health data from the platform API
2. Format using `HealthSingleData` or `HealthSingleHighlight`
3. Send via BLE to the glasses

Example with Apple HealthKit (Swift):
```swift
let stepCount = healthStore.statisticsCollection(for: stepType)
let packet = buildHealthHighlight(
    dataType: .steps,
    text: "\(Int(stepCount)) steps"
)
bleManager.write(packet, to: g2Characteristic)
```
