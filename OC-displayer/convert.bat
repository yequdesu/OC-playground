@echo off
setlocal enabledelayedexpansion

set JAR=ctif-convert.jar
set IN_DIR=in
set OUT_DIR=out
set PREVIEW_DIR=preview

echo CTIF Batch Converter
echo ====================

:: Create directories if not exist
if not exist %IN_DIR% mkdir %IN_DIR%
if not exist %OUT_DIR% mkdir %OUT_DIR%
if not exist %PREVIEW_DIR% mkdir %PREVIEW_DIR%

:: Count files
set COUNT=0
for %%f in (%IN_DIR%\*.png %IN_DIR%\*.jpg %IN_DIR%\*.jpeg) do set /a COUNT+=1
echo Found %COUNT% input file(s)

if %COUNT%==0 echo No files to convert & goto :end

:: Convert each file
for %%f in (%IN_DIR%\*.png %IN_DIR%\*.jpg %IN_DIR%\*.jpeg) do (
    set "BASE=%%~nf"
    if not exist "!OUT_DIR!\!BASE!.ctif" (
        echo Converting: %%f
        java -jar !JAR! -W 320 -H 200 --resize-mode QUALITY_NATIVE --dither-mode ERROR -P "!PREVIEW_DIR!\!BASE!.png" -o "!OUT_DIR!\!BASE!.ctif" "%%f"
    ) else (
        echo Skipping: !BASE!.ctif (already exists)
    )
)

echo.
echo Done! Converted files are in %OUT_DIR%/
echo Preview images are in %PREVIEW_DIR%/

:end
pause