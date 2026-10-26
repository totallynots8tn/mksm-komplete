# Decompile functions of default.xbe with Ghidra (headless, read-only).
#   powershell -File tools/ghidra/decompile.ps1 0x9c3f0 0x13954
# Prints the C to the console and keeps it in tools/ghidra/out/last.c.
# Needs the analysed project from the one-time setup (see README.md here).
param([Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)][string[]]$Addresses)

$ghidra = if ($env:GHIDRA_HOME) { $env:GHIDRA_HOME } else { "C:\Users\Arcade Machine 1\Tools\ghidra_12.1.4_PUBLIC" }
$projects = if ($env:GHIDRA_PROJECTS) { $env:GHIDRA_PROJECTS } else { "C:\Users\Arcade Machine 1\Tools\ghidra-projects" }
if (-not $env:JAVA_HOME) { $env:JAVA_HOME = "C:\Program Files\Java\jdk-23" }

# Ghidra's headless launcher dislikes spaces in paths: use the short (8.3) forms.
$fso = New-Object -ComObject Scripting.FileSystemObject
$short = { param($p) if (Test-Path $p -PathType Container) { $fso.GetFolder($p).ShortPath } else { $fso.GetFile($p).ShortPath } }
$here = & $short $PSScriptRoot
$outDir = Join-Path $PSScriptRoot "out"
New-Item -ItemType Directory -Force $outDir | Out-Null
$out = Join-Path (& $short $outDir) "last.c"

& (Join-Path (& $short $ghidra) "support\analyzeHeadless.bat") (& $short $projects) MKSMK `
    -process default.xbe -noanalysis -readOnly -scriptPath $here `
    -postScript Decompile.java $out @Addresses *> (Join-Path $outDir "last.log")
if (Test-Path $out) { Get-Content $out } else { Get-Content (Join-Path $outDir "last.log") -Tail 20 }
