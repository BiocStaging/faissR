param([string]$Root = "$env:USERPROFILE\r-package-test-lab", [string]$Version = '1.11.0')
$ErrorActionPreference = 'Stop'
$tool = 'C:/rtools45/x86_64-w64-mingw32.static.posix'
$env:PATH = "$tool/bin;C:/rtools45/usr/bin;C:/Program Files/CMake/bin;$env:PATH"
New-Item -ItemType Directory -Force "$Root\sources" | Out-Null
$archive = "$Root\sources\faiss-$Version.tar.gz"
if (!(Test-Path $archive)) {
    Invoke-WebRequest "https://github.com/facebookresearch/faiss/archive/refs/tags/v$Version.tar.gz" -OutFile $archive
}
Get-FileHash $archive -Algorithm SHA256 | Format-List | Out-File "$archive.sha256.txt"
& "$env:SystemRoot\System32\tar.exe" -xzf $archive -C "$Root\sources"
if ($LASTEXITCODE) { throw 'FAISS extraction failed' }
if ($Version -eq '1.11.0') {
    & 'C:/rtools45/usr/bin/patch.exe' -p1 -d "$Root/sources/faiss-$Version" -i "$PSScriptRoot/faiss-1.11.0-mingw.patch"
    if ($LASTEXITCODE) { throw 'FAISS MinGW compatibility patch failed' }
}
$prefix = "$Root/faiss-$Version".Replace('\','/')
& cmake -S "$Root/sources/faiss-$Version" -B "$Root/faiss-build" -G 'Unix Makefiles' `
    "-DCMAKE_MAKE_PROGRAM=C:/rtools45/usr/bin/make.exe" `
    "-DCMAKE_C_COMPILER=$tool/bin/gcc.exe" "-DCMAKE_CXX_COMPILER=$tool/bin/g++.exe" `
    '-DFAISS_ENABLE_GPU=OFF' '-DFAISS_ENABLE_PYTHON=OFF' '-DBUILD_TESTING=OFF' `
    '-DBUILD_SHARED_LIBS=OFF' '-DFAISS_OPT_LEVEL=generic' '-DCMAKE_BUILD_TYPE=Release' `
    "-DBLAS_LIBRARIES=$tool/lib/libblas.a" "-DLAPACK_LIBRARIES=$tool/lib/liblapack.a" `
    "-DCMAKE_INSTALL_PREFIX=$prefix"
if ($LASTEXITCODE) { throw 'FAISS configuration failed' }
& cmake --build "$Root/faiss-build" --target install -j2
if ($LASTEXITCODE) { throw 'FAISS compilation failed' }
Write-Output "FAISS_HOME=$prefix"
