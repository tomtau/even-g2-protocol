//! Even G2 Push Notification - Send Custom Notifications
//!
//! Sends push notifications with custom text to Even G2 glasses.
//!
//! # Usage
//!
//! ```bash
//! cargo run --bin notification -- "Title" "Subtitle" "Message"
//! cargo run --bin notification -- "Sender" "Hello there!"
//! ```
//!
//! # Requirements
//!
//! - Bluetooth adapter with BLE support
//! - Even G2 glasses in pairing mode

use btleplug::api::{Central, Manager as _, Peripheral as _, ScanFilter, WriteType};
use btleplug::platform::{Adapter, Manager, Peripheral};
use chrono::Local;
use serde::Serialize;
use std::env;
use std::time::Duration;
use tokio::time::sleep;
use uuid::Uuid;

// BLE UUIDs for Even G2
const UUID_BASE: &str = "00002760-08c2-11e1-9073-0e8ac72e";
fn char_write() -> Uuid {
    Uuid::parse_str(&format!("{}{:04x}", UUID_BASE, 0x5401)).unwrap()
}
fn char_notify() -> Uuid {
    Uuid::parse_str(&format!("{}{:04x}", UUID_BASE, 0x5402)).unwrap()
}
fn char_notif_write() -> Uuid {
    Uuid::parse_str(&format!("{}{:04x}", UUID_BASE, 0x7401)).unwrap()
}
fn char_notif_notify() -> Uuid {
    Uuid::parse_str(&format!("{}{:04x}", UUID_BASE, 0x7402)).unwrap()
}

/// CRC32C (Castagnoli) lookup table
/// Polynomial: 0x1EDC6F41, Init: 0, Non-reflected
const CRC32C_TABLE: [u32; 256] = [
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
];

/// Calculate CRC32C (Castagnoli) checksum.
fn calc_crc32c(data: &[u8]) -> u32 {
    let mut crc: u32 = 0;
    for &b in data {
        let idx = (b ^ ((crc >> 24) as u8)) as usize;
        crc = ((crc << 8) & 0xFFFFFFFF) ^ CRC32C_TABLE[idx];
    }
    crc
}

/// Calculate file check header fields.
/// Returns (size, checksum, extra) where:
/// - size = len(data) * 256
/// - checksum = CRC32C << 8
/// - extra = CRC32C >> 24
fn calc_file_check_fields(data: &[u8]) -> (u32, u32, u8) {
    let crc = calc_crc32c(data);
    (
        (data.len() as u32) * 256,
        (crc << 8) & 0xFFFFFFFF,
        ((crc >> 24) & 0xFF) as u8,
    )
}

/// CRC-16/CCITT for packet framing.
fn crc16_ccitt(data: &[u8]) -> u16 {
    let mut crc: u16 = 0xFFFF;
    for &byte in data {
        crc ^= (byte as u16) << 8;
        for _ in 0..8 {
            if crc & 0x8000 != 0 {
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
            } else {
                crc = (crc << 1) & 0xFFFF;
            }
        }
    }
    crc
}

/// Encode integer as protobuf varint.
fn encode_varint(mut value: u64) -> Vec<u8> {
    let mut result = Vec::new();
    while value > 0x7F {
        result.push(((value & 0x7F) | 0x80) as u8);
        value >>= 7;
    }
    result.push((value & 0x7F) as u8);
    result
}

/// Build a G2 protocol packet with header and CRC.
fn build_packet(
    seq: u8,
    svc_hi: u8,
    svc_lo: u8,
    payload: &[u8],
    total_pkts: u8,
    pkt_num: u8,
) -> Vec<u8> {
    let mut packet = vec![
        0xAA,
        0x21,
        seq,
        (payload.len() + 2) as u8,
        total_pkts,
        pkt_num,
        svc_hi,
        svc_lo,
    ];
    packet.extend_from_slice(payload);
    let crc = crc16_ccitt(payload);
    packet.push((crc & 0xFF) as u8);
    packet.push(((crc >> 8) & 0xFF) as u8);
    packet
}

/// Send authentication sequence to a G2 eye.
async fn authenticate(peripheral: &Peripheral, name: &str) -> Result<(), Box<dyn std::error::Error>> {
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)?
        .as_secs();
    let ts_var = encode_varint(ts);
    let mut txid = vec![0xE8];
    txid.extend_from_slice(&[0xFF; 8]);
    txid.push(0x01);

    let auth_pkts = vec![
        build_packet(
            1,
            0x80,
            0x00,
            &[0x08, 0x04, 0x10, 0x0D, 0x1A, 0x04, 0x08, 0x01, 0x10, 0x04],
            1,
            1,
        ),
        build_packet(
            2,
            0x80,
            0x20,
            &[0x08, 0x05, 0x10, 0x0E, 0x22, 0x02, 0x08, 0x02],
            1,
            1,
        ),
        {
            let mut payload = vec![0x08, 0x80, 0x01, 0x10, 0x0F, 0x82, 0x08, 0x11, 0x08];
            payload.extend_from_slice(&ts_var);
            payload.push(0x10);
            payload.extend_from_slice(&txid);
            build_packet(3, 0x80, 0x20, &payload, 1, 1)
        },
    ];

    let chars = peripheral.characteristics();
    let write_char = chars
        .iter()
        .find(|c| c.uuid == char_write())
        .ok_or("Write characteristic not found")?;

    for p in auth_pkts {
        peripheral
            .write(write_char, &p, WriteType::WithoutResponse)
            .await?;
        sleep(Duration::from_millis(100)).await;
    }
    println!("  {}: Authenticated", name);
    Ok(())
}

#[derive(Serialize)]
struct AndroidNotification {
    msg_id: u32,
    action: u32,
    app_identifier: String,
    title: String,
    subtitle: String,
    message: String,
    time_s: u64,
    date: String,
    display_name: String,
}

#[derive(Serialize)]
struct NotificationPayload {
    android_notification: AndroidNotification,
}

/// Build notification JSON payload.
fn build_notification_json(
    title: &str,
    subtitle: &str,
    message: &str,
    app_id: &str,
    display_name: &str,
) -> Vec<u8> {
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();

    let notif = NotificationPayload {
        android_notification: AndroidNotification {
            msg_id: 10000 + ((ts % 10000) as u32),
            action: 0,
            app_identifier: app_id.to_string(),
            title: title.to_string(),
            subtitle: subtitle.to_string(),
            message: message.to_string(),
            time_s: ts,
            date: Local::now().format("%Y%m%dT%H%M%S").to_string(),
            display_name: display_name.to_string(),
        },
    };
    serde_json::to_vec(&notif).unwrap()
}

/// Send a push notification to G2 glasses.
async fn send_notification(
    right_peripheral: &Peripheral,
    left_peripheral: &Peripheral,
    title: &str,
    subtitle: &str,
    message: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let json_bytes = build_notification_json(title, subtitle, message, "com.google.android.gm", "Gmail");
    let (size, checksum, extra) = calc_file_check_fields(&json_bytes);

    println!("\nSending: {} / {}", title, subtitle);
    println!("  {} bytes, checksum: 0x{:08X}", json_bytes.len(), checksum);

    let filename = b"user/notify_whitelist.json";

    // FILE_CHECK payload
    let mut fc_payload = Vec::new();
    fc_payload.extend_from_slice(&0x100u32.to_le_bytes());
    fc_payload.extend_from_slice(&size.to_le_bytes());
    fc_payload.extend_from_slice(&checksum.to_le_bytes());
    fc_payload.push(extra);
    fc_payload.extend_from_slice(filename);
    fc_payload.extend_from_slice(&vec![0u8; 80 - filename.len()]);

    let right_chars = right_peripheral.characteristics();
    let notif_write = right_chars
        .iter()
        .find(|c| c.uuid == char_notif_write())
        .ok_or("Notification write characteristic not found")?;

    // FILE_CHECK
    right_peripheral
        .write(
            notif_write,
            &build_packet(0x10, 0xC4, 0x00, &fc_payload, 1, 1),
            WriteType::WithoutResponse,
        )
        .await?;
    sleep(Duration::from_millis(300)).await;

    // START
    right_peripheral
        .write(
            notif_write,
            &build_packet(0x49, 0xC4, 0x00, &[0x01], 1, 1),
            WriteType::WithoutResponse,
        )
        .await?;
    sleep(Duration::from_millis(100)).await;

    // DATA chunks
    let chunks: Vec<&[u8]> = json_bytes.chunks(234).collect();
    for (i, chunk) in chunks.iter().enumerate() {
        let pkt = build_packet(
            0x49,
            0xC5,
            0x00,
            chunk,
            chunks.len() as u8,
            (i + 1) as u8,
        );
        right_peripheral
            .write(notif_write, &pkt, WriteType::WithoutResponse)
            .await?;
        sleep(Duration::from_millis(50)).await;
    }
    sleep(Duration::from_millis(300)).await;

    // END
    right_peripheral
        .write(
            notif_write,
            &build_packet(0xDA, 0xC4, 0x00, &[0x02], 1, 1),
            WriteType::WithoutResponse,
        )
        .await?;

    // Heartbeat to left eye
    sleep(Duration::from_millis(200)).await;
    let left_chars = left_peripheral.characteristics();
    let left_write = left_chars
        .iter()
        .find(|c| c.uuid == char_write())
        .ok_or("Left write characteristic not found")?;

    let heartbeat = hex::decode("aa210e0601018020080e106b6a00e174").unwrap();
    left_peripheral
        .write(left_write, &heartbeat, WriteType::WithoutResponse)
        .await?;

    Ok(())
}

async fn find_adapter() -> Result<Adapter, Box<dyn std::error::Error>> {
    let manager = Manager::new().await?;
    let adapters = manager.adapters().await?;
    adapters.into_iter().next().ok_or("No Bluetooth adapter found".into())
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().collect();

    let (title, subtitle, message) = match args.len() {
        1 => ("Rust".to_string(), "Test Notification".to_string(), "Hello from Rust!".to_string()),
        2 => ("Message".to_string(), args[1].clone(), String::new()),
        3 => (args[1].clone(), args[2].clone(), String::new()),
        _ => (args[1].clone(), args[2].clone(), args[3].clone()),
    };

    println!("Even G2 Custom Notification");
    println!("{}", "=".repeat(40));

    println!("\nScanning for G2 glasses...");
    let adapter = find_adapter().await?;
    adapter.start_scan(ScanFilter::default()).await?;
    sleep(Duration::from_secs(10)).await;

    let peripherals = adapter.peripherals().await?;
    let mut left_dev: Option<Peripheral> = None;
    let mut right_dev: Option<Peripheral> = None;

    for p in peripherals {
        if let Some(props) = p.properties().await? {
            if let Some(name) = props.local_name {
                if name.contains("G2") && name.contains("_L_") {
                    left_dev = Some(p.clone());
                } else if name.contains("G2") && name.contains("_R_") {
                    right_dev = Some(p.clone());
                }
            }
        }
    }

    let left = left_dev.ok_or("Left G2 eye not found")?;
    let right = right_dev.ok_or("Right G2 eye not found")?;

    println!("  LEFT:  {:?}", left.properties().await?.and_then(|p| p.local_name));
    println!("  RIGHT: {:?}", right.properties().await?.and_then(|p| p.local_name));

    left.connect().await?;
    right.connect().await?;
    println!("\nConnected!");

    left.discover_services().await?;
    right.discover_services().await?;

    // Subscribe to notifications
    let left_chars = left.characteristics();
    if let Some(notif_char) = left_chars.iter().find(|c| c.uuid == char_notif_notify()) {
        left.subscribe(notif_char).await?;
    }
    if let Some(char) = left_chars.iter().find(|c| c.uuid == char_notify()) {
        left.subscribe(char).await?;
    }

    let right_chars = right.characteristics();
    if let Some(notif_char) = right_chars.iter().find(|c| c.uuid == char_notif_notify()) {
        right.subscribe(notif_char).await?;
    }
    if let Some(char) = right_chars.iter().find(|c| c.uuid == char_notify()) {
        right.subscribe(char).await?;
    }

    println!("\nAuthenticating...");
    authenticate(&left, "LEFT").await?;
    authenticate(&right, "RIGHT").await?;
    sleep(Duration::from_millis(500)).await;

    send_notification(&right, &left, &title, &subtitle, &message).await?;

    println!("\nNotification sent!");
    sleep(Duration::from_secs(3)).await;

    left.disconnect().await?;
    right.disconnect().await?;

    Ok(())
}
