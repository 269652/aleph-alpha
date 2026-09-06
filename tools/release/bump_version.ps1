<#
.SYNOPSIS
    Bumps the project's semver (project.godot's application/config/version)
    -- major, minor, or patch -- commits it, and (by default) pushes.

.DESCRIPTION
    Run this BEFORE build_release.ps1 whenever you want the NEXT release to
    carry a new version number. Skip it entirely to re-run build_release.ps1
    against the CURRENT version instead -- e.g. to re-export/re-sign/
    re-publish the same release after fixing a packaging problem, with no
    version churn.

    Release/ops tooling, not game code -- same "developer tooling, not part
    of this project's TDD-covered game code" status tools/sign_build.gd and
    tools/generate_keypair.gd already carry in their own doc comments.

.PARAMETER Part
    Which part of X.Y.Z to bump. Defaults to 'patch'.

.PARAMETER Version
    Set an exact version instead of bumping a part (e.g. for the very first
    release, or to correct a mistake). Mutually exclusive with -Part.

.PARAMETER NoPush
    Commit the bump locally but don't push it. Off by default -- this
    repo's own convention (CLAUDE.md: "commit every sound change set...
    push after every commit") treats a version bump as exactly that kind of
    change.

.EXAMPLE
    .\tools\release\bump_version.ps1
    Bumps the patch version (0.1.0 -> 0.1.1), commits, pushes.

.EXAMPLE
    .\tools\release\bump_version.ps1 -Part minor
    0.1.4 -> 0.2.0

.EXAMPLE
    .\tools\release\bump_version.ps1 -Version 1.0.0
    Sets the version explicitly, e.g. for the first tagged release.
#>
[CmdletBinding(DefaultParameterSetName = 'Part')]
param(
    [Parameter(ParameterSetName = 'Part')]
    [ValidateSet('major', 'minor', 'patch')]
    [string]$Part = 'patch',

    [Parameter(ParameterSetName = 'Explicit', Mandatory = $true)]
    [string]$Version,

    [switch]$NoPush
)

. "$PSScriptRoot\ReleaseCommon.ps1"

Push-Location $Script:RepoRoot
try {
    $currentBranch = (git rev-parse --abbrev-ref HEAD).Trim()
    if ($currentBranch -ne 'main') {
        Write-Warning "Current branch is '$currentBranch', not 'main'. A version bump usually belongs on main, where releases are cut from."
        $confirm = Read-Host "Continue bumping on '$currentBranch' anyway? [y/N]"
        if ($confirm -notmatch '^[Yy]') {
            Write-Host "Aborted."
            exit 1
        }
    }

    $dirty = git status --porcelain -- project.godot
    if ($dirty) {
        throw "project.godot already has uncommitted changes -- commit or stash those first, so this bump's own commit contains only the version change."
    }

    $current = Get-ProjectVersion
    if ($null -eq $current) {
        Write-Host "No config/version found in project.godot yet -- seeding it."
        $current = '0.0.0'
    }

    if ($PSCmdlet.ParameterSetName -eq 'Explicit') {
        if (-not (Test-SemVer $Version)) {
            throw "-Version must be plain X.Y.Z semver (got '$Version')."
        }
        $new = $Version
    }
    else {
        $new = Get-BumpedVersion -CurrentVersion $current -Part $Part
    }

    if ($new -eq $current) {
        throw "New version ($new) is the same as the current version ($current) -- nothing to bump."
    }

    Write-Host "Bumping version: $current -> $new" -ForegroundColor Green
    Set-ProjectVersion -NewVersion $new

    git add -- project.godot
    git commit -m "chore: bump version to $new"

    if ($NoPush) {
        Write-Host "Committed locally (not pushed -- run 'git push' manually when ready)."
    }
    else {
        git push
        Write-Host "Pushed."
    }

    Write-Host ""
    Write-Host "Next: .\tools\release\build_release.ps1 -KeyPath <path-to-your-private-key.pem>" -ForegroundColor Cyan
}
finally {
    Pop-Location
}
