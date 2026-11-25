$root='C:\Users\quoth\Documents\Default Project\project-fantasy'
$test=Join-Path $root 'tests\foliage_wind_material_smoke.gd'
$content=Get-Content -LiteralPath $test -Raw
$old='"res://scenes/world/reverie_pack/Royal_Gardens/Vegetation/rose_bush_01.tscn"'
$new=@'
"res://scenes/world/reverie_pack/Royal_Gardens/Vegetation/rose_bush_01.tscn",
	"res://scenes/world/reverie_pack/Royal_Gardens/Vegetation/rose_bush_02.tscn",
	"res://scenes/world/reverie_pack/Royal_Gardens/Vegetation/ivy_wall_01.tscn",
	"res://scenes/world/reverie_pack/Royal_Gardens/Vegetation/ivy_wall_02.tscn"
'@.Trim()
if(-not $content.Contains($old)){ throw 'Test scene list anchor missing' }
$content=$content.Replace($old,$new)
Set-Content -LiteralPath $test -Value $content -NoNewline
Write-Output 'EXPANDED QA LIST TO 13 SCENES'