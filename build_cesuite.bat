@echo off
cd /d "%~dp0"

echo.
echo === Building CESuite ===
echo.

python tools\build_ce.py

echo.
echo === Build finished ===
echo.

pause
