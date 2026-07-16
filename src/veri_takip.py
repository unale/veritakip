#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
VeriTakip - Cep telefonu hotspot veri kullanımı takipçisi (macOS)

Her dakika launchd tarafından çalıştırılır:
  1. Aktif ağ arayüzünü ve ağ geçidini (gateway) bulur
  2. iPhone hotspot mu (172.20.10.x) yoksa başka ağ mı (ev WiFi vb.) ayırt eder
  3. Sistem sayaçlarından geçen veri miktarını okur, günlük toplama ekler
  4. ~/VeriTakip/rapor.html dosyasını günceller
  5. Günlük/aylık limit aşımlarında macOS bildirimi gösterir

Komutlar:
  python3 veri_takip.py          -> örnek al + rapor güncelle (launchd bunu çağırır)
  python3 veri_takip.py rapor    -> raporu tarayıcıda aç
  python3 veri_takip.py ozet     -> terminalde kısa özet
"""

import json
import os
import subprocess
import sys
from datetime import date, datetime, timedelta

VERI_DIR = os.path.expanduser("~/VeriTakip")
STATE_FILE = os.path.join(VERI_DIR, "state.json")
DATA_FILE = os.path.join(VERI_DIR, "gunluk.json")
CONFIG_FILE = os.path.join(VERI_DIR, "config.json")
RAPOR_FILE = os.path.join(VERI_DIR, "rapor.html")
MINI_FILE = os.path.join(VERI_DIR, "mini.html")
KALAN_FILE = os.path.join(VERI_DIR, "kalan.json")

DEFAULT_CONFIG = {
    "aylik_kota_gb": 60,        # telefon paketindeki toplam internet
    "donem_baslangic_gunu": 1,  # faturalama döneminin başladığı gün (1-28)
    "gunluk_uyari_adim_gb": 0.5,   # her adımda bildirim: 0.5, 1, 1.5, 2 GB...
    "kota_uyari_yuzdeler": [60, 80],  # kalan girişi varsa paket doluluk uyarıları
    "aylik_uyari_yuzde": 80,    # kalan girişi YOKSA Mac harcamasına göre tek eşik
    # Hotspot ağ geçidi önekleri: iPhone hep 172.20.10.x kullanır.
    # Android telefonlar için genellikle "192.168.43." eklenmelidir.
    "hotspot_onekler": ["172.20.10."],
    # Bildirim aç/kapat anahtarları
    "bildirim_baglanti": True,  # hotspot'a bağlanınca durum bildirimi
    "bildirim_gunluk": True,    # günlük eşik aşımı bildirimi
    "bildirim_aylik": True,     # dönem eşiği aşımı bildirimi
    "dil": "tr",                # arayüz dili: "tr" veya "en" (rapor sonraki adımda çevrilecek)
}

HOTSPOT = "hotspot"
DIGER = "diger"      # eski kayıtlar (Wi-Fi + Ethernet birlikte) — geriye uyum
WIFI = "wifi"
ETHERNET = "ethernet"
# Kota yalnız HOTSPOT'tan sayılır; WIFI/ETHERNET yalnız bilgi amaçlı ayrılır.
KOTASIZ = (WIFI, ETHERNET, DIGER)


def yukle(path, varsayilan):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return varsayilan


def kaydet(path, veri):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(veri, f, ensure_ascii=False, indent=1)
    os.replace(tmp, path)


def calistir(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=10).stdout
    except Exception:
        return ""


def aktif_arayuz_ve_gateway():
    out = calistir(["route", "-n", "get", "default"])
    iface, gw = None, ""
    for satir in out.splitlines():
        satir = satir.strip()
        if satir.startswith("interface:"):
            iface = satir.split(":", 1)[1].strip()
        elif satir.startswith("gateway:"):
            gw = satir.split(":", 1)[1].strip()
    return iface, gw


def bayt_sayaclari(iface):
    """netstat -ibn çıktısından arayüzün toplam giren/çıkan baytlarını okur."""
    out = calistir(["netstat", "-ibn"])
    for satir in out.splitlines():
        p = satir.split()
        if len(p) >= 10 and p[0] == iface and "<Link" in p[2]:
            try:
                return int(p[6]), int(p[9])  # Ibytes, Obytes
            except ValueError:
                return None
    return None


def uygulama_sayaclari():
    """nettop ile süreç başına toplam giren/çıkan baytları okur (süreç açıldığından beri)."""
    out = calistir(["nettop", "-P", "-x", "-L", "1"])
    satirlar = out.splitlines()
    if not satirlar:
        return {}
    baslik = satirlar[0].split(",")
    try:
        i_in, i_out = baslik.index("bytes_in"), baslik.index("bytes_out")
    except ValueError:
        return {}
    sonuc = {}
    for s in satirlar[1:]:
        p = s.split(",")
        if len(p) <= max(i_in, i_out) or len(p) < 2:
            continue
        try:
            sonuc[p[1]] = (int(p[i_in]), int(p[i_out]))
        except ValueError:
            continue
    return sonuc


SISTEM_SURECLERI = {
    "mDNSResponder", "apsd", "cloudd", "rapportd", "netbiosd", "syslogd",
    "trustd", "nsurlsessiond", "accountsd", "rtcreportingd", "bluetoothd",
    "WindowServer", "locationd", "AssetCacheLocatorService", "timed",
}


def app_adi(ham):
    """nettop'un 'isim.pid' anahtarından okunabilir uygulama adı üretir."""
    ad = ham.rsplit(".", 1)[0]
    if ad.startswith("Google Chrome"):
        return "Google Chrome"
    if ad == "claude":
        return "Claude Code (terminal)"
    if ad in ("Claude", "Claude Helper") or ad.startswith("Claude Helper"):
        return "Claude (masaüstü)"
    if ad in SISTEM_SURECLERI:
        return "macOS sistem servisleri"
    return ad


def ag_turu(gw, config):
    """Telefon paylaşımını ağ geçidi adresinden tanır (iPhone: 172.20.10.x)."""
    onekler = config.get("hotspot_onekler", ["172.20.10."])
    return HOTSPOT if any(gw.startswith(o) for o in onekler) else DIGER


def wifi_aygiti():
    """Wi-Fi donanımının aygıt adını bulur (genellikle en0)."""
    out = calistir(["networksetup", "-listallhardwareports"])
    wifi_blogu = False
    for satir in out.splitlines():
        if satir.startswith("Hardware Port:"):
            wifi_blogu = "Wi-Fi" in satir
        elif wifi_blogu and satir.startswith("Device:"):
            return satir.split(":", 1)[1].strip()
    return "en0"


def ag_detay(iface, gw, config):
    """Gösterge paneli için ayrıntılı bağlantı türü."""
    if not iface:
        return "yok"
    if iface.startswith("utun") or iface.startswith("ipsec"):
        return "vpn"
    if ag_turu(gw, config) == HOTSPOT:
        return "hotspot"
    return "wifi" if iface == wifi_aygiti() else "ethernet"


def fiziksel_arayuzler():
    """IPv4 adresi olan fiziksel arayüzleri döndürür: {arayuz: ip}.

    VPN tünelleri (utun) hariç tutulur; trafik zaten altta yatan fiziksel
    arayüzden de geçtiği için sayım her zaman fiziksel katmanda yapılır.
    Böylece Speedify gibi VPN'ler açıkken de hotspot harcaması doğru sayılır.
    """
    out = calistir(["ifconfig"])
    sonuc, iface = {}, None
    for satir in out.splitlines():
        if satir and not satir[0].isspace():
            iface = satir.split(":")[0]
        elif iface and iface.startswith("en") and "inet " in satir:
            parcalar = satir.split()
            if len(parcalar) >= 2:
                sonuc[iface] = parcalar[1]
    return sonuc


def ip_hotspot_mu(ip, config):
    """Arayüzün IP'si hotspot ağından mı? (iPhone istemcilere 172.20.10.x verir)"""
    onekler = config.get("hotspot_onekler", ["172.20.10."])
    return any(ip.startswith(o) for o in onekler)


def bildirim(baslik, mesaj):
    script = 'display notification "{}" with title "{}" sound name "Submarine"'.format(
        mesaj.replace('"', "'"), baslik.replace('"', "'"))
    calistir(["osascript", "-e", script])


def donem_baslangici(bugun, baslangic_gunu):
    if bugun.day >= baslangic_gunu:
        return bugun.replace(day=baslangic_gunu)
    onceki_ay = bugun.replace(day=1) - timedelta(days=1)
    gun = min(baslangic_gunu, onceki_ay.day)
    return onceki_ay.replace(day=gun)


def gb(bayt):
    return bayt / (1024 ** 3)


def kalan_hesapla(donem_bayt, d_bas):
    """Kullanıcının elle girdiği 'gerçek kalan' değerinden güncel kalanı türetir.

    Telefonun kendi harcaması Mac'ten bilinemez; bu yüzden kalan yalnızca
    kullanıcı operatör uygulamasından baktığı değeri girdiğinde hesaplanır:
    kalan = girilen değer - girişten sonra Mac'in harcadığı.
    """
    k = yukle(KALAN_FILE, None)
    if not isinstance(k, dict) or "kalan_gb" not in k:
        return None
    try:
        t = datetime.fromisoformat(str(k["tarih"]))
        girilen = float(k["kalan_gb"])
    except (ValueError, TypeError, KeyError):
        return None
    if t.date() < d_bas:
        return None  # önceki fatura döneminden kalma giriş, artık geçersiz
    if "donem_snapshot_bayt" not in k:
        # Giriş yeni yapılmış: o anki dönem sayacını mühürle
        k["donem_snapshot_bayt"] = donem_bayt
        kaydet(KALAN_FILE, k)
    kalan = girilen - gb(donem_bayt - k["donem_snapshot_bayt"])
    return {"kalan_gb": max(0.0, kalan), "tarih": t}


def etime_saniye(e):
    """ps etime biçimini ([[gg-]ss:]dd:ss) saniyeye çevirir."""
    gun = 0
    if "-" in e:
        g, e = e.split("-", 1)
        gun = int(g)
    par = [int(x) for x in e.split(":")]
    while len(par) < 3:
        par.insert(0, 0)
    return gun * 86400 + par[0] * 3600 + par[1] * 60 + par[2]


def surec_yaslari(pidler):
    """Verilen PID'lerin kaç saniyedir çalıştığını döndürür."""
    if not pidler:
        return {}
    out = calistir(["ps", "-o", "pid=,etime=", "-p", ",".join(pidler)])
    yas = {}
    for satir in out.splitlines():
        p = satir.split()
        if len(p) == 2:
            try:
                yas[p[0]] = etime_saniye(p[1])
            except ValueError:
                continue
    return yas


def uygulama_isle(state, gun, tur):
    """Süreç başına bayt farklarını günün uygulama toplamlarına ekler.

    Sayaçlar süreç açıldığından beri kümülatiftir; süreç kaybolup geri
    gelirse çift saymamak için eski kayıtlar 24 saat saklanır.
    """
    proc = uygulama_sayaclari()
    if not proc:
        return
    simdi = datetime.now().timestamp()
    onceki = state.get("uygulamalar")
    ilk_calisma = onceki is None
    onceki = onceki or {}

    if not ilk_calisma:
        # İlk kez görülen süreçler: gerçekten yeni mi (son örnekten sonra mı
        # açılmış), yoksa eskiden beri çalışıp yeni mi görünür oldu?
        yeni_gorulen = [k for k in proc if k not in onceki]
        yaslar = surec_yaslari([k.rsplit(".", 1)[1] for k in yeni_gorulen])

        gun_app = gun.setdefault("uygulama", {}).setdefault(tur, {})
        for key, (pin, pout) in proc.items():
            o = onceki.get(key)
            if o:
                d_in, d_out = pin - o["in"], pout - o["out"]
                if d_in < 0 or d_out < 0:  # PID yeniden kullanılmış: yeni süreç
                    d_in, d_out = pin, pout
            else:
                # Eski bir süreçse birikmiş sayaçlarını bugüne yazma
                if yaslar.get(key.rsplit(".", 1)[1], 0) > 180:
                    continue
                d_in, d_out = pin, pout  # yeni süreç: tamamı bu aralıkta harcandı
            if d_in or d_out:
                ad = app_adi(key)
                a = gun_app.setdefault(ad, {"in": 0, "out": 0})
                a["in"] += d_in
                a["out"] += d_out

    yeni = {k: v for k, v in onceki.items() if simdi - v.get("ts", 0) < 86400}
    for key, (pin, pout) in proc.items():
        yeni[key] = {"in": pin, "out": pout, "ts": simdi}
    state["uygulamalar"] = yeni


def ornek_al():
    os.makedirs(VERI_DIR, exist_ok=True)
    config = {**DEFAULT_CONFIG, **yukle(CONFIG_FILE, {})}
    if not os.path.exists(CONFIG_FILE):
        kaydet(CONFIG_FILE, config)

    iface, gw = aktif_arayuz_ve_gateway()
    state = yukle(STATE_FILE, {})
    data = yukle(DATA_FILE, {})
    bugun = date.today().isoformat()
    onceki_ag = state.get("son_ag")

    if not iface:
        state["son_ag"] = "yok"
        state["son_ag_detay"] = "yok"
    else:
        state["son_ag"] = ag_turu(gw, config)
        state["son_ag_detay"] = ag_detay(iface, gw, config)

    # Sayım her zaman fiziksel arayüzler üzerinden (VPN'e dayanıklı):
    # her arayüzün farkı, arayüz türüne göre hotspot/wifi/ethernet hanesine yazılır.
    gun = data.setdefault(bugun, {})
    wifi_dev = wifi_aygiti()
    fiz = fiziksel_arayuzler()
    saat = str(datetime.now().hour)   # 0-23, saatlik kayıt için
    tur_delta = {HOTSPOT: 0, WIFI: 0, ETHERNET: 0}
    for arayuz, ip in fiz.items():
        sayac = bayt_sayaclari(arayuz)
        if not sayac:
            continue
        i_bytes, o_bytes = sayac
        onceki = state.get("sayaclar", {}).get(arayuz)
        if onceki:
            d_in = i_bytes - onceki["in"]
            d_out = o_bytes - onceki["out"]
            # Yeniden başlatma sonrası sayaçlar sıfırlanır
            if d_in < 0 or d_out < 0:
                d_in, d_out = i_bytes, o_bytes
            if d_in or d_out:
                if ip_hotspot_mu(ip, config):
                    tur = HOTSPOT
                elif arayuz == wifi_dev:
                    tur = WIFI
                else:
                    tur = ETHERNET
                t = gun.setdefault(tur, {"in": 0, "out": 0})
                t["in"] += d_in
                t["out"] += d_out
                tur_delta[tur] += d_in + d_out
                # Saatlik kayıt: hangi saatte hangi ağdan ne kadar
                sh = gun.setdefault("saatlik", {}).setdefault(saat, {})
                st = sh.setdefault(tur, {"in": 0, "out": 0})
                st["in"] += d_in
                st["out"] += d_out
        state.setdefault("sayaclar", {})[arayuz] = {"in": i_bytes, "out": o_bytes}
    if iface:
        state["son_ornek"] = datetime.now().isoformat(timespec="seconds")
        # Uygulama dökümü, bu örnekte en çok veri taşıyan ağa yazılır
        baskin = max(tur_delta, key=tur_delta.get)
        if tur_delta[baskin] > 0:
            uygulama_isle(state, gun, baskin)

    # --- Uyarılar ---
    bugun_h = data.get(bugun, {}).get(HOTSPOT, {"in": 0, "out": 0})
    bugun_gb = gb(bugun_h["in"] + bugun_h["out"])

    d_bas = donem_baslangici(date.today(), config["donem_baslangic_gunu"])
    donem_bayt = 0
    for g, aglar in data.items():
        try:
            if date.fromisoformat(g) >= d_bas:
                h = aglar.get(HOTSPOT, {})
                donem_bayt += h.get("in", 0) + h.get("out", 0)
        except ValueError:
            continue
    donem_gb = gb(donem_bayt)

    kalan_bilgi = kalan_hesapla(donem_bayt, d_bas)

    # --- ACİL KORUMA: Ethernet/Wi-Fi bağlıyken trafik telefona kaydıysa ---
    # macOS, kısıtlı Ethernet yerine hotspot'u "birincil" yapabilir; o zaman
    # TÜM trafik (yalnız istenen pencere değil) telefondan gider ve kota erir.
    hotspot_bagli = any(ip_hotspot_mu(ip, config) for ip in fiz.values())
    kablo_bagli = any(not ip_hotspot_mu(ip, config) for ip in fiz.values())
    default_telefon = state.get("son_ag_detay") == HOTSPOT
    uyarilar = state.setdefault("uyarilar", {})
    if hotspot_bagli and kablo_bagli and default_telefon:
        simdi = datetime.now().timestamp()
        if simdi - uyarilar.get("anomali_ts", 0) > 90:  # ~her 90 sn'de tekrar
            bildirim("⚠️ DİKKAT — İnternet telefondan gidiyor!",
                     "Ethernet/Wi-Fi bağlı ama tüm trafik TELEFON hattından akıyor; "
                     "kotanız hızla eriyor. Hotspot penceresini kapatın ve gerekirse "
                     "Wi-Fi'yi kapatıp Ethernet'e dönün.")
            uyarilar["anomali_ts"] = simdi
        state["anomali"] = True
        # Geçmişe dönük analiz için: bu saatte anomali oldu diye işaretle
        anom = gun.setdefault("anomali_saatler", [])
        if int(saat) not in anom:
            anom.append(int(saat))
    else:
        state["anomali"] = False

    # Hotspot'a yeni bağlanıldıysa güncel durumu bildir
    if (config.get("bildirim_baglanti", True)
            and state.get("son_ag") == HOTSPOT and onceki_ag != HOTSPOT):
        if kalan_bilgi:
            mesaj = (f"Bugün: {bugun_gb:.2f} GB · Dönem: {donem_gb:.1f} GB · "
                     f"Kalan (girişinize göre): {kalan_bilgi['kalan_gb']:.1f} GB")
        else:
            mesaj = f"Bugün: {bugun_gb:.2f} GB · Bu dönem toplam: {donem_gb:.1f} GB"
        bildirim("VeriTakip — iPhone Hotspot'a bağlandınız 📱", mesaj)

    uyarilar = state.setdefault("uyarilar", {})
    kota = config["aylik_kota_gb"]

    # Günlük kademeli uyarı: her adımda bir (0.5 → 1 → 1.5 → 2 GB ...)
    adim = config.get("gunluk_uyari_adim_gb", 0.5)
    if config.get("bildirim_gunluk", True) and adim > 0:
        seviye = int(bugun_gb / adim)
        g_kayit = uyarilar.get("gunluk_adim", {})
        onceki_seviye = g_kayit.get("seviye", 0) if g_kayit.get("tarih") == bugun else 0
        if seviye > onceki_seviye:
            bildirim("VeriTakip — Günlük Kullanım",
                     f"Bugün hotspot ile {seviye * adim:g} GB'ı geçtiniz "
                     f"(şu an {bugun_gb:.2f} GB).")
            uyarilar["gunluk_adim"] = {"tarih": bugun, "seviye": seviye}

    # Dönem uyarısı
    donem_key = d_bas.isoformat()
    if config.get("bildirim_aylik", True) and kota:
        if kalan_bilgi:
            # Kalan girişi varsa GERÇEK dolulukla uyar (%60, %80 ...)
            dolu_yuzde = max(0.0, (kota - kalan_bilgi["kalan_gb"]) / kota * 100)
            k_kayit = uyarilar.get("kota_yuzde", {})
            verilmis = k_kayit.get("esikler", []) if k_kayit.get("donem") == donem_key else []
            for esik_y in sorted(config.get("kota_uyari_yuzdeler", [60, 80])):
                if dolu_yuzde >= esik_y and esik_y not in verilmis:
                    bildirim("VeriTakip — Kota Uyarısı",
                             f"Paket doluluğu %{esik_y} eşiğini aştı! Kalan: "
                             f"{kalan_bilgi['kalan_gb']:.1f} / {kota} GB (girişinize göre).")
                    verilmis.append(esik_y)
            uyarilar["kota_yuzde"] = {"donem": donem_key, "esikler": verilmis}
        else:
            # Giriş yoksa yalnızca Mac'in harcamasına göre tek eşik
            esik = kota * config["aylik_uyari_yuzde"] / 100
            if donem_gb > esik and uyarilar.get("aylik") != donem_key:
                bildirim("VeriTakip — Dönem Uyarısı",
                         f"Bu dönem bilgisayar hotspot'tan {donem_gb:.1f} GB harcadı — "
                         f"{kota} GB paketin %{config['aylik_uyari_yuzde']}'i "
                         f"(yalnızca Mac'in payı).")
                uyarilar["aylik"] = donem_key

    kaydet(STATE_FILE, state)
    kaydet(DATA_FILE, data)
    rapor_yaz(data, config, state)


def rapor_yaz(data, config, state):
    bugun = date.today()
    d_bas = donem_baslangici(bugun, config["donem_baslangic_gunu"])
    kota = config["aylik_kota_gb"]
    dil = config.get("dil", "tr")

    def T(tr, en):
        return en if dil == "en" else tr

    marka = T("VeriTakip", "TetherTrack")

    bugun_veri = data.get(bugun.isoformat(), {})
    bugun_h = bugun_veri.get(HOTSPOT, {"in": 0, "out": 0})

    def bugun_toplam(*turler):
        tin = sum(bugun_veri.get(t, {}).get("in", 0) for t in turler)
        tout = sum(bugun_veri.get(t, {}).get("out", 0) for t in turler)
        return tin + tout

    bugun_wifi = bugun_toplam(WIFI)
    bugun_eth = bugun_toplam(ETHERNET)
    bugun_diger_top = bugun_toplam(*KOTASIZ)  # wifi+ethernet+eski diger
    bugun_gb = gb(bugun_h["in"] + bugun_h["out"])

    donem_bayt = 0
    for g, aglar in data.items():
        try:
            if date.fromisoformat(g) >= d_bas:
                h = aglar.get(HOTSPOT, {})
                donem_bayt += h.get("in", 0) + h.get("out", 0)
        except ValueError:
            continue
    donem_gb = gb(donem_bayt)
    yuzde = min(100.0, donem_gb / kota * 100) if kota else 0
    kalan_bilgi = kalan_hesapla(donem_bayt, d_bas)
    sonraki_donem = (d_bas + timedelta(days=32)).replace(day=config["donem_baslangic_gunu"])
    kalan_gun = max(1, (sonraki_donem - bugun).days)

    if kalan_bilgi:
        kalan_deger = f'{kalan_bilgi["kalan_gb"]:.1f} GB'
        kalan_aciklama = T(f'{kalan_bilgi["tarih"].strftime("%d.%m %H:%M")} girişinize göre',
                           f'per your {kalan_bilgi["tarih"].strftime("%d.%m %H:%M")} entry')
        kalan_satir = T(
            f'Girişinize göre kalan <b>{kalan_bilgi["kalan_gb"]:.1f} GB</b>; dönem sonuna '
            f'{kalan_gun} gün var, günde ortalama {kalan_bilgi["kalan_gb"] / kalan_gun:.2f} GB '
            f'kullanabilirsiniz. Telefonun kendi harcaması buraya yansımaz — arada bir '
            f'güncel değeri yeniden girin.',
            f'<b>{kalan_bilgi["kalan_gb"]:.1f} GB</b> remaining per your entry; {kalan_gun} days '
            f'left in the period, so ~{kalan_bilgi["kalan_gb"] / kalan_gun:.2f} GB/day. The phone\'s '
            f'own usage is not reflected here — re-enter the current value now and then.')
    else:
        kalan_deger = '—'
        kalan_aciklama = T('📶 menüsünden "Kalan Kotayı Gir"', 'Menu 📶 → "Enter Remaining Quota"')
        kalan_satir = T(
            'Gerçek kalanı görmek için operatör uygulamanızdaki değeri menü çubuğundaki '
            '📶 menüsünden "Kalan Kotayı Gir" ile işleyin. Telefonun kendi harcaması Mac\'ten '
            'ölçülemediği için kalan, yalnızca girişinizle hesaplanır.',
            'To see the real remaining amount, enter the value from your carrier\'s app via the '
            'menu bar 📶 → "Enter Remaining Quota". Since the Mac cannot measure the phone\'s own '
            'usage, the remaining amount is computed only from your entry.')

    # Son 30 günün çubukları
    gunler = []
    for i in range(29, -1, -1):
        g = bugun - timedelta(days=i)
        aglar = data.get(g.isoformat(), {})
        h = aglar.get(HOTSPOT, {})
        d_bayt = sum(aglar.get(t, {}).get("in", 0) + aglar.get(t, {}).get("out", 0)
                     for t in KOTASIZ)
        gunler.append((g, gb(h.get("in", 0) + h.get("out", 0)), gb(d_bayt)))
    maks = max([h for _, h, _ in gunler] + [0.1])

    cubuklar = ""
    for g, h_gb, d_gb in gunler:
        yükseklik = max(2, round(h_gb / maks * 120))
        etiket = g.strftime("%d")
        deger = f"{h_gb:.2f}" if h_gb >= 0.005 else ""
        vurgu = " bugun" if g == bugun else ""
        cubuklar += (f'<div class="gun{vurgu}" title="{g.strftime("%d.%m.%Y")} — '
                     f'Hotspot: {h_gb:.2f} GB, {T("Diğer ağ", "Other")}: {d_gb:.2f} GB">'
                     f'<span class="deger">{deger}</span>'
                     f'<div class="cubuk" style="height:{yükseklik}px"></div>'
                     f'<span class="etiket">{etiket}</span></div>')

    def mb_gb(b):
        return f"{b / 1024**3:.2f} GB" if b >= 1024**3 else f"{b / 1024**2:.0f} MB"

    # --- Dönem geçmişi: her günü ait olduğu fatura dönemine topla ---
    AYLAR = (["Oca", "Şub", "Mar", "Nis", "May", "Haz",
              "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara"] if dil != "en" else
             ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"])
    donemler = {}
    for g, aglar in data.items():
        try:
            tarih = date.fromisoformat(g)
        except ValueError:
            continue
        h = aglar.get(HOTSPOT, {})
        db = donem_baslangici(tarih, config["donem_baslangic_gunu"])
        donemler[db] = donemler.get(db, 0) + h.get("in", 0) + h.get("out", 0)

    donem_bolum = ""
    if donemler:
        satirlar = ""
        for db in sorted(donemler, reverse=True)[:12]:
            d_gb = gb(donemler[db])
            d_son = (db + timedelta(days=32)).replace(
                day=config["donem_baslangic_gunu"]) - timedelta(days=1)
            etiket = (f"{db.day} {AYLAR[db.month - 1]} – "
                      f"{d_son.day} {AYLAR[d_son.month - 1]} {d_son.year}")
            devam = (f" · <span style='color:#e67e22'>{T('devam ediyor', 'ongoing')}</span>"
                     if db == d_bas else "")
            d_yuzde = min(100, d_gb / kota * 100) if kota else 0
            d_renk = "#e74c3c" if d_yuzde > 80 else ("#f39c12" if d_yuzde > 60 else "#27ae60")
            satirlar += (f'<tr><td style="white-space:nowrap">{etiket}{devam}</td>'
                         f'<td style="width:55%"><div class="bar" style="height:14px;margin:0">'
                         f'<div style="width:{d_yuzde:.1f}%;background:{d_renk}"></div></div></td>'
                         f'<td style="white-space:nowrap"><b>{d_gb:.2f} GB</b> '
                         f'<span class="alt">/ {kota}</span></td></tr>')
        kesim = config["donem_baslangic_gunu"]
        donem_not = T(f"Her satır bir fatura dönemidir (kesim günü: ayın {kesim}'i). "
                      f"Çubuklar {kota} GB kotaya göre doludur.",
                      f"Each row is a billing period (cycle day: {kesim}). "
                      f"Bars fill relative to the {kota} GB quota.")
        donem_bolum = (f'<br><div class="grafik"><b>'
                       f'{T("Dönem geçmişi — fatura dönemine göre hotspot toplamları", "Billing-period history — hotspot totals per cycle")}</b>'
                       f'<table>{satirlar}</table>'
                       f'<p class="alt">{donem_not}</p></div>')

    # --- Üç ağ için özet + uygulama dökümü (modal için JSON) ---
    gun_app = data.get(bugun.isoformat(), {}).get("uygulama", {})
    dusen = T("kotadan düşer", "counts against quota")
    dusmez = T("kotadan düşmez", "not counted")
    AG_META = [
        (HOTSPOT, "iPhone Hotspot", "📱", dusen, bugun_h["in"] + bugun_h["out"]),
        (ETHERNET, "Ethernet", "🔌", dusmez, bugun_eth),
        (WIFI, "Wi-Fi", "🏠", dusmez, bugun_wifi),
    ]
    # Uygulama dökümü (nettop) süreçlerin localhost dahil TÜM bağlantılarını
    # sayar; ağ hanesi (netstat) ise yalnız fiziksel arayüzü. İki ölçümü
    # uyumlu göstermek için uygulama paylarını ağ hanesine oranlıyoruz:
    # her uygulamanın payı korunur, toplam gerçek ağ trafiğine eşitlenir.
    ag_veri = {}
    for tur, ad, ikon, not_, toplam in AG_META:
        apps = gun_app.get(tur, {})
        nettop_top = sum(v["in"] + v["out"] for v in apps.values())
        oran = (toplam / nettop_top) if nettop_top else 0
        app_list = sorted(
            ({"ad": a, "b": (v["in"] + v["out"]) * oran,
              "in": v["in"] * oran, "out": v["out"] * oran}
             for a, v in apps.items()),
            key=lambda z: -z["b"])[:15]
        ag_veri[tur] = {"ad": ad, "ikon": ikon, "not": not_,
                        "toplam": toplam, "apps": app_list}
    ag_json = json.dumps(ag_veri, ensure_ascii=False)

    renk = "#e74c3c" if yuzde > 80 else ("#f39c12" if yuzde > 60 else "#27ae60")
    AG_RENK = {HOTSPOT: "#e67e22", ETHERNET: "#2980b9", WIFI: "#27ae60"}

    # --- Saatlik grafik (bugün): saat saat hotspot kullanımı + anomali işareti ---
    gun_saatlik = bugun_veri.get("saatlik", {})
    anom_saatler = set(bugun_veri.get("anomali_saatler", []))
    saatlik_bolum = ""
    if gun_saatlik:
        saat_veri = []
        for s in range(24):
            v = gun_saatlik.get(str(s), {})
            h = v.get(HOTSPOT, {}).get("in", 0) + v.get(HOTSPOT, {}).get("out", 0)
            kablo = sum(v.get(t, {}).get("in", 0) + v.get(t, {}).get("out", 0)
                        for t in (ETHERNET, WIFI))
            saat_veri.append((s, gb(h), gb(kablo)))
        smaks = max([h for _, h, _ in saat_veri] + [0.01])
        scubuk = ""
        for s, h, k in saat_veri:
            yuk = max(2, round(h / smaks * 90)) if h > 0.001 else 2
            anom = s in anom_saatler
            crenk = "#e74c3c" if anom else "#e67e22"
            isaret = "⚠️" if anom else ""
            ipucu = (f"{s:02d}:00 — Hotspot {h:.2f} GB, {T('diğer', 'other')} {k:.2f} GB"
                     + (T(" · ⚠️ telefona kaçış!", " · ⚠️ shifted to phone!") if anom else ""))
            scubuk += (f'<div class="sgun" title="{ipucu}"><span class="sisaret">{isaret}</span>'
                       f'<div class="scubuk" style="height:{yuk}px;background:{crenk}"></div>'
                       f'<span class="setiket">{s:02d}</span></div>')
        saatlik_bolum = (
            f'<br><div class="grafik"><b>'
            f'{T("Bugün saat bazında hotspot kullanımı", "Today’s hotspot usage by hour")}</b>'
            f'<br><br><div class="sgunler">{scubuk}</div>'
            f'<p class="alt">{T("Kırmızı çubuk / ⚠️: o saatte Ethernet bağlıyken trafik telefona kaçmış (kota erimesi).", "Red bar / ⚠️: at that hour, traffic shifted to the phone while Ethernet was connected (quota drain).")}</p></div>')

    # Modal + hücre etkileşimi — f-string dışında düz JS (kaçış gerekmez)
    js_kod = """
const AG_RENK = {hotspot:'#e67e22', ethernet:'#2980b9', wifi:'#27ae60'};
function mbgb(b){
  if(b>=1073741824) return (b/1073741824).toFixed(2)+' GB';
  if(b>=1048576) return (b/1048576).toFixed(0)+' MB';
  return (b/1024).toFixed(0)+' KB';
}
function agAc(tur){
  const a = AGLAR[tur]; if(!a) return;
  document.getElementById('m-baslik').textContent = a.ikon+'  '+a.ad+' — '+M_BUGUN;
  document.getElementById('m-baslik').style.color = AG_RENK[tur];
  document.getElementById('m-toplam').textContent = mbgb(a.toplam)+'  ('+a.not+')';
  let satir = '';
  if(a.apps.length===0){
    satir = '<tr><td colspan="4" style="color:#95a5a6;text-align:center;padding:22px">'
          + M_YOK+'</td></tr>';
  } else {
    for(const p of a.apps){
      const pay = a.toplam>0 ? Math.round((p.b/a.toplam)*100) : 0;
      satir += '<tr><td>'+p.ad+'</td>'
        + '<td class="say">'+mbgb(p.in)+'</td>'
        + '<td class="say">'+mbgb(p.out)+'</td>'
        + '<td class="say"><b>'+mbgb(p.b)+'</b></td>'
        + '<td style="width:90px"><div class="mini-bar"><div style="width:'+pay
        + '%;background:'+AG_RENK[tur]+'"></div></div></td></tr>';
    }
  }
  document.getElementById('m-govde').innerHTML = satir;
  document.getElementById('modal').classList.add('acik');
}
function agKapat(e){
  if(!e || e.target.id==='modal' || e.target.id==='m-kapat')
    document.getElementById('modal').classList.remove('acik');
}
document.addEventListener('keydown', e=>{ if(e.key==='Escape') agKapat(); });
"""
    son_ornek = state.get("son_ornek", "-")
    detay = state.get("son_ag_detay") or {"hotspot": "hotspot", "diger": "wifi"}.get(
        state.get("son_ag", ""), "yok")
    son_ag = {
        "hotspot": T("iPhone Hotspot 📱 (kotadan düşer)", "iPhone Hotspot 📱 (counts against quota)"),
        "wifi": T("Wi-Fi 🏠 (kotadan düşmez)", "Wi-Fi 🏠 (not counted)"),
        "ethernet": T("Ethernet 🔌 (kotadan düşmez)", "Ethernet 🔌 (not counted)"),
        "vpn": T("VPN 🔒 (trafik tünelde; sayım fiziksel hatlardan sürüyor)",
                 "VPN 🔒 (traffic tunneled; counting from physical links)"),
        "yok": T("Bağlantı yok", "No connection")}.get(detay, T("Bilinmiyor", "Unknown"))

    html = f"""<!DOCTYPE html>
<html lang="{dil}"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="120">
<title>{marka} — {T("Veri Kullanımı", "Data Usage")}</title>
<style>
 :root {{
   --bg:#eef1f5; --kart:#ffffff; --metin:#243242; --alt:#7a8899;
   --cizgi:#e6ebf0; --golge:0 2px 10px rgba(30,50,80,.07); --raf:#e0e6ec;
 }}
 @media (prefers-color-scheme: dark) {{
   :root {{ --bg:#15181c; --kart:#1e2227; --metin:#e8ecf0; --alt:#9aa4b0;
     --cizgi:#2c313800; --golge:0 2px 10px rgba(0,0,0,.35); --raf:#333a42; }}
 }}
 * {{ box-sizing:border-box; }}
 body {{ font-family:-apple-system,'Segoe UI',sans-serif; background:var(--bg);
        color:var(--metin); max-width:860px; margin:0 auto; padding:26px 18px 50px;
        -webkit-font-smoothing:antialiased; }}
 h1 {{ font-size:1.5em; margin:0 0 4px; }}
 .alt {{ color:var(--alt); font-size:.85em; line-height:1.5; }}
 .kartlar {{ display:grid; grid-template-columns:repeat(3,1fr); gap:13px; margin:20px 0; }}
 .kart {{ background:var(--kart); border-radius:15px; padding:16px 18px; box-shadow:var(--golge); }}
 .kart .ust {{ font-size:.82em; color:var(--alt); }}
 .kart b {{ display:block; font-size:1.7em; margin:5px 0 2px; letter-spacing:-.5px; }}
 .panel {{ background:var(--kart); border-radius:15px; padding:18px 20px;
          box-shadow:var(--golge); margin-bottom:16px; }}
 .panel > .baslik {{ font-weight:700; font-size:1.02em; }}
 .bar {{ background:var(--raf); border-radius:9px; height:24px; overflow:hidden; margin:12px 0 8px; }}
 .bar > div {{ height:100%; background:{renk}; border-radius:9px; min-width:8px;
              transition:width .4s; }}

 /* Üç tıklanabilir ağ hücresi */
 .aglar {{ display:grid; grid-template-columns:repeat(3,1fr); gap:13px; margin:16px 0; }}
 .hucre {{ border:none; text-align:left; cursor:pointer; border-radius:15px; padding:17px 18px;
          color:#fff; box-shadow:var(--golge); position:relative; overflow:hidden;
          transition:transform .12s, box-shadow .12s; font-family:inherit; }}
 .hucre:hover {{ transform:translateY(-3px); box-shadow:0 8px 22px rgba(30,50,80,.22); }}
 .hucre:active {{ transform:translateY(-1px); }}
 .hucre .ikon {{ font-size:1.5em; }}
 .hucre .ad {{ font-size:.9em; opacity:.92; margin-top:2px; }}
 .hucre .val {{ font-size:1.7em; font-weight:700; margin-top:8px; letter-spacing:-.5px; }}
 .hucre .ipucu {{ font-size:.72em; opacity:.85; margin-top:4px; }}
 .hucre .not {{ position:absolute; top:14px; right:15px; font-size:.66em; opacity:.8;
               background:rgba(255,255,255,.2); padding:2px 8px; border-radius:20px; }}

 .gunler {{ display:flex; align-items:flex-end; gap:3px; height:170px; }}
 .gun {{ flex:1; display:flex; flex-direction:column; align-items:center; justify-content:flex-end; }}
 .cubuk {{ width:100%; background:#5aa9e6; border-radius:4px 4px 0 0; transition:background .2s; }}
 .gun:hover .cubuk {{ background:#3498db; }}
 .gun.bugun .cubuk {{ background:#e67e22; }}
 .etiket {{ font-size:.6em; color:var(--alt); margin-top:3px; }}
 .deger {{ font-size:.55em; color:var(--alt); margin-bottom:2px; white-space:nowrap; }}
 .sgunler {{ display:flex; align-items:flex-end; gap:2px; height:120px; }}
 .sgun {{ flex:1; display:flex; flex-direction:column; align-items:center; justify-content:flex-end; }}
 .scubuk {{ width:100%; border-radius:3px 3px 0 0; min-height:2px; }}
 .setiket {{ font-size:.55em; color:var(--alt); margin-top:3px; }}
 .sisaret {{ font-size:.6em; margin-bottom:1px; height:1em; }}
 table {{ width:100%; border-collapse:collapse; margin-top:8px; }}
 th, td {{ text-align:left; padding:8px 10px; font-size:.9em; }}
 td.say, th.say {{ text-align:right; font-variant-numeric:tabular-nums; }}
 th {{ color:var(--alt); font-weight:600; border-bottom:2px solid var(--raf); font-size:.82em; }}
 td {{ border-bottom:1px solid var(--cizgi); }}
 tr:last-child td {{ border-bottom:none; }}
 .mini-bar {{ background:var(--raf); border-radius:5px; height:8px; overflow:hidden; }}
 .mini-bar > div {{ height:100%; border-radius:5px; }}

 /* Modal */
 .modal {{ position:fixed; inset:0; background:rgba(15,22,32,.55); display:none;
          align-items:center; justify-content:center; padding:20px; z-index:9;
          backdrop-filter:blur(3px); }}
 .modal.acik {{ display:flex; }}
 .modal-ic {{ background:var(--kart); border-radius:18px; padding:22px 24px; width:100%;
            max-width:560px; max-height:82vh; overflow:auto; box-shadow:0 20px 60px rgba(0,0,0,.35);
            animation:acil .18s ease; }}
 @keyframes acil {{ from {{ opacity:0; transform:translateY(12px); }} }}
 .modal-ust {{ display:flex; align-items:flex-start; justify-content:space-between; gap:12px; }}
 #m-baslik {{ font-size:1.2em; font-weight:700; }}
 #m-toplam {{ color:var(--alt); font-size:.9em; margin:2px 0 10px; }}
 #m-kapat {{ cursor:pointer; border:none; background:var(--raf); color:var(--metin);
           width:30px; height:30px; border-radius:50%; font-size:1em; flex:none; }}
</style></head><body>
<h1>📶 {marka}</h1>
<p class="alt">{T("Son güncelleme", "Last update")}: {son_ornek} &nbsp;·&nbsp; {T("Şu anki bağlantı", "Current connection")}: {son_ag}
&nbsp;·&nbsp; {T("Sayfa 2 dakikada bir yenilenir.", "Page refreshes every 2 minutes.")}</p>

<div class="kartlar">
 <div class="kart"><span class="ust">{T("Bugün (hotspot)", "Today (hotspot)")}</span><b>{bugun_gb:.2f} GB</b>
   <span class="alt">↓{gb(bugun_h["in"]):.2f} ↑{gb(bugun_h["out"]):.2f} GB</span></div>
 <div class="kart"><span class="ust">{T("Bu dönem (hotspot)", "This period (hotspot)")}</span><b>{donem_gb:.2f} GB</b>
   <span class="alt">{T("", "since ")}{d_bas.strftime("%d.%m.%Y")}{T("'ten beri", "")}</span></div>
 <div class="kart"><span class="ust">{T("Kalan kota", "Remaining quota")}</span><b>{kalan_deger}</b>
   <span class="alt">{kalan_aciklama}</span></div>
</div>

<div class="panel">
 <div class="baslik">{T(f"{kota} GB paketin %{yuzde:.0f}'i bu bilgisayardan harcandı", f"{yuzde:.0f}% of the {kota} GB plan used by this computer")}</div>
 <div class="bar"><div style="width:{yuzde:.1f}%"></div></div>
 <p class="alt">{kalan_satir}</p>
</div>

<div class="baslik" style="font-weight:700; margin:22px 4px 2px">{T("Bugün ağ bazında — ayrıntı için tıklayın", "Today by network — click for details")}</div>
<div class="aglar">
 <button class="hucre" style="background:linear-gradient(135deg,#e67e22,#d35400)" onclick="agAc('hotspot')">
   <span class="not">{dusen}</span>
   <div class="ikon">📱</div><div class="ad">Hotspot</div>
   <div class="val">{bugun_gb:.2f} GB</div><div class="ipucu">{T("uygulama dökümü", "app breakdown")} ›</div></button>
 <button class="hucre" style="background:linear-gradient(135deg,#3498db,#2471a3)" onclick="agAc('ethernet')">
   <span class="not">{T("kotasız", "free")}</span>
   <div class="ikon">🔌</div><div class="ad">Ethernet</div>
   <div class="val">{gb(bugun_eth):.2f} GB</div><div class="ipucu">{T("uygulama dökümü", "app breakdown")} ›</div></button>
 <button class="hucre" style="background:linear-gradient(135deg,#27ae60,#1e8449)" onclick="agAc('wifi')">
   <span class="not">{T("kotasız", "free")}</span>
   <div class="ikon">🏠</div><div class="ad">Wi-Fi</div>
   <div class="val">{gb(bugun_wifi):.2f} GB</div><div class="ipucu">{T("uygulama dökümü", "app breakdown")} ›</div></button>
</div>

<div class="panel">
 <div class="baslik">{T("Son 30 gün — günlük hotspot kullanımı (GB)", "Last 30 days — daily hotspot usage (GB)")}</div><br>
 <div class="gunler">{cubuklar}</div>
 <p class="alt">{T("Turuncu çubuk bugünü gösterir. Üzerine gelince o günün ayrıntısı görünür.", "The orange bar is today. Hover for that day's detail.")}</p>
</div>
{saatlik_bolum}
{donem_bolum}

<p class="alt" style="margin-top:24px">{T("Ayarlar: menü çubuğu 📶 → Ayarlar", "Settings: menu bar 📶 → Settings")} &nbsp;·&nbsp;
{T("Ethernet ve Wi-Fi yalnızca bilgi amaçlıdır, kotadan düşmez.", "Ethernet and Wi-Fi are informational only, not counted against quota.")}</p>

<div class="modal" id="modal" onclick="agKapat(event)">
 <div class="modal-ic">
   <div class="modal-ust">
     <div><div id="m-baslik"></div><div id="m-toplam"></div></div>
     <button id="m-kapat" onclick="agKapat(event)">✕</button>
   </div>
   <table>
     <tr><th>{T("Uygulama", "App")}</th><th class="say">{T("İndirme", "Down")}</th><th class="say">{T("Yükleme", "Up")}</th>
         <th class="say">{T("Toplam", "Total")}</th><th>{T("Pay", "Share")}</th></tr>
     <tbody id="m-govde"></tbody>
   </table>
   <p class="alt" style="margin-top:12px">{T("En çok kullanan 15 uygulama (günlük). Paylar, o ağdan geçen gerçek trafiğe oranlanmıştır; toplamları üstteki ağ miktarıyla eşleşir. Uygulama ayrımı yaklaşıktır.", "Top 15 apps (daily). Shares are scaled to the real traffic on that network, so their total matches the amount above. The per-app split is approximate.")}</p>
 </div>
</div>

<script>
const AGLAR = {ag_json};
const M_BUGUN = {json.dumps(T("bugün", "today"))};
const M_YOK = {json.dumps(T("Bugün bu ağda kayıtlı uygulama trafiği yok.", "No app traffic recorded on this network today."))};
{js_kod}
</script>
</body></html>"""
    tmp = RAPOR_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(html)
    os.replace(tmp, RAPOR_FILE)

    # Menü çubuğu uygulamasının mini penceresi için kompakt görünüm
    saat = son_ornek[11:16] if len(son_ornek) >= 16 else son_ornek
    cipler = "".join(
        f'<span class="cip{" on" if detay == anahtar else ""}">{ad}</span>'
        for anahtar, ad in (("ethernet", "🔌 Ethernet"),
                            ("wifi", "🏠 Wi-Fi"),
                            ("hotspot", "📱 Hotspot"),
                            ("vpn", "🔒 VPN")))
    if kalan_bilgi:
        mini_kalan = T(
            f'Kalan: <b>{kalan_bilgi["kalan_gb"]:.1f} GB</b> (girişinize göre) &nbsp;·&nbsp; '
            f'günde {kalan_bilgi["kalan_gb"] / kalan_gun:.2f} GB hakkınız var',
            f'Left: <b>{kalan_bilgi["kalan_gb"]:.1f} GB</b> (per your entry) &nbsp;·&nbsp; '
            f'{kalan_bilgi["kalan_gb"] / kalan_gun:.2f} GB/day available')
    else:
        mini_kalan = T('Kalan için: 📶 menü → "Kalan Kotayı Gir"',
                       'For remaining: 📶 menu → "Enter Remaining Quota"')
    mini = f"""<!DOCTYPE html><html lang="{dil}"><head><meta charset="utf-8">
<meta http-equiv="refresh" content="30">
<style>
 body {{ font-family:-apple-system,sans-serif; margin:0; padding:14px 16px;
        background:transparent; color:#222; font-size:13px; -webkit-user-select:none; }}
 @media (prefers-color-scheme: dark) {{ body {{ color:#eee; }} .alt {{ color:#9aa0a6; }}
   .bar {{ background:#3a3d42; }} }}
 .b {{ font-size:24px; font-weight:700; }}
 .alt {{ color:#666; font-size:11.5px; margin-top:2px; }}
 .bar {{ background:#d8dde2; border-radius:6px; height:10px; margin:10px 0 6px; }}
 .bar div {{ height:100%; border-radius:6px; background:{renk}; min-width:4px; }}
 .cips {{ display:flex; gap:6px; margin-bottom:10px; }}
 .cip {{ border-radius:12px; padding:3px 11px; font-size:11px;
        background:#e3e7ea; color:#8a9199; }}
 .cip.on {{ background:#27ae60; color:#fff; font-weight:600; }}
 @media (prefers-color-scheme: dark) {{ .cip {{ background:#3a3d42; }}
   .cip.on {{ background:#27ae60; }} }}
 .alarm {{ background:#e74c3c; color:#fff; padding:8px 11px; border-radius:9px;
          font-size:12px; font-weight:600; margin-bottom:10px; line-height:1.35; }}
</style></head><body>
{("<div class='alarm'>" + T("⚠️ İnternet TELEFONDAN gidiyor! Ethernet bağlı ama trafik hotspot hattından akıyor — kota eriyor.", "⚠️ Internet is going through the PHONE! Ethernet is connected but traffic flows via the hotspot — quota draining.") + "</div>") if state.get("anomali") else ""}
<div class="cips">{cipler}</div>
<div>📶 {T("Bugün (hotspot)", "Today (hotspot)")}: <span class="b">{bugun_gb:.2f} GB</span></div>
<div class="bar"><div style="width:{yuzde:.0f}%"></div></div>
<div class="alt">{T("Bu dönem toplam", "This period total")}: <b>{donem_gb:.1f} GB</b> {T("harcandı", "used")} ({kota} GB {T("paket", "plan")})</div>
<div class="alt">{mini_kalan} &nbsp;·&nbsp; {T("Ölçüm", "Measured")}: {saat}</div>
</body></html>"""
    tmp = MINI_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(mini)
    os.replace(tmp, MINI_FILE)


def ozet():
    config = {**DEFAULT_CONFIG, **yukle(CONFIG_FILE, {})}
    data = yukle(DATA_FILE, {})
    bugun = date.today()
    d_bas = donem_baslangici(bugun, config["donem_baslangic_gunu"])
    bugun_h = data.get(bugun.isoformat(), {}).get(HOTSPOT, {"in": 0, "out": 0})
    donem = sum(a.get(HOTSPOT, {}).get("in", 0) + a.get(HOTSPOT, {}).get("out", 0)
                for g, a in data.items()
                if g >= d_bas.isoformat())
    print(f"Bugün hotspot : {gb(bugun_h['in'] + bugun_h['out']):.2f} GB")
    print(f"Bu dönem      : {gb(donem):.2f} GB / {config['aylik_kota_gb']} GB")
    kalan_bilgi = kalan_hesapla(donem, d_bas)
    if kalan_bilgi:
        print(f"Kalan (girişe göre): {kalan_bilgi['kalan_gb']:.1f} GB "
              f"[giriş: {kalan_bilgi['tarih'].strftime('%d.%m %H:%M')}]")
    else:
        print("Kalan         : giriş yok ('veri_takip.py kalan <GB>' ile girin)")


if __name__ == "__main__":
    komut = sys.argv[1] if len(sys.argv) > 1 else ""
    if komut == "rapor":
        subprocess.run(["open", RAPOR_FILE])
    elif komut == "ozet":
        ozet()
    elif komut == "kalan":
        try:
            deger = float(sys.argv[2].replace(",", "."))
        except (IndexError, ValueError):
            print("Kullanım: veri_takip.py kalan <GB>   (örn. kalan 54.5)")
            sys.exit(1)
        kaydet(KALAN_FILE, {"tarih": datetime.now().isoformat(timespec="seconds"),
                            "kalan_gb": deger})
        ornek_al()
        print(f"Kaydedildi: kalan {deger} GB")
    elif komut == "saatlik":
        # Bir günün saat bazlı kullanımı: veri_takip.py saatlik [YYYY-MM-DD]
        gun_str = sys.argv[2] if len(sys.argv) > 2 else date.today().isoformat()
        data = yukle(DATA_FILE, {})
        gun = data.get(gun_str, {})
        sh = gun.get("saatlik", {})
        anom = set(gun.get("anomali_saatler", []))
        if not sh:
            print(f"{gun_str} için saatlik kayıt yok "
                  "(saatlik takip 2026-07-16'dan itibaren tutuluyor).")
        else:
            print(f"{gun_str} — saat bazlı kullanım (MB):")
            print("Saat | Hotspot | Ethernet | Wi-Fi | ⚠️")
            for s in range(24):
                v = sh.get(str(s))
                if not v:
                    continue
                def mb(t):
                    x = v.get(t, {})
                    return (x.get("in", 0) + x.get("out", 0)) / 1024**2
                isaret = "⚠️ ethernet bağlıyken telefon!" if s in anom else ""
                print(f"{s:02d}   | {mb('hotspot'):6.0f}  | {mb('ethernet'):7.0f}  | "
                      f"{mb('wifi'):5.0f} | {isaret}")
    else:
        ornek_al()
