#!/usr/bin/env python3
"""
G2 Packet Parser using Official Protobuf Definitions

This script parses G2 BLE packets using the official protobuf definitions
from proto/g2_re/. It demonstrates how to use the compiled proto files
to decode real packet data.

Setup:
    cd proto/g2_re
    protoc --python_out=../../examples/proto_parser *.proto
"""

import sys
import struct
from pathlib import Path

# Service IDs from service_id_def.proto
SERVICE_IDS = {
    0: "UI_DEFAULT_APP_ID",
    1: "UI_BACKGROUND_DASHBOARD_APP_ID",
    3: "UI_FOREGROUND_MEUN_ID",
    4: "UI_FOREGROUND_NOTIFICATION_ID",
    5: "UI_TRANSLATE_APP_ID",
    6: "UI_TELEPROMPT_APP_ID",
    7: "UI_FOREGROUND_EVEN_AI_ID",
    8: "UI_BACKGROUND_NAVIGATION_ID",
    9: "UI_SETTING_APP_ID",
    10: "UI_TRANSCRIBE_APP_ID",
    11: "UI_CONVERSATE_APP_ID",
    12: "UI_QUICKLIST_APP_ID",
    13: "SERVICE_SYNC_INFO_APP_ID",
    14: "UI_HEALTH_APP_ID",
    15: "UI_LOGGER_APP_ID",
    16: "UI_ONBOARDING_APP_ID",
    32: "SERVICE_MODULE_CONFIGURE_APP_ID",
    33: "UI_FOREGROUND_SYSTEM_ALERT_APP_ID",
    128: "UX_DEVICE_SETTINGS_APP_ID",
    129: "UX_GLASSES_CASE_APP_ID",
}

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

def parse_transport_header(data: bytes) -> dict:
    """Parse the G2 BLE transport header."""
    if len(data) < 6:
        return None
    
    result = {
        'prefix': data[0],
        'type': data[1],
        'sync_id': data[2],
        'length': data[3],
    }
    
    if len(data) >= 8:
        result['packet_total'] = data[4]
        result['packet_serial'] = data[5]
        result['service_id'] = data[6]
        result['sub_id'] = data[7] if len(data) > 7 else 0
        
        # Extract payload (after header, before CRC)
        payload_start = 8
        payload_end = 4 + result['length']  # prefix+type+sync+len + length
        if payload_end + 2 <= len(data):
            result['payload'] = data[payload_start:payload_end]
            result['crc'] = struct.unpack('<H', data[payload_end:payload_end+2])[0]
            
            # Verify CRC
            crc_data = data[4:payload_end]
            calculated_crc = crc16_ccitt(crc_data)
            result['crc_valid'] = (calculated_crc == result['crc'])
    
    return result

def parse_protobuf_generic(payload: bytes) -> dict:
    """Parse protobuf payload without compiled protos (generic parsing)."""
    result = {}
    pos = 0
    
    while pos < len(payload):
        if pos >= len(payload):
            break
            
        # Read field tag
        tag_byte = payload[pos]
        field_num = tag_byte >> 3
        wire_type = tag_byte & 0x07
        pos += 1
        
        if wire_type == 0:  # Varint
            value = 0
            shift = 0
            while pos < len(payload):
                b = payload[pos]
                pos += 1
                value |= (b & 0x7F) << shift
                if not (b & 0x80):
                    break
                shift += 7
            result[f"field_{field_num}"] = value
            
        elif wire_type == 2:  # Length-delimited
            if pos >= len(payload):
                break
            length = payload[pos]
            pos += 1
            if pos + length <= len(payload):
                data = payload[pos:pos+length]
                pos += length
                # Try to decode as UTF-8
                try:
                    result[f"field_{field_num}"] = data.decode('utf-8')
                except:
                    result[f"field_{field_num}"] = data.hex()
            
        elif wire_type == 5:  # 32-bit fixed
            if pos + 4 <= len(payload):
                value = struct.unpack('<f', payload[pos:pos+4])[0]
                result[f"field_{field_num}"] = value
                pos += 4
                
        else:
            # Skip unknown wire types
            break
    
    return result

def parse_packet(hex_data: str):
    """Parse a G2 packet from hex string."""
    # Clean up hex string
    hex_data = hex_data.replace(' ', '').replace('\n', '').replace(':', '')
    
    # Handle xxd output format (remove addresses and ASCII)
    lines = hex_data.split('\n')
    clean_hex = ''
    for line in lines:
        # Skip if contains ASCII column
        if '  ' in line:
            line = line.split('  ')[0]
        # Remove address prefix
        if ':' in line:
            line = line.split(':')[1] if ':' in line else line
        clean_hex += line.replace(' ', '')
    
    if not clean_hex:
        clean_hex = hex_data
    
    try:
        data = bytes.fromhex(clean_hex)
    except ValueError as e:
        print(f"Error parsing hex: {e}")
        return
    
    print(f"Raw data ({len(data)} bytes): {data.hex()}")
    print()
    
    # Parse transport header
    header = parse_transport_header(data)
    if not header:
        print("Could not parse transport header")
        return
    
    print("=== Transport Header ===")
    print(f"  Prefix: 0x{header['prefix']:02X}")
    print(f"  Type: 0x{header['type']:02X}")
    print(f"  Sync ID: {header['sync_id']}")
    print(f"  Length: {header['length']}")
    
    if 'packet_total' in header:
        print(f"  Packet: {header['packet_serial']}/{header['packet_total']}")
        
        service_name = SERVICE_IDS.get(header['service_id'], f"Unknown (0x{header['service_id']:02X})")
        print(f"  Service: {service_name} (ID: {header['service_id']})")
        
        if 'crc' in header:
            crc_status = "✓ Valid" if header.get('crc_valid') else "✗ Invalid"
            print(f"  CRC: 0x{header['crc']:04X} ({crc_status})")
    
    print()
    
    # Parse payload
    if 'payload' in header and header['payload']:
        print("=== Payload ===")
        print(f"  Hex: {header['payload'].hex()}")
        print()
        
        # Try generic protobuf parsing
        fields = parse_protobuf_generic(header['payload'])
        if fields:
            print("=== Protobuf Fields (Generic Parse) ===")
            for key, value in fields.items():
                print(f"  {key}: {value}")

def main():
    if len(sys.argv) > 1:
        # Parse hex string from command line
        hex_data = ' '.join(sys.argv[1:])
        parse_packet(hex_data)
    else:
        # Example: Parse the health packet from the problem statement
        print("Example: Parsing health status packet")
        print("=" * 50)
        
        # Health packet from the captured session
        health_packet = """
        aa21209301010e200802105e228a01080112150802109
        04e1d0000000025000000002800300038001215080310
        d00f1d0000000025000000002800300038001214080410
        001d00000000250000000028003000380012140805100
        01d000000002500000000280030003800121408061000
        1d00000000250000000028003000380012140809100
        01d00000000250000000028003000380018005649
        """
        
        parse_packet(health_packet)

if __name__ == "__main__":
    main()
