# Even G2 Service IDs

## Service ID Format

Service IDs are 2 bytes in the packet header (bytes 6-7):

```
AA 21 01 0C 01 01 [hi] [lo] ...
                   ↑    ↑
              Service ID
```

## Official Service IDs

From `proto/g2_re/service_id_def.proto`, the glasses use an internal service ID enum:

| SID Value | Enum Name | Description |
|-----------|-----------|-------------|
| 0 | UI_DEFAULT_APP_ID | Default/Control |
| 1 | UI_BACKGROUND_DASHBOARD_APP_ID | Dashboard background |
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
| 128 | UX_DEVICE_SETTINGS_APP_ID | Device Settings |
| 129 | UX_GLASSES_CASE_APP_ID | Glasses Case |

See [docs/protobuf.md](protobuf.md) for complete protobuf message definitions.

## BLE Packet Service IDs

The BLE packet service ID maps to the internal SID. The high byte is the SID value,
and the low byte indicates the operation mode:

### Core Services

| Service ID | Name | Description |
|------------|------|-------------|
| `0x80-00` | Auth Control | Session management, sync |
| `0x80-20` | Auth Data | Authentication with payload |
| `0x80-01` | Auth Response | Glasses auth acknowledgment |

### Feature Services

| Service ID | SID | Name | Description |
|------------|-----|------|-------------|
| `0x01-01` | - | Status | Gesture/status events (tap, swipe) |
| `0x01-20` | - | Notifications | Calendar/email/app notifications |
| `0x04-20` | 4 | Notification | Foreground notification |
| `0x05-20` | 5 | Translation | Real-time speech translation |
| `0x06-20` | 6 | Teleprompter | Text display, scripts |
| `0x07-20` | 7 | Even AI | AI assistant |
| `0x08-20` | 8 | Navigation | Turn-by-turn navigation |
| `0x09-00` | 9 | Settings | Device info/settings |
| `0x0A-20` | 10 | Transcribe | Speech transcription |
| `0x0B-20` | 11 | Conversate | Meeting transcription |
| `0x0C-20` | 12 | Quick List | Todo list items |
| `0x0D-00` | 13 | Sync Info | Sync information |
| `0x0D-01` | - | Control | Long press/acknowledgment |
| `0x0E-20` | 14 | Health | Health data display |
| `0x0F-20` | 15 | Logger | Debug logging |
| `0x10-20` | 16 | Onboarding | Setup/onboarding |
| `0x20-20` | 32 | Module Config | Module configuration |
| `0x81-20` | - | Display Trigger | Wake/activate display |

### File Services (0x74xx characteristics)

| Service ID | Name | Description |
|------------|------|-------------|
| `0xC4-00` | File Command | File check, start, end commands |
| `0xC5-00` | File Data | Raw file/JSON data transfer |

### Service ID Breakdown

The service ID appears to encode:
- **High byte**: Service category/type
- **Low byte**: Sub-service or mode
  - `0x00` = Control/query
  - `0x01` = Response
  - `0x20` = Data/payload

## Service Details

### 0x80-00 / 0x80-20 (Authentication)

Used for session establishment:

```
Type 0x04: Capability query
Type 0x05: Capability response
Type 0x80: Time sync with transaction ID
```

### 0x06-20 (Teleprompter)

Text display service with multiple message types:

| Type | Purpose |
|------|---------|
| `0x01` | Init/select script |
| `0x02` | Script list |
| `0x03` | Content page |
| `0x04` | Content complete |
| `0xFF` | Mid-stream marker |

### 0x0E-20 (Display Config)

Display configuration sent before content:

```
08-02         Type = 2
10-XX         msg_id
22-6A         Field 4, length 106
  [config]    Display parameters
```

### 0x07-20 (Dashboard)

Widget display (calendar, weather, etc.):

```
08-XX         Widget type
10-XX         msg_id
1A-XX         Widget data
```

### 0xC4-00 (File Command)

File transfer control on 0x74xx characteristics:

| Payload | Command | Description |
|---------|---------|-------------|
| 93-byte header | FILE_CHECK | Announce file with CRC32C checksum |
| `0x01` | START | Begin data transfer |
| `0x02` | END | Complete transfer |

FILE_CHECK header structure:
```
[4] mode      - 0x00010000 (little-endian)
[4] size      - len(data) * 256
[4] checksum  - (CRC32C << 8) & 0xFFFFFFFF
[1] extra     - (CRC32C >> 24) & 0xFF
[80] filename - Null-padded string
```

### 0xC5-00 (File Data)

Raw file content transfer:

```
[json_bytes]  UTF-8 JSON payload
```

Used for notifications (JSON) and potentially other file types.

## Service Discovery

Services can be enumerated by observing traffic patterns:

1. **Auth services** (0x80-xx): Always first in session
2. **Config services** (0x0D-xx, 0x0E-xx): After auth
3. **Feature services**: On-demand based on user action

## Adding New Services

When you discover a new service ID:

1. Note the packet context (what triggered it)
2. Capture the full packet sequence
3. Identify the payload structure
4. Document the message types within the service
