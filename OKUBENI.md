# Avrupa Kurumsal Bülten

Portföyündeki **357 kurumsal müşterinin** internetteki haberlerini
**1 Ağustos 2026'dan itibaren** toplar, bankacılık gözüyle sınıflandırır ve tek
ekranda gösterir. Arka planda kendi kendine tarar; her yeni haber uygulamaya düşer.

Haberler **uygulamanın içinde okunur** — başlığa tıklayınca haber sitesine gitmez,
metni ve görseliyle birlikte uygulamada açılır. Kaynak her zaman belirtilir.

---

## Neden bu haber, neden bu haber değil

Sistem her habere "bu neden önemli" sorusunu sorar. Cevabı olmayan haber öne
çıkmaz. Bir haberin listeye girmesi için üç şart var:

1. **Müşterinin adı haber başlığında geçmeli**
2. **Başlık eleme listesine takılmamalı** — spor, konser, magazin, "emekliye kaç
   maaş", "kaç TL", hava durumu, günlük teknik analiz gibi başlıklar hiç alınmaz
3. **Başlık en az bir konuyla eşleşmeli** — aşağıdaki 12 başlıktan biri

| Konu | Ne yakalar |
|---|---|
| **Satın alma / birleşme** | devir, hisse satışı, el değiştirme, ortaklık |
| **Anlaşma / sözleşme / ihale** | imzalanan anlaşma, kazanılan ihale, iş birliği, distribütörlük |
| **Yatırım / tesis** | yeni fabrika, kapasite artışı, temel atma, ar-ge merkezi |
| **Finansal sonuç** | kâr, zarar, ciro, bilanço, çeyrek sonuçları, temettü |
| **Finansman / kredi** | kredi, sendikasyon, tahvil, halka arz, sermaye artırımı |
| **Yönetim değişikliği** | genel müdür, CEO, CFO, yönetim kurulu atama ve istifaları |
| **Risk / hukuki** | soruşturma, dava, ceza, haciz, konkordato, kayyum, temerrüt |
| **İhracat / yeni pazar** | ihracat, yurt dışı açılım, yeni ülke |
| **Ürün / hizmet** | lansman, yeni ürün, patent, ödül |
| **İstihdam / kapanma** | işten çıkarma, grev, fabrika kapatma, toplu alım |
| **Regülasyon / kamu** | teşvik, lisans, EPDK/SPK/BDDK kararı, kamu ihalesi |
| **Kredi notu** | derecelendirme, not artırımı/indirimi |

Üçüncü şartı geçemeyen haberler **silinmez**, "sınıflandırılmamış" olarak
işaretlenir ve varsayılan olarak gizlenir. Araç çubuğundaki
**"Sınıflandırılmamışları da göster"** kutusuyla hepsini görebilirsin — bir şey
kaçırdığımı düşünüyorsan oraya bak.

---

## Hızlı başlangıç

**1.** `SimdiTara.bat` dosyasına çift tıkla — tarar ve uygulamayı açar.
**2.** Günlük kullanımda `Baslat.bat`.

Telefondan okumak ve bilgisayar kapalıyken de toplanması için:
[KURULUM.md](KURULUM.md)

---

## Ekranda neler var

| Bölüm | İşlevi |
|---|---|
| **Başlığa tıkla** | Haberi uygulamada açar: görsel, tam metin, kaynak |
| **Konular** | 12 kategoriden birine göre filtreler |
| **Müşteriler** | Haberi olan müşteriler, çok haberi olan üstte. Arama kutusuyla 357'sine de ulaşırsın |
| **Çubuk grafik** | Günlük haber yoğunluğu; bir çubuğa tıklayınca o güne filtreler |
| **Arama** | Başlık, kaynak ve müşteri adında arar (`/` tuşu odaklar) |
| **★ / ✓** | Kaydet / okundu işaretle |
| **CSV indir** | Ekrandaki haberleri Excel'de açılacak dosya olarak indirir |

---

## Müşteri listesini değiştirme

`musteriler.txt` — satır başına bir ticari unvan. Excel'den kopyalayıp
yapıştırabilirsin. Değişiklikten sonra:

```bash
powershell -ExecutionPolicy Bypass -File Tara.ps1 -Temizle
```

`-Temizle` arşivi yeni listeye göre yeniden değerlendirir; listeden çıkan
müşterinin haberleri silinir.

### Unvandan marka adı nasıl çıkıyor

`KAPTAN DEMİR ÇELİK ENDÜSTRİSİ VE TİCARET A.Ş.` → aranan ad: **Kaptan Demir Çelik**

Sektör ve hukuki kelimeler (sanayi, ticaret, anonim, şirketi…) atılır, baştaki
en fazla 3 kelime marka sayılır.

**Marka tek genel kelimeye düşerse** o müşteri takibe alınmaz — yoksa liste
alakasız haberle dolar. Bunlar `data\takip_disi.txt` dosyasına yazılır.
Kurtarmak için `takma_adlar.txt` kullan:

```
YENI MAGAZACILIK | A101, Yeni Mağazacılık
TURKIYE PETROL RAFINERILERI | Tüpraş
```

Sol taraf unvanda geçtiğinde, sağdaki adlar aranır. Şu an 20 kural tanımlı,
bu sayede **357 müşterinin tamamı** takipte.

## Konuları ve eleme listesini değiştirme

`ayarlar.json` dosyasındaki `konular` ve `haric` listelerine kelime ekleyip
çıkarabilirsin.

**Önemli:** kalıplar kelimenin başına sabitlenir, sonuna ek gelmesine izin
verilir. `anlaşma` yazarsan "anlaşmayı", "anlaşmasını" da yakalanır; ama
"amaç" içindeki "maç" yakalanmaz.

---

## Komutlar

```bash
powershell -ExecutionPolicy Bypass -File Tara.ps1
```
Tüm müşterileri tarar (~6 dakika, 328 benzersiz sorgu).

```bash
powershell -ExecutionPolicy Bypass -File Tara.ps1 -Sinir 15
```
İlk 15 müşteriyi tarar — hızlı deneme.

```bash
powershell -ExecutionPolicy Bypass -File Icerik.ps1 -Adet 300
```
Haber metinlerini ve görsellerini indirir. `-Adet 0` hepsini indirir.

```bash
powershell -ExecutionPolicy Bypass -File Kur.ps1 -Kaldir
```
Yerel otomatik taramayı kaldırır (bulut kurulduysa gerekir).

Tarama kayıtları: `data\log.txt` · Takip dışı kalanlar: `data\takip_disi.txt`

---

## Bilinmesi gerekenler

**Kaynak Google Haberler'dir.** Google'ın dizinlemediği haber bu sisteme düşmez.
Halka açık ve kurumsal şirketlerde kapsama yüksek, küçük aile şirketlerinde düşük.

**Müşteri adı başlıkta yoksa haber gelmez.** Bilinçli tercih — aksi halde liste
alakasız haberle dolardı. Bedeli: müşteriden bahsedip adını başlığa koymayan
haberler kaçırılır.

**Konu filtresi kelimeye dayanır, anlama değil.** Alışılmadık ifadeyle yazılmış
önemli bir haber "sınıflandırılmamış"a düşebilir. Ara sıra o kutuyu işaretleyip
göz atmakta fayda var; kaçan bir kalıp görürsen `ayarlar.json`'a ekle.

**Her haberin metni alınamaz.** Bazı siteler otomatik erişimi engelliyor (403),
bazıları metni JavaScript ile yüklüyor. Bu haberlerde okuyucuda uyarı çıkar ve
"Kaynağında aç" bağlantısı kalır. Başarı oranı yaklaşık %85.

**Metin kaynak sitenin telifindedir.** Uygulama kişisel takip amacıyla yerel
olarak saklar ve kaynağı her zaman gösterir.
