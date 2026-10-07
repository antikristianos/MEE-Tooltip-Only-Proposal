param([string]$Commit='HEAD',[string]$OutputPath)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$sourceCommit=git -C $repo rev-parse --verify "$Commit^{commit}"
if($LASTEXITCODE -ne 0){throw 'Invalid source commit'}
$artifacts=Join-Path $repo 'artifacts'
New-Item -ItemType Directory -Path $artifacts -Force|Out-Null
if(-not $OutputPath){$OutputPath=Join-Path $artifacts 'MEE-Unified-0.1-test.zip'}
$OutputPath=[IO.Path]::GetFullPath($OutputPath)
if(Test-Path -LiteralPath $OutputPath){throw 'Output ZIP already exists; use a new output path'}
$payload=Join-Path $artifacts ('payload-'+[Guid]::NewGuid().ToString('N')+'.zip')
$prefix='Contents/mods/MoodleEffectsExplainedUnified/'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$manifest=@()
$utf8=New-Object Text.UTF8Encoding($false)
function Get-BytesHash([byte[]]$bytes){
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()}
    finally{$sha.Dispose()}
}
function Write-ZipEntry($archive,[string]$name,[byte[]]$bytes){
    $entry=$archive.CreateEntry($name,[IO.Compression.CompressionLevel]::Optimal)
    $stream=$entry.Open()
    try{$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
}
try{
    git -C $repo archive --format=zip --output=$payload $sourceCommit -- Contents/mods/MoodleEffectsExplainedUnified
    if($LASTEXITCODE -ne 0){throw 'Cannot export source commit'}
    $inputZip=[IO.Compression.ZipFile]::OpenRead($payload)
    $outputZip=[IO.Compression.ZipFile]::Open($OutputPath,[IO.Compression.ZipArchiveMode]::Create)
    try{
        foreach($entry in $inputZip.Entries){
            if(-not $entry.Name){continue}
            if(-not $entry.FullName.StartsWith($prefix,[StringComparison]::Ordinal)){throw 'Unexpected source path'}
            $name='MoodleEffectsExplainedUnified/'+$entry.FullName.Substring($prefix.Length)
            $stream=$entry.Open();$buffer=New-Object IO.MemoryStream
            try{$stream.CopyTo($buffer);$bytes=$buffer.ToArray()}finally{$stream.Dispose();$buffer.Dispose()}
            Write-ZipEntry $outputZip $name $bytes
            $manifest += [pscustomobject]@{path=$name;bytes=$bytes.Length;sha256=(Get-BytesHash $bytes)}
        }
        $guide=[IO.File]::ReadAllBytes((Join-Path $repo 'docs\TESTING-DOWNLOAD.md'))
        Write-ZipEntry $outputZip 'README-TESTING.md' $guide
        $manifest += [pscustomobject]@{path='README-TESTING.md';bytes=$guide.Length;sha256=(Get-BytesHash $guide)}
        $metadata=[ordered]@{proposal_version='0.1';source_commit=$sourceCommit;tested_game='42.21';manual_test_status='Tests 1-3 reported passed; test 4 not performed';files=$manifest}
        Write-ZipEntry $outputZip 'PACKAGE-MANIFEST.json' $utf8.GetBytes(($metadata|ConvertTo-Json -Depth 6)+"`n")
    }finally{$inputZip.Dispose();$outputZip.Dispose()}
    $verify=[IO.Compression.ZipFile]::OpenRead($OutputPath)
    try{
        if($verify.Entries.Count -ne $manifest.Count+1){throw 'Unexpected ZIP file count'}
        foreach($item in $manifest){
            $entry=$verify.GetEntry($item.path);if(-not $entry){throw 'Missing ZIP entry'}
            $stream=$entry.Open();$buffer=New-Object IO.MemoryStream
            try{$stream.CopyTo($buffer);$bytes=$buffer.ToArray()}finally{$stream.Dispose();$buffer.Dispose()}
            if((Get-BytesHash $bytes) -ne $item.sha256){throw "ZIP integrity failed: $($item.path)"}
        }
    }finally{$verify.Dispose()}
    $hash=(Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText($OutputPath+'.sha256',$hash+'  '+[IO.Path]::GetFileName($OutputPath)+"`n",$utf8)
    Write-Output "Verified ZIP: $OutputPath"
    Write-Output "Source commit: $sourceCommit; mod files: $($manifest.Count-1); SHA256: $hash"
}finally{if(Test-Path -LiteralPath $payload){Remove-Item -LiteralPath $payload}}
