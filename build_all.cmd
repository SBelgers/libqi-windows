@echo off
setlocal enabledelayedexpansion

:: ======================================================================
:: Build libqi and libqi-python from source on Windows with MSVC.
::
:: Usage:
::   build_all.cmd -pythonversion 3.14
::   build_all.cmd -pythonversion 3.14 -buildwheel
::   build_all.cmd -pythonversion 3.13 -skiplibqi -buildwheel
::   build_all.cmd                        (uses active venv)
::
:: Run from a "Developer Command Prompt for VS 2022" (or any shell
:: where cl.exe is on the PATH).
:: ======================================================================

set "PYTHON_VERSION="
set "PYTHON_VENV="
set "SKIP_LIBQI=0"
set "BUILD_WHEEL=0"

:: ── Parse arguments ──────────────────────────────────────────────────────
:parse_args
if "%~1"=="" goto :done_args
if /i "%~1"=="-pythonversion" (
    set "PYTHON_VERSION=%~2"
    shift & shift
    goto :parse_args
)
if /i "%~1"=="-pythonvenv" (
    set "PYTHON_VENV=%~2"
    shift & shift
    goto :parse_args
)
if /i "%~1"=="-skiplibqi" (
    set "SKIP_LIBQI=1"
    shift
    goto :parse_args
)
if /i "%~1"=="-buildwheel" (
    set "BUILD_WHEEL=1"
    shift
    goto :parse_args
)
echo ERROR: Unknown argument: %~1
exit /b 1
:done_args

:: ── Pre-flight checks ───────────────────────────────────────────────────
where cl >nul 2>&1    || (echo ERROR: cl.exe not found. Run this from a VS Developer Command Prompt. & exit /b 1)
where cmake >nul 2>&1 || (echo ERROR: cmake not found. Install CMake. & exit /b 1)
where conan >nul 2>&1 || (echo ERROR: conan not found. Install Conan 2: pip install conan & exit /b 1)
where git >nul 2>&1   || (echo ERROR: git not found. & exit /b 1)
where ninja >nul 2>&1 || (echo ERROR: ninja not found. Install Ninja: pip install ninja & exit /b 1)

set "REPO_ROOT=%~dp0"
:: Remove trailing backslash
if "%REPO_ROOT:~-1%"=="\" set "REPO_ROOT=%REPO_ROOT:~0,-1%"

:: libqi/ and libqi-python/ will be cloned inside the repo
set "WORK_DIR=%REPO_ROOT%"

:: ── Resolve Python version and venv ─────────────────────────────────────
if defined PYTHON_VERSION (
    where py >nul 2>&1 || (echo ERROR: py launcher not found. Install Python from python.org. & exit /b 1)
    py -%PYTHON_VERSION% -c "import sys; print(sys.executable)" >nul 2>&1
    if errorlevel 1 (
        echo ERROR: Python %PYTHON_VERSION% not found. Install it from python.org.
        exit /b 1
    )
    for /f "delims=" %%P in ('py -%PYTHON_VERSION% -c "import sys; print(sys.executable)"') do (
        echo Found Python %PYTHON_VERSION% at: %%P
    )

    if not defined PYTHON_VENV (
        set "TAG=%PYTHON_VERSION:.=%"
        set "PYTHON_VENV=%REPO_ROOT%\venvs\!TAG!"
    )

    if not exist "!PYTHON_VENV!\Scripts\python.exe" (
        echo Creating venv: !PYTHON_VENV!
        py -%PYTHON_VERSION% -m venv "!PYTHON_VENV!"
        "!PYTHON_VENV!\Scripts\pip.exe" install conan ninja
    )
) else (
    if not defined PYTHON_VENV (
        if defined VIRTUAL_ENV (
            set "PYTHON_VENV=%VIRTUAL_ENV%"
        ) else (
            echo ERROR: No Python version or virtualenv specified.
            echo Usage: build_all.cmd -pythonversion 3.13
            exit /b 1
        )
    )
)

for /f "delims=" %%V in ('"!PYTHON_VENV!\Scripts\python.exe" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"') do set "PY_VER=%%V"
echo Using Python %PY_VER% from venv: %PYTHON_VENV%

:: ── 1. Clone ^& patch libqi ──────────────────────────────────────────────
echo.
echo === Cloning libqi ===
pushd "%WORK_DIR%"
if exist "libqi" (
    echo   libqi/ already exists -- skipping clone.
) else (
    git clone --depth 1 --branch qi-framework-v4.0.1 https://github.com/aldebaran/libqi.git
)
cd libqi

for %%f in ("%REPO_ROOT%\patches\libqi\*.patch") do (
    echo   Applying %%~nxf ...
    git am "%%f" >nul 2>&1
    if errorlevel 1 (
        git am --abort >nul 2>&1
        echo     ^(already applied or conflict -- skipped^)
    )
)
popd

:: ── 2. Clone ^& patch libqi-python ───────────────────────────────────────
echo.
echo === Cloning libqi-python ===
pushd "%WORK_DIR%"
if exist "libqi-python" (
    echo   libqi-python/ already exists -- skipping clone.
) else (
    git clone --depth 1 --branch qi-python-v3.1.5 https://github.com/aldebaran/libqi-python.git
)
cd libqi-python

for %%f in ("%REPO_ROOT%\patches\libqi-python\*.patch") do (
    echo   Applying %%~nxf ...
    git am "%%f" >nul 2>&1
    if errorlevel 1 (
        git am --abort >nul 2>&1
        echo     ^(already applied or conflict -- skipped^)
    )
)
popd

:: ── 3. Build libqi ──────────────────────────────────────────────────────
if "%SKIP_LIBQI%"=="1" (
    echo.
    echo === Skipping libqi build ^(-skiplibqi^) ===
) else (
    echo.
    echo === Building libqi ===
    pushd "%WORK_DIR%\libqi"
    conan install . -s build_type=Release --build=missing || exit /b 1
    cmake --preset conan-release || exit /b 1
    cmake --build --preset conan-release || exit /b 1
    popd
)

:: ── 4. Build libqi-python ───────────────────────────────────────────────
echo.
echo === Building libqi-python (Python %PY_VER%) ===
pushd "%WORK_DIR%\libqi-python"

if exist "build" (
    echo   Cleaning previous libqi-python build...
    rmdir /s /q "build"
)

conan install . -s build_type=Release --build=missing || exit /b 1
cmake --preset conan-release || exit /b 1
:: Ensure CMake uses the venv's Python executable when configuring the project.
:: Re-run a configure step that sets the Python3 executable cache variable so
:: the generated extension matches the target Python version.
:: Prefer the generic FindPython cache variables used by "find_package(Python ...)".
cmake -S . -B build/release -DPython_EXECUTABLE="%PYTHON_VENV%\Scripts\python.exe" -DPython_ROOT_DIR="%PYTHON_VENV%" || exit /b 1
cmake --build --preset conan-release || exit /b 1
popd

:: ── 5. Install into venv ────────────────────────────────────────────────
echo.
echo === Installing qi into venv ===
pushd "%WORK_DIR%\libqi-python"
"%PYTHON_VENV%\Scripts\python.exe" install_local.py || exit /b 1
popd

:: ── 6. Smoke test ───────────────────────────────────────────────────────
echo.
echo === Smoke test ===
pushd "%REPO_ROOT%"
"%PYTHON_VENV%\Scripts\python.exe" -c "import qi; print(f'qi {qi.__version__} loaded successfully')"
if errorlevel 1 (
    popd
    echo ERROR: Smoke test failed.
    exit /b 1
)
echo.
echo Build complete! qi is ready to use (Python %PY_VER%).
popd

:: ── 7. Build wheel (optional) ───────────────────────────────────────────
if "%BUILD_WHEEL%"=="1" (
    echo.
    echo === Building wheel ===
    pushd "%REPO_ROOT%"
    "%PYTHON_VENV%\Scripts\python.exe" build_wheel.py || exit /b 1
    popd
)

endlocal
