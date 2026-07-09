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

## Local release publish

Use this when Actions are unavailable, or when you want to publish from your PC:

```powershell
gh auth login
.\publish-release.ps1 -Version 0.4.3
```

Requirements:

- Git for Windows
- GitHub CLI from https://cli.github.com/
- `gh auth login` completed for your GitHub account

What it does:

- builds `dist\WinSweep-v0.4.3.zip`;
- creates the local tag `v0.4.3` if missing;
- pushes the tag to `origin` if missing;
- creates or updates the GitHub Release asset.

Useful options:

```powershell
.\publish-release.ps1 -Version 0.4.3 -DryRun
.\publish-release.ps1 -Version 0.4.3 -Repository kappapr1der/winsweep
.\publish-release.ps1 -Version 0.4.3 -Prerelease
.\publish-release.ps1 -Version 0.4.3 -Draft
.\publish-release.ps1 -Version 0.4.3 -SkipTagPush
```
