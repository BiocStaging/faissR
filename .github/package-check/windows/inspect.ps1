$ErrorActionPreference = 'Stop'
Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, OSArchitecture
Get-PSDrive C | Select-Object Used, Free
Get-ChildItem 'C:\rtools45\x86_64-w64-mingw32.static.posix\lib' -Filter '*blas*'
Get-ChildItem 'C:\rtools45\x86_64-w64-mingw32.static.posix\lib' -Filter '*lapack*'
& 'C:\Program Files\R\R-4.6.1\bin\Rscript.exe' (Join-Path (Split-Path $PSScriptRoot -Parent) 'inspect.R')
exit $LASTEXITCODE
