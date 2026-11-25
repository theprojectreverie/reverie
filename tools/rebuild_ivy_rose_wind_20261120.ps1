$root='C:\Users\quoth\Documents\Default Project\project-fantasy'
$items=@(
  @{Name='rose_bush_02';Old='5';New='7';Amplitude='1.1';Speed='0.88';Phase='0.8'},
  @{Name='ivy_wall_01';Old='3';New='5';Amplitude='0.45';Speed='0.72';Phase='2.1'},
  @{Name='ivy_wall_02';Old='3';New='5';Amplitude='0.5';Speed='0.78';Phase='4.5'}
)
foreach($item in $items){
  $name=$item.Name
  $path=Join-Path $root "scenes\world\reverie_pack\Royal_Gardens\Vegetation\$name.tscn"
  $backup="$path.pre_wind_shader_20261120.bak"
  $content=Get-Content -LiteralPath $backup -Raw
  $content=$content.Replace("[gd_scene load_steps=$($item.Old) format=3]","[gd_scene load_steps=$($item.New) format=3]")
  $anchor='[ext_resource type="Texture2D" path="res://assets/reverie_pack_v01/Royal_Gardens/Vegetation/'+$name+'.png" id="2_tex"]'
  if(-not $content.Contains($anchor)){ throw "Texture anchor missing: $name" }
  $ext='[ext_resource type="Shader" path="res://shaders/world/foliage_canopy_wind.gdshader" id="4_wind"]'
  $content=$content.Replace($anchor,$anchor+[Environment]::NewLine+$ext)
  $sub='[sub_resource type="ShaderMaterial" id="CanopyWindMaterial"]'+[Environment]::NewLine+'shader = ExtResource("4_wind")'+[Environment]::NewLine+'shader_parameter/wind_amplitude = '+$item.Amplitude+[Environment]::NewLine+'shader_parameter/wind_speed = '+$item.Speed+[Environment]::NewLine+'shader_parameter/wind_phase = '+$item.Phase+[Environment]::NewLine+[Environment]::NewLine
  $first=[regex]::Match($content,'(?m)^\[node ')
  if(-not $first.Success){ throw "Node section missing: $name" }
  $content=$content.Insert($first.Index,$sub)
  $textureLine='texture = ExtResource("2_tex")'
  if(-not $content.Contains($textureLine)){ throw "Sprite texture line missing: $name" }
  $content=$content.Replace($textureLine,$textureLine+[Environment]::NewLine+'material = SubResource("CanopyWindMaterial")')
  Set-Content -LiteralPath $path -Value $content -NoNewline
  Write-Output "REBUILT $name"
}