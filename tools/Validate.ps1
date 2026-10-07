param([string]$PZRoot='E:\Steam\steamapps\common\ProjectZomboid',[string]$JdkRoot='C:\Program Files\Java\jdk-25')
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$package=Join-Path $repo 'Contents\mods\MoodleEffectsExplainedUnified'
$info=Get-Content -LiteralPath "$package\42.20\mod.info" -Raw
if($info -match '(?m)^(require|incompatible|loadAfter|loadBefore)='){throw 'Forbidden dependency/incompatibility/load-order metadata'}
$luaFiles=& rg --files $package -g '*.lua'
foreach($file in $luaFiles){ & 'C:\Program Files (x86)\Lua\5.1\luac.exe' -p $file; if($LASTEXITCODE -ne 0){throw 'Lua syntax failed'} }
$classes=Join-Path $repo 'tests\classes'; New-Item -ItemType Directory -Path $classes -Force|Out-Null
$jar=Join-Path $PZRoot 'projectzomboid.jar'
& "$JdkRoot\bin\javac.exe" --release 17 -encoding UTF-8 -classpath $jar -d $classes "$repo\tests\RunMEEProbe.java" "$repo\tests\UnifiedProfileProbe.java"
if($LASTEXITCODE -ne 0){throw 'Native probes failed compilation'}
Push-Location $PZRoot
try {
    foreach($probe in @('RunMEEProbe','UnifiedProfileProbe')){
        & "$JdkRoot\bin\java.exe" --enable-native-access=ALL-UNNAMED -ea -classpath "$classes;$jar" $probe $repo
        if($LASTEXITCODE -ne 0){throw "Native probe failed: $probe"}
    }
}finally{Pop-Location}
git -C $repo diff --check
if($LASTEXITCODE -ne 0){throw 'Whitespace check failed'}
Write-Output 'PASS single-package metadata, Lua syntax, native tooltip regression and all language/profile combinations.'
