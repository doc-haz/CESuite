@echo off
cd /d "%~dp0"

echo.
echo === Running CESuite Lua tests ===
echo.

set "CE_LUA=C:\Program Files\Cheat Engine\lua53-64.dll"

if not exist "%CE_LUA%" (
    echo ERROR: Cheat Engine Lua library not found:
    echo %CE_LUA%
    echo.
    echo Set CE_LUA to your Cheat Engine lua53-64.dll path.
    pause
    exit /b 1
)

python tools\run_lua_tests.py --library "%CE_LUA%"

echo.
echo === Tests finished ===
echo.

pause
