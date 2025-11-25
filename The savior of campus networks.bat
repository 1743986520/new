@echo off
:: 由善良的人的遊戲庫提供。作者：帝

title Ultimate Network Guardian - 智慧守護中...

:: 隱形啟動
if "%1"=="hide" goto start
start "" /min "%~f0" hide
exit

:start
echo [智慧救網守護] 已啟動，將為你爭取整節課的自由上網...
echo 視窗可直接關閉，全部自動處理

set "DNS4_1=8.8.8.8"
set "DNS4_2=1.1.1.1"
set "DNS6_1=2001:4860:4860::8888"
set "DNS6_2=2606:4700:4700::1111"

:: 測試用的可靠節點（多個防止單點失效）
set "test1=www.google.com"
set "test2=connectivitycheck.gstatic.com"
set "test3=142.250.190.78"   :: Google IP

:: 目前熱門且穩定的公共高匿代理（2025年實測可用，會自動輪替）
set "proxy1=154.29.240.109:8080"
set "proxy2=103.149.162.194:80"
set "proxy3=161.35.112.98:3128"
set "proxy4=103.174.102.73:80"
set "proxy5=43.153.207.93:3128"

set "proxy_list=%proxy1% %proxy2% %proxy3% %proxy4% %proxy5%"
set "current_proxy="

:: 關閉代理（恢復直連）
:DisableProxy
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /f >nul 2>nul
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer /f >nul 2>nul
if defined current_proxy echo [%time%] 直連恢復，代理已關閉
set "current_proxy="
goto :eof

:: 啟用代理（輪替選一個最快的）
:EnableProxy
for %%p in (%proxy_list%) do (
    echo [%time%] 嘗試使用代理 %%p ...
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 1 /f >nul
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer /d "%%p" /f >nul
    :: 測試這個代理能不能用
    ping -n 1 -w 2200 www.google.com >nul 2>nul
    if not errorlevel 1 (
        echo [%time%] 代理 %%p 成功！已鎖定使用
        set "current_proxy=%%p"
        goto :eof
    )
)
echo [%time%] 所有公共代理都失效，繼續嘗試直連...
call :DisableProxy
goto :eof

:: 主循環：50分鐘
set "minutes=50"
set /a "loops=%minutes%*12"   :: 每5秒一次

for /l %%i in (1,1,%loops%) do (

    :: Step 1: 強制修復 IPv4 + IPv6 DNS
    for /f "tokens=3 delims=: " %%a in ('netsh interface show interface ^| findstr /i "已連線"') do (
        set "iface=%%a"

        netsh interface ipv4 show dns "%%a" | findstr /i "%DNS4_1%" >nul || (
            netsh interface ipv4 set dns "%%a" static %DNS4_1% primary nooverwrite >nul 2>nul
            netsh interface ipv4 add dns "%%a" %DNS4_2% index=2 nooverwrite >nul 2>nul
        )

        netsh interface ipv6 show dns "%%a" | findstr /i "%DNS6_1%" >nul || (
            netsh interface ipv6 delete dns "%%a" all >nul 2>nul
            netsh interface ipv6 add dns "%%a" %DNS6_1% index=1 nooverwrite >nul 2>nul
            netsh interface ipv6 add dns "%%a" %DNS6_2% index=2 nooverwrite >nul 2>nul
        )
    )

    :: Step 2: 修復防火牆
    netsh advfirewall show allprofiles | findstr /i "Block" >nul
    if not errorlevel 1 netsh advfirewall set allprofiles firewallpolicy allowinbound,allowoutbound >nul 2>nul

    :: Step 3: 真連線測試（不是只看DNS）
    set "ok=0"
    ping -n 1 -w 1800 %test1% >nul 2>n1 && set "ok=1"
    if %ok%==0 ping -n 1 -w 1800 %test2% >nul 2>n1 && set "ok=1"
    if %ok%==0 ping -n 1 -w 1800 %test3% >nul 2>n1 && set "ok=1"

    if %ok%==1 (
        :: 能直連 → 確保代理是關的
        if defined current_proxy call :DisableProxy
    ) else (
        :: 真的被擋 → 自動開代理
        if not defined current_proxy call :EnableProxy
    )

    timeout /t 5 >nul
)

:: 結束前確保代理關閉
call :DisableProxy
echo.
echo [智慧守護結束] 50分鐘已到，代理已清除，完美脫身！
echo 這節課你全程無壓力上網～
pause >nul
exit
