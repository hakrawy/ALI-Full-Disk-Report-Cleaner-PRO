
# ALI Full Disk Report - C ONLY - FIXED
# Safe report tool: does NOT delete anything.
# Run as Administrator for best results.

$ErrorActionPreference = "SilentlyContinue"
$DriveRoot = "C:\"
$Desktop = [Environment]::GetFolderPath("Desktop")
$Stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$TxtReport = Join-Path $Desktop "ALI_Full_Disk_Report_C_ONLY_$Stamp.txt"
$HtmlReport = Join-Path $Desktop "ALI_Full_Disk_Report_C_ONLY_$Stamp.html"

function Format-Size {
    param([double]$Bytes)
    if ($null -eq $Bytes) { return "0 B" }
    if ($Bytes -ge 1TB) { return "{0:N2} TB" -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "{0:N0} B" -f $Bytes
}

function Add-Line {
    param([string]$Text = "")
    $Text | Out-File -FilePath $TxtReport -Append -Encoding UTF8
}

function Add-Section {
    param([string]$Title)
    Add-Line ""
    Add-Line "============================================================"
    Add-Line $Title
    Add-Line "============================================================"
}

function Get-FolderSizeFast {
    param([string]$Path)
    $total = 0
    try {
        Get-ChildItem -LiteralPath $Path -Force -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            $total += $_.Length
        }
    } catch {}
    return [double]$total
}

function New-ItemRow {
    param([string]$Name, [string]$Path, [double]$SizeBytes, [string]$Type)
    [PSCustomObject]@{
        Name = $Name
        Type = $Type
        Size = Format-Size $SizeBytes
        SizeBytes = [int64]$SizeBytes
        Path = $Path
    }
}

Write-Host "ALI Full Disk Report - C ONLY" -ForegroundColor Cyan
Write-Host "This tool only scans C: and does NOT delete anything." -ForegroundColor Yellow
Write-Host "Report TXT: $TxtReport"
Write-Host "Report HTML: $HtmlReport"
Write-Host ""

"ALI FULL DISK REPORT - C ONLY" | Out-File -FilePath $TxtReport -Encoding UTF8
Add-Line "Generated: $(Get-Date)"
Add-Line "Computer: $env:COMPUTERNAME"
Add-Line "User: $env:USERNAME"
Add-Line "Mode: REPORT ONLY - NO DELETE"

# Drive summary
Add-Section "DRIVE SUMMARY"
$drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
if ($drive) {
    Add-Line "Drive: C:"
    Add-Line "Total: $(Format-Size $drive.Size)"
    Add-Line "Free : $(Format-Size $drive.FreeSpace)"
    Add-Line "Used : $(Format-Size ($drive.Size - $drive.FreeSpace))"
}

# System large files
Add-Section "SYSTEM LARGE FILES"
$systemFiles = @(
    "C:\pagefile.sys",
    "C:\hiberfil.sys",
    "C:\swapfile.sys",
    "C:\DumpStack.log.tmp"
)

$systemFileRows = @()
foreach ($file in $systemFiles) {
    if (Test-Path -LiteralPath $file) {
        $item = Get-Item -LiteralPath $file -Force
        $row = New-ItemRow -Name $item.Name -Path $item.FullName -SizeBytes $item.Length -Type "System file"
        $systemFileRows += $row
        Add-Line "$($row.Size) - $($row.Path)"
    }
}

# Top root folders
Add-Section "TOP ROOT FOLDERS ON C"
$rootRows = @()
$rootItems = Get-ChildItem -LiteralPath "C:\" -Force -Directory -ErrorAction SilentlyContinue
foreach ($folder in $rootItems) {
    Write-Host "Scanning root folder: $($folder.FullName)"
    $size = Get-FolderSizeFast -Path $folder.FullName
    $rootRows += New-ItemRow -Name $folder.Name -Path $folder.FullName -SizeBytes $size -Type "Root folder"
}
$rootRows = $rootRows | Sort-Object SizeBytes -Descending
foreach ($row in ($rootRows | Select-Object -First 30)) {
    Add-Line "$($row.Size) - $($row.Path)"
}

# AppData top folders
Add-Section "TOP APPDATA FOLDERS"
$appDataTargets = @(
    "$env:LOCALAPPDATA",
    "$env:APPDATA",
    "$env:USERPROFILE\AppData\LocalLow"
)
$appDataRows = @()
foreach ($base in $appDataTargets) {
    if (Test-Path -LiteralPath $base) {
        $children = Get-ChildItem -LiteralPath $base -Force -Directory -ErrorAction SilentlyContinue
        foreach ($child in $children) {
            Write-Host "Scanning AppData: $($child.FullName)"
            $size = Get-FolderSizeFast -Path $child.FullName
            $appDataRows += New-ItemRow -Name $child.Name -Path $child.FullName -SizeBytes $size -Type "AppData folder"
        }
    }
}
$appDataRows = $appDataRows | Sort-Object SizeBytes -Descending
foreach ($row in ($appDataRows | Select-Object -First 50)) {
    Add-Line "$($row.Size) - $($row.Path)"
}

# Developer folders
Add-Section "DEVELOPER CACHE LOCATIONS"
$devPaths = @(
    "$env:USERPROFILE\.gradle",
    "$env:USERPROFILE\.npm",
    "$env:USERPROFILE\.expo",
    "$env:USERPROFILE\.android",
    "$env:LOCALAPPDATA\Android",
    "$env:LOCALAPPDATA\Gradle",
    "$env:LOCALAPPDATA\npm-cache",
    "$env:LOCALAPPDATA\Temp\metro-cache",
    "$env:LOCALAPPDATA\Temp\haste-map-*"
)
$devRows = @()
foreach ($p in $devPaths) {
    $matches = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
    if (-not $matches) {
        $matches = Get-ChildItem -Path $p -Force -ErrorAction SilentlyContinue
    }
    foreach ($m in $matches) {
        if ($m -and (Test-Path -LiteralPath $m.FullName)) {
            $size = 0
            if ($m.PSIsContainer) { $size = Get-FolderSizeFast -Path $m.FullName } else { $size = $m.Length }
            $devRows += New-ItemRow -Name $m.Name -Path $m.FullName -SizeBytes $size -Type "Developer cache"
        }
    }
}
$devRows = $devRows | Sort-Object SizeBytes -Descending
foreach ($row in ($devRows | Select-Object -First 50)) {
    Add-Line "$($row.Size) - $($row.Path)"
}

# Node modules scanner - common locations only to avoid very slow full C scan
Add-Section "NODE_MODULES SCANNER"
$searchBases = @(
    "$env:USERPROFILE\Desktop",
    "$env:USERPROFILE\Documents",
    "$env:USERPROFILE\Downloads",
    "C:\Users\ALI\Desktop",
    "C:\Users\ALI\Documents",
    "C:\Users\ALI\Downloads",
    "C:\dev",
    "C:\projects",
    "C:\العاب C"
) | Select-Object -Unique

$nodeRows = @()
foreach ($base in $searchBases) {
    if (Test-Path -LiteralPath $base) {
        Write-Host "Searching node_modules in: $base"
        $nodes = Get-ChildItem -LiteralPath $base -Force -Directory -Recurse -Filter "node_modules" -ErrorAction SilentlyContinue
        foreach ($node in $nodes) {
            $size = Get-FolderSizeFast -Path $node.FullName
            $nodeRows += New-ItemRow -Name $node.Name -Path $node.FullName -SizeBytes $size -Type "node_modules"
        }
    }
}
$nodeRows = $nodeRows | Sort-Object SizeBytes -Descending
if ($nodeRows.Count -eq 0) {
    Add-Line "No node_modules found in common locations."
} else {
    foreach ($row in ($nodeRows | Select-Object -First 50)) {
        Add-Line "$($row.Size) - $($row.Path)"
    }
}

# Game scanner - C only, safer matching
Add-Section "GAME SCANNER - C ONLY"
$gameBases = @(
    "C:\Program Files (x86)\Steam\steamapps\common",
    "C:\Program Files\Steam\steamapps\common",
    "C:\Program Files\Epic Games",
    "C:\Program Files (x86)\Epic Games",
    "C:\Riot Games",
    "C:\Program Files\Riot Games",
    "C:\Program Files\Rockstar Games",
    "C:\Program Files (x86)\Rockstar Games",
    "C:\XboxGames",
    "C:\Program Files\WindowsApps"
)

$excludeWindowsAppsPrefixes = @(
    "Microsoft.",
    "MicrosoftCorporationII.",
    "MSTeams_",
    "AppleInc.",
    "OpenAI.",
    "12030rocksdanister.",
    "SpotifyAB.",
    "WhatsApp.",
    "Adobe."
)

$gameRows = @()
foreach ($base in $gameBases) {
    if (Test-Path -LiteralPath $base) {
        Write-Host "Scanning game base: $base"
        $children = Get-ChildItem -LiteralPath $base -Force -Directory -ErrorAction SilentlyContinue
        foreach ($child in $children) {
            $skip = $false
            if ($base -like "*WindowsApps*") {
                foreach ($prefix in $excludeWindowsAppsPrefixes) {
                    if ($child.Name.StartsWith($prefix)) { $skip = $true }
                }
            }
            if (-not $skip) {
                $size = Get-FolderSizeFast -Path $child.FullName
                if ($size -gt 300MB) {
                    $gameRows += New-ItemRow -Name $child.Name -Path $child.FullName -SizeBytes $size -Type "Possible game/app"
                }
            }
        }
    }
}
$gameRows = $gameRows | Sort-Object SizeBytes -Descending
if ($gameRows.Count -eq 0) {
    Add-Line "No large games found in known C: locations."
} else {
    foreach ($row in ($gameRows | Select-Object -First 50)) {
        Add-Line "$($row.Size) - $($row.Path)"
    }
}

# Cache scanner
Add-Section "COMMON CACHE LOCATIONS"
$cachePaths = @(
    "$env:TEMP",
    "C:\Windows\Temp",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\GPUCache",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\GPUCache",
    "$env:APPDATA\discord\Cache",
    "$env:APPDATA\discord\Code Cache",
    "$env:APPDATA\discord\GPUCache",
    "$env:APPDATA\Code\Cache",
    "$env:APPDATA\Code\Code Cache",
    "$env:LOCALAPPDATA\NVIDIA\DXCache",
    "$env:LOCALAPPDATA\NVIDIA\GLCache",
    "$env:LOCALAPPDATA\D3DSCache",
    "$env:LOCALAPPDATA\CrashDumps"
)
$cacheRows = @()
foreach ($p in $cachePaths) {
    if (Test-Path -LiteralPath $p) {
        Write-Host "Scanning cache: $p"
        $size = Get-FolderSizeFast -Path $p
        $cacheRows += New-ItemRow -Name (Split-Path $p -Leaf) -Path $p -SizeBytes $size -Type "Cache"
    }
}
$cacheRows = $cacheRows | Sort-Object SizeBytes -Descending
foreach ($row in ($cacheRows | Select-Object -First 50)) {
    Add-Line "$($row.Size) - $($row.Path)"
}

# Large files by extension in user folders
Add-Section "LARGE FILES IN USER FOLDERS"
$userBases = @(
    "$env:USERPROFILE\Desktop",
    "$env:USERPROFILE\Downloads",
    "$env:USERPROFILE\Documents",
    "$env:USERPROFILE\Videos",
    "$env:USERPROFILE\Pictures"
)
$largeFileRows = @()
foreach ($base in $userBases) {
    if (Test-Path -LiteralPath $base) {
        Write-Host "Scanning large files in: $base"
        $files = Get-ChildItem -LiteralPath $base -Force -Recurse -File -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            if ($file.Length -gt 100MB) {
                $largeFileRows += New-ItemRow -Name $file.Name -Path $file.FullName -SizeBytes $file.Length -Type "Large file"
            }
        }
    }
}
$largeFileRows = $largeFileRows | Sort-Object SizeBytes -Descending
if ($largeFileRows.Count -eq 0) {
    Add-Line "No files larger than 100MB found in common user folders."
} else {
    foreach ($row in ($largeFileRows | Select-Object -First 100)) {
        Add-Line "$($row.Size) - $($row.Path)"
    }
}

# Old installers/packages
Add-Section "INSTALLERS / ARCHIVES / APK / ISO IN USER FOLDERS"
$packageExt = @(".zip",".rar",".7z",".iso",".apk",".aab",".exe",".msi",".dmg",".tar",".gz")
$packageRows = @()
foreach ($base in $userBases) {
    if (Test-Path -LiteralPath $base) {
        $files = Get-ChildItem -LiteralPath $base -Force -Recurse -File -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            if ($packageExt -contains $file.Extension.ToLower()) {
                if ($file.Length -gt 50MB) {
                    $packageRows += New-ItemRow -Name $file.Name -Path $file.FullName -SizeBytes $file.Length -Type "Package/archive"
                }
            }
        }
    }
}
$packageRows = $packageRows | Sort-Object SizeBytes -Descending
if ($packageRows.Count -eq 0) {
    Add-Line "No large packages found."
} else {
    foreach ($row in ($packageRows | Select-Object -First 100)) {
        Add-Line "$($row.Size) - $($row.Path)"
    }
}

# Recommendations
Add-Section "SMART RECOMMENDATIONS"
Add-Line "1) If hiberfil.sys exists: run as Admin -> powercfg -h off"
Add-Line "2) If pagefile.sys is very large: reduce virtual memory carefully or use the cleaner restore option."
Add-Line "3) node_modules can be deleted from old projects; restore with npm install."
Add-Line "4) NVIDIA/DXCache/Browser/Discord cache can usually be cleaned safely."
Add-Line "5) Do NOT delete C:\Windows, C:\Program Files, or C:\ProgramData randomly."
Add-Line "6) Uninstall Microsoft Store apps/games from Settings > Apps, not by deleting WindowsApps manually."

# HTML report
$allRows = @()
$allRows += $systemFileRows
$allRows += ($rootRows | Select-Object -First 30)
$allRows += ($appDataRows | Select-Object -First 50)
$allRows += ($devRows | Select-Object -First 50)
$allRows += ($nodeRows | Select-Object -First 50)
$allRows += ($gameRows | Select-Object -First 50)
$allRows += ($cacheRows | Select-Object -First 50)
$allRows += ($largeFileRows | Select-Object -First 100)
$allRows += ($packageRows | Select-Object -First 100)

$css = @"
<style>
body{font-family:Segoe UI,Arial;background:#0b1220;color:#e5e7eb;margin:24px}
h1{color:#38bdf8}
.card{background:#111827;border:1px solid #334155;border-radius:14px;padding:16px;margin:16px 0}
table{width:100%;border-collapse:collapse;background:#0f172a;border-radius:12px;overflow:hidden}
th,td{padding:10px;border-bottom:1px solid #243244;text-align:left}
th{background:#1e293b;color:#f59e0b}
tr:hover{background:#172033}
.small{color:#94a3b8}
</style>
"@

$html = @()
$html += "<html><head><meta charset='utf-8'><title>ALI Full Disk Report</title>$css</head><body>"
$html += "<h1>ALI Full Disk Report - C ONLY</h1>"
$html += "<div class='card'><b>Generated:</b> $(Get-Date)<br><b>Mode:</b> Report only - no deletion<br><b>TXT:</b> $TxtReport</div>"
if ($drive) {
    $html += "<div class='card'><h2>Drive C Summary</h2><p>Total: $(Format-Size $drive.Size)<br>Free: $(Format-Size $drive.FreeSpace)<br>Used: $(Format-Size ($drive.Size - $drive.FreeSpace))</p></div>"
}
$html += "<div class='card'><h2>Combined Findings</h2>"
$html += ($allRows | Sort-Object SizeBytes -Descending | Select-Object -First 300 Name,Type,Size,Path | ConvertTo-Html -Fragment)
$html += "</div>"
$html += "<div class='card'><h2>Recommendations</h2><ol><li>Disable Hibernate if not needed.</li><li>Reduce Pagefile carefully.</li><li>Delete old node_modules only from projects you can reinstall.</li><li>Clean cache locations safely.</li><li>Uninstall apps from Settings, not manually from WindowsApps.</li></ol></div>"
$html += "</body></html>"
$html -join "`n" | Out-File -FilePath $HtmlReport -Encoding UTF8

Write-Host ""
Write-Host "DONE!" -ForegroundColor Green
Write-Host "TXT report: $TxtReport" -ForegroundColor Cyan
Write-Host "HTML report: $HtmlReport" -ForegroundColor Cyan
Write-Host ""
Write-Host "Opening reports..."
Start-Process notepad.exe $TxtReport
Start-Process $HtmlReport
