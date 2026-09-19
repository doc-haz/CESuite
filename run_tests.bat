@echo off
cd /d C:\Azuara\CESuite

echo.
echo === Running CESuite Lua tests ===
echo.

python tools\run_lua_tests.py --library "C:/Program Files/Cheat Engine/lua53-64.dll"

echo.
echo === Tests finished ===
echo.

pause