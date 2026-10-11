<#
.SYNOPSIS
  Finds (and optionally removes) orphaned "Apps & features" entries whose
  uninstaller file no longer exists (e.g. D:\VLC\uninstall.exe).

.EXAMPLE
  .\Remove-DeadUninstallEntries.ps1                 # dry run: only lists dead entries
  .\Remove-DeadUninstallEntries.ps1 -Remove         # backs up, then asks y/N per entry
  .\Remove-DeadUninstallEntries.ps1 -Remove -Force  # backs up, removes all without asking
#>
param(
    [switch]$Remove,
    [switch]$Force
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).
           IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($Remove -and -not $isAdmin) {
    Write-Error "Run PowerShell as Administrator to remove machine-wide (HKLM) entries."
    exit 1
}

$roots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
)

# Pull the executable path out of an UninstallString like:
#   "C:\Program Files\X\uninst.exe" /S      or      D:\VLC\uninstall.exe
function Get-ExePath([string]$cmd) {
    if ([string]::IsNullOrWhiteSpace($cmd)) { return $null }
    $cmd = [Environment]::ExpandEnvironmentVariables($cmd.Trim())
    if ($cmd -match '^"([^"]+)"')                    { return $Matches[1] }
    if ($cmd -match '^(.+?\.(exe|cmd|bat))(\s|$)')   { return $Matches[1] }
    return ($cmd -split '\s')[0]
}

# Files referenced as arguments, e.g. IsUninst.exe -f"D:\App\Uninst.isu"
function Get-ArgFiles([string]$cmd) {
    if ([string]::IsNullOrWhiteSpace($cmd)) { return @() }
    $cmd = [Environment]::ExpandEnvironmentVariables($cmd)
    [regex]::Matches($cmd, '(?i)[A-Z]:\\[^"<>|*?\r\n]*?\.(isu|exe|dll|msi|ini|dat)\b') |
        ForEach-Object { $_.Value }
}

$dead = foreach ($root in $roots) {
    Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
        $p = Get-ItemProperty $_.PSPath
        if (-not $p.DisplayName -or $p.SystemComponent -eq 1) { return }   # hidden entries
        $cmd = $p.UninstallString
        $exe = Get-ExePath $cmd
        if (-not $exe) { return }

        $reason = $null
        $missing = $null
        if ($exe -notmatch '(?i)(msiexec|rundll32)(\.exe)?$' -and -not (Test-Path -LiteralPath $exe)) {
            $reason = 'Uninstaller missing'; $missing = $exe
        }
        elseif ($exe -notmatch '(?i)msiexec(\.exe)?$') {
            # Uninstaller exists but a file it needs (e.g. .isu log) is gone
            $gone = Get-ArgFiles $cmd | Where-Object { $_ -ne $exe -and -not (Test-Path -LiteralPath $_) } |
                    Select-Object -First 1
            if ($gone) { $reason = 'Referenced file missing'; $missing = $gone }
        }
        if (-not $reason -and $p.InstallLocation) {
            $loc = [Environment]::ExpandEnvironmentVariables($p.InstallLocation.Trim('" '))
            if ($loc -and -not (Test-Path -LiteralPath $loc)) { $reason = 'Install folder missing'; $missing = $loc }
        }

        if ($reason) {
            [pscustomobject]@{
                Name    = $p.DisplayName
                Reason  = $reason
                Missing = $missing
                Key     = $_.Name      # e.g. HKEY_LOCAL_MACHINE\SOFTWARE\...\Uninstall\VLC media player
            }
        }
    }
}

if (-not $dead) { Write-Host "No dead entries found." -ForegroundColor Green; return }

$dead | Sort-Object Name | Format-Table Name, Reason, Missing -AutoSize -Wrap
Write-Host "$(@($dead).Count) dead entr(y/ies) found."

if (-not $Remove) {
    Write-Host "`nDry run only. Re-run with -Remove to delete them." -ForegroundColor Yellow
    return
}

$backup = Join-Path ([Environment]::GetFolderPath('Desktop')) "uninstall-backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
New-Item -ItemType Directory -Path $backup | Out-Null

$i = 0
foreach ($d in ($dead | Sort-Object Name)) {
    if (-not $Force) {
        $a = Read-Host "Remove '$($d.Name)'? [y/N]"
        if ($a -notmatch '^(y|yes)$') { continue }
    }
    $i++
    $safe = $d.Name -replace '[\\/:*?"<>|]', '_'
    reg export "$($d.Key)" (Join-Path $backup "$i - $safe.reg") /y | Out-Null
    Remove-Item -LiteralPath "Registry::$($d.Key)" -Recurse -ErrorAction Continue
    Write-Host "Removed: $($d.Name)" -ForegroundColor Cyan
}

Write-Host "`nDone. $i removed. Backups in: $backup (double-click a .reg file to restore)."