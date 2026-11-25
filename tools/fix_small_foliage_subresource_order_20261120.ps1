$root='C:\Users\quoth\Documents\Default Project\project-fantasy'
$names=@('bush_flowering_01','bush_round_01','flower_patch_01','grass_tuft_01','rose_bush_01')
foreach($name in $names){
  $path=Join-Path $root "scenes\world\reverie_pack\Royal_Gardens\Vegetation\$name.tscn"
  $content=Get-Content -LiteralPath $path -Raw
  $pattern='(?ms)^\[sub_resource type="ShaderMaterial" id="CanopyWindMaterial"\]\r?\n.*?(?=^\[node )'
  $match=[regex]::Match($content,$pattern)
  if(-not $match.Success){ throw "ShaderMaterial block not found in $name" }
  $block=$match.Value.TrimEnd()+[Environment]::NewLine+[Environment]::NewLine
  $content=$content.Remove($match.Index,$match.Length)
  $firstNode=[regex]::Match($content,'(?m)^\[node ')
  if(-not $firstNode.Success){ throw "No node section in $name" }
  $content=$content.Insert($firstNode.Index,$block)
  Set-Content -LiteralPath $path -Value $content -NoNewline
  Write-Output "REORDERED $name"
}