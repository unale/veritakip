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
    var acilisSatiri: NSMenuItem?
    var dil = "tr"   // config.json'dan başlangıçta okunur

    // Ayarlar penceresi bileşenleri
    var ayarWin: NSWindow?
    let fKota = NSTextField()
    let pGun = NSPopUpButton()
    let pAdim = NSPopUpButton()
    let fEsik = NSTextField()
    let pDil = NSPopUpButton()
    let cBag = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let cGunluk = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let cAylik = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let adimDegerleri = [0.0, 0.25, 0.5, 1.0, 1.5, 2.0]

    let veriDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("VeriTakip")

    func applicationDidFinishLaunching(_ note: Notification) {
        // Tek kopya: zaten çalışan bir VeriTakip varsa bu yeni kopyayı kapat
        // (alias/Spotlight'tan tekrar açılınca çift simge oluşmasın).
        let benim = NSRunningApplication.current
        let digerleri = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == benim.bundleIdentifier
                && $0.processIdentifier != benim.processIdentifier
        }
        if !digerleri.isEmpty {
            // Çalışan asıl kopyayı öne getir, bu fazladan kopyayı kapat
            digerleri.first?.activate()
            NSApp.terminate(nil)
            return
        }
        dil = (jsonOku("config.json")?["dil"] as? String) ?? "tr"
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "📶 …"

        let menu = NSMenu()
        durumSatiri = menu.addItem(withTitle: L("Bağlantı: kontrol ediliyor…", "Connection: checking…"),
                                   action: nil, keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: L("Mini Pencereyi Göster/Gizle", "Show/Hide Mini Window"),
                     action: #selector(togglePanel), keyEquivalent: "m")
        menu.addItem(withTitle: L("Detaylı Raporu Aç", "Open Detailed Report"),
                     action: #selector(raporAc), keyEquivalent: "r")
        menu.addItem(withTitle: L("Kalan Kotayı Gir…", "Enter Remaining Quota…"),
                     action: #selector(kalanGir), keyEquivalent: "k")
        menu.addItem(withTitle: L("Ayarlar…", "Settings…"),
                     action: #selector(ayarlarAc), keyEquivalent: ",")
        acilisSatiri = menu.addItem(withTitle: L("Bilgisayar açılınca başlat", "Start at login"),
                                    action: #selector(acilisToggle), keyEquivalent: "")
        acilisSatiri?.state = acilistaBaslarMi() ? .on : .off
        menu.addItem(withTitle: L("Yardım / Geri Bildirim ✉️", "Help / Feedback ✉️"),
                     action: #selector(yardimAc), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: L("Bu Ağı Hotspot Olarak İşaretle", "Mark This Network as Hotspot"),
                     action: #selector(hotspotIsaretle), keyEquivalent: "")
        menu.addItem(withTitle: L("Hotspot Penceresi Aç (telefondan) 📱", "Open Hotspot Window (via phone) 📱"),
                     action: #selector(hotspotPenceresi), keyEquivalent: "h")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: L("VeriTakip'ten Çık", "Quit TetherTrack"),
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { $0.target = ($0.action == #selector(NSApplication.terminate(_:))) ? NSApp : self }
        statusItem.menu = menu

        let boyut = NSRect(x: 0, y: 0, width: 330, height: 162)
        panel = NSPanel(contentRect: boyut,
                        styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow],
                        backing: .buffered, defer: false)
        panel.title = L("VeriTakip", "TetherTrack")
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

    // Dil yardımcısı: config.json'daki "dil" ayarına göre metin seçer.
    func L(_ tr: String, _ en: String) -> String { dil == "en" ? en : tr }

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
        let etiketler = [
            "ethernet": L("🟢 Ethernet 🔌 — kotadan düşmez", "🟢 Ethernet 🔌 — not counted"),
            "wifi": L("🟢 Wi-Fi 🏠 — kotadan düşmez", "🟢 Wi-Fi 🏠 — not counted"),
            "hotspot": L("🟢 Hotspot 📱 — kota sayılıyor!", "🟢 Hotspot 📱 — counting quota!"),
            "vpn": L("🔒 VPN aktif — sayım fiziksel hatlardan", "🔒 VPN active — counting from physical links"),
            "yok": L("⚪️ Bağlantı yok", "⚪️ No connection")]
        durumSatiri?.title = L("Bağlantı: ", "Connection: ") + (etiketler[detay] ?? L("bilinmiyor", "unknown"))
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

    // --- Yardım / Geri Bildirim: geliştiriciye e-posta taslağı açar ---
    @objc func yardimAc() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = L("Yardım / Geri Bildirim", "Help / Feedback")
        a.informativeText = L(
            "Bir sorun, hata veya öneriniz mi var? Aşağıdaki düğme e-posta " +
            "uygulamanızda geliştiriciye (Emir Ünal) bir mesaj taslağı açar. " +
            "Olabildiğince açık yazın; en kısa sürede dönüş yapılır.\n\n" +
            "Alternatif: GitHub üzerinde de sorun açabilirsiniz.",
            "Have a problem, bug or suggestion? The button below opens a draft " +
            "message to the developer (Emir Ünal) in your email app. Please be as " +
            "clear as possible; you'll get a reply as soon as possible.\n\n" +
            "Alternatively, you can open an issue on GitHub.")
        a.addButton(withTitle: L("E-posta Gönder", "Send Email"))
        a.addButton(withTitle: L("GitHub'da Aç", "Open on GitHub"))
        a.addButton(withTitle: L("Vazgeç", "Cancel"))
        let sonuc = a.runModal()
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        func enc(_ s: String) -> String {
            s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
        }
        if sonuc == .alertFirstButtonReturn {
            // Otomatik oluşmuş sorun raporu varsa e-postaya ekle
            let sorunURL = veriDir.appendingPathComponent("sorun_raporu.txt")
            let sorun = (try? String(contentsOf: sorunURL, encoding: .utf8)) ?? ""
            let konu = sorun.isEmpty
                ? L("TetherTrack — Geri Bildirim / Hata", "TetherTrack — Feedback / Issue")
                : L("TetherTrack — Sorun Raporu", "TetherTrack — Problem Report")
            var govde = L("Merhaba,\n\n[Sorununuzu, hatayı veya talebinizi buraya yazın]\n\n",
                          "Hello,\n\n[Write your problem, bug or request here]\n\n")
            if !sorun.isEmpty {
                govde += L("\n--- Otomatik Sorun Raporu ---\n", "\n--- Automatic Problem Report ---\n") + sorun
            }
            govde += "\n---\nTetherTrack 1.0\nmacOS: \(os)"
            if let url = URL(string: "mailto:emirunal@gmail.com?subject=\(enc(konu))&body=\(enc(govde))") {
                NSWorkspace.shared.open(url)
            }
        } else if sonuc == .alertSecondButtonReturn {
            if let url = URL(string: "https://github.com/unale/tethertrack/issues/new") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // --- Açılışta başlat (Login Item) aç/kapat ---
    var loginPlist: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.veritakip.app.plist")
    }
    func acilistaBaslarMi() -> Bool {
        FileManager.default.fileExists(atPath: loginPlist.path)
    }
    @objc func acilisToggle() {
        if acilistaBaslarMi() {
            // plist'i sil → bir sonraki açılışta başlamaz. Çalışan uygulama
            // (bu süreç) etkilenmez, kapanmaz.
            try? FileManager.default.removeItem(at: loginPlist)
        } else {
            let exe = Bundle.main.bundlePath + "/Contents/MacOS/VeriTakip"
            let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
              <key>Label</key><string>com.veritakip.app</string>
              <key>ProgramArguments</key><array><string>\(exe)</string></array>
              <key>RunAtLoad</key><true/>
            </dict></plist>
            """
            try? FileManager.default.createDirectory(
                at: loginPlist.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try? xml.write(to: loginPlist, atomically: true, encoding: .utf8)
            kabuk("/bin/launchctl", ["bootstrap", "gui/\(getuid())", loginPlist.path])
        }
        acilisSatiri?.state = acilistaBaslarMi() ? .on : .off
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

    // --- Bu ağı hotspot olarak işaretle (Android vb. — marka bağımsız) ---
    // Kullanıcı telefonuna bağlıyken bu ağın geçidi (gateway) önekini
    // config'teki hotspot_onekler listesine ekler; böylece o telefon tanınır.
    @objc func hotspotIsaretle() {
        NSApp.activate(ignoringOtherApps: true)
        // Mevcut varsayılan geçidi bul
        let out = kabuk("/sbin/route", ["-n", "get", "default"])
        var gw = ""
        for satir in out.split(separator: "\n") {
            let s = satir.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("gateway:") {
                gw = String(s.dropFirst("gateway:".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        let parcalar = gw.split(separator: ".")
        guard parcalar.count == 4 else {
            let a = NSAlert()
            a.messageText = L("Ağ bulunamadı", "No network found")
            a.informativeText = L("Şu an bir ağa bağlı görünmüyorsunuz. Önce telefonunuzun " +
                "kişisel erişim noktasına bağlanın.",
                "You don't seem to be connected to a network. Connect to your phone's " +
                "personal hotspot first.")
            a.runModal(); return
        }
        let onek = parcalar[0...2].joined(separator: ".") + "."

        let a = NSAlert()
        a.messageText = L("Bu ağı hotspot olarak işaretle?", "Mark this network as hotspot?")
        a.informativeText = L(
            "Şu an bağlı olduğunuz ağ (\(onek)x) telefon paylaşımı olarak kaydedilecek ve " +
            "bundan sonra kotadan sayılacak.\n\nYALNIZCA telefonunuzun hotspot'una " +
            "bağlıyken yapın — ev/iş Wi-Fi'ınıza bağlıyken yaparsanız o ağ yanlışlıkla " +
            "kotadan sayılır.",
            "The network you're currently on (\(onek)x) will be saved as tethering and " +
            "counted against your quota from now on.\n\nDo this ONLY while connected to " +
            "your phone's hotspot — doing it on home/office Wi-Fi would wrongly count that " +
            "network against your quota.")
        a.addButton(withTitle: L("Hotspot Olarak İşaretle", "Mark as Hotspot"))
        a.addButton(withTitle: L("Vazgeç", "Cancel"))
        guard a.runModal() == .alertFirstButtonReturn else { return }

        // config.json'daki hotspot_onekler'e ekle
        let cfgURL = veriDir.appendingPathComponent("config.json")
        var cfg = ((try? Data(contentsOf: cfgURL))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        var onekler = (cfg["hotspot_onekler"] as? [String]) ?? ["172.20.10."]
        if !onekler.contains(onek) { onekler.append(onek) }
        cfg["hotspot_onekler"] = onekler
        if let d = try? JSONSerialization.data(withJSONObject: cfg, options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: cfgURL)
        }
        let t = NSAlert()
        t.messageText = L("İşaretlendi ✅", "Marked ✅")
        t.informativeText = L("\(onek)x artık hotspot olarak tanınıyor.",
                              "\(onek)x is now recognized as hotspot.")
        t.runModal()
    }

    func hotspotVarMi() -> Bool {
        if let s = jsonOku("state.json"), let d = s["son_ag_detay"] as? String, d == "hotspot" {
            return true
        }
        return kabuk("/sbin/ifconfig", []).contains("172.20.10.")
    }

    // VPN'in yalnız AÇIK olması değil, BAĞLI olması önemli: varsayılan ağ
    // rotası tünel arayüzünden (utun/ipsec) geçiyorsa VPN gerçekten aktiftir.
    // (Speedify menü çubuğunda açık ama bağlantı kapalıysa uyarı çıkmaz.)
    func vpnBagliMi() -> Bool {
        let out = kabuk("/sbin/route", ["-n", "get", "default"])
        for satir in out.split(separator: "\n") {
            let s = satir.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("interface:") {
                let iface = s.dropFirst("interface:".count).trimmingCharacters(in: .whitespaces)
                return iface.hasPrefix("utun") || iface.hasPrefix("ipsec")
            }
        }
        return false
    }

    // --- Hotspot Penceresi: yalnız telefon hattından çıkan ayrı Chrome ---
    // Ethernet kablosuna dokunmadan, sadece bu pencere telefondan çıkar.
    @objc func hotspotPenceresi() {
        NSApp.activate(ignoringOtherApps: true)
        let chrome = "/Applications/Google Chrome.app"
        guard FileManager.default.fileExists(atPath: chrome) else {
            let a = NSAlert()
            a.messageText = L("Google Chrome gerekli", "Google Chrome required")
            a.informativeText = L("Hotspot Penceresi için Google Chrome kurulu olmalı.",
                                  "Google Chrome must be installed for the Hotspot Window.")
            a.runModal(); return
        }
        if !hotspotVarMi() {
            let a = NSAlert()
            a.messageText = L("Telefon bağlı değil", "Phone not connected")
            a.informativeText = L(
                "Önce iPhone'unuzun Kişisel Erişim Noktası'na bağlanın (Ethernet " +
                "kablosunu çekmenize gerek yok), sonra tekrar deneyin. Pencere " +
                "yalnızca telefon hattından çalışır.",
                "First connect to your iPhone's Personal Hotspot (no need to unplug " +
                "Ethernet), then try again. The window works only over the phone line.")
            a.addButton(withTitle: L("Tamam", "OK")); a.runModal(); return
        }
        if vpnBagliMi() {
            let a = NSAlert()
            a.messageText = L("VPN bağlantısı aktif", "VPN connection active")
            a.informativeText = L(
                "Şu an bir VPN (ör. Speedify) BAĞLI ve tüm trafiği kendi tüneline " +
                "alıyor; bu yüzden Hotspot Penceresi telefon hattı yerine VPN'den " +
                "çıkabilir. Doğru çalışması için önce VPN bağlantısını kesin.",
                "A VPN (e.g. Speedify) is currently CONNECTED and routing all traffic " +
                "through its tunnel, so the Hotspot Window may exit via the VPN instead " +
                "of the phone line. Disconnect the VPN first for correct behavior.")
            a.addButton(withTitle: L("Yine de Aç", "Open Anyway"))
            a.addButton(withTitle: L("Vazgeç", "Cancel"))
            if a.runModal() != .alertFirstButtonReturn { return }
        }
        // Önemli risk uyarısı: macOS telefonu birincil yapabilir → her şey
        // telefondan gider. Kullanıcı bilinçli onaylasın.
        let risk = NSAlert()
        risk.messageText = L("Önce şunu bilin ⚠️", "Please note ⚠️")
        risk.informativeText = L(
            "Hastane/kısıtlı Ethernet'te macOS telefonu 'birincil bağlantı' yapabilir; " +
            "o zaman SADECE bu pencere değil, bilgisayarın TÜM trafiği (güncellemeler, " +
            "uygulamalar) telefondan gider ve kotanız hızla erir.\n\n" +
            "VeriTakip bunu algılarsa sizi kırmızı alarmla uyarır. İşiniz biter bitmez " +
            "bu pencereyi kapatın; alarm görürseniz Wi-Fi'yi kapatıp Ethernet'e dönün.",
            "On a restricted Ethernet, macOS may make the phone the 'primary connection'; " +
            "then NOT just this window but ALL of your computer's traffic (updates, apps) " +
            "goes through the phone and your quota drains fast.\n\n" +
            "TetherTrack warns you with a red alarm if it detects this. Close this window " +
            "as soon as you're done; if you see the alarm, turn off Wi-Fi and return to Ethernet.")
        risk.addButton(withTitle: L("Anladım, Aç", "Got it, Open"))
        risk.addButton(withTitle: L("Vazgeç", "Cancel"))
        if risk.runModal() != .alertFirstButtonReturn { return }

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
        alert.messageText = L("Kalan Kotayı Gir", "Enter Remaining Quota")
        alert.informativeText = L(
            "Operatör uygulamanızda (Turkcell vb.) şu an görünen kalan internet " +
            "miktarını GB olarak yazın. Bundan sonra kalan, bilgisayarın harcamasına " +
            "göre otomatik azaltılır.",
            "Enter the remaining data (in GB) currently shown in your carrier's app. " +
            "From then on, the remaining amount is decremented automatically as your " +
            "computer spends.")
        let alan = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        alan.placeholderString = L("örn. 54,5", "e.g. 54.5")
        alert.accessoryView = alan
        alert.addButton(withTitle: L("Kaydet", "Save"))
        alert.addButton(withTitle: L("Vazgeç", "Cancel"))
        alert.window.initialFirstResponder = alan
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let metin = alan.stringValue.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let deger = Double(metin), deger >= 0, deger < 10000 else {
            let hata = NSAlert()
            hata.messageText = L("Geçersiz değer", "Invalid value")
            hata.informativeText = L("Lütfen sayı girin (örn. 54,5).", "Please enter a number (e.g. 54.5).")
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
        tamam.messageText = L("Kaydedildi ✅", "Saved ✅")
        tamam.informativeText = String(format: L(
            "Kalan %.1f GB olarak işlendi. Rapor ve mini pencere 1 dakika içinde güncellenir.",
            "Recorded as %.1f GB remaining. Report and mini window update within a minute."), deger)
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
        win.title = L("VeriTakip Ayarları", "TetherTrack Settings")
        win.isReleasedWhenClosed = false

        fKota.placeholderString = L("örn. 60", "e.g. 60")
        if pGun.numberOfItems == 0 {
            pGun.addItems(withTitles: (1...28).map { L("Ayın \($0)'i", "Day \($0)") })
            pAdim.addItems(withTitles: [L("Kapalı", "Off"),
                L("250 MB'de bir", "Every 250 MB"), L("500 MB'de bir", "Every 500 MB"),
                L("1 GB'de bir", "Every 1 GB"), L("1.5 GB'de bir", "Every 1.5 GB"),
                L("2 GB'de bir", "Every 2 GB")])
            pDil.addItems(withTitles: ["Türkçe", "English"])
        }
        fEsik.placeholderString = L("örn. 60, 80", "e.g. 60, 80")

        let kaydet = NSButton(title: L("Kaydet", "Save"), target: self, action: #selector(ayarKaydet))
        kaydet.keyEquivalent = "\r"
        let aciklama = etiket(L("Değişiklikler en geç 1 dakika içinde geçerli olur. Dil değişimi için uygulamayı yeniden başlatın.",
                                "Changes take effect within a minute. Restart the app for a language change."))
        aciklama.textColor = .secondaryLabelColor
        aciklama.font = NSFont.systemFont(ofSize: 11)
        aciklama.lineBreakMode = .byWordWrapping
        aciklama.preferredMaxLayoutWidth = 260

        let grid = NSGridView(views: [
            [etiket(L("Aylık internet kotası (GB):", "Monthly data quota (GB):")), fKota],
            [etiket(L("Fatura kesim günü:", "Billing cycle day:")), pGun],
            [etiket(L("Günlük kullanım uyarısı:", "Daily usage alert:")), pAdim],
            [etiket(L("Doluluk uyarı eşikleri (%):", "Quota-full thresholds (%):")), fEsik],
            [etiket(L("Dil / Language:", "Dil / Language:")), pDil],
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
        pDil.selectItem(at: ((cfg["dil"] as? String) == "en") ? 1 : 0)
        // Onay kutusu başlıklarını güncel dile göre ayarla
        cBag.title = L("Hotspot'a bağlanınca durum bildirimi", "Notify when connecting to hotspot")
        cGunluk.title = L("Günlük kademe bildirimleri (adım başına)", "Daily step alerts (per step)")
        cAylik.title = L("Paket doluluk bildirimleri", "Quota-full alerts")
    }

    @objc func ayarKaydet() {
        let kotaMetin = fKota.stringValue.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let kota = Double(kotaMetin), kota > 0, kota < 100000 else {
            let a = NSAlert()
            a.messageText = L("Geçersiz kota", "Invalid quota")
            a.informativeText = L("Aylık kota sayı olmalı (örn. 60).", "Monthly quota must be a number (e.g. 60).")
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
        let yeniDil = pDil.indexOfSelectedItem == 1 ? "en" : "tr"
        cfg["dil"] = yeniDil
        if let d = try? JSONSerialization.data(withJSONObject: cfg, options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: cfgURL)
        }
        ayarWin?.orderOut(nil)

        // Dil değiştiyse arayüzü yeni dile geçirmek için uygulamayı yeniden başlat
        if yeniDil != dil {
            let a = NSAlert()
            a.messageText = L("Dil değiştirildi", "Language changed")
            a.informativeText = L("Uygulama yeni dille yeniden başlatılıyor.",
                                  "The app is restarting in the new language.")
            a.addButton(withTitle: L("Tamam", "OK"))
            a.runModal()
            kabuk("/bin/launchctl",
                  ["kickstart", "-k", "gui/\(getuid())/com.veritakip.app"], bekle: false)
        }
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
