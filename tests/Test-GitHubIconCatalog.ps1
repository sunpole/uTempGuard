# Verifies GitHub README can display all uploaded SVGs without executing HTML.
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
foreach($lang in @('ICON_CATALOG.md','ICON_CATALOG_EN.md')){
    $path=Join-Path $root ('docs\'+$lang)
    $md=Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $icons=[regex]::Matches($md,'<img src="\.\./assets/logo/(utg_[wb]_(?:000|010|020|030|040|050|060|070|080|090|100)(?:_active)?\.svg)"')
    if($icons.Count -ne 28){throw ("Gallery {0} contains {1} icon images, expected 28" -f $lang,$icons.Count)}
    $names=@($icons|ForEach-Object{$_.Groups[1].Value})
    if(@($names|Select-Object -Unique).Count -ne 28){throw 'SVG catalog contains duplicates'}
    foreach($name in $names){
        if(-not (Test-Path -LiteralPath (Join-Path $root ('assets\logo\'+$name)))){throw ('Referenced SVG missing: '+$name)}
        if(-not $md.Contains('](../assets/logo/'+$name+')')){throw ('Image has no clickable filename: '+$name)}
    }
}
Write-Output 'PASS: GitHub-rendered RU/EN catalog displays and links all 28 original SVG icons.'
