#!/usr/bin/env python3
"""
Even G2 Gesture Handler - Detect and Handle Touch Gestures

Listens for gesture events from G2 glasses and handles tap, swipe, and long press.

Usage:
    python gesture_handler.py

Requirements:
    pip install bleak
"""

import asyncio
import time
from bleak import BleakClient, BleakScanner
from enum import Enum
from typing import Callable, Optional

# BLE UUIDs for Even G2
UUID_BASE = "00002760-08c2-11e1-9073-0e8ac72e{:04x}"
CHAR_NOTIFY = UUID_BASE.format(0x5402)


class G2Gesture(Enum):
    """Gesture types detected from G2 packets."""
    TAP = "tap"
    SWIPE_FORWARD = "swipe_forward"
    SWIPE_BACKWARD = "swipe_backward"
    LONG_PRESS = "long_press"


def detect_gesture(data: bytes) -> Optional[G2Gesture]:
    """
    Detect gesture type from G2 packet bytes.
    
    Args:
        data: Raw BLE packet data
        
    Returns:
        Detected gesture type or None if no gesture detected
    """
    packet_hex = data.hex()
    
    # Long press (service 0d01)
    if "01010d01" in packet_hex and "1a0408011003" in packet_hex:
        return G2Gesture.LONG_PRESS
    
    # Check for gesture patterns in status packets (service 0101)
    if "320d" in packet_hex:
        if "12040801" in packet_hex:
            return G2Gesture.SWIPE_FORWARD
        elif "12040802" in packet_hex:
            return G2Gesture.SWIPE_BACKWARD
    
    if "320b" in packet_hex and "08011202" in packet_hex:
        return G2Gesture.TAP
    
    return None


class DoubleTapDetector:
    """
    Detects double taps from single tap events.
    
    Since single and double taps are identical at the protocol level,
    this class implements timing-based double-tap detection.
    """
    
    def __init__(
        self,
        double_tap_threshold: float = 0.3,
        on_single_tap: Optional[Callable[[], None]] = None,
        on_double_tap: Optional[Callable[[], None]] = None
    ):
        self.double_tap_threshold = double_tap_threshold
        self.on_single_tap = on_single_tap or (lambda: None)
        self.on_double_tap = on_double_tap or (lambda: None)
        self._last_tap_time: Optional[float] = None
        self._pending_task: Optional[asyncio.Task] = None
    
    async def handle_tap(self):
        """Handle a tap event, detecting single vs double tap."""
        now = time.time()
        
        if self._last_tap_time is not None:
            elapsed = now - self._last_tap_time
            if elapsed < self.double_tap_threshold:
                # Double tap detected
                if self._pending_task:
                    self._pending_task.cancel()
                self._last_tap_time = None
                self.on_double_tap()
                return
        
        # Record tap time and schedule single tap callback
        self._last_tap_time = now
        
        async def delayed_single_tap():
            await asyncio.sleep(self.double_tap_threshold)
            if self._last_tap_time is not None:
                self.on_single_tap()
                self._last_tap_time = None
        
        self._pending_task = asyncio.create_task(delayed_single_tap())


class GestureHandler:
    """
    Main gesture handler for G2 glasses.
    
    Connects to glasses, listens for gesture events, and dispatches callbacks.
    """
    
    def __init__(self):
        self.double_tap_detector = DoubleTapDetector(
            on_single_tap=self._on_single_tap,
            on_double_tap=self._on_double_tap
        )
        self.gesture_counter = 0
    
    def _on_single_tap(self):
        print("  → Single Tap detected!")
    
    def _on_double_tap(self):
        print("  → Double Tap detected!")
    
    def _on_swipe_forward(self):
        print("  → Swipe Forward detected!")
    
    def _on_swipe_backward(self):
        print("  → Swipe Backward detected!")
    
    def _on_long_press(self):
        print("  → Long Press detected!")
    
    async def handle_notification(self, sender, data: bytes):
        """Handle BLE notification data."""
        gesture = detect_gesture(data)
        
        if gesture:
            self.gesture_counter += 1
            print(f"\n[{self.gesture_counter}] Gesture: {gesture.value}")
            print(f"    Raw: {data.hex()[:60]}...")
            
            if gesture == G2Gesture.TAP:
                await self.double_tap_detector.handle_tap()
            elif gesture == G2Gesture.SWIPE_FORWARD:
                self._on_swipe_forward()
            elif gesture == G2Gesture.SWIPE_BACKWARD:
                self._on_swipe_backward()
            elif gesture == G2Gesture.LONG_PRESS:
                self._on_long_press()


async def main():
    print("Even G2 Gesture Handler")
    print("=" * 40)
    
    print("\nScanning for G2 glasses...")
    devices = await BleakScanner.discover(timeout=10.0)
    
    # Find either left or right eye
    g2_device = next(
        (d for d in devices if d.name and "G2" in d.name and "_L_" in d.name),
        None
    )
    
    if not g2_device:
        g2_device = next(
            (d for d in devices if d.name and "G2" in d.name and "_R_" in d.name),
            None
        )
    
    if not g2_device:
        print("ERROR: No G2 glasses found!")
        for d in devices:
            if d.name:
                print(f"  Found: {d.name}")
        return
    
    print(f"  Found: {g2_device.name}")
    
    handler = GestureHandler()
    
    async with BleakClient(g2_device) as client:
        print("\nConnected!")
        print("\nListening for gestures...")
        print("  - Tap: Touch sensor briefly")
        print("  - Double Tap: Tap twice quickly")
        print("  - Swipe Forward: Swipe towards temple")
        print("  - Swipe Backward: Swipe towards nose")
        print("  - Long Press: Hold touch sensor")
        print("\nPress Ctrl+C to exit.\n")
        
        await client.start_notify(CHAR_NOTIFY, handler.handle_notification)
        
        # Keep running until interrupted
        try:
            while True:
                await asyncio.sleep(1)
        except asyncio.CancelledError:
            pass


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nInterrupted")
