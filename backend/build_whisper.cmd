@echo off
setlocal enabledelayedexpansion

echo === Starting Whisper.cpp Build Process ===
echo.

echo Updating git submodules...
git submodule update --init --recursive
if %ERRORLEVEL% neq 0 (
    echo Failed to update git submodules
    goto :eof
)

echo Checking for whisper.cpp directory...
if not exist "whisper.cpp" (
    echo Directory 'whisper.cpp' not found. Please make sure you're in the correct directory and the submodule is initialized
    goto :eof
)

echo Changing to whisper.cpp directory...
cd whisper.cpp

echo Checking for whisper.cpp repository...
if not exist ".git" (
    echo Repository not found. Please make sure the whisper.cpp repository is properly cloned
    cd ..
    goto :eof
)

echo "List all files in the whisper.cpp examples directory"
dir /b examples\server

echo "Copying the all the server files from ../whisper-custom/server to examples/server"
xcopy /E /Y /I ..\whisper-custom\server examples\server

echo Checking for server directory...
if not exist "examples\server" (
    echo Server directory not found. Please make sure the whisper.cpp repository is properly cloned
    cd ..
    goto :eof
)

echo Checking for server source files...
if not exist "examples\server\server.cpp" (
    echo Server source files not found. Please make sure the whisper.cpp repository is properly cloned
    cd ..
    goto :eof
)

echo Building whisper.cpp server...
mkdir build 2>nul
cd build

echo Running CMake...
cmake .. -DBUILD_SHARED_LIBS=OFF -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=ON
if %ERRORLEVEL% neq 0 (
    echo Failed to run CMake
    cd ..\..
    goto :eof
)

echo Building with CMake...
cmake --build . --config Release
if %ERRORLEVEL% neq 0 (
    echo Failed to build with CMake
    cd ..\..
    goto :eof
)

echo Checking for server executable...
if not exist "bin\Release\whisper-server.exe" (
    if not exist "bin\whisper-server.exe" (
        echo Server executable not found. Build may have failed
        cd ..\..
        goto :eof
    )
)

echo Creating package directory...
cd ..\..

set "PACKAGE_NAME=whisper-server-package"
set "MODEL_DIR=models"

echo Checking for models directory...
if not exist "whisper.cpp\%MODEL_DIR%" (
    echo Creating models directory...
    mkdir "whisper.cpp\%MODEL_DIR%"
)

echo === Model Selection ===
echo.

set models=tiny.en tiny base.en base small.en small medium.en medium large-v1 large-v2 large-v3 large-v3-turbo tiny-q5_1 tiny.en-q5_1 tiny-q8_0 base-q5_1 base.en-q5_1 base-q8_0 small.en-tdrz small-q5_1 small.en-q5_1 small-q8_0 medium-q5_0 medium.en-q5_0 medium-q8_0 large-v2-q5_0 large-v2-q8_0 large-v3-q5_0 large-v3-turbo-q5_0 large-v3-turbo-q8_0

if "%~1"=="" (
    echo Available models:
    for %%m in (%models%) do (
        echo  %%m
    )
    echo.
    set /p MODEL_SHORT_NAME="Enter a model name (e.g. small): "
) else (
    set "MODEL_SHORT_NAME=%~1"
)

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
if exist "whisper.cpp\%MODEL_DIR%\%MODEL_NAME%" (
    echo Model file exists: whisper.cpp\%MODEL_DIR%\%MODEL_NAME%
) else (
    echo Model file does not exist: whisper.cpp\%MODEL_DIR%\%MODEL_NAME%
    echo Trying to download model...
    
    REM Run the download script
    call download-ggml-model.cmd %MODEL_SHORT_NAME%
    if %ERRORLEVEL% neq 0 (
        echo Failed to download model
        goto :eof
    )
)

echo Creating run script...
if not exist "%PACKAGE_NAME%" (
    mkdir "%PACKAGE_NAME%"
    if %ERRORLEVEL% neq 0 (
        echo Failed to create package directory
        goto :eof
    )
)

if not exist "%PACKAGE_NAME%\models" (
    mkdir "%PACKAGE_NAME%\models"
)

(
    echo @echo off
    echo REM Default configuration
    echo set "HOST=127.0.0.1"
    echo set "PORT=8178"
    echo set "MODEL=models\%MODEL_NAME%"
    echo.
    echo REM Parse command line arguments
    echo :parse_args
    echo if "%%~1"=="" goto run
    echo if "%%~1"=="--host" (
    echo     set "HOST=%%~2"
    echo     shift /2
    echo     goto parse_args
    echo )
    echo if "%%~1"=="--port" (
    echo     set "PORT=%%~2"
    echo     shift /2
    echo     goto parse_args
    echo )
    echo if "%%~1"=="--model" (
    echo     set "MODEL=%%~2"
    echo     shift /2
    echo     goto parse_args
    echo )
    echo if "%%~1"=="--language" (
    echo     set "LANGUAGE=%%~2"
    echo     shift /2
    echo     goto parse_args
    echo )
    echo echo Unknown option: %%~1
    echo exit /b 1
    echo.
    echo :run
    echo REM Run the server
    echo whisper-server.exe ^
    echo     --model "%%MODEL%%" ^
    echo     --host "%%HOST%%" ^
    echo     --port "%%PORT%%" ^
    echo     --diarize ^
    echo     --language "%%LANGUAGE%%" ^
    echo     --print-progress
) > "%PACKAGE_NAME%\run-server.cmd"

echo Run script created successfully

REM Copy files to package directory
echo Copying files to package directory...

echo Waiting for 5 seconds...
timeout /t 5 /nobreak >nul

if not exist "%PACKAGE_NAME%" (
    mkdir "%PACKAGE_NAME%"
)

echo Waiting for 5 seconds...
timeout /t 2 /nobreak >nul

if not exist "%PACKAGE_NAME%\models" (
    mkdir "%PACKAGE_NAME%\models"
)

echo Waiting for 5 seconds...
timeout /t 5 /nobreak >nul

if exist "whisper.cpp\build\bin\Release\whisper-server.exe" (
    copy "whisper.cpp\build\bin\Release\whisper-server.exe" "%PACKAGE_NAME%\"
) else if exist "whisper.cpp\build\bin\whisper-server.exe" (
    copy "whisper.cpp\build\bin\whisper-server.exe" "%PACKAGE_NAME%\"
)

echo Waiting for 5 seconds...
timeout /t 5 /nobreak >nul

if %ERRORLEVEL% neq 0 (
    echo Failed to copy whisper-server.exe
    goto :eof
)

echo Waiting for 5 seconds...
timeout /t 5 /nobreak >nul

copy "whisper.cpp\%MODEL_DIR%\%MODEL_NAME%" "%PACKAGE_NAME%\models\"
if %ERRORLEVEL% neq 0 (
    echo Failed to copy model
    goto :eof
)

echo Waiting for 5 seconds...
timeout /t 5 /nobreak >nul

if exist "whisper.cpp\examples\server\public" (
    xcopy /E /Y /I "whisper.cpp\examples\server\public" "%PACKAGE_NAME%\public\"
)

echo Waiting for 5 seconds...
timeout /t 5 /nobreak >nul

echo === Environment Setup ===
echo.

echo Setting up environment variables...
if exist "temp.env" (
    if not exist ".env" (
        copy temp.env .env
        echo Environment variables copied
    else (
        echo .env already exists. Skipping copy...
    )
)

echo If you want to use Models hosted on Anthropic, OpenAi or GROQ, add the API keys to the .env file.

echo === Installing Python Dependencies ===
echo.

echo Waiting for 5 seconds...
timeout /t 5 /nobreak >nul

REM Create virtual environment only if it doesn't exist
if not exist "venv" (
    echo Creating virtual environment...
    python -m venv venv
    if %ERRORLEVEL% neq 0 (
        echo Failed to create virtual environment
        goto :eof
    )
    
    call venv\Scripts\activate.bat
    if %ERRORLEVEL% neq 0 (
        echo Failed to activate virtual environment
        goto :eof
    )
    
    pip install -r requirements.txt
    if %ERRORLEVEL% neq 0 (
        echo Failed to install dependencies
        goto :eof
    )
) else (
    echo Virtual environment already exists
    call venv\Scripts\activate.bat
    if %ERRORLEVEL% neq 0 (
        echo Failed to activate virtual environment
        goto :eof
    )
    
    pip install -r requirements.txt
    if %ERRORLEVEL% neq 0 (
        echo Failed to install dependencies
        goto :eof
    )
)

echo Dependencies installed successfully

echo === Build Process Complete ===
echo You can now proceed with running the server by running 'start_with_output.ps1'

goto :eof
