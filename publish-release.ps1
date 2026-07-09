[CmdletBinding()]
param(
    [string]$Version = "",
    [string]$Repository = "",
    [switch]$Prerelease,
    [switch]$Draft,
    [switch]$SkipTagPush,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath
$cleanupScript = Join-Path $root "cleanup-windows.ps1"
$buildScript = Join-Path $root "build-release.ps1"

function Get-WinSweepVersion {
    param([string]$ScriptPath)

    $text = Get-Content -LiteralPath $ScriptPath -Raw -Encoding UTF8
    if ($text -match 'WinSweepVersion\s*=\s*"([^"]+)"') {
        return $Matches[1]
    }

    throw "Could not read WinSweepVersion from cleanup-windows.ps1."
}

function Find-Tool {
    param([string]$Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) {
        if ($Name -eq "gh") {
            throw "GitHub CLI (gh) was not found on PATH. Install it from https://cli.github.com/ and run: gh auth login"
        }
        if ($Name -eq "git") {
            throw "Git was not found on PATH. Install Git for Windows or run with -SkipTagPush after creating/pushing the tag yourself."
        }
        throw "$Name was not found on PATH."
    }

    return $command.Source
}

function Invoke-External {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    Write-Host "> $FilePath $($Arguments -join ' ')"
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE."
    }
}

function Get-RepositoryFromGh {
    param([string]$GhPath)

    Push-Location $root
    try {
        $value = & $GhPath repo view --json nameWithOwner -q ".nameWithOwner"
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($value)) {
            throw "Could not resolve GitHub repository. Pass -Repository owner/name."
        }
        return $value.Trim()
    }
    finally {
        Pop-Location
    }
}

if (-not (Test-Path -LiteralPath $cleanupScript -PathType Leaf)) {
    throw "cleanup-windows.ps1 was not found next to this file."
}

if (-not (Test-Path -LiteralPath $buildScript -PathType Leaf)) {
    throw "build-release.ps1 was not found next to this file."
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = Get-WinSweepVersion -ScriptPath $cleanupScript
}

$Version = $Version.Trim().TrimStart("v")
if ($Version -notmatch '^\d+\.\d+\.\d+([.-][A-Za-z0-9.-]+)?$') {
    throw "Version should look like 0.4.3 or v0.4.3. Got: $Version"
}

$tag = "v$Version"
$zipPath = Join-Path $root "dist\WinSweep-v$Version.zip"
$notesPath = Join-Path $root "release-notes.md"

& $buildScript -Version $Version

if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
    throw "Release zip was not created: $zipPath"
}

@(
    "WinSweep $tag",
    "",
    "Download WinSweep-v$Version.zip, extract it, then run setup-desktop-folder.bat or winsweep-menu.bat.",
    "",
    "Included:",
    "- Windows cleanup profiles and pressure guard",
    "- HTML reports",
    "- disk analyzer lite",
    "- cleanup history",
    "- configurable winsweep-config.json"
) | Set-Content -LiteralPath $notesPath -Encoding UTF8

Write-Host ""
Write-Host "Release asset:"
Write-Host $zipPath
Write-Host ""

if ($DryRun) {
    Write-Host "Dry run only. No tag or GitHub release was created."
    Write-Host "Would publish $tag to GitHub Releases."
    exit 0
}

$git = Find-Tool -Name "git"
$gh = Find-Tool -Name "gh"

if ([string]::IsNullOrWhiteSpace($Repository)) {
    $Repository = Get-RepositoryFromGh -GhPath $gh
}

Push-Location $root
try {
    if (-not $SkipTagPush) {
        $existingLocalTag = & $git tag --list $tag
        if ($LASTEXITCODE -ne 0) {
            throw "Could not list local tags."
        }

        if ([string]::IsNullOrWhiteSpace($existingLocalTag)) {
            Invoke-External -FilePath $git -Arguments @("tag", $tag)
        }
        else {
            Write-Host "Local tag already exists: $tag"
        }

        $existingRemoteTag = & $git ls-remote --tags origin "refs/tags/$tag"
        if ($LASTEXITCODE -ne 0) {
            throw "Could not check remote tag $tag."
        }

        if ([string]::IsNullOrWhiteSpace($existingRemoteTag)) {
            Invoke-External -FilePath $git -Arguments @("push", "origin", $tag)
        }
        else {
            Write-Host "Remote tag already exists: $tag"
        }
    }

    & $gh release view $tag --repo $Repository *> $null
    $releaseExists = ($LASTEXITCODE -eq 0)

    if ($releaseExists) {
        Invoke-External -FilePath $gh -Arguments @("release", "upload", $tag, $zipPath, "--repo", $Repository, "--clobber")
    }
    else {
        $args = @("release", "create", $tag, $zipPath, "--repo", $Repository, "--title", "WinSweep $tag", "--notes-file", $notesPath)
        if ($Prerelease) {
            $args += "--prerelease"
        }
        if ($Draft) {
            $args += "--draft"
        }

        Invoke-External -FilePath $gh -Arguments $args
    }
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host "Release published:"
Write-Host "https://github.com/$Repository/releases/tag/$tag"
