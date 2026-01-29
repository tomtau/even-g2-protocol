#!/usr/bin/env python3
"""
Even G2 Translation - Real-time Speech Translation

Enables translation mode on G2 glasses and displays translation results.

Usage:
    python translation.py CS EN     # Czech to English
    python translation.py HK EN     # Cantonese to English
    python translation.py --list    # Show available languages

Requirements:
    pip install bleak
"""

import asyncio
import sys
import time
from bleak import BleakClient, BleakScanner
from enum import Enum
from typing import Optional

# BLE UUIDs for Even G2
UUID_BASE = "00002760-08c2-11e1-9073-0e8ac72e{:04x}"
CHAR_WRITE = UUID_BASE.format(0x5401)
CHAR_NOTIFY = UUID_BASE.format(0x5402)


# Common language codes
LANGUAGES = {
    'EN': 'English',
    'CS': 'Czech',
    'HK': 'Cantonese (Hong Kong)',
    'ZH': 'Mandarin Chinese',
    'JA': 'Japanese',
    'KO': 'Korean',
    'ES': 'Spanish',
    'FR': 'French',
    'DE': 'German',
    'IT': 'Italian',
    'PT': 'Portuguese',
    'RU': 'Russian',
    'AR': 'Arabic',
}


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


def build_packet(seq: int, svc_hi: int, svc_lo: int, payload: bytes) -> bytes:
    """Build a complete G2 packet with header and CRC."""
    header = bytes([0xAA, 0x21, seq, len(payload) + 2, 0x01, 0x01, svc_hi, svc_lo])
    full = header + payload
    crc = crc16_ccitt(payload)
    return full + bytes([crc & 0xFF, (crc >> 8) & 0xFF])


def build_auth_packets() -> list:
    """Build the 7-packet authentication sequence."""
    timestamp = int(time.time())
    ts_varint = encode_varint(timestamp)
    txid = bytes([0xE8, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01])
    
    def add_crc(packet: bytes) -> bytes:
        crc = crc16_ccitt(packet[8:])
        return packet + bytes([crc & 0xFF, (crc >> 8) & 0xFF])
    
    packets = []
    
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


def build_translation_enable(seq: int, msg_id: int, source: str, target: str) -> bytes:
    """
    Build packet to enable translation with specified language pair.
    
    Args:
        seq: Packet sequence number
        msg_id: Message ID
        source: Source language code (e.g., "CS")
        target: Target language code (e.g., "EN")
    
    Returns:
        Complete packet bytes
    """
    lang_pair = f"{source}>{target}".encode('utf-8')
    
    # Mode data: 08 01 12 len lang 18 01
    mode_data = bytes([0x08, 0x01, 0x12, len(lang_pair)]) + lang_pair + bytes([0x18, 0x01])
    
    # Payload: 08 01 10 msg_id 1A len mode_data
    payload = bytes([0x08, 0x01, 0x10, msg_id, 0x1A, len(mode_data)]) + mode_data
    
    return build_packet(seq, 0x05, 0x20, payload)


def build_translation_disable(seq: int, msg_id: int) -> bytes:
    """
    Build packet to disable translation.
    
    Args:
        seq: Packet sequence number
        msg_id: Message ID
    
    Returns:
        Complete packet bytes
    """
    # Mode data: 08 02
    mode_data = bytes([0x08, 0x02])
    
    # Payload: 08 01 10 msg_id 1A len mode_data
    payload = bytes([0x08, 0x01, 0x10, msg_id, 0x1A, len(mode_data)]) + mode_data
    
    return build_packet(seq, 0x05, 0x20, payload)


def parse_translation_result(data: bytes) -> Optional[dict]:
    """
    Parse translation result from notification data.
    
    Returns dict with keys: original, translation, is_final
    """
    # Skip header (AA 21 seq len 01 01 05 20)
    if len(data) < 10:
        return None
    
    # Find service 05 20
    try:
        idx = data.index(bytes([0x05, 0x20]))
        payload = data[idx + 2:-2]  # Skip service and CRC
    except ValueError:
        return None
    
    if len(payload) < 4 or payload[0] != 0x08 or payload[1] != 0x02:
        return None
    
    result = {}
    idx = 2
    
    while idx < len(payload):
        tag = payload[idx]
        
        if tag == 0x10:  # Message ID
            idx += 1
            if idx < len(payload):
                result['msg_id'] = payload[idx]
                idx += 1
        
        elif tag == 0x22:  # Translation content
            idx += 1
            if idx >= len(payload):
                break
            content_len = payload[idx]
            idx += 1
            content = payload[idx:idx + content_len]
            idx += content_len
            
            # Parse content: 0A len original 12 len translation
            cidx = 0
            if cidx < len(content) and content[cidx] == 0x0A:
                cidx += 1
                if cidx >= len(content):
                    continue
                orig_len = content[cidx]
                cidx += 1
                result['original'] = content[cidx:cidx + orig_len].decode('utf-8', errors='replace')
                cidx += orig_len
                
                if cidx < len(content) and content[cidx] == 0x12:
                    cidx += 1
                    if cidx >= len(content):
                        continue
                    trans_len = content[cidx]
                    cidx += 1
                    result['translation'] = content[cidx:cidx + trans_len].decode('utf-8', errors='replace')
        
        elif tag == 0x18:
            idx += 2
        
        elif tag == 0x20:  # Final flag
            idx += 1
            if idx < len(payload):
                result['is_final'] = payload[idx] == 0x01
                idx += 1
        
        elif tag == 0x2A:  # Speaker info
            idx += 1
            if idx >= len(payload):
                break
            spk_len = payload[idx]
            idx += 1
            idx += spk_len
        
        else:
            idx += 1
    
    return result if 'original' in result else None


class TranslationHandler:
    """Handles translation session with G2 glasses."""
    
    def __init__(self, source: str, target: str):
        self.source = source.upper()
        self.target = target.upper()
        self.seq = 0x10
        self.msg_id = 0x50
        self.translation_count = 0
    
    def handle_notification(self, sender, data: bytes):
        """Handle BLE notification data."""
        result = parse_translation_result(data)
        if result:
            self.translation_count += 1
            final = "[FINAL]" if result.get('is_final') else "[...]"
            print(f"\n{final} Original: {result.get('original', '')}")
            print(f"      Translation: {result.get('translation', '')}")


async def main():
    args = sys.argv[1:]
    
    if '--list' in args or '-l' in args:
        print("Available language codes:")
        print("-" * 40)
        for code, name in LANGUAGES.items():
            print(f"  {code}: {name}")
        print("\nUsage: python translation.py SOURCE TARGET")
        print("Example: python translation.py CS EN")
        return
    
    if len(args) < 2:
        print("Even G2 Translation")
        print("=" * 40)
        print("\nUsage:")
        print("  python translation.py SOURCE TARGET")
        print("  python translation.py --list")
        print("\nExamples:")
        print("  python translation.py CS EN    # Czech to English")
        print("  python translation.py HK EN    # Cantonese to English")
        return
    
    source = args[0].upper()
    target = args[1].upper()
    
    print("Even G2 Translation")
    print("=" * 40)
    print(f"\nLanguage: {LANGUAGES.get(source, source)} → {LANGUAGES.get(target, target)}")
    
    print("\nScanning for G2 glasses...")
    devices = await BleakScanner.discover(timeout=10.0)
    
    # Find left eye (primary)
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
    
    handler = TranslationHandler(source, target)
    
    async with BleakClient(g2_device) as client:
        print("\nConnected!")
        
        # Enable notifications
        await client.start_notify(CHAR_NOTIFY, handler.handle_notification)
        
        # Authenticate
        print("\nAuthenticating...")
        for pkt in build_auth_packets():
            await client.write_gatt_char(CHAR_WRITE, pkt, response=False)
            await asyncio.sleep(0.1)
        await asyncio.sleep(0.5)
        print("  Authenticated!")
        
        # Enable translation
        print(f"\nEnabling {source}>{target} translation...")
        enable_pkt = build_translation_enable(handler.seq, handler.msg_id, source, target)
        await client.write_gatt_char(CHAR_WRITE, enable_pkt, response=False)
        handler.seq += 1
        handler.msg_id += 1
        
        print("\nTranslation active! Speak to see results.")
        print("Press Ctrl+C to stop.\n")
        
        try:
            while True:
                await asyncio.sleep(1)
        except asyncio.CancelledError:
            pass
        finally:
            # Disable translation
            print("\n\nDisabling translation...")
            disable_pkt = build_translation_disable(handler.seq, handler.msg_id)
            await client.write_gatt_char(CHAR_WRITE, disable_pkt, response=False)
            await asyncio.sleep(0.5)
            print(f"Done! Received {handler.translation_count} translation(s).")


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nInterrupted")
