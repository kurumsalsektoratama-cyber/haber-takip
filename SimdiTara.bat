@echo off
rem Once yeni haberleri bulur, sonra haber metinlerini indirir, sonra uygulamayi acar.
echo Yeni haberler taraniyor (birkac dakika)...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Tara.ps1"
echo.
echo Haber metinleri ve gorselleri indiriliyor...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Icerik.ps1" -Adet 200
echo.
echo Bitti, uygulama aciliyor.
start "" "%~dp0index.html"
timeout /t 5 >nul
