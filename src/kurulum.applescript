-- VeriTakip Kur.app — çift tıklamalı grafik kurulum sihirbazı
on run
	set kaynakYolu to POSIX path of (path to me) & "Contents/Resources/payload/"

	try
		set secim to button returned of (display dialog "VeriTakip 📶" & return & return & ¬
			"Bilgisayarınız telefonunuzun internetini (hotspot) kullanırken kotanızdan ne kadar harcadığını takip eder." & return & return & ¬
			"• Menü çubuğunda anlık kullanım" & return & ¬
			"• Hotspot'a bağlanınca mini pencere" & return & ¬
			"• Günlük ve aylık ayrıntılı rapor" ¬
			buttons {"Vazgeç", "Kaldır", "Kur"} default button "Kur" with title "VeriTakip Kurulum")
	on error number -128
		return
	end try

	if secim is "Kaldır" then
		kaldir(kaynakYolu)
		return
	else if secim is "Vazgeç" then
		return
	end if

	-- (Python kontrolü kaldırıldı — ölçüm motoru artık gömülü binary; hiçbir
	--  ek bileşen gerekmez.)

	-- Sorular
	try
		set kota to text returned of (display dialog ¬
			"Aylık internet paketiniz kaç GB?" default answer "60" ¬
			with title "VeriTakip Kurulum — 1/3")
		set kesimGunu to text returned of (display dialog ¬
			"Fatura kesim gününüz ayın kaçı? (1-28)" & return & ¬
			"(Operatör uygulamanızda 'yenileme tarihi' olarak görünür)" default answer "1" ¬
			with title "VeriTakip Kurulum — 2/3")
		set telefon to button returned of (display dialog ¬
			"Telefonunuz hangisi?" buttons {"Android", "iPhone"} default button "iPhone" ¬
			with title "VeriTakip Kurulum — 3/3")
	on error number -128
		return
	end try

	if telefon is "Android" then
		set telArg to "android"
	else
		set telArg to "iphone"
	end if

	-- Kurulum
	try
		set sonuc to do shell script "bash " & quoted form of (kaynakYolu & "kur_motor.sh") & ¬
			" " & quoted form of kota & " " & quoted form of kesimGunu & " " & telArg
	on error hata
		display dialog "Kurulum sırasında bir sorun oluştu:" & return & return & hata ¬
			buttons {"Tamam"} default button "Tamam" with icon caution with title "VeriTakip Kurulum"
		return
	end try

	if sonuc contains "KURULUM_TAMAM" then
		display dialog "✅ Kurulum tamamlandı!" & return & return & ¬
			"• Menü çubuğunda (saatin yanında) 📶 simgesini göreceksiniz." & return & ¬
			"• Telefonunuzun hotspot'una bağlanınca mini pencere kendiliğinden açılır." & return & ¬
			"• Ayrıntılı rapor masaüstünüzde: 'VeriTakip Raporu.html'" ¬
			buttons {"Bitti"} default button "Bitti" with title "VeriTakip Kurulum"
	else
		display dialog "Kurulum beklenmedik şekilde sonuçlandı:" & return & sonuc ¬
			buttons {"Tamam"} default button "Tamam" with icon caution with title "VeriTakip Kurulum"
	end if
end run

on kaldir(kaynakYolu)
	set onay to button returned of (display dialog ¬
		"VeriTakip bilgisayardan kaldırılsın mı?" & return & ¬
		"(Toplanan veriler ~/VeriTakip klasöründe korunur)" ¬
		buttons {"Vazgeç", "Kaldır"} default button "Vazgeç" with title "VeriTakip")
	if onay is not "Kaldır" then return
	do shell script "bash " & quoted form of (kaynakYolu & "kaldir.sh")
	display dialog "VeriTakip kaldırıldı." buttons {"Tamam"} default button "Tamam" with title "VeriTakip"
end kaldir
