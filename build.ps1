# Builds .tar.xz for every mod under mods/*/pack into mods/*/dist
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$mods = Get-ChildItem -LiteralPath "$root\mods" -Directory
foreach ($m in $mods) {
    $pack = Join-Path $m.FullName "pack"
    if (-not (Test-Path -LiteralPath $pack)) { continue }
    $dist = Join-Path $m.FullName "dist"
    New-Item -ItemType Directory -Force -Path $dist | Out-Null
    $modJson = Get-Content -LiteralPath (Join-Path $pack "mod.json") -Raw | ConvertFrom-Json
    $name = $modJson.name
    $ver = $modJson.version
    $out = Join-Path $dist "$name-$ver.tar.xz"
    tar -cJf $out -C $pack .
    Write-Host "Built $out"
}
