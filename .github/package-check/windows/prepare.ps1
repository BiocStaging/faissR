param([string]$Root = "$env:USERPROFILE\r-package-test-lab")
$ErrorActionPreference = 'Stop'
$runtime = "$Root\R-4.6.1"
if (!(Test-Path "$runtime\bin\Rscript.exe")) {
    Copy-Item 'C:\Program Files\R\R-4.6.1' $runtime -Recurse
}
$pandoc = "$Root\pandoc-3.6.4"
if (!(Test-Path "$pandoc\pandoc.exe")) {
    $zip = "$Root\pandoc-3.6.4.zip"
    Invoke-WebRequest 'https://github.com/jgm/pandoc/releases/download/3.6.4/pandoc-3.6.4-windows-x86_64.zip' -OutFile $zip
    Get-FileHash $zip -Algorithm SHA256 | Format-List | Out-File "$zip.sha256.txt"
    Expand-Archive $zip -DestinationPath $Root -Force
}
& "$runtime\bin\Rscript.exe" "$Root\harness\dependencies.R" "$Root\dependencies"
exit $LASTEXITCODE
