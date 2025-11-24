@echo off
:: 由善良的人的遊戲庫提供支持

title NetworkGuardian - 正在守護你的網路...

:: 把自己藏起來（不讓老師看到黑窗）
if "%1"=="hide" goto :start
start "" /min "%~f0" hide
exit

:start
echo [NetworkGuardian] 守護進程已啟動，將常駐到課程結束...
echo [提示] 可以把視窗最小化或直接關掉，會在背景繼續跑

:: 設定你要強制使用的 DNS（可自行換）
set "DNS1=8.8.8.8"
set "DNS2=1.1.1.1"

:: 總共守護 50 分鐘（一節課夠用，可改成 3600 = 1小時）
set "minutes=50"
set /a "loops=%minutes%*20"

for /l %%i in (1,1,%loops%) do (
    :: 每 3 秒檢查一次

    :: 检查 1：如果主要 DNS 不是我們要的，就強制改回來
    netsh interface ip show config | findstr /i "DNS.*%DNS1%" >nul
    if errorlevel 1 (
        echo [%time%] 偵測到 DNS 被改！正在救回...
        for /f "tokens=2 delims=:" %%a in ('netsh interface show interface ^| findstr /i "已連線"') do (
            set "iface=%%a"
            set "iface=!iface: =!"
            netsh interface ip set dns name="!iface!" source=static address=%DNS1% register=none >nul 2>nul
            netsh interface ip add dns name="!iface!" address=%DNS2% index=2 >nul 2>nul
        )
    )

    :: 检查 2：如果防火牆把 outbound 擋了，就直接允許
    netsh advfirewall show allprofiles state | findstr /i "ON" | findstr /i "Block" >nul
    if not errorlevel 1 (
        echo [%time%] 防火牆被設成阻擋！正在解除...
        netsh advfirewall set allprofiles firewallpolicy allowinbound,allowoutbound >nul 2>nul
    )

    :: 检查 3：如果老師直接把防火牆規則清空或亂設，乾脆全部重置
    netsh advfirewall show currentprofile | findstr /i "BlockInbound" >nul
    if not errorlevel 1 (
        echo [%time%] 防火牆規則異常，重置中...
        netsh advfirewall reset >nul 2>nul
        netsh advfirewall set allprofiles firewallpolicy allowinbound,allowoutbound >nul 2>nul
    )

    timeout /t 3 >nul
)

echo.
echo [NetworkGuardian] 課程時間到，守護進程自動結束
echo 你已經自由上網一節課了 XD
pause
exit
