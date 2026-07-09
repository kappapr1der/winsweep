# Publishing Releases

WinSweep supports two release paths.

## Automatic GitHub Actions release

Push a version tag:

```bash
git tag v0.4.3
git push origin v0.4.3
```

GitHub Actions will build `dist\WinSweep-v0.4.3.zip` and attach it to a new
GitHub Release.

This requires GitHub Actions to be enabled for the repository and the account to
be allowed to run Actions. If the run annotation says `The job was not started
because your account is locked due to a billing issue`, fix the billing lock on
GitHub first or use the local release path below.

## Local release publish without Actions

Use this when Actions are unavailable, or when you want to publish from your PC
without adding billing details to GitHub:

```powershell
$env:WINSWEEP_GITHUB_TOKEN = "paste_your_token_here"
.\publish-release.ps1 -Version 0.4.3
Remove-Item Env:\WINSWEEP_GITHUB_TOKEN
```

Requirements:

- a GitHub personal access token
- repository access to `kappapr1der/winsweep`
- repository permission `Contents: Read and write`

Recommended token setup:

1. Open GitHub `Settings`.
2. Open `Developer settings`.
3. Open `Personal access tokens`.
4. Create a fine-grained token.
5. Set repository access to `kappapr1der/winsweep`.
6. Set `Contents` to `Read and write`.

What it does:

- builds `dist\WinSweep-v0.4.3.zip`;
- creates or reuses the GitHub tag `v0.4.3`;
- creates or updates the GitHub Release asset.

Useful options:

```powershell
.\publish-release.ps1 -Version 0.4.3 -DryRun
.\publish-release.ps1 -Version 0.4.3 -Repository kappapr1der/winsweep
.\publish-release.ps1 -Version 0.4.3 -Prerelease
.\publish-release.ps1 -Version 0.4.3 -Draft
.\publish-release.ps1 -Version 0.4.3 -TargetCommitish main
```

If `WINSWEEP_GITHUB_TOKEN`, `GITHUB_TOKEN`, or `GH_TOKEN` is not set, the script
will ask for the token with hidden input.
