#Requires -Version 5.1
<#
    Avrupa Kurumsal Bulten - tarama motoru (1. asama: haberleri bul)

    musteriler.txt icindeki her musteri icin Google Haberler'i tarar. Bir haberin
    listeye girmesi icin uc sart var:
      1) Musterinin marka adi haber basliginda gecmeli
      2) Baslik "haric" listesindeki bir ifadeyi ICERMEMELI (spor, magazin, vb.)
      3) Baslik en az bir "konu" ile eslesmeli (anlasma, satin alma, kar, dava...)

    Ucuncu sarti gecemeyen haberler silinmez, "siniflandirilmamis" olarak
    isaretlenir ve arayuzde varsayilan olarak gizlenir.

    Kullanim:
      .\Tara.ps1                 -> tum musterileri tara
      .\Tara.ps1 -Sinir 10       -> ilk 10 musteriyi tara (hizli deneme)
      .\Tara.ps1 -Temizle        -> arsivi guncel kurallara gore yeniden degerlendir
      .\Tara.ps1 -Sessiz         -> ekrana az yaz (zamanlanmis gorev icin)

    Not: bu dosya SADECE ASCII karakter icerir (bkz. Ortak.ps1 aciklamasi).
#>
[CmdletBinding()]
param(
    [int]$Sinir = 0,
    [switch]$Temizle,
    [switch]$Sessiz
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

$Kok = $PSScriptRoot
if (-not $Kok) { $Kok = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Kok 'Ortak.ps1')

$VeriKlasor = Join-Path $Kok 'data'
if (-not (Test-Path $VeriKlasor)) { New-Item -ItemType Directory -Path $VeriKlasor -Force | Out-Null }

$AyarYolu    = Join-Path $Kok 'ayarlar.json'
$MusteriYolu = Join-Path $Kok 'musteriler.txt'
$TakmaYolu   = Join-Path $Kok 'takma_adlar.txt'
$ArsivYolu   = Join-Path $VeriKlasor 'haberler.json'
$WebYolu     = Join-Path $VeriKlasor 'haberler.js'
$LogYolu     = Join-Path $VeriKlasor 'log.txt'

function Yaz([string]$m, [string]$seviye = 'BILGI') {
    $satir = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $seviye, $m
    if (-not $Sessiz -or $seviye -ne 'BILGI') { Write-Host $satir }
    try { Add-Content -Path $LogYolu -Value $satir -Encoding UTF8 } catch { }
}

if (-not (KilitAl (Join-Path $VeriKlasor 'kilit'))) {
    Yaz 'Baska bir tarama/icerik islemi calisiyor, bu calisma atlandi.' 'UYARI'
    return
}
try {

# ---------------------------------------------------------------- ayarlar
if (-not (Test-Path $AyarYolu))    { throw "ayarlar.json bulunamadi: $AyarYolu" }
if (-not (Test-Path $MusteriYolu)) { throw "musteriler.txt bulunamadi: $MusteriYolu" }
$Ayar = Get-Content $AyarYolu -Raw -Encoding UTF8 | ConvertFrom-Json

$Baslangic = [datetime]::ParseExact($Ayar.baslangicTarihi, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
$Bekleme   = [int]$Ayar.sorguBeklemeMs; if ($Bekleme -le 0) { $Bekleme = 800 }
$UstSinir  = [int]$Ayar.arsivUstSinir;  if ($UstSinir -le 0) { $UstSinir = 40000 }

# Konu ve haric desenleri.
# Kalip kelimenin BASINA sabitlenir, sonuna ek gelmesine izin verilir:
#   \bANLASMA\w*  -> "ANLASMAYI", "ANLASMASINI" tutar
# Bu sabitleme sart. Serbest birakilirsa "AMAC" icinde "MAC", "TEBLIGI"
# icinde "LIG", "PLATFORMA" icinde "FORMA" yakalanip haber yanlislikla elenir.
function DesenKur($kelimeler) {
    $d = @()
    foreach ($kel in $kelimeler) {
        $n = Duzle $kel
        if ($n) { $d += ('\b' + [regex]::Escape($n) + '\w*') }
    }
    if ($d.Count -eq 0) { return '' }
    return ($d -join '|')
}

$Konular = @()
foreach ($k in $Ayar.konular) {
    $desen = DesenKur $k.kelimeler
    if (-not $desen) { continue }
    $Konular += [pscustomobject]@{ Id = $k.id; Ad = $k.ad; Renk = $k.renk; Desen = $desen }
}

$HaricDesen = DesenKur $Ayar.haric.kelimeler
$hd = @($Ayar.haric.kelimeler)

$Jenerik = @()
foreach ($kel in $Ayar.jenerik.kelimeler) { $Jenerik += (Duzle $kel) }

Yaz "Ayarlar: $($Konular.Count) konu, $($hd.Count) haric ifadesi, baslangic $($Ayar.baslangicTarihi)"

# ------------------------------------------------------------ marka cikarma
# Unvanin basindan, sektor/hukuki kelime gorunene kadar olan kisim marka sayilir.
# "KAPTAN DEMIR CELIK ENDUSTRISI VE TICARET A.S." -> "KAPTAN DEMIR CELIK"
$Durdurucu = @(
    'SANAYI','SANAYII','SAN','TICARET','TICARETI','TIC','ANONIM','SIRKETI','SIRKET','STI',
    'LIMITED','LTD','AS','A','S','VE','ITHALAT','IHRACAT','ITH','IHR','DIS','PAZARLAMA','PAZ',
    'NAKLIYAT','NAKLIYE','TAAHHUT','TAAH','MUHENDISLIK','MUH','INSAAT','INS','ENERJI','GIDA',
    'TURIZM','MADENCILIK','MADEN','PETROL','OTOMOTIV','TARIM','HAYVANCILIK','TEKSTIL','YATIRIM',
    'YATIRIMLARI','URETIM','URETIMI','ELEKTRIK','ELEKTRONIK','BILISIM','BILGISAYAR','GAYRIMENKUL',
    'LOJISTIK','SIGORTA','DANISMANLIK','IMALAT','YAYINCILIK','YAYIN','KIMYA','METAL','PLASTIK',
    'AMBALAJ','MOBILYA','SAGLIK','EGITIM','SAVUNMA','HAVACILIK','YAZILIM','ISLETMELERI',
    'ISLETMECILIGI','ISLETMESI','HIZMETLERI','HIZMET','TASIMACILIK','DEPOLAMA','TEKNOLOJI',
    'TEKNOLOJILERI','ILETISIM','SISTEMLERI','SISTEM','KIRALAMA','EMLAK','YAPI','KONUT','FINANSAL',
    'MENKUL','DEGERLER','KAGIT','KUYUMCULUK','PERAKENDE','MAGAZACILIK','DENIZCILIK','ACENTALIGI',
    'ARACILIK','KAUCUK','DAGITIM','URUNLERI','GEMI','BAKIM','ONARIM','ENDUSTRISI','ENDUSTRI',
    'TASARRUF','FINANSMAN','KATILIM','BANKASI','FZE','CO','KSCC','TRADING','INTERNATIONAL',
    'TASIMACILIGI','HAVA','YOLLARI','DOGAL','GAZ','PORTFOY','YONETIMI','YONETIM','SUBESI',
    'MERKEZ','MERKEZI','UNIVERSITESI','VAKFI','DERNEGI','ISLETME','ORGANIZASYON','MADENLER',
    'KIYMETLI','ARACILIK','TEMSILCILIK','ACENTELIGI','ETICARET','TELEKOMUNIKASYON'
)
$HukukiForm = @('SANAYI','TICARET','ANONIM','SIRKETI','SIRKET','STI','LIMITED','LTD','AS','A','S','VE','ITHALAT','IHRACAT','DIS')
$SirketIpucu = @('AS','A S','HOLDING','GRUP','SIRKET','SIRKETI','SIRKETINDE','FIRMA','FIRMASI','LTD','GROUP','INC','FABRIKA','MARKA')

function MarkaCikar([string]$unvan) {
    $n = Duzle $unvan
    if (-not $n) { return $null }
    $t = $n.Split(' ')
    $m = New-Object System.Collections.Generic.List[string]
    foreach ($w in $t) {
        if ($Durdurucu -contains $w) { break }
        if ($w.Length -le 1) { break }
        $m.Add($w)
        if ($m.Count -ge 3) { break }
    }
    if ($m.Count -eq 0) {
        foreach ($w in $t) { if ($w.Length -gt 2 -and $w -ne 'VE') { $m.Add($w) }; if ($m.Count -ge 2) { break } }
    }
    if ($m.Count -eq 0) { return $null }
    # Tek basina kalan 2-3 harfli kisaltma marka olmaz; sonraki anlamli kelimeyi ekle
    if ($m.Count -eq 1 -and $m[0].Length -le 3) {
        $ix = [array]::IndexOf($t, $m[0])
        for ($j = $ix + 1; $j -lt $t.Count; $j++) {
            if ($t[$j].Length -lt 3 -or ($HukukiForm -contains $t[$j])) { continue }
            $m.Add($t[$j]); break
        }
    }
    return ($m -join ' ')
}

# Unvandaki sektor kelimeleri: tek kelimelik markalarda dogrulama icin
function BaglamCikar([string]$unvan) {
    $b = @()
    foreach ($w in (Duzle $unvan).Split(' ')) {
        if ($w.Length -lt 4) { continue }
        if ($HukukiForm -contains $w) { continue }
        if ($Durdurucu -contains $w) { $b += $w }
        if ($b.Count -ge 3) { break }
    }
    return $b
}

# ------------------------------------------------------------- takma adlar
$Takma = @()
if (Test-Path $TakmaYolu) {
    foreach ($satir in (Get-Content $TakmaYolu -Encoding UTF8)) {
        if (-not $satir.Trim() -or $satir.TrimStart().StartsWith('#')) { continue }
        $p = $satir -split '\|'
        if ($p.Count -lt 2) { continue }
        $anahtar = Duzle $p[0]
        $adlar = @($p[1] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($anahtar -and $adlar.Count -gt 0) {
            $Takma += [pscustomobject]@{ Anahtar = $anahtar; Adlar = $adlar }
        }
    }
    Yaz "Takma ad kurali: $($Takma.Count)"
}

# -------------------------------------------------------------- musteriler
$Hedefler = New-Object System.Collections.Generic.List[object]
$TakipDisi = @()

foreach ($unvan in (Get-Content $MusteriYolu -Encoding UTF8)) {
    $unvan = $unvan.Trim()
    if (-not $unvan) { continue }
    $nUnvan = Duzle $unvan

    $adlar = $null
    foreach ($tk in $Takma) { if ($nUnvan -like ('*' + $tk.Anahtar + '*')) { $adlar = $tk.Adlar; break } }

    $tekil = $false
    if (-not $adlar) {
        $marka = MarkaCikar $unvan
        if (-not $marka) { $TakipDisi += "$unvan  ->  marka cikarilamadi"; continue }
        $par = $marka.Split(' ')
        if ($par.Count -eq 1) {
            if ($Jenerik -contains $par[0]) { $TakipDisi += "$unvan  ->  '$marka' cok genel"; continue }
            if ($par[0].Length -lt 4)        { $TakipDisi += "$unvan  ->  '$marka' cok kisa"; continue }
            $tekil = $true
        }
        $adlar = @($marka)
    }

    $desen = @()
    foreach ($a in $adlar) { $d = Duzle $a; if ($d) { $desen += ('\b' + [regex]::Escape($d) + '\b') } }
    if ($desen.Count -eq 0) { continue }

    $Hedefler.Add([pscustomobject]@{
        Unvan   = $unvan
        Adlar   = $adlar
        Desen   = $desen
        Tekil   = $tekil
        Baglam  = (BaglamCikar $unvan)
        Sorgu   = (($adlar | ForEach-Object { '"' + $_ + '"' }) -join ' OR ')
    })
}

# Ayni gruba ait birden fazla musteri ayni marka adina dusuyor (orn. uc ayri
# Ahlatci sirketi). Ayni sorguyu tekrar tekrar gondermeyelim: tek sorgu at,
# sonucu o marka adini paylasan butun musterilere yaz.
$Gruplu = New-Object System.Collections.Generic.List[object]
$Sozluk = @{}
foreach ($h in $Hedefler) {
    $anahtar = ($h.Adlar | ForEach-Object { Duzle $_ }) -join '|'
    if ($Sozluk.ContainsKey($anahtar)) {
        $g = $Sozluk[$anahtar]
        $g.Unvanlar += $h.Unvan
        foreach ($b in @($h.Baglam)) { if ($g.Baglam -notcontains $b) { $g.Baglam += $b } }
        if (-not $h.Tekil) { $g.Tekil = $false }
    } else {
        $g = [pscustomobject]@{
            Unvanlar = @($h.Unvan)
            Adlar    = $h.Adlar
            Desen    = $h.Desen
            Tekil    = $h.Tekil
            Baglam   = @($h.Baglam)
            Sorgu    = $h.Sorgu
        }
        $Sozluk[$anahtar] = $g
        $Gruplu.Add($g)
    }
}
$MusteriSayisi = $Hedefler.Count
$Hedefler = $Gruplu

if ($TakipDisi.Count -gt 0) {
    $TakipDisi | Set-Content -Path (Join-Path $VeriKlasor 'takip_disi.txt') -Encoding UTF8
}
$TumHedefler = $Hedefler
if ($Sinir -gt 0 -and $Hedefler.Count -gt $Sinir) {
    $Hedefler = [System.Collections.Generic.List[object]]@($Hedefler[0..($Sinir - 1)])
}
if ($Hedefler.Count -eq 0) { throw 'Taranacak musteri bulunamadi.' }

Yaz "Musteri listesi: $MusteriSayisi takip ediliyor / $($TakipDisi.Count) takip disi / $($TumHedefler.Count) benzersiz sorgu"

# ---------------------------------------------------------------- siniflama
# Basligi konulara gore etiketler. Hicbir konuya girmezse bos donerse haber
# "siniflandirilmamis" sayilir ve arayuzde varsayilan olarak gizlenir.
function KonulariBul([string]$duzBaslik) {
    $bulunan = @()
    foreach ($k in $Konular) { if ($duzBaslik -match $k.Desen) { $bulunan += $k.Id } }
    # Bos dizi dondururken virgul sart: yoksa PowerShell $null'a cevirir
    return ,$bulunan
}

function HaricMi([string]$duzBaslik) {
    if (-not $HaricDesen) { return $false }
    return ($duzBaslik -match $HaricDesen)
}

# Tek kelimelik markada kisi/yer adi karismasin diye ek dogrulama
function MusteriDogrula($hedef, [string]$duzBaslik) {
    if (-not $hedef.Tekil) { return $true }
    foreach ($b in @($hedef.Baglam))    { if ($duzBaslik -match ('\b' + [regex]::Escape($b) + '\b')) { return $true } }
    foreach ($i in $SirketIpucu)        { if ($duzBaslik -match ('\b' + [regex]::Escape($i) + '\b')) { return $true } }
    return $false
}

# -------------------------------------------------------------------- arsiv
$Arsiv = @{}
try {
    $Arsiv = ArsivOku $ArsivYolu
    if ($Arsiv.Count -gt 0) { Yaz "Arsiv yuklendi: $($Arsiv.Count) haber" }
    else { Yaz 'Arsiv yok, ilk tarama yapiliyor.' }
} catch {
    Yaz "Arsiv okunamadi, sifirdan baslaniyor: $($_.Exception.Message)" 'UYARI'
    $Arsiv = @{}
}

# --------------------------------------------------------------- haber cekme
$script:HataliSorgu = 0

function HaberCek([string]$sorgu) {
    $url = 'https://news.google.com/rss/search?q=' + [uri]::EscapeDataString($sorgu) + '&hl=tr&gl=TR&ceid=TR:tr'
    $r = $null
    for ($deneme = 1; $deneme -le 3; $deneme++) {
        try {
            $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30 -Headers @{ 'User-Agent' = 'Mozilla/5.0' }
            break
        } catch {
            if ($deneme -eq 3) {
                $script:HataliSorgu++
                Yaz "Sorgu basarisiz ($sorgu): $($_.Exception.Message)" 'UYARI'
                return @()
            }
            Start-Sleep -Seconds (3 * $deneme)
        }
    }
    try {
        [xml]$x = $r.Content
        $sonuc = @()
        foreach ($it in @($x.rss.channel.item)) {
            $baslik = [string]$it.title
            $kaynak = ''
            $i = $baslik.LastIndexOf(' - ')
            if ($i -gt 10) { $kaynak = $baslik.Substring($i + 3); $baslik = $baslik.Substring(0, $i) }
            if (-not $kaynak -and $it.source) { $kaynak = [string]$it.source.'#text' }
            $tarih = $null
            try { $tarih = [datetime]::Parse($it.pubDate, [Globalization.CultureInfo]::InvariantCulture) } catch { $tarih = Get-Date }
            $sonuc += [pscustomobject]@{
                Baslik = $baslik.Trim(); Kaynak = $kaynak.Trim()
                Link = [string]$it.link; Tarih = $tarih
            }
        }
        return $sonuc
    } catch {
        $script:HataliSorgu++
        Yaz "Cevap cozumlenemedi ($sorgu): $($_.Exception.Message)" 'UYARI'
        return @()
    }
}

# ------------------------------------------------------------------- tarama
$simdi = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
$yeniSayi = 0; $elenenHaric = 0; $sira = 0

foreach ($hedef in $Hedefler) {
    $sira++
    $bulunan = 0
    foreach ($h in (HaberCek $hedef.Sorgu)) {
        if ($h.Tarih -lt $Baslangic) { continue }
        $duz = Duzle $h.Baslik

        $uyuyor = $false
        foreach ($d in $hedef.Desen) { if ($duz -match $d) { $uyuyor = $true; break } }
        if (-not $uyuyor) { continue }
        if (-not (MusteriDogrula $hedef $duz)) { continue }

        if (HaricMi $duz) { $elenenHaric++; continue }

        $bulunan++
        $id = Kimlik ($duz + '|' + (Duzle $h.Kaynak))

        if ($Arsiv.ContainsKey($id)) {
            $kayit = $Arsiv[$id]
            foreach ($u in $hedef.Unvanlar) { if ($kayit.firmalar -notcontains $u) { $kayit.firmalar = @($kayit.firmalar) + $u } }
        } else {
            $Arsiv[$id] = YeniHaber $id $h.Baslik $h.Link $h.Kaynak `
                                    ($h.Tarih.ToString('yyyy-MM-ddTHH:mm:ss')) $simdi `
                                    (KonulariBul $duz) @($hedef.Unvanlar)
            $yeniSayi++
        }
    }
    if (-not $Sessiz) {
        $kisa = $hedef.Adlar[0]
        if ($kisa.Length -gt 34) { $kisa = $kisa.Substring(0, 34) }
        Write-Host ("  [{0,3}/{1}] {2,-36} {3,3} haber" -f $sira, $Hedefler.Count, $kisa, $bulunan)
    }
    Start-Sleep -Milliseconds $Bekleme
}

Yaz "Tarama bitti: $yeniSayi yeni haber, $elenenHaric alakasiz baslik elendi, $script:HataliSorgu hatali sorgu"

# ------------------------------------------------------------------ temizlik
if ($Temizle) {
    $silinen = 0; $yenidenEtiket = 0
    foreach ($id in @($Arsiv.Keys)) {
        $kayit = $Arsiv[$id]
        $duz = Duzle $kayit.baslik
        if (HaricMi $duz) { $Arsiv.Remove($id); $silinen++; continue }

        $yeniMusteri = @()
        foreach ($t in $TumHedefler) {
            $u = $false
            foreach ($d in $t.Desen) { if ($duz -match $d) { $u = $true; break } }
            if (-not $u) { continue }
            if (-not (MusteriDogrula $t $duz)) { continue }
            foreach ($u in $t.Unvanlar) { if ($yeniMusteri -notcontains $u) { $yeniMusteri += $u } }
        }
        if ($yeniMusteri.Count -eq 0) { $Arsiv.Remove($id); $silinen++; continue }
        $kayit.firmalar = $yeniMusteri
        $kayit.gruplar = KonulariBul $duz
        $yenidenEtiket++
    }
    Yaz "Temizlik: $silinen haber cikarildi, $yenidenEtiket haber yeniden etiketlendi"
}

# ------------------------------------------------------- arsivi budama/siralama
$Liste = @($Arsiv.Values | Where-Object { [datetime]$_.tarih -ge $Baslangic } |
           Sort-Object { [datetime]$_.tarih } -Descending)
if ($Liste.Count -gt $UstSinir) { $Liste = $Liste[0..($UstSinir - 1)] }

$icerikli = @($Liste | Where-Object { $_.durum -eq 'ok' }).Count
$konulu   = @($Liste | Where-Object { @($_.gruplar).Count -gt 0 }).Count

$meta = '{"sonTarama":' + (JsonMetin $simdi) +
        ',"baslangicTarihi":' + (JsonMetin $Ayar.baslangicTarihi) +
        ',"toplamHaber":' + $Liste.Count +
        ',"konuluHaber":' + $konulu +
        ',"yeniHaber":' + $yeniSayi +
        ',"icerikliHaber":' + $icerikli +
        ',"takipEdilenFirma":' + $MusteriSayisi +
        ',"hataliSorgu":' + $script:HataliSorgu + '}'

$MusteriAdlari = @($TumHedefler | ForEach-Object { $_.Unvanlar }) | Sort-Object -Unique
VeriYaz $ArsivYolu $WebYolu $Liste $Konular $MusteriAdlari $meta

Yaz "Yazildi: $($Liste.Count) haber ($konulu konulu) -> data\haberler.js"
if ($script:HataliSorgu -gt 0) {
    Yaz "$script:HataliSorgu sorgu yanit alamadi; bu taramanin kapsami eksik olabilir." 'UYARI'
}
Yaz 'Tamamlandi.'

} finally {
    KilitBirak
}
