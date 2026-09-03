# Builds the pieces of a release and packages them: the native projects,
# the BERTModule R package, the console, the installer and a zip.
#
#   .\build-release.ps1 -Version 2.4.3-r4
#
# Prerequisites: Visual Studio 2026 (msbuild on the path or found below),
# R 4.2 or later with Rtools for the module, node for the console, and NSIS
# (makensis) for the installer. Each stage can be skipped.
#
# Output, in ..\Build: the native binaries, module\, Console\win-unpacked\,
# and in this directory BERT-Installer-<version>-x64.exe and
# BERT-<version>-x64.zip.

Param(
  [string]$Version = "",
  [string]$RHome = "",
  [string]$MakeNsis = "makensis",
  [switch]$SkipNative,
  [switch]$SkipModule,
  [switch]$SkipConsole,
  [switch]$SkipInstaller,
  [switch]$SkipZip
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Resolve-Path (Join-Path $here "..")
$build = Join-Path $root "Build"

function Step($text) { Write-Host "`n== $text" -ForegroundColor Cyan }
function Fail($text) { Write-Host $text -ForegroundColor Red; exit 1 }

# ---- version: from the add-in's header unless given ------------------------
if (-not $Version) {
  $header = Get-Content (Join-Path $root "BERT\BERT\include\bert_version.h") -Raw
  $number = [regex]::Match($header, 'BERT_VERSION_NUMBER\s+L"([^"]+)"').Groups[1].Value
  $tag = [regex]::Match($header, 'BERT_VERSION_TAG\s+L"([^"]*)"').Groups[1].Value
  if (-not $number) { Fail "could not read the version from bert_version.h" }
  $Version = "$number$tag"
}
Write-Host "release version: $Version"

# ---- R: the registered current version unless given ------------------------
if (-not $RHome) {
  foreach ($key in "HKCU:\SOFTWARE\R-core\R64", "HKLM:\SOFTWARE\R-core\R64", "HKCU:\SOFTWARE\R-core\R", "HKLM:\SOFTWARE\R-core\R") {
    if (Test-Path $key) { $RHome = (Get-ItemProperty $key).InstallPath; if ($RHome) { break } }
  }
}
if (-not $RHome -or -not (Test-Path "$RHome\bin\x64\R.exe")) { Fail "no 64-bit R found; pass -RHome" }
Write-Host "R: $RHome"

# ---- native ----------------------------------------------------------------
if (-not $SkipNative) {
  Step "native projects (Release x64)"
  $msbuild = Get-Command msbuild -ErrorAction SilentlyContinue
  if ($msbuild) { $msbuild = $msbuild.Source }
  else {
    $candidates = Get-ChildItem "C:\Program Files\Microsoft Visual Studio\*\*\MSBuild\Current\Bin\MSBuild.exe" -ErrorAction SilentlyContinue
    if (-not $candidates) { Fail "msbuild not found" }
    $msbuild = $candidates[0].FullName
  }
  & $msbuild (Join-Path $root "BERT\BERT.sln") -p:Configuration=Release -p:Platform=x64 -m -nologo -v:minimal
  if ($LASTEXITCODE) { Fail "native build failed" }
}

# ---- R module --------------------------------------------------------------
if (-not $SkipModule) {
  Step "BERTModule (R CMD INSTALL with $RHome)"
  $lib = Join-Path $build "module"
  if (Test-Path $lib) { Remove-Item $lib -Recurse -Force }
  New-Item -ItemType Directory $lib | Out-Null
  & "$RHome\bin\x64\R.exe" CMD INSTALL --library="$lib" --no-multiarch (Join-Path $root "Module")
  if ($LASTEXITCODE) { Fail "module build failed" }
}

# ---- console ---------------------------------------------------------------
if (-not $SkipConsole) {
  Step "console (npm run repackage)"
  Push-Location (Join-Path $root "Console")
  try {
    if (-not (Test-Path "node_modules")) { npm install --no-audit --no-fund; if ($LASTEXITCODE) { Fail "npm install failed" } }
    npm run repackage
    if ($LASTEXITCODE) { Fail "console build failed" }
  } finally { Pop-Location }
}

# ---- what a release contains -----------------------------------------------
$files = "BERT64.xll", "BERTRibbon2x64.dll", "ControlR.exe",
         "bert-config-template.json", "user-stylesheet-template.less", "Welcome.md", "bert2.ico"

# shipped from this directory rather than from Build
$installer_files = "BERT-IntelliSense.xlam"

# the binaries must not need the Visual C++ redistributable: everything is
# linked against the static runtime, protobuf included (x64-windows-static)
foreach ($f in "BERT64.xll", "BERTRibbon2x64.dll", "ControlR.exe") {
  $bytes = [IO.File]::ReadAllBytes((Join-Path $build $f))
  $text = [Text.Encoding]::ASCII.GetString($bytes)
  foreach ($dll in "VCRUNTIME140", "MSVCP140", "libprotobuf.dll", "abseil_dll.dll") {
    if ($text.IndexOf($dll, [StringComparison]::OrdinalIgnoreCase) -ge 0) { Fail "$f imports $dll; build with the static vcpkg triplet" }
  }
}
$dirs = "Console", "module", "startup"
foreach ($f in $files) { if (-not (Test-Path (Join-Path $build $f))) { Fail "missing $f in Build" } }
foreach ($d in $dirs) { if (-not (Test-Path (Join-Path $build $d))) { Fail "missing $d\ in Build" } }

# ---- installer -------------------------------------------------------------
if (-not $SkipInstaller) {
  Step "installer (makensis)"
  if (-not (Get-Command $MakeNsis -ErrorAction SilentlyContinue)) {
    $found = "${env:ProgramFiles(x86)}\NSIS\makensis.exe", "$env:ProgramFiles\NSIS\makensis.exe" | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $found) { Fail "makensis not found; install NSIS or pass -MakeNsis" }
    $MakeNsis = $found
  }
  Push-Location $here
  try {
    & $MakeNsis "/DVERSION=$Version" install-script.nsi
    if ($LASTEXITCODE) { Fail "makensis failed" }
  } finally { Pop-Location }
  Write-Host "installer: $(Join-Path $here "BERT-Installer-$Version-x64.exe")"
}

# ---- zip -------------------------------------------------------------------
if (-not $SkipZip) {
  Step "zip"
  $stage = Join-Path $env:TEMP "bert-release-$Version"
  if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
  New-Item -ItemType Directory $stage | Out-Null
  foreach ($f in $files) { Copy-Item (Join-Path $build $f) $stage }
  foreach ($f in $installer_files) { Copy-Item (Join-Path $here $f) $stage }
  foreach ($d in $dirs) { Copy-Item (Join-Path $build $d) (Join-Path $stage $d) -Recurse }
  # the languages file with no R filled in: the zip relies on BERT.R.home
  (Get-Content (Join-Path $here "bert-languages.template.json") -Raw).Replace('"@R_HOME@"', '""') |
    Set-Content (Join-Path $stage "bert-languages.json") -NoNewline
  Copy-Item (Join-Path $here "INSTALL-FROM-ZIP.md") $stage
  $zip = Join-Path $here "BERT-$Version-x64.zip"
  if (Test-Path $zip) { Remove-Item $zip -Force }
  Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip -CompressionLevel Optimal
  Remove-Item $stage -Recurse -Force
  Write-Host "zip: $zip"
}

Write-Host "`ndone" -ForegroundColor Green
