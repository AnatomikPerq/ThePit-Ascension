@echo off
REM Start the dedicated server from a source checkout, on Windows.
REM
REM   serverun-server.bat [--set key=value ...]
REM
REM Use the CONSOLE build of Godot. The ordinary Windows executable is a
REM GUI-subsystem app: started from a terminal it attaches to no console and
REM prints nothing at all, which for a server means no log and no way to type a
REM command. See godot-pixel-stack-setup.md.
setlocal
cd /d "%~dp0.."
if "%GODOT%"=="" set GODOT=godot_console.exe
"%GODOT%" --headless --path . -- --server %*
