@echo off
setlocal enabledelayedexpansion

set "PACKAGE_NAME=whisper-server-package"
set "MODEL_NAME=ggml-small.bin"

if "%~1" neq "" (
    set "MODEL_NAME=ggml-%~1.bin"
)

echo Starting Whisper server with model: %MODEL_NAME%

if not exist "%PACKAGE_NAME%" (
    echo Error: %PACKAGE_NAME% directory not found
    echo Please run build_whisper.cmd first
    goto :eof
)

if not exist "%PACKAGE_NAME%\whisper-server.exe" (
    echo Error: whisper-server.exe not found in %PACKAGE_NAME% directory
    echo Please run build_whisper.cmd first
    goto :eof
)

if not exist "%PACKAGE_NAME%\models\%MODEL_NAME%" (
    echo Error: Model %MODEL_NAME% not found in %PACKAGE_NAME%\models directory
    echo Available models:
    dir /b "%PACKAGE_NAME%\models" 2>nul
    echo.
    echo Please run build_whisper.cmd with the correct model name
    goto :eof
)

cd "%PACKAGE_NAME%" || (
    echo Error: Failed to change to %PACKAGE_NAME% directory
    goto :eof
)

echo Running: whisper-server.exe --model models\%MODEL_NAME% --host 127.0.0.1 --port 8178 --diarize --print-progress
echo.
echo Output will be displayed in this window
echo Press Ctrl+C to stop the server
echo.

REM Run the server in the current window to see output
whisper-server.exe --model models\%MODEL_NAME% --host 127.0.0.1 --port 8178 --diarize --print-progress

cd ..
goto :eof
