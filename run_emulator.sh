#!/usr/bin/env bash
set -euo pipefail

# Android SDK paths (adjust if needed)
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"

AVD_NAME="${1:-Pixel2API30}"

echo "[adb] restarting daemon..."
adb kill-server || true
adb start-server

echo "[emulator] launching $AVD_NAME ..."
nohup emulator -avd "$AVD_NAME" -netdelay none -netspeed full -gpu auto -no-snapshot-load >/dev/null 2>&1 &

echo "[adb] waiting for device..."
adb wait-for-device
until adb shell getprop sys.boot_completed 2>/dev/null | grep -q "1"; do
  sleep 2
done
adb devices
echo "[ok] Emulator ready. Run: flutter run -d \$(adb devices | awk '/emulator-/{print \$1; exit}')
"
