# Builds Morph for Windows: a self-contained publish per architecture, then
#   dist/Morph-<version>.msixbundle         for the Microsoft Store (the Store signs it)
#   dist/Morph-<version>-<arch>.msix        the same, one architecture each
#   dist/Morph-<version>-<arch>-setup.exe   installer for GitHub releases (Inno Setup)
#
#   pwsh windows/scripts/package.ps1 [-Version 1.0.0] [-Architectures x64,arm64]
#
# Store builds need the identity Partner Center shows under Product management > Product identity:
#   -IdentityName 12345Name.Morph -Publisher "CN=XXXXXXXX-..." -PublisherDisplayName "Geetansh Goyal"
# (or MSIX_IDENTITY_NAME, MSIX_PUBLISHER and MSIX_PUBLISHER_DISPLAY_NAME in the environment).
# Needs the .NET 10 SDK, the Windows 10/11 SDK (makeappx, makepri) and Inno Setup 6 (iscc).
param(
    [string]$Version = "1.0.0",
    [string[]]$Architectures = @("x64", "arm64"),
    [string]$IdentityName = $(if ($env:MSIX_IDENTITY_NAME) { $env:MSIX_IDENTITY_NAME } else { "Morph" }),
    [string]$Publisher = $(if ($env:MSIX_PUBLISHER) { $env:MSIX_PUBLISHER } else { "CN=Geetansh Goyal" }),
    [string]$PublisherDisplayName = $(if ($env:MSIX_PUBLISHER_DISPLAY_NAME) { $env:MSIX_PUBLISHER_DISPLAY_NAME } else { "Geetansh Goyal" }),
    [switch]$SkipInstaller
)
$ErrorActionPreference = "Stop"
$windows = Split-Path $PSScriptRoot -Parent
$build = Join-Path $windows "build"
$dist = Join-Path $windows "dist"
Remove-Item $build, $dist -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory $build, $dist | Out-Null

# The newest Windows SDK's tools for this machine.
$kits = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
$sdk = Get-ChildItem $kits -Directory | Where-Object Name -Match '^10\.' | Sort-Object { [version]$_.Name } -Descending |
    Where-Object { Test-Path (Join-Path $_.FullName "x64\makeappx.exe") } | Select-Object -First 1
if (-not $sdk) { throw "Windows SDK not found under $kits" }
$makeappx = Join-Path $sdk.FullName "x64\makeappx.exe"
$makepri = Join-Path $sdk.FullName "x64\makepri.exe"

function Invoke-Tool([string]$tool, [string[]]$arguments) {
    & $tool @arguments
    if ($LASTEXITCODE -ne 0) { throw "$(Split-Path $tool -Leaf) failed with exit code $LASTEXITCODE" }
}

$msixFolder = Join-Path $build "msix"
New-Item -ItemType Directory $msixFolder | Out-Null

foreach ($arch in $Architectures) {
    Write-Host "== $arch"
    $publish = Join-Path $build "publish-$arch"
    Invoke-Tool dotnet @("publish", (Join-Path $windows "src\Morph.App\Morph.App.csproj"), "-c", "Release", "-r", "win-$arch",
        "--self-contained", "true", "-p:Version=$Version", "-o", $publish)

    # MSIX: the app, the tile images and a manifest with this build's identity, version and architecture.
    $stage = Join-Path $build "stage-$arch"
    Copy-Item $publish $stage -Recurse
    # Into the Assets folder the app already has (its tray icon), not a nested one.
    Copy-Item (Join-Path $windows "packaging\Assets\*") (Join-Path $stage "Assets") -Force
    foreach ($needed in "Morph.exe", "Assets\Morph.ico", "Assets\Square44x44Logo.scale-100.png", "Assets\StoreLogo.scale-100.png") {
        if (-not (Test-Path (Join-Path $stage $needed))) { throw "$needed is missing from the package" }
    }
    (Get-Content (Join-Path $windows "packaging\AppxManifest.xml") -Raw).
        Replace("{IdentityName}", $IdentityName).
        Replace("{Publisher}", [Security.SecurityElement]::Escape($Publisher)).
        Replace("{PublisherDisplayName}", [Security.SecurityElement]::Escape($PublisherDisplayName)).
        Replace("{Version}", "$Version.0").
        Replace("{Arch}", $arch) | Set-Content (Join-Path $stage "AppxManifest.xml") -Encoding utf8

    # resources.pri picks the right scale and size of each image for the screen. It indexes a folder with just
    # the images, since app file names such as Magick.NET-Q8-AnyCPU.dll would read as resource qualifiers.
    $priRoot = Join-Path $build "pri-$arch"
    New-Item -ItemType Directory $priRoot | Out-Null
    Copy-Item (Join-Path $windows "packaging\Assets") (Join-Path $priRoot "Assets") -Recurse
    $config = Join-Path $build "priconfig-$arch.xml"
    Invoke-Tool $makepri @("createconfig", "/cf", $config, "/dq", "en-US", "/pv", "10.0.0", "/o")
    Invoke-Tool $makepri @("new", "/pr", $priRoot, "/cf", $config, "/mn", (Join-Path $stage "AppxManifest.xml"),
        "/of", (Join-Path $stage "resources.pri"), "/o")

    $msix = Join-Path $msixFolder "Morph-$Version-$arch.msix"
    Invoke-Tool $makeappx @("pack", "/d", $stage, "/p", $msix, "/o")
    Copy-Item $msix $dist

    if (-not $SkipInstaller) {
        $iscc = (Get-Command iscc -ErrorAction SilentlyContinue).Source
        if (-not $iscc) { $iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" }
        Invoke-Tool $iscc @("/Q", "/DVersion=$Version", "/DArch=$arch", "/DSource=$publish", "/O$dist",
            (Join-Path $windows "installer\Morph.iss"))
    }
}

Invoke-Tool $makeappx @("bundle", "/d", $msixFolder, "/p", (Join-Path $dist "Morph-$Version.msixbundle"), "/bv", "$Version.0", "/o")
Get-ChildItem $dist | Format-Table Name, @{ Label = "MB"; Expression = { [math]::Round($_.Length / 1MB, 1) } }
