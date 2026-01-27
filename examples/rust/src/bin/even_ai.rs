//! Even AI Display - Send Custom Q&A to G2 Glasses
//!
//! Displays custom questions and answers on the Even AI card.
//! No Even app or cloud service required.
//!
//! # Usage
//!
//! ```bash
//! cargo run --bin even-ai -- "What is 2+2?" "The answer is 4!"
//! cargo run --bin even-ai -- --question "Hello" --answer "Hi there!"
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

/// Build G2 packet with header and CRC.
fn build_packet(seq: u8, svc_hi: u8, svc_lo: u8, payload: &[u8]) -> Vec<u8> {
    let mut packet = vec![
        0xAA,
        0x21,
        seq,
        (payload.len() + 2) as u8,
        0x01,
        0x01,
        svc_hi,
        svc_lo,
    ];
    packet.extend_from_slice(payload);
    let crc = crc16_ccitt(payload);
    packet.push((crc & 0xFF) as u8);
    packet.push(((crc >> 8) & 0xFF) as u8);
    packet
}

/// Build 7-packet authentication sequence.
fn build_auth_packets() -> Vec<Vec<u8>> {
    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let ts_varint = encode_varint(timestamp);
    let txid = vec![0xE8, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01];

    let mut packets = Vec::new();

    // Helper to add CRC
    let add_crc = |mut pkt: Vec<u8>| -> Vec<u8> {
        let crc = crc16_ccitt(&pkt[8..]);
        pkt.push((crc & 0xFF) as u8);
        pkt.push(((crc >> 8) & 0xFF) as u8);
        pkt
    };

    // Auth 1-2: Capability exchange
    packets.push(add_crc(vec![
        0xAA, 0x21, 0x01, 0x0C, 0x01, 0x01, 0x80, 0x00, 0x08, 0x04, 0x10, 0x0C, 0x1A, 0x04, 0x08,
        0x01, 0x10, 0x04,
    ]));
    packets.push(add_crc(vec![
        0xAA, 0x21, 0x02, 0x0A, 0x01, 0x01, 0x80, 0x20, 0x08, 0x05, 0x10, 0x0E, 0x22, 0x02, 0x08,
        0x02,
    ]));

    // Auth 3: Time sync
    let mut payload3 = vec![0x08, 0x80, 0x01, 0x10, 0x0F, 0x82, 0x08, 0x11, 0x08];
    payload3.extend_from_slice(&ts_varint);
    payload3.push(0x10);
    payload3.extend_from_slice(&txid);
    let mut p3 = vec![
        0xAA,
        0x21,
        0x03,
        (payload3.len() + 2) as u8,
        0x01,
        0x01,
        0x80,
        0x20,
    ];
    p3.extend_from_slice(&payload3);
    let crc3 = crc16_ccitt(&payload3);
    p3.push((crc3 & 0xFF) as u8);
    p3.push(((crc3 >> 8) & 0xFF) as u8);
    packets.push(p3);

    // Auth 4-6: Additional exchanges
    packets.push(add_crc(vec![
        0xAA, 0x21, 0x04, 0x0C, 0x01, 0x01, 0x80, 0x00, 0x08, 0x04, 0x10, 0x10, 0x1A, 0x04, 0x08,
        0x01, 0x10, 0x04,
    ]));
    packets.push(add_crc(vec![
        0xAA, 0x21, 0x05, 0x0C, 0x01, 0x01, 0x80, 0x00, 0x08, 0x04, 0x10, 0x11, 0x1A, 0x04, 0x08,
        0x01, 0x10, 0x04,
    ]));
    packets.push(add_crc(vec![
        0xAA, 0x21, 0x06, 0x0A, 0x01, 0x01, 0x80, 0x20, 0x08, 0x05, 0x10, 0x12, 0x22, 0x02, 0x08,
        0x01,
    ]));

    // Auth 7: Final time sync
    let mut payload7 = vec![0x08, 0x80, 0x01, 0x10, 0x13, 0x82, 0x08, 0x11, 0x08];
    payload7.extend_from_slice(&ts_varint);
    payload7.push(0x10);
    payload7.extend_from_slice(&txid);
    let mut p7 = vec![
        0xAA,
        0x21,
        0x07,
        (payload7.len() + 2) as u8,
        0x01,
        0x01,
        0x80,
        0x20,
    ];
    p7.extend_from_slice(&payload7);
    let crc7 = crc16_ccitt(&payload7);
    p7.push((crc7 & 0xFF) as u8);
    p7.push(((crc7 >> 8) & 0xFF) as u8);
    packets.push(p7);

    packets
}

// ============================================================
// Even AI Protocol
// ============================================================

/// CTRL(ENTER) - Enter Even AI mode.
/// REQUIRED before ASK/REPLY will display!
fn build_ctrl_enter(seq: u8, magic: u8) -> Vec<u8> {
    let payload = vec![
        0x08, 0x01, // commandId = 1 (CTRL)
        0x10, magic, // magicRandom
        0x1a, 0x02, // ctrl field (field 3)
        0x08, 0x02, // status = 2 (EVEN_AI_ENTER)
    ];
    build_packet(seq, 0x07, 0x20, &payload)
}

/// CTRL(EXIT) - Exit Even AI mode.
fn build_ctrl_exit(seq: u8, magic: u8) -> Vec<u8> {
    let payload = vec![
        0x08, 0x01, // commandId = 1 (CTRL)
        0x10, magic, // magicRandom
        0x1a, 0x02, // ctrl field
        0x08, 0x03, // status = 3 (EVEN_AI_EXIT)
    ];
    build_packet(seq, 0x07, 0x20, &payload)
}

/// ASK - Display question text on glasses.
fn build_ask(seq: u8, magic: u8, text: &str) -> Vec<u8> {
    let text_bytes = text.as_bytes();
    let text_len_varint = encode_varint(text_bytes.len() as u64);

    let mut askinfo = vec![
        0x08, 0x00, // cmdCnt = 0
        0x10, 0x00, // streamEnable = 0
        0x18, 0x00, // textMode = 0
        0x22, // text field (field 4)
    ];
    askinfo.extend_from_slice(&text_len_varint);
    askinfo.extend_from_slice(text_bytes);

    let askinfo_len_varint = encode_varint(askinfo.len() as u64);
    let mut payload = vec![
        0x08, 0x03, // commandId = 3 (ASK)
        0x10, magic, // magicRandom
        0x2a, // askInfo field (field 5)
    ];
    payload.extend_from_slice(&askinfo_len_varint);
    payload.extend_from_slice(&askinfo);

    build_packet(seq, 0x07, 0x20, &payload)
}

/// REPLY - Display answer text on glasses.
fn build_reply(seq: u8, magic: u8, text: &str) -> Vec<u8> {
    let text_bytes = text.as_bytes();
    let text_len_varint = encode_varint(text_bytes.len() as u64);

    let mut replyinfo = vec![
        0x08, 0x00, // cmdCnt = 0
        0x10, 0x00, // streamEnable = 0
        0x18, 0x00, // textMode = 0
        0x22, // text field (field 4)
    ];
    replyinfo.extend_from_slice(&text_len_varint);
    replyinfo.extend_from_slice(text_bytes);

    let replyinfo_len_varint = encode_varint(replyinfo.len() as u64);
    let mut payload = vec![
        0x08, 0x05, // commandId = 5 (REPLY)
        0x10, magic, // magicRandom
        0x3a, // replyInfo field (field 7)
    ];
    payload.extend_from_slice(&replyinfo_len_varint);
    payload.extend_from_slice(&replyinfo);

    build_packet(seq, 0x07, 0x20, &payload)
}

// ============================================================
// Main
// ============================================================

async fn display_qa(
    peripheral: &Peripheral,
    question: &str,
    answer: &str,
) -> Result<(), Box<dyn std::error::Error>> {
    let chars = peripheral.characteristics();
    let write_char = chars
        .iter()
        .find(|c| c.uuid == char_write())
        .ok_or("Write characteristic not found")?;

    let mut seq: u8 = 0x08;
    let mut magic: u8 = 100;

    // 1. Enter AI mode (REQUIRED!)
    println!("  Entering AI mode...");
    peripheral
        .write(
            write_char,
            &build_ctrl_enter(seq, magic),
            WriteType::WithoutResponse,
        )
        .await?;
    seq = seq.wrapping_add(1);
    magic = magic.wrapping_add(1);
    sleep(Duration::from_millis(300)).await;

    // 2. Display question
    println!("  Displaying question: {}", question);
    peripheral
        .write(
            write_char,
            &build_ask(seq, magic, question),
            WriteType::WithoutResponse,
        )
        .await?;
    seq = seq.wrapping_add(1);
    magic = magic.wrapping_add(1);
    sleep(Duration::from_secs(1)).await;

    // 3. Display answer
    println!("  Displaying answer: {}", answer);
    peripheral
        .write(
            write_char,
            &build_reply(seq, magic, answer),
            WriteType::WithoutResponse,
        )
        .await?;

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

    // Parse arguments (support both positional and named)
    let mut question = "What is 2 + 2?".to_string();
    let mut answer = "The answer is 4!".to_string();
    let mut use_left = false;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "-q" | "--question" => {
                if i + 1 < args.len() {
                    question = args[i + 1].clone();
                    i += 2;
                } else {
                    i += 1;
                }
            }
            "-a" | "--answer" => {
                if i + 1 < args.len() {
                    answer = args[i + 1].clone();
                    i += 2;
                } else {
                    i += 1;
                }
            }
            "--left" => {
                use_left = true;
                i += 1;
            }
            _ => {
                // Positional arguments
                if i == 1 && !args[i].starts_with('-') {
                    question = args[i].clone();
                } else if i == 2 && !args[i].starts_with('-') {
                    answer = args[i].clone();
                }
                i += 1;
            }
        }
    }

    println!("Even G2 - Custom AI Display");
    println!("{}", "=".repeat(50));

    println!("\nScanning for G2 glasses...");
    let adapter = find_adapter().await?;
    adapter.start_scan(ScanFilter::default()).await?;
    sleep(Duration::from_secs(10)).await;

    let peripherals = adapter.peripherals().await?;
    let pattern = if use_left { "_L_" } else { "_R_" };

    let mut device: Option<Peripheral> = None;
    for p in &peripherals {
        if let Some(props) = p.properties().await? {
            if let Some(name) = &props.local_name {
                if name.contains("G2") && name.contains(pattern) {
                    device = Some(p.clone());
                    break;
                }
            }
        }
    }

    let device = match device {
        Some(d) => d,
        None => {
            println!("ERROR: No G2 glasses found");
            for p in &peripherals {
                if let Some(props) = p.properties().await? {
                    if let Some(name) = &props.local_name {
                        if name.contains("G2") {
                            println!("  Found: {}", name);
                        }
                    }
                }
            }
            return Ok(());
        }
    };

    let name = device
        .properties()
        .await?
        .and_then(|p| p.local_name)
        .unwrap_or_else(|| "Unknown".to_string());
    println!("  Using: {}", name);

    device.connect().await?;
    println!("  Connected!");

    device.discover_services().await?;

    let chars = device.characteristics();
    if let Some(notify_char) = chars.iter().find(|c| c.uuid == char_notify()) {
        device.subscribe(notify_char).await?;
    }

    // Authenticate
    println!("\nAuthenticating...");
    let write_char = chars
        .iter()
        .find(|c| c.uuid == char_write())
        .ok_or("Write characteristic not found")?;

    for pkt in build_auth_packets() {
        device
            .write(write_char, &pkt, WriteType::WithoutResponse)
            .await?;
        sleep(Duration::from_millis(100)).await;
    }
    sleep(Duration::from_millis(500)).await;
    println!("  Authenticated!");

    // Display Q&A
    println!("\nDisplaying Q&A...");
    display_qa(&device, &question, &answer).await?;

    println!("\n{}", "=".repeat(50));
    println!("Done! Check your glasses.");
    println!("{}", "=".repeat(50));

    // Keep alive for viewing
    sleep(Duration::from_secs(5)).await;

    device.disconnect().await?;

    Ok(())
}
