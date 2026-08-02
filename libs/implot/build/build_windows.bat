@echo off
setlocal

rem Builds the ImPlot static library for Windows (x64).
rem
rem This script fetches the exact sources the committed implot_windows_x64.lib
rem was built from, compiles them with MSVC and drops the archive next to
rem implot.odin. It is meant to be run from libs/implot/build.
rem
rem Requirements:
rem   - git
rem   - Visual Studio (or the Build Tools) with the C++ workload
rem     (vcvars64.bat is located through vswhere, or used from the PATH if set)
rem
rem To upgrade ImPlot or ImGui, update the pins at the top and re-run.

set "SCRIPT_DIR=%~dp0"
set "ROOT=%SCRIPT_DIR%.."
set "DEPS=%SCRIPT_DIR%deps"

rem --- Pins -----------------------------------------------------------------
rem ImGui headers, the project uses the same version as libs/imgui.
set "IMGUI_TAG=v1.92.8-docking"
rem cimgui.h, the C header cimplot includes. Find the commit whose message
rem matches your ImGui version in https://github.com/cimgui/cimgui/commits.
set "CIMGUI_COMMIT=650a4270695803565a2f40f49bcc01726a25c702"
rem cimplot commit; its submodule pins the matching implot revision.
set "CIMPLOT_COMMIT=8213880"
rem ---------------------------------------------------------------------------

if not exist "%DEPS%" mkdir "%DEPS%"

rem ImGui headers
if not exist "%DEPS%\imgui\imgui.h" (
	echo Cloning ImGui %IMGUI_TAG%...
	git clone --depth 1 --branch %IMGUI_TAG% https://github.com/ocornut/imgui.git "%DEPS%\imgui" || exit /b 1
)

rem cimplot (C API for ImPlot) plus its implot submodule
if not exist "%DEPS%\cimplot\cimplot.h" (
	echo Cloning cimplot %CIMPLOT_COMMIT%...
	git clone https://github.com/cimgui/cimplot.git "%DEPS%\cimplot" || exit /b 1
	git -C "%DEPS%\cimplot" checkout %CIMPLOT_COMMIT% || exit /b 1
	git -C "%DEPS%\cimplot" submodule update --init --depth 1 || exit /b 1
)

rem cimgui.h
if not exist "%DEPS%\cimgui.h" (
	echo Fetching cimgui.h at %CIMGUI_COMMIT%...
	powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/cimgui/cimgui/%CIMGUI_COMMIT%/cimgui.h' -OutFile '%DEPS%\cimgui.h'" || exit /b 1
)

rem Locate the MSVC environment
set "VCVARS="
where vcvars64.bat >nul 2>nul && set "VCVARS=vcvars64.bat"
if not defined VCVARS (
	for /f "usebackq delims=" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do (
		set "VCVARS=%%i\VC\Auxiliary\Build\vcvars64.bat"
	)
)
if not defined VCVARS (
	echo Could not find vcvars64.bat. Install the Visual Studio C++ workload and retry.
	exit /b 1
)

call "%VCVARS%" || exit /b 1

set "SRC=%DEPS%\cimplot"
set "OBJ=%SCRIPT_DIR%obj"
if not exist "%OBJ%" mkdir "%OBJ%"

set "INCLUDE_DIRS=/I"%SRC%" /I"%SRC%\implot" /I"%DEPS%" /I"%DEPS%\imgui""
set "CFLAGS=/MT /EHsc /O2 /D NDEBUG /D "IMGUI_DISABLE_OBSOLETE_FUNCTIONS" /D "IMGUI_DISABLE_OBSOLETE_KEYIO""

echo Compiling cimplot.cpp...
cl /nologo /c %CFLAGS% %INCLUDE_DIRS% "%SRC%\cimplot.cpp" /Fo"%OBJ%\\" || exit /b 1
echo Compiling implot.cpp...
cl /nologo /c %CFLAGS% %INCLUDE_DIRS% "%SRC%\implot\implot.cpp" /Fo"%OBJ%\\" || exit /b 1
echo Compiling implot_items.cpp...
cl /nologo /c %CFLAGS% %INCLUDE_DIRS% "%SRC%\implot\implot_items.cpp" /Fo"%OBJ%\\" || exit /b 1
echo Compiling implot_demo.cpp...
cl /nologo /c %CFLAGS% %INCLUDE_DIRS% "%SRC%\implot\implot_demo.cpp" /Fo"%OBJ%\\" || exit /b 1

echo Creating static library...
lib /NOLOGO /OUT:"%ROOT%\implot_windows_x64.lib" "%OBJ%\*.obj" || exit /b 1

del /q "%OBJ%\*.obj" >nul 2>nul
rmdir "%OBJ%" >nul 2>nul

echo Done. Library written to %ROOT%\implot_windows_x64.lib
endlocal
