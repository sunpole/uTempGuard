# Versioned, UTF-8 JSON localization for Windows PowerShell 5.1.
# Presentation only: never affects AIDA, thresholds, emergency approvals or actions.
Set-StrictMode -Version 2.0
$script:translationRoot=Join-Path (Split-Path $PSScriptRoot -Parent) 'i18n'
$script:languageFile=$null
$script:defaultLocale='ru-RU'
$script:activeLocale='ru-RU'
$script:catalogs=@{}

function Test-GuardLocaleCode {
    param([string]$Locale)
    return $Locale -cmatch '^[a-z]{2}(?:-[A-Z]{2})?$'
}
function Get-GuardSupportedLanguages {
    @('ru-RU','en-US')
}
function Read-GuardLocaleCatalog {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Locale)
    if($script:catalogs.ContainsKey($Locale)){return $script:catalogs[$Locale]}
    if(-not (Test-GuardLocaleCode $Locale) -or
       $Locale -cnotin @(Get-GuardSupportedLanguages)){throw 'Unsupported locale'}
    $path=Join-Path $script:translationRoot ($Locale+'.json')
    $json=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
    if([string]$json.locale -cne $Locale -or [int]$json.schemaVersion -ne 1 -or
       $null -eq $json.messages){throw 'Invalid locale catalog'}
    $map=@{}
    foreach($p in $json.messages.PSObject.Properties){
        if($p.Name -cnotmatch '^[a-zA-Z][a-zA-Z0-9.-]{0,95}$' -or $p.Value -isnot [string]){throw 'Invalid translation key'}
        $map[$p.Name]=$p.Value
    }
    $script:catalogs[$Locale]=$map
    return $map
}
function Initialize-GuardLocalization {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DataDirectory)
    $script:languageFile=Join-Path $DataDirectory 'language.json'
    $script:activeLocale=$script:defaultLocale
    $null=Read-GuardLocaleCatalog -Locale $script:defaultLocale
    if(Test-Path -LiteralPath $script:languageFile -PathType Leaf){
        try {
            $saved=Get-Content -LiteralPath $script:languageFile -Raw -Encoding UTF8|ConvertFrom-Json
            $locale=[string]$saved.locale
            if($locale -cin @(Get-GuardSupportedLanguages)){
                $null=Read-GuardLocaleCatalog -Locale $locale
                $script:activeLocale=$locale
            }
        }catch{ $script:activeLocale=$script:defaultLocale }
    }
    return $script:activeLocale
}
function Get-GuardCurrentLanguage {
    $script:activeLocale
}
function Get-GuardText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Key,[object[]]$Values=@())
    $fallback=Read-GuardLocaleCatalog -Locale $script:defaultLocale
    $active=Read-GuardLocaleCatalog -Locale $script:activeLocale
    $raw=if($active.ContainsKey($Key)){$active[$Key]}elseif($fallback.ContainsKey($Key)){$fallback[$Key]}else{$Key}
    if(@($Values).Count -eq 0){return [string]$raw}
    try{return [string]::Format([Globalization.CultureInfo]::InvariantCulture,[string]$raw,$Values)}
    catch{return [string]$raw}
}
function Set-GuardLanguage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Locale)
    if($Locale -cnotin @(Get-GuardSupportedLanguages)){throw 'Unsupported locale'}
    $null=Read-GuardLocaleCatalog -Locale $Locale
    if([string]::IsNullOrWhiteSpace($script:languageFile)){throw 'Localization not initialized'}
    $dir=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($script:languageFile))
    [IO.Directory]::CreateDirectory($dir)|Out-Null
    $tmp=$script:languageFile+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try{
        [IO.File]::WriteAllText($tmp,(@{locale=$Locale;schemaVersion=1}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $tmp -Destination $script:languageFile -Force
        $script:activeLocale=$Locale
    }finally{
        if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force}
    }
    return $script:activeLocale
}
Export-ModuleMember -Function Initialize-GuardLocalization,Get-GuardSupportedLanguages,Get-GuardCurrentLanguage,Get-GuardText,Set-GuardLanguage
