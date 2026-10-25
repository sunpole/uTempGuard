# Safe localization QA: bilingual UTF-8 catalogs, persistence, independent of power settings.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'src\Guard.Localization.psm1') -Force
$base=Join-Path $root ('artifacts\locale-test-'+[guid]::NewGuid().ToString('N'))
$initial=Initialize-GuardLocalization -DataDirectory $base
if($initial -cne 'ru-RU'){throw 'Russian fallback is not the default'}
$ru=Get-Content -LiteralPath (Join-Path $root 'i18n\ru-RU.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$en=Get-Content -LiteralPath (Join-Path $root 'i18n\en-US.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$ruKeys=@($ru.messages.PSObject.Properties|ForEach-Object {$_.Name}|Sort-Object)
$enKeys=@($en.messages.PSObject.Properties|ForEach-Object {$_.Name}|Sort-Object)
if(($ruKeys -join '|') -cne ($enKeys -join '|')){throw 'Translation catalog coverage differs between Russian and English'}
if($ruKeys.Count -lt 90){throw 'Translation catalog is incomplete'}
foreach($k in $ruKeys){
    $rv=[string]$ru.messages.$k
    $ev=[string]$en.messages.$k
    if([string]::IsNullOrWhiteSpace($rv) -or [string]::IsNullOrWhiteSpace($ev)){
        throw ('Missing translation for '+$k)
    }
    # Require matching format placeholders so new locales cannot break runtime.
    $format='\{\d+\}'
    $rup=[regex]::Matches($rv,$format)|ForEach-Object{$_.Value}|Sort-Object
    $enp=[regex]::Matches($ev,$format)|ForEach-Object{$_.Value}|Sort-Object
    if(($rup -join '|') -cne ($enp -join '|')){throw ('Format placeholders differ: '+$k)}
}
if((Get-GuardText -Key 'home.stop') -ne 'Остановить uTempGuard'){throw 'Russian text lookup failed'}
$null=Set-GuardLanguage -Locale 'en-US'
if((Get-GuardText -Key 'home.stop') -ne 'Stop uTempGuard'){throw 'English text lookup failed'}
if((Get-GuardText -Key 'home.temperature' -Values @(41)) -notmatch '41°C'){throw 'Number formatting failed'}
if((Get-GuardCurrentLanguage) -ne 'en-US'){throw 'Language switch failed'}
$null=Initialize-GuardLocalization -DataDirectory $base
if((Get-GuardCurrentLanguage) -ne 'en-US'){throw 'Local preference did not persist'}
$invalidWasRejected=$false
try{$null=Set-GuardLanguage -Locale '..\evil'}catch{$invalidWasRejected=$true}
if(-not $invalidWasRejected){throw 'Locale path traversal accepted'}
$languageFile=Join-Path $base 'language.json'
[IO.File]::WriteAllText($languageFile,'{ broken file',[Text.UTF8Encoding]::new($false))
$null=Initialize-GuardLocalization -DataDirectory $base
if((Get-GuardCurrentLanguage) -ne 'ru-RU'){throw 'Corrupt settings did not fail safely to Russian'}
if(Test-Path -LiteralPath (Join-Path $base 'config.json')){throw 'Localization test touched power config'}
Write-Output ('PASS: {0} bilingual keys, format placeholders, language persistence and safe fallback.' -f $ruKeys.Count)
