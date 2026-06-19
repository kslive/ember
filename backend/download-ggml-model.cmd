@echo off

pushd %~dp0
set models_path=%CD%
for %%d in (%~dp0..) do set root_path=%%~fd
popd

set models=tiny.en tiny base.en base small.en small medium.en medium large-v1 large-v2 large-v3 large-v3-turbo tiny-q5_1 tiny.en-q5_1 tiny-q8_0 base-q5_1 base.en-q5_1 base-q8_0 small.en-tdrz small-q5_1 small.en-q5_1 small-q8_0 medium-q5_0 medium.en-q5_0 medium-q8_0 large-v2-q5_0 large-v2-q8_0 large-v3-q5_0 large-v3-turbo-q5_0 large-v3-turbo-q8_0

set argc=0
for %%x in (%*) do set /A argc+=1

if %argc% neq 1 (
  echo.
  echo Usage: download-ggml-model.cmd model
  CALL :list_models
  goto :eof
)

set model=%1

for %%b in (%models%) do (
  if "%%b"=="%model%" (
    CALL :download_model
    goto :eof
  )
)

echo Invalid model: %model%
CALL :list_models
goto :eof

:download_model
echo Downloading ggml model %model%...

cd "%models_path%"

if exist "whisper.cpp\models" (
    cd whisper.cpp\models
) else if exist "models" (
    cd models
) else (
    mkdir models
    cd models
)

if exist "ggml-%model%.bin" (
  echo Model %model% already exists in current directory. Skipping download.
  goto :eof
)

REM Also check if model exists in target directory
set target_model=%models_path%\whisper-server-package\models\ggml-%model%.bin
if exist "%target_model%" (
  echo Model %model% already exists in whisper-server-package\models. Skipping download.
  goto :eof
)

REM Check if model contains `tdrz` and update the src accordingly
echo %model% | findstr /C:"tdrz" >nul
if %ERRORLEVEL% equ 0 (
    set "src=https://huggingface.co/akashmjn/tinydiarize-whisper.cpp/resolve/main"
) else (
    set "src=https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
)

PowerShell -NoProfile -ExecutionPolicy Bypass -Command "Start-BitsTransfer -Source %src%/ggml-%model%.bin -Destination ggml-%model%.bin"

if %ERRORLEVEL% neq 0 (
  echo Failed to download ggml model %model%
  echo Please try again later or download the original Whisper model files and convert them yourself.
  goto :eof
)

set current_dir=%CD%
set source_file=%current_dir%\ggml-%model%.bin
echo Done! Model %model% saved in %source_file%

REM Set target directory for whisper-server-package
set target_dir=%models_path%\whisper-server-package\models

REM Debug output
echo.
echo Checking if model needs to be moved...
echo Current directory: %current_dir%
echo Target directory: %target_dir%
echo.

REM Check if we're already in the target directory
if "%current_dir%"=="%target_dir%" (
    echo Model is already in the correct location.
) else (
    REM Check if target directory exists
    if exist "%target_dir%" (
        echo Target directory exists. Copying model...
        
        REM Ensure target directory exists
        if not exist "%target_dir%" mkdir "%target_dir%"
        
        REM Copy the model to the target directory
        copy /Y "%source_file%" "%target_dir%\ggml-%model%.bin"
        
        if %ERRORLEVEL% equ 0 (
            REM Verify the copy was successful by checking file size
            if exist "%target_dir%\ggml-%model%.bin" (
                echo Model successfully copied to whisper-server-package\models
                
                REM Delete the source file to save space
                echo Removing model from temporary location: %source_file%
                del /F /Q "%source_file%"
                
                if exist "%source_file%" (
                    echo Warning: Could not remove temporary model file.
                    echo The file may be in use or you may not have permission.
                ) else (
                    echo Cleanup completed successfully.
                    echo Model removed from: %current_dir%
                )
            ) else (
                echo Warning: Copy verification failed. Keeping source file.
            )
        ) else (
            echo Warning: Failed to copy model to whisper-server-package\models
            echo Model remains in: %source_file%
        )
    ) else (
        echo Target directory does not exist: %target_dir%
        
        REM Try to create it
        echo Attempting to create target directory...
        mkdir "%target_dir%" 2>nul
        
        if exist "%target_dir%" (
            echo Directory created. Copying model...
            copy /Y "%source_file%" "%target_dir%\ggml-%model%.bin"
            
            if %ERRORLEVEL% equ 0 (
                if exist "%target_dir%\ggml-%model%.bin" (
                    echo Model successfully copied.
                    del /F /Q "%source_file%"
                    if not exist "%source_file%" (
                        echo Cleanup completed successfully.
                    )
                )
            )
        ) else (
            echo Could not create target directory.
            echo Model saved in: %source_file%
        )
    )
)

echo.
echo You can now use the model with the Whisper server.

goto :eof

:list_models
  echo.
  echo Available models:
  (for %%a in (%models%) do (
    echo %%a
  ))
  echo.
  goto :eof
