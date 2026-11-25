$root='C:\Users\quoth\Documents\Default Project\project-fantasy'
$godot='C:\Users\quoth\Downloads\Godot_4.7.2_runtime\Godot_v4.7.2-stable_win64_console.exe'
$log=Join-Path $root 'artifacts\foliage_wind_expanded_smoke_20261120.log'
& $godot --headless --path $root 'res://tests/foliage_wind_material_smoke.tscn' *> $log
$code=$LASTEXITCODE
Add-Content $log "EXIT_CODE=$code"
exit $code