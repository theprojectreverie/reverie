extends SceneTree

const PALETTE: Array[Color] = [
	Color(0,0,0,0), Color("#241c32"), Color("#493653"), Color("#79516a"),
	Color("#b56d88"), Color("#e6a0ad"), Color("#f6d7b0"), Color("#5b7b4b"),
	Color("#91ad5d"), Color("#c7c66e"), Color("#754b3b"), Color("#b47a50"),
	Color("#65738d"), Color("#9ba8ba"), Color("#8d5ac4"), Color("#d6a5ff"),
]

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	var root := "res://assets/pixelpen_act1"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	var specs := [
		{"id":"royal_gate","name":"Royal Gate","kind":0},
		{"id":"willow_windmill","name":"Willow Fields Windmill","kind":1},
		{"id":"elderwood_ancient_tree","name":"Elderwood Ancient Tree","kind":2},
		{"id":"forsaken_ruins_arch","name":"Forsaken Ruins Arch","kind":3},
		{"id":"ruined_tower","name":"Ruined Tower","kind":4},
	]
	for spec in specs:
		var project := PixelPenProject.new()
		project.initialized(Vector2i(64,64), str(spec.name), "", true)
		project.palette.color_index.resize(256)
		project.palette.color_index.fill(Color.TRANSPARENT)
		for i in PALETTE.size():
			project.palette.color_index[i] = PALETTE[i]
		project.palette.grid_sync_to_palette()
		project.background_color = PixelPenProject.BackgroundColor.TRANSPARENT
		project.show_grid = true
		var layer := project.active_layer
		layer.label = "PixelPen Art"
		var img := layer.colormap
		_draw_asset(img, int(spec.kind))
		var png := root + "/" + str(spec.id) + ".png"
		var pxpen := root + "/" + str(spec.id) + ".pxpen"
		var save_error := ProjectPacker.save(project, ProjectSettings.globalize_path(pxpen))
		var export_error := project.export_png_image(ProjectSettings.globalize_path(png))
		print("PIXELPEN_ASSET ", spec.id, " pxpen=", save_error, " png=", export_error, " size=", project.canvas_size)
	quit()

func _put(img: Image, x: int, y: int, c: int) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, Color8(c,0,0,0))

func _rect(img: Image, x: int, y: int, w: int, h: int, c: int) -> void:
	for py in range(y, y+h):
		for px in range(x, x+w):
			_put(img,px,py,c)

func _line(img: Image, x0: int, y0: int, x1: int, y1: int, c: int, thickness: int = 1) -> void:
	var dx := absi(x1-x0)
	var sx := 1 if x0 < x1 else -1
	var dy := -absi(y1-y0)
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	while true:
		for oy in range(-thickness/2, thickness/2+1):
			for ox in range(-thickness/2, thickness/2+1):
				_put(img,x0+ox,y0+oy,c)
		if x0 == x1 and y0 == y1: break
		var e2 := 2*err
		if e2 >= dy: err += dy; x0 += sx
		if e2 <= dx: err += dx; y0 += sy

func _ellipse(img: Image, cx: int, cy: int, rx: int, ry: int, c: int) -> void:
	for y in range(cy-ry,cy+ry+1):
		for x in range(cx-rx,cx+rx+1):
			var nx := float(x-cx)/maxf(1.0,float(rx))
			var ny := float(y-cy)/maxf(1.0,float(ry))
			if nx*nx+ny*ny <= 1.0: _put(img,x,y,c)

func _draw_asset(img: Image, kind: int) -> void:
	# Palette-indexed drawing directly into a PixelPen layer.
	if kind == 0: # royal gate: gilded arch and violet enamel
		_rect(img,8,45,48,7,2); _rect(img,12,20,8,29,1); _rect(img,44,20,8,29,1)
		_rect(img,15,23,3,23,12); _rect(img,46,23,3,23,12)
		_rect(img,19,28,26,22,2); _rect(img,22,31,20,18,14)
		_rect(img,25,35,14,14,1); _rect(img,29,38,6,11,15)
		_line(img,12,20,20,10,6,3); _line(img,52,20,44,10,6,3); _line(img,20,10,44,10,6,3)
		for x in [13,18,46,51]: _rect(img,x,15,3,5,9)
		for x in [22,27,32,37,42]: _put(img,x,27,6)
	elif kind == 1: # willow fields windmill with warm thatch and wheat rows
		_rect(img,25,34,16,17,10); _rect(img,28,39,5,12,11); _rect(img,35,40,4,5,6)
		_line(img,23,35,32,25,6,3); _line(img,32,25,43,35,6,3); _line(img,43,35,23,35,6,3)
		_rect(img,28,29,9,5,11); _line(img,27,29,32,22,6,3); _line(img,32,22,39,29,6,3)
		_line(img,32,24,32,7,10,3); _line(img,32,24,48,24,10,3); _line(img,32,24,32,41,10,3); _line(img,32,24,16,24,10,3)
		_ellipse(img,32,24,3,3,6); _rect(img,5,52,54,2,7)
		for x in range(7,60,6): _line(img,x,57,x+3,48,9,1)
		for x in [8,14,50,56]: _ellipse(img,x,46,2,2,5)
	elif kind == 2: # ancient elderwood with roots, broad crown, moonlit blooms
		_line(img,31,30,29,57,10,7); _line(img,31,37,18,49,10,3); _line(img,31,40,46,51,10,3)
		_line(img,29,55,18,59,10,2); _line(img,31,55,43,60,10,2)
		for p in [Vector2i(17,19),Vector2i(28,12),Vector2i(43,17),Vector2i(13,30),Vector2i(47,30),Vector2i(31,27)]: _ellipse(img,p.x,p.y,10,9,2)
		for p in [Vector2i(18,18),Vector2i(29,12),Vector2i(42,18),Vector2i(13,29),Vector2i(48,29),Vector2i(31,26)]: _ellipse(img,p.x,p.y,6,6,7)
		for p in [Vector2i(17,16),Vector2i(29,10),Vector2i(44,16),Vector2i(11,27),Vector2i(49,27)]: _ellipse(img,p.x,p.y,3,3,8)
		for p in [Vector2i(20,20),Vector2i(38,17),Vector2i(48,32),Vector2i(23,31)]: _put(img,p.x,p.y,15)
	elif kind == 3: # broken processional arch, cracked stone and corruption
		_rect(img,9,45,46,7,1); _rect(img,12,21,8,28,12); _rect(img,44,25,8,24,12)
		_rect(img,14,24,4,22,13); _rect(img,46,28,4,18,13)
		_line(img,12,22,20,13,12,4); _line(img,20,13,30,17,12,4); _line(img,30,17,38,11,12,4); _line(img,38,11,51,25,12,4)
		_line(img,14,24,19,20,13,2); _line(img,46,28,50,33,13,2)
		_line(img,18,45,26,37,4,2); _line(img,26,37,30,42,4,2); _line(img,48,45,42,38,4,2)
		for p in [Vector2i(22,47),Vector2i(27,51),Vector2i(38,49),Vector2i(42,53)]: _rect(img,p.x,p.y,4,2,3)
		for p in [Vector2i(24,30),Vector2i(35,24),Vector2i(42,33)]: _put(img,p.x,p.y,15)
	elif kind == 4: # narrow ruined tower with violet core and fractured crown
		_rect(img,20,28,25,29,1); _rect(img,24,31,17,23,12); _rect(img,28,35,9,19,14)
		_line(img,18,29,23,17,2,3); _line(img,23,17,30,23,2,3); _line(img,30,23,37,14,2,3); _line(img,37,14,47,29,2,3)
		_rect(img,26,25,13,5,2); _rect(img,30,7,5,14,1); _line(img,32,7,32,1,15,2)
		_rect(img,31,37,4,9,15); _rect(img,25,46,3,5,4); _rect(img,39,43,3,8,4)
		for p in [Vector2i(15,52),Vector2i(50,53),Vector2i(11,57),Vector2i(54,58)]: _line(img,p.x,p.y,p.x+2,p.y-7,14,2)
		for p in [Vector2i(24,22),Vector2i(41,19),Vector2i(45,33)]: _put(img,p.x,p.y,15)
