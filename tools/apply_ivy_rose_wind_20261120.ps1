$root='C:\Users\quoth\Documents\Default Project\project-fantasy'
$items=@(
  @{Name='rose_bush_02';Amplitude='1.1';Speed='0.88';Phase='0.8'},
  @{Name='ivy_wall_01';Amplitude='0.45';Speed='0.72';Phase='2.1'},
  @{Name='ivy_wall_02';Amplitude='0.5';Speed='0.78';Phase='4.5'}
)
foreach($item in $items){
  $name=$item.Name
  $path=Join-Path $root "scenes\world\reverie_pack\Royal_Gardens\Vegetation\$name.tscn"
  $content=Get-Content -LiteralPath $path -Raw
  if($content.Contains('CanopyWindMaterial')){ throw "Already wind-enabled: $name" }
  $backup="$path.pre_wind_shader_20261120.bak"
  if(-not (Test-Path $backup)){ Copy-Item -LiteralPath $path -Destination $backup }
  $content=$content -replace '^\[gd_scene load_steps=(\d+)',{ param($m) '[gd_scene load_steps=' + ([int]$m.Groups[1].Value + 2) }
  $ext='[ext_resource type="Shader" path="res://shaders/world/foliage_canopy_wind.gdshader" id="4_wind"]'+[Environment]::NewLine+[Environment]::NewLine
  $anchor='[ext_resource type="Texture2D" path="res://assets/reverie_pack_v01/Royal_Gardens/Vegetation/'+$name+'.png" id="2_tex"]'
  if(-not $content.Contains($anchor)){ throw "Texture anchor missing: $name" }
  $content=$content.Replace($anchor,$anchor+[Environment]::NewLine+$ext.TrimEnd())
  $sub='[sub_resource type="ShaderMaterial" id="CanopyWindMaterial"]'+[Environment]::NewLine+'shader = ExtResource("4_wind")'+[Environment]::NewLine+'shader_parameter/wind_amplitude = '+$item.Amplitude+[Environment]::NewLine+'shader_parameter/wind_speed = '+$item.Speed+[Environment]::NewLine+'shader_parameter/wind_phase = '+$item.Phase+[Environment]::NewLine+[Environment]::NewLine
  $first=[regex]::Match($content,'(?m)^\[node ')
  if(-not $first.Success){ throw "Node section missing: $name" }
  $content=$content.Insert($first.Index,$sub)
  $content=$content -replace '(?m)^texture = ExtResource\("2_tex"\)$','texture = ExtResource("2_tex")'+[Environment]::NewLine+'material = SubResource("CanopyWindMaterial")'
  Set-Content -LiteralPath $path -Value $content -NoNewline
  Write-Output "WIND PATCHED $name amplitude=$($item.Amplitude) speed=$($item.Speed) phase=$($item.Phase)"
}