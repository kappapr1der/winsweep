[CmdletBinding()]
param(
    [string]$Version = "",
    [string]$Repository = "kappapr1der/winsweep",
    [string]$Token = "",
    [string]$TargetCommitish = "main",
    [switch]$Prerelease,
    [switch]$Draft,
    [switch]$UpdateExisting,
    [switch]$ReplaceAsset,
    [switch]$SkipTagPush,
    [ValidateRange(10, 300)]
    [int]$RequestTimeoutSeconds = 30,
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

function Get-PlainTextSecret {
    param([Security.SecureString]$SecureValue)

    if (-not $SecureValue) {
        return ""
    }

    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

function Get-TokenStorePath {
    $base = [Environment]::GetFolderPath("ApplicationData")
    if ([string]::IsNullOrWhiteSpace($base)) {
        $base = Join-Path $HOME "AppData\Roaming"
    }

    return Join-Path (Join-Path $base "WinSweep") "github-token.txt"
}

function Get-StoredReleaseToken {
    $path = Get-TokenStorePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return ""
    }

    try {
        $encrypted = (Get-Content -LiteralPath $path -Raw -Encoding ASCII).Trim()
        $secure = $encrypted | ConvertTo-SecureString
        $plain = Get-PlainTextSecret -SecureValue $secure
        if (-not [string]::IsNullOrWhiteSpace($plain)) {
            Write-Host "Using saved token from $path."
            return $plain.Trim()
        }
    }
    catch {
        Write-Warning "Saved token exists but could not be decrypted. Run save-github-token.ps1 again."
    }

    return ""
}

function Get-ReleaseToken {
    param([string]$ExplicitToken)

    if (-not [string]::IsNullOrWhiteSpace($ExplicitToken)) {
        return $ExplicitToken.Trim()
    }

    foreach ($name in @("WINSWEEP_GITHUB_TOKEN", "GITHUB_TOKEN", "GH_TOKEN")) {
        $value = [Environment]::GetEnvironmentVariable($name, "Process")
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            Write-Host "Using token from $name."
            return $value.Trim()
        }
    }

    $stored = Get-StoredReleaseToken
    if (-not [string]::IsNullOrWhiteSpace($stored)) {
        return $stored
    }

    Write-Host "GitHub token was not found in WINSWEEP_GITHUB_TOKEN, GITHUB_TOKEN, or GH_TOKEN."
    Write-Host "Create a fine-grained token with repository Contents: Read and write, then paste it below."
    Write-Host "Tip: run save-github-token.ps1 once to avoid pasting the token every time."
    $secure = Read-Host "GitHub token (hidden)" -AsSecureString
    $plain = Get-PlainTextSecret -SecureValue $secure
    if ([string]::IsNullOrWhiteSpace($plain)) {
        throw "GitHub token is required to publish a release."
    }

    return $plain.Trim()
}

function Invoke-GitHubCurl {
    param(
        [ValidateSet("GET", "POST", "PATCH", "DELETE")]
        [string]$Method,
        [string]$Uri,
        [string]$AuthToken,
        [string]$ContentPath = "",
        [string]$ContentType = ""
    )

    if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
        throw "curl.exe was not found. Windows includes it by default; install curl or use a supported Windows version."
    }

    $responsePath = [IO.Path]::GetTempFileName()
    try {
        $curlArgs = @(
            "--silent",
            "--show-error",
            "--request", $Method,
            "--header", "Authorization: Bearer $AuthToken",
            "--header", "Accept: application/vnd.github+json",
            "--header", "X-GitHub-Api-Version: 2022-11-28",
            "--header", "User-Agent: WinSweepReleasePublisher",
            "--output", $responsePath,
            "--write-out", "%{http_code}",
            "--max-time", [string]$RequestTimeoutSeconds
        )

        if (-not [string]::IsNullOrWhiteSpace($ContentPath)) {
            if (-not (Test-Path -LiteralPath $ContentPath -PathType Leaf)) {
                throw "GitHub request content file was not found: $ContentPath"
            }

            $curlArgs += @(
                "--header", "Content-Type: $ContentType",
                "--data-binary", "@$ContentPath"
            )
        }

        $statusText = & curl.exe @curlArgs $Uri
        $exitCode = $LASTEXITCODE
        $responseText = [IO.File]::ReadAllText($responsePath, [Text.UTF8Encoding]::new($false))
        if ($exitCode -ne 0) {
            throw "GitHub API $Method $Uri failed: curl.exe exited with code $exitCode. $responseText"
        }

        [int]$statusCode = 0
        if (-not [int]::TryParse($statusText.Trim(), [ref]$statusCode)) {
            throw "GitHub API $Method $Uri did not return an HTTP status code."
        }

        return [pscustomobject]@{
            StatusCode = $statusCode
            BodyText   = $responseText
        }
    }
    finally {
        Remove-Item -LiteralPath $responsePath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-GitHubJson {
    param(
        [ValidateSet("GET", "POST", "PATCH", "DELETE")]
        [string]$Method,
        [string]$Uri,
        [string]$AuthToken,
        $Body = $null,
        [switch]$AllowNotFound
    )

    $bodyPath = ""
    try {
        if ($null -ne $Body) {
            $bodyPath = [IO.Path]::GetTempFileName()
            $json = $Body | ConvertTo-Json -Depth 12
            [IO.File]::WriteAllText($bodyPath, $json, [Text.UTF8Encoding]::new($false))
        }

        $response = Invoke-GitHubCurl `
            -Method $Method `
            -Uri $Uri `
            -AuthToken $AuthToken `
            -ContentPath $bodyPath `
            -ContentType "application/json"

        if ($AllowNotFound -and $response.StatusCode -eq 404) {
            return $null
        }

        if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
            throw "GitHub API $Method $Uri failed ($($response.StatusCode)) $($response.BodyText)"
        }

        if ([string]::IsNullOrWhiteSpace($response.BodyText)) {
            return $null
        }

        return $response.BodyText | ConvertFrom-Json
    }
    finally {
        if (-not [string]::IsNullOrWhiteSpace($bodyPath)) {
            Remove-Item -LiteralPath $bodyPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-GitHubUpload {
    param(
        [string]$Uri,
        [string]$AuthToken,
        [string]$FilePath
    )

    $response = Invoke-GitHubCurl `
        -Method "POST" `
        -Uri $Uri `
        -AuthToken $AuthToken `
        -ContentPath $FilePath `
        -ContentType "application/zip"

    if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
        throw "GitHub release asset upload failed ($($response.StatusCode)) $($response.BodyText)"
    }

    return $response.BodyText | ConvertFrom-Json
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

if ([string]::IsNullOrWhiteSpace($Repository) -or $Repository -notmatch '^[^/\s]+/[^/\s]+$') {
    throw "Repository should look like owner/name. Got: $Repository"
}

$tag = "v$Version"
$zipPath = Join-Path $root "dist\WinSweep-v$Version.zip"
$notesPath = Join-Path $root "release-notes.md"
$assetName = Split-Path -Leaf $zipPath

if ($SkipTagPush) {
    Write-Host "Note: -SkipTagPush is no longer needed. The GitHub Releases API creates or reuses the tag."
}

& $buildScript -Version $Version

if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
    throw "Release zip was not created: $zipPath"
}

@(
    "WinSweep $tag",
    "",
    "Скачайте $assetName, распакуйте архив и запустите setup-desktop-folder.bat или winsweep-menu.bat.",
    "",
    "Что нового:",
    "- отдельные переключатели кэшей Discord, Telegram, Spotify и других программ",
    "- исключения для папок, которые нельзя чистить",
    "- отдельные пороги свободного места для каждого диска",
    "- история изменения свободного места и анализ крупных папок",
    "- безопасная диагностика гибернации, точек восстановления и компонентов Windows"
) | Set-Content -LiteralPath $notesPath -Encoding UTF8

Write-Host ""
Write-Host "Release asset:"
Write-Host $zipPath
Write-Host ""

if ($DryRun) {
    Write-Host "Dry run only. No GitHub release was created."
    Write-Host "Would publish $tag to https://github.com/$Repository/releases using target $TargetCommitish."
    exit 0
}

$releaseToken = Get-ReleaseToken -ExplicitToken $Token
$apiRoot = "https://api.github.com/repos/$Repository"
$releaseByTagUri = "$apiRoot/releases/tags/$tag"
$release = Invoke-GitHubJson -Method GET -Uri $releaseByTagUri -AuthToken $releaseToken -AllowNotFound
$notes = Get-Content -LiteralPath $notesPath -Raw -Encoding UTF8

if ($release) {
    Write-Host "Release already exists: $tag"
    if ($UpdateExisting) {
        $release = Invoke-GitHubJson `
            -Method PATCH `
            -Uri "$apiRoot/releases/$($release.id)" `
            -AuthToken $releaseToken `
            -Body @{
                name       = "WinSweep $tag"
                body       = $notes
                draft      = [bool]$Draft
                prerelease = [bool]$Prerelease
            }
    }
    else {
        Write-Host "Keeping existing release title and notes. Use -UpdateExisting to change them."
    }
}
else {
    Write-Host "Creating release: $tag"
    $release = Invoke-GitHubJson `
        -Method POST `
        -Uri "$apiRoot/releases" `
        -AuthToken $releaseToken `
        -Body @{
            tag_name               = $tag
            target_commitish       = $TargetCommitish
            name                   = "WinSweep $tag"
            body                   = $notes
            draft                  = [bool]$Draft
            prerelease             = [bool]$Prerelease
            generate_release_notes = $false
        }
}

$assets = Invoke-GitHubJson -Method GET -Uri "$apiRoot/releases/$($release.id)/assets?per_page=100" -AuthToken $releaseToken
$assetAlreadyExists = $false
foreach ($asset in @($assets)) {
    if ($asset.name -eq $assetName) {
        if ($ReplaceAsset) {
            Write-Host "Replacing existing asset: $assetName"
            Invoke-GitHubJson -Method DELETE -Uri "$apiRoot/releases/assets/$($asset.id)" -AuthToken $releaseToken | Out-Null
        }
        else {
            $assetAlreadyExists = $true
            Write-Host "Asset already exists: $assetName"
        }
    }
}

$uploadedAsset = $null
if (-not $assetAlreadyExists -or $ReplaceAsset) {
    $encodedAssetName = [Uri]::EscapeDataString($assetName)
    $uploadUri = "https://uploads.github.com/repos/$Repository/releases/$($release.id)/assets?name=$encodedAssetName"
    $uploadedAsset = Invoke-GitHubUpload -Uri $uploadUri -AuthToken $releaseToken -FilePath $zipPath
}

Write-Host ""
Write-Host "Release published:"
Write-Host $release.html_url
if ($uploadedAsset) {
    Write-Host ""
    Write-Host "Asset:"
    Write-Host $uploadedAsset.browser_download_url
}
