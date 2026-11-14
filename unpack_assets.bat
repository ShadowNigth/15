@echo off
rem Restaura assets/ (modelos, mapas, texturas, sonidos) desde los archivos de packs/.
cd /d "%~dp0"
where py >nul 2>nul && (set "PY=py -3") || (set "PY=python")
%PY% tools\pak.py unpack %*
if errorlevel 1 (
  echo.
  echo No se pudo desempaquetar. Instala Python 3.8+ desde https://www.python.org/ y vuelve a intentarlo.
)
pause
