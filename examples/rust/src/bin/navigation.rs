//! Even G2 Navigation - Send Turn-by-Turn Navigation to Glasses
//!
//! Sends navigation updates with distance, instructions, ETA, and maneuver icons.
//!
//! # Usage
//!
//! ```bash
//! cargo run --bin navigation -- "86 m" "Turn left" "7 min" "701 m" "ETA: 13:07"
//! cargo run --bin navigation -- --demo
//! ```
//!
//! # Requirements
//!
//! - Bluetooth adapter with BLE support
//! - Even G2 glasses

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

/// Navigation maneuver icon types
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum ManeuverIcon {
    TurnLeft = 1,
    TurnRight = 2,
    Straight = 3,
    UTurn = 4,
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

/// Encode a string field with tag and length prefix
fn encode_string(tag: u8, value: &str) -> Vec<u8> {
    let data = value.as_bytes();
    assert!(data.len() <= 255, "String too long ({} bytes, max 255)", data.len());
    let mut result = vec![tag, data.len() as u8];
    result.extend_from_slice(data);
    result
}

/// Build authentication packets
fn build_auth_packets() -> Vec<Vec<u8>> {
    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let ts_varint = encode_varint(timestamp);
    let txid = vec![0xE8, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01];

    let add_crc = |mut pkt: Vec<u8>| -> Vec<u8> {
        let crc = crc16_ccitt(&pkt[8..]);
        pkt.push((crc & 0xFF) as u8);
        pkt.push(((crc >> 8) & 0xFF) as u8);
        pkt
    };

    let mut packets = Vec::new();

    packets.push(add_crc(vec![
        0xAA, 0x21, 0x01, 0x0C, 0x01, 0x01, 0x80, 0x00,
        0x08, 0x04, 0x10, 0x0C, 0x1A, 0x04, 0x08, 0x01, 0x10, 0x04,
    ]));
    packets.push(add_crc(vec![
        0xAA, 0x21, 0x02, 0x0A, 0x01, 0x01, 0x80, 0x20,
        0x08, 0x05, 0x10, 0x0E, 0x22, 0x02, 0x08, 0x02,
    ]));

    let mut payload3 = vec![0x08, 0x80, 0x01, 0x10, 0x0F, 0x82, 0x08, 0x11, 0x08];
    payload3.extend_from_slice(&ts_varint);
    payload3.push(0x10);
    payload3.extend_from_slice(&txid);
    let mut p3 = vec![0xAA, 0x21, 0x03, (payload3.len() + 2) as u8, 0x01, 0x01, 0x80, 0x20];
    p3.extend_from_slice(&payload3);
    packets.push(add_crc(p3));

    packets.push(add_crc(vec![
        0xAA, 0x21, 0x04, 0x0C, 0x01, 0x01, 0x80, 0x00,
        0x08, 0x04, 0x10, 0x10, 0x1A, 0x04, 0x08, 0x01, 0x10, 0x04,
    ]));
    packets.push(add_crc(vec![
        0xAA, 0x21, 0x05, 0x0C, 0x01, 0x01, 0x80, 0x00,
        0x08, 0x04, 0x10, 0x11, 0x1A, 0x04, 0x08, 0x01, 0x10, 0x04,
    ]));
    packets.push(add_crc(vec![
        0xAA, 0x21, 0x06, 0x0A, 0x01, 0x01, 0x80, 0x20,
        0x08, 0x05, 0x10, 0x12, 0x22, 0x02, 0x08, 0x01,
    ]));

    let mut payload7 = vec![0x08, 0x80, 0x01, 0x10, 0x13, 0x82, 0x08, 0x11, 0x08];
    payload7.extend_from_slice(&ts_varint);
    payload7.push(0x10);
    payload7.extend_from_slice(&txid);
    let mut p7 = vec![0xAA, 0x21, 0x07, (payload7.len() + 2) as u8, 0x01, 0x01, 0x80, 0x20];
    p7.extend_from_slice(&payload7);
    packets.push(add_crc(p7));

    packets
}

/// Build a G2 navigation packet
pub fn build_navigation_packet(
    distance: &str,
    instruction: &str,
    time_remaining: &str,
    total_distance: &str,
    eta: &str,
    speed: &str,
    icon_type: ManeuverIcon,
    sequence: u8,
) -> Vec<u8> {
    // Build navigation fields
    let mut nav_fields = Vec::new();
    nav_fields.extend_from_slice(&[0x08, 0x04]); // Distance container tag
    nav_fields.extend(encode_string(0x12, distance));
    nav_fields.extend(encode_string(0x1a, instruction));
    nav_fields.extend(encode_string(0x22, time_remaining));
    nav_fields.extend(encode_string(0x2a, total_distance));
    nav_fields.extend(encode_string(0x32, eta));
    nav_fields.extend(encode_string(0x3a, speed));
    nav_fields.extend_from_slice(&[0x40, icon_type as u8]);

    // Wrap in container
    assert!(nav_fields.len() <= 255, "Navigation payload too large ({} bytes, max 255)", nav_fields.len());
    let mut payload = vec![0x08, 0x07, 0x2a, nav_fields.len() as u8];
    payload.extend(nav_fields);

    // Build packet
    let service = [0x08, 0x20]; // Navigation service
    let pkt_info = [0x01, 0x01]; // Single packet
    
    let mut full_payload = Vec::new();
    full_payload.extend_from_slice(&pkt_info);
    full_payload.extend_from_slice(&service);
    full_payload.extend(payload);

    assert!(full_payload.len() + 2 <= 255, "Packet too large ({} bytes, max 255)", full_payload.len() + 2);
    let mut packet = vec![0xAA, 0x21, sequence, (full_payload.len() + 2) as u8];
    packet.extend(&full_payload);

    // Add CRC
    let crc = crc16_ccitt(&full_payload);
    packet.push((crc & 0xFF) as u8);
    packet.push((crc >> 8) as u8);

    packet
}

async fn send_navigation(
    peripheral: &Peripheral,
    distance: &str,
    instruction: &str,
    time_remaining: &str,
    total_distance: &str,
    eta: &str,
    icon_type: ManeuverIcon,
    sequence: u8,
) -> Result<(), Box<dyn std::error::Error>> {
    let packet = build_navigation_packet(
        distance,
        instruction,
        time_remaining,
        total_distance,
        eta,
        "0.0 km/h",
        icon_type,
        sequence,
    );

    let chars = peripheral.characteristics();
    let write_char = chars
        .iter()
        .find(|c| c.uuid == char_write())
        .ok_or("Write characteristic not found")?;

    peripheral
        .write(write_char, &packet, WriteType::WithoutResponse)
        .await?;
    
    println!("  Sent: {} in {}", instruction, distance);
    Ok(())
}

async fn run_demo(peripheral: &Peripheral) -> Result<(), Box<dyn std::error::Error>> {
    println!("\nRunning navigation demo...");

    let demo_steps = vec![
        ("200 m", "Turn left onto Main St", "12 min", "2.1 km", "ETA: 14:32", ManeuverIcon::TurnLeft),
        ("150 m", "Turn left onto Main St", "12 min", "2.0 km", "ETA: 14:32", ManeuverIcon::TurnLeft),
        ("100 m", "Turn left onto Main St", "11 min", "1.9 km", "ETA: 14:32", ManeuverIcon::TurnLeft),
        ("50 m", "Turn left onto Main St", "11 min", "1.85 km", "ETA: 14:32", ManeuverIcon::TurnLeft),
        ("300 m", "Continue straight", "10 min", "1.8 km", "ETA: 14:32", ManeuverIcon::Straight),
        ("250 m", "Continue straight", "10 min", "1.75 km", "ETA: 14:32", ManeuverIcon::Straight),
        ("200 m", "Turn right onto Oak Ave", "9 min", "1.5 km", "ETA: 14:32", ManeuverIcon::TurnRight),
        ("100 m", "Turn right onto Oak Ave", "9 min", "1.4 km", "ETA: 14:32", ManeuverIcon::TurnRight),
        ("50 m", "Turn right onto Oak Ave", "8 min", "1.35 km", "ETA: 14:32", ManeuverIcon::TurnRight),
        ("500 m", "Your destination is ahead", "5 min", "500 m", "ETA: 14:30", ManeuverIcon::Straight),
    ];

    let mut seq = 0x10u8;
    for (distance, instruction, time_rem, total_dist, eta, icon) in demo_steps {
        send_navigation(
            peripheral,
            distance,
            instruction,
            time_rem,
            total_dist,
            eta,
            icon,
            seq,
        )
        .await?;
        seq = seq.wrapping_add(1);
        sleep(Duration::from_secs(2)).await;
    }

    println!("\nDemo complete!");
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

    println!("Even G2 Navigation");
    println!("{}", "=".repeat(40));

    let demo_mode = args.contains(&"--demo".to_string());

    if !demo_mode && args.len() < 6 {
        println!("\nUsage:");
        println!(r#"  cargo run --bin navigation -- "86 m" "Turn left" "7 min" "701 m" "ETA: 13:07""#);
        println!("  cargo run --bin navigation -- --demo");
        return Ok(());
    }

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

    // Fallback to any G2 device
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

    // Subscribe to notifications
    let chars = device.characteristics();
    if let Some(nc) = chars.iter().find(|c| c.uuid == char_notify()) {
        device.subscribe(nc).await?;
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

    if demo_mode {
        run_demo(&device).await?;
    } else {
        // Single navigation update
        let distance = &args[1];
        let instruction = &args[2];
        let time_remaining = &args[3];
        let total_distance = &args[4];
        let eta = &args[5];

        println!("\nSending navigation update...");
        send_navigation(
            &device,
            distance,
            instruction,
            time_remaining,
            total_distance,
            eta,
            ManeuverIcon::TurnLeft,
            0x10,
        )
        .await?;
        println!("\nDone! Check your glasses.");
    }

    sleep(Duration::from_secs(2)).await;
    device.disconnect().await?;

    Ok(())
}
