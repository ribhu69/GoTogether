#!/bin/bash
# GoTogether — launch Android emulator + iOS simulators + start server
# Usage: bash scripts/sim.sh [ios|android|all]
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SERVER_PORT="${SERVER_PORT:-8080}"
PLATFORM="${1:-all}"

ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
ADB="$ANDROID_HOME/platform-tools/adb"
EMULATOR="$ANDROID_HOME/emulator/emulator"
AVD_NAME="Pixel_9_Pro_XL"  # change to your preferred AVD

IPHONE_18="6A824587-58D3-4740-AD4D-B22AC87E7B87"
IPHONE_17="319C58B1-7AF5-4681-8DB8-A04631B7A23C"

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

# ═══ Platform builds ═══

build_ios() {
    echo ""
    echo "━━━ Building iOS ━━━"
    cd "$PROJECT_DIR/ios"
    xcodegen generate --quiet 2>&1
    xcodebuild -project GoTogether.xcodeproj -scheme GoTogether \
        -configuration Debug -sdk iphonesimulator \
        -destination "platform=iOS Simulator,id=$IPHONE_18" \
        build 2>&1 | grep -E '(BUILD|error:)' | tail -3
    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "GoTogether.app" \
        -path "*/Debug-iphonesimulator/*" 2>/dev/null | head -1)
    echo "  iOS app: $APP_PATH"

    echo ""
    echo "━━━ Launching iOS simulators ━━━"
    for SIM in "$IPHONE_18" "$IPHONE_17"; do
        xcrun simctl boot "$SIM" 2>/dev/null || true
    done
    sleep 3
    for SIM in "$IPHONE_18" "$IPHONE_17"; do
        xcrun simctl install "$SIM" "$APP_PATH" 2>&1 || true
        xcrun simctl launch "$SIM" com.gotogether.demo 2>&1 || true
    done
}

build_android() {
    echo ""
    echo "━━━ Building Android ━━━"
    cd "$PROJECT_DIR/android"
    ./gradlew assembleDebug 2>&1 | grep -E '(BUILD|Task)' | tail -3

    APK_PATH=$(find "$PROJECT_DIR/android/app/build/outputs" -name "*.apk" 2>/dev/null | head -1)
    echo "  APK: $APK_PATH"

    echo ""
    echo "━━━ Launching Android emulator ━━━"
    # Start emulator in background
    $EMULATOR -avd "$AVD_NAME" -no-snapshot-load &
    EMU_PID=$!
    echo "  Booting $AVD_NAME (PID $EMU_PID)…"

    # Wait for emulator to be ready
    echo -n "  Waiting for device"
    for i in $(seq 1 60); do
        if $ADB get-state 2>/dev/null | grep -q device; then
            echo " ready"
            break
        fi
        echo -n "."
        sleep 2
    done

    # Wait for boot to complete
    $ADB wait-for-device
    while [ "$($ADB shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]; do
        sleep 2
    done
    echo "  Device booted"

    # Install and launch
    $ADB install -r "$APK_PATH" 2>&1 || echo "  (install skipped — may already be installed)"
    $ADB shell am start -n com.gotogether.app/.MainActivity 2>&1 || true
    echo "  App launched"
}

# ═══ Execute ═══

case "$PLATFORM" in
    ios)   build_ios ;;
    android) build_android ;;
    all)
        build_ios
        build_android
        ;;
    *)
        echo "Usage: bash scripts/sim.sh [ios|android|all]"
        exit 1
        ;;
esac

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Server: http://localhost:$SERVER_PORT"
echo "  Dashboard: http://localhost:$SERVER_PORT"
echo "  Press Ctrl+C to stop"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

wait "$SERVER_PID"