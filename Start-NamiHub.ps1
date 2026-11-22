param(
    [string]$Root = (Join-Path $PSScriptRoot 'fixtures/media'),
    [string]$StateDirectory = (Join-Path $env:LOCALAPPDATA 'NamiHub/interop-v1'),
    [ValidateRange(0,65535)][int]$Port = 8443,
    [switch]$Lan,
    [switch]$TraceReads,
    [switch]$OperatorPipe
)
$ErrorActionPreference = 'Stop'
$rootPath = (Resolve-Path -LiteralPath $Root).ProviderPath
$statePath = [IO.Path]::GetFullPath($StateDirectory)
function Nested-In([string]$Child, [string]$Parent) {
    $prefix = $Parent.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    return $Child.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}
if ($rootPath -eq $statePath -or (Nested-In $statePath $rootPath) -or (Nested-In $rootPath $statePath)) {
    throw 'Use separate, non-overlapping share and state directories.'
}
& (Join-Path $PSScriptRoot 'tool/init_tls.ps1') -StateDirectory $statePath
$listenAddress = if ($Lan) { '0.0.0.0' } else { '127.0.0.1' }
$options = @('--root',$rootPath,'--state',$statePath,'--bind',$listenAddress,'--port',"$Port")
if ($TraceReads) { $options += '--trace-reads' }
if ($OperatorPipe) { $options += '--operator-pipe' }
$binary = Join-Path $PSScriptRoot 'nami_hub.exe'
if (Test-Path -LiteralPath $binary) {
    & $binary @options
    exit $LASTEXITCODE
}
Push-Location $PSScriptRoot
try {
    & dart pub get --offline
    if ($LASTEXITCODE -ne 0) { & dart pub get }
    if ($LASTEXITCODE -ne 0) { throw 'dart pub get failed' }
    & dart run bin/nami_hub.dart @options
    exit $LASTEXITCODE
} finally { Pop-Location }
