#Requires -Version 5.1
<#
    Ortak yardimci fonksiyonlar. Tara.ps1 ve Icerik.ps1 bu dosyayi dot-source eder:
        . (Join-Path $PSScriptRoot 'Ortak.ps1')

    Not: bu dosya SADECE ASCII karakter icerir. Windows PowerShell 5.1, BOM'suz
    kaydedilmis betikleri ANSI sanip Turkce harfleri bozar.
#>

# ------------------------------------------------------- metin normalizasyon
# Turkce karakterleri sadelestirip buyuk harfe cevirir; noktalama bosluk olur.
# Boylece "Turk Telekom'un" ile "TURK TELEKOM" ayni sekilde eslesir.
$script:HarfMap = @{}
$HarfCiftleri = @(
    0x0131, 'i', 0x0130, 'i',   # i (noktasiz) / I (noktali)
    0x015F, 's', 0x015E, 's',   # s / S
    0x011F, 'g', 0x011E, 'g',   # g / G
    0x00FC, 'u', 0x00DC, 'u',   # u / U
    0x00F6, 'o', 0x00D6, 'o',   # o / O
    0x00E7, 'c', 0x00C7, 'c',   # c / C
    0x00E2, 'a', 0x00C2, 'a',   # a inceltme
    0x00EE, 'i', 0x00CE, 'i',   # i inceltme
    0x00FB, 'u', 0x00DB, 'u',   # u inceltme
    0x00E9, 'e', 0x00C9, 'e'    # e aksan
)
for ($i = 0; $i -lt $HarfCiftleri.Count; $i += 2) {
    $script:HarfMap[[string][char][int]$HarfCiftleri[$i]] = [string]$HarfCiftleri[$i + 1]
}

function Duzle([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return '' }
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        $k = [string]$ch
        if ($script:HarfMap.ContainsKey($k)) { [void]$sb.Append($script:HarfMap[$k]) }
        elseif ([char]::IsLetterOrDigit($ch)) { [void]$sb.Append($ch) }
        else { [void]$sb.Append(' ') }
    }
    return (($sb.ToString().ToUpperInvariant()) -replace '\s+', ' ').Trim()
}

function Kimlik([string]$metin) {
    $sha = [System.Security.Cryptography.SHA1]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($metin)
    return ([System.BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').Substring(0, 16)
}

function JsonMetin([string]$s) {
    if ($null -eq $s) { return '""' }
    $t = $s -replace '\\', '\\' -replace '"', '\"'
    $t = $t -replace "`r", ' ' -replace "`n", '\n' -replace "`t", ' '
    $t = [regex]::Replace($t, '[\x00-\x09\x0B-\x1F]', ' ')
    return '"' + $t + '"'
}

# ConvertFrom-Json ile gelen nesnede olmayan alani sormak hata vermesin diye
function Alan($nesne, [string]$ad) {
    if ($null -eq $nesne) { return '' }
    if ($nesne.PSObject.Properties.Name -contains $ad) { return [string]$nesne.$ad }
    return ''
}

function YeniHaber([string]$id, [string]$baslik, [string]$link, [string]$kaynak,
                   [string]$tarih, [string]$eklendi, $gruplar, $firmalar) {
    return [pscustomobject]@{
        id         = $id
        baslik     = $baslik
        link       = $link          # Google Haberler yonlendirme adresi
        gercekLink = ''             # cozumlenen gercek haber adresi
        kaynak     = $kaynak
        tarih      = $tarih
        eklendi    = $eklendi
        gruplar    = @($gruplar  | Where-Object { $_ })
        firmalar   = @($firmalar | Where-Object { $_ })
        gorsel     = ''             # haber gorseli (og:image)
        ozet       = ''             # kisa ozet (og:description)
        metin      = ''             # cikarilan haber metni
        durum      = ''             # '' denenmedi | 'ok' | 'hata'
    }
}

# ------------------------------------------------------------------- kilit
# Tara.ps1 ve Icerik.ps1 ayni arsiv dosyasini bastan sona okuyup yeniden
# yaziyor. Ikisi ayni anda calisirsa sonra biten digerinin isini siler.
# Kilit dosyasi paylasimsiz acilir; surec biterse isletim sistemi otomatik
# birakir, yani takili kalma riski yok.
$script:KilitAkis = $null

function KilitAl([string]$yol) {
    try {
        $script:KilitAkis = [System.IO.File]::Open($yol, 'OpenOrCreate', 'ReadWrite', 'None')
        return $true
    } catch {
        return $false
    }
}

function KilitBirak() {
    if ($script:KilitAkis) {
        try { $script:KilitAkis.Close() } catch { }
        $script:KilitAkis = $null
    }
}

# ------------------------------------------------------------------- arsiv
function ArsivOku([string]$yol) {
    $arsiv = @{}
    if (-not (Test-Path $yol)) { return $arsiv }
    $eski = Get-Content $yol -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($h in @($eski.haberler)) {
        $k = YeniHaber ([string]$h.id) ([string]$h.baslik) ([string]$h.link) ([string]$h.kaynak) `
                       ([string]$h.tarih) ([string]$h.eklendi) @($h.gruplar) @($h.firmalar)
        $k.gercekLink = Alan $h 'gercekLink'
        $k.gorsel     = Alan $h 'gorsel'
        $k.ozet       = Alan $h 'ozet'
        $k.metin      = Alan $h 'metin'
        $k.durum      = Alan $h 'durum'
        $arsiv[$k.id] = $k
    }
    return $arsiv
}

function HaberlerJson($liste) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('[')
    $ilk = $true
    foreach ($h in $liste) {
        if (-not $ilk) { [void]$sb.Append(',') }
        $ilk = $false
        $gr = (@($h.gruplar)  | ForEach-Object { JsonMetin $_ }) -join ','
        $fr = (@($h.firmalar) | ForEach-Object { JsonMetin $_ }) -join ','
        [void]$sb.Append('{"id":')         ; [void]$sb.Append((JsonMetin $h.id))
        [void]$sb.Append(',"baslik":')     ; [void]$sb.Append((JsonMetin $h.baslik))
        [void]$sb.Append(',"link":')       ; [void]$sb.Append((JsonMetin $h.link))
        [void]$sb.Append(',"gercekLink":') ; [void]$sb.Append((JsonMetin $h.gercekLink))
        [void]$sb.Append(',"kaynak":')     ; [void]$sb.Append((JsonMetin $h.kaynak))
        [void]$sb.Append(',"tarih":')      ; [void]$sb.Append((JsonMetin $h.tarih))
        [void]$sb.Append(',"eklendi":')    ; [void]$sb.Append((JsonMetin $h.eklendi))
        [void]$sb.Append(',"gorsel":')     ; [void]$sb.Append((JsonMetin $h.gorsel))
        [void]$sb.Append(',"ozet":')       ; [void]$sb.Append((JsonMetin $h.ozet))
        [void]$sb.Append(',"metin":')      ; [void]$sb.Append((JsonMetin $h.metin))
        [void]$sb.Append(',"durum":')      ; [void]$sb.Append((JsonMetin $h.durum))
        [void]$sb.Append(',"gruplar":[')   ; [void]$sb.Append($gr) ; [void]$sb.Append(']')
        [void]$sb.Append(',"firmalar":[')  ; [void]$sb.Append($fr) ; [void]$sb.Append(']}')
    }
    [void]$sb.Append(']')
    return $sb.ToString()
}

# Arayuzun yan menusunde renkli kategori olarak gorunen konular
function KonularJson($konular) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('[')
    $ilk = $true
    foreach ($k in $konular) {
        if (-not $ilk) { [void]$sb.Append(',') }
        $ilk = $false
        [void]$sb.Append('{"id":')   ; [void]$sb.Append((JsonMetin $k.id))
        [void]$sb.Append(',"ad":')   ; [void]$sb.Append((JsonMetin $k.ad))
        [void]$sb.Append(',"renk":') ; [void]$sb.Append((JsonMetin $k.renk))
        [void]$sb.Append('}')
    }
    [void]$sb.Append(']')
    return $sb.ToString()
}

function MetinListesiJson($liste) {
    return '[' + ((@($liste) | ForEach-Object { JsonMetin $_ }) -join ',') + ']'
}

# Hem arsiv (haberler.json) hem arayuzun okudugu kopya (haberler.js) yazilir.
# gruplar alani konulari, musteriler alani takip edilen firma adlarini tasir.
function VeriYaz([string]$arsivYolu, [string]$webYolu, $liste, $konular, $musteriler, [string]$metaJson) {
    $govde = '{"meta":' + $metaJson +
             ',"gruplar":' + (KonularJson $konular) +
             ',"musteriler":' + (MetinListesiJson $musteriler) +
             ',"haberler":' + (HaberlerJson $liste) + '}'
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($arsivYolu, $govde, $utf8)
    [System.IO.File]::WriteAllText($webYolu, "window.HABER_VERISI = $govde;", $utf8)

    # Kucucuk surum dosyasi: telefon once buna bakip veri degismediyse
    # sifreli arsivi bastan indirmiyor. Degerler metaJson'dan aynen aliniyor;
    # ConvertFrom-Json kullanilsa PS7 tarihi DateTime'a cevirip bicimi bozuyor.
    $t = [regex]::Match($metaJson, '"sonTarama":"([^"]*)"')
    $a = [regex]::Match($metaJson, '"toplamHaber":(\d+)')
    $i = [regex]::Match($metaJson, '"icerikliHaber":(\d+)')
    $surum = '{"sonTarama":"' + $t.Groups[1].Value + '"' +
             ',"toplam":'     + $(if ($a.Success) { $a.Groups[1].Value } else { '0' }) +
             ',"okunabilir":' + $(if ($i.Success) { $i.Groups[1].Value } else { '0' }) + '}'
    [System.IO.File]::WriteAllText((Join-Path (Split-Path $webYolu -Parent) 'surum.json'), $surum, $utf8)
}

# Onceki yazimdan musteri listesini geri okur (Icerik.ps1 icin)
function MusterileriOku([string]$yol) {
    if (-not (Test-Path $yol)) { return @() }
    try { return @((Get-Content $yol -Raw -Encoding UTF8 | ConvertFrom-Json).musteriler) } catch { return @() }
}

function KonulariOku([string]$yol) {
    if (-not (Test-Path $yol)) { return @() }
    try { return @((Get-Content $yol -Raw -Encoding UTF8 | ConvertFrom-Json).gruplar) } catch { return @() }
}

# Onceki meta bilgisini korumak icin (Icerik.ps1 tarama sayilarini degistirmez)
function MetaOku([string]$yol) {
    if (-not (Test-Path $yol)) { return $null }
    try { return (Get-Content $yol -Raw -Encoding UTF8 | ConvertFrom-Json).meta } catch { return $null }
}

# Tarama alanlarini oldugu gibi birakip sadece sayilari tazeler.
function MetaGuncelle($eskiMeta, $liste) {
    $icerikli = @($liste | Where-Object { $_.durum -eq 'ok' }).Count
    $sonTarama       = Alan $eskiMeta 'sonTarama'
    $baslangicTarihi = Alan $eskiMeta 'baslangicTarihi'
    $yeniHaber       = 0
    $takipEdilen     = 0
    $hataliSorgu     = 0
    if ($eskiMeta) {
        if ($eskiMeta.PSObject.Properties.Name -contains 'yeniHaber')       { $yeniHaber   = [int]$eskiMeta.yeniHaber }
        if ($eskiMeta.PSObject.Properties.Name -contains 'takipEdilenFirma') { $takipEdilen = [int]$eskiMeta.takipEdilenFirma }
        if ($eskiMeta.PSObject.Properties.Name -contains 'hataliSorgu')      { $hataliSorgu = [int]$eskiMeta.hataliSorgu }
    }
    return '{"sonTarama":' + (JsonMetin $sonTarama) +
           ',"baslangicTarihi":' + (JsonMetin $baslangicTarihi) +
           ',"toplamHaber":' + $liste.Count +
           ',"yeniHaber":' + $yeniHaber +
           ',"icerikliHaber":' + $icerikli +
           ',"takipEdilenFirma":' + $takipEdilen +
           ',"hataliSorgu":' + $hataliSorgu +
           ',"sonIcerik":' + (JsonMetin ((Get-Date).ToString('yyyy-MM-ddTHH:mm:ss'))) + '}'
}
