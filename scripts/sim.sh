#!/bin/bash
# GoTogether — launch on two simulators + start server
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SERVER_PORT="${SERVER_PORT:-8080}"

IPHONE_18="6A824587-58D3-4740-AD4D-B22AC87E7B87"   # iPhone 18 Pro Max (iOS 27)
IPHONE_17="319C58B1-7AF5-4681-8DB8-A04631B7A23C"   # iPhone 17 Pro Max (iOS 26.2)

cleanup() {
    echo ""
    echo "Shutting down server..."
    kill "$SERVER_PID" 2>/dev/null
    wait "$SERVER_PID" 2>/dev/null
    echo "Done."
}
trap cleanup EXIT INT TERM

# ═══ 1. Start server ═══
echo "━━━ Starting server ━━━"
lsof -ti:"$SERVER_PORT" | xargs kill -9 2>/dev/null || true
cd "$PROJECT_DIR/server"
python3 server.py "$SERVER_PORT" &
SERVER_PID=$!
sleep 1
echo "  Server: http://localhost:$SERVER_PORT"

# ═══ 2. Build app ═══
echo ""
echo "━━━ Building app ━━━"
cd "$PROJECT_DIR/ios"
xcodegen generate --quiet 2>&1

xcodebuild -project GoTogether.xcodeproj -scheme GoTogether \
    -configuration Debug \
    -sdk iphonesimulator \
    -destination "platform=iOS Simulator,id=$IPHONE_18" \
    build 2>&1 | grep -E '(BUILD|error:)' | tail -3

APP_PATH=$(xcodebuild -project GoTogether.xcodeproj -scheme GoTogether \
    -configuration Debug -sdk iphonesimulator -showBuildSettings 2>/dev/null \
    | grep "CODESIGNING_FOLDER_PATH" | head -1 | awk '{print $3}')

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    # Fallback: find the built app
    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "GoTogether.app" \
        -path "*/Debug-iphonesimulator/*" 2>/dev/null | head -1)
fi

echo "  App: $APP_PATH"

# ═══ 3. Boot simulators + install ═══
echo ""
echo "━━━ Launching simulators ━━━"

for SIM in "$IPHONE_18" "$IPHONE_17"; do
    echo "  Booting $SIM..."
    xcrun simctl boot "$SIM" 2>/dev/null || true
done

# Wait for simulators to finish booting
sleep 3

for SIM in "$IPHONE_18" "$IPHONE_17"; do
    NAME=$(xcrun simctl list devices | grep "$SIM" | sed -E 's/.*\(([0-9.]+)\) \([A-F0-9-]+\).*/\1/' | head -1)
    echo "  Installing on $NAME..."
    xcrun simctl install "$SIM" "$APP_PATH" 2>&1 || echo "    (install skipped — may already be installed)"
    xcrun simctl launch "$SIM" com.gotogether.demo 2>&1 || echo "    (launch skipped)"
done

# ═══ 4. Done ═══
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Both simulators launched"
echo "  Server: http://localhost:$SERVER_PORT"
echo "  Dashboard: http://localhost:$SERVER_PORT"
echo "  Press Ctrl+C to stop"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

wait "$SERVER_PID"