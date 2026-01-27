//! Even G2 Teleprompter - Display Custom Text
//!
//! # Usage
//!
//! ```bash
//! cargo run --bin teleprompter -- "Your text here"
//! cargo run --bin teleprompter -- "Line one\nLine two\nLine three"
//! cargo run --bin teleprompter -- "Use right eye" --right
//! ```
//!
//! # Requirements
//!
//! - Bluetooth adapter with BLE support
//! - Even G2 glasses in pairing mode

use btleplug::api::{Central, Manager as _, Peripheral as _, ScanFilter, WriteType};
use btleplug::platform::{Adapter, Manager, Peripheral};
use std::env;
use std::time::Duration;
use tokio::time::sleep;
use uuid::Uuid;

// BLE UUIDs
const UUID_BASE: &str = "00002760-08c2-11e1-9073-0e8ac72e";
fn char_write() -> Uuid {
    Uuid::parse_str(&format!("{}{:04x}", UUID_BASE, 0x5401)).unwrap()
}
fn char_notify() -> Uuid {
    Uuid::parse_str(&format!("{}{:04x}", UUID_BASE, 0x5402)).unwrap()
}

// =============================================================================
// CRC-16/CCITT
// =============================================================================

/// CRC-16/CCITT with init=0xFFFF, polynomial=0x1021
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

/// Add CRC to packet (calculated over payload, stored little-endian)
fn add_crc(mut packet: Vec<u8>) -> Vec<u8> {
    let crc = crc16_ccitt(&packet[8..]); // Skip 8-byte header
    packet.push((crc & 0xFF) as u8);
    packet.push(((crc >> 8) & 0xFF) as u8);
    packet
}

// =============================================================================
// Encoding Helpers
// =============================================================================

/// Encode integer as protobuf varint
fn encode_varint(mut value: u64) -> Vec<u8> {
    let mut result = Vec::new();
    while value > 0x7F {
        result.push(((value & 0x7F) | 0x80) as u8);
        value >>= 7;
    }
    result.push((value & 0x7F) as u8);
    result
}

/// Build a complete packet with header and CRC
fn build_packet(seq: u8, service_hi: u8, service_lo: u8, payload: &[u8]) -> Vec<u8> {
    let mut packet = vec![
        0xAA,
        0x21,
        seq,
        (payload.len() + 2) as u8,
        0x01,
        0x01,
        service_hi,
        service_lo,
    ];
    packet.extend_from_slice(payload);
    add_crc(packet)
}

// =============================================================================
// Authentication
// =============================================================================

/// Build the 7-packet authentication sequence
fn build_auth_packets() -> Vec<Vec<u8>> {
    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let ts_varint = encode_varint(timestamp);
    let txid = vec![0xE8, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01];

    let mut packets = Vec::new();

    // Auth 1: Capability query
    packets.push(add_crc(vec![
        0xAA, 0x21, 0x01, 0x0C, 0x01, 0x01, 0x80, 0x00, 0x08, 0x04, 0x10, 0x0C, 0x1A, 0x04, 0x08,
        0x01, 0x10, 0x04,
    ]));

    // Auth 2: Capability response request
    packets.push(add_crc(vec![
        0xAA, 0x21, 0x02, 0x0A, 0x01, 0x01, 0x80, 0x20, 0x08, 0x05, 0x10, 0x0E, 0x22, 0x02, 0x08,
        0x02,
    ]));

    // Auth 3: Time sync with transaction ID
    let mut payload = vec![0x08, 0x80, 0x01, 0x10, 0x0F, 0x82, 0x08, 0x11, 0x08];
    payload.extend_from_slice(&ts_varint);
    payload.push(0x10);
    payload.extend_from_slice(&txid);
    let mut pkt = vec![0xAA, 0x21, 0x03, (payload.len() + 2) as u8, 0x01, 0x01, 0x80, 0x20];
    pkt.extend_from_slice(&payload);
    packets.push(add_crc(pkt));

    // Auth 4-5: Additional capability exchanges
    packets.push(add_crc(vec![
        0xAA, 0x21, 0x04, 0x0C, 0x01, 0x01, 0x80, 0x00, 0x08, 0x04, 0x10, 0x10, 0x1A, 0x04, 0x08,
        0x01, 0x10, 0x04,
    ]));
    packets.push(add_crc(vec![
        0xAA, 0x21, 0x05, 0x0C, 0x01, 0x01, 0x80, 0x00, 0x08, 0x04, 0x10, 0x11, 0x1A, 0x04, 0x08,
        0x01, 0x10, 0x04,
    ]));

    // Auth 6: Final capability
    packets.push(add_crc(vec![
        0xAA, 0x21, 0x06, 0x0A, 0x01, 0x01, 0x80, 0x20, 0x08, 0x05, 0x10, 0x12, 0x22, 0x02, 0x08,
        0x01,
    ]));

    // Auth 7: Final time sync
    let mut payload = vec![0x08, 0x80, 0x01, 0x10, 0x13, 0x82, 0x08, 0x11, 0x08];
    payload.extend_from_slice(&ts_varint);
    payload.push(0x10);
    payload.extend_from_slice(&txid);
    let mut pkt = vec![0xAA, 0x21, 0x07, (payload.len() + 2) as u8, 0x01, 0x01, 0x80, 0x20];
    pkt.extend_from_slice(&payload);
    packets.push(add_crc(pkt));

    packets
}

// =============================================================================
// Teleprompter Protocol
// =============================================================================

/// Service 0x0E-20: Display configuration
fn build_display_config(seq: u8, msg_id: u32) -> Vec<u8> {
    let config = hex::decode(
        "0801121308021090\
         4E1D00E094442500\
         000000280030001213\
         0803100D0F1D0040\
         8D44250000000028\
         0030001212080410\
         001D0000884225\
         00000000280030\
         001212080510001D\
         00009242250000\
         A242280030001212\
         080610001D0000C6\
         42250000C4422800\
         30001800",
    )
    .unwrap();

    let msg_id_varint = encode_varint(msg_id as u64);
    let mut payload = vec![0x08, 0x02, 0x10];
    payload.extend_from_slice(&msg_id_varint);
    payload.push(0x22);
    payload.push(0x6A);
    payload.extend_from_slice(&config);

    build_packet(seq, 0x0E, 0x20, &payload)
}

/// Service 0x06-20 type=1: Initialize teleprompter
fn build_teleprompter_init(seq: u8, msg_id: u32, total_lines: usize, manual_mode: bool) -> Vec<u8> {
    let mode: u8 = if manual_mode { 0x00 } else { 0x01 };

    // Scale content height based on line count (Bee Movie: 140 lines = 2665)
    let content_height = std::cmp::max(1, (total_lines * 2665) / 140);
    let content_height_varint = encode_varint(content_height as u64);

    let mut display = vec![0x08, 0x01, 0x10, 0x00, 0x18, 0x00, 0x20, 0x8B, 0x02]; // Fixed settings
    display.push(0x28);
    display.extend_from_slice(&content_height_varint); // Content height
    display.extend_from_slice(&[0x30, 0xE6, 0x01]); // Line height = 230
    display.extend_from_slice(&[0x38, 0x8E, 0x0A]); // Viewport = 1294
    display.extend_from_slice(&[0x40, 0x05, 0x48, mode]); // Font size + mode

    let mut settings = vec![0x08, 0x01, 0x12, display.len() as u8];
    settings.extend_from_slice(&display);

    let msg_id_varint = encode_varint(msg_id as u64);
    let mut payload = vec![0x08, 0x01, 0x10];
    payload.extend_from_slice(&msg_id_varint);
    payload.push(0x1A);
    payload.push(settings.len() as u8);
    payload.extend_from_slice(&settings);

    build_packet(seq, 0x06, 0x20, &payload)
}

/// Service 0x06-20 type=3: Content page
fn build_content_page(seq: u8, msg_id: u32, page_num: u8, text: &str) -> Vec<u8> {
    let text_bytes = format!("\n{}", text).into_bytes();
    let text_len_varint = encode_varint(text_bytes.len() as u64);

    let page_num_varint = encode_varint(page_num as u64);
    let mut inner = vec![0x08];
    inner.extend_from_slice(&page_num_varint);
    inner.extend_from_slice(&[0x10, 0x0A]); // 10 lines
    inner.push(0x1A);
    inner.extend_from_slice(&text_len_varint);
    inner.extend_from_slice(&text_bytes);

    let inner_len_varint = encode_varint(inner.len() as u64);
    let mut content = vec![0x2A];
    content.extend_from_slice(&inner_len_varint);
    content.extend_from_slice(&inner);

    let msg_id_varint = encode_varint(msg_id as u64);
    let mut payload = vec![0x08, 0x03, 0x10];
    payload.extend_from_slice(&msg_id_varint);
    payload.extend_from_slice(&content);

    build_packet(seq, 0x06, 0x20, &payload)
}

/// Service 0x06-20 type=255: Mid-stream marker
fn build_marker(seq: u8, msg_id: u32) -> Vec<u8> {
    let msg_id_varint = encode_varint(msg_id as u64);
    let mut payload = vec![0x08, 0xFF, 0x01, 0x10];
    payload.extend_from_slice(&msg_id_varint);
    payload.extend_from_slice(&[0x6A, 0x04, 0x08, 0x00, 0x10, 0x06]);
    build_packet(seq, 0x06, 0x20, &payload)
}

/// Service 0x80-00 type=14: Sync/trigger
fn build_sync(seq: u8, msg_id: u32) -> Vec<u8> {
    let msg_id_varint = encode_varint(msg_id as u64);
    let mut payload = vec![0x08, 0x0E, 0x10];
    payload.extend_from_slice(&msg_id_varint);
    payload.extend_from_slice(&[0x6A, 0x00]);
    build_packet(seq, 0x80, 0x00, &payload)
}

// =============================================================================
// Text Formatting
// =============================================================================

/// Format text into pages of wrapped lines
fn format_text(text: &str, chars_per_line: usize, lines_per_page: usize) -> Vec<String> {
    // Handle escaped newlines
    let text = text.replace("\\n", "\n");

    // Split and wrap lines
    let mut wrapped = Vec::new();
    for line in text.split('\n') {
        if line.trim().is_empty() {
            wrapped.push(String::new());
            continue;
        }

        let words: Vec<&str> = line.split_whitespace().collect();
        let mut current = String::new();
        for word in words {
            if current.len() + word.len() + 1 > chars_per_line {
                if !current.is_empty() {
                    wrapped.push(current.trim().to_string());
                }
                current = format!("{} ", word);
            } else {
                current.push_str(word);
                current.push(' ');
            }
        }
        if !current.trim().is_empty() {
            wrapped.push(current.trim().to_string());
        }
    }

    if wrapped.is_empty() {
        wrapped.push(text.to_string());
    }

    // Pad to at least 10 lines
    while wrapped.len() < lines_per_page {
        wrapped.push(" ".to_string());
    }

    // Split into pages
    let mut pages = Vec::new();
    for chunk in wrapped.chunks(lines_per_page) {
        let mut page_lines: Vec<String> = chunk.to_vec();
        while page_lines.len() < lines_per_page {
            page_lines.push(" ".to_string());
        }
        pages.push(format!("{} \n", page_lines.join("\n")));
    }

    // Pad to minimum 14 pages
    while pages.len() < 14 {
        let empty_page = vec![" "; lines_per_page].join("\n");
        pages.push(format!("{} \n", empty_page));
    }

    pages
}

// =============================================================================
// Main
// =============================================================================

async fn send_text(device: &Peripheral, text: &str) -> Result<(), Box<dyn std::error::Error>> {
    let name = device
        .properties()
        .await?
        .and_then(|p| p.local_name)
        .unwrap_or_else(|| "Unknown".to_string());
    println!("Connecting to {}...", name);

    device.connect().await?;
    if !device.is_connected().await? {
        println!("Failed to connect!");
        return Ok(());
    }

    println!("Connected!");
    device.discover_services().await?;

    let chars = device.characteristics();
    let write_char = chars
        .iter()
        .find(|c| c.uuid == char_write())
        .ok_or("Write characteristic not found")?;
    let notify_char = chars.iter().find(|c| c.uuid == char_notify());

    // Enable notifications
    if let Some(nc) = notify_char {
        device.subscribe(nc).await?;
    }

    // Send auth sequence
    println!("Authenticating...");
    for pkt in build_auth_packets() {
        device
            .write(write_char, &pkt, WriteType::WithoutResponse)
            .await?;
        sleep(Duration::from_millis(100)).await;
    }
    sleep(Duration::from_millis(500)).await;

    // Format text into pages
    let pages = format_text(text, 25, 10);
    let total_lines = text.replace("\\n", "\n").split('\n').count();

    let mut seq: u8 = 0x08;
    let mut msg_id: u32 = 0x14;

    // Display config
    println!("Configuring display...");
    device
        .write(
            write_char,
            &build_display_config(seq, msg_id),
            WriteType::WithoutResponse,
        )
        .await?;
    seq = seq.wrapping_add(1);
    msg_id += 1;
    sleep(Duration::from_millis(300)).await;

    // Teleprompter init
    println!("Initializing teleprompter...");
    device
        .write(
            write_char,
            &build_teleprompter_init(seq, msg_id, total_lines, true),
            WriteType::WithoutResponse,
        )
        .await?;
    seq = seq.wrapping_add(1);
    msg_id += 1;
    sleep(Duration::from_millis(500)).await;

    // Send content pages 0-9
    println!("Sending {} pages...", pages.len());
    for i in 0..std::cmp::min(10, pages.len()) {
        device
            .write(
                write_char,
                &build_content_page(seq, msg_id, i as u8, &pages[i]),
                WriteType::WithoutResponse,
            )
            .await?;
        seq = seq.wrapping_add(1);
        msg_id += 1;
        sleep(Duration::from_millis(100)).await;
    }

    // Mid-stream marker
    device
        .write(
            write_char,
            &build_marker(seq, msg_id),
            WriteType::WithoutResponse,
        )
        .await?;
    seq = seq.wrapping_add(1);
    msg_id += 1;
    sleep(Duration::from_millis(100)).await;

    // Pages 10-11
    for i in 10..std::cmp::min(12, pages.len()) {
        device
            .write(
                write_char,
                &build_content_page(seq, msg_id, i as u8, &pages[i]),
                WriteType::WithoutResponse,
            )
            .await?;
        seq = seq.wrapping_add(1);
        msg_id += 1;
        sleep(Duration::from_millis(100)).await;
    }

    // Sync trigger
    device
        .write(
            write_char,
            &build_sync(seq, msg_id),
            WriteType::WithoutResponse,
        )
        .await?;
    seq = seq.wrapping_add(1);
    msg_id += 1;
    sleep(Duration::from_millis(100)).await;

    // Remaining pages
    for i in 12..pages.len() {
        device
            .write(
                write_char,
                &build_content_page(seq, msg_id, i as u8, &pages[i]),
                WriteType::WithoutResponse,
            )
            .await?;
        seq = seq.wrapping_add(1);
        msg_id += 1;
        sleep(Duration::from_millis(100)).await;
    }

    println!("Done! Check your glasses.");
    sleep(Duration::from_secs(5)).await;

    device.disconnect().await?;
    Ok(())
}

async fn find_adapter() -> Result<Adapter, Box<dyn std::error::Error>> {
    let manager = Manager::new().await?;
    let adapters = manager.adapters().await?;
    adapters
        .into_iter()
        .next()
        .ok_or("No Bluetooth adapter found".into())
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().collect();
    let text = if args.len() > 1 {
        args[1].clone()
    } else {
        "Hello from Rust!\nThis is a test.".to_string()
    };
    let use_right = args.contains(&"--right".to_string());

    println!("Scanning for Even G2 glasses...");
    let adapter = find_adapter().await?;
    adapter.start_scan(ScanFilter::default()).await?;
    sleep(Duration::from_secs(10)).await;

    let peripherals = adapter.peripherals().await?;
    let g2_devices: Vec<Peripheral> = futures::future::join_all(
        peripherals.iter().map(|p| async {
            let props = p.properties().await.ok().flatten();
            if let Some(props) = props {
                if let Some(name) = props.local_name {
                    if name.contains("G2") {
                        return Some(p.clone());
                    }
                }
            }
            None
        }),
    )
    .await
    .into_iter()
    .flatten()
    .collect();

    if g2_devices.is_empty() {
        println!("No G2 glasses found!");
        return Ok(());
    }

    // Select left or right
    let pattern = if use_right { "_R_" } else { "_L_" };
    let device = {
        let mut found: Option<Peripheral> = None;
        for d in &g2_devices {
            if let Some(props) = d.properties().await? {
                if let Some(name) = props.local_name {
                    if name.contains(pattern) {
                        found = Some(d.clone());
                        break;
                    }
                }
            }
        }
        found.unwrap_or_else(|| g2_devices[0].clone())
    };

    let name = device
        .properties()
        .await?
        .and_then(|p| p.local_name)
        .unwrap_or_else(|| "Unknown".to_string());
    println!("Using: {}", name);

    send_text(&device, &text).await?;

    Ok(())
}
