$root='C:\Users\quoth\Documents\Default Project\project-fantasy\scenes\world\reverie_pack\Royal_Gardens\Vegetation'
$items=@(@('bush_flowering_01.tscn',0.6,0.75,0.4),@('bush_round_01.tscn',1.0,0.8,1.6),@('flower_patch_01.tscn',0.35,1.05,2.8),@('grass_tuft_01.tscn',0.22,1.2,4.0),@('rose_bush_01.tscn',1.3,0.9,5.2))
foreach($item in $items){
 $path=Join-Path $root $item[0]
 $s=[IO.File]::ReadAllText($path)
 if($s.Contains('CanopyWindMaterial')){throw "Already patched: $path"}
 Copy-Item $path ($path+'.pre_wind_shader_20261120.bak') -Force
 $s=[regex]::Replace($s,'\[gd_scene load_steps=(\d+) format=3\]',{param($m) "[gd_scene load_steps=$([int]$m.Groups[1].Value+2) format=3]"},1)
 $anchor='[ext_resource type="Texture2D" path="res://assets/castle_pack_v02/effects/shadow_blob_64.png" id="3_shadow"]'
 if(!$s.Contains($anchor)){throw "Shadow resource anchor missing: $path"}
 $s=$s.Replace($anchor,$anchor+[Environment]::NewLine+'[ext_resource type="Shader" path="res://shaders/world/foliage_canopy_wind.gdshader" id="4_wind"]')
 $nl=[Environment]::NewLine
 $material='[sub_resource type="ShaderMaterial" id="CanopyWindMaterial"]'+$nl+'shader = ExtResource("4_wind")'+$nl+"shader_parameter/wind_amplitude = $($item[1])"+$nl+"shader_parameter/wind_speed = $($item[2])"+$nl+"shader_parameter/wind_phase = $($item[3])"+$nl+$nl
 $insert='[node name="Sprite" type="Sprite2D" parent="."]'
 if(!$s.Contains($insert)){throw "Sprite node anchor missing: $path"}
 $s=$s.Replace($insert,$material+$insert)
 $tex='texture = ExtResource("2_tex")'
 if(!$s.Contains($tex)){throw "Texture anchor missing: $path"}
 $s=$s.Replace($tex,$tex+$nl+'material = SubResource("CanopyWindMaterial")')
 [IO.File]::WriteAllText($path,$s,[Text.UTF8Encoding]::new($false))
 Write-Output ("PATCHED "+$item[0])
}