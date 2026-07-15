// VeriTakip menü çubuğu uygulaması
// Saatin yanında bugünkü hotspot kullanımını gösterir; hotspot'a
// bağlanınca mini pencereyi kendiliğinden açar.
import Cocoa
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var statusItem: NSStatusItem!
    var panel: NSPanel!
    var webView: WKWebView!
    var timer: Timer?
    var sonAg = ""
    var ilkOkuma = true
    var durumSatiri: NSMenuItem?

    // Ayarlar penceresi bileşenleri
    var ayarWin: NSWindow?
    let fKota = NSTextField()
    let pGun = NSPopUpButton()
    let pAdim = NSPopUpButton()
    let fEsik = NSTextField()
    let cBag = NSButton(checkboxWithTitle: "Hotspot'a bağlanınca durum bildirimi", target: nil, action: nil)
    let cGunluk = NSButton(checkboxWithTitle: "Günlük kademe bildirimleri (adım başına)", target: nil, action: nil)
    let cAylik = NSButton(checkboxWithTitle: "Paket doluluk bildirimleri", target: nil, action: nil)
    let adimDegerleri = [0.0, 0.25, 0.5, 1.0, 1.5, 2.0]

    let veriDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("VeriTakip")

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "📶 …"

        let menu = NSMenu()
        durumSatiri = menu.addItem(withTitle: "Bağlantı: kontrol ediliyor…",
                                   action: nil, keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Mini Pencereyi Göster/Gizle",
                     action: #selector(togglePanel), keyEquivalent: "m")
        menu.addItem(withTitle: "Detaylı Raporu Aç",
                     action: #selector(raporAc), keyEquivalent: "r")
        menu.addItem(withTitle: "Kalan Kotayı Gir…",
                     action: #selector(kalanGir), keyEquivalent: "k")
        menu.addItem(withTitle: "Ayarlar…",
                     action: #selector(ayarlarAc), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Hotspot Penceresi Aç (telefondan) 📱",
                     action: #selector(hotspotPenceresi), keyEquivalent: "h")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "VeriTakip'ten Çık",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { $0.target = ($0.action == #selector(NSApplication.terminate(_:))) ? NSApp : self }
        statusItem.menu = menu

        let boyut = NSRect(x: 0, y: 0, width: 330, height: 162)
        panel = NSPanel(contentRect: boyut,
                        styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow],
                        backing: .buffered, defer: false)
        panel.title = "VeriTakip"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let cfg = WKWebViewConfiguration()
        webView = WKWebView(frame: boyut, configuration: cfg)
        webView.navigationDelegate = self
        panel.contentView = webView

        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.tik()
        }
        tik()
    }

    func jsonOku(_ dosya: String) -> [String: Any]? {
        let url = veriDir.appendingPathComponent(dosya)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    func tik() {
        // Menü çubuğu başlığı: bugünkü hotspot GB
        let bicim = DateFormatter()
        bicim.dateFormat = "yyyy-MM-dd"
        let bugun = bicim.string(from: Date())
        if let gunluk = jsonOku("gunluk.json"),
           let gun = gunluk[bugun] as? [String: Any],
           let hs = gun["hotspot"] as? [String: Any] {
            let toplam = ((hs["in"] as? Double) ?? 0) + ((hs["out"] as? Double) ?? 0)
            statusItem.button?.title = String(format: "📶 %.2f GB", toplam / 1_073_741_824)
        } else {
            statusItem.button?.title = "📶 0.00 GB"
        }

        // Hotspot'a geçiş algılama
        guard let state = jsonOku("state.json"),
              let ag = state["son_ag"] as? String else { return }

        // Menüdeki canlı bağlantı satırı
        let detay = (state["son_ag_detay"] as? String) ?? ag
        let etiketler = ["ethernet": "🟢 Ethernet 🔌 — kotadan düşmez",
                         "wifi": "🟢 Wi-Fi 🏠 — kotadan düşmez",
                         "hotspot": "🟢 Hotspot 📱 — kota sayılıyor!",
                         "vpn": "🔒 VPN aktif — sayım fiziksel hatlardan",
                         "yok": "⚪️ Bağlantı yok"]
        durumSatiri?.title = "Bağlantı: " + (etiketler[detay] ?? "bilinmiyor")
        if !ilkOkuma && ag == "hotspot" && sonAg != "hotspot" {
            panelGoster()
        }
        sonAg = ag
        ilkOkuma = false
    }

    func panelGoster() {
        let mini = veriDir.appendingPathComponent("mini.html")
        webView.loadFileURL(mini, allowingReadAccessTo: veriDir)
        if let ekran = NSScreen.main {
            let g = ekran.visibleFrame
            panel.setFrameOrigin(NSPoint(x: g.maxX - panel.frame.width - 16,
                                         y: g.maxY - panel.frame.height - 12))
        }
        panel.orderFrontRegardless()
    }

    @objc func togglePanel() {
        if panel.isVisible { panel.orderOut(nil) } else { panelGoster() }
    }

    @objc func raporAc() {
        NSWorkspace.shared.open(veriDir.appendingPathComponent("rapor.html"))
    }

    // --- Yardımcı: komut çalıştır ---
    @discardableResult
    func kabuk(_ yol: String, _ args: [String], bekle: Bool = true) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: yol)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        if !bekle { return "" }
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                      encoding: .utf8) ?? ""
    }

    func pythonYolu() -> String {
        for y in ["/opt/homebrew/bin/python3", "/usr/bin/python3", "/usr/local/bin/python3"] {
            if FileManager.default.fileExists(atPath: y) { return y }
        }
        return "/usr/bin/python3"
    }

    func hotspotVarMi() -> Bool {
        if let s = jsonOku("state.json"), let d = s["son_ag_detay"] as? String, d == "hotspot" {
            return true
        }
        return kabuk("/sbin/ifconfig", []).contains("172.20.10.")
    }

    func speedifyCalisiyorMu() -> Bool {
        return !kabuk("/usr/bin/pgrep", ["-x", "Speedify"])
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // --- Hotspot Penceresi: yalnız telefon hattından çıkan ayrı Chrome ---
    // Ethernet kablosuna dokunmadan, sadece bu pencere telefondan çıkar.
    @objc func hotspotPenceresi() {
        NSApp.activate(ignoringOtherApps: true)
        let chrome = "/Applications/Google Chrome.app"
        guard FileManager.default.fileExists(atPath: chrome) else {
            let a = NSAlert()
            a.messageText = "Google Chrome gerekli"
            a.informativeText = "Hotspot Penceresi için Google Chrome kurulu olmalı."
            a.runModal(); return
        }
        if !hotspotVarMi() {
            let a = NSAlert()
            a.messageText = "Telefon bağlı değil"
            a.informativeText = "Önce iPhone'unuzun Kişisel Erişim Noktası'na bağlanın " +
                "(Ethernet kablosunu çekmenize gerek yok), sonra tekrar deneyin. " +
                "Pencere yalnızca telefon hattından çalışır."
            a.addButton(withTitle: "Tamam"); a.runModal(); return
        }
        if speedifyCalisiyorMu() {
            let a = NSAlert()
            a.messageText = "Speedify (VPN) açık"
            a.informativeText = "Speedify tüm trafiği kendi tüneline aldığı için Hotspot " +
                "Penceresi telefon hattı yerine VPN'den çıkabilir. Doğru çalışması için " +
                "önce Speedify'ı kapatın."
            a.addButton(withTitle: "Yine de Aç")
            a.addButton(withTitle: "Vazgeç")
            if a.runModal() != .alertFirstButtonReturn { return }
        }
        // Takılı eski proxy'leri temizle, taze başlat (port çakışması önlenir)
        kabuk("/usr/bin/pkill", ["-f", "hotspot_proxy"])
        usleep(300_000)
        let proxy = veriDir.appendingPathComponent("hotspot_proxy.py").path
        if FileManager.default.fileExists(atPath: proxy) {
            kabuk(pythonYolu(), [proxy, "8899"], bekle: false)
        }
        let profil = veriDir.appendingPathComponent("hotspot-chrome").path
        kabuk("/usr/bin/open",
              ["-na", "Google Chrome", "--args",
               "--user-data-dir=\(profil)",
               "--proxy-server=socks5://127.0.0.1:8899",
               "--no-first-run", "--no-default-browser-check",
               "https://music.youtube.com"], bekle: false)
    }

    @objc func kalanGir() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Kalan Kotayı Gir"
        alert.informativeText = "Operatör uygulamanızda (Turkcell vb.) şu an görünen " +
            "kalan internet miktarını GB olarak yazın. Bundan sonra kalan, " +
            "bilgisayarın harcamasına göre otomatik azaltılır."
        let alan = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        alan.placeholderString = "örn. 54,5"
        alert.accessoryView = alan
        alert.addButton(withTitle: "Kaydet")
        alert.addButton(withTitle: "Vazgeç")
        alert.window.initialFirstResponder = alan
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let metin = alan.stringValue.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let deger = Double(metin), deger >= 0, deger < 10000 else {
            let hata = NSAlert()
            hata.messageText = "Geçersiz değer"
            hata.informativeText = "Lütfen sayı girin (örn. 54,5)."
            hata.runModal()
            return
        }

        let bicim = DateFormatter()
        bicim.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let obj: [String: Any] = ["tarih": bicim.string(from: Date()), "kalan_gb": deger]
        if let data = try? JSONSerialization.data(withJSONObject: obj) {
            try? data.write(to: veriDir.appendingPathComponent("kalan.json"))
        }

        let tamam = NSAlert()
        tamam.messageText = "Kaydedildi ✅"
        tamam.informativeText = String(format: "Kalan %.1f GB olarak işlendi. " +
            "Rapor ve mini pencere 1 dakika içinde güncellenir.", deger)
        tamam.runModal()
    }

    // --- Ayarlar penceresi ---

    @objc func ayarlarAc() {
        NSApp.activate(ignoringOtherApps: true)
        if ayarWin == nil { ayarPencereKur() }
        ayarlariYukle()
        ayarWin?.center()
        ayarWin?.makeKeyAndOrderFront(nil)
    }

    func etiket(_ s: String) -> NSTextField { NSTextField(labelWithString: s) }

    func ayarPencereKur() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 320),
                           styleMask: [.titled, .closable],
                           backing: .buffered, defer: false)
        win.title = "VeriTakip Ayarları"
        win.isReleasedWhenClosed = false

        fKota.placeholderString = "örn. 60"
        pGun.addItems(withTitles: (1...28).map { "Ayın \($0)'i" })
        pAdim.addItems(withTitles: ["Kapalı", "250 MB'de bir", "500 MB'de bir",
                                    "1 GB'de bir", "1.5 GB'de bir", "2 GB'de bir"])
        fEsik.placeholderString = "örn. 60, 80"

        let kaydet = NSButton(title: "Kaydet", target: self, action: #selector(ayarKaydet))
        kaydet.keyEquivalent = "\r"
        let aciklama = etiket("Değişiklikler en geç 1 dakika içinde geçerli olur.")
        aciklama.textColor = .secondaryLabelColor
        aciklama.font = NSFont.systemFont(ofSize: 11)

        let grid = NSGridView(views: [
            [etiket("Aylık internet kotası (GB):"), fKota],
            [etiket("Fatura kesim günü:"), pGun],
            [etiket("Günlük kullanım uyarısı:"), pAdim],
            [etiket("Doluluk uyarı eşikleri (%):"), fEsik],
            [NSGridCell.emptyContentView, cBag],
            [NSGridCell.emptyContentView, cGunluk],
            [NSGridCell.emptyContentView, cAylik],
            [NSGridCell.emptyContentView, aciklama],
            [NSGridCell.emptyContentView, kaydet],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false

        win.contentView?.addSubview(grid)
        if let cv = win.contentView {
            NSLayoutConstraint.activate([
                grid.topAnchor.constraint(equalTo: cv.topAnchor, constant: 20),
                grid.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
                grid.trailingAnchor.constraint(lessThanOrEqualTo: cv.trailingAnchor, constant: -20),
                grid.bottomAnchor.constraint(lessThanOrEqualTo: cv.bottomAnchor, constant: -20),
                fKota.widthAnchor.constraint(equalToConstant: 110),
                fEsik.widthAnchor.constraint(equalToConstant: 110),
            ])
        }
        ayarWin = win
    }

    func ayarlariYukle() {
        let cfg = jsonOku("config.json") ?? [:]
        let kota = (cfg["aylik_kota_gb"] as? Double) ?? 60
        fKota.stringValue = kota == kota.rounded() ? String(Int(kota)) : String(kota)
        let gun = (cfg["donem_baslangic_gunu"] as? Int) ?? 1
        pGun.selectItem(at: min(max(gun, 1), 28) - 1)
        let adim = (cfg["gunluk_uyari_adim_gb"] as? Double) ?? 0.5
        pAdim.selectItem(at: adimDegerleri.firstIndex(where: { abs($0 - adim) < 0.01 }) ?? 2)
        if let esikler = cfg["kota_uyari_yuzdeler"] as? [Int] {
            fEsik.stringValue = esikler.map(String.init).joined(separator: ", ")
        } else {
            fEsik.stringValue = "60, 80"
        }
        cBag.state = ((cfg["bildirim_baglanti"] as? Bool) ?? true) ? .on : .off
        cGunluk.state = ((cfg["bildirim_gunluk"] as? Bool) ?? true) ? .on : .off
        cAylik.state = ((cfg["bildirim_aylik"] as? Bool) ?? true) ? .on : .off
    }

    @objc func ayarKaydet() {
        let kotaMetin = fKota.stringValue.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let kota = Double(kotaMetin), kota > 0, kota < 100000 else {
            let a = NSAlert()
            a.messageText = "Geçersiz kota"
            a.informativeText = "Aylık kota sayı olmalı (örn. 60)."
            a.runModal()
            return
        }
        let esikler = fEsik.stringValue.split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .filter { $0 > 0 && $0 <= 100 }

        let cfgURL = veriDir.appendingPathComponent("config.json")
        var cfg = ((try? Data(contentsOf: cfgURL))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        cfg["aylik_kota_gb"] = kota == kota.rounded() ? Int(kota) : kota as Any
        cfg["donem_baslangic_gunu"] = pGun.indexOfSelectedItem + 1
        cfg["gunluk_uyari_adim_gb"] = adimDegerleri[max(0, pAdim.indexOfSelectedItem)]
        cfg["kota_uyari_yuzdeler"] = esikler.isEmpty ? [60, 80] : esikler.sorted()
        cfg["bildirim_baglanti"] = cBag.state == .on
        cfg["bildirim_gunluk"] = cGunluk.state == .on
        cfg["bildirim_aylik"] = cAylik.state == .on
        if let d = try? JSONSerialization.data(withJSONObject: cfg, options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: cfgURL)
        }
        ayarWin?.orderOut(nil)
    }

    // mini.html içindeki olası bağlantıları varsayılan tarayıcıda aç
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.navigationType == .linkActivated, let url = action.request.url {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
