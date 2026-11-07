#requires -Version 5.1
<#
    GSV.Vault.psm1
    Snapshot backup + restore engine for GameSaveVault.
#>

$script:GSVVersion = '1.0.0'
$script:Root = Split-Path -Parent $PSScriptRoot

# Vault depends on the discovery helpers in GSV.Core.  Import it when the
# caller imported only this module (tests / direct use).
if (-not (Get-Command Get-GSVTokenTable -ErrorAction SilentlyContinue)) {
    $coreModule = Join-Path $PSScriptRoot 'GSV.Core.psm1'
    if (Test-Path -LiteralPath $coreModule) { Import-Module $coreModule -Force }
}

#region ---------------------------------------------------------------- copy helpers

function Invoke-GSVCopyTree {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [string[]]$ExcludeDirs = @(),
        [string[]]$ExcludeFiles = @()
    )

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    $robocopy = Get-Command robocopy.exe -ErrorAction SilentlyContinue
    if (-not $robocopy) {
        Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force -ErrorAction Stop
        return
    }

    $args = @(
        $Source, $Destination, '/E', '/R:1', '/W:1',
        '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/COPY:DAT', '/DCOPY:DAT'
    )
    if ($ExcludeDirs.Count -gt 0)  { $args += '/XD'; $args += $ExcludeDirs }
    if ($ExcludeFiles.Count -gt 0) { $args += '/XF'; $args += $ExcludeFiles }

    $null = & robocopy @args 2>&1
    $code = $LASTEXITCODE
    # Robocopy: 0-7 = success (bits mean files copied/extras/etc), >=8 = failure.
    if ($code -ge 8) {
        throw "robocopy failed with exit code $code while copying '$Source'"
    }
}

function Get-GSVManifestFileList {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$HashFiles
    )
    $list = New-Object System.Collections.Generic.List[object]

    if (-not (Test-Path -LiteralPath $Path)) { return @() }

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $fi = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
        if ($fi) {
            $item = [ordered]@{
                Path         = $fi.Name
                Size         = [int64]$fi.Length
                LastWriteUtc = $fi.LastWriteTimeUtc.ToString('o')
            }
            if ($HashFiles) {
                try { $item.Sha256 = (Get-FileHash -LiteralPath $fi.FullName -Algorithm SHA256).Hash } catch { }
            }
            $list.Add([pscustomobject]$item)
        }
        return $list.ToArray()
    }

    try {
        foreach ($f in [System.IO.Directory]::EnumerateFiles($Path, '*', [System.IO.SearchOption]::AllDirectories)) {
            try {
                $fi = New-Object System.IO.FileInfo($f)
                $rel = $fi.FullName.Substring($Path.TrimEnd('\').Length).TrimStart('\')
                $item = [ordered]@{
                    Path         = $rel
                    Size         = [int64]$fi.Length
                    LastWriteUtc = $fi.LastWriteTimeUtc.ToString('o')
                }
                if ($HashFiles) {
                    try { $item.Sha256 = (Get-FileHash -LiteralPath $fi.FullName -Algorithm SHA256).Hash } catch { }
                }
                $list.Add([pscustomobject]$item)
            } catch { }
        }
    } catch { }
    return $list.ToArray()
}

#endregion

#region ---------------------------------------------------------------- snapshot creation

function New-GSVSnapshot {
    param(
        [Parameter(Mandatory)][object[]]$Locations,
        [Parameter(Mandatory)][string]$BackupRoot,
        [string]$Label = 'manual',
        [switch]$HashFiles,
        [switch]$DryRun,
        [string]$LogFile
    )

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $safeLabel = ($Label -replace '[^A-Za-z0-9_-]', '_')
    if ($safeLabel.Length -gt 30) { $safeLabel = $safeLabel.Substring(0, 30) }
    if (-not $safeLabel) { $safeLabel = 'snapshot' }

    $snapDir = Join-Path $BackupRoot ("snapshots\{0}_{1}" -f $stamp, $safeLabel)
    $payloadRoot = Join-Path $snapDir 'payload'

    $entries = New-Object System.Collections.Generic.List[object]
    $errors = New-Object System.Collections.Generic.List[string]
    $totalBytes = [int64]0
    $totalFiles = 0
    $index = 0

    $settings = Get-GSVSettings
    $excludeDirs = @($settings.ExcludeNames)
    $excludeFiles = @($settings.ExcludeFiles)

    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $payloadRoot -Force | Out-Null
    }

    foreach ($loc in $Locations) {
        $index++
        $display = if ($loc.Kind -eq 'Registry') { $loc.RegistryKey } else { $loc.ResolvedPath }

        if ($loc.Kind -eq 'Registry') {
            if ($DryRun) {
                Write-GSVLog -Level Info -Message "[dry-run] registry  $display"
                continue
            }
            try {
                $regDir = Join-Path $payloadRoot ("{0:D4}" -f $index)
                New-Item -ItemType Directory -Path $regDir -Force | Out-Null
                $regFile = Join-Path $regDir 'registry.reg'
                $null = & reg.exe export "$($loc.RegistryKey)" "$regFile" /y 2>&1
                if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $regFile)) {
                    throw "reg.exe export failed (exit $LASTEXITCODE)"
                }
                $fi = Get-Item -LiteralPath $regFile
                $entries.Add([pscustomobject]@{
                    GameId         = $loc.GameId
                    GameName       = $loc.GameName
                    Source         = $loc.Source
                    AppId          = $loc.AppId
                    InstallDirHint = $loc.InstallDirHint
                    Token          = $null
                    RelativePath   = ''
                    Kind           = 'Registry'
                    RegistryKey    = $loc.RegistryKey
                    Payload        = ("payload\{0:D4}" -f $index)
                    PayloadFile    = 'registry.reg'
                    FileCount      = 1
                    Bytes          = [int64]$fi.Length
                    Files          = @([pscustomobject]@{ Path = 'registry.reg'; Size = [int64]$fi.Length; LastWriteUtc = $fi.LastWriteTimeUtc.ToString('o') })
                    Note           = $loc.Note
                    Origin         = $loc.Origin
                    RuleId         = $loc.RuleId
                    RestoreMode    = $loc.RestoreMode
                    InstallDirNames = @($loc.InstallDirNames)
                    FilePatterns   = @($loc.FilePatterns)
                })
                $totalBytes += [int64]$fi.Length
                $totalFiles++
                Write-GSVLog -Level Success -Message "registry   $display"
            } catch {
                $msg = "registry '$display': $($_.Exception.Message)"
                $errors.Add($msg)
                Write-GSVLog -Level Error -Message $msg
            }
            continue
        }

        if (-not (Test-Path -LiteralPath $loc.ResolvedPath)) {
            $errors.Add("missing: $($loc.ResolvedPath)")
            Write-GSVLog -Level Warn -Message "skipped (missing): $($loc.ResolvedPath)"
            continue
        }

        if ($DryRun) {
            Write-GSVLog -Level Info -Message ("[dry-run] {0,-11} {1}" -f $loc.Kind, $display)
            continue
        }

        $payloadRel = "payload\{0:D4}" -f $index
        $dest = Join-Path $snapDir $payloadRel

        try {
            if ($loc.Kind -eq 'File') {
                New-Item -ItemType Directory -Path $dest -Force | Out-Null
                Copy-Item -LiteralPath $loc.ResolvedPath -Destination $dest -Force -ErrorAction Stop
            } else {
                New-Item -ItemType Directory -Path $dest -Force | Out-Null
                Invoke-GSVCopyTree -Source $loc.ResolvedPath -Destination $dest -ExcludeDirs $excludeDirs -ExcludeFiles $excludeFiles
            }

            $files = @(Get-GSVManifestFileList -Path $dest -HashFiles:$HashFiles)
            $bytes = [int64]0
            foreach ($f in $files) { $bytes += [int64]$f.Size }

            $entries.Add([pscustomobject]@{
                GameId         = $loc.GameId
                GameName       = $loc.GameName
                Source         = $loc.Source
                AppId          = $loc.AppId
                InstallDirHint = $loc.InstallDirHint
                Token          = $loc.Token
                RelativePath   = $loc.RelativePath
                AbsolutePath   = $loc.ResolvedPath
                Kind           = $loc.Kind
                RegistryKey    = $null
                Payload        = $payloadRel
                PayloadFile    = $null
                FileCount      = $files.Count
                Bytes          = $bytes
                Files          = $files
                Note           = $loc.Note
                Origin         = $loc.Origin
                RuleId         = $loc.RuleId
                RestoreMode    = $loc.RestoreMode
                InstallDirNames = @($loc.InstallDirNames)
                FilePatterns   = @($loc.FilePatterns)
            })

            $totalBytes += $bytes
            $totalFiles += $files.Count
            Write-GSVLog -Level Success -Message ("{0,-11} {1}  ({2} files, {3})" -f $loc.Kind, $display, $files.Count, (Format-GSVSize $bytes))
        } catch {
            $msg = "copy '$display': $($_.Exception.Message)"
            $errors.Add($msg)
            Write-GSVLog -Level Error -Message $msg
        }
    }

    $manifest = [ordered]@{
        Version      = 1
        Tool         = 'GameSaveVault'
        ToolVersion  = $script:GSVVersion
        CreatedUtc   = (Get-Date).ToUniversalTime().ToString('o')
        Label        = $Label
        Machine      = $env:COMPUTERNAME
        User         = $env:USERNAME
        Os           = [Environment]::OSVersion.VersionString
        BackupRoot   = $BackupRoot
        EntryCount   = $entries.Count
        TotalFiles   = $totalFiles
        TotalBytes   = $totalBytes
        Entries      = $entries.ToArray()
        Errors       = $errors.ToArray()
    }

    if (-not $DryRun) {
        Write-GSVTextFile -Path (Join-Path $snapDir 'manifest.json') -Text ($manifest | ConvertTo-Json -Depth 12)
    }

    return [pscustomobject]@{
        SnapshotPath = $snapDir
        ManifestPath = (Join-Path $snapDir 'manifest.json')
        Manifest     = [pscustomobject]$manifest
        EntryCount   = $entries.Count
        TotalFiles   = $totalFiles
        TotalBytes   = $totalBytes
        Errors       = $errors.ToArray()
        DryRun       = [bool]$DryRun
    }
}

#endregion

#region ---------------------------------------------------------------- snapshot listing

function Get-GSVSnapshots {
    param([Parameter(Mandatory)][string]$BackupRoot)

    $snapRoot = Join-Path $BackupRoot 'snapshots'
    if (-not (Test-Path -LiteralPath $snapRoot)) { return @() }

    $result = New-Object System.Collections.Generic.List[object]
    foreach ($d in @(Get-ChildItem -LiteralPath $snapRoot -Directory -ErrorAction SilentlyContinue)) {
        $manifestPath = Join-Path $d.FullName 'manifest.json'
        $m = Read-GSVJson -Path $manifestPath
        if (-not $m) { continue }
        $result.Add([pscustomobject]@{
            Path        = $d.FullName
            Name        = $d.Name
            CreatedUtc  = if ($m.CreatedUtc) { [string]$m.CreatedUtc } else { $d.CreationTimeUtc.ToString('o') }
            Label       = [string]$m.Label
            EntryCount  = [int]$m.EntryCount
            TotalFiles  = [int]$m.TotalFiles
            TotalBytes  = [int64]$m.TotalBytes
            Machine     = [string]$m.Machine
            User        = [string]$m.User
            Errors      = @($m.Errors).Count
            Manifest    = $m
        })
    }
    return @($result | Sort-Object CreatedUtc -Descending)
}

function Get-GSVLatestSnapshot {
    param([Parameter(Mandatory)][string]$BackupRoot)
    $all = @(Get-GSVSnapshots -BackupRoot $BackupRoot)
    if ($all.Count -eq 0) { return $null }
    return $all[0]
}

function Resolve-GSVSnapshot {
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [string]$Snapshot
    )
    if (-not $Snapshot -or $Snapshot -eq 'latest') {
        $latest = Get-GSVLatestSnapshot -BackupRoot $BackupRoot
        if (-not $latest) { throw "No snapshots found in '$BackupRoot'." }
        return $latest
    }
    if (Test-Path -LiteralPath $Snapshot) {
        $p = (Get-Item -LiteralPath $Snapshot).FullName
        if (Test-Path -LiteralPath (Join-Path $p 'manifest.json')) {
            $m = Read-GSVJson -Path (Join-Path $p 'manifest.json')
            return [pscustomobject]@{
                Path       = $p
                Name       = (Split-Path -Leaf $p)
                CreatedUtc = if ($m -and $m.CreatedUtc) { [string]$m.CreatedUtc } else { '' }
                Label      = if ($m) { [string]$m.Label } else { '' }
                EntryCount = if ($m) { [int]$m.EntryCount } else { 0 }
                TotalFiles = if ($m) { [int]$m.TotalFiles } else { 0 }
                TotalBytes = if ($m) { [int64]$m.TotalBytes } else { [int64]0 }
                Machine    = if ($m) { [string]$m.Machine } else { '' }
                User       = if ($m) { [string]$m.User } else { '' }
                Errors     = if ($m) { @($m.Errors).Count } else { 0 }
                Manifest   = $m
            }
        }
    }
    $byName = @(Get-GSVSnapshots -BackupRoot $BackupRoot | Where-Object { $_.Name -eq $Snapshot -or $_.Name -like "*$Snapshot*" })
    if ($byName.Count -ge 1) { return $byName[0] }
    throw "Snapshot '$Snapshot' not found."
}

function Remove-GSVOldSnapshots {
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [int]$Keep = 8,
        [switch]$DryRun
    )
    $all = @(Get-GSVSnapshots -BackupRoot $BackupRoot)
    if ($all.Count -le $Keep) { return @() }

    $remove = @($all | Select-Object -Skip $Keep)
    $removed = New-Object System.Collections.Generic.List[string>
    foreach ($s in $remove) {
        if ($DryRun) {
            Write-GSVLog -Level Info -Message "[dry-run] would delete $($s.Path)"
            $removed.Add($s.Path)
            continue
        }
        try {
            Remove-Item -LiteralPath $s.Path -Recurse -Force -ErrorAction Stop
            $removed.Add($s.Path)
            Write-GSVLog -Level Info -Message "deleted old snapshot $($s.Name)"
        } catch {
            Write-GSVLog -Level Warn -Message "could not delete '$($s.Path)': $($_.Exception.Message)"
        }
    }
    return $removed.ToArray()
}

#endregion

#region ---------------------------------------------------------------- restore

function Find-GSVGameDir {
    param([string]$Hint)
    if (-not $Hint) { return '' }

    $candidates = New-Object System.Collections.Generic.List[string]

    foreach ($lib in (Get-GSVSteamLibraries)) {
        $candidates.Add((Join-Path $lib ('steamapps\common\' + $Hint)))
    }
    $settings = Get-GSVSettings
    foreach ($root in @($settings.GameScanRoots)) {
        if ($root) { $candidates.Add((Join-Path $root $Hint)) }
    }

    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) {
            return (Get-Item -LiteralPath $c -ErrorAction SilentlyContinue).FullName
        }
    }
    return ''
}

function Resolve-GSVTargetPath {
    param(
        [Parameter(Mandatory)]$Entry,
        [hashtable]$TokenTable,
        [string]$RestoreFormat = 'profile',
        [string]$RestoreRoot = ''
    )
    if (-not $TokenTable) { $TokenTable = Get-GSVTokenTable }

    if ($Entry.Kind -eq 'Registry') { return $null }

    # ---- verbatim: write to the exact absolute path recorded in the manifest
    # (the original drive layout, e.g. C:\Users\<olduser>\...). This recreates
    # the old profile on a fresh install instead of using the new one.
    if ($RestoreFormat -eq 'verbatim') {
        if ($Entry.Token -eq 'GAMEDIR') { return $null }  # install-relative: cannot be verbatim
        if ($Entry.AbsolutePath) { return [string]$Entry.AbsolutePath }
        # entries without an absolute path fall back to the profile view
    }

    # ---- folder: keep the layout, but root everything under one folder
    if ($RestoreFormat -eq 'folder') {
        $root = if ($RestoreRoot) { $RestoreRoot } else { $null }
        if (-not $root) { return $null }
        if ($Entry.Token) {
            $sub = Join-Path $Entry.Token ([string]$Entry.RelativePath)
            return (Join-Path $root $sub)
        }
        if ($Entry.AbsolutePath) {
            # strip the drive letter and keep the rest of the original path
            $abs = [string]$Entry.AbsolutePath
            $driveRoot = ''
            try { $driveRoot = [System.IO.Path]::GetPathRoot($abs) } catch { }
            $rel = if ($driveRoot) { $abs.Substring($driveRoot.Length) } else { $abs.TrimStart('\', '/') }
            return (Join-Path $root $rel)
        }
        return $null
    }

    # ---- save rules: put the save back next to the game found on THIS machine
    # (new drive letter / new install folder / repack folder).
    if ($RestoreFormat -eq 'profile' -and $Entry.RestoreMode) {
        $rm = ([string]$Entry.RestoreMode).ToLowerInvariant()
        $hints = New-Object System.Collections.Generic.List[string]
        if ($Entry.InstallDirHint) { $hints.Add([string]$Entry.InstallDirHint) }
        foreach ($h in @($Entry.InstallDirNames)) { if ($h) { $hints.Add([string]$h) } }

        if ($rm -eq 'gamedir' -and $hints.Count -gt 0) {
            $dir = ''
            foreach ($h in $hints.ToArray()) {
                $dir = Find-GSVGameDir -Hint $h
                if (-not $dir) { $dir = Find-GSVRuleGameDir -Names @($h) }
                if ($dir) { break }
            }
            if ($dir) {
                if ($Entry.RelativePath) { return (Join-Path $dir ([string]$Entry.RelativePath)) }
                return $dir
            }
            # game not installed yet: fall through to the normal token view
        }
        elseif ($rm -eq 'absolute') {
            $abs = [string]$Entry.AbsolutePath
            if ($abs) {
                $root = ''
                try { $root = [System.IO.Path]::GetPathRoot($abs) } catch { }
                if ($root -and (Test-Path -LiteralPath $root)) { return $abs }
            }
            return $null
        }
    }

    if ($Entry.Token -eq 'GAMEDIR') {
        $dir = Find-GSVGameDir -Hint $Entry.InstallDirHint
        if (-not $dir) { $dir = Find-GSVRuleGameDir -Names @($Entry.InstallDirHint) }
        if (-not $dir) { return $null }
        if ($Entry.RelativePath) { return (Join-Path $dir $Entry.RelativePath) }
        return $dir
    }

    if ($Entry.Token -eq 'STEAMUSERDATA') {
        $root = $TokenTable['STEAMUSERDATA']
        if (-not $root) { return $null }
        $rel = [string]$Entry.RelativePath
        $parts = @($rel -split '\\')
        if ($parts.Count -ge 1 -and $parts[0] -match '^\d+$') {
            $existing = Join-Path $root $parts[0]
            if (-not (Test-Path -LiteralPath $existing)) {
                $current = Get-GSVCurrentSteamUserId -UserDataRoot $root
                if ($current) { $parts[0] = $current }
            }
        }
        return (Join-Path $root ($parts -join '\'))
    }

    if (-not $Entry.Token) {
        # Absolute path from the manifest (no token anchor). Keep it only if the
        # drive exists; otherwise the caller reports it as unrestorable.
        if ($Entry.AbsolutePath) { return [string]$Entry.AbsolutePath }
        return $null
    }

    $rootValue = $TokenTable[$Entry.Token]
    if (-not $rootValue) { return $null }
    if ($Entry.RelativePath) { return (Join-Path $rootValue $Entry.RelativePath) }
    return [string]$rootValue
}

function Move-GSVToRollback {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$Stamp
    )
    $anchor = Get-GSVPathAnchor -ResolvedPath $Path
    if ($anchor.Token) {
        $key = Join-Path $anchor.Token $anchor.Relative
    } else {
        $safe = ($Path -replace '^([A-Za-z]):', '$1')
        $key = $safe.TrimStart('\')
    }
    $dest = Join-Path $BackupRoot ("rollback\{0}\{1}" -f $Stamp, $key)

    $destDir = Split-Path -Parent $dest
    if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    try {
        Move-Item -LiteralPath $Path -Destination $dest -Force -ErrorAction Stop
        return $dest
    } catch {
        # Cross-volume move fallback.
        if (Test-Path -LiteralPath $Path -PathType Container) {
            Invoke-GSVCopyTree -Source $Path -Destination $dest
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Copy-Item -LiteralPath $Path -Destination $dest -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        }
        return $dest
    }
}

function Restore-GSVSnapshot {
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [string]$Snapshot = 'latest',
        [string[]]$GameFilter = @(),
        [switch]$DryRun,
        [switch]$SkipRegistry,
        [switch]$NoRollback,
        [switch]$KeepExisting,
        [hashtable]$TokenTable,
        [string]$RestoreFormat = 'profile',
        [string]$RestoreRoot = '',
        [string]$LogFile
    )

    $snap = Resolve-GSVSnapshot -BackupRoot $BackupRoot -Snapshot $Snapshot
    if (-not $snap.Manifest) { throw "Snapshot '$($snap.Path)' has no readable manifest.json." }

    $manifest = $snap.Manifest
    $entries = @($manifest.Entries)
    if (-not $TokenTable) { $TokenTable = Get-GSVTokenTable }
    $table = $TokenTable
    $fmt = if ($RestoreFormat) { ([string]$RestoreFormat).ToLowerInvariant() } else { 'profile' }
    if ($fmt -notin @('profile', 'verbatim', 'folder')) { throw "Unknown restore format: $RestoreFormat" }
    if ($fmt -eq 'folder' -and -not $RestoreRoot) { throw '-RestoreRoot is required with -RestoreFormat folder.' }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

    $restored = 0
    $skipped = 0
    $failed = 0
    $registry = 0
    $bytes = [int64]0
    $messages = New-Object System.Collections.Generic.List[string]

    Write-GSVLog -Level Info -Message ("Snapshot: {0}  ({1} entries, format={2})" -f $snap.Path, $entries.Count, $fmt)

    foreach ($e in $entries) {
        $label = if ($e.Kind -eq 'Registry') { $e.RegistryKey } else { "$($e.GameName): $($e.Token)\$($e.RelativePath)" }

        if ($GameFilter.Count -gt 0) {
            $hit = $false
            foreach ($f in $GameFilter) {
                if (Test-GSVNameSimilar -A $e.GameName -B $f) { $hit = $true; break }
                if ($e.GameName -and $e.GameName.IndexOf($f, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $hit = $true; break }
            }
            if (-not $hit) { $skipped++; continue }
        }

        if ($e.Kind -eq 'Registry') {
            if ($SkipRegistry) { $skipped++; continue }
            $payloadFile = Join-Path (Join-Path $snap.Path $e.Payload) $e.PayloadFile
            if (-not (Test-Path -LiteralPath $payloadFile)) {
                Write-GSVLog -Level Warn -Message "missing registry payload for $label"
                $failed++
                continue
            }
            if ($DryRun) {
                Write-GSVLog -Level Info -Message "[dry-run] import registry  $label"
                continue
            }
            try {
                $null = & reg.exe import "$payloadFile" 2>&1
                if ($LASTEXITCODE -ne 0) { throw "reg.exe import exit $LASTEXITCODE" }
                $registry++
                Write-GSVLog -Level Success -Message "registry  $label"
            } catch {
                $failed++
                $messages.Add("registry '$label': $($_.Exception.Message)")
                Write-GSVLog -Level Error -Message "registry '$label': $($_.Exception.Message)"
            }
            continue
        }

        $target = Resolve-GSVTargetPath -Entry $e -TokenTable $table -RestoreFormat $fmt -RestoreRoot $RestoreRoot
        if (-not $target) {
            $reason = if ($e.Token -eq 'GAMEDIR') { 'game not installed (GAMEDIR not found)' } else { "token '$($e.Token)' unavailable" }
            Write-GSVLog -Level Warn -Message "skipped $label ($reason)"
            $skipped++
            $messages.Add("skipped '$label': $reason")
            continue
        }

        $payloadPath = Join-Path $snap.Path $e.Payload
        if (-not (Test-Path -LiteralPath $payloadPath)) {
            Write-GSVLog -Level Warn -Message "missing payload for $label"
            $failed++
            continue
        }

        if ($DryRun) {
            $existsText = if (Test-Path -LiteralPath $target) { ' [overwrites existing]' } else { ' [new]' }
            Write-GSVLog -Level Info -Message ("[dry-run] restore {0,-11} {1} -> {2}{3}" -f $e.Kind, $label, $target, $existsText)
            continue
        }

        try {
            if (Test-Path -LiteralPath $target) {
                if ($KeepExisting) {
                    Write-GSVLog -Level Info -Message "kept existing: $target"
                    $skipped++
                    continue
                }
                if (-not $NoRollback) {
                    $null = Move-GSVToRollback -Path $target -BackupRoot $BackupRoot -Stamp $stamp
                } else {
                    Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
                }
            }

            $targetDir = if ($e.Kind -eq 'File') { Split-Path -Parent $target } else { $target }
            if ($targetDir -and -not (Test-Path -LiteralPath $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }

            if ($e.Kind -eq 'File') {
                $srcFile = Get-ChildItem -LiteralPath $payloadPath -File -ErrorAction SilentlyContinue | Select-Object -First 1
                if (-not $srcFile) { throw 'payload file missing' }
                Copy-Item -LiteralPath $srcFile.FullName -Destination $target -Force -ErrorAction Stop
            } else {
                Invoke-GSVCopyTree -Source $payloadPath -Destination $target
            }

            $restored++
            $bytes += [int64]$e.Bytes
            Write-GSVLog -Level Success -Message ("restored {0,-11} {1} -> {2}" -f $e.Kind, $label, $target)
        } catch {
            $failed++
            $messages.Add("restore '$label': $($_.Exception.Message)")
            Write-GSVLog -Level Error -Message "restore '$label': $($_.Exception.Message)"
        }
    }

    $summary = [pscustomobject]@{
        SnapshotPath = $snap.Path
        Restored     = $restored
        Registry     = $registry
        Skipped      = $skipped
        Failed       = $failed
        Bytes        = $bytes
        Format       = $fmt
        RestoreRoot  = $RestoreRoot
        Messages     = $messages.ToArray()
        DryRun       = [bool]$DryRun
    }

    Write-GSVLog -Level Info -Message ("Done. restored={0} registry={1} skipped={2} failed={3} ({4})" -f $restored, $registry, $skipped, $failed, (Format-GSVSize $bytes))
    return $summary
}

#endregion

#region ---------------------------------------------------------------- windows.old import

function Import-GSVFromWindowsOld {
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [string]$WindowsOldRoot,
        [string[]]$GameFilter = @(),
        [switch]$DryRun,
        [switch]$NoRestore,
        [switch]$NoSize,
        [string]$Label = 'windows-old',
        [string]$RestoreFormat = 'profile',
        [string]$RestoreRoot = ''
    )

    $roots = if ($WindowsOldRoot) { @($WindowsOldRoot) } else { @(Get-GSVWindowsOldRoots) }
    if ($roots.Count -eq 0) {
        throw "No Windows.old folder found. Pass -WindowsOldRoot 'D:\Windows.old' if it is on another drive."
    }

    $all = New-Object System.Collections.Generic.List[object]
    foreach ($root in $roots) {
        Write-GSVLog -Level Info -Message "Scanning $root ..."
        foreach ($loc in @(Get-GSVWindowsOldLocations -Root $root -Games $GameFilter -NoSize:$NoSize)) {
            $all.Add($loc)
        }
    }

    # De-duplicate across profiles by token+relative (first profile wins).
    $seen = @{}
    $unique = New-Object System.Collections.Generic.List[object]
    foreach ($loc in $all) {
        $key = ("{0}|{1}" -f $loc.Token, $loc.RelativePath).ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $unique.Add($loc)
    }

    if ($unique.Count -eq 0) {
        Write-GSVLog -Level Warn -Message 'Nothing found in Windows.old that looks like game saves.'
        return [pscustomobject]@{ Locations = 0; Snapshot = $null; Restore = $null }
    }

    Write-GSVLog -Level Info -Message ("Found {0} save locations in Windows.old." -f $unique.Count)

    $snap = New-GSVSnapshot -Locations $unique.ToArray() -BackupRoot $BackupRoot -Label $Label -DryRun:$DryRun
    if ($DryRun -or $NoRestore) {
        return [pscustomobject]@{ Locations = $unique.Count; Snapshot = $snap; Restore = $null }
    }

    $restore = Restore-GSVSnapshot -BackupRoot $BackupRoot -Snapshot $snap.SnapshotPath -GameFilter $GameFilter -RestoreFormat $RestoreFormat -RestoreRoot $RestoreRoot
    return [pscustomobject]@{ Locations = $unique.Count; Snapshot = $snap; Restore = $restore }
}

#endregion

#region ---------------------------------------------------------------- vault maintenance

function Get-GSVVaultStats {
    param([Parameter(Mandatory)][string]$BackupRoot)

    $snapshots = @(Get-GSVSnapshots -BackupRoot $BackupRoot)
    $rollbackRoot = Join-Path $BackupRoot 'rollback'
    $rollbackBytes = [int64]0
    if (Test-Path -LiteralPath $rollbackRoot) {
        $s = Measure-GSVPathSize -Path $rollbackRoot
        $rollbackBytes = [int64]$s.Bytes
    }

    $snapBytes = [int64]0
    foreach ($s in $snapshots) { $snapBytes += [int64]$s.TotalBytes }

    return [pscustomobject]@{
        BackupRoot    = $BackupRoot
        SnapshotCount = $snapshots.Count
        SnapshotBytes = $snapBytes
        RollbackBytes = $rollbackBytes
        Latest        = if ($snapshots.Count) { $snapshots[0] } else { $null }
        Snapshots     = $snapshots
    }
}

#region ---------------------------------------------------------------- vault maintenance

function Copy-GSVEmulatorSaves {
    param(
        [Parameter(Mandatory)][object[]]$Entries,
        [Parameter(Mandatory)][string]$DestinationEmulatorId,
        [hashtable]$TokenTable,
        [string]$BackupRoot,
        [switch]$DryRun
    )
    if (-not $TokenTable) { $TokenTable = Get-GSVTokenTable }

    $def = @((Get-GSVEmulatorDefinitions) | Where-Object { $_.Id -eq $DestinationEmulatorId }) | Select-Object -First 1
    if (-not $def) { throw "Unknown destination emulator: $DestinationEmulatorId" }

    # Every save root the destination emulator currently has (so we can place a
    # save next to its existing data instead of guessing a new folder).
    $destDirs = @(Get-GSVEmulatorDirs -EmulatorIds @($DestinationEmulatorId) -TokenTable $TokenTable -IncludePortable)
    if ($destDirs.Count -eq 0) {
        throw "$($def.Name) was not found on this PC. Install it, or point GameScanRoots at its folder, then migrate again."
    }

    $destRoots = New-Object System.Collections.Generic.List[object]
    foreach ($hit in $destDirs) {
        foreach ($relRoot in @($def.SaveRoots)) {
            $saveRoot = $relRoot -replace '/', '\'
            if ($saveRoot -match '\*') {
                $keep = @()
                foreach ($seg in ($saveRoot -split '\\')) {
                    if ($seg -match '\*') { break }
                    $keep += $seg
                }
                $base = $keep -join '\'
                $rootDir = Join-Path $hit.DataDir $base
                if (-not (Test-Path -LiteralPath $rootDir)) { continue }
                foreach ($userDir in @(Get-ChildItem -LiteralPath $rootDir -Directory -ErrorAction SilentlyContinue)) {
                    foreach ($leaf in @('savedata', 'SaveData', 'saveData', 'Savedata')) {
                        $candidate = Join-Path $userDir.FullName $leaf
                        if (Test-Path -LiteralPath $candidate) {
                            $destRoots.Add([pscustomobject]@{ DataDir = $hit.DataDir; SaveRoot = $candidate })
                        }
                    }
                }
            } else {
                $candidate = Join-Path $hit.DataDir $saveRoot
                if (Test-Path -LiteralPath $candidate) {
                    $destRoots.Add([pscustomobject]@{ DataDir = $hit.DataDir; SaveRoot = $candidate })
                }
            }
        }
    }
    if ($destRoots.Count -eq 0) {
        throw "$($def.Name) is installed but its save folder does not exist yet. Launch it once, then migrate again."
    }

    $migrated = 0; $skipped = 0; $failed = 0
    $messages = New-Object System.Collections.Generic.List[string]
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

    foreach ($entry in $Entries) {
        $src = $entry.Path
        if (-not $src -or -not (Test-Path -LiteralPath $src)) {
            $messages.Add("missing source: $src")
            $skipped++
            continue
        }

        # Pick the matching destination save root: prefer the same subsystem
        # (user saves vs system saves), then the first one available.
        $destRoot = $destRoots[0].SaveRoot
        foreach ($candidate in $destRoots) {
            $candLeaf = Split-Path -Leaf $candidate.SaveRoot
            $srcLeaf = Split-Path -Leaf $entry.SaveRoot
            if ($candLeaf -ieq $srcLeaf) { $destRoot = $candidate.SaveRoot; break }
        }
        foreach ($candidate in $destRoots) {
            if ($candidate.SaveRoot -match '(?i)\\user\\save$' -and $entry.SaveRoot -match '(?i)\\user\\save$') { $destRoot = $candidate.SaveRoot; break }
        }

        # Profile mapping: keep the source profile if the destination knows it,
        # otherwise use the destination's own profile slot.
        $profile = [string]$entry.ProfileId
        if ($profile) {
            $profileDir = Join-Path $destRoot $profile
            if (-not (Test-Path -LiteralPath $profileDir)) {
                $existing = @(Get-ChildItem -LiteralPath $destRoot -Directory -ErrorAction SilentlyContinue | Select-Object -First 1)
                if ($existing.Count -gt 0) { $profile = $existing[0].Name }
            }
        }

        $dest = if ($profile) { Join-Path (Join-Path $destRoot $profile) $entry.TitleId } else { Join-Path $destRoot $entry.TitleId }

        if ($DryRun) {
            Write-GSVLog -Level Info -Message ("[dry-run] migrate {0} -> {1}  [{2}]" -f $src, $dest, $entry.TitleId)
            $migrated++
            continue
        }

        try {
            if (Test-Path -LiteralPath $dest) {
                # The destination save is first moved to the rollback folder so
                # a migration never destroys existing progress.
                if ($BackupRoot) {
                    $null = Move-GSVToRollback -Path $dest -BackupRoot $BackupRoot -Stamp $stamp
                } else {
                    Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
                }
            }

            New-Item -ItemType Directory -Path $dest -Force | Out-Null
            $settings = Get-GSVSettings
            Invoke-GSVCopyTree -Source $src -Destination $dest -ExcludeDirs $settings.ExcludeNames -ExcludeFiles $settings.ExcludeFiles
            $migrated++
            Write-GSVLog -Level Success -Message ("migrated {0} -> {1}" -f $src, $dest)
        } catch {
            $failed++
            $msg = "migrate '$src': $($_.Exception.Message)"
            $messages.Add($msg)
            Write-GSVLog -Level Error -Message $msg
        }
    }

    return [pscustomobject]@{
        Migrated = $migrated; Skipped = $skipped; Failed = $failed
        Messages = $messages.ToArray(); Destination = $DestinationEmulatorId
    }
}

#endregion

#region ---------------------------------------------------------------- portable database

function New-GSVPortableDatabase {
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [string]$Snapshot = 'latest',
        [Parameter(Mandatory)][string]$OutputPath,
        [switch]$IncludeScanDatabase,
        [switch]$Force,
        [string]$LogFile
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

    $snap = Resolve-GSVSnapshot -BackupRoot $BackupRoot -Snapshot $Snapshot
    if (-not $snap -or -not $snap.Manifest) { throw "Snapshot '$Snapshot' has no readable manifest.json." }

    if (-not $OutputPath) { throw 'OutputPath is required.' }
    if ([System.IO.Path]::GetExtension($OutputPath) -eq '') { $OutputPath += '.gsvdb' }
    $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

    if ((Test-Path -LiteralPath $OutputPath) -and -not $Force) {
        throw "Output file already exists: $OutputPath (use -Force to overwrite)"
    }
    $outDir = Split-Path -Parent $OutputPath
    if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }

    $stage = Join-Path ([System.IO.Path]::GetTempPath()) ('gsv-bundle-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage -Force | Out-Null

    try {
        $manifestSource = Join-Path $snap.Path 'manifest.json'
        if (-not (Test-Path -LiteralPath $manifestSource)) { throw "Snapshot manifest missing: $manifestSource" }
        Copy-Item -LiteralPath $manifestSource -Destination (Join-Path $stage 'manifest.json') -Force

        $payloadSource = Join-Path $snap.Path 'payload'
        if (Test-Path -LiteralPath $payloadSource) {
            Invoke-GSVCopyTree -Source $payloadSource -Destination (Join-Path $stage 'payload')
        }

        $includedDb = $false
        if ($IncludeScanDatabase) {
            $dbPath = Get-GSVScanDatabasePath
            if ($dbPath -and (Test-Path -LiteralPath $dbPath)) {
                Copy-Item -LiteralPath $dbPath -Destination (Join-Path $stage 'scan-database.json') -Force
                $includedDb = $true
            }
        }

        $bundleInfo = [pscustomobject]([ordered]@{
            Version       = 1
            Tool          = 'GameSaveVault'
            ToolVersion   = $script:GSVVersion
            CreatedUtc    = (Get-Date).ToUniversalTime().ToString('o')
            SnapshotName  = $snap.Name
            SnapshotLabel = [string]$snap.Label
            Machine       = $env:COMPUTERNAME
            User          = $env:USERNAME
            EntryCount    = [int]$snap.EntryCount
            TotalFiles    = [int]$snap.TotalFiles
            TotalBytes    = [int64]$snap.TotalBytes
            ScanDatabase  = $includedDb
        })
        Write-GSVTextFile -Path (Join-Path $stage 'bundle.json') -Text ($bundleInfo | ConvertTo-Json -Depth 6)

        if ((Test-Path -LiteralPath $OutputPath) -and $Force) {
            Remove-Item -LiteralPath $OutputPath -Force -ErrorAction SilentlyContinue
        }
        [System.IO.Compression.ZipFile]::CreateFromDirectory(
            $stage, $OutputPath,
            [System.IO.Compression.CompressionLevel]::Optimal,
            $false)

        $fi = Get-Item -LiteralPath $OutputPath
        Write-GSVLog -Level Success -Message ("portable database: {0} ({1})" -f $OutputPath, (Format-GSVSize $fi.Length)) -LogFile $LogFile

        return [pscustomobject]@{
            Path         = $OutputPath
            Bytes        = [int64]$fi.Length
            SnapshotPath = $snap.Path
            SnapshotName = $snap.Name
            EntryCount   = [int]$snap.EntryCount
            TotalFiles   = [int]$snap.TotalFiles
            ScanDatabase = $includedDb
        }
    } finally {
        if (Test-Path -LiteralPath $stage) {
            Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-GSVPortableDatabaseInfo {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Portable database not found: $Path" }

    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $zip = $null
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)

        $readEntry = {
            param($name)
            $entry = $zip.Entries | Where-Object { $_.FullName -ieq $name } | Select-Object -First 1
            if (-not $entry) { return $null }
            $reader = New-Object System.IO.StreamReader($entry.Open())
            try { return ($reader.ReadToEnd() | ConvertFrom-Json) } finally { $reader.Dispose() }
        }

        $manifest = & $readEntry 'manifest.json'
        if (-not $manifest) { throw "Not a GameSaveVault portable database (manifest.json missing): $Path" }
        $bundle = & $readEntry 'bundle.json'

        return [pscustomobject]@{
            Path         = (Get-Item -LiteralPath $Path).FullName
            Bytes        = [int64](Get-Item -LiteralPath $Path).Length
            Manifest     = $manifest
            Bundle       = $bundle
            SnapshotName = if ($bundle) { [string]$bundle.SnapshotName } else { '' }
            Machine      = if ($bundle) { [string]$bundle.Machine } else { [string]$manifest.Machine }
            EntryCount   = [int]$manifest.EntryCount
            TotalFiles   = [int]$manifest.TotalFiles
            TotalBytes   = [int64]$manifest.TotalBytes
            HasScanDb    = [bool](@($zip.Entries | Where-Object { $_.FullName -ieq 'scan-database.json' }).Count -gt 0)
        }
    } finally {
        if ($zip) { $zip.Dispose() }
    }
}

function Restore-GSVPortableDatabase {
    param(
        [Parameter(Mandatory)][string]$BundlePath,
        [Parameter(Mandatory)][string]$BackupRoot,
        [string]$RestoreFormat = 'profile',
        [string]$RestoreRoot = '',
        [string[]]$GameFilter = @(),
        [switch]$DryRun,
        [switch]$SkipRegistry,
        [switch]$KeepExisting,
        [switch]$NoScanDatabaseImport,
        [string]$LogFile
    )

    if (-not (Test-Path -LiteralPath $BundlePath)) { throw "Portable database not found: $BundlePath" }

    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('gsv-restore-' + [guid]::NewGuid().ToString('N'))
    $importedDb = $false

    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($BundlePath, $tempDir)

        $manifestPath = Join-Path $tempDir 'manifest.json'
        if (-not (Test-Path -LiteralPath $manifestPath)) {
            throw "Not a GameSaveVault portable database (manifest.json missing): $BundlePath"
        }

        $dbPath = Join-Path $tempDir 'scan-database.json'
        if (-not $DryRun -and -not $NoScanDatabaseImport -and (Test-Path -LiteralPath $dbPath)) {
            $null = Import-GSVScanDatabaseFile -Path $dbPath
            $importedDb = $true
        }

        if (-not $DryRun -and -not (Test-Path -LiteralPath $BackupRoot)) {
            New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
        }

        $result = Restore-GSVSnapshot -BackupRoot $BackupRoot -Snapshot $tempDir `
            -GameFilter $GameFilter -DryRun:$DryRun -SkipRegistry:$SkipRegistry `
            -KeepExisting:$KeepExisting -RestoreFormat $RestoreFormat -RestoreRoot $RestoreRoot `
            -LogFile $LogFile

        return [pscustomobject]@{
            BundlePath        = (Get-Item -LiteralPath $BundlePath).FullName
            ImportedDatabase  = $importedDb
            Restore           = $result
            Restored          = $result.Restored
            Registry          = $result.Registry
            Skipped           = $result.Skipped
            Failed            = $result.Failed
            Messages          = $result.Messages
        }
    } finally {
        if (Test-Path -LiteralPath $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

#endregion

Export-ModuleMember -Function *
