# Builds MacWispr for Windows: dist\MacWispr\ (app folder), a portable zip and,
# when Inno Setup 6 is installed, an installer.  Run from the windows\ folder:
#   powershell -ExecutionPolicy Bypass -File build.ps1
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$version = (Select-String -Path macwispr_win\config.py -Pattern '^VERSION = "(.+)"').Matches[0].Groups[1].Value
Write-Host "MacWispr for Windows $version"

if (-not (Test-Path .venv)) {
    if (Get-Command py -ErrorAction SilentlyContinue) { py -3.12 -m venv .venv } else { python -m venv .venv }
    if ($LASTEXITCODE) { throw "could not create venv (needs Python 3.12)" }
}
$py = ".venv\Scripts\python.exe"
& $py -m pip install --disable-pip-version-check -q -r requirements-build.txt
if ($LASTEXITCODE) { throw "pip install failed" }

& $py -m pytest -q tests
if ($LASTEXITCODE) { throw "tests failed" }

& $py -m PyInstaller --noconfirm --clean --windowed --name MacWispr `
    --icon assets\MacWispr.ico --add-data "assets\MacWispr.ico;assets" `
    --collect-data onnx_asr --collect-submodules onnx_asr --collect-binaries onnxruntime --hidden-import pystray._win32 `
    --copy-metadata onnx-asr --copy-metadata onnxruntime --copy-metadata huggingface-hub `
    MacWispr.py
if ($LASTEXITCODE) { throw "PyInstaller failed" }

New-Item -ItemType Directory -Force out | Out-Null
$zip = "out\MacWispr-$version-windows-x64.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path dist\MacWispr -DestinationPath $zip

$iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
if (Test-Path $iscc) {
    & $iscc /Qp "/DAppVersion=$version" installer.iss
    if ($LASTEXITCODE) { throw "Inno Setup failed" }
} else {
    Write-Host "Inno Setup 6 not found; skipped installer"
}
Get-ChildItem out | Format-Table Name, Length
