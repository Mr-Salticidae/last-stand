$root = "D:\MyGame\LastStand\last-stand\assets\models\quaternius"
$out = "D:\MyGame\LastStand\last-stand\tools\glb_dumps"
if (-not (Test-Path $out)) { New-Item -ItemType Directory -Path $out | Out-Null }

Get-ChildItem -Path $root -Recurse -Filter *.glb | ForEach-Object {
    $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
    $jlen = [BitConverter]::ToUInt32($bytes, 12)
    $jtxt = [System.Text.Encoding]::UTF8.GetString($bytes, 20, $jlen).TrimEnd([char]0, ' ')
    $rel = $_.FullName.Substring($root.Length + 1).Replace('\','__').Replace(' ','_').Replace('.glb','.json')
    $outPath = Join-Path $out $rel
    Set-Content -Path $outPath -Value $jtxt -Encoding UTF8
    Write-Output "Wrote $outPath"
}
