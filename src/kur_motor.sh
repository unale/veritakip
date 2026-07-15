#!/bin/bash
# VeriTakip kurulum motoru — "VeriTakip Kur.app" tarafından çağrılır.
# Kullanım: kur_motor.sh <kota_gb> <kesim_gunu> <iphone|android> [--dry]
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
KOTA="${1:-60}"
GUN="${2:-1}"
TEL="${3:-iphone}"
DRY="${4:-}"

case "$KOTA" in (*[!0-9]*|"") echo "HATA: Kota sayı olmalı (örn. 60)"; exit 1;; esac
case "$GUN" in (*[!0-9]*|"") echo "HATA: Kesim günü 1-28 arası olmalı"; exit 1;; esac
[ "$GUN" -ge 1 ] && [ "$GUN" -le 28 ] || { echo "HATA: Kesim günü 1-28 arası olmalı"; exit 1; }

PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then
    echo "PYTHON_YOK"
    exit 2
fi

if [ "$TEL" = "android" ]; then
    ONEKLER='["172.20.10.", "192.168.43.", "192.168.44."]'
else
    ONEKLER='["172.20.10."]'
fi

mkdir -p "$HOME/VeriTakip"
cp "$DIR/veri_takip.py" "$HOME/VeriTakip/"
cp "$DIR/hotspot_proxy.py" "$HOME/VeriTakip/" 2>/dev/null || true
cat > "$HOME/VeriTakip/config.json" <<EOF
{"aylik_kota_gb": $KOTA, "donem_baslangic_gunu": $GUN, "gunluk_uyari_gb": 2.0, "aylik_uyari_yuzde": 80, "hotspot_onekler": $ONEKLER}
EOF

mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/VeriTakip.app"
cp -R "$DIR/VeriTakip.app" "$HOME/Applications/"
xattr -dr com.apple.quarantine "$HOME/Applications/VeriTakip.app" 2>/dev/null || true

UID_="$(id -u)"
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Desktop"
OLCUM="$HOME/Library/LaunchAgents/com.veritakip.olcum.plist"
cat > "$OLCUM" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.veritakip.olcum</string>
    <key>ProgramArguments</key>
    <array><string>$PY</string><string>$HOME/VeriTakip/veri_takip.py</string></array>
    <key>StartInterval</key><integer>60</integer>
    <key>WatchPaths</key>
    <array>
        <string>/private/var/run/resolv.conf</string>
        <string>/Library/Preferences/SystemConfiguration/preferences.plist</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>StandardErrorPath</key><string>$HOME/VeriTakip/hata.log</string>
</dict>
</plist>
EOF

APP="$HOME/Library/LaunchAgents/com.veritakip.app.plist"
cat > "$APP" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.veritakip.app</string>
    <key>ProgramArguments</key>
    <array><string>$HOME/Applications/VeriTakip.app/Contents/MacOS/VeriTakip</string></array>
    <key>RunAtLoad</key><true/>
</dict>
</plist>
EOF

if [ "$DRY" != "--dry" ]; then
    launchctl bootout "gui/$UID_/com.veritakip.olcum" 2>/dev/null || true
    launchctl bootstrap "gui/$UID_" "$OLCUM"
    launchctl bootout "gui/$UID_/com.veritakip.app" 2>/dev/null || true
    launchctl bootstrap "gui/$UID_" "$APP"
fi

"$PY" "$HOME/VeriTakip/veri_takip.py"
ln -sf "$HOME/VeriTakip/rapor.html" "$HOME/Desktop/VeriTakip Raporu.html"
echo "KURULUM_TAMAM"
