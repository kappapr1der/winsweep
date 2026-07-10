[CmdletBinding()]
param(
    [string]$Version = "",
    [string]$Repository = "kappapr1der/winsweep",
    [string]$Token = "",
    [string]$TargetCommitish = "main",
    [switch]$Prerelease,
    [switch]$Draft,
    [switch]$SkipTagPush,
    [ValidateRange(10, 300)]
    [int]$RequestTimeoutSeconds = 30,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Net.Http

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

function Get-GitHubErrorText {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)

    $response = $ErrorRecord.Exception.Response
    $status = ""
    $body = ""

    if ($response) {
        try {
            $status = " ($([int]$response.StatusCode) $($response.StatusDescription))"
        }
        catch {
            $status = ""
        }

        try {
            $stream = $response.GetResponseStream()
            if ($stream) {
                $reader = New-Object IO.StreamReader($stream)
                $body = $reader.ReadToEnd()
            }
        }
        catch {
            $body = ""
        }
    }

    if ([string]::IsNullOrWhiteSpace($body)) {
        $body = $ErrorRecord.Exception.Message
    }

    return "$status $body"
}

function New-GitHubHttpClient {
    param([string]$AuthToken)

    $client = [System.Net.Http.HttpClient]::new()
    $client.Timeout = [TimeSpan]::FromSeconds($RequestTimeoutSeconds)
    $client.DefaultRequestHeaders.Accept.Add(
        [System.Net.Http.Headers.MediaTypeWithQualityHeaderValue]::new("application/vnd.github+json")
    )
    $client.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $AuthToken)
    $client.DefaultRequestHeaders.Add("X-GitHub-Api-Version", "2022-11-28")
    $client.DefaultRequestHeaders.UserAgent.ParseAdd("WinSweepReleasePublisher")
    return $client
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

    $client = New-GitHubHttpClient -AuthToken $AuthToken
    $request = $null
    $response = $null
    try {
        $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method), $Uri)
        if ($null -ne $Body) {
            $json = $Body | ConvertTo-Json -Depth 12
            $request.Content = [System.Net.Http.StringContent]::new($json, [Text.Encoding]::UTF8, "application/json")
        }

        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        $responseText = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $status = [int]$response.StatusCode

        if ($AllowNotFound -and $status -eq 404) {
            return $null
        }

        if (-not $response.IsSuccessStatusCode) {
            throw "GitHub API $Method $Uri failed ($status $($response.ReasonPhrase)) $responseText"
        }

        if ([string]::IsNullOrWhiteSpace($responseText)) {
            return $null
        }

        return $responseText | ConvertFrom-Json
    }
    finally {
        if ($response) { $response.Dispose() }
        if ($request) { $request.Dispose() }
        $client.Dispose()
    }
}

function Invoke-GitHubUpload {
    param(
        [string]$Uri,
        [string]$AuthToken,
        [string]$FilePath
    )

    $client = New-GitHubHttpClient -AuthToken $AuthToken
    $request = $null
    $response = $null
    $stream = $null
    try {
        $stream = [IO.File]::OpenRead($FilePath)
        $content = [System.Net.Http.StreamContent]::new($stream)
        $content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new("application/zip")
        $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, $Uri)
        $request.Content = $content
        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        $responseText = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()

        if (-not $response.IsSuccessStatusCode) {
            throw "GitHub release asset upload failed ($([int]$response.StatusCode) $($response.ReasonPhrase)) $responseText"
        }

        return $responseText | ConvertFrom-Json
    }
    finally {
        if ($response) { $response.Dispose() }
        if ($request) { $request.Dispose() }
        if ($stream) { $stream.Dispose() }
        $client.Dispose()
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
    "Download $assetName, extract it, then run setup-desktop-folder.bat or winsweep-menu.bat.",
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
foreach ($asset in @($assets)) {
    if ($asset.name -eq $assetName) {
        Write-Host "Replacing existing asset: $assetName"
        Invoke-GitHubJson -Method DELETE -Uri "$apiRoot/releases/assets/$($asset.id)" -AuthToken $releaseToken | Out-Null
    }
}

$encodedAssetName = [Uri]::EscapeDataString($assetName)
$uploadUri = "https://uploads.github.com/repos/$Repository/releases/$($release.id)/assets?name=$encodedAssetName"
$uploadedAsset = Invoke-GitHubUpload -Uri $uploadUri -AuthToken $releaseToken -FilePath $zipPath

Write-Host ""
Write-Host "Release published:"
Write-Host $release.html_url
Write-Host ""
Write-Host "Asset:"
Write-Host $uploadedAsset.browser_download_url
