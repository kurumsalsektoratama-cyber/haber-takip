#Requires -Version 5.1
<#
    Zamanlanmis gorevin calistirdigi betik: once yeni haberleri bulur,
    sonra icerigi eksik olanlarin metnini ve gorselini indirir.

      .\Otomatik.ps1              -> tarama + 200 haberlik icerik
      .\Otomatik.ps1 -Icerik 500  -> icerik adedini degistir

    Not: bu dosya SADECE ASCII karakter icerir (bkz. Ortak.ps1 aciklamasi).
#>
[CmdletBinding()]
param(
    [int]$Icerik = 200
)

$Kok = $PSScriptRoot
if (-not $Kok) { $Kok = Split-Path -Parent $MyInvocation.MyCommand.Definition }

# Biri hata verirse digeri yine de calissin
try {
    & (Join-Path $Kok 'Tara.ps1') -Sessiz
} catch {
    Write-Host "Tara.ps1 hata verdi: $($_.Exception.Message)"
}

try {
    & (Join-Path $Kok 'Icerik.ps1') -Adet $Icerik -Sessiz
} catch {
    Write-Host "Icerik.ps1 hata verdi: $($_.Exception.Message)"
}
