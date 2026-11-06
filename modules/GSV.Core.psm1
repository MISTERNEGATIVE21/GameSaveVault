#requires -Version 5.1
<#
    GSV.Core.psm1
    Discovery + shared helpers for GameSaveVault.
    Works on Windows PowerShell 5.1 and PowerShell 7+.
#>

$script:GSVVersion = '1.0.0'
$script:Root       = Split-Path -Parent $PSScriptRoot
$script:ConfigDir  = Join-Path $script:Root 'config'
$script:SettingsPath = Join-Path $script:ConfigDir 'settings.json'
$script:CustomPath   = Join-Path $script:ConfigDir 'games.custom.json'
$script:CatalogPath  = Join-Path $script:Root 'data\catalog.psd1'
$script:Catalog      = $null
$script:Settings     = $null

# Folders that must never be treated as a game save folder by name matching.
$script:FolderBlocklist = @(
    'microsoft','windows','packages','temp','tmp','google','mozilla','adobe','nvidia','intel','amd',
    'realtek','apple','dropbox','onedrive','discord','slack','spotify','steam','epicgameslauncher',
    'ubisoft game launcher','origin','ea desktop','electronic arts','battle.net','riot client',
    'gog galaxy','common files','connecteddevicesplatform','comms','d3dscache','diagnostics',
    'elevateddiagnostics','fontcache','iconcache','microsoft corporation','publisher','virtualstore',
    'programs','low','roaming','crashdumps','wer','placeholdertilelogofolder','ntuser',
    'assembly','application data','history','inetcookies','local settings','my documents','netcache',
    'privatedisplaycache','recent','sendto','start menu','templates','temporary internet files',
    'the creative assembly','daybreak game company','unity','unrealengine','epic games'
)

#region ---------------------------------------------------------------- logging

function Write-GSVLog {
    param(
        [ValidateSet('Info','Warn','Error','Debug','Success')]
        [string]$Level = 'Info',
        [string]$Message,
        [string]$LogFile
    )
    $line = '[{0}] {1,-7} {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    switch ($Level) {
        'Warn'    { Write-Host $line -ForegroundColor Yellow }
        'Error'   { Write-Host $line -ForegroundColor Red }
        'Success' { Write-Host $line -ForegroundColor Green }
        'Debug'   { Write-Verbose $line }
        default   { Write-Host $line }
    }
    if ($LogFile) {
        try {
            $dir = Split-Path -Parent $LogFile
            if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
        } catch { }
    }
}

function Get-GSVRoot { $script:Root }
function Get-GSVVersion { $script:GSVVersion }

function Write-GSVTextFile {
    param([string]$Path, [string]$Text)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $utf8)
}

function Read-GSVJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        if (-not $raw) { return $null }
        return ($raw | ConvertFrom-Json)
    } catch {
        Write-GSVLog -Level Warn -Message "Could not read JSON '$Path': $($_.Exception.Message)"
        return $null
    }
}

#endregion

#region ---------------------------------------------------------------- settings

function Get-GSVDefaultBackupRoot {
    # Prefer a fixed drive that is not the system drive, so a Windows reinstall
    # on C: cannot destroy the vault.
    $systemDrive = ($env:SystemDrive).TrimEnd('\').ToUpperInvariant()
    try {
        $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
            Where-Object { $_.Root -and $_.Free -gt 2GB } |
            Sort-Object Free -Descending
        foreach ($d in $drives) {
            $letter = $d.Root.TrimEnd('\').ToUpperInvariant()
            if ($letter -ne $systemDrive) {
                return (Join-Path $d.Root 'GameSaveVault')
            }
        }
    } catch { }
    return (Join-Path $env:USERPROFILE 'GameSaveVault')
}

function Get-GSVDefaultScanRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    $candidates = @(
        'C:\Games','D:\Games','E:\Games','F:\Games',
        'C:\Game','D:\Game',
        'C:\Program Files (x86)\Steam\steamapps\common',
        'C:\Program Files\Steam\steamapps\common',
        'C:\Program Files\Epic Games',
        'C:\Program Files\EA Games',
        'C:\Program Files (x86)\Ubisoft',
        'C:\Program Files\Ubisoft',
        'C:\Program Files (x86)\GOG Galaxy\Games',
        'C:\GOG Games',
        'D:\GOG Games'
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) {
            $full = (Get-Item -LiteralPath $c -ErrorAction SilentlyContinue).FullName
            if ($full -and -not $roots.Contains($full)) { $roots.Add($full) }
        }
    }
    return $roots.ToArray()
}

function Get-GSVDefaultSettings {
    [pscustomobject]@{
        BackupRoot      = (Get-GSVDefaultBackupRoot)
        GameScanRoots   = @(Get-GSVDefaultScanRoots)
        ExtraPaths      = @()
        ExcludeNames    = @('cache','Cache','ShaderCache','shadercache','CrashReports','crashdumps','logs','Logs','__pycache__','.git')
        ExcludeFiles    = @('*.log','*.tmp','*.dmp','*.etl')
        HashFiles       = $false
        KeepSnapshots   = 8
        RegistryExport  = $true
        LastScanUtc     = $null
    }
}

function Get-GSVSettings {
    param([switch]$Refresh)
    if ($script:Settings -and -not $Refresh) { return $script:Settings }

    $defaults = Get-GSVDefaultSettings
    $obj = Read-GSVJson -Path $script:SettingsPath

    if (-not $obj) {
        $obj = $defaults
    } else {
        foreach ($p in $defaults.PSObject.Properties) {
            if (-not ($obj.PSObject.Properties.Name -contains $p.Name)) {
                $obj | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force
            }
        }
    }
    $script:Settings = $obj
    return $obj
}

function Save-GSVSettings {
    param($Settings)
    if (-not $Settings) { $Settings = Get-GSVSettings }
    Write-GSVTextFile -Path $script:SettingsPath -Text ($Settings | ConvertTo-Json -Depth 8)
    $script:Settings = $Settings
}

#endregion

#region ---------------------------------------------------------------- paths + tokens

function Get-GSVSteamRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    $candidates = New-Object System.Collections.Generic.List[string]

    foreach ($reg in @(
        'HKCU:\Software\Valve\Steam',
        'HKLM:\SOFTWARE\Valve\Steam',
        'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam'
    )) {
        try {
            if (Test-Path $reg) {
                $p = Get-ItemProperty -Path $reg -ErrorAction SilentlyContinue
                if ($p.SteamPath)   { $candidates.Add($p.SteamPath) }
                if ($p.InstallPath) { $candidates.Add($p.InstallPath) }
            }
        } catch { }
    }
    $candidates.Add('C:\Program Files (x86)\Steam')
    $candidates.Add('C:\Program Files\Steam')

    foreach ($c in $candidates) {
        if (-not $c) { continue }
        $c = $c -replace '/', '\'
        try {
            if (Test-Path -LiteralPath $c) {
                $full = (Get-Item -LiteralPath $c -ErrorAction SilentlyContinue).FullName
                if (-not $full) { continue }
                # A real Steam root always has steamapps or steam.exe. This filters
                # out stale/emulator registry values that point at a game folder.
                $isSteam = (Test-Path -LiteralPath (Join-Path $full 'steamapps')) -or
                           (Test-Path -LiteralPath (Join-Path $full 'steam.exe'))
                if ($isSteam -and -not $roots.Contains($full)) { $roots.Add($full) }
            }
        } catch { }
    }
    return $roots.ToArray()
}

function Get-GSVSteamLibraries {
    $libs = New-Object System.Collections.Generic.List[string]
    foreach ($root in (Get-GSVSteamRoots)) {
        if (-not $libs.Contains($root)) { $libs.Add($root) }

        $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            try {
                $txt = Get-Content -LiteralPath $vdf -Raw -ErrorAction SilentlyContinue
                if ($txt) {
                    foreach ($m in [regex]::Matches($txt, '"path"\s+"([^"]+)"')) {
                        $p = $m.Groups[1].Value -replace '\\\\', '\' -replace '/', '\'
                        if ((Test-Path -LiteralPath $p) -and -not $libs.Contains($p)) { $libs.Add($p) }
                    }
                }
            } catch { }
        }
    }
    return $libs.ToArray()
}

function Get-GSVSteamUserDataRoot {
    foreach ($root in (Get-GSVSteamRoots)) {
        $ud = Join-Path $root 'userdata'
        if (Test-Path -LiteralPath $ud) { return $ud }
    }
    return ''
}

function Get-GSVCurrentSteamUserId {
    param([string]$UserDataRoot)
    $ud = if ($UserDataRoot) { $UserDataRoot } else { Get-GSVSteamUserDataRoot }
    if (-not $ud) { return '' }

    $login = Join-Path $ud 'loginusers.vdf'
    if (Test-Path -LiteralPath $login) {
        try {
            $txt = Get-Content -LiteralPath $login -Raw -ErrorAction SilentlyContinue
            # Prefer the block containing "MostRecent" "1"
            foreach ($m in [regex]::Matches($txt, '"(\d{6,20})"\s*\{([^}]*)\}')) {
                if ($m.Groups[2].Value -match '"MostRecent"\s+"1"') { return $m.Groups[1].Value }
            }
            $first = [regex]::Match($txt, '"(\d{6,20})"\s*\{')
            if ($first.Success) { return $first.Groups[1].Value }
        } catch { }
    }
    try {
        $dirs = Get-ChildItem -LiteralPath $ud -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d{6,20}$' } |
            Sort-Object { [int64]$_.Name } -Descending
        if ($dirs) { return $dirs[0].Name }
    } catch { }
    return ''
}

function Get-GSVSavedGamesPath {
    # .NET Framework's SpecialFolder enum has no "SavedGames" member, so read the
    # shell known-folder value and fall back to the default profile location.
    try {
        $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
        $v = (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue).'{4C5C32FF-BB9D-43B0-B5B4-2D72E54EAAA4}'
        if ($v) { return [Environment]::ExpandEnvironmentVariables([string]$v) }
    } catch { }
    return (Join-Path $env:USERPROFILE 'Saved Games')
}

function Get-GSVTokenTable {
    param([hashtable]$Override)

    $docs = [Environment]::GetFolderPath('MyDocuments')
    if (-not $docs) { $docs = Join-Path $env:USERPROFILE 'Documents' }

    $saved = Get-GSVSavedGamesPath

    $table = @{
        'USERPROFILE'   = $env:USERPROFILE
        'APPDATA'       = $env:APPDATA
        'LOCALAPPDATA'  = $env:LOCALAPPDATA
        'LOCALLOW'      = (Join-Path $env:USERPROFILE 'AppData\LocalLow')
        'DOCUMENTS'     = $docs
        'SAVEDGAMES'    = $saved
        'PUBLIC'        = $env:PUBLIC
        'PUBLICDOCS'    = (Join-Path $env:PUBLIC 'Documents')
        'PROGRAMDATA'   = $env:ProgramData
        'ONEDRIVE'      = $env:OneDrive
        'GAMEDIR'       = ''
        'STEAMUSERDATA' = (Get-GSVSteamUserDataRoot)
    }

    if ($Override) {
        foreach ($k in $Override.Keys) {
            if ($Override[$k]) { $table[$k] = $Override[$k] }
        }
    }
    return $table
}

function Expand-GSVToken {
    param(
        [string]$Path,
        [hashtable]$TokenTable
    )
    if (-not $TokenTable) { $TokenTable = Get-GSVTokenTable }
    $result = [string]$Path
    foreach ($k in $TokenTable.Keys) {
        $v = $TokenTable[$k]
        if ($null -eq $v) { $v = '' }
        $result = $result.Replace("%$k%", [string]$v)
    }
    $result = [Environment]::ExpandEnvironmentVariables($result)
    return $result
}

function Get-GSVPathAnchor {
    param(
        [string]$ResolvedPath,
        [hashtable]$TokenTable
    )
    if (-not $TokenTable) { $TokenTable = Get-GSVTokenTable }
    if ([string]::IsNullOrWhiteSpace($ResolvedPath)) {
        return [pscustomobject]@{ Token = $null; Relative = ''; Root = ''; Absolute = '' }
    }

    $norm = $ResolvedPath.TrimEnd('\')
    $best = $null

    foreach ($k in $TokenTable.Keys) {
        $v = $TokenTable[$k]
        if ([string]::IsNullOrWhiteSpace([string]$v)) { continue }
        $root = ([string]$v).TrimEnd('\')
        if ($root.Length -lt 3) { continue }

        if ($norm.Equals($root, [StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{ Token = $k; Relative = ''; Root = $root; Absolute = $norm }
        }
        if ($norm.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
            $rel = $norm.Substring($root.Length + 1)
            if (-not $best -or $root.Length -gt $best.Root.Length) {
                $best = [pscustomobject]@{ Token = $k; Relative = $rel; Root = $root; Absolute = $norm }
            }
        }
    }

    if ($best) { return $best }

    $drive = ''
    try { $drive = [System.IO.Path]::GetPathRoot($norm) } catch { }
    if ($drive) {
        return [pscustomobject]@{
            Token = $null
            Relative = $norm.Substring($drive.Length)
            Root = $drive.TrimEnd('\')
            Absolute = $norm
        }
    }
    return [pscustomobject]@{ Token = $null; Relative = $norm; Root = ''; Absolute = $norm }
}

function Resolve-GSVPathPattern {
    param(
        [string]$Pattern,
        [hashtable]$TokenTable
    )
    $expanded = Expand-GSVToken -Path $Pattern -TokenTable $TokenTable
    $results = New-Object System.Collections.Generic.List[string]

    if ($expanded -match '[*?]') {
        try {
            foreach ($i in @(Get-Item -Path $expanded -Force -ErrorAction SilentlyContinue)) {
                if ($i -and $i.FullName) { $results.Add($i.FullName) }
            }
        } catch { }
    } else {
        try {
            if (Test-Path -LiteralPath $expanded) {
                $i = Get-Item -LiteralPath $expanded -Force -ErrorAction SilentlyContinue
                if ($i) { $results.Add($i.FullName) }
            }
        } catch { }
    }
    return $results.ToArray()
}

function Measure-GSVPathSize {
    param(
        [string]$Path,
        [int]$MaxFiles = 50000
    )
    $files = 0
    $bytes = [int64]0

    try {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            $f = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
            if ($f) { return @{ Files = 1; Bytes = [int64]$f.Length } }
            return @{ Files = 0; Bytes = 0 }
        }
    } catch { }

    $stack = New-Object System.Collections.Stack
    $stack.Push($Path)
    while ($stack.Count -gt 0 -and $files -lt $MaxFiles) {
        $dir = $stack.Pop()
        try {
            foreach ($f in [System.IO.Directory]::EnumerateFiles($dir)) {
                $files++
                try { $bytes += (New-Object System.IO.FileInfo($f)).Length } catch { }
                if ($files -ge $MaxFiles) { break }
            }
            foreach ($d in [System.IO.Directory]::EnumerateDirectories($dir)) {
                $stack.Push($d)
            }
        } catch { }
    }
    return @{ Files = $files; Bytes = $bytes }
}

function Format-GSVSize {
    param([object]$Bytes)
    if ($null -eq $Bytes) { return '' }
    $b = [double]$Bytes
    if ($b -ge 1GB) { return ('{0:N2} GB' -f ($b / 1GB)) }
    if ($b -ge 1MB) { return ('{0:N1} MB' -f ($b / 1MB)) }
    if ($b -ge 1KB) { return ('{0:N0} KB' -f ($b / 1KB)) }
    return ('{0:N0} B' -f $b)
}

function Get-GSVRegistryPath {
    param([string]$Key)
    if (-not $Key) { return '' }
    $k = $Key.Trim()
    if ($k -match '^(?i)HKCU\\') { return ('Registry::HKEY_CURRENT_USER\' + $k.Substring(5)) }
    if ($k -match '^(?i)HKLM\\') { return ('Registry::HKEY_LOCAL_MACHINE\' + $k.Substring(5)) }
    if ($k -match '^(?i)HKEY_CURRENT_USER\\') { return ('Registry::' + $k) }
    if ($k -match '^(?i)HKEY_LOCAL_MACHINE\\') { return ('Registry::' + $k) }
    return ''
}

function Test-GSVRegistryKey {
    param([string]$Key)
    $p = Get-GSVRegistryPath -Key $Key
    if (-not $p) { return $false }
    try { return (Test-Path -LiteralPath $p) } catch { return $false }
}

#endregion

#region ---------------------------------------------------------------- name matching

function ConvertTo-GSVNormalName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return '' }
    $n = $Name.ToLowerInvariant()
    $n = $n -replace '[®™©]', ' '
    $n = $n -replace '\(.*?\)|\[.*?\]', ' '
    $n = $n -replace '\b(repack|fitgirl|dodi|elamigos|codex|plaza|rune|empress|skidrow|reloaded|razor1911|goldberg|flt|tenoke|hoodlum|prophet|ali213|3dm|steamrip|gog|multi\d*|update|hotfix|dlc|portable|preinstalled)\b', ' '
    $n = $n -replace '\bv?\d+(\.\d+)+[a-z]?\b', ' '
    $n = $n -replace '[^a-z0-9]+', ' '
    return $n.Trim()
}

function Get-GSVNameTokens {
    param([string]$Name)
    $s = ConvertTo-GSVNormalName -Name $Name
    $s = $s -replace '\b(game of the year|goty|definitive|remastered|directors cut|deluxe|ultimate|complete|enhanced|anniversary|special|legendary|premium|gold|standard|edition|collection|bundle)\b', ' '
    $s = $s -replace '[^a-z0-9]+', ' '
    return @($s.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries) |
        Where-Object { $_.Length -ge 3 -and $_.Length -le 24 } |
        Select-Object -Unique)
}

function Test-GSVNameSimilar {
    param(
        [string]$A,
        [string]$B,
        [double]$Threshold = 0.75
    )
    $ta = @(Get-GSVNameTokens -Name $A)
    $tb = @(Get-GSVNameTokens -Name $B)
    if ($ta.Count -eq 0 -or $tb.Count -eq 0) { return $false }

    $common = @($ta | Where-Object { $tb -contains $_ }).Count
    if ($common -eq 0) { return $false }
    $min = [Math]::Min($ta.Count, $tb.Count)
    $ratio = $common / [double]$min
    return ($ratio -ge $Threshold)
}

#endregion

#region ---------------------------------------------------------------- catalog

function Get-GSVCustomGames {
    $raw = Read-GSVJson -Path $script:CustomPath
    if (-not $raw) { return @() }
    $items = @()
    foreach ($g in @($raw)) {
        if (-not $g.Name) { continue }
        $items += [pscustomobject]@{
            Id           = if ($g.Id) { [string]$g.Id } else { 'custom-' + (ConvertTo-GSVNormalName $g.Name) }
            Name         = [string]$g.Name
            Aliases      = @($g.Aliases)
            Engine       = if ($g.Engine) { [string]$g.Engine } else { 'Custom' }
            SteamAppIds  = @($g.SteamAppIds)
            Paths        = @($g.Paths)
            RegistryKeys = @($g.RegistryKeys)
            Notes        = [string]$g.Notes
            Normalized   = (ConvertTo-GSVNormalName $g.Name)
            Custom       = $true
        }
    }
    return @($items)
}

function Save-GSVCustomGame {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$Paths,
        [string[]]$RegistryKeys = @(),
        [string]$Notes = ''
    )
    $existing = @()
    if (Test-Path -LiteralPath $script:CustomPath) {
        $raw = Read-GSVJson -Path $script:CustomPath
        if ($raw) { $existing = @($raw) }
    }

    # Merge with an existing entry of the same name instead of replacing it.
    $previous = $existing | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if ($previous) {
        $Paths = @(@($previous.Paths) + @($Paths) | Where-Object { $_ } | Select-Object -Unique)
        if (-not $RegistryKeys -or @($RegistryKeys).Count -eq 0) { $RegistryKeys = @($previous.RegistryKeys) }
        if (-not $Notes -and $previous.Notes) { $Notes = [string]$previous.Notes }
    }

    $entry = [ordered]@{
        Id           = 'custom-' + (ConvertTo-GSVNormalName $Name)
        Name         = $Name
        Aliases      = @()
        Engine       = 'Custom'
        SteamAppIds  = @()
        Paths        = @($Paths)
        RegistryKeys = @($RegistryKeys)
        Notes        = $Notes
    }
    $merged = @($existing | Where-Object { $_.Name -ne $Name })
    $merged += [pscustomobject]$entry
    Write-GSVTextFile -Path $script:CustomPath -Text (ConvertTo-Json -InputObject @($merged) -Depth 8)
    $script:Catalog = $null
    return $entry
}

function Get-GSVCatalog {
    param([switch]$Refresh)
    if ($script:Catalog -and -not $Refresh) { return $script:Catalog }

    $games = New-Object System.Collections.Generic.List[object]

    if (Test-Path -LiteralPath $script:CatalogPath) {
        try {
            $data = Import-PowerShellDataFile -LiteralPath $script:CatalogPath
            foreach ($g in @($data.Games)) {
                if (-not $g.Name) { continue }
                $games.Add([pscustomobject]@{
                    Id           = [string]$g.Id
                    Name         = [string]$g.Name
                    Aliases      = @($g.Aliases)
                    Engine       = [string]$g.Engine
                    SteamAppIds  = @($g.SteamAppIds)
                    Paths        = @($g.Paths)
                    RegistryKeys = @($g.RegistryKeys)
                    Notes        = [string]$g.Notes
                    Normalized   = (ConvertTo-GSVNormalName $g.Name)
                    Custom       = $false
                })
            }
        } catch {
            Write-GSVLog -Level Warn -Message "Catalog load failed: $($_.Exception.Message)"
        }
    }

    foreach ($g in (Get-GSVCustomGames)) { $games.Add($g) }

    $script:Catalog = $games.ToArray()
    return $script:Catalog
}

function Find-GSVCatalogEntry {
    param(
        $Game,
        [object[]]$Catalog
    )
    if (-not $Catalog) { $Catalog = Get-GSVCatalog }
    if (-not $Game) { return $null }

    # 1. Exact Steam AppID match is the strongest signal.
    if ($Game.AppId -and ([string]$Game.AppId -match '^\d+$')) {
        $id = [int64]$Game.AppId
        foreach ($e in $Catalog) {
            foreach ($aid in @($e.SteamAppIds)) {
                if ([string]$aid -match '^\d+$' -and [int64]$aid -eq $id) { return $e }
            }
        }
    }

    # 2. Exact normalized name / alias.
    $n = ConvertTo-GSVNormalName -Name $Game.Name
    if ($n) {
        foreach ($e in $Catalog) {
            if ($e.Normalized -eq $n) { return $e }
            foreach ($a in @($e.Aliases)) {
                if ((ConvertTo-GSVNormalName -Name $a) -eq $n) { return $e }
            }
        }
        # 3. Fuzzy token match.
        foreach ($e in $Catalog) {
            if (Test-GSVNameSimilar -A $Game.Name -B $e.Name) { return $e }
        }
    }
    return $null
}

#endregion

#region ---------------------------------------------------------------- installed game discovery

function Get-GSVSteamGames {
    $games = New-Object System.Collections.Generic.List[object]
    foreach ($lib in (Get-GSVSteamLibraries)) {
        $apps = Join-Path $lib 'steamapps'
        if (-not (Test-Path -LiteralPath $apps)) { continue }

        foreach ($acf in @(Get-ChildItem -LiteralPath $apps -Filter 'appmanifest_*.acf' -File -ErrorAction SilentlyContinue)) {
            try {
                $txt = Get-Content -LiteralPath $acf.FullName -Raw -ErrorAction SilentlyContinue
                if (-not $txt) { continue }

                $appid = ''
                if ($txt -match '"appid"\s+"(\d+)"') { $appid = $Matches[1] }

                $name = $acf.BaseName
                if ($txt -match '"name"\s+"([^"]+)"') { $name = $Matches[1] }

                $dir = ''
                if ($txt -match '"installdir"\s+"([^"]+)"') { $dir = $Matches[1] }
                if (-not $dir) { continue }

                $gameDir = Join-Path $apps ('common\' + $dir)
                $games.Add([pscustomobject]@{
                    Id         = "steam-$appid"
                    Name       = $name
                    Source     = 'Steam'
                    AppId      = $appid
                    InstallDir = $dir
                    GameDir    = $gameDir
                    Exists     = (Test-Path -LiteralPath $gameDir)
                })
            } catch { }
        }
    }
    return $games.ToArray()
}

function Get-GSVOtherGames {
    $games = New-Object System.Collections.Generic.List[object]

    # Epic Games
    $epicRoot = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'
    if (Test-Path -LiteralPath $epicRoot) {
        foreach ($f in @(Get-ChildItem -LiteralPath $epicRoot -Filter '*.item' -File -ErrorAction SilentlyContinue)) {
            try {
                $j = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($j.InstallLocation -and (Test-Path -LiteralPath $j.InstallLocation)) {
                    $games.Add([pscustomobject]@{
                        Id         = "epic-$($j.AppName)"
                        Name       = if ($j.DisplayName) { $j.DisplayName } else { $j.AppName }
                        Source     = 'Epic'
                        AppId      = [string]$j.AppName
                        InstallDir = (Split-Path -Leaf $j.InstallLocation)
                        GameDir    = $j.InstallLocation
                        Exists     = $true
                    })
                }
            } catch { }
        }
    }

    # GOG
    foreach ($base in @('HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games', 'HKLM:\SOFTWARE\GOG.com\Games')) {
        if (-not (Test-Path $base)) { continue }
        foreach ($k in @(Get-ChildItem -Path $base -ErrorAction SilentlyContinue)) {
            try {
                $p = Get-ItemProperty -Path $k.PSPath -ErrorAction SilentlyContinue
                if ($p.path -and (Test-Path -LiteralPath $p.path)) {
                    $games.Add([pscustomobject]@{
                        Id         = "gog-$($k.PSChildName)"
                        Name       = if ($p.gameName) { $p.gameName } else { Split-Path -Leaf $p.path }
                        Source     = 'GOG'
                        AppId      = [string]$k.PSChildName
                        InstallDir = (Split-Path -Leaf $p.path)
                        GameDir    = $p.path
                        Exists     = $true
                    })
                }
            } catch { }
        }
    }

    return $games.ToArray()
}

$script:GameFolderBlocklist = @(
    'bin', 'uninstall', 'launcher', 'directxredist', 'directx', 'redist', '_commonredist',
    'commonredist', 'support', 'tools', 'engine', 'data', 'content', 'paks', 'temp-dodi',
    'output', 'uplay_download', 'vcredist', 'dotnet', 'dxsetup', 'installers', 'backup',
    'downloads', 'runtime', 'retail', '_ost', 'steamworks common redistributables',
    'steamworks shared', 'crashreportclient', 'easyanticheat', 'battleye', 'anti-cheat'
)

function Test-GSVLooksLikeGame {
    param([string]$Path)

    $leaf = Split-Path -Leaf $Path
    if ($script:GameFolderBlocklist -contains $leaf.ToLowerInvariant()) { return $false }

    try {
        $exeCount = 0
        $bigExe = $false
        $firstName = ''
        foreach ($f in [System.IO.Directory]::EnumerateFiles($Path, '*.exe', [System.IO.SearchOption]::TopDirectoryOnly)) {
            $exeCount++
            if (-not $firstName) { $firstName = [System.IO.Path]::GetFileNameWithoutExtension($f) }
            try { if ((New-Object System.IO.FileInfo($f)).Length -ge 1MB) { $bigExe = $true } } catch { }
            if ($exeCount -ge 4) { break }
        }
        if ($bigExe -or $exeCount -ge 2) { return $true }

        foreach ($n in @(
            'Binaries', 'Engine', 'Data', 'Data_Final', 'Bin', 'Retail', 'Content', 'Paks',
            'Saved', 'steamapps', 'steam_api64.dll', 'steam_api.dll', 'uplay_install.manifest'
        )) {
            if (Test-Path -LiteralPath (Join-Path $Path $n)) { return $true }
        }

        if ($exeCount -ge 1) {
            if ($firstName -notmatch '^(unins|setup|install|redist|dxsetup|vcredist|launcher|crash|report|update|clean)') {
                return $true
            }
        }
    } catch { }
    return $false
}

function Get-GSVFolderGames {
    param($Settings)
    if (-not $Settings) { $Settings = Get-GSVSettings }

    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($r in @($Settings.GameScanRoots)) {
        if ($r) { $roots.Add($r) }
    }
    foreach ($lib in (Get-GSVSteamLibraries)) {
        $roots.Add((Join-Path $lib 'steamapps\common'))
    }

    $games = New-Object System.Collections.Generic.List[object]
    $seen = @{}

    foreach ($root in @($roots | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $root)) { continue }

        foreach ($d in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
            if ($script:GameFolderBlocklist -contains $d.Name.ToLowerInvariant()) { continue }

            $candidates = New-Object System.Collections.Generic.List[object]
            $candidates.Add($d)

            if (-not (Test-GSVLooksLikeGame -Path $d.FullName)) {
                foreach ($d2 in @(Get-ChildItem -LiteralPath $d.FullName -Directory -ErrorAction SilentlyContinue)) {
                    $candidates.Add($d2)
                }
            }

            foreach ($c in $candidates) {
                if (-not (Test-GSVLooksLikeGame -Path $c.FullName)) { continue }
                $key = $c.FullName.TrimEnd('\').ToLowerInvariant()
                if ($seen.ContainsKey($key)) { continue }

                # Skip a folder that is already covered by a detected parent game.
                $nested = $false
                foreach ($existing in $seen.Keys) {
                    if ($key.StartsWith($existing + '\', [StringComparison]::OrdinalIgnoreCase)) { $nested = $true; break }
                }
                if ($nested) { continue }

                $seen[$key] = $true

                $games.Add([pscustomobject]@{
                    Id         = 'folder-' + (ConvertTo-GSVNormalName -Name $c.Name)
                    Name       = $c.Name
                    Source     = 'Folder'
                    AppId      = $null
                    InstallDir = $c.Name
                    GameDir    = $c.FullName
                    Exists     = $true
                })
            }
        }
    }
    return $games.ToArray()
}

function Get-GSVAllGames {
    param(
        $Settings,
        [switch]$NoLocations
    )
    if (-not $Settings) { $Settings = Get-GSVSettings }

    $games = New-Object System.Collections.Generic.List[object]
    $seenDirs = @{}

    $all = @()
    $all += @(Get-GSVSteamGames)
    $all += @(Get-GSVOtherGames)
    $all += @(Get-GSVFolderGames -Settings $Settings)

    foreach ($g in $all) {
        if (-not $g.GameDir) { continue }
        $key = $g.GameDir.TrimEnd('\').ToLowerInvariant()
        if ($seenDirs.ContainsKey($key)) { continue }
        $seenDirs[$key] = $true
        $games.Add($g)
    }

    $catalog = Get-GSVCatalog
    foreach ($g in $games) {
        $entry = Find-GSVCatalogEntry -Game $g -Catalog $catalog
        $g | Add-Member -NotePropertyName CatalogEntry -NotePropertyValue $entry -Force

        if (-not $NoLocations) {
            $locs = @(Get-GSVGameSaveLocations -Game $g -CatalogEntry $entry -Settings $Settings)
            $g | Add-Member -NotePropertyName Locations -NotePropertyValue $locs -Force
        }
    }
    return $games.ToArray()
}

#endregion

#region ---------------------------------------------------------------- save-location resolution

function Get-GSVGameSaveLocations {
    param(
        [Parameter(Mandatory)]$Game,
        $CatalogEntry,
        $Settings,
        [hashtable]$TokenTable,
        [switch]$IncludeMissing,
        [switch]$NoSize
    )
    if (-not $Settings) { $Settings = Get-GSVSettings }
    if (-not $TokenTable) { $TokenTable = Get-GSVTokenTable }

    # Local copy so we can add a per-game GAMEDIR token without mutating the caller's table.
    $table = @{}
    foreach ($k in $TokenTable.Keys) { $table[$k] = $TokenTable[$k] }
    if ($Game.GameDir) { $table['GAMEDIR'] = $Game.GameDir }

    $names = New-Object System.Collections.Generic.List[string]
    if ($Game.Name) { $names.Add([string]$Game.Name) }
    if ($CatalogEntry) {
        $names.Add([string]$CatalogEntry.Name)
        foreach ($a in @($CatalogEntry.Aliases)) { if ($a) { $names.Add([string]$a) } }
    }

    $appIds = New-Object System.Collections.Generic.List[string]
    if ($Game.AppId -and ([string]$Game.AppId -match '^\d+$')) { $appIds.Add([string]$Game.AppId) }
    if ($CatalogEntry) {
        foreach ($id in @($CatalogEntry.SteamAppIds)) {
            if ([string]$id -match '^\d+$') { $appIds.Add([string]$id) }
        }
    }
    $appIds = @($appIds | Select-Object -Unique)

    $patterns = New-Object System.Collections.Generic.List[object]

    # --- 1. curated catalog paths ------------------------------------------------
    if ($CatalogEntry) {
        foreach ($p in @($CatalogEntry.Paths)) {
            if ($p) {
                $patterns.Add([pscustomobject]@{ Pattern = [string]$p; Note = 'known location'; Origin = 'catalog' })
            }
        }
    }

    # --- 2. Steam userdata + scene/emulator save folders -------------------------
    foreach ($id in $appIds) {
        # Steam saves live under userdata\<Steam64ID>\<appid>\remote, so probe
        # every account folder (a fresh install may have a different account id).
        # The glob also matches a plain userdata\<appid> layout.
        $patterns.Add([pscustomobject]@{ Pattern = "%STEAMUSERDATA%\*\$id";                    Note = "Steam userdata ($id)";   Origin = 'steam' })
        $patterns.Add([pscustomobject]@{ Pattern = "%PUBLICDOCS%\Steam\CODEX\$id";          Note = 'CODEX save folder';      Origin = 'scene' })
        $patterns.Add([pscustomobject]@{ Pattern = "%PUBLICDOCS%\Steam\RUNE\$id";           Note = 'RUNE save folder';       Origin = 'scene' })
        $patterns.Add([pscustomobject]@{ Pattern = "%PUBLICDOCS%\Steam\PLAZA\$id";          Note = 'PLAZA save folder';      Origin = 'scene' })
        $patterns.Add([pscustomobject]@{ Pattern = "%PUBLICDOCS%\Steam\ALI213\$id";         Note = 'ALI213 save folder';     Origin = 'scene' })
        $patterns.Add([pscustomobject]@{ Pattern = "%PUBLICDOCS%\EMPRESS\$id";              Note = 'EMPRESS save folder';    Origin = 'scene' })
        $patterns.Add([pscustomobject]@{ Pattern = "%PROGRAMDATA%\Steam\CODEX\$id";         Note = 'CODEX save folder (ProgramData)'; Origin = 'scene' })
        $patterns.Add([pscustomobject]@{ Pattern = "%DOCUMENTS%\CPY_SAVES\$id";             Note = 'CPY save folder';        Origin = 'scene' })
        $patterns.Add([pscustomobject]@{ Pattern = "%APPDATA%\CPY_SAVES\$id";               Note = 'CPY save folder';        Origin = 'scene' })
        $patterns.Add([pscustomobject]@{ Pattern = "%LOCALAPPDATA%\CPY_SAVES\$id";          Note = 'CPY save folder';        Origin = 'scene' })
        $patterns.Add([pscustomobject]@{ Pattern = "%PROGRAMDATA%\CPY_SAVES\$id";           Note = 'CPY save folder';        Origin = 'scene' })
        $patterns.Add([pscustomobject]@{ Pattern = "%APPDATA%\RELOADED\$id";                Note = 'RELOADED save folder';   Origin = 'scene' })
        $patterns.Add([pscustomobject]@{ Pattern = "%APPDATA%\SKIDROW\$id";                 Note = 'SKIDROW save folder';    Origin = 'scene' })
        $patterns.Add([pscustomobject]@{ Pattern = "%DOCUMENTS%\SKIDROW\$id";               Note = 'SKIDROW save folder';    Origin = 'scene' })
        $patterns.Add([pscustomobject]@{ Pattern = "%PROGRAMDATA%\SKIDROW\$id";             Note = 'SKIDROW save folder';    Origin = 'scene' })
        $patterns.Add([pscustomobject]@{ Pattern = "%APPDATA%\3DMGAME\$id";                 Note = '3DM save folder';        Origin = 'scene' })
        $patterns.Add([pscustomobject]@{ Pattern = "%DOCUMENTS%\3DMGAME\$id";               Note = '3DM save folder';        Origin = 'scene' })
        $patterns.Add([pscustomobject]@{ Pattern = "%PROGRAMDATA%\3DMGAME\$id";             Note = '3DM save folder';        Origin = 'scene' })
        $patterns.Add([pscustomobject]@{ Pattern = "%APPDATA%\Goldberg SteamEmu Saves\$id"; Note = 'Goldberg emu saves';     Origin = 'emu' })
        $patterns.Add([pscustomobject]@{ Pattern = "%APPDATA%\GSE Saves\$id";               Note = 'GSE emu saves';          Origin = 'emu' })
        $patterns.Add([pscustomobject]@{ Pattern = "%LOCALAPPDATA%\GSE Saves\$id";          Note = 'GSE emu saves';          Origin = 'emu' })
        $patterns.Add([pscustomobject]@{ Pattern = "%PROGRAMDATA%\GSE Saves\$id";           Note = 'GSE emu saves';          Origin = 'emu' })
        $patterns.Add([pscustomobject]@{ Pattern = "%APPDATA%\SmartSteamEmu\$id";           Note = 'SmartSteamEmu saves';    Origin = 'emu' })
    }

    # --- 3. folders inside the game install --------------------------------------
    if ($Game.GameDir -and (Test-Path -LiteralPath $Game.GameDir)) {
        foreach ($sub in @(
            'Save','Saves','save','saves','SaveGame','SaveGames','savegame','savegames',
            'Saved','Saved Games','Profile','Profiles','profile','SaveData','UserData',
            'userdata','Data\Save','Data\Saves','Binaries\Save','steam_settings'
        )) {
            $patterns.Add([pscustomobject]@{ Pattern = ('%GAMEDIR%\' + $sub); Note = 'inside game folder'; Origin = 'heuristic' })
        }
    }

    # --- 4. name-matched folders in the usual per-user save roots -----------------
    $searchRoots = @(
        @{ Token = 'DOCUMENTS';    Sub = 'My Games' },
        @{ Token = 'DOCUMENTS';    Sub = '' },
        @{ Token = 'SAVEDGAMES';   Sub = '' },
        @{ Token = 'APPDATA';      Sub = '' },
        @{ Token = 'LOCALAPPDATA'; Sub = '' }
    )

    foreach ($sr in $searchRoots) {
        $root = $table[$sr.Token]
        if (-not $root) { continue }
        $dir = if ($sr.Sub) { Join-Path $root $sr.Sub } else { $root }
        if (-not (Test-Path -LiteralPath $dir)) { continue }

        foreach ($d in @(Get-ChildItem -LiteralPath $dir -Directory -ErrorAction SilentlyContinue)) {
            if ($script:FolderBlocklist -contains $d.Name.ToLowerInvariant()) { continue }

            $matched = $false
            foreach ($n in $names) {
                if (Test-GSVNameSimilar -A $d.Name -B $n) { $matched = $true; break }
            }
            if (-not $matched) { continue }

            $rel = if ($sr.Sub) { Join-Path $sr.Sub $d.Name } else { $d.Name }
            $patterns.Add([pscustomobject]@{
                Pattern = ('%' + $sr.Token + '%\' + $rel)
                Note    = 'name-matched: ' + $d.Name
                Origin  = 'name-match'
            })
        }
    }

    # --- 5. Unity / LocalLow two-level layout ------------------------------------
    $low = $table['LOCALLOW']
    if ($low -and (Test-Path -LiteralPath $low)) {
        foreach ($company in @(Get-ChildItem -LiteralPath $low -Directory -ErrorAction SilentlyContinue)) {
            foreach ($product in @(Get-ChildItem -LiteralPath $company.FullName -Directory -ErrorAction SilentlyContinue)) {
                $matched = $false
                foreach ($n in $names) {
                    if ((Test-GSVNameSimilar -A $product.Name -B $n) -or
                        (Test-GSVNameSimilar -A ($company.Name + ' ' + $product.Name) -B $n)) {
                        $matched = $true; break
                    }
                }
                if ($matched) {
                    $patterns.Add([pscustomobject]@{
                        Pattern = ('%LOCALLOW%\' + $company.Name + '\' + $product.Name)
                        Note    = 'Unity / LocalLow: ' + $company.Name + '\' + $product.Name
                        Origin  = 'name-match'
                    })
                }
            }
        }
    }

    # --- 6. resolve every pattern ------------------------------------------------
    $locations = New-Object System.Collections.Generic.List[object]
    $seen = @{}

    foreach ($p in $patterns) {
        $resolvedItems = @(Resolve-GSVPathPattern -Pattern $p.Pattern -TokenTable $table)

        if ($resolvedItems.Count -eq 0) {
            if ($IncludeMissing) {
                $expanded = Expand-GSVToken -Path $p.Pattern -TokenTable $table
                if ($expanded -notmatch '%[A-Z]+%') {
                    $anchor = Get-GSVPathAnchor -ResolvedPath $expanded -TokenTable $table
                    $key = ("{0}|{1}" -f $anchor.Token, $anchor.Relative).ToLowerInvariant()
                    if (-not $seen.ContainsKey($key)) {
                        $seen[$key] = $true
                        $locations.Add([pscustomobject]@{
                            GameId         = [string]$Game.Id
                            GameName       = [string]$Game.Name
                            Source         = [string]$Game.Source
                            AppId          = if ($appIds.Count) { $appIds[0] } else { '' }
                            InstallDirHint = if ($Game.GameDir) { Split-Path -Leaf $Game.GameDir } else { '' }
                            Token          = $anchor.Token
                            RelativePath   = $anchor.Relative
                            ResolvedPath   = $expanded
                            Kind           = 'Directory'
                            Note           = $p.Note
                            Origin         = $p.Origin
                            Exists         = $false
                            FileCount      = 0
                            Bytes          = [int64]0
                        })
                    }
                }
            }
            continue
        }

        foreach ($path in $resolvedItems) {
            if (-not $path) { continue }
            if ($Settings.BackupRoot -and $path.StartsWith($Settings.BackupRoot, [StringComparison]::OrdinalIgnoreCase)) { continue }

            $anchor = Get-GSVPathAnchor -ResolvedPath $path -TokenTable $table
            $key = ("{0}|{1}" -f $anchor.Token, $anchor.Relative).ToLowerInvariant()
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true

            $isFile = $false
            try { $isFile = (Test-Path -LiteralPath $path -PathType Leaf) } catch { }

            $size = $null
            if (-not $NoSize) { $size = Measure-GSVPathSize -Path $path }

            $locations.Add([pscustomobject]@{
                GameId         = [string]$Game.Id
                GameName       = [string]$Game.Name
                Source         = [string]$Game.Source
                AppId          = if ($appIds.Count) { $appIds[0] } else { '' }
                InstallDirHint = if ($Game.GameDir) { Split-Path -Leaf $Game.GameDir } else { '' }
                Token          = $anchor.Token
                RelativePath   = $anchor.Relative
                ResolvedPath   = $path
                Kind           = if ($isFile) { 'File' } else { 'Directory' }
                Note           = $p.Note
                Origin         = $p.Origin
                Exists         = $true
                FileCount      = if ($size) { $size.Files } else { $null }
                Bytes          = if ($size) { $size.Bytes } else { $null }
            })
        }
    }

    # --- 7. registry keys (backed up separately) ---------------------------------
    if ($CatalogEntry) {
        foreach ($rk in @($CatalogEntry.RegistryKeys)) {
            if (-not $rk) { continue }
            $exists = Test-GSVRegistryKey -Key $rk
            if ($exists -or $IncludeMissing) {
                $locations.Add([pscustomobject]@{
                    GameId         = [string]$Game.Id
                    GameName       = [string]$Game.Name
                    Source         = [string]$Game.Source
                    AppId          = if ($appIds.Count) { $appIds[0] } else { '' }
                    InstallDirHint = if ($Game.GameDir) { Split-Path -Leaf $Game.GameDir } else { '' }
                    Token          = $null
                    RelativePath   = ''
                    ResolvedPath   = ''
                    Kind           = 'Registry'
                    RegistryKey    = [string]$rk
                    Note           = 'registry settings'
                    Origin         = 'catalog'
                    Exists         = $exists
                    FileCount      = 0
                    Bytes          = [int64]0
                })
            }
        }
    }

    # --- 8. drop nested duplicates inside the same game --------------------------
    $sorted = @($locations | Sort-Object @{ Expression = { if ($_.ResolvedPath) { $_.ResolvedPath.Length } else { 0 } } })
    $final = New-Object System.Collections.Generic.List[object]
    foreach ($loc in $sorted) {
        if ($loc.Kind -eq 'Registry' -or -not $loc.ResolvedPath) { $final.Add($loc); continue }

        $nested = $false
        foreach ($f in $final) {
            if ($f.Kind -eq 'Registry' -or -not $f.ResolvedPath) { continue }
            if ($f.Kind -ne 'Directory') { continue }
            if ($loc.ResolvedPath.Equals($f.ResolvedPath, [StringComparison]::OrdinalIgnoreCase)) { $nested = $true; break }
            if ($loc.ResolvedPath.StartsWith($f.ResolvedPath.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
                $nested = $true; break
            }
        }
        if (-not $nested) { $final.Add($loc) }
    }

    return $final.ToArray()
}

#endregion

#region ---------------------------------------------------------------- windows.old

function Get-GSVWindowsOldRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    try {
        foreach ($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
            if (-not $d.Root) { continue }
            $p = Join-Path $d.Root 'Windows.old'
            if (Test-Path -LiteralPath $p) {
                $full = (Get-Item -LiteralPath $p -ErrorAction SilentlyContinue).FullName
                if ($full -and -not $roots.Contains($full)) { $roots.Add($full) }
            }
        }
    } catch { }
    return $roots.ToArray()
}

function Get-GSVWindowsOldProfiles {
    param([Parameter(Mandatory)][string]$Root)

    $profiles = New-Object System.Collections.Generic.List[object]
    $usersDir = Join-Path $Root 'Users'
    if (-not (Test-Path -LiteralPath $usersDir)) { return @() }

    $skip = @('public', 'default', 'default user', 'all users', 'defaultaccount', 'wdagutilityaccount')

    foreach ($u in @(Get-ChildItem -LiteralPath $usersDir -Directory -ErrorAction SilentlyContinue)) {
        if ($skip -contains $u.Name.ToLowerInvariant()) { continue }

        $profilePath = $u.FullName
        $documents = Join-Path $profilePath 'Documents'
        if (-not (Test-Path -LiteralPath $documents)) {
            $oneDriveDocs = Join-Path $profilePath 'OneDrive\Documents'
            if (Test-Path -LiteralPath $oneDriveDocs) {
                $documents = $oneDriveDocs
            } else {
                $od = @(Get-ChildItem -LiteralPath $profilePath -Directory -Filter 'OneDrive*' -ErrorAction SilentlyContinue)
                foreach ($o in $od) {
                    $cand = Join-Path $o.FullName 'Documents'
                    if (Test-Path -LiteralPath $cand) { $documents = $cand; break }
                }
            }
        }

        $savedGames = Join-Path $profilePath 'Saved Games'
        if (-not (Test-Path -LiteralPath $savedGames)) {
            # Saved Games can be relocated; fall back to the well-known GUID under the old profile.
            $savedGames = Join-Path $profilePath 'Saved Games'
        }

        $public = Join-Path $Root 'Users\Public'
        $programData = Join-Path $Root 'ProgramData'

        $profiles.Add([pscustomobject]@{
            Name            = $u.Name
            ProfilePath     = $profilePath
            AppData         = (Join-Path $profilePath 'AppData\Roaming')
            LocalAppData    = (Join-Path $profilePath 'AppData\Local')
            LocalLow        = (Join-Path $profilePath 'AppData\LocalLow')
            Documents       = $documents
            SavedGames      = $savedGames
            Public          = $public
            PublicDocuments = (Join-Path $public 'Documents')
            ProgramData     = $programData
            SteamUserData   = (Get-GSVOldSteamUserData -ProfilePath $profilePath)
        })
    }
    return $profiles.ToArray()
}

function Get-GSVOldSteamUserData {
    param([string]$ProfilePath)
    # Steam is usually installed outside the profile; if it was on C: it may live
    # inside Windows.old as well. Try the common locations.
    $candidates = @(
        (Join-Path $ProfilePath 'AppData\Local\Steam\userdata'),
        (Join-Path $ProfilePath 'Steam\userdata')
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return ''
}

function Get-GSVOldTokenTable {
    param($Profile)
    return (Get-GSVTokenTable -Override @{
        'USERPROFILE'   = $Profile.ProfilePath
        'APPDATA'       = $Profile.AppData
        'LOCALAPPDATA'  = $Profile.LocalAppData
        'LOCALLOW'      = $Profile.LocalLow
        'DOCUMENTS'     = $Profile.Documents
        'SAVEDGAMES'    = $Profile.SavedGames
        'PUBLIC'        = $Profile.Public
        'PUBLICDOCS'    = $Profile.PublicDocuments
        'PROGRAMDATA'   = $Profile.ProgramData
        'STEAMUSERDATA' = $Profile.SteamUserData
        'GAMEDIR'       = ''
    })
}

function Test-GSVSaveLikeFolder {
    param([string]$Path)
    foreach ($sub in @(
        'Save','Saves','save','saves','SaveGame','SaveGames','savegame','savegames',
        'Saved','Profiles','Profile','PlayerProfiles','SaveData','UserData','userdata'
    )) {
        if (Test-Path -LiteralPath (Join-Path $Path $sub)) { return $true }
    }
    try {
        $n = 0
        foreach ($f in [System.IO.Directory]::EnumerateFiles($Path, '*.*', [System.IO.SearchOption]::TopDirectoryOnly)) {
            if ($f -match '\.(sav|save|profile|slot|dat|sl2|lsv|es3)$') { return $true }
            $n++
            if ($n -ge 200) { break }
        }
    } catch { }
    return $false
}

function Get-GSVWindowsOldLocations {
    param(
        [Parameter(Mandatory)][string]$Root,
        [string[]]$Games = @(),
        [switch]$NoSize
    )

    $all = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $profiles = @(Get-GSVWindowsOldProfiles -Root $Root)
    if ($profiles.Count -eq 0) { return @() }

    $catalog = Get-GSVCatalog

    foreach ($prof in $profiles) {
        $table = Get-GSVOldTokenTable -Profile $prof

        $add = {
            param($pattern, $note, $origin, $gameName, $gameId)
            foreach ($path in @(Resolve-GSVPathPattern -Pattern $pattern -TokenTable $table)) {
                if (-not $path) { continue }
                $anchor = Get-GSVPathAnchor -ResolvedPath $path -TokenTable $table
                if (-not $anchor.Token) { continue }
                $key = ("{0}|{1}" -f $anchor.Token, $anchor.Relative).ToLowerInvariant()
                if ($seen.ContainsKey($key)) { continue }
                $seen[$key] = $true

                $isFile = $false
                try { $isFile = (Test-Path -LiteralPath $path -PathType Leaf) } catch { }

                $size = $null
                if (-not $NoSize) { $size = Measure-GSVPathSize -Path $path }

                $all.Add([pscustomobject]@{
                    GameId         = $gameId
                    GameName       = $gameName
                    Source         = 'Windows.old'
                    AppId          = ''
                    InstallDirHint = ''
                    Token          = $anchor.Token
                    RelativePath   = $anchor.Relative
                    ResolvedPath   = $path
                    Kind           = if ($isFile) { 'File' } else { 'Directory' }
                    Note           = $note
                    Origin         = $origin
                    Exists         = $true
                    FileCount      = if ($size) { $size.Files } else { $null }
                    Bytes          = if ($size) { $size.Bytes } else { $null }
                })
            }
        }

        # 1. Every curated catalog game, resolved against the OLD profile.
        foreach ($entry in $catalog) {
            if ($Games.Count -gt 0) {
                $hit = $false
                foreach ($g in $Games) { if (Test-GSVNameSimilar -A $entry.Name -B $g) { $hit = $true; break } }
                if (-not $hit) { continue }
            }
            $pseudo = [pscustomobject]@{
                Id = $entry.Id; Name = $entry.Name; Source = 'Windows.old'; AppId = $null; GameDir = ''; Exists = $false
            }
            foreach ($loc in @(Get-GSVGameSaveLocations -Game $pseudo -CatalogEntry $entry -TokenTable $table -NoSize)) {
                if ($loc.Kind -eq 'Registry' -or -not $loc.Exists) { continue }
                $key = ("{0}|{1}" -f $loc.Token, $loc.RelativePath).ToLowerInvariant()
                if ($seen.ContainsKey($key)) { continue }
                $seen[$key] = $true
                $all.Add($loc)
            }
        }

        # 2. Wholesale safe roots that only ever contain game data.
        foreach ($sub in @(Get-ChildItem -LiteralPath (Join-Path $prof.Documents 'My Games') -Directory -ErrorAction SilentlyContinue)) {
            & $add ('%DOCUMENTS%\My Games\' + $sub.Name) 'My Games folder' 'windows.old' $sub.Name ('old-' + $sub.Name)
        }
        foreach ($sub in @(Get-ChildItem -LiteralPath $prof.SavedGames -Directory -ErrorAction SilentlyContinue)) {
            & $add ('%SAVEDGAMES%\' + $sub.Name) 'Saved Games folder' 'windows.old' $sub.Name ('old-' + $sub.Name)
        }
        if (Test-Path -LiteralPath $prof.LocalLow) {
            foreach ($company in @(Get-ChildItem -LiteralPath $prof.LocalLow -Directory -ErrorAction SilentlyContinue)) {
                foreach ($product in @(Get-ChildItem -LiteralPath $company.FullName -Directory -ErrorAction SilentlyContinue)) {
                    & $add ('%LOCALLOW%\' + $company.Name + '\' + $product.Name) 'LocalLow (Unity) folder' 'windows.old' $product.Name ('old-' + $product.Name)
                }
            }
        }

        # 3. Steam userdata: every account / appid is game data only.
        if ($prof.SteamUserData -and (Test-Path -LiteralPath $prof.SteamUserData)) {
            foreach ($acct in @(Get-ChildItem -LiteralPath $prof.SteamUserData -Directory -ErrorAction SilentlyContinue)) {
                if ($acct.Name -notmatch '^\d+$') { continue }
                foreach ($app in @(Get-ChildItem -LiteralPath $acct.FullName -Directory -ErrorAction SilentlyContinue)) {
                    if ($app.Name -notmatch '^\d+$') { continue }
                    & $add ('%STEAMUSERDATA%\' + $acct.Name + '\' + $app.Name) 'Steam userdata' 'windows.old' ('Steam app ' + $app.Name) ('steam-' + $app.Name)
                }
            }
        }

        # 4. Scene / emulator save roots.
        foreach ($emu in @(
            @{ P = '%APPDATA%\Goldberg SteamEmu Saves'; N = 'Goldberg emu saves' },
            @{ P = '%APPDATA%\SmartSteamEmu';           N = 'SmartSteamEmu saves' },
            @{ P = '%PUBLICDOCS%\Steam\CODEX';          N = 'CODEX saves' },
            @{ P = '%PUBLICDOCS%\Steam\RUNE';           N = 'RUNE saves' },
            @{ P = '%PUBLICDOCS%\Steam\ALI213';         N = 'ALI213 saves' },
            @{ P = '%PUBLICDOCS%\EMPRESS';              N = 'EMPRESS saves' },
            @{ P = '%PROGRAMDATA%\Steam\CODEX';         N = 'CODEX saves' }
        )) {
            & $add $emu.P $emu.N 'windows.old' 'Scene/emulator saves' 'scene'
        }

        # 4b. Console emulator saves (eden / ryujinx / eglantine / kyty / shadPS4).
        foreach ($loc in @(Get-GSVEmulatorSaveLocations -NoSize -TokenTable $table)) {
            $key = ("{0}|{1}" -f $loc.Token, $loc.RelativePath).ToLowerInvariant()
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            $all.Add($loc)
        }

        # 5. Heuristic scan of AppData for save-like game folders.
        foreach ($pair in @(
            @{ Root = $prof.LocalAppData; Token = 'LOCALAPPDATA' },
            @{ Root = $prof.AppData;      Token = 'APPDATA' }
        )) {
            if (-not (Test-Path -LiteralPath $pair.Root)) { continue }
            foreach ($d in @(Get-ChildItem -LiteralPath $pair.Root -Directory -ErrorAction SilentlyContinue)) {
                if ($script:FolderBlocklist -contains $d.Name.ToLowerInvariant()) { continue }
                if (-not (Test-GSVSaveLikeFolder -Path $d.FullName)) { continue }
                & $add ('%' + $pair.Token + '%\' + $d.Name) 'save-like folder in AppData' 'windows.old' $d.Name ('old-' + $d.Name)
            }
        }

        # 6. Loose save files sitting directly in Documents.
        if (Test-Path -LiteralPath $prof.Documents) {
            foreach ($f in @(Get-ChildItem -LiteralPath $prof.Documents -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.sav', '.save') })) {
                & $add ('%DOCUMENTS%\' + $f.Name) 'loose save file' 'windows.old' $f.BaseName ('old-' + $f.BaseName)
            }
        }
    }

    return $all.ToArray()
}

#endregion

#region ---------------------------------------------------------------- global / launcher-wide saves

function Get-GSVGlobalSaveLocations {
    param(
        $Settings,
        [switch]$NoSize,
        [hashtable]$TokenTable
    )
    if (-not $Settings) { $Settings = Get-GSVSettings }
    if (-not $TokenTable) { $TokenTable = Get-GSVTokenTable }

    $defs = @(
        @{ P = '%LOCALAPPDATA%\Ubisoft Game Launcher\savegames'; N = 'Ubisoft Connect saves (all games)';        O = 'launcher' }
        @{ P = '%APPDATA%\Goldberg SteamEmu Saves';              N = 'Goldberg emulator saves (all games)';       O = 'emu' }
        @{ P = '%APPDATA%\GSE Saves';                            N = 'GSE / Goldberg saves (all games)';          O = 'emu' }
        @{ P = '%LOCALAPPDATA%\GSE Saves';                       N = 'GSE / Goldberg saves (all games)';          O = 'emu' }
        @{ P = '%PROGRAMDATA%\GSE Saves';                        N = 'GSE / Goldberg saves (all games)';          O = 'emu' }
        @{ P = '%APPDATA%\SmartSteamEmu';                        N = 'SmartSteamEmu saves (all games)';           O = 'emu' }
        @{ P = '%DOCUMENTS%\CPY_SAVES';                          N = 'CPY saves (all games)';                     O = 'scene' }
        @{ P = '%APPDATA%\CPY_SAVES';                            N = 'CPY saves (all games)';                     O = 'scene' }
        @{ P = '%LOCALAPPDATA%\CPY_SAVES';                       N = 'CPY saves (all games)';                     O = 'scene' }
        @{ P = '%PROGRAMDATA%\CPY_SAVES';                        N = 'CPY saves (all games)';                     O = 'scene' }
        @{ P = '%APPDATA%\RELOADED';                             N = 'RELOADED saves (all games)';                O = 'scene' }
        @{ P = '%APPDATA%\SKIDROW';                              N = 'SKIDROW saves (all games)';                 O = 'scene' }
        @{ P = '%DOCUMENTS%\SKIDROW';                            N = 'SKIDROW saves (all games)';                 O = 'scene' }
        @{ P = '%PROGRAMDATA%\SKIDROW';                          N = 'SKIDROW saves (all games)';                 O = 'scene' }
        @{ P = '%APPDATA%\3DMGAME';                              N = '3DM saves (all games)';                     O = 'scene' }
        @{ P = '%DOCUMENTS%\3DMGAME';                            N = '3DM saves (all games)';                     O = 'scene' }
        @{ P = '%PROGRAMDATA%\3DMGAME';                          N = '3DM saves (all games)';                     O = 'scene' }
        @{ P = '%PUBLICDOCS%\Steam';                             N = 'Scene release saves (CODEX / RUNE / ALI213)'; O = 'scene' }
        @{ P = '%PUBLICDOCS%\EMPRESS';                           N = 'EMPRESS saves (all games)';                 O = 'scene' }
        @{ P = '%PROGRAMDATA%\Steam\CODEX';                      N = 'CODEX saves in ProgramData';                O = 'scene' }
    )

    foreach ($x in @($Settings.ExtraPaths)) {
        if ($x) { $defs += @{ P = [string]$x; N = 'extra path (from settings.json)'; O = 'extra' } }
    }

    $locations = New-Object System.Collections.Generic.List[object]
    $seen = @{}

    foreach ($d in $defs) {
        foreach ($path in @(Resolve-GSVPathPattern -Pattern $d.P -TokenTable $TokenTable)) {
            if (-not $path) { continue }
            $anchor = Get-GSVPathAnchor -ResolvedPath $path -TokenTable $TokenTable
            $key = ("{0}|{1}" -f $anchor.Token, $anchor.Relative).ToLowerInvariant()
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true

            $isFile = $false
            try { $isFile = (Test-Path -LiteralPath $path -PathType Leaf) } catch { }

            $size = $null
            if (-not $NoSize) { $size = Measure-GSVPathSize -Path $path }

            $locations.Add([pscustomobject]@{
                GameId         = 'global'
                GameName       = 'Global launcher / emulator saves'
                Source         = 'Global'
                AppId          = ''
                InstallDirHint = ''
                Token          = $anchor.Token
                RelativePath   = $anchor.Relative
                ResolvedPath   = $path
                Kind           = if ($isFile) { 'File' } else { 'Directory' }
                Note           = $d.N
                Origin         = $d.O
                Exists         = $true
                FileCount      = if ($size) { $size.Files } else { $null }
                Bytes          = if ($size) { $size.Bytes } else { $null }
            })
        }
    }

    # Drop folders already contained in a parent we are backing up.
    $sorted = @($locations | Sort-Object @{ Expression = { if ($_.ResolvedPath) { $_.ResolvedPath.Length } else { 0 } } })
    $final = New-Object System.Collections.Generic.List[object]
    foreach ($loc in $sorted) {
        $nested = $false
        foreach ($f in $final) {
            if (-not $f.ResolvedPath) { continue }
            if ($loc.ResolvedPath.Equals($f.ResolvedPath, [StringComparison]::OrdinalIgnoreCase) -or
                $loc.ResolvedPath.StartsWith($f.ResolvedPath.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
                $nested = $true; break
            }
        }
        if (-not $nested) { $final.Add($loc) }
    }
    return $final.ToArray()
}

#region ---------------------------------------------------------------- console emulators (Switch / PS5)

# Save folders that the big console emulators keep outside the game folder.
# These are *not* catalog games: per-game folders exist under a save root, keyed
# by a title ID instead of a game name (16 hex digits for Nintendo Switch, a
# PPSA/CUSA id for PlayStation). The functions below enumerate every one of
# them so a normal backup covers them, and index them by title ID so saves can
# be migrated between emulators (Eden <-> Ryujinx <-> Eglantine, Kyty <-> KytyPS5).

function Get-GSVEmulatorDefinitions {
    return @(
        [pscustomobject]@{
            Id = 'eden'; Name = 'Eden'; Console = 'Nintendo Switch'
            DataDirPatterns = @('%APPDATA%\eden', '%LOCALAPPDATA%\eden')
            SaveRoots = @('nand\user\save', 'nand\system\save')
            TitlePattern = '^[0-9a-fA-F]{16}$'; TitleNoun = 'Switch title'
        }
        [pscustomobject]@{
            Id = 'eglantine'; Name = 'Eglantine'; Console = 'Nintendo Switch'
            DataDirPatterns = @('%APPDATA%\eglantine', '%LOCALAPPDATA%\eglantine', '%APPDATA%\Eglantine', '%LOCALAPPDATA%\Eglantine')
            SaveRoots = @('nand\user\save', 'nand\system\save')
            TitlePattern = '^[0-9a-fA-F]{16}$'; TitleNoun = 'Switch title'
        }
        [pscustomobject]@{
            Id = 'ryujinx'; Name = 'Ryujinx'; Console = 'Nintendo Switch'
            DataDirPatterns = @('%APPDATA%\ryujinx', '%LOCALAPPDATA%\ryujinx', '%APPDATA%\Ryujinx', '%LOCALAPPDATA%\Ryujinx')
            SaveRoots = @('bis\user\save', 'bis\system\save')
            TitlePattern = '^[0-9a-fA-F]{16}$'; TitleNoun = 'Switch title'
        }
        [pscustomobject]@{
            Id = 'yuzu'; Name = 'Yuzu'; Console = 'Nintendo Switch'
            DataDirPatterns = @('%APPDATA%\yuzu', '%LOCALAPPDATA%\yuzu')
            SaveRoots = @('nand\user\save', 'nand\system\save')
            TitlePattern = '^[0-9a-fA-F]{16}$'; TitleNoun = 'Switch title'
        }
        [pscustomobject]@{
            Id = 'suyu'; Name = 'Suyu'; Console = 'Nintendo Switch'
            DataDirPatterns = @('%APPDATA%\suyu', '%LOCALAPPDATA%\suyu')
            SaveRoots = @('nand\user\save', 'nand\system\save')
            TitlePattern = '^[0-9a-fA-F]{16}$'; TitleNoun = 'Switch title'
        }
        [pscustomobject]@{
            Id = 'kyty'; Name = 'Kyty / KytyPS5'; Console = 'PlayStation 5'
            DataDirPatterns = @('%APPDATA%\Kyty', '%APPDATA%\kyty', '%APPDATA%\KytyPS5', '%APPDATA%\kytyps5',
                                '%LOCALAPPDATA%\Kyty', '%LOCALAPPDATA%\kyty', '%LOCALAPPDATA%\KytyPS5', '%LOCALAPPDATA%\kytyps5')
            SaveRoots = @('_SaveData')
            TitlePattern = '^(PPSA|CUSA)\d{4,6}$'; TitleNoun = 'PS5 title'
        }
        [pscustomobject]@{
            Id = 'shadps4'; Name = 'shadPS4'; Console = 'PlayStation 4'
            DataDirPatterns = @('%APPDATA%\shadPS4', '%LOCALAPPDATA%\shadPS4')
            SaveRoots = @('user\*\savedata')
            TitlePattern = '^(PPSA|CUSA)\d{4,6}$'; TitleNoun = 'PS4 title'
        }
    )
}

function Get-GSVEmulatorDirs {
    param(
        [string[]]$EmulatorIds,
        [hashtable]$TokenTable,
        [switch]$IncludePortable
    )
    if (-not $TokenTable) { $TokenTable = Get-GSVTokenTable }

    $defs = @(Get-GSVEmulatorDefinitions)
    if ($EmulatorIds -and $EmulatorIds.Count -gt 0) {
        $defs = @($defs | Where-Object { $EmulatorIds -contains $_.Id })
    }

    $found = New-Object System.Collections.Generic.List[object]
    $seen = @{}

    # 1. standard per-user locations (%APPDATA% / %LOCALAPPDATA%)
    foreach ($def in $defs) {
        foreach ($pattern in @($def.DataDirPatterns)) {
            foreach ($path in @(Resolve-GSVPathPattern -Pattern $pattern -TokenTable $TokenTable)) {
                if (-not $path) { continue }
                $key = ("{0}|{1}" -f $def.Id, $path.ToLowerInvariant())
                if ($seen.ContainsKey($key)) { continue }
                $seen[$key] = $true
                $found.Add([pscustomobject]@{ Emulator = $def; DataDir = $path; Origin = 'appdata' })
            }
        }
    }

    # 2. portable installs: emulator folder anywhere next to an .exe, found by a
    #    shallow walk of every drive root and the configured game folders.
    if ($IncludePortable) {
        $portableNames = @{
            'eden' = 'eden'; 'eglantine' = 'eglantine'; 'ryujinx' = 'ryujinx'
            'yuzu' = 'yuzu'; 'suyu' = 'suyu'; 'kyty' = 'kyty'; 'kytyps5' = 'kyty'
            'shadps4' = 'shadps4'
        }

        $roots = New-Object System.Collections.Generic.List[string]
        try {
            foreach ($d in @(Get-GSVFixedDriveRoots)) { $roots.Add($d) }
        } catch { }
        try {
            foreach ($g in @(Get-GSVSettings.GameScanRoots)) { if (Test-Path -LiteralPath $g) { $roots.Add($g) } }
        } catch { }

        $visited = 0
        $queue = New-Object System.Collections.Queue
        foreach ($r in $roots) { if ($r) { $queue.Enqueue([pscustomobject]@{ Path = $r.TrimEnd('\'); Depth = 0 }) } }

        while ($queue.Count -gt 0) {
            $node = $queue.Dequeue()
            $path = [string]$node.Path
            $depth = [int]$node.Depth
            $visited++
            if ($visited -gt 60000) { break }

            $leaf = ''
            try { $leaf = Split-Path -Leaf $path } catch { }
            $lower = $leaf.ToLowerInvariant()
            if ($script:DeepPruneNames -and ($script:DeepPruneNames -contains $lower)) { continue }
            if ($lower -ieq '_savedata') {
                # Kyty / KytyPS5 store saves in a portable _SaveData folder next
                # to the exe, whatever the install folder is called.
                $parentDir = ''
                try { $parentDir = Split-Path -Parent $path } catch { }
                $def = @($defs | Where-Object { $_.Id -eq 'kyty' }) | Select-Object -First 1
                if ($def -and $parentDir) {
                    $key = ("{0}|{1}" -f $def.Id, $parentDir.ToLowerInvariant())
                    if (-not $seen.ContainsKey($key)) {
                        $seen[$key] = $true
                        $found.Add([pscustomobject]@{ Emulator = $def; DataDir = $parentDir; Origin = 'portable' })
                    }
                }
            }
            if ($portableNames.ContainsKey($lower)) {
                $emuId = $portableNames[$lower]
                $def = @($defs | Where-Object { $_.Id -eq $emuId }) | Select-Object -First 1
                if ($def) {
                    $key = ("{0}|{1}" -f $def.Id, $path.ToLowerInvariant())
                    if (-not $seen.ContainsKey($key)) {
                        $seen[$key] = $true
                        $found.Add([pscustomobject]@{ Emulator = $def; DataDir = $path; Origin = 'portable' })
                    }
                }
            }

            if ($depth -ge 4) { continue }
            try {
                foreach ($child in [System.IO.Directory]::EnumerateDirectories($path)) {
                    $queue.Enqueue([pscustomobject]@{ Path = $child; Depth = $depth + 1 })
                }
            } catch { }
        }
    }

    return $found.ToArray()
}

function Get-GSVEmulatorSaveIndex {
    param(
        [string[]]$EmulatorIds,
        [hashtable]$TokenTable,
        [switch]$IncludePortable
    )
    if (-not $TokenTable) { $TokenTable = Get-GSVTokenTable }

    $rows = New-Object System.Collections.Generic.List[object]

    foreach ($hit in @(Get-GSVEmulatorDirs -EmulatorIds $EmulatorIds -TokenTable $TokenTable -IncludePortable:$IncludePortable)) {
        $def = $hit.Emulator

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
                            Add-GSVEmulatorSaveEntries -Rows $rows -Def $def -DataDir $hit.DataDir -SaveRoot $candidate -Origin $hit.Origin
                        }
                    }
                }
            } else {
                $candidate = Join-Path $hit.DataDir $saveRoot
                if (Test-Path -LiteralPath $candidate) {
                    Add-GSVEmulatorSaveEntries -Rows $rows -Def $def -DataDir $hit.DataDir -SaveRoot $candidate -Origin $hit.Origin
                }
            }
        }
    }

    # De-duplicate: on a case-insensitive file system, savedata/SaveData/saveData
    # all point at the same folder.
    $seen = @{}
    $final = New-Object System.Collections.Generic.List[object]
    foreach ($row in $rows) {
        $key = ("{0}|{1}|{2}" -f $row.EmulatorId, $row.TitleId, ([string]$row.Path).ToLowerInvariant())
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $final.Add($row)
    }

    return $final.ToArray()
}

function Add-GSVEmulatorSaveEntries {
    param(
        [System.Collections.Generic.List[object]]$Rows,
        $Def,
        [string]$DataDir,
        [string]$SaveRoot,
        [string]$Origin
    )

    # PS5/PS4 style: SaveRoot\<PPSA…\ or <CUSA…\
    $addedFlat = $false
    $flatTitles = @(Get-ChildItem -LiteralPath $SaveRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $Def.TitlePattern })
    foreach ($title in $flatTitles) {
        # A Switch profile folder (SaveRoot\<profile>\<title>) also matches the
        # 16-hex pattern. If a child holds title folders itself, it is a
        # profile container, not a title, so leave it to the 2-level pass.
        $nested = @(Get-ChildItem -LiteralPath $title.FullName -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match $Def.TitlePattern })
        if ($nested.Count -gt 0) { continue }

        $addedFlat = $true
        $Rows.Add([pscustomobject]@{
            EmulatorId = $Def.Id; EmulatorName = $Def.Name; Console = $Def.Console
            TitleId = $title.Name; ProfileId = ''; Path = $title.FullName
            DataDir = $DataDir; SaveRoot = $SaveRoot; Origin = $Origin
        })
    }
    if ($addedFlat) { return }

    # Switch style: SaveRoot\<profile>\<title>
    foreach ($profile in @(Get-ChildItem -LiteralPath $SaveRoot -Directory -ErrorAction SilentlyContinue)) {
        foreach ($title in @(Get-ChildItem -LiteralPath $profile.FullName -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match $Def.TitlePattern })) {
            $Rows.Add([pscustomobject]@{
                EmulatorId = $Def.Id; EmulatorName = $Def.Name; Console = $Def.Console
                TitleId = $title.Name; ProfileId = $profile.Name; Path = $title.FullName
                DataDir = $DataDir; SaveRoot = $SaveRoot; Origin = $Origin
            })
        }
    }
}

function Get-GSVEmulatorSaveLocations {
    param(
        $Settings,
        [switch]$NoSize,
        [hashtable]$TokenTable
    )
    if (-not $Settings) { $Settings = Get-GSVSettings }
    if (-not $TokenTable) { $TokenTable = Get-GSVTokenTable }

    $locations = New-Object System.Collections.Generic.List[object]

    foreach ($row in @(Get-GSVEmulatorSaveIndex -TokenTable $TokenTable -IncludePortable)) {
        $anchor = Get-GSVPathAnchor -ResolvedPath $row.Path -TokenTable $TokenTable
        $size = $null
        if (-not $NoSize) { $size = Measure-GSVPathSize -Path $row.Path }

        $locations.Add([pscustomobject]@{
            GameId         = 'emu-' + $row.EmulatorId + '-' + (ConvertTo-GSVNormalName -Name $row.TitleId)
            GameName       = ("{0} title {1}" -f ($row.Console -replace 'Nintendo ', '' -replace 'PlayStation ', 'PS'), $row.TitleId)
            Source         = $row.EmulatorName
            AppId          = [string]$row.TitleId
            InstallDirHint = ''
            Token          = $anchor.Token
            RelativePath   = $anchor.Relative
            AbsolutePath   = $anchor.Absolute
            ResolvedPath   = $row.Path
            Kind           = 'Directory'
            Note           = ("{0}: {1}" -f $row.EmulatorName, $row.SaveRoot)
            Origin         = 'emulator'
            Exists         = $true
            FileCount      = if ($size) { $size.Files } else { $null }
            Bytes          = if ($size) { $size.Bytes } else { $null }
        })
    }

    return $locations.ToArray()
}

#endregion

#region ---------------------------------------------------------------- deep C: scan

$script:DeepPruneNames = @(
    'windows','winsxs','$recycle.bin','system volume information','recovery','perflogs',
    'msocache','config.msi','$winreagent','program files','program files (x86)',
    'installer','temp','tmp','cache','caches','shadercache','crashreports','crashdumps',
    'node_modules','.git','.svn','.hg','__pycache__','logs','log','packages',
    'package cache','windows.old','microsoft','google','mozilla','chrome','firefox',
    'edge','brave','opera','adobe','nvidia','intel','amd','dropbox','discord','slack',
    'spotify','teams','zoom','skype','telegram','jetbrains','visual studio','vs code',
    'npm','pip','nuget','docker','wsl'
)

$script:DeepContainerNames = @(
    'cpy_saves','cpy saves','gse saves','gse_saves','goldberg steamemu saves',
    'smartsteamemu','reloaded','skidrow','3dmgame','ali213','empress','codex',
    'plaza','rune','prophet','hoodlum','flt','tenoke','razor1911','steamrip',
    '_savedata','savedata'
)

$script:DeepSaveFolderNames = @(
    'saves','save','savegame','savegames','savedata','save data','playerprofiles'
)

$script:DeepPublisherNames = @(
    'rockstar games','wb games','warner bros. games','electronic arts','ubisoft','koeitecmo',
    'koei tecmo','larian studios','cd projekt red','2k games','2k','square enix','sega',
    'capcom','bandai namco','bandai namco entertainment','fromsoftware','bethesda softworks',
    'machinegames','id software','arkane studios','tango gameworks','zenimax','rocksteady',
    'monolith productions','netherrealm studios','take-two interactive','krafton','team ninja',
    'platinumgames','atlus','crystal dynamics','eidos-montreal','io interactive',
    'remedy entertainment','paradox interactive','thq nordic','deep silver','focus entertainment',
    'team17','devolver digital','annapurna interactive','raw fury','coffee stain studios',
    '505 games','private division','humble games','gamemill entertainment','maximum games',
    'modus games','akupara games','playstack','tinybuild'
)

function Get-GSVFixedDriveRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    try {
        foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
            try {
                if ($d.IsReady -and $d.DriveType -eq [System.IO.DriveType]::Fixed) {
                    $roots.Add($d.RootDirectory.FullName)
                }
            } catch { }
        }
    } catch { }
    return $roots.ToArray()
}

function Test-GSVDeepSkipPath {
    param(
        [string]$Path,
        [string]$Vault,
        [string]$AppRoot
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return $true }

    if ($Vault -and $Path.StartsWith($Vault.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ($AppRoot -and $Path.StartsWith($AppRoot.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) { return $true }

    $leaf = ''
    try { $leaf = Split-Path -Leaf $Path } catch { }
    if ($leaf -and ($script:DeepPruneNames -contains $leaf.ToLowerInvariant())) { return $true }

    if ($Path -match '(?i)\\AppData\\Local\\Microsoft(\\|$)')      { return $true }
    if ($Path -match '(?i)\\AppData\\Roaming\\Microsoft(\\|$)')    { return $true }
    if ($Path -match '(?i)\\AppData\\Local\\Temp(\\|$)')           { return $true }
    if ($Path -match '(?i)\\ProgramData\\Microsoft(\\|$)')         { return $true }
    if ($Path -match '(?i)\\ProgramData\\Package Cache(\\|$)')     { return $true }
    if ($Path -match '(?i)\\Windows\.old(\\|$)')                   { return $true }
    return $false
}

function Test-GSVDeepHasSaveFiles {
    param([string]$Path)
    try {
        $n = 0
        foreach ($f in [System.IO.Directory]::EnumerateFiles($Path)) {
            $ext = [System.IO.Path]::GetExtension($f).ToLowerInvariant()
            if ($ext -in @('.sav', '.save', '.sl2', '.lsv', '.es3', '.profile', '.slot')) { return $true }
            $n++
            if ($n -ge 60) { break }
        }
    } catch { }
    return $false
}

function Get-GSVDeepGameName {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return 'Unknown game' }

    $leaf = ''
    try { $leaf = Split-Path -Leaf $Path } catch { }
    if (-not $leaf) { return 'Unknown game' }

    if ($leaf -match '^\d{3,10}$') {
        foreach ($c in @(Get-GSVCatalog)) {
            foreach ($id in @($c.SteamAppIds)) {
                if ([string]$id -eq $leaf) { return [string]$c.Name }
            }
        }
        return "Steam app $leaf"
    }

    $parent = ''
    try { $parent = Split-Path -Leaf (Split-Path -Parent $Path) } catch { }

    if ($leaf -ieq 'wgs') {
        try {
            $pkg = Split-Path -Leaf (Split-Path -Parent (Split-Path -Parent $Path))
            if ($pkg) { return $pkg }
        } catch { }
    }
    if ($leaf -ieq 'LocalState') {
        try {
            $pkg = Split-Path -Leaf (Split-Path -Parent $Path)
            if ($pkg) { return $pkg }
        } catch { }
    }

    if ($script:DeepSaveFolderNames -contains $leaf.ToLowerInvariant() -and $parent) { return $parent }
    if ($parent -ieq 'My Games' -or $parent -ieq 'Saved Games' -or $parent -ieq 'Documents') { return $leaf }

    return $leaf
}

function Get-GSVDeepScanLocations {
    param(
        [string[]]$Roots,
        [int]$MaxDepth = 10,
        [int]$MaxResults = 500,
        [int]$MaxFolders = 200000,
        [switch]$NoSize,
        [scriptblock]$Progress
    )

    if (-not $Roots -or $Roots.Count -eq 0) { $Roots = @($env:SystemDrive + '\') }

    $rootList = New-Object System.Collections.Generic.List[string]
    foreach ($r in $Roots) {
        if (-not $r) { continue }
        $full = [string]$r
        try { if (Test-Path -LiteralPath $r) { $full = (Get-Item -LiteralPath $r -ErrorAction SilentlyContinue).FullName } } catch { }
        if (-not $full) { continue }
        if (-not $full.EndsWith('\')) { $full += '\' }
        if (-not $rootList.Contains($full)) { $rootList.Add($full) }
    }
    if ($rootList.Count -eq 0) { throw 'No valid scan roots.' }

    $settings = Get-GSVSettings
    $vault = [string]$settings.BackupRoot
    $appRoot = Split-Path -Parent $PSScriptRoot

    $results = New-Object System.Collections.Generic.List[object]
    $seen = @{}

    $add = {
        param([string]$Path, [string]$Note, [string]$GameName, [string]$AppId)

        if (-not $Path) { return }
        $anchor = Get-GSVPathAnchor -ResolvedPath $Path
        if (-not $anchor.Token -and -not $anchor.Absolute) { return }

        $key = if ($anchor.Token) {
            ("{0}|{1}" -f $anchor.Token, $anchor.Relative).ToLowerInvariant()
        } else {
            ('abs|' + ([string]$anchor.Absolute).ToLowerInvariant())
        }
        if ($seen.ContainsKey($key)) { return }
        $seen[$key] = $true

        if (-not $GameName) { $GameName = Get-GSVDeepGameName -Path $Path }
        $size = $null
        if (-not $NoSize) { $size = Measure-GSVPathSize -Path $Path }

        $results.Add([pscustomobject]@{
            GameId         = 'deep-' + (ConvertTo-GSVNormalName -Name $GameName)
            GameName       = [string]$GameName
            Source         = 'Deep scan'
            AppId          = [string]$AppId
            InstallDirHint = ''
            Token          = $anchor.Token
            RelativePath   = $anchor.Relative
            AbsolutePath   = $anchor.Absolute
            ResolvedPath   = $Path
            Kind           = 'Directory'
            Note           = [string]$Note
            Origin         = 'deep-scan'
            Exists         = $true
            FileCount      = if ($size) { $size.Files } else { $null }
            Bytes          = if ($size) { $size.Bytes } else { $null }
        })
    }

    # --- UWP / Xbox containers (Packages is pruned from the walk) --------------
    foreach ($r in $rootList) {
        foreach ($p in @(Resolve-GSVPathPattern -Pattern (Join-Path $r 'Users\*\AppData\Local\Packages\*\SystemAppData\wgs'))) {
            & $add $p 'deep scan: UWP / Xbox save container' (Get-GSVDeepGameName -Path $p) ''
        }
        foreach ($p in @(Resolve-GSVPathPattern -Pattern (Join-Path $r 'Users\*\AppData\Local\Packages\*\LocalState'))) {
            if ((Test-Path -LiteralPath (Join-Path $p 'games')) -or (Test-Path -LiteralPath (Join-Path $p 'Saves'))) {
                & $add $p 'deep scan: UWP LocalState saves' (Get-GSVDeepGameName -Path $p) ''
            }
        }
    }

    # --- every Steam account/appid, even if Steam lives in Program Files -------
    foreach ($lib in @(Get-GSVSteamLibraries)) {
        $ud = Join-Path $lib 'userdata'
        if (-not (Test-Path -LiteralPath $ud)) { continue }

        $underRoot = $false
        foreach ($r in $rootList) {
            if ($ud.StartsWith($r.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) { $underRoot = $true; break }
        }
        if (-not $underRoot) { continue }

        foreach ($acct in @(Get-ChildItem -LiteralPath $ud -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+$' })) {
            foreach ($app in @(Get-ChildItem -LiteralPath $acct.FullName -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+$' })) {
                & $add $app.FullName 'deep scan: Steam userdata' (Get-GSVDeepGameName -Path $app.FullName) $app.Name
            }
        }
    }

    # --- pre-compute catalog names for folder matching -------------------------
    $catalogNames = New-Object System.Collections.Generic.List[string]
    foreach ($c in @(Get-GSVCatalog)) {
        if ($c.Name) { $catalogNames.Add([string]$c.Name) }
        foreach ($a in @($c.Aliases)) { if ($a) { $catalogNames.Add([string]$a) } }
    }

    # --- breadth-first walk ----------------------------------------------------
    $queue = New-Object System.Collections.Queue
    foreach ($r in $rootList) { $queue.Enqueue([pscustomobject]@{ Path = $r; Depth = 0 }) }

    $visited = 0
    while ($queue.Count -gt 0 -and $results.Count -lt $MaxResults -and $visited -lt $MaxFolders) {
        $node = $queue.Dequeue()
        $path = [string]$node.Path
        $depth = [int]$node.Depth
        $visited++

        if ($Progress -and ($visited % 500 -eq 0)) { & $Progress $visited $path }
        if (Test-GSVDeepSkipPath -Path $path -Vault $vault -AppRoot $appRoot) { continue }

        $di = $null
        try { $di = New-Object System.IO.DirectoryInfo($path) } catch { continue }
        if (-not $di.Exists) { continue }
        if (($di.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }

        $leaf = ''
        try { $leaf = $di.Name } catch { }
        $leafLower = $leaf.ToLowerInvariant()
        $parentLeaf = ''
        $grandLeaf = ''
        try { if ($di.Parent) { $parentLeaf = $di.Parent.Name } } catch { }
        try { if ($di.Parent -and $di.Parent.Parent) { $grandLeaf = $di.Parent.Parent.Name } } catch { }

        # 1. CPY / GSE / Goldberg / CODEX / RUNE / EMPRESS containers.
        #    If the container holds per-game folders, descend so each game is
        #    listed (and backed up) on its own instead of duplicating everything.
        if ($script:DeepContainerNames -contains $leafLower) {
            $childDirs = @()
            try { $childDirs = [System.IO.Directory]::GetDirectories($path) } catch { }
            if ($childDirs.Count -eq 0) {
                & $add $path ('deep scan: ' + $leaf + ' container') ($leaf + ' (all games)') ''
                continue
            }
        }

        # 1b. a game folder directly inside a CPY / GSE / Goldberg / scene container
        if ($parentLeaf -and ($script:DeepContainerNames -contains $parentLeaf.ToLowerInvariant())) {
            if ($leafLower -notin @('settings', 'stats', 'achievements', 'userdata', 'cache')) {
                $appId = if ($leaf -match '^\d{3,10}$') { $leaf } else { '' }
                & $add $path ('deep scan: ' + $parentLeaf + ' save') (Get-GSVDeepGameName -Path $path) $appId
            }
            continue
        }

        # 1c. PS4/PS5 emulator title folder: _SaveData\<PPSA…\ or <CUSA…\
        if (($parentLeaf -ieq '_savedata' -or $parentLeaf -ieq 'savedata') -and $leaf -match '^(PPSA|CUSA)\d{4,6}$') {
            & $add $path 'deep scan: console emulator title save' ("PS title " + $leaf) $leaf
            continue
        }

        # 1d. Switch emulator title folder: nand\user\save\<profile>\<titleID> (or bis\…)
        if ($leaf -match '^[0-9a-fA-F]{16}$' -and $parentLeaf -match '^[0-9a-fA-F]{16}$' -and $grandLeaf -ieq 'save') {
            & $add $path 'deep scan: Switch emulator title save' ("Switch title " + $leaf) $leaf
            continue
        }

        # 2. Public/ProgramData Steam container (scene groups live inside)
        if ($leafLower -eq 'steam' -and (
                ($parentLeaf -ieq 'Documents' -and $grandLeaf -ieq 'Public') -or
                $parentLeaf -ieq 'ProgramData')) {
            & $add $path 'deep scan: scene / emulator Steam container' 'Scene release saves (all games)' ''
            continue
        }

        # 3. Steam userdata <account>\<appid>
        if ($leaf -match '^\d{3,10}$' -and $parentLeaf -match '^\d{6,20}$' -and $grandLeaf -ieq 'userdata') {
            & $add $path 'deep scan: Steam userdata' (Get-GSVDeepGameName -Path $path) $leaf
            continue
        }

        # 4. UWP SystemAppData\wgs
        if ($leafLower -eq 'wgs' -and $parentLeaf -ieq 'SystemAppData') {
            & $add $path 'deep scan: UWP / Xbox save container' (Get-GSVDeepGameName -Path $path) ''
            continue
        }

        # 5. Unity: LocalLow\<company>\<product>
        if ($parentLeaf -and $grandLeaf -ieq 'LocalLow') {
            & $add $path 'deep scan: Unity LocalLow' $leaf ''
            continue
        }

        # 6. My Games\<game> and Saved Games\<game>. Descend through publisher
        #    folders such as Saved Games\CD Projekt Red\<game> or when the child
        #    is only a container (no save files / no Save subfolder of its own).
        if ($parentLeaf -ieq 'My Games' -or $parentLeaf -ieq 'Saved Games') {
            $childDirs = @()
            try { $childDirs = [System.IO.Directory]::GetDirectories($path) } catch { }

            $hasSaveSub = $false
            foreach ($cd in $childDirs) {
                $cn = ''
                try { $cn = Split-Path -Leaf $cd } catch { }
                if ($cn -and ($script:DeepSaveFolderNames -contains $cn.ToLowerInvariant())) { $hasSaveSub = $true; break }
            }

            $isPublisher = $script:DeepPublisherNames -contains $leafLower
            $looksLikeContainer = $isPublisher -or
                ($childDirs.Count -gt 0 -and -not $hasSaveSub -and -not (Test-GSVDeepHasSaveFiles -Path $path))

            if (-not $looksLikeContainer) {
                & $add $path ('deep scan: ' + $parentLeaf) $leaf ''
                continue
            }
        }

        # 7. publisher folders: Documents\Rockstar Games\<game>, etc.
        if ($parentLeaf -and ($script:DeepPublisherNames -contains $parentLeaf.ToLowerInvariant())) {
            & $add $path 'deep scan: publisher folder' $leaf ''
            continue
        }

        # 8. folders literally named Save / Saves / SaveGames / SaveData
        #    (except Switch save roots nand\user\save, which are handled per
        #     title by 1d — descending into them is what we want)
        $isSwitchSaveRoot = ($leafLower -eq 'save' -and $parentLeaf -ieq 'user' -and ($grandLeaf -ieq 'nand' -or $grandLeaf -ieq 'bis'))
        if (($script:DeepSaveFolderNames -contains $leafLower) -and -not $isSwitchSaveRoot) {
            & $add $path ('deep scan: ' + $leaf + ' folder') (Get-GSVDeepGameName -Path $path) ''
            continue
        }

        # 9. top-level game folder in Documents / AppData / ProgramData / drive root
        $isGameParent = ($parentLeaf -ieq 'Documents') -or
                        ($parentLeaf -ieq 'ProgramData') -or
                        (($parentLeaf -ieq 'Local' -or $parentLeaf -ieq 'Roaming') -and $grandLeaf -ieq 'AppData') -or
                        ($depth -eq 1)
        if ($isGameParent -and $leaf) {
            $matchedName = $null
            foreach ($cn in $catalogNames) {
                if (Test-GSVNameSimilar -A $leaf -B $cn) { $matchedName = $cn; break }
            }
            if ($matchedName) {
                & $add $path 'deep scan: known game data folder' $matchedName ''
                continue
            }
        }

        # 10. any folder under Documents / Saved Games that contains save files
        if ($leaf -and $leaf -notin @('Documents', 'Saved Games', 'My Games', 'ProgramData') -and
            ($path -match '(?i)\\(Documents|Saved Games)(\\|$)') -and
            (Test-GSVDeepHasSaveFiles -Path $path)) {
            & $add $path 'deep scan: folder with save files' (Get-GSVDeepGameName -Path $path) ''
            continue
        }

        # 11. descend
        if ($depth -ge $MaxDepth) { continue }
        try {
            foreach ($child in [System.IO.Directory]::EnumerateDirectories($path)) {
                $queue.Enqueue([pscustomobject]@{ Path = $child; Depth = $depth + 1 })
            }
        } catch { }
    }

    return $results.ToArray()
}

#endregion

Export-ModuleMember -Function *
