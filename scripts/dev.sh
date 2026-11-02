#!/bin/bash
# ──────────────────────────────────────────────────────────
# GoTogether dev launcher
#   1. Starts the server + opens HTML dashboard in browser
#   2. Builds the iOS app
#   3. Installs on real devices (if UDIDs in devices.local)
#      Falls back to opening iPhone + iPad simulators
# ──────────────────────────────────────────────────────────
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SERVER_PORT="${SERVER_PORT:-8080}"
SERVER_URL="http://localhost:$SERVER_PORT"

# ── Device UDIDs (from devices.local — gitignored, never committed) ──
IPHONE_UDID=""
IPAD_UDID=""
if [ -f "$SCRIPT_DIR/devices.local" ]; then
    source "$SCRIPT_DIR/devices.local"
fi

cleanup() {
    echo ""
    echo "Shutting down server (PID $SERVER_PID)..."
    kill "$SERVER_PID" 2>/dev/null
    wait "$SERVER_PID" 2>/dev/null
    echo "Done."
}
trap cleanup EXIT INT TERM

# ══════════════════════════════════════════════════════════
# 1. Start server
# ══════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Starting GoTogether server..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Kill any existing server on the port
lsof -ti:"$SERVER_PORT" | xargs kill -9 2>/dev/null || true

cd "$PROJECT_DIR/server"
python3 server.py "$SERVER_PORT" &
SERVER_PID=$!
sleep 1

echo "  Server:  $SERVER_URL"
echo "  Health:  $SERVER_URL/api/health"

# Open dashboard in browser
if command -v open &>/dev/null; then
    open "$SERVER_URL"
    echo "  Dashboard opened in browser"
fi

# ══════════════════════════════════════════════════════════
# 2. Build iOS app
# ══════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Building iOS app..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "$PROJECT_DIR/ios"
xcodegen generate --quiet 2>&1

echo "  Building GoTogether..."
xcodebuild -project GoTogether.xcodeproj -scheme GoTogether \
    -configuration Debug \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    build 2>&1 | grep -E '(BUILD|error:|warning:)' | tail -5

# ══════════════════════════════════════════════════════════
# 3. Install on devices or open simulators
# ══════════════════════════════════════════════════════════
echo ""
INSTALLED=0

if [ -n "$IPHONE_UDID" ]; then
    echo "━━━ Installing on iPhone ($IPHONE_UDID) ━━━"
    xcodebuild -project GoTogether.xcodeproj -scheme GoTogether \
        -destination "platform=iOS,id=$IPHONE_UDID" \
        -configuration Debug \
        build 2>&1 | grep -E '(BUILD|error:)' | tail -5
    INSTALLED=1
fi

if [ -n "$IPAD_UDID" ]; then
    echo "━━━ Installing on iPad ($IPAD_UDID) ━━━"
    xcodebuild -project GoTogether.xcodeproj -scheme GoTogether \
        -destination "platform=iOS,id=$IPAD_UDID" \
        -configuration Debug \
        build 2>&1 | grep -E '(BUILD|error:)' | tail -5
    INSTALLED=1
fi

if [ "$INSTALLED" -eq 0 ]; then
    echo "  No device UDIDs in scripts/devices.local"
    echo "  → Opening iPhone + iPad simulators instead"
    echo ""

    # Boot simulators if not already booted
    IPHONE_SIM=$(xcrun simctl list devices available iPhone | grep -m1 "iPhone 17" | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')
    IPAD_SIM=$(xcrun simctl list devices available iPad | grep -m1 "iPad" | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')

    if [ -n "$IPHONE_SIM" ]; then
        echo "  iPhone sim: $IPHONE_SIM"
        xcrun simctl boot "$IPHONE_SIM" 2>/dev/null || true
        xcrun simctl install "$IPHONE_SIM" "$PROJECT_DIR/ios/build/GoTogether.app" 2>/dev/null || \
            echo "  (build first — app not found at expected path)"
    fi

    if [ -n "$IPAD_SIM" ]; then
        echo "  iPad sim:   $IPAD_SIM"
        xcrun simctl boot "$IPAD_SIM" 2>/dev/null || true
        xcrun simctl install "$IPAD_SIM" "$PROJECT_DIR/ios/build/GoTogether.app" 2>/dev/null || \
            echo "  (build first — app not found at expected path)"
    fi

    open -a Simulator
fi

# ══════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  All set. Server running on $SERVER_URL"
echo "  Dashboard: $SERVER_URL"
echo "  Press Ctrl+C to stop"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Keep running until Ctrl+C
wait "$SERVER_PID"