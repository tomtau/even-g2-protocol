#!/usr/bin/env python3
"""
Even G2 Navigation - Send Turn-by-Turn Navigation to Glasses

Sends navigation updates with distance, instructions, ETA, and maneuver icons.

Usage:
    python navigation.py "86 m" "Turn left" "7 min" "701 m" "ETA: 13:07"
    python navigation.py --demo  # Run demo sequence

Requirements:
    pip install bleak
"""

import asyncio
import sys
import time
from bleak import BleakClient, BleakScanner
from enum import IntEnum
from typing import Optional

# BLE UUIDs for Even G2
UUID_BASE = "00002760-08c2-11e1-9073-0e8ac72e{:04x}"
CHAR_WRITE = UUID_BASE.format(0x5401)
CHAR_NOTIFY = UUID_BASE.format(0x5402)


class ManeuverIcon(IntEnum):
    """Navigation maneuver icon types."""
    TURN_LEFT = 1
    TURN_RIGHT = 2
    STRAIGHT = 3
    U_TURN = 4


def crc16_ccitt(data: bytes) -> int:
    """CRC-16/CCITT for packet framing."""
    crc = 0xFFFF
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) if crc & 0x8000 else (crc << 1)
            crc &= 0xFFFF
    return crc


def encode_varint(value: int) -> bytes:
    """Encode integer as protobuf varint."""
    result = []
    while value > 0x7F:
        result.append((value & 0x7F) | 0x80)
        value >>= 7
    result.append(value & 0x7F)
    return bytes(result)


def encode_string(tag: int, value: str) -> bytes:
    """Encode a string field with tag and length prefix."""
    data = value.encode('utf-8')
    if len(data) > 255:
        raise ValueError(f"String too long ({len(data)} bytes, max 255)")
    return bytes([tag, len(data)]) + data


def build_auth_packets() -> list:
    """Build the 7-packet authentication sequence."""
    timestamp = int(time.time())
    ts_varint = encode_varint(timestamp)
    txid = bytes([0xE8, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01])
    
    def add_crc(packet: bytes) -> bytes:
        crc = crc16_ccitt(packet[8:])
        return packet + bytes([crc & 0xFF, (crc >> 8) & 0xFF])
    
    packets = []
    
    # Auth 1-7
    packets.append(add_crc(bytes([
        0xAA, 0x21, 0x01, 0x0C, 0x01, 0x01, 0x80, 0x00,
        0x08, 0x04, 0x10, 0x0C, 0x1A, 0x04, 0x08, 0x01, 0x10, 0x04
    ])))
    packets.append(add_crc(bytes([
        0xAA, 0x21, 0x02, 0x0A, 0x01, 0x01, 0x80, 0x20,
        0x08, 0x05, 0x10, 0x0E, 0x22, 0x02, 0x08, 0x02
    ])))
    
    payload3 = bytes([0x08, 0x80, 0x01, 0x10, 0x0F, 0x82, 0x08, 0x11, 0x08]) + ts_varint + bytes([0x10]) + txid
    packets.append(add_crc(bytes([0xAA, 0x21, 0x03, len(payload3) + 2, 0x01, 0x01, 0x80, 0x20]) + payload3))
    
    packets.append(add_crc(bytes([
        0xAA, 0x21, 0x04, 0x0C, 0x01, 0x01, 0x80, 0x00,
        0x08, 0x04, 0x10, 0x10, 0x1A, 0x04, 0x08, 0x01, 0x10, 0x04
    ])))
    packets.append(add_crc(bytes([
        0xAA, 0x21, 0x05, 0x0C, 0x01, 0x01, 0x80, 0x00,
        0x08, 0x04, 0x10, 0x11, 0x1A, 0x04, 0x08, 0x01, 0x10, 0x04
    ])))
    packets.append(add_crc(bytes([
        0xAA, 0x21, 0x06, 0x0A, 0x01, 0x01, 0x80, 0x20,
        0x08, 0x05, 0x10, 0x12, 0x22, 0x02, 0x08, 0x01
    ])))
    
    payload7 = bytes([0x08, 0x80, 0x01, 0x10, 0x13, 0x82, 0x08, 0x11, 0x08]) + ts_varint + bytes([0x10]) + txid
    packets.append(add_crc(bytes([0xAA, 0x21, 0x07, len(payload7) + 2, 0x01, 0x01, 0x80, 0x20]) + payload7))
    
    return packets


def build_navigation_packet(
    distance: str,
    instruction: str,
    time_remaining: str,
    total_distance: str,
    eta: str,
    speed: str = "0.0 km/h",
    icon_type: ManeuverIcon = ManeuverIcon.TURN_LEFT,
    sequence: int = 0x10
) -> bytes:
    """
    Build a G2 navigation packet.
    
    Args:
        distance: Distance to next maneuver (e.g., "86 m")
        instruction: Turn instruction (e.g., "Turn left")
        time_remaining: Time to destination (e.g., "7 min")
        total_distance: Total remaining distance (e.g., "701 m")
        eta: Arrival time (e.g., "ETA: 13:07")
        speed: Current speed (e.g., "0.0 km/h")
        icon_type: Maneuver icon type
        sequence: Packet sequence number
        
    Returns:
        Complete navigation packet bytes
    """
    # Build navigation fields
    nav_fields = b''
    nav_fields += bytes([0x08, 0x04])  # Distance container tag
    nav_fields += encode_string(0x12, distance)
    nav_fields += encode_string(0x1a, instruction)
    nav_fields += encode_string(0x22, time_remaining)
    nav_fields += encode_string(0x2a, total_distance)
    nav_fields += encode_string(0x32, eta)
    nav_fields += encode_string(0x3a, speed)
    nav_fields += bytes([0x40, icon_type])
    
    # Wrap in container (0x08 0x07 = state=7, 0x2a = field 5, length, data)
    if len(nav_fields) > 255:
        raise ValueError(f"Navigation payload too large ({len(nav_fields)} bytes, max 255)")
    payload = bytes([0x08, 0x07, 0x2a, len(nav_fields)]) + nav_fields
    
    # Build packet
    service = bytes([0x08, 0x20])  # Navigation service
    pkt_info = bytes([0x01, 0x01])  # Single packet
    full_payload = pkt_info + service + payload
    
    if len(full_payload) + 2 > 255:
        raise ValueError(f"Packet too large ({len(full_payload) + 2} bytes, max 255)")
    header = bytes([0xAA, 0x21, sequence, len(full_payload) + 2])
    
    # Calculate CRC
    crc = crc16_ccitt(full_payload)
    
    return header + full_payload + bytes([crc & 0xFF, (crc >> 8) & 0xFF])


async def send_navigation(
    client: BleakClient,
    distance: str,
    instruction: str,
    time_remaining: str,
    total_distance: str,
    eta: str,
    speed: str = "0.0 km/h",
    icon_type: ManeuverIcon = ManeuverIcon.TURN_LEFT,
    sequence: int = 0x10
):
    """Send a navigation update to the glasses."""
    packet = build_navigation_packet(
        distance=distance,
        instruction=instruction,
        time_remaining=time_remaining,
        total_distance=total_distance,
        eta=eta,
        speed=speed,
        icon_type=icon_type,
        sequence=sequence
    )
    
    await client.write_gatt_char(CHAR_WRITE, packet, response=False)
    print(f"  Sent: {instruction} in {distance}")


async def run_demo(client: BleakClient):
    """Run a demo navigation sequence."""
    print("\nRunning navigation demo...")
    
    demo_steps = [
        ("200 m", "Turn left onto Main St", "12 min", "2.1 km", "ETA: 14:32", ManeuverIcon.TURN_LEFT),
        ("150 m", "Turn left onto Main St", "12 min", "2.0 km", "ETA: 14:32", ManeuverIcon.TURN_LEFT),
        ("100 m", "Turn left onto Main St", "11 min", "1.9 km", "ETA: 14:32", ManeuverIcon.TURN_LEFT),
        ("50 m", "Turn left onto Main St", "11 min", "1.85 km", "ETA: 14:32", ManeuverIcon.TURN_LEFT),
        ("300 m", "Continue straight", "10 min", "1.8 km", "ETA: 14:32", ManeuverIcon.STRAIGHT),
        ("250 m", "Continue straight", "10 min", "1.75 km", "ETA: 14:32", ManeuverIcon.STRAIGHT),
        ("200 m", "Turn right onto Oak Ave", "9 min", "1.5 km", "ETA: 14:32", ManeuverIcon.TURN_RIGHT),
        ("100 m", "Turn right onto Oak Ave", "9 min", "1.4 km", "ETA: 14:32", ManeuverIcon.TURN_RIGHT),
        ("50 m", "Turn right onto Oak Ave", "8 min", "1.35 km", "ETA: 14:32", ManeuverIcon.TURN_RIGHT),
        ("500 m", "Your destination is ahead", "5 min", "500 m", "ETA: 14:30", ManeuverIcon.STRAIGHT),
    ]
    
    seq = 0x10
    for distance, instruction, time_rem, total_dist, eta, icon in demo_steps:
        await send_navigation(
            client,
            distance=distance,
            instruction=instruction,
            time_remaining=time_rem,
            total_distance=total_dist,
            eta=eta,
            icon_type=icon,
            sequence=seq
        )
        seq += 1
        await asyncio.sleep(2.0)  # 2 second between updates
    
    print("\nDemo complete!")


async def main():
    args = sys.argv[1:]
    
    print("Even G2 Navigation")
    print("=" * 40)
    
    # Parse arguments
    demo_mode = "--demo" in args
    
    if not demo_mode and len(args) < 5:
        print("\nUsage:")
        print('  python navigation.py "86 m" "Turn left" "7 min" "701 m" "ETA: 13:07"')
        print("  python navigation.py --demo")
        return
    
    print("\nScanning for G2 glasses...")
    devices = await BleakScanner.discover(timeout=10.0)
    
    # Find left eye (primary for navigation)
    g2_device = next(
        (d for d in devices if d.name and "G2" in d.name and "_L_" in d.name),
        None
    )
    
    if not g2_device:
        g2_device = next(
            (d for d in devices if d.name and "G2" in d.name),
            None
        )
    
    if not g2_device:
        print("ERROR: No G2 glasses found!")
        return
    
    print(f"  Found: {g2_device.name}")
    
    async with BleakClient(g2_device) as client:
        print("\nConnected!")
        
        # Enable notifications
        await client.start_notify(CHAR_NOTIFY, lambda s, d: None)
        
        # Authenticate
        print("\nAuthenticating...")
        for pkt in build_auth_packets():
            await client.write_gatt_char(CHAR_WRITE, pkt, response=False)
            await asyncio.sleep(0.1)
        await asyncio.sleep(0.5)
        print("  Authenticated!")
        
        if demo_mode:
            await run_demo(client)
        else:
            # Single navigation update
            distance = args[0]
            instruction = args[1]
            time_remaining = args[2]
            total_distance = args[3]
            eta = args[4]
            
            print(f"\nSending navigation update...")
            await send_navigation(
                client,
                distance=distance,
                instruction=instruction,
                time_remaining=time_remaining,
                total_distance=total_distance,
                eta=eta
            )
            print("\nDone! Check your glasses.")
        
        await asyncio.sleep(2.0)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nInterrupted")
