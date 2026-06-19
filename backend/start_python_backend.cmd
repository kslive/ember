@echo off
setlocal enabledelayedexpansion

set "PORT=5167"
if "%~1" neq "" (
    set "PORT=%~1"
)

echo Starting Python backend on port %PORT%...

if not exist "venv" (
    echo Error: Virtual environment not found
    echo Please run build_whisper.cmd first
    goto :eof
)

REM Activate virtual environment
echo Activating virtual environment...
call venv\Scripts\activate.bat
if %ERRORLEVEL% neq 0 (
    echo Error: Failed to activate virtual environment
    goto :eof
)

REM Check if required Python packages are installed
pip show fastapi >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo Error: FastAPI not found. Please run build_whisper.cmd to install dependencies
    goto :eof
)

REM Check if app directory exists
if not exist "app" (
    echo Error: app directory not found
    echo Please run build_whisper.cmd first
    goto :eof
)

REM Check if main.py exists
if not exist "app\main.py" (
    echo Error: app\main.py not found
    echo Please run build_whisper.cmd first
    goto :eof
)

echo Running: python app\main.py
echo.
echo Output will be displayed in this window
echo Press Ctrl+C to stop the Python backend
echo.

REM Set environment variable for port
set "PORT=%PORT%"

REM Run the Python backend in the current window to see output
python app\main.py

goto :eof
