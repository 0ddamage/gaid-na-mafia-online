@echo off
call "%~dp0install.bat" restore %*
exit /b %ERRORLEVEL%
