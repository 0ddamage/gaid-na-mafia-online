@echo off
setlocal EnableExtensions DisableDelayedExpansion
if /I not "%REPACKGENDER_NO_REOPEN%"=="1" (
  if not defined REPACKGENDER_RELAUNCHED (
    echo(%CMDCMDLINE% | findstr /I /C:" /c " >nul
    if not errorlevel 1 (
      >nul 2>&1 reg add HKCU\Console /v VirtualTerminalLevel /t REG_DWORD /d 1 /f
      set "REPACKGENDER_RELAUNCHED=1"
      set "REPACKGENDER_FORCE_COLOR=1"
      start "" "%SystemRoot%\System32\cmd.exe" /k ""%~f0" %*"
      exit /b
    )
  )
)
set "CSCRIPT_EXE=%SystemRoot%\System32\cscript.exe"
if not exist "%CSCRIPT_EXE%" set "CSCRIPT_EXE=cscript.exe"
"%CSCRIPT_EXE%" //nologo //e:jscript "%~dp0..\_core\windows\install.js" %*
set "RC=%ERRORLEVEL%"
if not "%REPACKGENDER_NO_HOLD%"=="1" (
  echo.
  pause
)
exit /b %RC%
