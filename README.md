# TetherTrack 📶

**A macOS menu-bar app that tracks how much of your phone's data plan your computer eats while tethered (personal hotspot).**

It automatically distinguishes home/office Wi-Fi and Ethernet from the phone hotspot, and counts *only* hotspot usage against your quota. All data stays on your own machine — nothing is ever uploaded.

> macOS · English & Turkish UI · free and open source (MIT)
>
> 🇹🇷 [Türkçe](README.tr.md)

## Features

- 📶 **Live daily hotspot usage in the menu bar** (resets at midnight)
- 📱 **Auto mini window** in the screen corner when you connect to the hotspot
- 🚦 **Ethernet / Wi-Fi / Hotspot** connection indicator
- 📊 **Detailed report:** daily chart, billing-period history, and **per-network app breakdown** (which app used how much — clickable colored cells, light/dark theme)
- 🔔 **Stepped alerts:** a notification every 500 MB of daily use + 60%/80% quota-full warnings (configurable)
- 🎯 **Real remaining quota:** enter the value from your carrier's app and TetherTrack decrements it as your computer spends
- 🔒 **VPN-resilient counting:** even with a bonding VPN (e.g. Speedify) active, it counts phone traffic correctly from the physical interface
- ⚠️ **Emergency protection:** if traffic silently shifts to the phone while Ethernet is still plugged in, it warns you instantly with a red alarm
- 📱 **Hotspot Window:** open a single browser window routed only through the phone line, without unplugging Ethernet
- ⚙️ **Settings window:** quota, billing day, alerts — no file editing needed

## Installation (for users)

Easiest path — download the prebuilt package:

1. Download and unzip [**the installer**](https://github.com/unale/tethertrack/releases/latest)
2. Double-click `src/KURULUM.html` (illustrated guide, Turkish)
3. **Right-click → Open** on the **"VeriTakip Kur"** app *(not double-click; macOS asks for this on the first launch of unsigned apps)*
4. Enter your quota, billing day and phone type — done.

> **Note:** For apps downloaded from the internet, macOS is extra strict. If a warning appears: **System Settings → Privacy & Security → "Open Anyway".**

**To uninstall:** open "VeriTakip Kur" and click **Kaldır** (Remove), or run `bash src/kaldir.sh`.

## Build from source (for developers)

```bash
git clone https://github.com/unale/tethertrack.git
cd veritakip
bash build.sh
```

Produces: `VeriTakip.app` (menu-bar app), `VeriTakip Kur.app` (installer wizard), `VeriTakip-Kurulum.zip` (distribution package).

## Requirements

- macOS 12 (Monterey) or later — Apple Silicon and Intel supported
- **No dependencies for users** — the measurement engine is a bundled universal binary (Python embedded); nothing to install
- Xcode command-line tools only to *build* from source

## How it works

- An iPhone personal hotspot always uses the `172.20.10.x` network; the connection type is detected from that (no SSID / location permission needed). Android's `192.168.43.x` is also supported.
- Data counting comes from per-minute deltas of `netstat` interface counters; the app breakdown from `nettop` process counters (shown scaled to the network total).
- Measurement is triggered by `launchd` every minute plus on every network change.
- The menu-bar app is written in Swift/Cocoa and works by reading the measurement files.

## Privacy

TetherTrack sends nothing to the internet. Measurements live only in `~/VeriTakip/` on your own machine. The phone's own usage (its apps, etc.) is not measured — only what this Mac spends over the hotspot.

## Known limitations

- **macOS only.**
- The app is unsigned (no paid Apple signature required) — hence the Gatekeeper prompt on first launch.
- "Remaining quota" needs an occasional manual entry; the Mac cannot measure the phone's own usage.

## Roadmap

**Coming soon** — being planned now:
- 🔔 **Notification Center widget** — glance at usage without opening the menu
- 📈 **End-of-period forecast** — "at this pace you'll reach ~X GB" with a trend graph
- 🎯 **Per-app limit** — e.g. "warn me when Chrome passes 1 GB today"
- 🔵 **Low-data-mode suggestion** when quota gets critical

See the full list (done + planned, updated as we go) in [ROADMAP.md](ROADMAP.md).

## License

[MIT](LICENSE) — free for anyone to use, modify and distribute.
