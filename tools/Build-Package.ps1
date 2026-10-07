$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$package = Join-Path $repo 'Contents\mods\MoodleEffectsExplainedUnified'
$utf8 = New-Object System.Text.UTF8Encoding($false)
New-Item -ItemType Directory -Path "$package\42.20\media\lua\shared\Translate","$package\common\media\lua\client\MEE" -Force | Out-Null
$profiles = [ordered]@{ Base='MoodleEffectsExplained'; EM='MoodleEffectsExplained_ExpandedMoodles'; DTEM='MoodleEffectsExplained_DTEM' }
$languages = @(Get-ChildItem -LiteralPath "$repo\upstream\MoodleEffectsExplained\42.20\media\lua\shared\Translate" -Directory | Select-Object -ExpandProperty Name)
$allKeys = New-Object 'System.Collections.Generic.SortedSet[string]'
foreach ($language in $languages) {
    $combined = [ordered]@{}
    foreach ($profile in $profiles.Keys) {
        $source = "$repo\upstream\$($profiles[$profile])\42.20\media\lua\shared\Translate\$language\Moodles.json"
        $data = Get-Content -LiteralPath $source -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($property in $data.PSObject.Properties) {
            $allKeys.Add($property.Name) | Out-Null
            if ($profile -eq 'Base') { $combined[$property.Name] = $property.Value }
            $combined["Moodles_MEEProfile_${profile}_$($property.Name)"] = $property.Value
        }
    }
    $target = "$package\42.20\media\lua\shared\Translate\$language\Moodles.json"
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    [IO.File]::WriteAllText($target, ($combined | ConvertTo-Json -Depth 4) + "`n", $utf8)
}
$keysLua = "return {`n" + (($allKeys | ForEach-Object { '    "' + $_ + '",' }) -join "`n") + "`n}`n"
[IO.File]::WriteAllText("$package\common\media\lua\client\MEE\ProfileKeys.lua", $keysLua, $utf8)
foreach ($language in $languages) {
    $destination="$package\common\media\lua\shared\Translate\$language"
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    [IO.File]::WriteAllBytes("$destination\UI.json", [IO.File]::ReadAllBytes("$repo\upstream\MoodleEffectsExplained\common\media\lua\shared\Translate\$language\UI.json"))
}
foreach($art in @('mee_icon.png','mee_poster.png')) {
    [IO.File]::WriteAllBytes("$package\common\$art", [IO.File]::ReadAllBytes("$repo\upstream\MoodleEffectsExplained\common\$art"))
}
Write-Output "Built one package: $($languages.Count) languages; $($allKeys.Count) original keys per profile."
