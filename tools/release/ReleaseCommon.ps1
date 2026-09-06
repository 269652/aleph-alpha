# Shared helpers for bump_version.ps1 / build_release.ps1. Dot-source this
# from either script (". "$PSScriptRoot\ReleaseCommon.ps1"") rather than
# duplicating the project.godot / export_presets.cfg parsing in both --
# same "one source of truth, no drift" reasoning the rest of this codebase
# already follows everywhere else (e.g. this script reads export_path
# straight out of export_presets.cfg rather than hardcoding a second copy
# of it).
#
# Release/ops tooling, not game code -- same "developer tooling, not part
# of this project's TDD-covered game code" status tools/sign_build.gd and
# tools/generate_keypair.gd already carry in their own doc comments (see
# docs/licensing.md). Not unit-tested for the same reason those aren't.

$ErrorActionPreference = 'Stop'

# Repo root: two levels up from this file's own location
# (tools/release/ReleaseCommon.ps1 -> tools/release -> tools -> repo root),
# resolved from the script's own path rather than the caller's current
# directory, so these scripts behave the same whether run from the repo
# root or from anywhere else.
$Script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Script:ProjectGodotPath = Join-Path $Script:RepoRoot 'project.godot'
$Script:ExportPresetsPath = Join-Path $Script:RepoRoot 'export_presets.cfg'

function Get-ProjectVersion {
    <#
    .SYNOPSIS
    Reads application/config/version out of project.godot -- Godot's own
    canonical place for a project's version (Project Settings > Application
    > Config > Version maps directly to this key). Returns $null if the
    key doesn't exist yet.
    #>
    if (-not (Test-Path -LiteralPath $Script:ProjectGodotPath)) {
        throw "project.godot not found at $Script:ProjectGodotPath"
    }
    $content = Get-Content -Raw -LiteralPath $Script:ProjectGodotPath
    if ($content -match '(?m)^config/version="([^"]*)"') {
        return $Matches[1]
    }
    return $null
}

function Set-ProjectVersion {
    <#
    .SYNOPSIS
    Writes a new application/config/version into project.godot in place --
    a targeted line replace (or, the first time, an insert right after
    config/name=), never a full-file rewrite, so every other setting in the
    file survives byte-for-byte and this shows up as a one-line git diff.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$NewVersion
    )
    $content = Get-Content -Raw -LiteralPath $Script:ProjectGodotPath
    if ($content -match '(?m)^config/version="[^"]*"') {
        $updated = $content -replace '(?m)^config/version="[^"]*"', "config/version=`"$NewVersion`""
    }
    elseif ($content -match '(?m)^(config/name="[^"]*")\r?\n') {
        $updated = $content -replace '(?m)^(config/name="[^"]*")\r?\n', "`$1`r`nconfig/version=`"$NewVersion`"`r`n"
    }
    else {
        throw "Could not find config/name= in project.godot to anchor a new config/version= line next to -- add one manually once, then re-run."
    }
    # project.godot ships CRLF in this repo (confirmed directly) -- write it
    # back the same way rather than letting a PowerShell cmdlet normalize
    # line endings and turn this into a whole-file diff.
    [System.IO.File]::WriteAllText($Script:ProjectGodotPath, $updated)
}

function Test-SemVer {
    param([Parameter(Mandatory = $true)][string]$Version)
    return $Version -match '^\d+\.\d+\.\d+$'
}

function Get-BumpedVersion {
    <#
    .SYNOPSIS
    Computes the next version for a given semver part (major/minor/patch)
    -- the standard "every part below the bumped one resets to zero" rule.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$CurrentVersion,
        [Parameter(Mandatory = $true)][ValidateSet('major', 'minor', 'patch')][string]$Part
    )
    if (-not (Test-SemVer $CurrentVersion)) {
        throw "'$CurrentVersion' is not a plain X.Y.Z semver -- fix project.godot's config/version by hand once, then re-run."
    }
    $parts = $CurrentVersion.Split('.') | ForEach-Object { [int]$_ }
    switch ($Part) {
        'major' { return "$($parts[0] + 1).0.0" }
        'minor' { return "$($parts[0]).$($parts[1] + 1).0" }
        'patch' { return "$($parts[0]).$($parts[1]).$($parts[2] + 1)" }
    }
}

function Get-ExportPathForPreset {
    <#
    .SYNOPSIS
    Reads export_path out of export_presets.cfg for the named preset -- the
    single source of truth for where a build lands, so this can never drift
    from what the Godot editor itself would export to. export_presets.cfg
    is gitignored (a local/per-machine file), so this always reads whatever
    the machine actually running the release is really configured to
    produce.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$PresetName
    )
    if (-not (Test-Path -LiteralPath $Script:ExportPresetsPath)) {
        throw "export_presets.cfg not found at $Script:ExportPresetsPath -- open the project in the Godot editor once and configure an export preset (Project > Export) before running this."
    }
    $lines = Get-Content -LiteralPath $Script:ExportPresetsPath
    $inTargetPreset = $false
    foreach ($line in $lines) {
        if ($line -match '^\[preset\.\d+\]$') { $inTargetPreset = $false }
        if ($line -match '^name="([^"]*)"' -and $Matches[1] -eq $PresetName) { $inTargetPreset = $true }
        if ($inTargetPreset -and $line -match '^export_path="([^"]*)"') {
            # export_path is stored relative to the repo root (the same way
            # the Godot editor itself resolves it) -- Resolve-Path needs an
            # existing target, so build the absolute path by hand instead;
            # the parent directory is created later if it doesn't exist yet.
            return [System.IO.Path]::GetFullPath((Join-Path $Script:RepoRoot $Matches[1]))
        }
    }
    throw "No preset named '$PresetName' with an export_path found in export_presets.cfg"
}

function Assert-GhCli {
    <#
    .SYNOPSIS
    Fails fast with an actionable message if the GitHub CLI isn't installed
    or isn't authenticated, rather than letting a later `gh` call fail with
    a confusing error deep into the release process.
    #>
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "GitHub CLI ('gh') not found on PATH. Install it from https://cli.github.com/ and run 'gh auth login' once, then re-run this script."
    }
    & gh auth status *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub CLI is installed but not authenticated. Run 'gh auth login' once, then re-run this script."
    }
}

function Assert-NoPrivateKeyAmong {
    <#
    .SYNOPSIS
    Defense in depth: even though the packaging step only ever zips an
    explicit allowlist of files (never a whole directory), refuse to
    proceed if anything that looks like a private key would end up in the
    package -- see docs/licensing.md. Shipping this key to even one
    customer permanently burns it: anyone who has it can mint valid serials
    and re-sign a tampered build as genuine, forever.
    #>
    param([Parameter(Mandatory = $true)][string[]]$Paths)
    foreach ($path in $Paths) {
        $name = Split-Path -Leaf $path
        if ($name -match '\.pem$' -or $name -match 'private_key') {
            throw "REFUSING to package '$path' -- it looks like a private key. This must never ship. Aborting."
        }
    }
}
