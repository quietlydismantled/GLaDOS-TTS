@echo off
::
:: GLaDOS-TTS installer for Windows
::
:: Installs Miniconda (if needed), creates the "glados" conda environment, and
:: downloads the required ONNX model files.
::
:: Usage:
::   install_windows.bat          (interactive)
::   install_windows.bat /y       (assume "yes" to all prompts, CPU only)
::

setlocal enabledelayedexpansion

:: Always work from the repository directory, even when double-clicked
cd /d "%~dp0"

set "ENV_NAME=glados"
set "ENV_FILE=environment.yml"
set "ENV_FILE_CUDA=environment_cuda.yml"
set "ASSUME_YES=0"
set "INSTALL_CHOICE="
set "CONDA="
set "MINICONDA_PREFIX=%USERPROFILE%\Miniconda3"
set "MINICONDA_URL=https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe"

:: Miniconda's base configuration uses Anaconda's "defaults" channels, which recent
:: conda versions refuse to use until Anaconda's Terms of Service are accepted.
:: This project only needs conda-forge, so redefine what the "defaults" alias points
:: at. Anaconda's repositories are then never contacted and no Terms of Service
:: acceptance is required.
set "CONDA_DEFAULT_CHANNELS=conda-forge"

:: ---------------------------------------------------------------------------
:: Parse arguments
:: ---------------------------------------------------------------------------

:PARSE_ARGS
if "%~1"=="" goto ARGS_DONE
if /i "%~1"=="/y" goto ARG_YES
if /i "%~1"=="/yes" goto ARG_YES
if /i "%~1"=="/?" goto USAGE
if /i "%~1"=="/h" goto USAGE
echo Unknown option: %~1
endlocal
exit /b 1

:ARG_YES
set "ASSUME_YES=1"
shift
goto PARSE_ARGS

:USAGE
echo Usage: %~nx0 [/y^|/yes]
echo.
echo   /y, /yes   Assume "yes" to all prompts (installs the CPU-only environment)
endlocal
exit /b 0

:ARGS_DONE

echo.
echo GLaDOS-TTS Windows installer
echo ===========================
echo.

:: ---------------------------------------------------------------------------
:: Sanity checks
:: ---------------------------------------------------------------------------

where curl >nul 2>nul
if errorlevel 1 (
    echo !!! curl is required but was not found.
    echo     curl ships with Windows 10 version 1803 and newer.
    goto FAIL
)

if not exist "%ENV_FILE%" (
    echo !!! Could not find %ENV_FILE%.
    echo     Run this script from inside the repository.
    goto FAIL
)

if /i not "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
    if /i not "%PROCESSOR_ARCHITEW6432%"=="AMD64" (
        echo Note: no native Miniconda build exists for %PROCESSOR_ARCHITECTURE%.
        echo       The 64-bit x86 build will be used, which runs under emulation.
        echo.
    )
)

:: ---------------------------------------------------------------------------
:: 1. Choose CPU or CUDA
:: ---------------------------------------------------------------------------

if "%ASSUME_YES%"=="1" (
    set "INSTALL_CHOICE=1"
    echo ==^> Installing the CPU-only environment.
    goto CHOICE_DONE
)

echo ==^> Checking for an NVIDIA GPU...
where nvidia-smi >nul 2>nul
if errorlevel 1 (
    echo     No NVIDIA tools found. CUDA acceleration is probably not available.
) else (
    echo     Found NVIDIA tools. CUDA acceleration is probably available.
)
echo.

:INSTALL_PROMPT
echo You may choose from several installation methods:
echo.
echo   1. CPU only [Universal]
echo   2. CUDA accelerated [NVIDIA only]
echo.
set "INSTALL_CHOICE="
set /p "INSTALL_CHOICE=Please enter your desired install option: "
if "!INSTALL_CHOICE!"=="1" goto CHOICE_DONE
if "!INSTALL_CHOICE!"=="2" goto CHOICE_DONE
echo Invalid option.
echo.
goto INSTALL_PROMPT

:CHOICE_DONE
if "!INSTALL_CHOICE!"=="2" (
    set "ENV_FILE=%ENV_FILE_CUDA%"
    if not exist "!ENV_FILE!" (
        echo !!! Could not find !ENV_FILE!.
        goto FAIL
    )
)
echo.

:: ---------------------------------------------------------------------------
:: 2. Locate (or install) conda
:: ---------------------------------------------------------------------------

echo ==^> Looking for conda...
for /f "delims=" %%i in ('where conda 2^>nul') do (
    if not defined CONDA set "CONDA=%%i"
)
if defined CONDA goto CONDA_FOUND

call :CHECK_CONDA "%USERPROFILE%\Miniconda3\Scripts\conda.exe"
call :CHECK_CONDA "%USERPROFILE%\miniforge3\Scripts\conda.exe"
call :CHECK_CONDA "%USERPROFILE%\Anaconda3\Scripts\conda.exe"
call :CHECK_CONDA "%LOCALAPPDATA%\miniconda3\Scripts\conda.exe"
call :CHECK_CONDA "%PROGRAMDATA%\Miniconda3\Scripts\conda.exe"
call :CHECK_CONDA "%PROGRAMDATA%\Anaconda3\Scripts\conda.exe"
if defined CONDA goto CONDA_FOUND

echo !!! conda was not found on this system.
echo     Miniconda will be installed to %MINICONDA_PREFIX% (just for you, no
echo     administrator password required).
echo.
if "%ASSUME_YES%"=="1" goto INSTALL_CONDA
set "REPLY="
set /p "REPLY=Install Miniconda now? [y/N] "
if /i "!REPLY!"=="y" goto INSTALL_CONDA
if /i "!REPLY!"=="yes" goto INSTALL_CONDA
echo !!! conda is required.
echo     Install Miniconda from https://www.anaconda.com/download/success
echo     and re-run this script.
goto FAIL

:INSTALL_CONDA
set "MINICONDA_EXE=%TEMP%\miniconda_installer.exe"

echo ==^> Downloading Miniconda...
curl -fL "%MINICONDA_URL%" --output "%MINICONDA_EXE%"
if errorlevel 1 (
    echo !!! Failed to download the Miniconda installer.
    goto FAIL
)

echo ==^> Installing Miniconda to %MINICONDA_PREFIX% ...
:: /D must come last and must not be quoted
start /wait "" "%MINICONDA_EXE%" /InstallationType=JustMe /RegisterPython=0 /AddToPath=0 /S /D=%MINICONDA_PREFIX%
if errorlevel 1 (
    echo !!! Miniconda installation failed.
    goto FAIL
)
del "%MINICONDA_EXE%" >nul 2>nul

set "CONDA=%MINICONDA_PREFIX%\Scripts\conda.exe"
if not exist "!CONDA!" (
    echo !!! Miniconda reported success but !CONDA! does not exist.
    goto FAIL
)

echo ==^> Initializing conda for your shell...
call "!CONDA!" init cmd.exe >nul 2>nul
goto CONDA_READY

:CONDA_FOUND
echo     Found conda: !CONDA!

:CONDA_READY
echo.

:: ---------------------------------------------------------------------------
:: 3. Create or update the conda environment
:: ---------------------------------------------------------------------------

"!CONDA!" env list | findstr /r /c:"^!ENV_NAME! " >nul 2>nul
if errorlevel 1 goto CREATE_ENV

echo ==^> Conda environment '!ENV_NAME!' already exists.
if "%ASSUME_YES%"=="1" goto UPDATE_ENV
set "REPLY="
set /p "REPLY=Update it from !ENV_FILE!? [y/N] "
if /i "!REPLY!"=="y" goto UPDATE_ENV
if /i "!REPLY!"=="yes" goto UPDATE_ENV
echo     Leaving the existing environment untouched.
goto MODELS

:UPDATE_ENV
echo ==^> Updating conda environment '!ENV_NAME!' from !ENV_FILE! ...
call "!CONDA!" env update --name "!ENV_NAME!" --file "!ENV_FILE!" --prune
if errorlevel 1 (
    echo !!! Failed to update the '!ENV_NAME!' environment.
    call :TOS_HINT
    goto FAIL
)
goto MODELS

:CREATE_ENV
echo ==^> Creating conda environment '!ENV_NAME!' from !ENV_FILE! ...
call "!CONDA!" env create --file "!ENV_FILE!"
if errorlevel 1 (
    echo !!! Failed to create the '!ENV_NAME!' environment.
    call :TOS_HINT
    goto FAIL
)

:: ---------------------------------------------------------------------------
:: 4. Download the model files
:: ---------------------------------------------------------------------------

:MODELS
echo.
echo ==^> Verifying and downloading required models...
call :GET_MODEL "https://github.com/dnhkng/GlaDOS/releases/download/0.1/glados.onnx" "glados\models\glados.onnx"
if errorlevel 1 goto FAIL
call :GET_MODEL "https://github.com/dnhkng/GlaDOS/releases/download/0.1/phomenizer_en.onnx" "glados\models\phomenizer_en.onnx"
if errorlevel 1 goto FAIL

:: ---------------------------------------------------------------------------
:: 5. Verify the installation
:: ---------------------------------------------------------------------------

echo.
echo ==^> Verifying the installation...
call "!CONDA!" run --no-capture-output -n "!ENV_NAME!" python -c "import onnxruntime, sounddevice, num2words, tkinter"
if errorlevel 1 (
    echo !!! The environment is missing one or more dependencies.
    goto FAIL
)

echo.
echo Installation finished!
echo.
echo Run the interactive console demo with:
echo     run_console_windows.bat
echo.
echo Or activate the environment first:
echo     conda activate !ENV_NAME!
echo     python speak_console.py
echo.
endlocal
pause
exit /b 0

:: ---------------------------------------------------------------------------
:: Subroutines
:: ---------------------------------------------------------------------------

:CHECK_CONDA
if defined CONDA goto :eof
if exist "%~1" set "CONDA=%~1"
goto :eof

:GET_MODEL
:: %1 = URL, %2 = destination path
:: A zero-byte file counts as missing, so an interrupted download is retried
for %%F in ("%~2") do set "MODEL_SIZE=%%~zF"
if not exist "%~2" set "MODEL_SIZE=0"
if not "!MODEL_SIZE!"=="0" (
    echo     %~2 already exists.
    exit /b 0
)
echo     Downloading %~2 ...
curl -fL "%~1" --create-dirs --output "%~2"
if errorlevel 1 (
    del "%~2" >nul 2>nul
    echo !!! Failed to download %~2
    echo     URL: %~1
    exit /b 1
)
exit /b 0

:TOS_HINT
echo.
echo !!! If the failure above mentions Anaconda's Terms of Service, this script did
echo !!! not manage to avoid the 'defaults' channels. You can accept those terms
echo !!! yourself -- read them first, they are Anaconda's licensing terms -- with:
echo !!!     "!CONDA!" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main
echo !!!     "!CONDA!" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r
echo !!! or remove the 'defaults' channel from your conda configuration entirely.
goto :eof

:FAIL
echo.
echo Installation failed.
endlocal
pause
exit /b 1
