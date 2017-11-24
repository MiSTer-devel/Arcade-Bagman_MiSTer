@echo off

set    zip=bagman.zip
set ifiles=e9_b05.bin+f9_b06.bin+f9_b07.bin+k9_b08.bin+m9_b09s.bin+n9_b10.bin+t9_b12.bin+t9_b12.bin+t9_b12.bin +t9_b12.bin +t9_b12.bin +t9_b12.bin +t9_b12.bin +t9_b12.bin +t9_b12.bin +t9_b12.bin +e1_b02.bin+c1_b01.bin+j1_b04.bin+f1_b03s.bin+r9_b11.bin+t9_b12.bin
set  ofile=a.bagman.rom

rem =====================================
setlocal ENABLEDELAYEDEXPANSION

set pwd=%~dp0
echo.
echo.

if EXIST %zip% (

	!pwd!7za x -otmp %zip%
	if !ERRORLEVEL! EQU 0 ( 
		cd tmp

		copy /b/y %ifiles% !pwd!%ofile%
		if !ERRORLEVEL! EQU 0 ( 
			echo.
			echo ** done **
			echo.
			echo Copy "%ofile%" into root of SD card
		)
		cd !pwd!
		rmdir /s /q tmp
	)

) else (

	echo Error: Cannot find "%zip%" file
	echo.
	echo Put "%zip%", "7za.exe" and "%~nx0" into the same directory
)

echo.
echo.
pause
