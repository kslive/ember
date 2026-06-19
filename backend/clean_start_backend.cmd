@echo off
setlocal enabledelayedexpansion

REM Configuration
set "PACKAGE_NAME=whisper-server-package"
set "MODEL_DIR=%PACKAGE_NAME%\models"
set "PORT=5167"

echo === Environment Check ===
echo.

if not exist "%PACKAGE_NAME%" (
    echo Whisper server directory not found. Please run build_whisper.cmd first
    goto :eof
)

if not exist "app" (
    echo Python backend directory not found. Please check your installation
    goto :eof
)

if not exist "app\main.py" (
    echo Python backend main.py not found. Please check your installation
    goto :eof
)

if not exist "venv" (
    echo Virtual environment not found. Please run build_whisper.cmd first
    goto :eof
)

echo === Initial Cleanup ===
echo.

echo Checking for existing whisper servers...
taskkill /F /FI "IMAGENAME eq whisper-server.exe" 2>nul
if %ERRORLEVEL% equ 0 (
    echo Existing whisper servers terminated
) else (
    echo No existing whisper servers found
)
timeout /t 1 >nul

echo === Backend App Check ===
echo.

echo Checking for processes on port 5167...
set "PORT_IN_USE="
for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":5167.*LISTENING"') do (
    set "PORT_IN_USE=%%a"
)

if defined PORT_IN_USE (
    echo Backend app is running on port %PORT%
    set /p REPLY="Kill it? (y/N) "
    if /i not "!REPLY!"=="y" (
        echo User chose not to terminate existing backend app
        goto :eof
    )
    
    echo Terminating backend app...
    taskkill /F /PID !PORT_IN_USE! 2>nul
    if !ERRORLEVEL! equ 0 (
        echo Backend app terminated
    ) else (
        echo Failed to terminate backend app
        goto :eof
    )
    timeout /t 1 >nul
)

echo === Model Check ===
echo.

if not exist "%MODEL_DIR%" (
    echo Models directory not found. Please run build_whisper.cmd first
    goto :eof
)

echo Checking for Whisper models...
set "EXISTING_MODELS="
for /f "delims=" %%a in ('dir /b /s "%MODEL_DIR%\ggml-*.bin" 2^>nul') do (
    set "EXISTING_MODELS=!EXISTING_MODELS!%%a
"
)

if defined EXISTING_MODELS (
    echo Found existing models:
    echo %EXISTING_MODELS%
) else (
    echo No existing models found
)

REM Whisper models
set "models=tiny.en tiny base.en base small.en small medium.en medium large-v1 large-v2 large-v3 large-v3-turbo tiny-q5_1 tiny.en-q5_1 tiny-q8_0 base-q5_1 base.en-q5_1 base-q8_0 small.en-tdrz small-q5_1 small.en-q5_1 small-q8_0 medium-q5_0 medium.en-q5_0 medium-q8_0 large-v2-q5_0 large-v2-q8_0 large-v3-q5_0 large-v3-turbo-q5_0 large-v3-turbo-q8_0"

REM Ask user which model to use if the argument is not provided
set "MODEL_SHORT_NAME="
if "%~1"=="" (
    echo === Model Selection ===
    echo.
    echo Available models:
    for %%m in (%models%) do (
        echo %%m
    )
    echo.
    set /p MODEL_SHORT_NAME="Enter a model name (e.g. small): "
) else (
    set "MODEL_SHORT_NAME=%~1"
)

REM Check if the model is valid
set "MODEL_VALID=0"
for %%m in (%models%) do (
    if "%%m"=="%MODEL_SHORT_NAME%" set "MODEL_VALID=1"
)

if "%MODEL_VALID%"=="0" (
    echo Invalid model: %MODEL_SHORT_NAME%
    goto :eof
)

set "MODEL_NAME=ggml-%MODEL_SHORT_NAME%.bin"
echo Selected model: %MODEL_NAME%

REM Check if the modelname exists in directory
if exist "%MODEL_DIR%\%MODEL_NAME%" (
    echo Model file exists: %MODEL_DIR%\%MODEL_NAME%
) else (
    echo Model file does not exist: %MODEL_DIR%\%MODEL_NAME%
    echo Downloading model...
    
    call download-ggml-model.cmd %MODEL_SHORT_NAME%
    if %ERRORLEVEL% neq 0 (
        echo Failed to download model
        goto :eof
    )
    
    REM Move model to models directory
    move "whisper.cpp\models\%MODEL_NAME%" "%MODEL_DIR%\"
    if %ERRORLEVEL% neq 0 (
        echo Failed to move model to models directory
        goto :eof
    )
)

echo === Starting Services ===
echo.

REM Start the whisper server in background
echo Starting Whisper server...
cd "%PACKAGE_NAME%" || (
    echo Failed to change to whisper-server directory
    goto :eof
)

REM Start the server and capture its PID
echo Running whisper-server.exe with model %MODEL_NAME%...

REM Start the server without redirecting output
start "Whisper Server" cmd /k "whisper-server.exe --model models\%MODEL_NAME% --host 127.0.0.1 --port 8178 --diarize --print-progress"

REM Give the server a moment to start
echo Waiting for server to start...
timeout /t 5 >nul

REM Check if the process is running
for /f "tokens=2" %%a in ('tasklist /fi "imagename eq whisper-server.exe" /fo list ^| findstr "PID:"') do (
    set "WHISPER_PID=%%a"
)

if not defined WHISPER_PID (
    echo Whisper server failed to start. Check whisper-server.log for details.
    cd ..
    goto :eof
)

echo Whisper server started with PID: %WHISPER_PID%

REM Check if the server is listening on port 8178
netstat -ano | findstr ":8178.*LISTENING" >nul
if %ERRORLEVEL% neq 0 (
    echo Whisper server is not listening on port 8178. Waiting a bit longer...
    timeout /t 10 >nul
    
    netstat -ano | findstr ":8178.*LISTENING" >nul
    if %ERRORLEVEL% neq 0 (
        echo Whisper server still not listening. Check whisper-server.log for details.
        taskkill /F /PID %WHISPER_PID% 2>nul
        cd ..
        goto :eof
    )
)

echo Whisper server is running and listening on port 8178.
cd ..

REM Start the Python backend in background
echo Starting Python backend...

REM Activate virtual environment
echo Activating virtual environment...
call venv\Scripts\activate.bat
if %ERRORLEVEL% neq 0 (
    echo Failed to activate virtual environment
    goto :eof
)

REM Check if required Python packages are installed
pip show fastapi >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo FastAPI not found. Please run build_whisper.cmd to install dependencies
    goto :eof
)

REM Start the Python backend and capture its PID
echo Running Python backend on port %PORT%...

REM Start the Python backend without redirecting output
start "Python Backend" cmd /k "call venv\Scripts\activate.bat && python app\main.py"

REM Give the backend a moment to start
echo Waiting for Python backend to start...
timeout /t 5 >nul

REM Get the Python PID
for /f "tokens=2" %%a in ('tasklist /fi "imagename eq python.exe" /fo list ^| findstr "PID:"') do (
    set "PYTHON_PID=%%a"
)

if not defined PYTHON_PID (
    echo Python backend failed to start. Check python-backend.log for details.
    goto :eof
)

echo Python backend started with PID: %PYTHON_PID%

REM Wait for backend to start and check if it's listening
echo Waiting for Python backend to be ready...
timeout /t 5 >nul

REM Check if the port is actually listening
netstat -ano | findstr ":%PORT%.*LISTENING" >nul
if %ERRORLEVEL% neq 0 (
    echo Python backend is not listening on port %PORT%. Waiting a bit longer...
    timeout /t 10 >nul
    
    netstat -ano | findstr ":%PORT%.*LISTENING" >nul
    if %ERRORLEVEL% neq 0 (
        echo Python backend still not listening on port %PORT%. Check python-backend.log for details.
        taskkill /F /PID %PYTHON_PID% 2>nul
        goto :eof
    )
)

echo Python backend is running and listening on port %PORT%.

echo ===================================
echo All services started successfully!
echo ===================================
echo Whisper Server (PID: %WHISPER_PID%) - Port: 8178
echo Python Backend (PID: %PYTHON_PID%) - Port: %PORT%
echo.
echo Press Ctrl+C to stop all services

REM Keep the script running
echo.
echo Servers are running. Press Ctrl+C to stop...
pause >nul

REM Cleanup on exit
echo === Cleanup ===
echo.

if defined WHISPER_PID (
    echo Stopping Whisper server...
    taskkill /F /PID !WHISPER_PID! 2>nul
    if !ERRORLEVEL! equ 0 (
        echo Whisper server stopped
    ) else (
        echo Failed to kill Whisper server process
    )
    
    taskkill /F /FI "IMAGENAME eq whisper-server.exe" 2>nul
    if !ERRORLEVEL! equ 0 (
        echo All whisper-server processes stopped
    )
)

if defined PYTHON_PID (
    echo Stopping Python backend...
    taskkill /F /PID !PYTHON_PID! 2>nul
    if !ERRORLEVEL! equ 0 (
        echo Python backend stopped
    ) else (
        echo Failed to kill Python backend process
    )
)

goto :eof
