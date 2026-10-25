# Optional tray graphics from *pre-rendered* user-owned CorelDRAW SVG assets.
# Does not influence monitoring, actions or source approvals.
$script:trayIconFrames=@{}
$script:trayIconOriginal=$null
$script:trayIconCurrentKey=''
$script:trayTaskbarTheme='Dark'
$script:trayThemeCheckedAt=-9999.0
$script:trayRasterRoot=Join-Path $PSScriptRoot '..\assets\tray-icons'

function Get-GuardTaskbarTheme {
    # SystemUsesLightTheme describes the taskbar, not AppsUseLightTheme.
    $key=$null
    try{
        $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
            'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize',$false)
        if($null -ne $key){
            $raw=$key.GetValue('SystemUsesLightTheme',$null)
            if($null -ne $raw){return $(if([int]$raw -eq 1){'Light'}else{'Dark'})}
        }
    }catch{}finally{if($null -ne $key){$key.Dispose()}}
    return 'Dark'
}
function Get-GuardRenderedIcon {
    param([Parameter(Mandatory)][string]$Key)
    if($Key -cnotmatch '^utg_[wb]_(?:0[0-9]0|100)(?:_active)?$'){return $null}
    if($script:trayIconFrames.ContainsKey($Key)){return $script:trayIconFrames[$Key]}
    $path=Join-Path $script:trayRasterRoot ($Key+'.png.base64')
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)){return $null}
    try{
        $encoded=Get-Content -LiteralPath $path -Raw -Encoding ASCII
        if($encoded.Length -gt 140000){throw 'Oversized tray asset'}
        $bytes=[Convert]::FromBase64String($encoded.Trim())
        $stream=[IO.MemoryStream]::new($bytes,$false)
        try{
            $source=[Drawing.Image]::FromStream($stream)
            try{
                if($source.Width -ne 64 -or $source.Height -ne 64){throw 'Expected 64x64 raster'}
                $bitmap=[Drawing.Bitmap]::new(32,32,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
                try{
                    $graphics=[Drawing.Graphics]::FromImage($bitmap)
                    try{
                        $graphics.Clear([Drawing.Color]::Transparent)
                        $graphics.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                        $graphics.DrawImage($source,[Drawing.Rectangle]::new(0,0,32,32))
                    }finally{$graphics.Dispose()}
                    $handle=$bitmap.GetHicon()
                    try{
                        $temporary=[Drawing.Icon]::FromHandle($handle)
                        $icon=[Drawing.Icon]$temporary.Clone()
                    }finally{[void][GuardTrayNative]::DestroyIcon($handle)}
                    $script:trayIconFrames[$Key]=$icon
                    return $icon
                }finally{$bitmap.Dispose()}
            }finally{$source.Dispose()}
        }finally{$stream.Dispose()}
    }catch{
        # A corrupt logo must not crash the monitor or change any power action.
        return $null
    }
}
function Initialize-GuardTrayIcons {
    if($null -eq $script:tray){return}
    if(-not ('GuardTrayNative' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class GuardTrayNative {
    [DllImport("user32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool DestroyIcon(IntPtr hIcon);
}
'@
    }
    $script:trayIconOriginal=$script:tray.Icon
    $script:trayTaskbarTheme=Get-GuardTaskbarTheme
    $script:trayThemeCheckedAt=-9999.0
    $script:trayIconCurrentKey=''
}
function Update-GuardTrayIcons {
    param([double]$ElapsedSeconds)
    if($null -eq $script:tray -or [bool]$SimulationPath){return}
    if(($ElapsedSeconds-$script:trayThemeCheckedAt) -ge 2.0){
        $script:trayTaskbarTheme=Get-GuardTaskbarTheme
        $script:trayThemeCheckedAt=$ElapsedSeconds
    }
    $healthy=($null -ne $script:lastSample -and $script:lastSample.Healthy -and
       $null -ne $script:lastDisplayTemperature -and $script:lastDisplayTemperature.Healthy)
    $temp=if($healthy){$script:lastDisplayTemperature.MaxC}else{$null}
    $choice=Get-GuardTrayIconChoice -TemperatureC $temp -SensorHealthy $healthy -TaskbarTheme $script:trayTaskbarTheme -ElapsedSeconds $ElapsedSeconds -AssetDirectory $script:trayRasterRoot
    if(-not $choice.Ready){
        if($script:trayIconCurrentKey -ne '' -and $null -ne $script:trayIconOriginal){
            $script:tray.Icon=$script:trayIconOriginal
            $script:trayIconCurrentKey=''
        }
        return
    }
    if($choice.Key -ceq $script:trayIconCurrentKey){return}
    $frame=Get-GuardRenderedIcon -Key $choice.Key
    if($null -ne $frame){
        $script:tray.Icon=$frame
        $script:trayIconCurrentKey=$choice.Key
    }
}
function Close-GuardTrayIcons {
    if($null -ne $script:tray -and $null -ne $script:trayIconOriginal){
        try{$script:tray.Icon=$script:trayIconOriginal}catch{}
    }
    foreach($entry in @($script:trayIconFrames.Values)){try{$entry.Dispose()}catch{}}
    $script:trayIconFrames=@{}
    $script:trayIconCurrentKey=''
    $script:trayIconOriginal=$null
}
