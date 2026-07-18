# TetherTrack — Roadmap

> 🇹🇷 Türkçe için aşağıya kaydırın.

This is a living document — as features ship, they move to **Done**, and new ideas are added.

## ✅ Done

- Per-minute background measurement of hotspot / Wi-Fi / Ethernet, counted separately
- Only hotspot counts against quota; VPN-resilient physical-interface counting
- "Real remaining quota" via manual entry from the carrier app
- Menu-bar live usage + auto mini window on hotspot connect
- Modern, dark-mode-aware detailed report (clickable colored network cells, per-app breakdown)
- Stepped daily alerts (every 500 MB) + 60% / 80% quota warnings
- **Leak protection:** warns on ANY data leaving via the phone outside the Hotspot Window
  (detects the offending app by isolating the proxy) + writes an auto problem report you can email
- Hotspot Window (route one browser window via the phone without unplugging Ethernet)
- Hourly usage chart with anomaly markers
- Help / Feedback button (email + GitHub Issues)
- Bilingual UI (English / Turkish) — app and report
- Android support: broad IP ranges + "Mark This Network as Hotspot" (brand-independent)
- Single-instance protection, start-at-login toggle, installer wizard
- **No Python required** — measurement engine bundled as a universal binary (PyInstaller); works on any Mac, Intel or Apple Silicon, with nothing to install
- Published on GitHub with CI + pre-commit checks

## 🔜 Coming soon

These are being planned in priority order. Details may change as we build.

### Next up

- **Notification Center widget** — a small card in macOS Notification Center (the panel that
  opens when you click the clock). Glance at today's usage and remaining quota without even
  opening the menu bar — the Mac equivalent of an iPhone home-screen widget.
- **End-of-period forecast** — a projection based on your average rate and days left:
  "at this pace you'll reach ~X GB by the cycle end," shown as a small trend graph so you can
  see early whether you're on track to exceed the plan.

### Idea pool

- **Per-app limit** — set a threshold for a specific app, e.g. "warn me when Chrome passes
  1 GB of hotspot data today," so a single app can't quietly drain the quota.
- **End-of-day summary** — a short daily wrap-up graph of when (which hours) you spent the most.
- **Low-data-mode suggestion** — when the quota gets critical, offer to turn on macOS Low Data
  Mode (which throttles background downloads, auto-updates and high-res content — it reduces
  waste, not speed).
- **TripMode-style app blocking** — while on hotspot, actually block the internet for apps you
  choose (updates, cloud sync, etc.), not just measure them.
- **iCloud multi-Mac merge** — if you use more than one Mac, combine their hotspot usage into a
  single total via iCloud.
- **More polished report visuals** — richer charts and layout in the detailed report.

### Optional / later

- **Apple Developer signing + notarization ($99/yr)** — removes the "right-click → Open" step so
  the app opens like any App Store download (no rewrite needed; distribution stays outside the App Store).

---

# Yol Haritası (Türkçe)

Bu yaşayan bir belgedir — özellikler tamamlandıkça **Yapılanlar**'a taşınır, yeni fikirler eklenir.

## ✅ Yapılanlar

- Hotspot / Wi-Fi / Ethernet trafiğini dakikada bir ayrı ayrı ölçen arka plan servisi
- Yalnızca hotspot kotadan sayılır; VPN'e dayanıklı fiziksel-arayüz sayımı
- Operatör uygulamasından elle girişle "gerçek kalan kota"
- Menü çubuğunda anlık kullanım + hotspot'a bağlanınca otomatik mini pencere
- Modern, karanlık tema destekli detaylı rapor (tıklanabilir renkli ağ hücreleri, uygulama dökümü)
- Kademeli günlük uyarılar (her 500 MB) + %60 / %80 kota uyarıları
- **Sızıntı koruması:** Hotspot Penceresi dışında telefondan çıkan HER veriyi uyarır
  (proxy'yi ayırarak sorumlu uygulamayı tespit eder) + e-postayla gönderilebilen otomatik sorun raporu yazar
- Hotspot Penceresi (Ethernet'i çekmeden bir tarayıcı penceresini telefondan geçir)
- Anomali işaretli saatlik kullanım grafiği
- Yardım / Geri Bildirim butonu (e-posta + GitHub Issues)
- Çift dilli arayüz (İngilizce / Türkçe) — uygulama ve rapor
- Android desteği: geniş IP aralığı + "Bu Ağı Hotspot Olarak İşaretle" (marka bağımsız)
- Tek kopya koruması, açılışta başlat seçeneği, kurulum sihirbazı
- **Python gerektirmez** — ölçüm motoru universal binary olarak gömülü (PyInstaller); Intel ya da Apple Silicon her Mac'te, kurulacak hiçbir şey olmadan çalışır
- CI + pre-commit denetimleriyle GitHub'da yayında

## 🔜 Yakında gelecek özellikler

Öncelik sırasına göre planlanıyor. Yapım sırasında ayrıntılar değişebilir.

### Sıradaki

- **Bildirim Merkezi widget'ı** — macOS Bildirim Merkezi'ne (saate tıklayınca açılan panel)
  küçük bir kart. Menü çubuğuna bile tıklamadan bugünkü kullanımınızı ve kalan kotanızı görürsünüz
  — iPhone'daki ana ekran widget'larının Mac karşılığı.
- **Dönem sonu tahmini** — ortalama hızınıza ve kalan güne göre projeksiyon:
  "Bu hızla dönem sonunda ~X GB'a ulaşırsın." Küçük bir trend grafiğiyle, paketi aşma yolunda
  olup olmadığınızı erkenden görürsünüz.

### Fikir havuzu

- **Uygulama bazlı limit** — belirli bir uygulama için eşik: örn. "Chrome bugün 1 GB hotspot
  verisini geçince uyar." Böylece tek bir uygulama kotayı sessizce eritemez.
- **Gün sonu özeti** — günün hangi saatlerinde en çok harcadığınızı gösteren kısa özet grafiği.
- **Düşük veri modu önerisi** — kota kritikleşince macOS Düşük Veri Modu'nu açmayı önerir
  (arka plan indirmelerini, otomatik güncellemeleri ve yüksek çözünürlüklü içeriği kısar —
  hızı değil, gereksiz tüketimi azaltır).
- **TripMode tarzı uygulama engelleme** — hotspot'tayken seçtiğiniz uygulamaların internetini
  yalnızca ölçmekle kalmayıp fiilen keser (güncellemeler, bulut senkronu vb.).
- **iCloud ile çoklu-Mac** — birden fazla Mac kullanıyorsanız, hepsinin hotspot kullanımını
  iCloud üzerinden tek toplamda birleştirir.
- **Daha gösterişli rapor görselleri** — detaylı raporda daha zengin grafikler ve düzen.

### İsteğe bağlı / ileride

- **Apple Developer imzası + notarizasyon (99 $/yıl)** — "sağ tık → Aç" adımını kaldırır; uygulama
  tıpkı App Store'dan indirilmiş gibi açılır (yeniden yazım gerekmez, dağıtım App Store dışında kalır).
