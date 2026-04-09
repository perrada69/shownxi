@echo off
rem Build script for SHOWNXI dot command (ZX Spectrum Next)
rem Requires: sjasmplus

echo Building SHOWNXI...

sjasmplus --raw=shownxi shownxi.asm

if errorlevel 1 (
    echo BUILD FAILED
    exit /b 1
)

echo.
echo OK - output: shownxi
echo Copy 'shownxi' to /dot/ folder on your Next SD card.
echo Usage: .shownxi filename.nxi

echo Spoustim CSpect...

D:\Source\Assembler\CSpect\hdfmonkey.exe put D:\Source\Assembler\CSpect\cspect-next-2gb.img shownxi /dot/

D:\Source\Assembler\CSpect\hdfmonkey.exe put D:\Source\Assembler\CSpect\cspect-next-2gb.img screen1.nxi /
D:\Source\Assembler\CSpect\hdfmonkey.exe put D:\Source\Assembler\CSpect\cspect-next-2gb.img sillicon.nxi /
D:\Source\Assembler\CSpect\hdfmonkey.exe put D:\Source\Assembler\CSpect\cspect-next-2gb.img screen2.nxi /



D:\Source\Assembler\CSpect\CSpect.exe -zxnext -basickeys -tv -mmc=D:\Source\Assembler\CSpect\cspect-next-2gb.img 
