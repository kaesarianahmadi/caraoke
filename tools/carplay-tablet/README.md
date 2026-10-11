# DiPlay CarPlay Tablet Setup

Target: Android Tablet (Android 7.1+, Android 10+ recommended).

## 1. Install APK on Tablet
Send `DiPlay-0.2.15.apk` to the tablet (WhatsApp / Google Drive / USB transfer) and tap to install. Allow unknown sources if prompted.

## 2. Tablet Settings
1. Open **DiPlay**.
2. Grant Bluetooth, Nearby Devices, and Location/Wi-Fi permissions.
3. Turn on the tablet's **Wi-Fi Hotspot** (5 GHz preferred).
4. In DiPlay: **Settings → Connection → Connection setup → Built-in car hotspot**, enter exact hotspot name and password.

## 3. iPhone Connection
1. Turn on iPhone Bluetooth and Wi-Fi.
2. Pair iPhone with tablet via Bluetooth.
3. Tap **Connect phone** in DiPlay.
4. On iPhone, accept the **"Use CarPlay"** prompt.

## 4. Mac Live Control (Optional USB link)
1. On tablet: Enable **Developer Options** (tap Build Number 7 times) → enable **USB Debugging**.
2. Plug tablet to Mac via USB.
3. On Mac:
   ```bash
   brew install android-platform-tools scrcpy
   scrcpy
   ```
   A window opens on Mac showing CarPlay live with full mouse click/touch control.
