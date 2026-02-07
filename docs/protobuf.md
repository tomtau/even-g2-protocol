# Even G2 Protocol Buffer Definitions

This document describes the official protobuf definitions extracted from the Even app, located in `proto/g2_re/`.

## Overview

The Even G2 glasses use Protocol Buffers (protobuf) for message encoding over BLE. The `proto/g2_re/` directory contains the complete set of `.proto` files reverse-engineered from the app.

## Service ID Definitions

From `service_id_def.proto`:

| Enum Value | Service Name | ID |
|------------|--------------|-----|
| 0 | UI_DEFAULT_APP_ID | Default/Control |
| 1 | UI_BACKGROUND_DASHBOARD_APP_ID | Dashboard |
| 3 | UI_FOREGROUND_MEUN_ID | Menu |
| 4 | UI_FOREGROUND_NOTIFICATION_ID | Notifications |
| 5 | UI_TRANSLATE_APP_ID | Translation |
| 6 | UI_TELEPROMPT_APP_ID | Teleprompter |
| 7 | UI_FOREGROUND_EVEN_AI_ID | Even AI |
| 8 | UI_BACKGROUND_NAVIGATION_ID | Navigation |
| 9 | UI_SETTING_APP_ID | Settings |
| 10 | UI_TRANSCRIBE_APP_ID | Transcription |
| 11 | UI_CONVERSATE_APP_ID | Conversate |
| 12 | UI_QUICKLIST_APP_ID | Quick List |
| 13 | SERVICE_SYNC_INFO_APP_ID | Sync Info |
| 14 | UI_HEALTH_APP_ID | Health |
| 15 | UI_LOGGER_APP_ID | Logger |
| 16 | UI_ONBOARDING_APP_ID | Onboarding |
| 32 | SERVICE_MODULE_CONFIGURE_APP_ID | Module Config |
| 33 | UI_FOREGROUND_SYSTEM_ALERT_APP_ID | System Alerts |
| 128 | UX_DEVICE_SETTINGS_APP_ID | Device Settings |
| 129 | UX_GLASSES_CASE_APP_ID | Glasses Case |
| 144 | UX_RING_ROW_DATA_ID | Ring Raw Data |
| 145 | UX_RING_DATA_RELAY_ID | Ring Data Relay |
| 192 | UX_OTA_TRANSMIT_CMD_ID | OTA Commands |
| 193 | UX_OTA_TRANSMIT_RAW_DATA_ID | OTA Raw Data |
| 194 | UX_OTA_EXPORT_FILE_CMD_ID | Export Commands |
| 195 | UX_OTA_EXPORT_FILE_RAW_DATA_ID | Export Raw Data |
| 196 | UX_EVEN_FILE_SERVICE_CMD_SEND_ID | File Send Cmd |
| 197 | UX_EVEN_FILE_SERVICE_RAW_SEND_DATA_ID | File Send Data |
| 198 | UX_EVEN_FILE_SERVICE_CMD_EXPORT_ID | File Export Cmd |
| 199 | UX_EVEN_FILE_SERVICE_RAW_EXPORT_DATA_ID | File Export Data |
| 255 | INVALID_SERVICE_ID | Invalid |

## Proto Files Reference

### Common Types (`common.proto`)

Error codes used across all services:

```protobuf
enum eErrorCode {
    SUCCESS = 0;
    CRC = 1;
    PKT_LOST = 2;
    TIMEOUT = 3;
    NO_RESOURCES = 4;
    PB_ERROR = 5;
    NULL = 6;
    FAIL = 7;
    NOT_SUPPORT = 8;
    SUPPORT = 9;
    HEAD_ID = 10;
    INVALID_LENGTH = 11;
    INVALID_SDID = 12;
    DUPLICATE_PACKET = 13;
    RING_CONNECT_TIMEOUT = 90;
}
```

### Translation Service (`translate.proto`)

**Commands:**
```protobuf
enum TranslateCmd {
    CMD_NONE = 0;
    OPEN = 1;
    CLOSE = 2;
    PAUSE = 3;
    RESUME = 4;
}
```

**Command IDs:**
```protobuf
enum eTranslateCommandId {
    NONE_COMMAND = 0;
    TRANSLATE_CTRL = 1;      // Control command (open/close)
    TRANSLATE_RESULT = 2;    // Translation result data
    TRANSLATE_NOTIFY = 161;  // Notification from glasses
    COMM_RESP = 162;         // Response from glasses
    TRANSLATE_MODE_SWITCH = 163;
    TRANSLATE_HEARTBEAT = 255;
}
```

**Main Message:**
```protobuf
message TranslateDataPackage {
    eTranslateCommandId commandId = 1;
    int32 magicRandom = 2;  // Random message ID
    optional TranslateControl ctrl = 3;
    optional TranslateResult result = 4;
    optional TranslateNotify notify = 5;
    optional TranslateModeSwitch modeSwitch = 6;
    optional TranslateResp resp = 7;
    optional TranslateHeartBeat heartbeat = 8;
}

message TranslateControl {
    TranslateCmd cmd = 1;      // OPEN=1, CLOSE=2
    bytes languagePair = 2;    // e.g., "HK>EN"
    int32 useAudio = 3;        // 1 = use microphone
    eErrorCode errorCode = 4;
}

message TranslateResult {
    bytes srcText = 1;     // Original text
    bytes dstText = 2;     // Translated text
    eErrorCode errorCode = 3;
    int32 endFlag = 4;     // 1 = final result
    bytes speaker = 5;     // Speaker label (UTF-16LE)
}
```

### Transcription Service (`transcribe.proto`)

Similar to Translation but for single-language transcription:

```protobuf
message TranscribeDataPackage {
    eTranscribeCommandId commandId = 1;
    int32 magicRandom = 2;
    optional TranscribeControl ctrl = 3;
    optional TranscribeResult result = 4;
    optional TranscribeNotify notify = 5;
    optional TranscribeResp resp = 6;
    optional TranscribeHeartBeat heartbeat = 7;
}

message TranscribeResult {
    bytes text = 1;        // Transcribed text
    eErrorCode errorCode = 2;
    int32 endFlag = 3;     // 1 = final result
    bytes speaker = 4;     // Speaker label
}
```

### Even AI Service (`even_ai.proto`)

**Commands:**
```protobuf
enum eEvenAICommandId {
    NONE_COMMAND = 0;
    CTRL = 1;        // Control (wake/enter/exit)
    VAD_INFO = 2;    // Voice Activity Detection
    ASK = 3;         // Question from user
    ANALYSE = 4;     // Analysis request
    REPLY = 5;       // AI response
    SKILL = 6;       // Skill activation
    PROMPT = 7;      // Error prompts
    EVENT = 8;       // Events (scroll, complete)
    HEARTBEAT = 9;
    CONFIG = 10;
    COMM_RSP = 161;
}
```

**Supported Skills:**
```protobuf
enum eEvenAISkill {
    SKILL_NONE = 0;
    BRIGHTNESS = 1;
    TRANSLATE_CTRL = 2;
    NOTIFICATION = 3;
    TELEPROMPT = 4;
    NAVIGATE = 5;
    CONVERSATE = 6;
    QUICKLIST = 7;
    AUTO_BRIGHTNESS = 8;
}
```

**Main Message:**
```protobuf
message EvenAIDataPackage {
    eEvenAICommandId commandId = 1;
    int32 magicRandom = 2;
    optional EvenAIControl ctrl = 3;
    optional EvenAIVADInfo vadInfo = 4;
    optional EvenAIAskInfo askInfo = 5;
    optional EvenAIAnalyseInfo analyseInfo = 6;
    optional EvenAIReplyInfo replyInfo = 7;
    optional EvenAISkillInfo skillInfo = 8;
    optional EvenAIPromptInfo promptInfo = 9;
    optional EvenAIEvent event = 10;
    optional EvenAIHeartbeat heartbeat = 11;
    optional EvenAICommRsp resp = 12;
    optional EvenAIConfig config = 13;
}

message EvenAIReplyInfo {
    int32 cmdCnt = 1;
    int32 streamEnable = 2;
    int32 textMode = 3;
    bytes text = 4;           // AI response text
    eErrorCode errorCode = 5;
}
```

### Health Service (`health.proto`)

**Data Types:**
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
```

**Main Message:**
```protobuf
message HealthDataPackage {
    eHealthCommandId commandId = 1;
    int32 magicRandom = 2;
    optional HealthSingleData singleData = 3;
    optional HealthMultData multData = 4;
    optional HealthSingleHighlight singleHighlight = 5;
    optional HealthMultHighlight multHighlight = 6;
}

message HealthSingleData {
    eHealthDataType dataType = 1;
    int32 goal = 2;
    float value = 3;
    float avgValue = 4;
    int32 duration = 5;
    eErrorCode errorCode = 6;
}
```

### Navigation Service (`navigation.proto`)

**Commands:**
```protobuf
enum Navigation_Cmd_list {
    APP_SEND_HEARTBEAT_CMD = 0;
    OS_NOTIFY_MENU_STARTUP_REQUEST_LOCATION_LIST = 1;
    APP_RESPONSE_LOCATION_LIST = 2;
    APP_RESPONSE_LOCATION_NONE = 3;
    OS_NOTIFY_LOCATION_SELECTED = 4;
    APP_REQUEST_START_UP = 5;
    APP_SEND_ERROR_INFO_MSG = 6;
    APP_SEND_BASIC_INFO = 7;
    APP_SNED_MINI_MAP_FILE = 8;
    APP_SEND_MAX_MAP_FILE = 9;
    APP_REQUEST_RECALCULATING_LOCATION_START = 10;
    APP_REQUEST_NAVIGATION_COMPLETE = 11;
    APP_REQUEST_EXIT = 12;
    OS_NOTIFY_EXIT = 13;
    OS_NOTIFY_REVIEW_CHANGED = 14;
    OS_NOTIFY_COMPASS_CHANGED = 15;
}
```

**Basic Info Message:**
```protobuf
message basic_info_msg {
    int32 directionSignIndex = 1;    // Turn icon type
    optional string distance = 2;     // "86 m"
    optional string roadName = 3;     // "Turn left"
    optional string spendTime = 4;    // "7 min"
    optional string remainDistance = 5; // "701 m"
    optional string etaTime = 6;      // "ETA: 13:07"
    optional string speed = 7;        // "0.0 km/h"
    int32 navigateWorkMethod = 8;
    eErrorCode errorCode = 9;
}
```

### Teleprompter Service (`teleprompt.proto`)

**Commands:**
```protobuf
enum TelepromptCommandId {
    TELEPROMPT_NONE = 0;
    TELEPROMPT_CONTROL = 1;
    TELEPROMPT_FILE_LIST = 2;
    TELEPROMPT_PAGE_DATA = 3;
    TELEPROMPT_PAGE_AI_SYNC = 4;
    TELEPROMPT_STATUS_NOTIFY = 161;
    TELEPROMPT_FILE_LIST_REQUEST = 162;
    TELEPROMPT_FILE_SELECT = 163;
    TELEPROMPT_PAGE_DATA_REQUEST = 164;
    TELEPROMPT_PAGE_SCROLL_SYNC = 165;
    TELEPROMPT_COMM_RESP = 166;
    TELEPROMPT_HEART_BEAT = 255;
}
```

**Settings:**
```protobuf
message TelepromptSetting {
    TelepromptMode mode = 1;     // AI=0, MANUAL=1, AUTO=2
    int32 startPageId = 2;
    int32 startLineId = 3;
    int32 totalPages = 4;
    int32 totalLines = 5;
    int32 displayWidth = 6;
    int32 scrollIntervalMs = 7;
    int32 countdownSeconds = 8;
    int32 useAudio = 9;
}
```

### Dashboard Service (`dashboard.proto`)

Comprehensive dashboard with widgets for news, stocks, calendar, weather, health:

**Widget Types:**
```protobuf
enum WidgetType {
    WIDGET_UNKNOWN = 0;
    WIDGET_NEWS = 1;
    WIDGET_STOCK = 2;
    WIDGET_SCHEDULE = 3;
    WIDGET_QUICKLIST = 4;
    WIDGET_HEALTH = 5;
}

enum WeatherType {
    WEATHER_UNKNOWN = 0;
    WEATHER_SUNNY = 1;
    WEATHER_CLOUDS = 2;
    WEATHER_DRIZZLE = 3;
    // ... more weather types
}
```

### Conversate Service (`conversate.proto`)

Meeting transcription and insights:

```protobuf
enum ConversateCommandId {
    CONVERSATE_NONE = 0;
    CONVERSATE_CONTROL = 1;
    CONVERSATE_TITLE_DATA = 2;
    CONVERSATE_KEYPOINT_DATA = 3;
    CONVERSATE_TAG_DATA = 4;
    CONVERSATE_TRANSCRIBE_DATA = 5;
    CONVERSATE_STATUS_NOTIFY = 161;
    CONVERSATE_COMM_RESP = 162;
    CONVERSATE_HEART_BEAT = 255;
}

message ConversateKeypointData {
    bytes summary = 1;
    repeated bytes keypointText = 2;
}
```

### Quick List Service (`quicklist.proto`)

TODO list management:

```protobuf
message QuicklistItem {
    int32 uid = 1;
    int32 index = 2;
    int32 isCompleted = 3;
    fixed64 timestamp = 4;
    bytes title = 5;
    eErrorCode errorCode = 6;
    eQuicklistTsType tsType = 7;
}
```

## Using the Protos

### Compile the Proto Files

```bash
# Install protobuf compiler
pip install protobuf grpcio-tools

# Compile all protos to Python
cd proto/g2_re
protoc --python_out=../../examples/proto_parser *.proto
```

### Parse a Packet

```python
from translate_pb2 import TranslateDataPackage

# Extract protobuf payload from BLE packet
# (after transport header, before CRC)
payload = bytes.fromhex("0802105e22...")

# Parse the message
msg = TranslateDataPackage()
msg.ParseFromString(payload)

print(f"Command: {msg.commandId}")
if msg.result:
    print(f"Original: {msg.result.srcText.decode('utf-8')}")
    print(f"Translation: {msg.result.dstText.decode('utf-8')}")
```

### Build a Packet

```python
from translate_pb2 import TranslateDataPackage, TranslateResult

msg = TranslateDataPackage()
msg.commandId = 2  # TRANSLATE_RESULT
msg.magicRandom = 0x62

result = msg.result
result.srcText = "Bonjour".encode('utf-8')
result.dstText = "Hello".encode('utf-8')
result.endFlag = 1
result.speaker = "Speaker 1".encode('utf-16le')

# Serialize to bytes
payload = msg.SerializeToString()
```

## Example: Parsing the Health Packet

From the captured session:

```
Service: UI_HEALTH_APP_ID (14)
Payload: 08 02 10 5e 22 8a 01 08 01 12 15 08 02 10 90 4e...
```

Decoded with `health.proto`:

```python
from health_pb2 import HealthDataPackage

payload = bytes.fromhex("0802105e228a01...")
msg = HealthDataPackage()
msg.ParseFromString(payload)

# commandId = 2 (MULT_DATA)
# magicRandom = 94 (0x5e)
# multHighlight contains multiple HealthSingleHighlight messages
for highlight in msg.multHighlight.Highlight:
    print(f"Type: {highlight.dataType}, Value: {highlight.text}")
```

This would show health data like:
- Steps: 10000
- Calories: 2000
- Heart Rate: etc.

## Contributing

When adding new protocol features:

1. Reference the official `.proto` files in `proto/g2_re/`
2. Use the correct `commandId` and field numbers
3. Test with real device captures when possible
