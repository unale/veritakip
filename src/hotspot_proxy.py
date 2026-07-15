#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
VeriTakip Hotspot Proxy
=======================
Giden bağlantıları telefonun hotspot arayüzünün IP'sine bind ederek YALNIZCA
telefon hattından çıkaran küçük bir SOCKS5 proxy'si. "Hotspot Penceresi"
(ayrı Chrome profili) bu proxy'yi kullanır; o pencerenin trafiği telefondan,
Mac'in geri kalanı Ethernet/Wi-Fi'den akar. Ethernet kablosunu çekmeye gerek
kalmaz. Yalnız 127.0.0.1'de dinler, hiçbir veriyi dışarı sızdırmaz.

Kullanım: python3 hotspot_proxy.py [port]   (varsayılan 8899)
"""
import json
import os
import select
import socket
import struct
import subprocess
import sys
import threading

VERI_DIR = os.path.expanduser("~/VeriTakip")
CONFIG_FILE = os.path.join(VERI_DIR, "config.json")
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8899


def hotspot_onekler():
    try:
        with open(CONFIG_FILE, encoding="utf-8") as f:
            return json.load(f).get("hotspot_onekler", ["172.20.10."])
    except (OSError, ValueError):
        return ["172.20.10."]


def hotspot_ip():
    """Hotspot ağından IP almış yerel arayüzün adresini döndürür (yoksa None)."""
    zorla = os.environ.get("VERITAKIP_PROXY_IP")  # test/override
    if zorla:
        return zorla
    onekler = tuple(hotspot_onekler())
    try:
        out = subprocess.run(["ifconfig"], capture_output=True, text=True,
                             timeout=5).stdout
    except Exception:
        return None
    iface = None
    for satir in out.splitlines():
        if satir and not satir[0].isspace():
            iface = satir.split(":")[0]
        elif iface and iface.startswith("en") and "inet " in satir:
            ip = satir.split()[1]
            if ip.startswith(onekler):
                return ip
    return None


def akit(a, b):
    try:
        while True:
            r, _, _ = select.select([a, b], [], [], 60)
            if not r:
                break
            for s in r:
                veri = s.recv(65536)
                if not veri:
                    return
                (b if s is a else a).sendall(veri)
    except OSError:
        pass
    finally:
        for s in (a, b):
            try:
                s.close()
            except OSError:
                pass


def hedefe_baglan(host, port, kaynak_ip):
    son_hata = None
    for aile, tur, proto, _, adres in socket.getaddrinfo(
            host, port, socket.AF_INET, socket.SOCK_STREAM):
        try:
            uzak = socket.socket(aile, tur, proto)
            uzak.bind((kaynak_ip, 0))   # telefondan çıkışı zorlar
            uzak.settimeout(15)
            uzak.connect(adres)
            uzak.settimeout(None)
            return uzak
        except OSError as e:
            son_hata = e
            try:
                uzak.close()
            except OSError:
                pass
    raise son_hata or OSError("bağlanılamadı")


def istemci_isle(istemci):
    try:
        istemci.settimeout(20)
        veri = istemci.recv(2)
        if len(veri) < 2 or veri[0] != 0x05:
            return
        istemci.recv(veri[1])
        istemci.sendall(b"\x05\x00")

        baslik = istemci.recv(4)
        if len(baslik) < 4 or baslik[1] != 0x01:
            istemci.sendall(b"\x05\x07\x00\x01\x00\x00\x00\x00\x00\x00")
            return
        atur = baslik[3]
        if atur == 0x01:
            host = socket.inet_ntoa(istemci.recv(4))
        elif atur == 0x03:
            uzunluk = istemci.recv(1)[0]
            ham = istemci.recv(uzunluk)
            host = ham.decode("ascii", "ignore") or ham.decode("utf-8", "ignore")
        elif atur == 0x04:
            istemci.recv(16)
            istemci.sendall(b"\x05\x08\x00\x01\x00\x00\x00\x00\x00\x00")
            return
        else:
            return
        port = struct.unpack("!H", istemci.recv(2))[0]

        kaynak = hotspot_ip()
        if not kaynak:
            istemci.sendall(b"\x05\x03\x00\x01\x00\x00\x00\x00\x00\x00")
            return
        try:
            uzak = hedefe_baglan(host, port, kaynak)
        except OSError:
            istemci.sendall(b"\x05\x05\x00\x01\x00\x00\x00\x00\x00\x00")
            return

        istemci.sendall(b"\x05\x00\x00\x01\x00\x00\x00\x00\x00\x00")
        istemci.settimeout(None)
        print(f"CONNECT {host}:{port} -> kaynak {kaynak}", flush=True)
        akit(istemci, uzak)
    except OSError:
        try:
            istemci.close()
        except OSError:
            pass


def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        srv.bind(("127.0.0.1", PORT))
    except OSError as e:
        print(f"Port {PORT} kullanılamıyor: {e}", file=sys.stderr)
        sys.exit(1)
    srv.listen(64)
    print(f"Hotspot proxy 127.0.0.1:{PORT} dinliyor", flush=True)
    while True:
        try:
            istemci, _ = srv.accept()
        except OSError:
            continue
        threading.Thread(target=istemci_isle, args=(istemci,), daemon=True).start()


if __name__ == "__main__":
    main()
