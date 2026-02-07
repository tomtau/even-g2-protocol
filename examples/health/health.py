#!/usr/bin/env python3
"""
Even G2 Health Data Display Example

This example demonstrates displaying health data on the G2 glasses,
based on the official health.proto definitions.

Usage:
    python health.py                     # Display all health data
    python health.py --steps 5000        # Display step count
    python health.py --calories 1500     # Display calories
    python health.py --heart-rate 72     # Display heart rate
"""

import argparse
import asyncio
import struct
from bleak import BleakClient, BleakScanner

# BLE UUIDs
UART_SERVICE_UUID = "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
UART_TX_UUID = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"  # Write
UART_RX_UUID = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"  # Notify

# G2 Protocol Constants
SERVICE_HEALTH = 0x0E  # UI_HEALTH_APP_ID = 14

# Health data types from health.proto
HEALTH_TYPE_ALL = 1
HEALTH_TYPE_STEPS = 2
HEALTH_TYPE_CALORIES = 3
HEALTH_TYPE_SLEEP = 4
HEALTH_TYPE_HEART_RATE = 5
HEALTH_TYPE_BLOOD_OXYGEN = 6
HEALTH_TYPE_TEMPERATURE = 7
HEALTH_TYPE_HRV = 8
HEALTH_TYPE_PRODUCTIVITY = 9

# Health command IDs from health.proto
HEALTH_CMD_SINGLE_DATA = 1
HEALTH_CMD_MULT_DATA = 2
HEALTH_CMD_SINGLE_HIGHLIGHT = 3
HEALTH_CMD_MULT_HIGHLIGHT = 4


def crc16_ccitt(data: bytes) -> int:
    """Calculate CRC-16/CCITT."""
    crc = 0xFFFF
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            if crc & 0x8000:
                crc = (crc << 1) ^ 0x1021
            else:
                crc <<= 1
            crc &= 0xFFFF
    return crc


def encode_varint(value: int) -> bytes:
    """Encode an integer as a protobuf varint."""
    result = []
    while value > 0x7F:
        result.append((value & 0x7F) | 0x80)
        value >>= 7
    result.append(value)
    return bytes(result)


def build_health_single_data(
    data_type: int,
    value: float,
    goal: int = 0,
    avg_value: float = 0.0,
    duration: int = 0,
    seq: int = 0x20,
    msg_id: int = 0x50
) -> bytes:
    """
    Build a health single data packet.
    
    Based on health.proto:
    message HealthSingleData {
        eHealthDataType dataType = 1;
        int32 goal = 2;
        float value = 3;
        float avgValue = 4;
        int32 duration = 5;
        eErrorCode errorCode = 6;
    }
    """
    # Build HealthSingleData message
    single_data = bytearray()
    
    # Field 1: dataType (varint)
    single_data.extend([0x08])  # field 1, wire type 0
    single_data.extend(encode_varint(data_type))
    
    # Field 2: goal (varint)
    single_data.extend([0x10])  # field 2, wire type 0
    single_data.extend(encode_varint(goal))
    
    # Field 3: value (fixed32 float)
    single_data.extend([0x1D])  # field 3, wire type 5
    single_data.extend(struct.pack('<f', value))
    
    # Field 4: avgValue (fixed32 float)
    single_data.extend([0x25])  # field 4, wire type 5
    single_data.extend(struct.pack('<f', avg_value))
    
    # Field 5: duration (varint)
    single_data.extend([0x28])  # field 5, wire type 0
    single_data.extend(encode_varint(duration))
    
    # Field 6: errorCode = SUCCESS (0)
    single_data.extend([0x30, 0x00])
    
    # Build HealthDataPackage
    payload = bytearray()
    
    # Field 1: commandId = HEALTH_CMD_SINGLE_DATA (1)
    payload.extend([0x08, HEALTH_CMD_SINGLE_DATA])
    
    # Field 2: magicRandom (message ID)
    payload.extend([0x10])
    payload.extend(encode_varint(msg_id))
    
    # Field 3: singleData (embedded message)
    payload.extend([0x1A])  # field 3, wire type 2
    payload.extend(encode_varint(len(single_data)))
    payload.extend(single_data)
    
    # Build transport packet
    service = bytes([SERVICE_HEALTH, 0x20])  # Health service with sub-ID
    pkt_info = bytes([0x01, 0x01])  # Single packet
    length = len(pkt_info) + len(service) + len(payload)
    
    header = bytes([0xAA, 0x21, seq, length])
    full_payload = pkt_info + service + bytes(payload)
    
    crc = crc16_ccitt(full_payload)
    
    return header + full_payload + struct.pack('<H', crc)


def build_health_highlight(
    data_type: int,
    text: str,
    seq: int = 0x20,
    msg_id: int = 0x50
) -> bytes:
    """
    Build a health highlight packet for dashboard display.
    
    Based on health.proto:
    message HealthSingleHighlight {
        eHealthDataType dataType = 1;
        bytes text = 2;
        eErrorCode errorCode = 3;
    }
    """
    text_bytes = text.encode('utf-8')
    
    # Build HealthSingleHighlight message
    highlight = bytearray()
    
    # Field 1: dataType
    highlight.extend([0x08])
    highlight.extend(encode_varint(data_type))
    
    # Field 2: text
    highlight.extend([0x12])
    highlight.extend(encode_varint(len(text_bytes)))
    highlight.extend(text_bytes)
    
    # Field 3: errorCode = SUCCESS
    highlight.extend([0x18, 0x00])
    
    # Build HealthDataPackage
    payload = bytearray()
    
    # Field 1: commandId = HEALTH_CMD_SINGLE_HIGHLIGHT (3)
    payload.extend([0x08, HEALTH_CMD_SINGLE_HIGHLIGHT])
    
    # Field 2: magicRandom
    payload.extend([0x10])
    payload.extend(encode_varint(msg_id))
    
    # Field 5: singleHighlight
    payload.extend([0x2A])  # field 5, wire type 2
    payload.extend(encode_varint(len(highlight)))
    payload.extend(highlight)
    
    # Build transport packet
    service = bytes([SERVICE_HEALTH, 0x20])
    pkt_info = bytes([0x01, 0x01])
    length = len(pkt_info) + len(service) + len(payload)
    
    header = bytes([0xAA, 0x21, seq, length])
    full_payload = pkt_info + service + bytes(payload)
    
    crc = crc16_ccitt(full_payload)
    
    return header + full_payload + struct.pack('<H', crc)


async def find_g2_glasses():
    """Find G2 glasses by name."""
    print("Scanning for Even G2 glasses...")
    devices = await BleakScanner.discover(timeout=5.0)
    
    for device in devices:
        name = device.name or ""
        if "G2" in name or "Even" in name:
            print(f"Found: {device.name} ({device.address})")
            return device
    
    return None


async def send_health_data(args):
    """Send health data to G2 glasses."""
    device = await find_g2_glasses()
    
    if not device:
        print("G2 glasses not found. Make sure they are powered on and in range.")
        return
    
    async with BleakClient(device.address) as client:
        print(f"Connected to {device.name}")
        
        seq = 0x20
        msg_id = 0x50
        
        # Determine what data to send
        if args.steps is not None:
            print(f"Sending steps: {args.steps}")
            packet = build_health_single_data(
                HEALTH_TYPE_STEPS, 
                float(args.steps),
                goal=args.goal or 10000,
                seq=seq,
                msg_id=msg_id
            )
            await client.write_gatt_char(UART_TX_UUID, packet)
            msg_id += 1
            
            # Also send highlight
            packet = build_health_highlight(
                HEALTH_TYPE_STEPS,
                f"{args.steps:,} steps",
                seq=seq + 1,
                msg_id=msg_id
            )
            await client.write_gatt_char(UART_TX_UUID, packet)
            
        elif args.calories is not None:
            print(f"Sending calories: {args.calories}")
            packet = build_health_highlight(
                HEALTH_TYPE_CALORIES,
                f"{args.calories} kcal",
                seq=seq,
                msg_id=msg_id
            )
            await client.write_gatt_char(UART_TX_UUID, packet)
            
        elif args.heart_rate is not None:
            print(f"Sending heart rate: {args.heart_rate} bpm")
            packet = build_health_single_data(
                HEALTH_TYPE_HEART_RATE,
                float(args.heart_rate),
                seq=seq,
                msg_id=msg_id
            )
            await client.write_gatt_char(UART_TX_UUID, packet)
            msg_id += 1
            
            packet = build_health_highlight(
                HEALTH_TYPE_HEART_RATE,
                f"{args.heart_rate} bpm",
                seq=seq + 1,
                msg_id=msg_id
            )
            await client.write_gatt_char(UART_TX_UUID, packet)
            
        else:
            # Send example data
            print("Sending example health data...")
            
            data_items = [
                (HEALTH_TYPE_STEPS, "5,432 steps"),
                (HEALTH_TYPE_CALORIES, "1,234 kcal"),
                (HEALTH_TYPE_HEART_RATE, "72 bpm"),
            ]
            
            for dtype, text in data_items:
                packet = build_health_highlight(dtype, text, seq=seq, msg_id=msg_id)
                await client.write_gatt_char(UART_TX_UUID, packet)
                seq += 1
                msg_id += 1
                await asyncio.sleep(0.1)
        
        print("Health data sent successfully!")
        await asyncio.sleep(1)


def main():
    parser = argparse.ArgumentParser(description="Display health data on G2 glasses")
    parser.add_argument("--steps", type=int, help="Step count to display")
    parser.add_argument("--calories", type=int, help="Calories to display")
    parser.add_argument("--heart-rate", type=int, help="Heart rate (bpm) to display")
    parser.add_argument("--goal", type=int, help="Goal value (for step count)")
    
    args = parser.parse_args()
    
    try:
        asyncio.run(send_health_data(args))
    except KeyboardInterrupt:
        print("\nCancelled")


if __name__ == "__main__":
    main()
