<#
.SYNOPSIS
    Builds, signs, packages, and publishes a GitHub Release for the
    project's CURRENT version (project.godot's application/config/version).

.DESCRIPTION
    Exports the named preset (export_presets.cfg -- "Windows Desktop" by
    default, the only one currently configured), signs the resulting
    executable with your private signing key (tools/sign_build.gd -- see
    docs/licensing.md), zips exactly the two files a customer needs to run
    it (the .exe and its .sig sidecar -- nothing else; see
    Assert-NoPrivateKeyAmong), then creates -- or, if a release for this
    version already exists, re-uploads the asset to -- the matching vX.Y.Z
    GitHub Release.

    Re-running this with NO version bump in between re-builds and
    re-publishes the SAME release: the intended way to fix a bad packaging
    run without any version churn. Run tools\release\bump_version.ps1
    first if you actually want a NEW version released.

    Release/ops tooling, not game code -- same "developer tooling, not part
    of this project's TDD-covered game code" status tools/sign_build.gd and
    tools/generate_keypair.gd already carry in their own doc comments.

.PARAMETER KeyPath
    Path to your FULL private signing key (see tools/generate_keypair.gd).
    Required, with deliberately NO default and NO auto-discovery -- see
    docs/licensing.md: this file must never live inside this repo or its
    export output, only somewhere that never touches git (a password
    manager attachment, an encrypted offline drive).

.PARAMETER GodotPath
    Path to the Godot editor binary. Defaults to this machine's known
    install location -- override with -GodotPath on a different machine.

.PARAMETER Preset
    Which export_presets.cfg preset to build. Defaults to "Windows
    Desktop", the only preset currently configured in this project.

.PARAMETER DryRun
    Runs every read-only step (version + export-path resolution, preflight
    checks) and prints exactly what WOULD happen, but skips the actual
    export, signing, packaging, git tag/push, and GitHub release calls.
    Use this to sanity-check before a real publish.

.EXAMPLE
    .\tools\release\build_release.ps1 -KeyPath D:\secure\aleph-alpha-signing-key.pem

.EXAMPLE
    .\tools\release\build_release.ps1 -KeyPath D:\secure\key.pem -DryRun
#>
param(
    [Parameter(Mandatory = $true)][string]$KeyPath,
    [string]$GodotPath = "$env:USERPROFILE\Godot\Godot_v4.7.2-stable_win64_console.exe",
    [string]$Preset = "Windows Desktop",
    [switch]$DryRun
)

. "$PSScriptRoot\ReleaseCommon.ps1"

function Invoke-Checked {
    param([string]$Description, [scriptblock]$Action)
    Write-Host "-> $Description" -ForegroundColor Cyan
    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed (exit code $LASTEXITCODE)"
    }
}

Push-Location $Script:RepoRoot
try {
    # -- Preflight ------------------------------------------------------------

    if (-not (Test-Path -LiteralPath $KeyPath)) {
        throw "Private key not found at $KeyPath"
    }
    if (-not (Test-Path -LiteralPath $GodotPath)) {
        throw "Godot binary not found at $GodotPath -- pass -GodotPath explicitly."
    }
    Assert-GhCli

    $version = Get-ProjectVersion
    if ($null -eq $version) {
        throw "No config/version in project.godot yet -- run tools\release\bump_version.ps1 once first."
    }
    $tag = "v$version"
    Write-Host "Releasing version $version (tag $tag)" -ForegroundColor Green

    $exportPath = Get-ExportPathForPreset -PresetName $Preset
    $exportDir = Split-Path -Parent $exportPath
    $sigPath = "$exportPath.sig"
    $zipName = "AlephAlpha-$tag-windows.zip"
    $zipPath = Join-Path $Script:RepoRoot $zipName

    Write-Host "Export target : $exportPath"
    Write-Host "Package       : $zipPath"

    if ($DryRun) {
        Write-Host ""
        Write-Host "DRY RUN -- stopping before export/sign/package/publish." -ForegroundColor Yellow
        return
    }

    if (-not (Test-Path -LiteralPath $exportDir)) {
        New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
    }

    # -- Export -----------------------------------------------------------------

    Invoke-Checked "Exporting ($Preset)" {
        & $GodotPath --headless --path $Script:RepoRoot --export-release $Preset
    }
    if (-not (Test-Path -LiteralPath $exportPath)) {
        throw "Export reported success but $exportPath does not exist -- check export_presets.cfg's export_path for preset '$Preset'."
    }

    # -- Sign -------------------------------------------------------------------

    if (Test-Path -LiteralPath $sigPath) { Remove-Item -LiteralPath $sigPath }
    Invoke-Checked "Signing the build" {
        & $GodotPath --headless --path $Script:RepoRoot -s tools/sign_build.gd -- --key $KeyPath --file $exportPath
    }
    if (-not (Test-Path -LiteralPath $sigPath)) {
        throw "Signing reported success but $sigPath does not exist."
    }

    # -- Package ------------------------------------------------------------

    # An explicit allowlist of exactly what a customer needs -- never a
    # whole-directory zip. The export/dist folder can also hold a locally
    # entered license.txt or (for local SelfIntegrity auto-sign testing
    # only -- see docs/licensing.md) a private_key.pem; neither belongs in
    # a customer-facing package.
    $filesToShip = @($exportPath, $sigPath)
    Assert-NoPrivateKeyAmong -Paths $filesToShip
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath }
    Compress-Archive -Path $filesToShip -DestinationPath $zipPath
    Write-Host "Packaged: $zipPath ($((Get-Item -LiteralPath $zipPath).Length) bytes)"

    # -- Git tag ------------------------------------------------------------

    # Push the current branch first, so the commit the tag is about to
    # point at is actually reachable on origin -- otherwise a customer (or
    # GitHub's own UI) following the tag to "compare" or browse history
    # could land on a commit that only ever existed locally.
    git push

    $tagExistsLocally = git tag --list $tag
    if (-not $tagExistsLocally) {
        git tag -a $tag -m "Release $tag"
        git push origin $tag
        Write-Host "Created and pushed tag $tag"
    }
    else {
        Write-Host "Tag $tag already exists -- reusing it (this is a rebuild of the same version)."
    }

    # -- Publish to GitHub Releases ------------------------------------------

    $releaseExists = $true
    & gh release view $tag *> $null
    if ($LASTEXITCODE -ne 0) { $releaseExists = $false }

    if ($releaseExists) {
        Invoke-Checked "Updating existing GitHub release $tag" {
            & gh release upload $tag $zipPath --clobber
        }
    }
    else {
        Invoke-Checked "Creating GitHub release $tag" {
            & gh release create $tag $zipPath --title $tag --generate-notes
        }
    }

    $url = & gh release view $tag --json url --jq ".url"
    Write-Host ""
    Write-Host "Released $tag -> $url" -ForegroundColor Green
}
finally {
    Pop-Location
}
