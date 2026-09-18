<#
.SYNOPSIS
    Builds, signs, packages, and publishes a GitHub Release for the
    project's CURRENT version (project.godot's application/config/version).

.DESCRIPTION
    Exports the named preset (export_presets.cfg -- "Windows Desktop" by
    default, the only one currently configured), signs the resulting
    executable with your private signing key (tools/sign_build.gd -- see
    docs/licensing.md), zips exactly the files a customer needs to run it
    (the .exe and its .sig sidecar, plus a license.txt when one is
    configured and still valid -- nothing else; see
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
    Falls back to the ALEPH_ALPHA_SIGNING_KEY environment variable if
    omitted, so you can set that once in your own PowerShell profile ($PROFILE
    -- lives under your user profile, never committed to this repo) instead
    of retyping the path every release. Deliberately NO hardcoded default
    and NO filesystem auto-discovery in the script itself, though -- see
    docs/licensing.md: this file must never live inside this repo or its
    export output, only somewhere that never touches git (a password
    manager attachment or an encrypted offline drive is docs/licensing.md's
    own recommendation; a plain folder outside any repo, as long as you
    control that machine, is the accepted minimum). A script committed to
    this repo hardcoding your real key's literal filesystem path would
    permanently document exactly where to look for it to anyone who ever
    gets read access to this source -- that's what the environment-variable
    indirection avoids: the PATH lives only in your own local profile, never
    in tracked source.

.PARAMETER LicensePath
    Optional. Path to a license.txt holding ONE signed serial code, to be
    bundled into the release package so whoever downloads it can run the
    game without pasting a key. Falls back to the
    ALEPH_ALPHA_RELEASE_LICENSE environment variable, the same
    set-it-once-in-your-profile shape -KeyPath uses. Omit both and the
    package is built exactly as it always was, with no license in it.

    The code is verified BEFORE the export runs, by
    tools/verify_release_license.gd, against the same key ring the shipped
    game itself uses -- so a serial this bundles is one the game will
    accept. A license that is expired, malformed, signed by an unknown
    key, or is the owner/developer key (never for distribution -- see
    docs/licensing.md's issued-serials table) STOPS the release rather
    than quietly publishing a build without it: you asked for a licensed
    package, and a silently unlicensed one is the worse surprise.

    Deliberately NO auto-discovery, for the same reason -KeyPath has none
    and a stronger one besides: the export/dist folder routinely holds the
    developer's OWN testing license.txt, which is exactly the file that
    must never ship.

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
    # With $env:ALEPH_ALPHA_SIGNING_KEY already set (see -KeyPath above):
    .\tools\release\build_release.ps1 -DryRun
#>
param(
    [string]$KeyPath,
    [string]$LicensePath,
    [string]$GodotPath = "$env:USERPROFILE\Godot\Godot_v4.7.2-stable_win64_console.exe",
    [string]$Preset = "Windows Desktop",
    [switch]$DryRun
)

. "$PSScriptRoot\ReleaseCommon.ps1"

if ([string]::IsNullOrWhiteSpace($KeyPath)) {
    $KeyPath = $env:ALEPH_ALPHA_SIGNING_KEY
}
if ([string]::IsNullOrWhiteSpace($LicensePath)) {
    $LicensePath = $env:ALEPH_ALPHA_RELEASE_LICENSE
}
if ([string]::IsNullOrWhiteSpace($KeyPath)) {
    throw "No signing key given. Pass -KeyPath <path-to-your-private-key.pem>, or set it once via `$env:ALEPH_ALPHA_SIGNING_KEY in your PowerShell profile (`$PROFILE) -- see tools/release/README.md."
}

function Invoke-Checked {
    param([string]$Description, [scriptblock]$Action)
    Write-Host "-> $Description" -ForegroundColor Cyan
    Invoke-NativeChecked -Description $Description -Action $Action
}

# Runs a native command and judges it by its EXIT CODE alone. Windows
# PowerShell 5.1 wraps every stderr line a native program prints in an
# ErrorRecord, and under $ErrorActionPreference = 'Stop' (or a caller
# merging the error stream) that record terminates the script even when the
# program exited 0. Three real rebuilds of v0.0.1 died this way after the
# real work was done: git's "Everything up-to-date" on push, and Godot's
# harmless "CompanionServer: could not bind 127.0.0.1:8731" warning during
# signing. Both are stderr chatter with exit code 0.
function Invoke-NativeChecked {
    param([string]$Description, [scriptblock]$Action)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $global:LASTEXITCODE = 0
    try {
        & $Action 2>&1 | ForEach-Object { Write-Host ("$_") }
    }
    finally {
        $ErrorActionPreference = $previous
    }
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed (exit code $LASTEXITCODE)"
    }
}

# Declared before the try so the finally block can clean it up whether or
# not a license was ever staged.
$stagingDir = $null

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

    # -- License (verified up front, before the long export) ----------------
    #
    # Checked here rather than at packaging time on purpose: a bad serial
    # should cost you a second, not a full export, sign, tag and publish
    # cycle. The check itself is read-only, so it runs under -DryRun too --
    # that is exactly the question a dry run is for.
    $licenseToShip = $null
    if ([string]::IsNullOrWhiteSpace($LicensePath)) {
        Write-Host "License       : none configured -- packaging without one"
    }
    else {
        if (-not (Test-Path -LiteralPath $LicensePath)) {
            throw "License file not found at $LicensePath -- pass -LicensePath <path>, set `$env:ALEPH_ALPHA_RELEASE_LICENSE, or unset it to package without a license."
        }
        # Guard the SOURCE path as well as the staged copy below: a
        # -LicensePath accidentally pointed at a .pem must never get as far
        # as the zip.
        Assert-NoPrivateKeyAmong -Paths @($LicensePath)

        Write-Host "-> Verifying the license is still valid" -ForegroundColor Cyan
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $global:LASTEXITCODE = 0
        & $GodotPath --headless --path $Script:RepoRoot -s tools/verify_release_license.gd -- --file $LicensePath 2>&1 |
            ForEach-Object { Write-Host ("   $_") }
        $licenseVerdict = $LASTEXITCODE
        $ErrorActionPreference = $previousErrorActionPreference

        if ($licenseVerdict -ne 0) {
            throw "The license at $LicensePath cannot be bundled (see the line above). Fix or replace it, or unset -LicensePath/`$env:ALEPH_ALPHA_RELEASE_LICENSE to publish without one -- refusing to publish a release that silently lacks the license you asked for."
        }
        $licenseToShip = $LicensePath
    }

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
    # a customer-facing package. A license only ever reaches this list via
    # -LicensePath, verified in preflight -- never by being found lying in
    # the export folder, which is where the developer's own copy lives.
    $filesToShip = @($exportPath, $sigPath)
    if ($null -ne $licenseToShip) {
        # Staged under a temp directory rather than copied into the export
        # folder: the zip takes each file's LEAF name, the game looks for
        # exactly "license.txt" next to the executable
        # (LicenseStore.default_candidate_paths), and writing that name into
        # the export folder would clobber whatever license the developer
        # running this has there for their own testing.
        $stagingDir = Join-Path ([System.IO.Path]::GetTempPath()) "aleph-alpha-release-$tag"
        if (Test-Path -LiteralPath $stagingDir) { Remove-Item -LiteralPath $stagingDir -Recurse -Force }
        New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
        $stagedLicense = Join-Path $stagingDir "license.txt"
        Copy-Item -LiteralPath $licenseToShip -Destination $stagedLicense -Force
        $filesToShip += $stagedLicense
        Write-Host "Bundling license.txt from $licenseToShip"
    }
    Assert-NoPrivateKeyAmong -Paths $filesToShip
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath }
    Compress-Archive -Path $filesToShip -DestinationPath $zipPath
    Write-Host "Packaged: $zipPath ($((Get-Item -LiteralPath $zipPath).Length) bytes)"

    # -- Git tag ------------------------------------------------------------

    # Push the current branch first, so the commit the tag is about to
    # point at is actually reachable on origin -- otherwise a customer (or
    # GitHub's own UI) following the tag to "compare" or browse history
    # could land on a commit that only ever existed locally.
    Invoke-NativeChecked "Pushing the current branch" { git push }

    $tagExistsLocally = git tag --list $tag
    if (-not $tagExistsLocally) {
        Invoke-NativeChecked "Tagging $tag" { git tag -a $tag -m "Release $tag" }
        Invoke-NativeChecked "Pushing tag $tag" { git push origin $tag }
        Write-Host "Created and pushed tag $tag"
    }
    else {
        Write-Host "Tag $tag already exists -- reusing it (this is a rebuild of the same version)."
    }

    # -- Publish to GitHub Releases ------------------------------------------

    # $ErrorActionPreference = 'Stop' (see ReleaseCommon.ps1) turns gh's own
    # "release not found" stderr line into a terminating error even though
    # a non-zero exit here is the EXPECTED, handled outcome (no release
    # yet) -- the same stderr-vs-exit-code trap Invoke-NativeChecked's own
    # doc comment already covers for other commands in this file, just not
    # previously applied to this one. Scoped to just this check with the
    # same temporary-'Continue' pattern, not a second Invoke-NativeChecked
    # wrapper, since the exit code here is a real branch, not a failure.
    $releaseExists = $true
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $global:LASTEXITCODE = 0
    & gh release view $tag *> $null
    if ($LASTEXITCODE -ne 0) { $releaseExists = $false }
    $ErrorActionPreference = $previousErrorActionPreference

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
    if ($stagingDir -and (Test-Path -LiteralPath $stagingDir)) {
        Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Pop-Location
}
