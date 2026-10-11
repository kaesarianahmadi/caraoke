---
name: carplay-bridge
description: Headless CarPlay receiver daemon manager. Starts, monitors, and stops PlayPort on macOS, binds local Wi-Fi, and automatically opens the live CarPlay display in the browser.
---

# CarPlay Bridge

Headless CarPlay receiver lifecycle manager for local real-time development and visual testing.

## Capabilities

1. **Auto-Start & Browser Launch (`start`)**: Detects LAN Wi-Fi IP, clears stale ports 7000/8080, launches PlayPort daemon with fixed token (`caraoke`), and opens `http://localhost:8080/?token=caraoke` in Chrome.
2. **Stream Health Diagnostics (`status`)**: Checks port 7000 (AirPlay RTSP) and port 8080 (WebCodecs WebSocket) to verify if iPhone is actively streaming.
3. **Clean Teardown (`stop`)**: Stops server and frees all ports cleanly.

## Usage

```bash
# Start PlayPort daemon and automatically open browser
python3 .zcode/skills/carplay-bridge/bridge.py start

# Check if iPhone is connected and streaming
python3 .zcode/skills/carplay-bridge/bridge.py status

# Stop PlayPort daemon
python3 .zcode/skills/carplay-bridge/bridge.py stop
```
