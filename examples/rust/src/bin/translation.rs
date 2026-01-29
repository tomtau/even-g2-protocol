//! Even G2 Translation - Real-time Speech Translation
//!
//! Enables translation mode on G2 glasses and displays translation results.
//!
//! # Usage
//!
//! ```bash
//! cargo run --bin translation -- CS EN     # Czech to English
//! cargo run --bin translation -- HK EN     # Cantonese to English
//! cargo run --bin translation -- --list    # Show available languages
//! ```
//!
//! # Requirements
//!
//! - Bluetooth adapter with BLE support
//! - Even G2 glasses

use btleplug::api::{Central, Manager as _, Peripheral as _, ScanFilter, WriteType};
use btleplug::platform::{Adapter, Manager, Peripheral};
use futures::stream::StreamExt;
use std::collections::HashMap;
use std::env;
use std::sync::{Arc, Mutex};
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

/// CRC-16/CCITT for packet framing
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

/// Add CRC to packet
fn add_crc(mut packet: Vec<u8>) -> Vec<u8> {
    let crc = crc16_ccitt(&packet[8..]);
    packet.push((crc & 0xFF) as u8);
    packet.push(((crc >> 8) & 0xFF) as u8);
    packet
}

/// Build authentication packets
fn build_auth_packets() -> Vec<Vec<u8>> {
    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let ts_varint = encode_varint(timestamp);
    let txid = vec![0xE8, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01];

    let mut packets = Vec::new();

    packets.push(add_crc(vec![
        0xAA, 0x21, 0x01, 0x0C, 0x01, 0x01, 0x80, 0x00, 0x08, 0x04, 0x10, 0x0C, 0x1A, 0x04, 0x08,
        0x01, 0x10, 0x04,
    ]));

    packets.push(add_crc(vec![
        0xAA, 0x21, 0x02, 0x0A, 0x01, 0x01, 0x80, 0x20, 0x08, 0x05, 0x10, 0x0E, 0x22, 0x02, 0x08,
        0x02,
    ]));

    let mut payload = vec![0x08, 0x80, 0x01, 0x10, 0x0F, 0x82, 0x08, 0x11, 0x08];
    payload.extend_from_slice(&ts_varint);
    payload.push(0x10);
    payload.extend_from_slice(&txid);
    let mut pkt = vec![0xAA, 0x21, 0x03, (payload.len() + 2) as u8, 0x01, 0x01, 0x80, 0x20];
    pkt.extend_from_slice(&payload);
    packets.push(add_crc(pkt));

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

    let mut payload = vec![0x08, 0x80, 0x01, 0x10, 0x13, 0x82, 0x08, 0x11, 0x08];
    payload.extend_from_slice(&ts_varint);
    payload.push(0x10);
    payload.extend_from_slice(&txid);
    let mut pkt = vec![0xAA, 0x21, 0x07, (payload.len() + 2) as u8, 0x01, 0x01, 0x80, 0x20];
    pkt.extend_from_slice(&payload);
    packets.push(add_crc(pkt));

    packets
}

/// Build translation enable packet
pub fn build_translation_enable(seq: u8, msg_id: u8, source: &str, target: &str) -> Vec<u8> {
    let lang_pair = format!("{}>{}", source, target);
    let lang_bytes = lang_pair.as_bytes();

    // Mode data: 08 01 12 len lang 18 01
    let mut mode_data = vec![0x08, 0x01, 0x12, lang_bytes.len() as u8];
    mode_data.extend_from_slice(lang_bytes);
    mode_data.extend_from_slice(&[0x18, 0x01]);

    // Payload: 08 01 10 msg_id 1A len mode_data
    let mut payload = vec![0x08, 0x01, 0x10, msg_id, 0x1A, mode_data.len() as u8];
    payload.extend(mode_data);

    build_packet(seq, 0x05, 0x20, &payload)
}

/// Build translation disable packet
pub fn build_translation_disable(seq: u8, msg_id: u8) -> Vec<u8> {
    let mode_data = vec![0x08, 0x02];
    let mut payload = vec![0x08, 0x01, 0x10, msg_id, 0x1A, mode_data.len() as u8];
    payload.extend(mode_data);

    build_packet(seq, 0x05, 0x20, &payload)
}

/// Build translation result packet to send text TO the glasses for display.
///
/// This allows sending custom translation results to display on the glasses,
/// enabling use of third-party speech recognition and translation services.
///
/// Note: Text lengths are limited to 255 bytes when UTF-8 encoded.
/// Longer texts will be truncated.
pub fn build_translation_result(
    seq: u8,
    msg_id: u8,
    original: &str,
    translation: &str,
    is_final: bool,
    speaker: &str,
) -> Vec<u8> {
    // Truncate to max 255 bytes
    let original_bytes: Vec<u8> = original.as_bytes().iter().take(255).copied().collect();
    let translation_bytes: Vec<u8> = translation.as_bytes().iter().take(255).copied().collect();

    // Build content: 0A len original 12 len translation
    let mut content = vec![0x0A, original_bytes.len() as u8];
    content.extend_from_slice(&original_bytes);
    content.push(0x12);
    content.push(translation_bytes.len() as u8);
    content.extend_from_slice(&translation_bytes);

    // Build speaker info in UTF-16 BE with BOM (truncate if needed)
    let mut speaker_utf16: Vec<u8> = vec![0xFE, 0xFF];
    for c in speaker.encode_utf16() {
        if speaker_utf16.len() >= 253 {
            break; // Leave room for 2 more bytes
        }
        speaker_utf16.push((c >> 8) as u8);
        speaker_utf16.push((c & 0xFF) as u8);
    }

    // Truncate content if needed (unlikely with reasonable text)
    let content: Vec<u8> = content.into_iter().take(255).collect();

    // Build payload: 08 02 10 msg_id 22 len content 18 00 20 final 2A len speaker
    let mut payload = vec![0x08, 0x02, 0x10, msg_id];
    payload.push(0x22);
    payload.push(content.len() as u8);
    payload.extend(content);
    payload.extend_from_slice(&[0x18, 0x00]); // Unknown field
    payload.push(0x20);
    payload.push(if is_final { 0x01 } else { 0x00 });
    payload.push(0x2A);
    payload.push(speaker_utf16.len() as u8);
    payload.extend(speaker_utf16);

    build_packet(seq, 0x05, 0x20, &payload)
}

/// Translation result
#[derive(Debug, Clone)]
pub struct TranslationResult {
    pub original: String,
    pub translation: String,
    pub is_final: bool,
}

/// Parse translation result from notification data
pub fn parse_translation_result(data: &[u8]) -> Option<TranslationResult> {
    // Find service 05 20 in data
    let mut service_idx = None;
    for i in 0..data.len().saturating_sub(1) {
        if data[i] == 0x05 && data[i + 1] == 0x20 {
            service_idx = Some(i + 2);
            break;
        }
    }

    let payload_start = service_idx?;
    if payload_start + 4 > data.len() {
        return None;
    }

    let payload = &data[payload_start..data.len().saturating_sub(2)];

    if payload.len() < 4 || payload[0] != 0x08 || payload[1] != 0x02 {
        return None;
    }

    let mut original = String::new();
    let mut translation = String::new();
    let mut is_final = false;
    let mut idx = 2;

    while idx < payload.len() {
        let tag = payload[idx];

        if tag == 0x10 {
            idx += 2; // Skip msg_id
        } else if tag == 0x22 {
            idx += 1;
            if idx >= payload.len() {
                break;
            }
            let content_len = payload[idx] as usize;
            idx += 1;
            if idx + content_len > payload.len() {
                break;
            }
            let content = &payload[idx..idx + content_len];
            idx += content_len;

            // Parse content: 0A len original 12 len translation
            let mut cidx = 0;
            if cidx < content.len() && content[cidx] == 0x0A {
                cidx += 1;
                if cidx < content.len() {
                    let orig_len = content[cidx] as usize;
                    cidx += 1;
                    if cidx + orig_len <= content.len() {
                        original = String::from_utf8_lossy(&content[cidx..cidx + orig_len]).to_string();
                        cidx += orig_len;
                    }
                }

                if cidx < content.len() && content[cidx] == 0x12 {
                    cidx += 1;
                    if cidx < content.len() {
                        let trans_len = content[cidx] as usize;
                        cidx += 1;
                        if cidx + trans_len <= content.len() {
                            translation = String::from_utf8_lossy(&content[cidx..cidx + trans_len]).to_string();
                        }
                    }
                }
            }
        } else if tag == 0x18 {
            idx += 2;
        } else if tag == 0x20 {
            idx += 1;
            if idx < payload.len() {
                is_final = payload[idx] == 0x01;
            }
            idx += 1;
        } else if tag == 0x2A {
            idx += 1;
            if idx < payload.len() {
                let spk_len = payload[idx] as usize;
                idx += 1 + spk_len;
            }
        } else {
            idx += 1;
        }
    }

    if original.is_empty() {
        return None;
    }

    Some(TranslationResult {
        original,
        translation,
        is_final,
    })
}

fn get_languages() -> HashMap<&'static str, &'static str> {
    let mut map = HashMap::new();
    map.insert("EN", "English");
    map.insert("CS", "Czech");
    map.insert("HK", "Cantonese (Hong Kong)");
    map.insert("ZH", "Mandarin Chinese");
    map.insert("JA", "Japanese");
    map.insert("KO", "Korean");
    map.insert("ES", "Spanish");
    map.insert("FR", "French");
    map.insert("DE", "German");
    map.insert("IT", "Italian");
    map.insert("PT", "Portuguese");
    map.insert("RU", "Russian");
    map.insert("AR", "Arabic");
    map
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
    let languages = get_languages();

    if args.contains(&"--list".to_string()) || args.contains(&"-l".to_string()) {
        println!("Available language codes:");
        println!("{}", "-".repeat(40));
        for (code, name) in &languages {
            println!("  {}: {}", code, name);
        }
        println!("\nUsage: cargo run --bin translation -- SOURCE TARGET");
        println!("       cargo run --bin translation -- --send ORIGINAL TRANSLATION");
        println!("Example: cargo run --bin translation -- CS EN");
        return Ok(());
    }

    // Send mode: send custom translation text to glasses
    if args.contains(&"--send".to_string()) {
        let send_idx = args.iter().position(|x| x == "--send").unwrap();
        if args.len() < send_idx + 3 {
            println!("Usage: cargo run --bin translation -- --send ORIGINAL TRANSLATION");
            println!("Example: cargo run --bin translation -- --send 'Bonjour' 'Hello'");
            return Ok(());
        }
        let original = &args[send_idx + 1];
        let translation = &args[send_idx + 2];

        println!("Even G2 Translation - Send Mode");
        println!("{}", "=".repeat(40));
        println!("\nOriginal:    {}", original);
        println!("Translation: {}", translation);

        println!("\nScanning for G2 glasses...");
        let adapter = find_adapter().await?;
        adapter.start_scan(ScanFilter::default()).await?;
        sleep(Duration::from_secs(10)).await;

        let peripherals = adapter.peripherals().await?;
        let mut device: Option<Peripheral> = None;
        for p in &peripherals {
            if let Some(props) = p.properties().await? {
                if let Some(name) = &props.local_name {
                    if name.contains("G2") && name.contains("_L_") {
                        device = Some(p.clone());
                        println!("  Found: {}", name);
                        break;
                    }
                }
            }
        }
        if device.is_none() {
            for p in &peripherals {
                if let Some(props) = p.properties().await? {
                    if let Some(name) = &props.local_name {
                        if name.contains("G2") {
                            device = Some(p.clone());
                            println!("  Found: {}", name);
                            break;
                        }
                    }
                }
            }
        }

        let device = match device {
            Some(d) => d,
            None => {
                println!("ERROR: No G2 glasses found!");
                return Ok(());
            }
        };

        device.connect().await?;
        println!("\nConnected!");

        device.discover_services().await?;
        let chars = device.characteristics();
        let write_char = chars
            .iter()
            .find(|c| c.uuid == char_write())
            .ok_or("Write characteristic not found")?;
        let notify_char = chars
            .iter()
            .find(|c| c.uuid == char_notify())
            .ok_or("Notify characteristic not found")?;

        device.subscribe(notify_char).await?;

        println!("\nAuthenticating...");
        for pkt in build_auth_packets() {
            device
                .write(write_char, &pkt, WriteType::WithoutResponse)
                .await?;
            sleep(Duration::from_millis(100)).await;
        }
        sleep(Duration::from_millis(500)).await;
        println!("  Authenticated!");

        // Enable translation mode first
        // Note: The language pair here doesn't affect display when sending custom text
        println!("\nEnabling translation display...");
        let enable_pkt = build_translation_enable(0x10, 0x50, "EN", "EN");
        device
            .write(write_char, &enable_pkt, WriteType::WithoutResponse)
            .await?;
        sleep(Duration::from_millis(500)).await;

        // Send custom translation text
        println!("\nSending translation text...");
        let send_pkt = build_translation_result(0x11, 0x51, original, translation, true, "Speaker 1");
        device
            .write(write_char, &send_pkt, WriteType::WithoutResponse)
            .await?;

        println!("\nTranslation sent! Check your glasses.");
        sleep(Duration::from_secs(5)).await;

        // Disable translation
        let disable_pkt = build_translation_disable(0x12, 0x52);
        device
            .write(write_char, &disable_pkt, WriteType::WithoutResponse)
            .await?;
        sleep(Duration::from_millis(300)).await;
        println!("Done!");

        device.disconnect().await?;
        return Ok(());
    }

    if args.len() < 3 {
        println!("Even G2 Translation");
        println!("{}", "=".repeat(40));
        println!("\nUsage:");
        println!("  cargo run --bin translation -- SOURCE TARGET        # Listen mode");
        println!("  cargo run --bin translation -- --send ORIG TRANS    # Send custom text");
        println!("  cargo run --bin translation -- --list               # Show languages");
        println!("\nExamples:");
        println!("  cargo run --bin translation -- CS EN                # Czech to English");
        println!("  cargo run --bin translation -- HK EN                # Cantonese to English");
        println!("  cargo run --bin translation -- --send 'Bonjour' 'Hello'");
        return Ok(());
    }

    let source = args[1].to_uppercase();
    let target = args[2].to_uppercase();

    println!("Even G2 Translation");
    println!("{}", "=".repeat(40));
    println!(
        "\nLanguage: {} → {}",
        languages.get(source.as_str()).unwrap_or(&source.as_str()),
        languages.get(target.as_str()).unwrap_or(&target.as_str())
    );

    println!("\nScanning for G2 glasses...");
    let adapter = find_adapter().await?;
    adapter.start_scan(ScanFilter::default()).await?;
    sleep(Duration::from_secs(10)).await;

    let peripherals = adapter.peripherals().await?;

    let mut device: Option<Peripheral> = None;
    for p in &peripherals {
        if let Some(props) = p.properties().await? {
            if let Some(name) = &props.local_name {
                if name.contains("G2") && name.contains("_L_") {
                    device = Some(p.clone());
                    println!("  Found: {}", name);
                    break;
                }
            }
        }
    }

    if device.is_none() {
        for p in &peripherals {
            if let Some(props) = p.properties().await? {
                if let Some(name) = &props.local_name {
                    if name.contains("G2") {
                        device = Some(p.clone());
                        println!("  Found: {}", name);
                        break;
                    }
                }
            }
        }
    }

    let device = match device {
        Some(d) => d,
        None => {
            println!("ERROR: No G2 glasses found!");
            return Ok(());
        }
    };

    device.connect().await?;
    println!("\nConnected!");

    device.discover_services().await?;

    let chars = device.characteristics();
    let write_char = chars
        .iter()
        .find(|c| c.uuid == char_write())
        .ok_or("Write characteristic not found")?;
    let notify_char = chars
        .iter()
        .find(|c| c.uuid == char_notify())
        .ok_or("Notify characteristic not found")?;

    device.subscribe(notify_char).await?;

    // Authenticate
    println!("\nAuthenticating...");
    for pkt in build_auth_packets() {
        device
            .write(write_char, &pkt, WriteType::WithoutResponse)
            .await?;
        sleep(Duration::from_millis(100)).await;
    }
    sleep(Duration::from_millis(500)).await;
    println!("  Authenticated!");

    let translation_count = Arc::new(Mutex::new(0u32));
    let count_clone = translation_count.clone();

    // Enable translation
    println!("\nEnabling {}>{} translation...", source, target);
    let enable_pkt = build_translation_enable(0x10, 0x50, &source, &target);
    device
        .write(write_char, &enable_pkt, WriteType::WithoutResponse)
        .await?;

    println!("\nTranslation active! Speak to see results.");
    println!("Press Ctrl+C to stop.\n");

    let mut notification_stream = device.notifications().await?;

    // Handle notifications
    let device_clone = device.clone();
    let write_char_clone = write_char.clone();
    
    tokio::spawn(async move {
        tokio::signal::ctrl_c().await.ok();
        println!("\n\nDisabling translation...");
        let disable_pkt = build_translation_disable(0x11, 0x51);
        let _ = device_clone
            .write(&write_char_clone, &disable_pkt, WriteType::WithoutResponse)
            .await;
        sleep(Duration::from_millis(500)).await;
        let _ = device_clone.disconnect().await;
        let count = *count_clone.lock().unwrap();
        println!("Done! Received {} translation(s).", count);
        std::process::exit(0);
    });

    while let Some(data) = notification_stream.next().await {
        if let Some(result) = parse_translation_result(&data.value) {
            let mut count = translation_count.lock().unwrap();
            *count += 1;

            let final_marker = if result.is_final { "[FINAL]" } else { "[...]" };
            println!("\n{} Original: {}", final_marker, result.original);
            println!("      Translation: {}", result.translation);
        }
    }

    // This is reached if the notification stream ends (device disconnect, etc.)
    device.disconnect().await?;
    Ok(())
}
