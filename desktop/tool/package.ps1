param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '../../dist'),
    [switch]$SkipBuild
)
$ErrorActionPreference = 'Stop'
$appRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$output = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
Push-Location $appRoot
try {
    if (-not $SkipBuild) {
        & flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw 'Windows Release build failed.' }
    }
    $release = Join-Path $appRoot 'build/windows/x64/runner/Release'
    $version = (Select-String -LiteralPath 'pubspec.yaml' -Pattern '^version:\s*(\S+)').Matches.Groups[1].Value
    $exeVersion = (Get-Item -LiteralPath (Join-Path $release 'NamiHub.exe')).VersionInfo.ProductVersion
    if ($version -ne $exeVersion) { throw "Release executable is $exeVersion, expected $version. Rebuild the desktop app." }
    & python (Join-Path $PSScriptRoot 'package_desktop.py') --runtime $release --output $output
    if ($LASTEXITCODE -ne 0) { throw 'Could not package the Windows runtime.' }
} finally { Pop-Location }
