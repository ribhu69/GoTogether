#!/bin/bash
# Start the GoTogether server and print connection URLs for all device types.
set -e

PORT="${1:-8080}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Find LAN IP
LAN_IP=$(python3 -c "
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try:
    s.connect(('8.8.8.8', 80))
    print(s.getsockname()[0])
finally:
    s.close()
" 2>/dev/null || echo "unknown")

echo ""
echo "═══════════════════════════════════════════"
echo "  GoTogether Server"
echo "═══════════════════════════════════════════"
echo ""
echo "  iOS Simulator:    http://localhost:$PORT"
echo "  Android Emulator: http://10.0.2.2:$PORT"
echo "  Real device:      http://$LAN_IP:$PORT"
echo ""
echo "  Health:  http://localhost:$PORT/api/health"
echo "═══════════════════════════════════════════"
echo ""

cd "$SCRIPT_DIR"
python3 server.py "$PORT"