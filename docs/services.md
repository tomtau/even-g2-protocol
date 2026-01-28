# Even G2 Service IDs

## Service ID Format

Service IDs are 2 bytes in the packet header (bytes 6-7):

```
AA 21 01 0C 01 01 [hi] [lo] ...
                   ↑    ↑
              Service ID
```

## Known Services

### Core Services

| Service ID | Name | Description |
|------------|------|-------------|
| `0x80-00` | Auth Control | Session management, sync |
| `0x80-20` | Auth Data | Authentication with payload |
| `0x80-01` | Auth Response | Glasses auth acknowledgment |

### Feature Services

| Service ID | Name | Description |
|------------|------|-------------|
| `0x01-01` | Status | Gesture/status events (tap, swipe) |
| `0x01-20` | Notifications | Calendar/email/app notifications |
| `0x04-20` | Display Wake | Activate display |
| `0x06-20` | Teleprompter | Text display, scripts |
| `0x07-20` | Dashboard | Widget data |
| `0x08-20` | Navigation | Turn-by-turn navigation |
| `0x09-00` | Device Info | Version, firmware |
| `0x0B-20` | Conversate | Speech transcription |
| `0x0C-20` | Tasks | Todo list items |
| `0x0D-00` | Configuration | Device settings |
| `0x0D-01` | Control | Long press/acknowledgment |
| `0x0E-20` | Display Config | Display parameters |
| `0x11-20` | Conversate (alt) | Alternative conversate ID |
| `0x20-20` | Commit | Confirm/commit changes |
| `0x81-20` | Display Trigger | Wake/activate display |

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
