#!/bin/bash
# VeriTakip kurulum betiği
# Kullanım: Terminal'de bu klasöre gelip:  bash kur.sh
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "╔══════════════════════════════════════════════╗"
echo "║  VeriTakip — Hotspot Veri Kullanımı Takibi   ║"
echo "╚══════════════════════════════════════════════╝"
echo

PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then
    echo "HATA: python3 bulunamadı."
    echo "Şu komutla kurun ve tekrar deneyin:  xcode-select --install"
    exit 1
fi

# --- Sorular ---
read -p "Aylık internet kotanız kaç GB? [60]: " KOTA
KOTA=${KOTA:-60}
read -p "Fatura kesim gününüz (ayın kaçı, 1-28)? [1]: " GUN
GUN=${GUN:-1}
read -p "Telefonunuz iPhone mu Android mi? (i/a) [i]: " TEL
TEL=${TEL:-i}
if [ "$TEL" = "a" ] || [ "$TEL" = "A" ]; then
    ONEKLER='["172.20.10.", "192.168.43.", "192.168.44."]'
else
    ONEKLER='["172.20.10."]'
fi

# --- Dosyalar ---
mkdir -p "$HOME/VeriTakip"
cp "$DIR/veri_takip.py" "$HOME/VeriTakip/"
cp "$DIR/hotspot_proxy.py" "$HOME/VeriTakip/" 2>/dev/null || true
if [ ! -f "$HOME/VeriTakip/config.json" ]; then
    cat > "$HOME/VeriTakip/config.json" <<EOF
{"aylik_kota_gb": $KOTA, "donem_baslangic_gunu": $GUN, "gunluk_uyari_gb": 2.0, "aylik_uyari_yuzde": 80, "hotspot_onekler": $ONEKLER}
EOF
else
    echo "Mevcut config.json korundu."
fi

# --- Menü çubuğu uygulaması ---
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/VeriTakip.app"
cp -R "$DIR/VeriTakip.app" "$HOME/Applications/"
xattr -dr com.apple.quarantine "$HOME/Applications/VeriTakip.app" 2>/dev/null || true

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
launchctl bootout "gui/$UID_/com.veritakip.olcum" 2>/dev/null || true
launchctl bootstrap "gui/$UID_" "$OLCUM"

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
launchctl bootout "gui/$UID_/com.veritakip.app" 2>/dev/null || true
launchctl bootstrap "gui/$UID_" "$APP"

# --- Kısayol + ilk ölçüm ---
"$PY" "$HOME/VeriTakip/veri_takip.py"
ln -sf "$HOME/VeriTakip/rapor.html" "$HOME/Desktop/VeriTakip Raporu.html"

echo
echo "✅ Kurulum tamamlandı!"
echo "   • Menü çubuğunda (saatin yanında) 📶 simgesini göreceksiniz."
echo "   • Telefonunuzun hotspot'una bağlanınca mini pencere kendiliğinden açılır."
echo "   • Ayrıntılı rapor: Masaüstünüzdeki 'VeriTakip Raporu.html'"
echo "   • Ayarlar: ~/VeriTakip/config.json"
echo "   • Kaldırmak için: bash kaldir.sh"
