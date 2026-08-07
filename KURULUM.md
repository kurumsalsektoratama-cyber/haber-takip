# Avrupa Kurumsal Bülten — telefon kurulumu

Uygulama GitHub'da bir adreste yayınlanacak. Haber verisi **şifreli** duracak;
parolayı bilen açar, bilmeyen kilit ekranı görür.

Bilgisayarın kapalıyken de haberler toplanmaya devam eder.

**Ücret:** Yok. **Süre:** ~5 dakika.

---

## Parola

```
pa4c-dqwx-sqf5-hw6e
```

Bu parolayı kimlerle paylaşırsan onlar da okuyabilir. Bir yere kaydet —
kaybolursa arşivi kimse açamaz, yenisini üretip baştan şifrelemek gerekir.

---

## Adım 1 — Parolayı depoya tanıt

Parola dosyaların içinde **yok**. GitHub'da ayrı ve şifreli olarak saklanacak.

1. <https://github.com/kurumsalsektoratama-cyber/haber-takip> deposunda
   **Settings** sekmesi
2. Sol menüde **Secrets and variables** → **Actions**
3. **New repository secret**

| Name | Secret |
|---|---|
| `VERI_PAROLASI` | `pa4c-dqwx-sqf5-hw6e` |

Adı harfi harfine böyle olmalı, büyük harf ve alt çizgi dahil.

## Adım 2 — Depoyu herkese açık yap

1. **Settings** → en alta in → **Danger Zone**
2. **Change repository visibility** → **Change to public** → onayla

> **Neden gerekiyor?** GitHub Pages ücretsiz hesaplarda sadece açık depolarda
> çalışıyor. Depoda şifresiz haber metni **yok** — kod, firma listesi ve şifreli
> veri var. Ayrıca açık depolarda Actions dakika sınırı kalkıyor, bu yüzden
> iki saatte bir tarayabiliyoruz.

## Adım 3 — İlk taramayı çalıştır

1. **Actions** sekmesi
2. Soldan **Avrupa Kurumsal Bülten**
3. Sağdaki **Run workflow** → **Run workflow**
4. 15-20 dakika sürer (ilk çalışma en uzunu)

Adımlar yeşil tik alırsa `veri` adında bir dal oluşmuş demektir.

## Adım 4 — Pages'i aç

1. **Settings** → **Pages**
2. **Source:** `Deploy from a branch`
3. **Branch:** `veri` · klasör `/ (root)` → **Save**

Bir iki dakika sonra adres hazır olur:

```
https://kurumsalsektoratama-cyber.github.io/haber-takip/
```

## Adım 5 — Telefona ekle

1. Telefonda adresi aç
2. Parolayı gir (bir kez, sonra hatırlanır)
3. **Android/Chrome:** üç nokta → **Ana ekrana ekle**
   **iPhone/Safari:** paylaş simgesi → **Ana Ekrana Ekle**

Ana ekranda "AK Bülten" simgesi çıkar, adres çubuğu olmadan açılır.

## Adım 6 — Yerel görevi kaldır

Bilgisayarda 3 saatte bir çalışan görev artık gereksiz; bulut aynı işi yapıyor.

```bash
powershell -ExecutionPolicy Bypass -File "C:\Users\Bilgisayarım\Desktop\Claude\HaberTakip\Kur.ps1" -Kaldir
```

Bilgisayardan da aynı adresi açarsın, `Baslat.bat`'a gerek kalmaz.

---

## Başkasına vermek

Adresi ve parolayı gönder, o kişi açar, parolayı girer, ana ekrana ekler.
Hesap açma, davet, onay yok.

Birini çıkarmak istersen: yeni parola üretilir, `VERI_PAROLASI` gizli değişkeni
güncellenir, tarama yeniden çalıştırılır, yeni parola kalanlara verilir.
Eski parola o andan sonra işe yaramaz.

---

## Nasıl çalışıyor

**İki saatte bir** GitHub sunucusunda:

1. `veri` dalındaki şifreli arşiv indirilir ve çözülür
2. `Tara.ps1` yeni haberleri bulur
3. `Icerik.ps1` 120 haberin metnini ve görselini indirir
4. `Sifrele.ps1` arşivi sıkıştırıp şifreler — ayrıca **çözüp doğrular**,
   çözülemiyorsa yayınlamaz
5. Site ve şifreli veri `veri` dalına yazılır, Pages yayınlar

Telefondaki uygulama açıkken 5 dakikada bir küçük bir sürüm dosyasına bakar;
değiştiyse yeni veriyi indirip çözer. 6 MB'lik dosyayı boşuna indirmez.

**Şifreleme:** Veri gzip ile sıkıştırılır, AES-256-GCM ile şifrelenir. Anahtar,
parolandan PBKDF2-SHA256 ile 600.000 tur döndürülerek üretilir. Çözme işlemi
tarayıcının içinde yapılır — parola hiçbir sunucuya gitmez.

---

## Bilinmesi gerekenler

**Adres herkese açık, içerik değil.** Adresi bulan biri kilit ekranı görür.
Şifreli dosyayı indirebilir ama parola olmadan çözemez — 79 bitlik parola
kaba kuvvetle denenemez.

**Arama motorlarına kapalı.** `robots.txt` ile dizine eklenmesi engellendi.

**Google engelleme riski.** Haber taraması GitHub'ın veri merkezi
IP'lerinden gidiyor; Google buralara yerel bilgisayara göre daha sık kısıtlama
uygulayabiliyor. Başlık taraması `clevel-takip` deposunda zaten sorunsuz
çalışıyor. Metin indirme kısmı bulutta ilk kez denenecek — başarısız olsa bile
haberler toplanmaya devam eder, sadece okuyucuda "metin alınamadı" yazar.

**PowerShell 7 farkı.** Betikler Linux ve PowerShell 7 için uyumlu yazıldı ama
bu bilgisayarda PowerShell 7 yok, buradan denenemedi. Şifrelemenin matematiği
(anahtar üretimi ve sıkıştırma) tarayıcıda ayrıca doğrulandı; kalan tek
belirsizlik Adım 3'teki ilk çalışma. Hata çıkarsa Actions kaydındaki mesajı ilet.
