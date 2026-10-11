#!/usr/bin/env bash
# Quick audit tool for connected CarPlay Android tablet

mkdir -p out/carplay

echo "Checking connected ADB devices..."
adb devices

DEVICE_COUNT=$(adb devices | grep -v "List" | grep "device$" | wc -l | tr -d ' ')

if [ "$DEVICE_COUNT" -eq "0" ]; then
    echo "No Android device detected. Ensure USB Debugging is enabled on the tablet."
    exit 1
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
SHOT_PATH="out/carplay/shot_${TIMESTAMP}.png"
LATEST_PATH="out/carplay/latest.png"

echo "Capturing CarPlay frame..."
adb exec-out screencap -p > "$SHOT_PATH"
cp "$SHOT_PATH" "$LATEST_PATH"

echo "Saved: $SHOT_PATH"
echo "Latest: $LATEST_PATH"
sips -g pixelWidth -g pixelHeight "$LATEST_PATH"
