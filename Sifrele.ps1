#Requires -Version 7.0
<#
    Haber arsivini yayina hazirlar: sikistirir ve sifreler.

    Yayinlanan site herkese acik bir adreste duruyor; veri dosyasi bu betikle
    sifrelendigi icin parolayi bilmeyen indirse bile okuyamaz. Cozme islemi
    tarayicida (js/app.js) yapilir.

      pwsh ./Sifrele.ps1 -Giris data/haberler.json -Cikis data/haberler.enc -Parola "..."
      pwsh ./Sifrele.ps1 -Coz -Giris data/haberler.enc -Cikis data/haberler.json -Parola "..."

    PowerShell 7 gerekir (AesGcm .NET Framework 4.8'de yok). GitHub Actions
    ortaminda calisir; Windows'ta gerekmez, orada veri zaten duz duruyor.

    Bicim: {"v":1,"it":<tur>,"salt":b64,"iv":b64,"ct":b64}
    ct = AES-GCM sifreli metin + 16 baytlik dogrulama etiketi (WebCrypto boyle bekler)

    Not: bu dosya SADECE ASCII karakter icerir.
#>
[CmdletBinding()]
param(
    [switch]$Coz,
    [Parameter(Mandatory = $true)][string]$Giris,
    [Parameter(Mandatory = $true)][string]$Cikis,
    [string]$Parola = ''
)

$ErrorActionPreference = 'Stop'

if (-not $Parola) { $Parola = $env:VERI_PAROLASI }
if (-not $Parola) { throw 'Parola verilmedi. -Parola ile ya da VERI_PAROLASI ortam degiskeniyle gecin.' }
if (-not (Test-Path $Giris)) { throw "Giris dosyasi yok: $Giris" }

$TUR = 600000   # PBKDF2 tur sayisi (OWASP onerisi); tarayici tarafiyla ayni olmali

function AnahtarUret([string]$parola, [byte[]]$tuz) {
    $kdf = [System.Security.Cryptography.Rfc2898DeriveBytes]::new(
        $parola, $tuz, $TUR, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    try { return $kdf.GetBytes(32) } finally { $kdf.Dispose() }
}

function GcmAc([byte[]]$anahtar) {
    # .NET 8 etiket boyutunu zorunlu kiliyor, eski surumlerde tek parametreli
    try { return [System.Security.Cryptography.AesGcm]::new($anahtar, 16) }
    catch { return [System.Security.Cryptography.AesGcm]::new($anahtar) }
}

function Sikistir([byte[]]$veri) {
    $cikti = [System.IO.MemoryStream]::new()
    $gz = [System.IO.Compression.GZipStream]::new($cikti, [System.IO.Compression.CompressionLevel]::Optimal)
    $gz.Write($veri, 0, $veri.Length)
    $gz.Dispose()
    return $cikti.ToArray()
}

function Ac([byte[]]$veri) {
    $giris = [System.IO.MemoryStream]::new($veri)
    $gz = [System.IO.Compression.GZipStream]::new($giris, [System.IO.Compression.CompressionMode]::Decompress)
    $cikti = [System.IO.MemoryStream]::new()
    $gz.CopyTo($cikti)
    $gz.Dispose()
    return $cikti.ToArray()
}

if (-not $Coz) {
    # ---------------------------------------------------------------- sifrele
    $duz = [System.IO.File]::ReadAllBytes($Giris)
    $kucuk = Sikistir $duz

    $iv = [byte[]]::new(12)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($iv)   # her sifrelemede farkli olmali, bu sart

    # Tuz ayni kalabilir (gizli degildir, gorevi hazir tablo saldirisini
    # engellemek). Sabit tutunca tarayici anahtari bir kez uretip saklayabiliyor;
    # her yenilemede 600 bin turluk hesabi bastan yapmasi gerekmiyor.
    $tuz = $null
    if (Test-Path $Cikis) {
        try {
            $eski = Get-Content $Cikis -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($eski.salt) { $tuz = [Convert]::FromBase64String($eski.salt) }
        } catch { $tuz = $null }
    }
    if (-not $tuz -or $tuz.Length -ne 16) {
        $tuz = [byte[]]::new(16)
        $rng.GetBytes($tuz)
    }

    $anahtar = AnahtarUret $Parola $tuz
    $gcm = GcmAc $anahtar
    $sifreli = [byte[]]::new($kucuk.Length)
    $etiket  = [byte[]]::new(16)
    $gcm.Encrypt($iv, $kucuk, $sifreli, $etiket)
    $gcm.Dispose()

    # WebCrypto sifreli metin ile etiketi bitisik bekler
    $govde = [byte[]]::new($sifreli.Length + 16)
    [Array]::Copy($sifreli, 0, $govde, 0, $sifreli.Length)
    [Array]::Copy($etiket, 0, $govde, $sifreli.Length, 16)

    $paket = [ordered]@{
        v    = 1
        it   = $TUR
        salt = [Convert]::ToBase64String($tuz)
        iv   = [Convert]::ToBase64String($iv)
        ct   = [Convert]::ToBase64String($govde)
    }
    $json = $paket | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText($Cikis, $json, [System.Text.UTF8Encoding]::new($false))

    $o = [Math]::Round($duz.Length / 1MB, 2)
    $y = [Math]::Round((Get-Item $Cikis).Length / 1MB, 2)
    Write-Host "Sifrelendi: $o MB -> $y MB  ($Cikis)"
} else {
    # ------------------------------------------------------------------ coz
    $paket = Get-Content $Giris -Raw -Encoding UTF8 | ConvertFrom-Json
    $tuz = [Convert]::FromBase64String($paket.salt)
    $iv  = [Convert]::FromBase64String($paket.iv)
    $govde = [Convert]::FromBase64String($paket.ct)

    $sifreli = [byte[]]::new($govde.Length - 16)
    $etiket  = [byte[]]::new(16)
    [Array]::Copy($govde, 0, $sifreli, 0, $sifreli.Length)
    [Array]::Copy($govde, $sifreli.Length, $etiket, 0, 16)

    $anahtar = AnahtarUret $Parola $tuz
    $gcm = GcmAc $anahtar
    $kucuk = [byte[]]::new($sifreli.Length)
    try {
        $gcm.Decrypt($iv, $sifreli, $etiket, $kucuk)
    } catch {
        throw 'Cozulemedi. Parola yanlis ya da dosya bozuk.'
    } finally { $gcm.Dispose() }

    $duz = Ac $kucuk
    [System.IO.File]::WriteAllBytes($Cikis, $duz)
    Write-Host "Cozuldu: $Cikis ($([Math]::Round($duz.Length / 1MB, 2)) MB)"
}
