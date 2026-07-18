#!/bin/bash
# VeriTakip / TetherTrack kurulum betiği (Terminal alternatifi)
# Kullanım: Terminal'de bu klasöre gelip:  bash kur.sh
# NOT: Python GEREKTİRMEZ — ölçüm motoru uygulama paketine gömülü universal binary.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "╔══════════════════════════════════════════════╗"
echo "║  TetherTrack (VeriTakip) — Kurulum           ║"
echo "╚══════════════════════════════════════════════╝"
echo

# --- Sorular ---
read -p "Aylık internet kotanız kaç GB? [60]: " KOTA
KOTA=${KOTA:-60}
read -p "Fatura kesim gününüz (ayın kaçı, 1-28)? [1]: " GUN
GUN=${GUN:-1}
read -p "Telefonunuz iPhone mu Android mi? (i/a) [i]: " TEL
TEL=${TEL:-i}
if [ "$TEL" = "a" ] || [ "$TEL" = "A" ]; then
    ONEKLER='["172.20.10.", "192.168.42.", "192.168.43.", "192.168.44."]'
else
    ONEKLER='["172.20.10."]'
fi

# --- Config ---
mkdir -p "$HOME/VeriTakip"
if [ ! -f "$HOME/VeriTakip/config.json" ]; then
    cat > "$HOME/VeriTakip/config.json" <<EOF
{"aylik_kota_gb": $KOTA, "donem_baslangic_gunu": $GUN, "hotspot_onekler": $ONEKLER}
EOF
else
    echo "Mevcut config.json korundu."
fi

# --- Uygulama (gömülü ölçüm binary'si ile) ---
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/VeriTakip.app"
cp -R "$DIR/VeriTakip.app" "$HOME/Applications/"
xattr -dr com.apple.quarantine "$HOME/Applications/VeriTakip.app" 2>/dev/null || true
OLCUM_BIN="$HOME/Applications/VeriTakip.app/Contents/Resources/veri_takip"
chmod +x "$OLCUM_BIN" 2>/dev/null || true

# --- Arka plan servisleri ---
UID_="$(id -u)"
OLCUM="$HOME/Library/LaunchAgents/com.veritakip.olcum.plist"
cat > "$OLCUM" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.veritakip.olcum</string>
    <key>ProgramArguments</key>
    <array><string>$OLCUM_BIN</string></array>
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

launchctl bootout "gui/$UID_/com.veritakip.olcum" 2>/dev/null || true
launchctl bootstrap "gui/$UID_" "$OLCUM"
launchctl bootout "gui/$UID_/com.veritakip.app" 2>/dev/null || true
launchctl bootstrap "gui/$UID_" "$APP"

"$OLCUM_BIN" || true
ln -sf "$HOME/VeriTakip/rapor.html" "$HOME/Desktop/VeriTakip Raporu.html"

echo
echo "✅ Kurulum tamamlandı! Menü çubuğunda 📶 simgesini göreceksiniz."
echo "   Kaldırmak için: bash kaldir.sh"
