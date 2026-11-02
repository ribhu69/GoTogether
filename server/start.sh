#!/bin/bash
# Start the GoTogether server and print connection URLs for all device types.
set -e

PORT="${1:-8080}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Find all candidate IPs ──────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════"
echo "  GoTogether Server"
echo "═══════════════════════════════════════════"
echo ""
echo "  Server listening on:  http://0.0.0.0:$PORT"
echo ""

# Show every IPv4 address on common interfaces
found=0
for iface in en0 en1 en2 en3; do
  ip=$(ifconfig "$iface" 2>/dev/null | awk '/inet / {print $2}')
  if [ -n "$ip" ] && [ "$ip" != "127.0.0.1" ]; then
    found=1
    label="WiFi"
    [ "$iface" != "en0" ] && label="$iface"
    echo "  $label:  http://$ip:$PORT"
  fi
done

# Also show the routed IP (might be VPN)
ROUTED_IP=$(python3 -c "
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try:
    s.connect(('8.8.8.8', 80))
    print(s.getsockname()[0])
finally:
    s.close()
" 2>/dev/null || echo "")

if [ -n "$ROUTED_IP" ] && [ "$ROUTED_IP" != "127.0.0.1" ]; then
  # Check if this is NOT one of the en* IPs (i.e. it's VPN)
  is_vpn=1
  for iface in en0 en1 en2 en3; do
    ip=$(ifconfig "$iface" 2>/dev/null | awk '/inet / {print $2}')
    if [ "$ip" = "$ROUTED_IP" ]; then is_vpn=0; break; fi
  done
  if [ $is_vpn -eq 1 ]; then
    echo "  VPN (routed):       http://$ROUTED_IP:$PORT  ⚠️ likely won't work for LAN"
  fi
fi

echo ""
echo "  Simulator:           http://localhost:$PORT"
echo "  Health check:        http://localhost:$PORT/api/health"
echo ""
if [ $found -eq 1 ]; then
  echo "  👆 Use the WiFi IP above for real devices on the same network."
  echo "     If you're on VPN the routed IP may be wrong — use the WiFi one."
else
  echo "  ⚠️  No WiFi IP found. Check your network connection."
fi
echo "═══════════════════════════════════════════"
echo ""

# ── QR code for the first WiFi IP ─────────────────────────────────────
QR_URL=""
for iface in en0 en1 en2 en3; do
  ip=$(ifconfig "$iface" 2>/dev/null | awk '/inet / {print $2}')
  if [ -n "$ip" ] && [ "$ip" != "127.0.0.1" ]; then
    QR_URL="http://$ip:$PORT"
    break
  fi
done

if [ -n "$QR_URL" ]; then
  echo "  📱 Scan this QR code with your device to fill in the server URL:"
  echo ""
  python3 "$SCRIPT_DIR/qr_terminal.py" "$QR_URL" 2>/dev/null || echo "  (install qrcode: pip install qrcode)"
  echo ""
fi

cd "$SCRIPT_DIR"
python3 server.py "$PORT"