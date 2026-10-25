# Sends files the MKSMK workspace no longer needs to the Recycle Bin.
# Everything stays recoverable from the Recycle Bin until you empty it.
Add-Type -AssemblyName Microsoft.VisualBasic
$root = $PSScriptRoot
$items = @(
    'analysis\ShaolinMonks-Android',                         # Android port (not used)
    'analysis\__pycache__',
    'analysis\luaenv',                                       # only used by the old validator
    'analysis\final_validate.py',                            # validated the old packages; see mods\_build\tests
    'UMKSM VERSION II 2.6\SLUS-28688 (Android).zip',         # Android copy of the UMKSM texture pack (PC .rar kept)
    'Mortal Kombat - Shaolin Monks (USA, Europe) (En,Fr,De,Es,It)\Vimm''s Lair.txt',
    'mods\ldk\zips',                                         # 0.3.0 test build
    'mods\ldk\dist\ldk-1.3.0.tar.xz',
    'mods\ldk_bosses\dist\ldk_bosses-0.1.0.tar.xz',
    'mods\ldk_bosses\dist\ldk_bosses-0.1.1.tar.xz',
    'mods\randomizer\dist\randomizer-0.1.0.tar.xz',
    'mods\env_kill_xp\dist\env_kill_xp-1.0.0.tar.xz',
    'mods\env_kill_xp\dist\env_kill_xp-1.1.0.tar.xz',
    'mods\ldk\dist\ldk-2.0.0.tar.xz',                     # 2.0.0 / 0.2.0 / 1.2.0 had the pointer bug
    'mods\ldk_bosses\dist\ldk_bosses-0.2.0.tar.xz',
    'mods\randomizer\dist\randomizer-0.2.0.tar.xz',
    'mods\env_kill_xp\dist\env_kill_xp-1.2.0.tar.xz',
    'mods\ldk\dist\ldk-2.0.1.tar.xz',                     # 2.0.1 / 0.2.1 could crash; 1.2.1 skipped single player
    'mods\ldk_bosses\dist\ldk_bosses-0.2.1.tar.xz',
    'mods\randomizer\dist\randomizer-0.2.1.tar.xz',
    'mods\env_kill_xp\dist\env_kill_xp-1.2.1.tar.xz',
    'mods\ldk_bosses',                                      # Boss Invasion is part of LDK 3.0 now
    'mods\_build\src\bosses_body.lua',
    'mods\_build\readme\ldk_bosses.md',
    'mods\ldk\dist\ldk-2.1.0.tar.xz',                     # superseded by LDK 3.0 / Shuffle 0.4 / Env XP 1.3
    'mods\randomizer\dist\randomizer-0.3.0.tar.xz',
    'mods\env_kill_xp\dist\env_kill_xp-1.2.2.tar.xz',
    'mods\coop_solo\dist\coop_solo-0.1.0.tar.xz',
    'mods\mksmk_probe\dist\mksmk_probe-0.1.0.tar.xz',
    'mods\ldk\dist\ldk-3.0.0.tar.xz',                     # 3.0 / 0.4 could softlock (enemy in an incompatible spawn slot)
    'mods\randomizer\dist\randomizer-0.4.0.tar.xz',
    'mods\coop_solo\dist\coop_solo-0.2.0.tar.xz',
    'mods\mksmk_probe\dist\mksmk_probe-0.2.0.tar.xz',
    'mods\env_kill_xp\dist\env_kill_xp-1.3.0.tar.xz',
    'mods\ldk\dist\ldk-3.1.0.tar.xz',
    'mods\randomizer\dist\randomizer-0.5.0.tar.xz'
)
$found = $items | ForEach-Object { Join-Path $root $_ } | Where-Object { Test-Path -LiteralPath $_ }
if (-not $found) { Write-Host 'Nothing to clean up.'; Read-Host 'Press Enter to close'; exit }
Write-Host 'These will be moved to the Recycle Bin:'
$found | ForEach-Object { Write-Host "  $_" }
if ((Read-Host 'Continue? (y/n)') -ne 'y') { exit }
$ui = [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs
$bin = [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
foreach ($path in $found) {
    if (Test-Path -LiteralPath $path -PathType Container) {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($path, $ui, $bin)
    } else {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($path, $ui, $bin)
    }
    Write-Host "Recycled $path"
}
Read-Host 'Done. Press Enter to close'
