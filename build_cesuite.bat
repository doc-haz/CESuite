@echo off
cd /d C:\Azuara\CESuite

echo.
echo === Building CESuite ===
echo.

python tools\build_ce.py

echo.
echo === Build finished ===
echo.

pause