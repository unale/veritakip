# TetherTrack 📶 <sub>(VeriTakip)</sub>

**Mac'inizi telefonunuzun interneti (hotspot) ile kullanırken, bilgisayarın kotanızdan ne kadar harcadığını takip eden menü çubuğu uygulaması.**

Ev/iş Wi-Fi'ı ve Ethernet trafiğini otomatik ayırt eder; yalnızca hotspot kullanımını kotanızdan sayar. Tüm veriler yalnızca kendi bilgisayarınızda kalır — hiçbir yere gönderilmez.

> macOS için · Türkçe arayüz · ücretsiz ve açık kaynak (MIT)
>
> 🇬🇧 [English](README.md)

## Özellikler

- 📶 **Menü çubuğunda anlık günlük hotspot kullanımı** (gece yarısı sıfırlanır)
- 📱 **Hotspot'a bağlanınca** ekran köşesinde otomatik mini durum penceresi
- 🚦 **Ethernet / Wi-Fi / Hotspot** ışıklı bağlantı göstergesi
- 📊 **Ayrıntılı rapor:** günlük grafik, fatura dönemi geçmişi ve **ağ bazında uygulama dökümü** (hangi program ne kadar harcadı — tıklanabilir renkli hücreler, açık/karanlık tema)
- 🔔 **Kademeli uyarılar:** her 500 MB'de bir günlük uyarı + %60/%80 kota doluluk bildirimi (ayarlanabilir)
- 🎯 **Gerçek kalan kota:** operatör uygulamanızdaki değeri girin, VeriTakip bilgisayarın harcamasına göre otomatik günceller
- 🔒 **VPN'e dayanıklı sayım:** Speedify gibi VPN'ler açıkken bile telefondan gideni fiziksel arayüzden doğru sayar
- 📱 **Hotspot Penceresi:** Ethernet kablosunu çekmeden, yalnızca ayrı bir tarayıcı penceresini telefon hattından açar (menü çubuğu → "Hotspot Penceresi Aç")
- ⚙️ **Ayarlar penceresi:** kota, fatura kesim günü, uyarılar — dosyayla uğraşmadan

## Kurulum (kullanıcılar için)

En kolay yol — hazır paketi indirin:

1. [**kurulum paketini**](https://github.com/unale/tethertrack/releases/latest) dosyasını indirin ve açın
2. `KURULUM.html`'e çift tıklayın (resimli rehber)
3. **"VeriTakip Kur"** uygulamasına **sağ tık → Aç** deyin *(çift tık değil; imzasız uygulamalarda macOS ilk açılışta bunu ister)*
4. Kota, fatura kesim günü ve telefon türünü girin — bitti.

> **Not:** İnternetten indirilen imzasız uygulamalarda macOS ekstra dikkatli davranır. Uyarı çıkarsa: **Sistem Ayarları → Gizlilik ve Güvenlik → "Yine de Aç"**.

**Kaldırmak için:** "VeriTakip Kur" uygulamasını açıp **Kaldır** düğmesine basın (veya `bash src/kaldir.sh`).

## Kaynaktan derleme (geliştiriciler için)

```bash
git clone https://github.com/unale/tethertrack.git
cd veritakip
bash build.sh
```

Üretilenler: `VeriTakip.app` (menü çubuğu uygulaması), `VeriTakip Kur.app` (kurulum sihirbazı), `VeriTakip-Kurulum.zip` (dağıtım paketi).

## Gereksinimler

- macOS 12 (Monterey) veya üzeri — Apple Silicon ve Intel desteklenir
- **Kullanıcı için hiçbir bağımlılık yok** — ölçüm motoru gömülü universal binary'dir (Python içine gömülüdür); kurulacak bir şey yok
- Kaynaktan *derlemek* için yalnızca Xcode komut satırı araçları

## Nasıl çalışır?

- iPhone kişisel erişim noktası her zaman `172.20.10.x` ağını kullanır; ağ türü buradan tanınır (SSID/konum izni gerekmez). Android için `192.168.43.x` de desteklenir.
- Veri sayımı `netstat` arayüz sayaçlarının dakikalık farkından; uygulama dökümü `nettop` süreç sayaçlarından hesaplanır (ağ toplamına oranlanarak gösterilir).
- Ölçüm `launchd` ile dakikada bir + her ağ değişiminde tetiklenir.
- Menü çubuğu uygulaması Swift/Cocoa'dır; ölçüm dosyalarını okuyarak çalışır.

## Gizlilik

VeriTakip hiçbir veriyi internete göndermez. Ölçümler yalnızca `~/VeriTakip/` klasöründe, kullanıcının kendi bilgisayarında saklanır. Telefonun kendi kullanımı (uygulama trafiği vb.) ölçülmez — yalnızca bu Mac'in hotspot üzerinden harcadığı sayılır.

## Bilinen sınırlar

- Yalnızca **macOS**.
- Uygulama imzasızdır (yıllık ücretli Apple imzası gerektirmez) — bu yüzden ilk açılışta Gatekeeper uyarısı görülür.
- "Kalan kota" gerçek değer için ara sıra elle giriş ister; telefonun kendi harcamasını Mac ölçemez.

## Yol Haritası

**Yakında gelecek özellikler** — şu an planlanıyor:
- 🔔 **Bildirim Merkezi widget'ı** — menüyü açmadan kullanıma göz atma
- 📈 **Dönem sonu tahmini** — "bu hızla ~X GB'a ulaşırsın" + trend grafiği
- 🎯 **Uygulama bazlı limit** — örn. "Chrome bugün 1 GB'ı geçince uyar"
- 🔵 **Düşük veri modu önerisi** — kota kritikleşince

Tam liste (yapılanlar + planlananlar, güncellendikçe): [ROADMAP.md](ROADMAP.md)

## Lisans

[MIT](LICENSE) — herkes özgürce kullanabilir, değiştirebilir ve dağıtabilir.
