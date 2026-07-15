#!/bin/bash
# VeriTakip — kaynaktan derleme betiği
# Universal (Apple Silicon + Intel) menü çubuğu uygulamasını derler,
# kurulum sihirbazını paketler ve dağıtılabilir zip'i üretir.
#
# Kullanım:  bash build.sh
set -e
cd "$(dirname "$0")"
SRC="src"
TMP="$(mktemp -d)"

echo "▸ Swift menü çubuğu uygulaması derleniyor (universal)…"
xcrun swiftc -O -target arm64-apple-macos12  -o "$TMP/vt_arm" "$SRC/main.swift" -framework Cocoa -framework WebKit
xcrun swiftc -O -target x86_64-apple-macos12 -o "$TMP/vt_x86" "$SRC/main.swift" -framework Cocoa -framework WebKit

echo "▸ VeriTakip.app paketleniyor…"
APP="VeriTakip.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp "$SRC/Info.plist" "$APP/Contents/"
lipo -create "$TMP/vt_arm" "$TMP/vt_x86" -output "$APP/Contents/MacOS/VeriTakip"
chmod +x "$APP/Contents/MacOS/VeriTakip"

echo "▸ Kurulum sihirbazı (VeriTakip Kur.app) derleniyor…"
KUR="VeriTakip Kur.app"
rm -rf "$KUR"
osacompile -o "$KUR" "$SRC/kurulum.applescript"
mkdir -p "$KUR/Contents/Resources/payload"
cp "$SRC/veri_takip.py" "$SRC/hotspot_proxy.py" "$SRC/kaldir.sh" "$SRC/kur_motor.sh" "$KUR/Contents/Resources/payload/"
cp -R "$APP" "$KUR/Contents/Resources/payload/"

echo "▸ Dağıtım zip'i oluşturuluyor…"
rm -f VeriTakip-Kurulum.zip
zip -rqy VeriTakip-Kurulum.zip "$KUR" "$SRC/KURULUM.html" README.md \
    "$SRC/kur.sh" "$SRC/kaldir.sh" "$SRC/veri_takip.py" "$SRC/hotspot_proxy.py" "$APP"

rm -rf "$TMP"
echo "✅ Bitti: VeriTakip-Kurulum.zip  ·  VeriTakip.app  ·  VeriTakip Kur.app"
