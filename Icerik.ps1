#Requires -Version 5.1
<#
    Avrupa Kurumsal Bulten - icerik cekme (2. asama: haberi okunabilir hale getir)

    Arsivdeki haberlerin gercek adresini cozer, haber sayfasini indirir ve
    gorsel + ozet + metin bilgisini arsive yazar. Boylece haberler uygulamanin
    icinde okunabilir olur.

    Kullanim:
      .\Icerik.ps1               -> icerigi olmayan en yeni 150 haberi doldur
      .\Icerik.ps1 -Adet 500     -> daha fazlasini doldur (uzun surer)
      .\Icerik.ps1 -Yeniden      -> daha once basarisiz olanlari tekrar dene
      .\Icerik.ps1 -Sessiz       -> ekrana az yaz (zamanlanmis gorev icin)

    Her haber icin 3 istek gider (cozumleme + cozumleme + sayfa), yaklasik
    2 saniye surer. 150 haber ~ 5 dakika.

    Not: bu dosya SADECE ASCII karakter icerir (bkz. Ortak.ps1 aciklamasi).
#>
[CmdletBinding()]
param(
    [int]$Adet = 150,
    [switch]$Yeniden,
    [switch]$Sessiz
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

$Kok = $PSScriptRoot
if (-not $Kok) { $Kok = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Kok 'Ortak.ps1')

$VeriKlasor = Join-Path $Kok 'data'
$ArsivYolu  = Join-Path $VeriKlasor 'haberler.json'
$WebYolu    = Join-Path $VeriKlasor 'haberler.js'
$LogYolu    = Join-Path $VeriKlasor 'log.txt'

$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'
$METIN_SINIR = 6000

function Yaz([string]$m, [string]$seviye = 'BILGI') {
    $satir = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $seviye, $m
    if (-not $Sessiz -or $seviye -ne 'BILGI') { Write-Host $satir }
    try { Add-Content -Path $LogYolu -Value $satir -Encoding UTF8 } catch { }
}

if (-not (Test-Path $VeriKlasor)) { throw "Arsiv yok. Once Tara.ps1 calistirin." }

# Tara.ps1 ayni anda calisiyorsa arsivi birbirimizin ustune yazmayalim
if (-not (KilitAl (Join-Path $VeriKlasor 'kilit'))) {
    Yaz 'Baska bir tarama/icerik islemi calisiyor, bu calisma atlandi.' 'UYARI'
    return
}
try {

if (-not (Test-Path $ArsivYolu)) { throw "Arsiv yok. Once Tara.ps1 calistirin." }

# Konu ve musteri listeleri Tara.ps1'in yazdigi dosyadan aynen korunur;
# bu betik yalnizca haberlerin icerigini dolduruyor.
$Konular    = KonulariOku $ArsivYolu
$Musteriler = MusterileriOku $ArsivYolu

# ------------------------------------------------------------- html araclari
# WebUtility hem Windows PowerShell 5.1'de hem GitHub'daki PowerShell 7 /
# Linux ortaminda calisir; System.Web orada yok.
function HtmlCoz([string]$s) {
    if (-not $s) { return '' }
    try { return [System.Net.WebUtility]::HtmlDecode($s) } catch { return $s }
}

function EtiketTemizle([string]$html) {
    if (-not $html) { return '' }
    $t = [regex]::Replace($html, '<[^>]+>', ' ')
    $t = HtmlCoz $t
    return ($t -replace '\s+', ' ').Trim()
}

# <meta property="og:image" content="..."> - oznitelik sirasi degisebilir
function MetaBul([string]$html, [string]$ad) {
    $desenler = @(
        '<meta[^>]+(?:property|name)\s*=\s*["'']' + [regex]::Escape($ad) + '["''][^>]*content\s*=\s*["'']([^"'']+)["'']',
        '<meta[^>]+content\s*=\s*["'']([^"'']+)["''][^>]*(?:property|name)\s*=\s*["'']' + [regex]::Escape($ad) + '["'']'
    )
    foreach ($d in $desenler) {
        $m = [regex]::Match($html, $d, 'IgnoreCase')
        if ($m.Success) { return (HtmlCoz $m.Groups[1].Value).Trim() }
    }
    return ''
}

# Haber gorselini bulur: once meta etiketleri, olmazsa sayfadaki ilk buyuk resim.
function GorselBul([string]$html) {
    foreach ($ad in @('og:image', 'og:image:url', 'twitter:image', 'twitter:image:src')) {
        $g = MetaBul $html $ad
        if ($g) { return $g }
    }
    $m = [regex]::Match($html, '<link[^>]+rel\s*=\s*["'']image_src["''][^>]*href\s*=\s*["'']([^"'']+)["'']', 'IgnoreCase')
    if ($m.Success) { return (HtmlCoz $m.Groups[1].Value).Trim() }

    # JSON-LD icindeki "image" alani
    $m = [regex]::Match($html, '"image"\s*:\s*(?:\[\s*)?(?:\{[^}]*"url"\s*:\s*)?"(https?://[^"]{15,300})"', 'IgnoreCase')
    if ($m.Success) { return (HtmlCoz $m.Groups[1].Value).Trim() }

    # Son care: sayfa govdesindeki ilk makul boyutlu resim
    $g = [regex]::Replace($html, '(?is)<(script|style|noscript|header|footer|nav|aside)\b.*?</\1\s*>', ' ')
    foreach ($m in [regex]::Matches($g, '(?i)<img[^>]+?(?:data-src|data-original|src)\s*=\s*["'']([^"'']{15,300})["'']')) {
        $u = (HtmlCoz $m.Groups[1].Value).Trim()
        if ($u -match '(?i)^data:|\.svg|logo|icon|avatar|sprite|placeholder|blank|pixel|1x1|spacer') { continue }
        return $u
    }
    return ''
}

# Sayfadaki paragraflardan haber metnini cikarir.
function MetinCikar([string]$html) {
    # Once icerik olmayan bloklari at
    $g = [regex]::Replace($html, '(?is)<(script|style|noscript|iframe|svg|form|nav|header|footer|aside)\b.*?</\1\s*>', ' ')

    $paragraflar = @()
    $toplam = 0
    foreach ($m in [regex]::Matches($g, '(?is)<p\b[^>]*>(.*?)</p\s*>')) {
        $p = EtiketTemizle $m.Groups[1].Value
        if ($p.Length -lt 40) { continue }
        # Cerez / abonelik / telif uyarilarini atla. Karsilastirma Duzle ile
        # yapiliyor: "cerez" ve "cerez" (c cedilli) ayni sekilde yakalanir.
        if ((Duzle $p) -match 'CEREZ|KVKK|ABONE OL|TUM HAKLARI|COPYRIGHT|YORUM YAZ|IZINSIZ ALINTI') { continue }
        if ($paragraflar -contains $p) { continue }
        $paragraflar += $p
        $toplam += $p.Length
        if ($toplam -ge $METIN_SINIR) { break }
    }
    return ($paragraflar -join "`n`n")
}

# ------------------------------------------------- google haber adresi cozme
# Google Haberler gercek adresi imzali bir uc noktanin arkasinda tutuyor:
# once haber sayfasindaki imza alanlari okunur, sonra batchexecute'a sorulur.
function GercekAdres([string]$googleLink) {
    if ($googleLink -notmatch 'news\.google\.com') { return $googleLink }

    $r = Invoke-WebRequest -Uri $googleLink -UseBasicParsing -TimeoutSec 25 -Headers @{ 'User-Agent' = $UA }
    $c = $r.Content
    $id = ''; $sg = ''; $ts = ''
    $m = [regex]::Match($c, 'data-n-a-id="([^"]+)"'); if ($m.Success) { $id = $m.Groups[1].Value }
    $m = [regex]::Match($c, 'data-n-a-sg="([^"]+)"'); if ($m.Success) { $sg = $m.Groups[1].Value }
    $m = [regex]::Match($c, 'data-n-a-ts="([^"]+)"'); if ($m.Success) { $ts = $m.Groups[1].Value }
    if (-not $id -or -not $sg -or -not $ts) { throw 'imza alanlari bulunamadi' }

    $ic = '["garturlreq",[["tr","TR",["FINANCE_TOP_INDICES","WEB_TEST_1_0_0"],null,null,1,1,"TR:tr",' +
          'null,180,null,null,null,null,null,0,null,null,[1608992183,723341000]],"tr","TR",1,[2,3,4,8],' +
          '1,0,"655000234",0,0,null,0],"' + $id + '",' + $ts + ',"' + $sg + '"]'
    $freq = ConvertTo-Json @(, @(, @('Fbv4je', $ic, $null, 'generic'))) -Compress -Depth 6
    $govde = 'f.req=' + [uri]::EscapeDataString($freq)

    $p = Invoke-WebRequest -Uri 'https://news.google.com/_/DotsSplashUi/data/batchexecute?rpcids=Fbv4je' `
        -Method Post -Body $govde -ContentType 'application/x-www-form-urlencoded;charset=UTF-8' `
        -UseBasicParsing -TimeoutSec 25 -Headers @{ 'User-Agent' = $UA }

    foreach ($m in [regex]::Matches($p.Content, 'https?://[^"\\\s]{10,300}')) {
        $u = $m.Value
        if ($u -match 'google\.com|gstatic\.com|googleapis\.com|schema\.org') { continue }
        if ($u -match '/amp/|\.amp\.html') { continue }   # amp yerine normal sayfayi tercih et
        return $u
    }
    throw 'gercek adres cozulemedi'
}

# --------------------------------------------------------------------- arsiv
$Arsiv = ArsivOku $ArsivYolu
if ($Arsiv.Count -eq 0) { throw 'Arsiv bos. Once Tara.ps1 calistirin.' }

$Hedef = @($Arsiv.Values |
    Where-Object { $_.durum -ne 'ok' -and ($Yeniden -or $_.durum -ne 'hata') } |
    Sort-Object { [datetime]$_.tarih } -Descending)

if ($Hedef.Count -eq 0) {
    Yaz 'Icerigi eksik haber yok, yapilacak bir sey yok.'
    return
}
if ($Adet -gt 0 -and $Hedef.Count -gt $Adet) { $Hedef = $Hedef[0..($Adet - 1)] }

Yaz "Icerik cekiliyor: $($Hedef.Count) haber (arsivde toplam $($Arsiv.Count))"

# ------------------------------------------------------------------- dongu
$basarili = 0; $basarisiz = 0; $sira = 0
foreach ($h in $Hedef) {
    $sira++
    $sonuc = 'hata'
    try {
        if (-not $h.gercekLink) { $h.gercekLink = GercekAdres $h.link }

        $r = Invoke-WebRequest -Uri $h.gercekLink -UseBasicParsing -TimeoutSec 25 `
             -Headers @{ 'User-Agent' = $UA; 'Accept-Language' = 'tr-TR,tr;q=0.9' }
        $c = $r.Content

        $h.gorsel = GorselBul $c
        $h.ozet = MetaBul $c 'og:description'
        if (-not $h.ozet) { $h.ozet = MetaBul $c 'description' }
        $h.metin = MetinCikar $c

        # Gorsel adresi goreli olabilir; mutlak adrese cevir
        if ($h.gorsel -and $h.gorsel -notmatch '^https?://') {
            try {
                $taban = New-Object System.Uri($h.gercekLink)
                $h.gorsel = (New-Object System.Uri($taban, $h.gorsel)).AbsoluteUri
            } catch { $h.gorsel = '' }
        }

        if ($h.metin.Length -ge 200 -or $h.ozet.Length -ge 80) { $sonuc = 'ok'; $basarili++ }
        else { $basarisiz++ }
    } catch {
        $basarisiz++
        if (-not $Sessiz) { Write-Host ("      -> " + $_.Exception.Message) -ForegroundColor DarkGray }
    }
    $h.durum = $sonuc

    if (-not $Sessiz) {
        $kisa = $h.baslik
        if ($kisa.Length -gt 52) { $kisa = $kisa.Substring(0, 52) + '...' }
        Write-Host ("  [{0,4}/{1}] {2,-4} {3,5} krkt  {4}" -f $sira, $Hedef.Count, $sonuc, $h.metin.Length, $kisa)
    }

    # Her 25 haberde bir kaydet ki uzun calismada is kaybolmasin
    if ($sira % 25 -eq 0) {
        $ara = @($Arsiv.Values | Sort-Object { [datetime]$_.tarih } -Descending)
        $eskiMeta = MetaOku $ArsivYolu
        $metaJson = MetaGuncelle $eskiMeta $ara
        VeriYaz $ArsivYolu $WebYolu $ara $Konular $Musteriler $metaJson
    }
    Start-Sleep -Milliseconds 400
}

# ------------------------------------------------------------------- kaydet
$Liste = @($Arsiv.Values | Sort-Object { [datetime]$_.tarih } -Descending)
$eskiMeta = MetaOku $ArsivYolu
VeriYaz $ArsivYolu $WebYolu $Liste $Konular $Musteriler (MetaGuncelle $eskiMeta $Liste)

$kalan = @($Arsiv.Values | Where-Object { $_.durum -eq '' }).Count
Yaz "Icerik bitti: $basarili basarili, $basarisiz basarisiz. Icerigi bekleyen: $kalan"
Yaz 'Tamamlandi.'

} finally {
    KilitBirak
}
