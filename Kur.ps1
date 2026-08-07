#Requires -Version 5.1
<#
    Otomatik tarama icin Windows Gorev Zamanlayici kaydi olusturur.
    Yonetici yetkisi gerekmez (kullanici bazli gorev).

      .\Kur.ps1               -> her 3 saatte bir tarar
      .\Kur.ps1 -Saatte 1     -> her saat basi tarar
      .\Kur.ps1 -Kaldir       -> gorevi siler
#>
[CmdletBinding()]
param(
    [int]$Saatte = 3,
    [switch]$Kaldir
)

$ErrorActionPreference = 'Stop'
$Kok      = Split-Path -Parent $MyInvocation.MyCommand.Definition
$Betik    = Join-Path $Kok 'Otomatik.ps1'
$GorevAdi = 'HaberTakip'

if ($Kaldir) {
    Unregister-ScheduledTask -TaskName $GorevAdi -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Gorev kaldirildi: $GorevAdi"
    return
}

if (-not (Test-Path $Betik)) { throw "Otomatik.ps1 bulunamadi: $Betik" }
if ($Saatte -lt 1 -or $Saatte -gt 24) { throw "-Saatte degeri 1 ile 24 arasinda olmali." }

$eylem = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Betik`"" `
    -WorkingDirectory $Kok

# Ilk calisma 2 dakika sonra, sonrasinda belirtilen aralikla suresiz tekrar.
$tetik = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) `
    -RepetitionInterval (New-TimeSpan -Hours $Saatte)

$ayar = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -DontStopOnIdleEnd `
    -ExecutionTimeLimit (New-TimeSpan -Hours 2) `
    -MultipleInstances IgnoreNew

Unregister-ScheduledTask -TaskName $GorevAdi -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $GorevAdi -Action $eylem -Trigger $tetik -Settings $ayar `
    -Description 'Takip edilen holding gruplarinin haberlerini Google Haberler uzerinden tarar.' | Out-Null

Write-Host "Gorev kuruldu: $GorevAdi - her $Saatte saatte bir"
Write-Host "Not: Bilgisayar kapaliysa calismaz; acildiginda kacirilan tarama otomatik yapilir."
