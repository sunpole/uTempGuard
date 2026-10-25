# Windows release builder, source tree READ ONLY.
[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version='0.5.1',
    [string]$ProjectRoot='',
    [string]$OutputDirectory=''
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if([string]::IsNullOrWhiteSpace($ProjectRoot)){$ProjectRoot=Split-Path $PSScriptRoot -Parent}
$root=[IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\','/')
if(-not $OutputDirectory){$OutputDirectory=Join-Path $root 'artifacts\releases'}
$output=[IO.Path]::GetFullPath($OutputDirectory)
$zip=Join-Path $output ("uTempGuard-v"+$Version+"-win.zip")
if(Test-Path -LiteralPath $zip -PathType Leaf){throw 'Release ZIP already exists. Use a new output directory; no overwrite.'}
$staging=Join-Path ([IO.Path]::GetTempPath()) ('uTempGuard-dist-'+[guid]::NewGuid().ToString('N'))
$bundle=Join-Path $staging 'uTempGuard'
function Copy-PublicFile {
    param([string]$RelativePath)
    $from=Join-Path $root $RelativePath
    if(-not (Test-Path -LiteralPath $from -PathType Leaf)){throw ("Missing distribution file: "+$RelativePath)}
    $to=Join-Path $bundle $RelativePath
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($to)) | Out-Null
    Copy-Item -LiteralPath $from -Destination $to
}
try{
    [IO.Directory]::CreateDirectory($bundle)|Out-Null
    $entrypoints=@(
        '00_START-HERE.cmd','Install-uTempGuard.cmd','Start-uTempGuard.cmd',
        'Open-uTempGuard.cmd','Open-uTempGuard.ps1',
        'Open-Icon-Gallery.cmd','START-uTempGuard-Collector.cmd','Управление.cmd',
        'Setup-uTempGuard.ps1','Install.ps1','Manage.ps1','Launch.vbs',
        'Control.ps1','uTempGuard.ps1','Emergency-Control.ps1',
        'AidaAutostart.ps1','Collect-uTempGuard.ps1','Diagnose.ps1',
        'Update-uTempGuard.ps1','Uninstall.ps1',
        'config.example.json','README.md','README_EN.md','CHANGELOG.md'
    )
    foreach($file in $entrypoints){Copy-PublicFile $file}
    foreach($file in @(Get-ChildItem -LiteralPath (Join-Path $root 'src') -File)){
        if($file.Extension -notin @('.ps1','.psm1')){throw ('Unexpected source-file type: '+$file.Name)}
        Copy-PublicFile ('src\'+$file.Name)
    }
    foreach($file in @(Get-ChildItem -LiteralPath (Join-Path $root 'i18n') -Filter '*.json' -File)){
        Copy-PublicFile ('i18n\'+$file.Name)
    }
    foreach($file in @(Get-ChildItem -LiteralPath (Join-Path $root 'assets\logo') -Filter '*.svg' -File)){
        if($file.BaseName -notmatch '^utg_[wb]_(?:0[0-9]0|100)(?:_active)?$'){
            throw ('Unknown SVG in public icon set: '+$file.Name)
        }
        Copy-PublicFile ('assets\logo\'+$file.Name)
    }
    foreach($file in @(Get-ChildItem -LiteralPath (Join-Path $root 'assets\tray-icons') -Filter '*.png.base64' -File)){
        if($file.Name -notmatch '^utg_[wb]_(?:0[0-9]0|100)(?:_active)?\.png\.base64$'){
            throw ('Unexpected tray image name: '+$file.Name)
        }
        Copy-PublicFile ('assets\tray-icons\'+$file.Name)
    }
    foreach($file in @(Get-ChildItem -LiteralPath (Join-Path $root 'assets\buttons') -Filter '*.svg' -File)){
        Copy-PublicFile ('assets\buttons\'+$file.Name)
    }
    foreach($file in @('assets\u_logo_tempg2.svg','assets\u_logo_64.png.base64',
       'docs\INSTALL_RU.md','docs\INSTALL_EN.md',
       'docs\USER_GUIDE_RU.md','docs\USER_GUIDE_EN.md',
       'docs\LOCALIZATION.md','docs\TRAY_ICONS.md','docs\PROJECT_STRUCTURE.md',
       'docs\icon-gallery.html','docs\ICON_CATALOG.md','docs\ICON_CATALOG_EN.md')){
        Copy-PublicFile $file
    }
    if((Get-Content -LiteralPath (Join-Path $bundle 'config.example.json') -Raw -Encoding UTF8|ConvertFrom-Json).Mode -ne 'Observe'){
        throw 'Release template is not Observe-only'
    }
    foreach($file in @(Get-ChildItem -LiteralPath $bundle -File -Recurse)){
        $relative=$file.FullName.Substring($bundle.Length).TrimStart('\','/')
        if($relative -match '(?i)(^|[\\/])(\.git|tests|tools|\.github|\.release|screenshots|artifacts)([\\/]|$)' -or
            $relative -match '(?i)(^|[\\/])(config\.json|live-approval\.json|.*\.cdr|.*\.key|.*\.pfx|.*\.log|.*\.bak)$' -or
            $relative -match '(?i)(secret|token)'){
            throw ('Private or development file in ZIP: '+$relative)
        }
    }
    [IO.Directory]::CreateDirectory($output)|Out-Null
    Compress-Archive -LiteralPath $bundle -DestinationPath $zip -CompressionLevel Optimal
    $hash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    $checksum=Join-Path $output ("uTempGuard-v"+$Version+"-win.zip.sha256")
    if(Test-Path -LiteralPath $checksum -PathType Leaf){throw 'Existing SHA256 file; use a fresh output directory.'}
    [IO.File]::WriteAllText($checksum,($hash+"  "+[IO.Path]::GetFileName($zip)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
    [pscustomobject]@{
        ZipPath=$zip
        ChecksumPath=$checksum
        SHA256=$hash
        FileCount=@(Get-ChildItem -LiteralPath $bundle -Recurse -File).Count
        Format='Windows PowerShell 5.1 source distribution'
        ConfigIncluded=$false
        EmergencyArmed=$false
        OriginalSourceChanged=$false
    }
}finally{
    # Only our unique OS temporary staging folder is cleared; no source/project/user data touched.
    if(Test-Path -LiteralPath $staging -PathType Container){
        Remove-Item -LiteralPath $staging -Force -Recurse
    }
}
