//! Even G2 Gesture Handler - Detect and Handle Touch Gestures
//!
//! Listens for gesture events from G2 glasses and handles tap, swipe, and long press.
//!
//! # Usage
//!
//! ```bash
//! cargo run --bin gesture
//! ```
//!
//! # Requirements
//!
//! - Bluetooth adapter with BLE support
//! - Even G2 glasses

use btleplug::api::{Central, Manager as _, Peripheral as _, ScanFilter, CharPropFlags};
use btleplug::platform::{Adapter, Manager, Peripheral};
use futures::stream::StreamExt;
use std::time::{Duration, Instant};
use std::sync::{Arc, Mutex};
use tokio::time::sleep;
use uuid::Uuid;

// BLE UUIDs
const UUID_BASE: &str = "00002760-08c2-11e1-9073-0e8ac72e";
fn char_notify() -> Uuid {
    Uuid::parse_str(&format!("{}{:04x}", UUID_BASE, 0x5402)).unwrap()
}

/// Gesture types detected from G2 packets
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum G2Gesture {
    Tap,
    SwipeForward,
    SwipeBackward,
    LongPress,
}

impl std::fmt::Display for G2Gesture {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            G2Gesture::Tap => write!(f, "tap"),
            G2Gesture::SwipeForward => write!(f, "swipe_forward"),
            G2Gesture::SwipeBackward => write!(f, "swipe_backward"),
            G2Gesture::LongPress => write!(f, "long_press"),
        }
    }
}

/// Detect gesture type from G2 packet bytes
pub fn detect_gesture(data: &[u8]) -> Option<G2Gesture> {
    let hex: String = data.iter()
        .map(|b| format!("{:02x}", b))
        .collect();

    // Long press (service 0d01)
    if hex.contains("01010d01") && hex.contains("1a0408011003") {
        return Some(G2Gesture::LongPress);
    }

    // Swipe gestures (service 0101, pattern 320d)
    if hex.contains("320d") {
        if hex.contains("12040801") {
            return Some(G2Gesture::SwipeForward);
        } else if hex.contains("12040802") {
            return Some(G2Gesture::SwipeBackward);
        }
    }

    // Tap gesture (service 0101, pattern 320b)
    if hex.contains("320b") && hex.contains("08011202") {
        return Some(G2Gesture::Tap);
    }

    None
}

/// Double-tap detector using timing-based detection
struct DoubleTapDetector {
    last_tap_time: Option<Instant>,
    threshold: Duration,
}

impl DoubleTapDetector {
    fn new(threshold_ms: u64) -> Self {
        Self {
            last_tap_time: None,
            threshold: Duration::from_millis(threshold_ms),
        }
    }

    /// Returns true if this tap is a double-tap
    fn handle_tap(&mut self) -> bool {
        let now = Instant::now();
        
        if let Some(last) = self.last_tap_time {
            if now.duration_since(last) < self.threshold {
                self.last_tap_time = None;
                return true; // Double tap
            }
        }
        
        self.last_tap_time = Some(now);
        false // Potential single tap (needs timeout check)
    }
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
    println!("Even G2 Gesture Handler");
    println!("{}", "=".repeat(40));

    println!("\nScanning for G2 glasses...");
    let adapter = find_adapter().await?;
    adapter.start_scan(ScanFilter::default()).await?;
    sleep(Duration::from_secs(10)).await;

    let peripherals = adapter.peripherals().await?;
    
    let mut device: Option<Peripheral> = None;
    for p in &peripherals {
        if let Some(props) = p.properties().await? {
            if let Some(name) = &props.local_name {
                if name.contains("G2") && (name.contains("_L_") || name.contains("_R_")) {
                    device = Some(p.clone());
                    println!("  Found: {}", name);
                    break;
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

    // Find and subscribe to notify characteristic
    let chars = device.characteristics();
    let notify_char = chars.iter().find(|c| c.uuid == char_notify());
    
    if let Some(nc) = notify_char {
        device.subscribe(nc).await?;
    } else {
        println!("ERROR: Notify characteristic not found!");
        return Ok(());
    }

    println!("\nListening for gestures...");
    println!("  - Tap: Touch sensor briefly");
    println!("  - Double Tap: Tap twice quickly");
    println!("  - Swipe Forward: Swipe towards temple");
    println!("  - Swipe Backward: Swipe towards nose");
    println!("  - Long Press: Hold touch sensor");
    println!("\nPress Ctrl+C to exit.\n");

    let double_tap_detector = Arc::new(Mutex::new(DoubleTapDetector::new(300)));
    let gesture_counter = Arc::new(Mutex::new(0u32));

    let mut notification_stream = device.notifications().await?;
    
    while let Some(data) = notification_stream.next().await {
        if let Some(gesture) = detect_gesture(&data.value) {
            let mut counter = gesture_counter.lock().unwrap();
            *counter += 1;
            let count = *counter;
            drop(counter);

            let hex_preview: String = data.value.iter()
                .take(30)
                .map(|b| format!("{:02x}", b))
                .collect();

            println!("\n[{}] Gesture: {}", count, gesture);
            println!("    Raw: {}...", hex_preview);

            match gesture {
                G2Gesture::Tap => {
                    let mut detector = double_tap_detector.lock().unwrap();
                    if detector.handle_tap() {
                        println!("  → Double Tap detected!");
                    } else {
                        // For simplicity, we report single tap immediately
                        // A proper implementation would use a delayed callback
                        println!("  → Tap detected! (may be double tap)");
                    }
                }
                G2Gesture::SwipeForward => {
                    println!("  → Swipe Forward detected!");
                }
                G2Gesture::SwipeBackward => {
                    println!("  → Swipe Backward detected!");
                }
                G2Gesture::LongPress => {
                    println!("  → Long Press detected!");
                }
            }
        }
    }

    device.disconnect().await?;
    Ok(())
}
