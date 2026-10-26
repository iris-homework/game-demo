@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
title 午夜委托 Demo

pushd "%~dp0"
if errorlevel 1 goto directory_error
if not exist "project.godot" goto project_error

rem GODOT_PATH takes priority; otherwise search beside this script, then PATH.
set "engine="
if defined GODOT_PATH (
    set "engine=%GODOT_PATH%"
    goto check_engine
)
for %%G in ("godot.exe" "godot4.exe" "Godot_v4*_win64.exe" "Godot_v4*_win32.exe" "Godot_v4*_windows.arm64.exe") do (
    if exist "%%~fG" (
        set "engine=%%~fG"
        goto check_engine
    )
)
for %%G in (godot.exe godot4.exe) do (
    for /f "delims=" %%P in ('where %%G 2^>nul') do (
        set "engine=%%P"
        goto check_engine
    )
)
echo 未找到 Godot。请将 Godot 4.7 标准版的 exe 放在本脚本旁边，
echo 或将 GODOT_PATH 环境变量设为 Godot exe 的完整路径（值不加引号）。
goto failed

:check_engine
if not exist "%engine%" (
    echo GODOT_PATH 指向的文件不存在，请检查环境变量。
    goto failed
)
echo 正在导入资源，首次启动可能需要较长时间，请稍候……
"%engine%" --headless --path . --editor --import --quit
set "launch_result=%errorlevel%"
if not "%launch_result%"=="0" (
    echo 资源导入失败，请查看上方错误信息。
    goto failed
)

echo 正在启动午夜委托……
"%engine%" --path .
set "launch_result=%errorlevel%"
if not "%launch_result%"=="0" (
    echo 游戏异常退出，请查看上方错误信息。
    goto failed
)
popd
exit /b 0

:project_error
echo 未找到 project.godot，请将本脚本保留在 game-demo 工程根目录。
:failed
popd
pause
exit /b 1

:directory_error
echo 无法进入游戏目录，请检查文件夹路径与访问权限。
pause
exit /b 1
