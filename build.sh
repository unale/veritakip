#!/bin/bash
# TetherTrack (VeriTakip) — kaynaktan derleme betiği
# Universal (Apple Silicon + Intel) menü çubuğu uygulamasını ve Python'suz
# ölçüm binary'lerini derler, kurulum sihirbazını paketler, zip'i üretir.
#
# Kullanım:  bash build.sh
# Gereksinim: Xcode command line tools (universal /usr/bin/python3 içerir).
set -e
cd "$(dirname "$0")"
SRC="src"
TMP="$(mktemp -d)"

echo "▸ Swift menü çubuğu uygulaması derleniyor (universal)…"
xcrun swiftc -O -target arm64-apple-macos12  -o "$TMP/vt_arm" "$SRC/main.swift" -framework Cocoa -framework WebKit
xcrun swiftc -O -target x86_64-apple-macos12 -o "$TMP/vt_x86" "$SRC/main.swift" -framework Cocoa -framework WebKit

echo "▸ VeriTakip.app paketleniyor…"
APP="VeriTakip.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$SRC/Info.plist" "$APP/Contents/"
lipo -create "$TMP/vt_arm" "$TMP/vt_x86" -output "$APP/Contents/MacOS/VeriTakip"
chmod +x "$APP/Contents/MacOS/VeriTakip"

echo "▸ Ölçüm motoru universal binary'leri üretiliyor (PyInstaller — Python paketin içine gömülür)…"
VENV="$TMP/pyvenv"
/usr/bin/python3 -m venv "$VENV"
"$VENV/bin/pip" install -q --upgrade pip pyinstaller
for mod in veri_takip hotspot_proxy; do
    "$VENV/bin/pyinstaller" --onefile --target-arch universal2 \
        --distpath "$TMP/dist" --workpath "$TMP/pybuild" --specpath "$TMP/spec" \
        --name "$mod" "$SRC/$mod.py"
    cp "$TMP/dist/$mod" "$APP/Contents/Resources/$mod"
    chmod +x "$APP/Contents/Resources/$mod"
done

echo "▸ Ad-hoc imzalama (indirilince 'hasarlı' hatasını önler)…"
# Genişletilmiş öznitelikleri temizle (codesign 'resource fork' hatası verir), sonra imzala
xattr -cr "$APP"
codesign --force --deep -s - --timestamp=none "$APP" 2>&1 | grep -v "replacing" || true

echo "▸ Kurulum sihirbazı (VeriTakip Kur.app) derleniyor…"
KUR="VeriTakip Kur.app"
rm -rf "$KUR"
osacompile -o "$KUR" "$SRC/kurulum.applescript"
mkdir -p "$KUR/Contents/Resources/payload"
# Payload: uygulama (binary gömülü) + kurulum motoru + kaldırma — Python dosyası YOK
cp "$SRC/kaldir.sh" "$SRC/kur_motor.sh" "$KUR/Contents/Resources/payload/"
cp -R "$APP" "$KUR/Contents/Resources/payload/"
# Kurulum sihirbazını da imzala (kullanıcı önce bunu açıyor)
xattr -cr "$KUR"
codesign --force --deep -s - --timestamp=none "$KUR" 2>&1 | grep -v "replacing" || true

echo "▸ Dağıtım zip'i oluşturuluyor…"
rm -f VeriTakip-Kurulum.zip
zip -rqy VeriTakip-Kurulum.zip "$KUR" "$SRC/KURULUM.html" README.md \
    "$SRC/kur.sh" "$SRC/kaldir.sh" "$APP"

rm -rf "$TMP"
echo "✅ Bitti: VeriTakip-Kurulum.zip  ·  VeriTakip.app (Python gömülü, universal)"
