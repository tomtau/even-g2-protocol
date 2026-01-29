import Foundation

// MARK: - BLE UUIDs for Even G2

public struct G2UUIDs {
    private static let uuidBase = "00002760-08c2-11e1-9073-0e8ac72e"
    
    public static let charWrite = UUID(uuidString: "\(uuidBase)5401")!
    public static let charNotify = UUID(uuidString: "\(uuidBase)5402")!
    public static let charNotifWrite = UUID(uuidString: "\(uuidBase)7401")!
    public static let charNotifNotify = UUID(uuidString: "\(uuidBase)7402")!
}

// MARK: - CRC32C (Castagnoli) Lookup Table

/// Polynomial: 0x1EDC6F41, Init: 0, Non-reflected
public let crc32cTable: [UInt32] = [
    0, 0x1edc6f41, 0x3db8de82, 0x2364b1c3, 2071051524, 1705890373, 1187603334, 1477774535,
    4142103048, 3896448329, 3411780746, 3582446539, 2375206668, 2471405645, 2955549070, 2935387855,
    4078607185, 3989238800, 3466741203, 3497929362, 2288723541, 2528594196, 3050567895, 2869925782,
    0x5f9e159, 0x1b258e18, 0x38413fdb, 0x269d509a, 2122865757, 1616130844, 1127252703, 1575808414,
    4176042467, 3862247074, 3310454625, 3683510304, 2207835367, 2638515110, 3189783141, 2700891428,
    0xe0a23eb, 0x10d64caa, 0x33b2fd69, 0x2d6e9228, 1971035887, 1806168494, 1220755565, 1444884268,
    0xbf3c2b2, 0x152fadf3, 0x364b1c30, 0x28977371, 1887600566, 1851658487, 1295687988, 1407635061,
    4245731514, 3821852667, 3232261688, 3732146553, 2254505406, 2562550527, 3151616828, 2768614525,
    4010728583, 4057117638, 3535143429, 3429526852, 2491376003, 2325941954, 2848440065, 3072053312,
    0x19eda68f, 0x731c9ce, 0x2455780d, 0x3a89174c, 1654397835, 2084598986, 1596245257, 1106815560,
    0x1c1447d6, 0x2c82897, 0x21ac9954, 0x3f70f615, 1734736594, 2042205587, 1524442192, 1140935441,
    3942071774, 4096479903, 3612336988, 3381890077, 2441511130, 2405101467, 2889768536, 3001168153,
    0x17e78564, 0x93bea25, 0x2a5f5be6, 0x348334a7, 1821784160, 1917474593, 1362028258, 1341295011,
    3775201132, 4292382765, 3703316974, 3261091503, 2591375976, 2225679657, 2815270122, 3104961451,
    3841793589, 4196495732, 3645227191, 3348738038, 2676794161, 2169556080, 2721349043, 3169325810,
    0x121e643d, 0xcc20b7c, 0x2fa6babf, 0x317ad5fe, 1768937785, 2008266360, 1423378363, 1242261754,
    3233928783, 3726489870, 4252567757, 3819267980, 3148901195, 2775319562, 2248717769, 2564086408,
    0x3622ac47, 0x28fec306, 0xb9a72c5, 0x15461d84, 1297289539, 1401912834, 1894502337, 1849139328,
    0x33db4d1e, 0x2d07225f, 0xe63939c, 0x10bffcdd, 1219162138, 1450614619, 1964125848, 1808679385,
    3308795670, 3689175127, 4169197972, 3864823509, 3192490514, 2694178131, 2213631120, 2636987345,
    0x38288fac, 0x26f4e0ed, 0x590512e, 0x1b4c3e6f, 1129919144, 1569021417, 2128735274, 1614644075,
    3469473188, 3491207909, 4084411174, 3987686503, 3048884384, 2875598817, 2281870882, 2531195235,
    3409057021, 3589176252, 4136290943, 3897992510, 2957224441, 2929706680, 2382067579, 2468812858,
    0x3dd16ef5, 0x230d01b4, 0x69b077, 0x1eb5df36, 1184945137, 1484569776, 2065173875, 1707369010,
    0x2fcf0ac8, 0x31136589, 0x1277d44a, 0xcabbb0b, 1421785036, 1247991949, 1762027854, 2010777103,
    3643568320, 3354402689, 3834949186, 4199072003, 2724056516, 3162612357, 2682590022, 2168028167,
    3704983961, 3255434968, 3782037275, 4289798234, 2812554397, 3111666652, 2585588255, 2227215710,
    0x2a36eb91, 0x34ea84d0, 0x178e3513, 0x9525a52, 1363629717, 1335572948, 1828685847, 1914955606,
    3609613099, 3388619882, 3936259497, 4098024168, 2891443759, 2995487086, 2448371885, 2402508780,
    0x21c52923, 0x3f194662, 0x1c7df7a1, 0x2a198e0, 1521783847, 1147730790, 1728858789, 2043684324,
    0x243cc87a, 0x3ae0a73b, 0x198416f8, 0x75879b9, 1598911870, 1100028479, 1660267516, 2083112125,
    3537875570, 3422805299, 4016532720, 4055565233, 2846756726, 3077726263, 2484523508, 2328542901,
]

// MARK: - CRC Functions

/// Calculate CRC32C (Castagnoli) checksum.
public func calcCRC32C(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0
    for b in data {
        let idx = Int(b ^ UInt8((crc >> 24) & 0xFF))
        crc = ((crc << 8) & 0xFFFFFFFF) ^ crc32cTable[idx]
    }
    return crc
}

/// Calculate file check header fields.
/// Returns (size, checksum, extra) where:
/// - size = len(data) * 256
/// - checksum = CRC32C << 8
/// - extra = CRC32C >> 24
public func calcFileCheckFields(_ data: Data) -> (size: UInt32, checksum: UInt32, extra: UInt8) {
    let crc = calcCRC32C(data)
    return (
        UInt32(data.count) * 256,
        (crc << 8) & 0xFFFFFFFF,
        UInt8((crc >> 24) & 0xFF)
    )
}

/// CRC-16/CCITT for packet framing.
public func crc16CCITT(_ data: Data) -> UInt16 {
    var crc: UInt16 = 0xFFFF
    for byte in data {
        crc ^= UInt16(byte) << 8
        for _ in 0..<8 {
            if crc & 0x8000 != 0 {
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF
            } else {
                crc = (crc << 1) & 0xFFFF
            }
        }
    }
    return crc
}

// MARK: - Encoding Helpers

/// Encode integer as protobuf varint.
public func encodeVarint(_ value: UInt64) -> Data {
    var val = value
    var result = Data()
    while val > 0x7F {
        result.append(UInt8((val & 0x7F) | 0x80))
        val >>= 7
    }
    result.append(UInt8(val & 0x7F))
    return result
}

/// Build a G2 protocol packet with header and CRC.
public func buildPacket(
    seq: UInt8,
    svcHi: UInt8,
    svcLo: UInt8,
    payload: Data,
    totalPkts: UInt8 = 1,
    pktNum: UInt8 = 1
) -> Data {
    var packet = Data([0xAA, 0x21, seq, UInt8(payload.count + 2), totalPkts, pktNum, svcHi, svcLo])
    packet.append(payload)
    let crc = crc16CCITT(payload)
    packet.append(UInt8(crc & 0xFF))
    packet.append(UInt8((crc >> 8) & 0xFF))
    return packet
}

/// Add CRC to packet (calculated over payload, stored little-endian)
/// Used for auth packets that are constructed directly without using buildPacket
public func addCRC(_ packet: inout Data) {
    let payload = packet.suffix(from: 8) // Skip 8-byte header
    let crc = crc16CCITT(Data(payload))
    packet.append(UInt8(crc & 0xFF))
    packet.append(UInt8((crc >> 8) & 0xFF))
}

// MARK: - Authentication

/// Build the 7-packet authentication sequence.
public func buildAuthPackets() -> [Data] {
    let timestamp = UInt64(Date().timeIntervalSince1970)
    let tsVarint = encodeVarint(timestamp)
    let txid = Data([0xE8, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01])
    
    var packets: [Data] = []
    
    // Auth 1: Capability query
    var p1 = Data([
        0xAA, 0x21, 0x01, 0x0C, 0x01, 0x01, 0x80, 0x00,
        0x08, 0x04, 0x10, 0x0C, 0x1A, 0x04, 0x08, 0x01, 0x10, 0x04
    ])
    addCRC(&p1)
    packets.append(p1)
    
    // Auth 2: Capability response request
    var p2 = Data([
        0xAA, 0x21, 0x02, 0x0A, 0x01, 0x01, 0x80, 0x20,
        0x08, 0x05, 0x10, 0x0E, 0x22, 0x02, 0x08, 0x02
    ])
    addCRC(&p2)
    packets.append(p2)
    
    // Auth 3: Time sync with transaction ID
    var payload3 = Data([0x08, 0x80, 0x01, 0x10, 0x0F, 0x82, 0x08, 0x11, 0x08])
    payload3.append(tsVarint)
    payload3.append(0x10)
    payload3.append(txid)
    var p3 = Data([0xAA, 0x21, 0x03, UInt8(payload3.count + 2), 0x01, 0x01, 0x80, 0x20])
    p3.append(payload3)
    addCRC(&p3)
    packets.append(p3)
    
    // Auth 4-5: Additional capability exchanges
    var p4 = Data([
        0xAA, 0x21, 0x04, 0x0C, 0x01, 0x01, 0x80, 0x00,
        0x08, 0x04, 0x10, 0x10, 0x1A, 0x04, 0x08, 0x01, 0x10, 0x04
    ])
    addCRC(&p4)
    packets.append(p4)
    
    var p5 = Data([
        0xAA, 0x21, 0x05, 0x0C, 0x01, 0x01, 0x80, 0x00,
        0x08, 0x04, 0x10, 0x11, 0x1A, 0x04, 0x08, 0x01, 0x10, 0x04
    ])
    addCRC(&p5)
    packets.append(p5)
    
    // Auth 6: Final capability
    var p6 = Data([
        0xAA, 0x21, 0x06, 0x0A, 0x01, 0x01, 0x80, 0x20,
        0x08, 0x05, 0x10, 0x12, 0x22, 0x02, 0x08, 0x01
    ])
    addCRC(&p6)
    packets.append(p6)
    
    // Auth 7: Final time sync
    var payload7 = Data([0x08, 0x80, 0x01, 0x10, 0x13, 0x82, 0x08, 0x11, 0x08])
    payload7.append(tsVarint)
    payload7.append(0x10)
    payload7.append(txid)
    var p7 = Data([0xAA, 0x21, 0x07, UInt8(payload7.count + 2), 0x01, 0x01, 0x80, 0x20])
    p7.append(payload7)
    addCRC(&p7)
    packets.append(p7)
    
    return packets
}

// MARK: - Gesture Detection

/// Gesture types detected from G2 packets
public enum G2Gesture: String {
    case tap = "tap"
    case swipeForward = "swipe_forward"
    case swipeBackward = "swipe_backward"
    case longPress = "long_press"
}

/// Detect gesture type from G2 packet data
public func detectGesture(from data: Data) -> G2Gesture? {
    let hex = data.map { String(format: "%02x", $0) }.joined()
    
    // Long press (service 0d01)
    if hex.contains("01010d01") && hex.contains("1a0408011003") {
        return .longPress
    }
    
    // Swipe gestures (service 0101, pattern 320d)
    if hex.contains("320d") {
        if hex.contains("12040801") {
            return .swipeForward
        } else if hex.contains("12040802") {
            return .swipeBackward
        }
    }
    
    // Tap gesture (service 0101, pattern 320b)
    if hex.contains("320b") && hex.contains("08011202") {
        return .tap
    }
    
    return nil
}

// MARK: - Navigation

/// Navigation maneuver icon types
public enum ManeuverIcon: UInt8 {
    case turnLeft = 1
    case turnRight = 2
    case straight = 3
    case uTurn = 4
}

/// Navigation data structure
public struct G2Navigation {
    public let distance: String      // "86 m"
    public let instruction: String   // "Turn left"
    public let timeRemaining: String // "7 min"
    public let totalDistance: String // "701 m"
    public let eta: String          // "ETA: 13:07"
    public let speed: String        // "0.0 km/h"
    public let iconType: ManeuverIcon
    
    public init(
        distance: String,
        instruction: String,
        timeRemaining: String,
        totalDistance: String,
        eta: String,
        speed: String = "0.0 km/h",
        iconType: ManeuverIcon = .turnLeft
    ) {
        self.distance = distance
        self.instruction = instruction
        self.timeRemaining = timeRemaining
        self.totalDistance = totalDistance
        self.eta = eta
        self.speed = speed
        self.iconType = iconType
    }

    public func buildPacket(sequence: UInt8) -> Data {
        var navFields = Data()

        // Distance container
        navFields.append(contentsOf: [0x08, 0x04])
        navFields.append(encodeString(tag: 0x12, value: distance))
        navFields.append(encodeString(tag: 0x1a, value: instruction))
        navFields.append(encodeString(tag: 0x22, value: timeRemaining))
        navFields.append(encodeString(tag: 0x2a, value: totalDistance))
        navFields.append(encodeString(tag: 0x32, value: eta))
        navFields.append(encodeString(tag: 0x3a, value: speed))
        navFields.append(contentsOf: [0x40, iconType.rawValue])

        // Wrap in container (validate size)
        precondition(navFields.count <= 255, "Navigation payload too large (\(navFields.count) bytes, max 255)")
        var payload = Data([0x08, 0x07, 0x2a, UInt8(navFields.count)])
        payload.append(navFields)

        // Build packet
        let service = Data([0x08, 0x20])
        let pktInfo = Data([0x01, 0x01])
        let fullPayload = pktInfo + service + payload

        precondition(fullPayload.count + 2 <= 255, "Packet too large (\(fullPayload.count + 2) bytes, max 255)")
        var packet = Data([0xaa, 0x21, sequence, UInt8(fullPayload.count + 2)])
        packet.append(fullPayload)

        // Add CRC
        let crc = crc16CCITT(fullPayload)
        packet.append(contentsOf: [UInt8(crc & 0xFF), UInt8(crc >> 8)])

        return packet
    }

    private func encodeString(tag: UInt8, value: String) -> Data {
        let utf8 = Data(value.utf8)
        precondition(utf8.count <= 255, "String too long (\(utf8.count) bytes, max 255)")
        return Data([tag, UInt8(utf8.count)]) + utf8
    }
}

// MARK: - ANCS Notification Parsing

/// Parsed ANCS-like notification
public struct G2AncsNotification {
    public let notifId: UInt16
    public let notifType: UInt16
    public let bundleId: String
    public let title: String
    public let subtitle: String
    public let body: String
    public let internalId: String
    public let timestamp: String
    public let action1: String
    public let action2: String
}

/// Parse ANCS-like notification from Handle 0x0021 data
public func parseAncsNotification(data: Data) -> G2AncsNotification? {
    guard data.count > 6 else { return nil }

    let notifId = data.subdata(in: 1..<3).withUnsafeBytes {
        $0.load(as: UInt16.self)
    }
    let notifType = data.subdata(in: 3..<5).withUnsafeBytes {
        $0.load(as: UInt16.self)
    }

    var pos = 6

    // Parse bundle ID
    guard pos + 2 <= data.count else { return nil }
    let bundleLen = Int(data[pos]) | (Int(data[pos+1]) << 8)
    pos += 2
    guard pos + bundleLen <= data.count else { return nil }
    let bundleId = String(data: data.subdata(in: pos..<pos+bundleLen), encoding: .utf8) ?? ""
    pos += bundleLen

    // Helper to parse field
    func parseField(expectedId: UInt8) -> String {
        guard pos < data.count, data[pos] == expectedId else { return "" }
        pos += 1
        guard pos + 2 <= data.count else { return "" }
        let len = Int(data[pos]) | (Int(data[pos+1]) << 8)
        pos += 2
        guard pos + len <= data.count else { return "" }
        let value = String(data: data.subdata(in: pos..<pos+len), encoding: .utf8) ?? ""
        pos += len
        return value
    }

    return G2AncsNotification(
        notifId: notifId,
        notifType: notifType,
        bundleId: bundleId,
        title: parseField(expectedId: 0x01),
        subtitle: parseField(expectedId: 0x02),
        body: parseField(expectedId: 0x03),
        internalId: parseField(expectedId: 0x04),
        timestamp: parseField(expectedId: 0x05),
        action1: parseField(expectedId: 0x06),
        action2: parseField(expectedId: 0x07)
    )
}

// MARK: - Translation Protocol

/// Supported language codes for translation
public let G2Languages: [String: String] = [
    "EN": "English",
    "CS": "Czech",
    "HK": "Cantonese (Hong Kong)",
    "ZH": "Mandarin Chinese",
    "JA": "Japanese",
    "KO": "Korean",
    "ES": "Spanish",
    "FR": "French",
    "DE": "German",
    "IT": "Italian",
    "PT": "Portuguese",
    "RU": "Russian",
    "AR": "Arabic",
]

/// Translation result from G2 glasses
public struct G2TranslationResult {
    public let original: String
    public let translation: String
    public let isFinal: Bool
    
    public init(original: String, translation: String, isFinal: Bool) {
        self.original = original
        self.translation = translation
        self.isFinal = isFinal
    }
}

/// Build translation enable packet.
///
/// Enables translation mode on the G2 glasses with specified source and target languages.
///
/// - Parameters:
///   - seq: Sequence number for the packet
///   - msgId: Message ID for the protocol
///   - source: Source language code (e.g., "CS", "HK", "ZH")
///   - target: Target language code (e.g., "EN")
/// - Returns: BLE packet data to send to the glasses
public func buildTranslationEnable(seq: UInt8, msgId: UInt8, source: String, target: String) -> Data {
    let langPair = "\(source)>\(target)"
    let langBytes = Data(langPair.utf8)
    
    // Mode data: 08 01 12 len lang 18 01
    var modeData = Data([0x08, 0x01, 0x12, UInt8(langBytes.count)])
    modeData.append(langBytes)
    modeData.append(contentsOf: [0x18, 0x01])
    
    // Payload: 08 01 10 msg_id 1A len mode_data
    var payload = Data([0x08, 0x01, 0x10, msgId, 0x1A, UInt8(modeData.count)])
    payload.append(modeData)
    
    return buildPacket(seq: seq, svcHi: 0x05, svcLo: 0x20, payload: payload)
}

/// Build translation disable packet.
///
/// Disables translation mode on the G2 glasses.
///
/// - Parameters:
///   - seq: Sequence number for the packet
///   - msgId: Message ID for the protocol
/// - Returns: BLE packet data to send to the glasses
public func buildTranslationDisable(seq: UInt8, msgId: UInt8) -> Data {
    let modeData = Data([0x08, 0x02])
    var payload = Data([0x08, 0x01, 0x10, msgId, 0x1A, UInt8(modeData.count)])
    payload.append(modeData)
    
    return buildPacket(seq: seq, svcHi: 0x05, svcLo: 0x20, payload: payload)
}

/// Build translation result packet to send custom text TO the glasses for display.
///
/// This allows sending custom translation results to display on the glasses,
/// enabling use of third-party speech recognition and translation services.
///
/// - Parameters:
///   - seq: Sequence number for the packet
///   - msgId: Message ID for the protocol
///   - original: Original text (source language)
///   - translation: Translated text (target language)
///   - isFinal: Whether this is the final result (vs. interim/partial)
///   - speaker: Speaker label (e.g., "Speaker 1")
/// - Returns: BLE packet data to send to the glasses
///
/// - Note: Text lengths are limited to 255 bytes when UTF-8 encoded. Longer texts will be truncated.
public func buildTranslationResult(
    seq: UInt8,
    msgId: UInt8,
    original: String,
    translation: String,
    isFinal: Bool = false,
    speaker: String = "Speaker 1"
) -> Data {
    // Truncate to max 255 bytes
    let originalBytes = Data(Array(original.utf8).prefix(255))
    let translationBytes = Data(Array(translation.utf8).prefix(255))
    
    // Build speaker info in UTF-16 BE with BOM (truncate if needed)
    var speakerUtf16 = Data([0xFE, 0xFF])
    for scalar in speaker.unicodeScalars {
        if speakerUtf16.count >= 253 { break } // Leave room for 2 more bytes
        let value = UInt16(scalar.value)
        speakerUtf16.append(UInt8(value >> 8))
        speakerUtf16.append(UInt8(value & 0xFF))
    }
    
    // Build content field - ALL nested fields go inside content (tag 0x22):
    //   0A len original    - Field 1: original text
    //   12 len translation - Field 2: translated text
    //   18 00              - Field 3: unknown
    //   20 XX              - Field 4: final flag
    //   2A len speaker     - Field 5: speaker info
    var content = Data([0x0A, UInt8(originalBytes.count)])
    content.append(originalBytes)
    content.append(0x12)
    content.append(UInt8(translationBytes.count))
    content.append(translationBytes)
    content.append(contentsOf: [0x18, 0x00]) // Unknown field (inside content)
    content.append(0x20)
    content.append(isFinal ? 0x01 : 0x00)
    content.append(0x2A)
    content.append(UInt8(speakerUtf16.count))
    content.append(speakerUtf16)
    
    // Build payload: 08 02 10 msg_id 22 len content
    var payload = Data([0x08, 0x02, 0x10, msgId])
    payload.append(0x22)
    payload.append(UInt8(content.count))
    payload.append(content)
    
    return buildPacket(seq: seq, svcHi: 0x05, svcLo: 0x20, payload: payload)
}

/// Parse translation result from notification data.
///
/// Extracts original and translated text from G2 translation notification packets.
///
/// - Parameter data: Raw BLE notification data from the glasses
/// - Returns: Parsed translation result, or nil if the data is not a translation packet
public func parseTranslationResult(data: Data) -> G2TranslationResult? {
    // Find service 05 20 in data
    var serviceIdx: Int?
    for i in 0..<(data.count - 1) {
        if data[i] == 0x05 && data[i + 1] == 0x20 {
            serviceIdx = i + 2
            break
        }
    }
    
    guard let payloadStart = serviceIdx, payloadStart + 4 <= data.count else {
        return nil
    }
    
    let payload = data.subdata(in: payloadStart..<(data.count - 2))
    
    guard payload.count >= 4, payload[0] == 0x08, payload[1] == 0x02 else {
        return nil
    }
    
    var original = ""
    var translation = ""
    var isFinal = false
    var idx = 2
    
    while idx < payload.count {
        let tag = payload[idx]
        
        if tag == 0x10 {
            // Skip msg_id (need at least 2 more bytes)
            guard idx + 2 <= payload.count else { break }
            idx += 2
        } else if tag == 0x22 {
            idx += 1
            guard idx < payload.count else { break }
            let contentLen = Int(payload[idx])
            idx += 1
            guard idx + contentLen <= payload.count else { break }
            let content = payload.subdata(in: idx..<(idx + contentLen))
            idx += contentLen
            
            // Parse content: 0A len original 12 len translation
            var cidx = 0
            if cidx < content.count && content[cidx] == 0x0A {
                cidx += 1
                if cidx < content.count {
                    let origLen = Int(content[cidx])
                    cidx += 1
                    if cidx + origLen <= content.count {
                        original = String(data: content.subdata(in: cidx..<(cidx + origLen)), encoding: .utf8) ?? ""
                        cidx += origLen
                    }
                }
                
                if cidx < content.count && content[cidx] == 0x12 {
                    cidx += 1
                    if cidx < content.count {
                        let transLen = Int(content[cidx])
                        cidx += 1
                        if cidx + transLen <= content.count {
                            translation = String(data: content.subdata(in: cidx..<(cidx + transLen)), encoding: .utf8) ?? ""
                        }
                    }
                }
            }
        } else if tag == 0x18 {
            // Skip unknown field (need at least 2 more bytes)
            guard idx + 2 <= payload.count else { break }
            idx += 2
        } else if tag == 0x20 {
            idx += 1
            if idx < payload.count {
                isFinal = payload[idx] == 0x01
            }
            idx += 1
        } else if tag == 0x2A {
            idx += 1
            if idx < payload.count {
                let spkLen = Int(payload[idx])
                idx += 1 + spkLen
            }
        } else {
            idx += 1
        }
    }
    
    guard !original.isEmpty else { return nil }
    
    return G2TranslationResult(original: original, translation: translation, isFinal: isFinal)
}
