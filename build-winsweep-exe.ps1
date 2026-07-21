[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PayloadRoot,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath
$launcherRoot = Join-Path $root "launcher"
$project = Join-Path $launcherRoot "WinSweepLauncher.csproj"
$program = Join-Path $launcherRoot "Program.cs"
$payloadRootFull = [IO.Path]::GetFullPath($PayloadRoot)
$outputFull = [IO.Path]::GetFullPath($OutputPath)

if (-not (Test-Path -LiteralPath $project -PathType Leaf)) {
    throw "Launcher project was not found: $project"
}
if (-not (Test-Path -LiteralPath $program -PathType Leaf)) {
    throw "Launcher source was not found: $program"
}
if (-not (Test-Path -LiteralPath $payloadRootFull -PathType Container)) {
    throw "Payload root was not found: $payloadRootFull"
}
$compilerCandidates = @(
    (Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
    (Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe")
)
$compiler = $compilerCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($compiler)) {
    throw "The Windows C# compiler was not found. WinSweep.exe requires .NET Framework 4.8 build tools on the build machine."
}

$buildRoot = Join-Path $root ".launcher-build"
$payloadZip = Join-Path $launcherRoot "WinSweepPayload.zip"
$builtExe = Join-Path $buildRoot "WinSweep.exe"

if (Test-Path -LiteralPath $buildRoot) {
    Remove-Item -LiteralPath $buildRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
if (Test-Path -LiteralPath $payloadZip) {
    Remove-Item -LiteralPath $payloadZip -Force
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory(
    $payloadRootFull,
    $payloadZip,
    [IO.Compression.CompressionLevel]::Optimal,
    $false)

try {
    & $compiler /nologo /target:winexe /optimize+ /out:$builtExe `
        /reference:System.Windows.Forms.dll `
        /reference:System.IO.Compression.dll `
        /reference:System.IO.Compression.FileSystem.dll `
        "/resource:$payloadZip,WinSweepPayload.zip" `
        $program
    if ($LASTEXITCODE -ne 0) {
        throw "C# compilation failed with exit code $LASTEXITCODE."
    }

    if (-not (Test-Path -LiteralPath $builtExe -PathType Leaf)) {
        throw "C# compilation did not produce WinSweep.exe."
    }

    $outputDirectory = Split-Path -Parent $outputFull
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    Copy-Item -LiteralPath $builtExe -Destination $outputFull -Force
    Write-Host "WinSweep.exe created:"
    Write-Host $outputFull
}
finally {
    if (Test-Path -LiteralPath $payloadZip) {
        Remove-Item -LiteralPath $payloadZip -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $buildRoot) {
        Remove-Item -LiteralPath $buildRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
