@echo off >nul
chcp 1251 >nul
SetLocal EnableExtensions

set c = 0

:: 'Blue','Green','Cyan','Red','Magenta','Yellow','White'

	IF NOT EXIST logs mkdir logs
		del "*.smx" > nul 2>&1
		del "logs\*.log" > nul 2>&1	
		
	for /f "tokens=1*delims=-" %%b in ('dir "*.sp" /B') do ( 
		if %%c == 1 ( call :EchoColor " [%%b]" Yellow 
		) else ( echo [%%b]   )
			
		
		"_Компилятор SM 1.9\spcomp.exe" "%%b" -D. -i. -i"include" >"logs\%%b.log" 
		
		
		findstr /c:"Code" "logs\%%b.log" > nul		
		if ERRORLEVEL 1 ( 
			if %%c == 1 ( call :EchoColor " Ошибка.. Загляните в файл: logs\%%b.log" Red 
			) else ( echo Ошибка.. Загляните в файл: logs\%%b.log )
		) else (
			if %%c == 1 ( call :EchoColor " Успешно.." Green 
			) else ( echo  Успешно.. )
		)
		 
		
		del temp.txt  > nul 2>&1 
	)
pause



:EchoColor [text] [color]
powershell "'%~1'.GetEnumerator()|%%{Write-Host $_ -NoNewline -ForegroundColor %~2}"
exit /B