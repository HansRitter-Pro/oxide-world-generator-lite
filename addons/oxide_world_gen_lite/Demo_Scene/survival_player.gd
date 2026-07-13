extends Sprite2D
class_name SurvivalPlayer

signal stats_updated(energy: float, hunger: float, thirst: float)
signal destination_reached()

@export_group("References")
@export var world_map: TileMapLayer 

@export_group("Stats")
@export var max_energy: float = 100.0
@export var max_hunger: float = 100.0
@export var max_thirst: float = 100.0
@export var base_speed: float = 1200.0

var current_energy: float
var current_hunger: float
var current_thirst: float
var current_time: float = 480.0 
var total_distance_meters: float = 0.0

var is_moving: bool = false
var path: Array[Vector2i] = [] 
var current_path_index: int = 0

var biome_stats = {
	0: {"name": "Swamp", "speed": 0.15, "energy": 0.25, "time": 0.6, "thirst_mult": 1.5, "color": Color(0.18, 0.25, 0.15)},
	1: {"name": "Shallow water/River", "speed": 0.2, "energy": 0.15, "time": 0.4, "thirst_mult": 1.0, "color": Color(0.1, 0.4, 0.7)},
	3: {"name": "Deciduous Forest", "speed": 0.7, "energy": 0.04, "time": 0.2, "thirst_mult": 1.0, "color": Color(0.15, 0.45, 0.2)},
	4: {"name": "Old Highway", "speed": 1.2, "energy": 0.01, "time": 0.1, "thirst_mult": 1.0, "color": Color(0.25, 0.25, 0.25)},
	5: {"name": "Shore", "speed": 0.85, "energy": 0.03, "time": 0.15, "thirst_mult": 1.1, "color": Color(0.85, 0.8, 0.6)},
	7: {"name": "Plains", "speed": 1.0, "energy": 0.02, "time": 0.12, "thirst_mult": 1.0, "color": Color(0.4, 0.65, 0.3)},
	8: {"name": "Hills", "speed": 0.5, "energy": 0.08, "time": 0.3, "thirst_mult": 1.2, "color": Color(0.5, 0.45, 0.4)},
	10: {"name": "Deep water/Lake", "speed": 0.1, "energy": 0.4, "time": 1.2, "thirst_mult": 1.0, "color": Color(0.05, 0.25, 0.55)},
	14: {"name": "Taiga", "speed": 0.6, "energy": 0.05, "time": 0.25, "thirst_mult": 1.0, "color": Color(0.1, 0.3, 0.2)},
}

var astar = AStarGrid2D.new()
var camera: Camera2D
var game_log: Label
var day_night: CanvasModulate

var energy_bar: ProgressBar
var hunger_bar: ProgressBar
var thirst_bar: ProgressBar
var time_label: Label
var distance_label: Label 
var tooltip_label: Label
var safe_canvas_layer: CanvasLayer

var fog_material: ShaderMaterial 
var fog_rect: ColorRect 
var last_fog_clear_cell = Vector2i(-999, -999) 

var minimap_container: Panel
var minimap_rect: TextureRect
var minimap_img: Image
var minimap_tex: ImageTexture
var minimap_needs_update: bool = false

var explored_tiles = {} 
var mm_ui_size = 200 
var minimap_zoom: float = 0.2 

var fog_time: float = 0.0 

func _ready():
	z_index = 10
	camera = get_node_or_null("PlayerCamera")
	
	var scene = get_tree().current_scene
	if scene.find_child("GameLogLabel", true, false): game_log = scene.find_child("GameLogLabel", true, false)
	if scene.find_child("EnergyBar", true, false): energy_bar = scene.find_child("EnergyBar", true, false)
	if scene.find_child("HungerBar", true, false): hunger_bar = scene.find_child("HungerBar", true, false)
	if scene.find_child("ThirstBar", true, false): thirst_bar = scene.find_child("ThirstBar", true, false)
	
	safe_canvas_layer = CanvasLayer.new()
	safe_canvas_layer.layer = 120 
	scene.add_child.call_deferred(safe_canvas_layer)
	
	_build_minimap_and_stats() 
	
	tooltip_label = Label.new()
	tooltip_label.add_theme_font_size_override("font_size", 16)
	tooltip_label.add_theme_color_override("font_color", Color.WHITE)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.7)
	style.content_margin_left = 6
	style.content_margin_right = 6
	tooltip_label.add_theme_stylebox_override("normal", style)
	safe_canvas_layer.add_child.call_deferred(tooltip_label)
	
	day_night = CanvasModulate.new()
	scene.add_child.call_deferred(day_night)
	
	current_energy = max_energy
	current_hunger = max_hunger
	current_thirst = max_thirst
	
	if world_map:
		astar.cell_size = Vector2(64, 64)
		astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
		astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
		astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	
	setup_fog_of_war() 
	
	add_log("Oxide LITE loaded. Safe exploration initialized.")
	update_ui_bars()
	update_day_night_lighting()

func is_infinite_energy_enabled() -> bool:
	var main_menu = get_tree().current_scene.find_child("MainMenu", true, false)
	if main_menu and "infinite_energy" in main_menu:
		return main_menu.infinite_energy
	return true

func reset_player_data():
	explored_tiles.clear() 
	path.clear()           
	is_moving = false
	total_distance_meters = 0.0
	
	current_time = 480.0
	current_energy = max_energy
	current_hunger = max_hunger
	current_thirst = max_thirst
	
	update_ui_bars()
	update_day_night_lighting()
	
	if distance_label:
		distance_label.text = "Distance: 0.00 km"
	if minimap_img:
		minimap_img.fill(Color(0.02, 0.02, 0.03, 1.0))
		minimap_needs_update = true
	queue_redraw()

func _build_minimap_and_stats():
	minimap_container = Panel.new()
	minimap_container.clip_contents = true 
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color(0.02, 0.02, 0.03, 1.0) 
	p_style.border_width_left = 2; p_style.border_width_top = 2; p_style.border_width_right = 2; p_style.border_width_bottom = 2
	p_style.border_color = Color(0.3, 0.3, 0.3)
	minimap_container.add_theme_stylebox_override("panel", p_style)
	
	minimap_container.anchor_left = 1.0; minimap_container.anchor_right = 1.0
	minimap_container.offset_left = -220; minimap_container.offset_right = -20
	minimap_container.offset_top = 20; minimap_container.offset_bottom = 220
	safe_canvas_layer.add_child.call_deferred(minimap_container)

	minimap_img = Image.create(mm_ui_size, mm_ui_size, false, Image.FORMAT_RGBA8)
	minimap_img.fill(Color(0.02, 0.02, 0.03, 1.0)) 
	minimap_tex = ImageTexture.create_from_image(minimap_img)
	
	minimap_rect = TextureRect.new()
	minimap_rect.texture = minimap_tex
	minimap_rect.scale = Vector2(1.0, 1.0) 
	minimap_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	minimap_container.add_child(minimap_rect)
	
	var player_dot = ColorRect.new()
	player_dot.color = Color.RED
	player_dot.size = Vector2(4, 4)
	player_dot.position = Vector2(mm_ui_size/2 - 2, mm_ui_size/2 - 2) 
	minimap_container.add_child(player_dot)
	
	time_label = Label.new()
	time_label.add_theme_font_size_override("font_size", 20)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time_label.text = "08:00"
	time_label.anchor_left = 1.0; time_label.anchor_right = 1.0
	time_label.offset_left = -220; time_label.offset_right = -20
	time_label.offset_top = 230; time_label.offset_bottom = 260
	safe_canvas_layer.add_child.call_deferred(time_label)
	
	distance_label = Label.new()
	distance_label.add_theme_font_size_override("font_size", 14)
	distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	distance_label.text = "Distance: 0.00 km"
	distance_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	distance_label.anchor_left = 1.0; distance_label.anchor_right = 1.0
	distance_label.anchor_top = 1.0; distance_label.anchor_bottom = 1.0
	distance_label.offset_left = -200; distance_label.offset_right = 0
	distance_label.offset_top = 4; distance_label.offset_bottom = 24
	time_label.add_child.call_deferred(distance_label)

func setup_fog_of_war():
	var fog_layer = CanvasLayer.new()
	fog_layer.layer = 0 
	get_tree().current_scene.add_child.call_deferred(fog_layer)
	fog_rect = ColorRect.new()
	fog_rect.set_anchors_preset(Control.PRESET_FULL_RECT) 
	fog_layer.add_child(fog_rect)

	var shader = Shader.new()
	shader.code = """
	shader_type canvas_item;
	uniform vec2 player_screen_pos;
	uniform float clear_radius = 4500.0; 
	uniform float soft_edge = 1000.0; 
	uniform vec4 fog_color : source_color = vec4(0.05, 0.05, 0.08, 0.7); 
	uniform float zoom_level = 1.0;

	void fragment() {
		vec2 resolution = 1.0 / SCREEN_PIXEL_SIZE;
		vec2 pixel_pos = SCREEN_UV * resolution;
		vec2 player_pos = player_screen_pos * resolution;
		float dist = distance(pixel_pos, player_pos);
		float current_radius = clear_radius * zoom_level;
		float current_edge = soft_edge * zoom_level;
		float alpha = smoothstep(current_radius, current_radius + current_edge, dist);
		COLOR = vec4(fog_color.rgb, fog_color.a * alpha);
	}
	"""
	fog_material = ShaderMaterial.new()
	fog_material.shader = shader
	fog_rect.material = fog_material

func update_fog_of_war():
	if fog_material and camera and fog_rect:
		var main_menu = get_tree().current_scene.find_child("MainMenu", true, false)
		if main_menu and main_menu.visible:
			fog_rect.visible = false
			minimap_container.visible = false
			time_label.visible = false
			distance_label.visible = false
			return
		else:
			fog_rect.visible = true
			minimap_container.visible = true
			time_label.visible = true
			distance_label.visible = true

		var screen_pos = get_global_transform_with_canvas().origin
		var viewport_size = get_viewport_rect().size
		var normalized_pos = screen_pos / viewport_size
		fog_material.set_shader_parameter("player_screen_pos", normalized_pos)
		fog_material.set_shader_parameter("zoom_level", camera.zoom.x)

func clear_fog_map_around_player():
	if world_map == null: return
	var current_cell = world_map.local_to_map(world_map.to_local(global_position))
	
	if current_cell != last_fog_clear_cell:
		var f_map = get_tree().current_scene.find_child("FogMap", true, false)
		if not f_map: return 

		last_fog_clear_cell = current_cell
		var r = 90 
		for x in range(-r, r + 1):
			for y in range(-r, r + 1):
				if x*x + y*y <= r*r:
					var p = current_cell + Vector2i(x, y)
					if f_map.get_cell_source_id(p) != -1:
						f_map.set_cell(p, -1) 
						var tile_id = world_map.get_cell_source_id(p)
						var p_color = Color(0.02, 0.02, 0.03) 
						if biome_stats.has(tile_id): p_color = biome_stats[tile_id]["color"]
						explored_tiles[p] = p_color
		render_minimap_view(current_cell)

func render_minimap_view(center_cell: Vector2i):
	if minimap_img == null: return
	minimap_img.fill(Color(0.02, 0.02, 0.03, 1.0))
	var tiles_per_pixel = 1.0 / minimap_zoom 
	
	for px in range(mm_ui_size):
		for py in range(mm_ui_size):
			var offset_x = int((px - mm_ui_size / 2) * tiles_per_pixel)
			var offset_y = int((py - mm_ui_size / 2) * tiles_per_pixel)
			var map_pos = center_cell + Vector2i(offset_x, offset_y)
			if explored_tiles.has(map_pos):
				minimap_img.set_pixel(px, py, explored_tiles[map_pos])
	minimap_needs_update = true

func _process(delta):
	if is_moving:
		fog_time += delta
		
	update_tooltip()
	update_fog_of_war() 
	clear_fog_map_around_player() 
	
	if minimap_needs_update and minimap_tex:
		minimap_tex.update(minimap_img)
		minimap_needs_update = false
	
	if not is_moving: return
		
	if is_moving and path.size() > 0:
		var target = world_map.to_global(world_map.map_to_local(path[current_path_index]))
		var current_cell = world_map.local_to_map(world_map.to_local(global_position))
		var tile_id = world_map.get_cell_source_id(current_cell)
		
		var b_speed_mult = 1.0
		var b_energy_cost = 0.02 
		var b_time_cost = 0.15    
		var b_thirst_mult = 1.0     
		
		if biome_stats.has(tile_id):
			b_speed_mult = biome_stats[tile_id]["speed"]
			b_energy_cost = biome_stats[tile_id]["energy"]
			b_time_cost = biome_stats[tile_id]["time"]
			if biome_stats[tile_id].has("thirst_mult"):
				b_thirst_mult = biome_stats[tile_id]["thirst_mult"]
			
		var penalty = get_night_penalty(current_time)
		var actual_speed = base_speed * (b_speed_mult / penalty)
		
		var direction = (target - global_position).normalized()
		var step = direction * actual_speed * delta
		
		if global_position.distance_to(target) <= step.length():
			global_position = target
			current_path_index += 1
			if current_path_index >= path.size():
				is_moving = false
				path.clear()
				add_log("🏁 Destination reached.")
		else:
			global_position += step
			
		var distance_moved = step.length()
		var tiles_moved = distance_moved / 64.0
		
		current_energy -= tiles_moved * b_energy_cost * penalty
		var time_passed = tiles_moved * b_time_cost * penalty 
		
		total_distance_meters += tiles_moved * 10.0
		if distance_label:
			distance_label.text = "Distance: %.2f km" % (total_distance_meters / 1000.0)
		
		current_time += time_passed
		current_hunger -= time_passed * (0.8 / 60.0)
		current_thirst -= time_passed * (1.2 / 60.0) * b_thirst_mult
		
		queue_redraw()
		update_ui_bars()
		update_day_night_lighting()
		
		if current_energy <= 0:
			if is_infinite_energy_enabled():
				current_energy = 0.0
			else:
				is_moving = false
				path.clear()
				queue_redraw()
				add_log("💀 Total exhaustion! Movement impossible.")

func add_log(text: String):
	print(text)
	if game_log:
		var time_str = "%02d:%02d" % [int(current_time/60)%24, int(current_time)%60]
		game_log.text += "\n" + time_str + " " + text
		var lines = game_log.text.split("\n")
		if lines.size() > 8:
			var new_lines = lines.slice(lines.size() - 8)
			game_log.text = "\n".join(new_lines)

func _input(event):
	var main_menu = get_tree().current_scene.find_child("MainMenu", true, false)
	if main_menu and main_menu.visible: return

	if event is InputEventMouseButton and event.pressed:
		# Фикс бага: Считаем новый масштаб в безопасной временной переменной
		if camera and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var target_zoom = camera.zoom
			if event.button_index == MOUSE_BUTTON_WHEEL_UP: 
				target_zoom += Vector2(0.1, 0.1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: 
				target_zoom -= Vector2(0.1, 0.1)
			
			# Зажимаем значения в жесткие рамки до применения (0.1 спасает от ошибки нулевого зума)
			target_zoom.x = clamp(target_zoom.x, 0.1, 2.0)
			target_zoom.y = clamp(target_zoom.y, 0.1, 2.0)
			camera.zoom = target_zoom

		if event.button_index == MOUSE_BUTTON_LEFT:
			if world_map == null: return
			
			if current_energy <= 0 and not is_infinite_energy_enabled(): return
			
			if is_moving:
				is_moving = false
				path.clear()
				queue_redraw()
				add_log("🛑 Movement stopped.")
			else:
				var end_cell = world_map.local_to_map(world_map.to_local(get_global_mouse_position()))
				var start_cell = world_map.local_to_map(world_map.to_local(global_position))
				calculate_path(start_cell, end_cell)

func calculate_path(start: Vector2i, end: Vector2i):
	var min_x = min(start.x, end.x) - 10
	var min_y = min(start.y, end.y) - 10
	var grid_w = abs(end.x - start.x) + 20
	var grid_h = abs(end.y - start.y) + 20
	
	if grid_w > 500 or grid_h > 500: return
	
	astar.region = Rect2i(min_x, min_y, grid_w, grid_h)
	astar.update()
	
	for x in range(min_x, min_x + grid_w):
		for y in range(min_y, min_y + grid_h):
			var p = Vector2i(x, y)
			var t_id = world_map.get_cell_source_id(p)
			var weight = 1.0
			
			if t_id == 4: weight = 0.2     
			elif t_id == 20 or t_id == 21: weight = 0.8  
			elif t_id == 7 or t_id == 5: weight = 1.0  
			elif t_id == 3 or t_id == 14: weight = 1.8  
			elif t_id == 8: weight = 2.5   
			elif t_id == 0: weight = 3.0   
			elif t_id == 1: weight = 5.0   
			elif t_id == 10: weight = 10.0 
			astar.set_point_weight_scale(p, weight)
	
	if astar.is_in_bounds(end.x, end.y):
		path = astar.get_id_path(start, end)
		if path.size() > 1:
			current_path_index = 1
			is_moving = true
			add_log("🏃 Squad started moving.")
			queue_redraw()

func get_night_penalty(time_minutes: float) -> float:
	var hour = (int(time_minutes) % 1440) / 60.0
	if hour >= 22.0 or hour < 4.0: return 5.0 
	elif hour >= 20.0 and hour < 22.0: return lerp(1.0, 5.0, (hour - 20.0) / 2.0) 
	elif hour >= 4.0 and hour < 6.0: return lerp(5.0, 1.0, (hour - 4.0) / 2.0) 
	return 1.0 

func update_day_night_lighting():
	if not day_night: return
	var day_minutes = int(current_time) % 1440 
	var hour = day_minutes / 60.0
	var light_color = Color.WHITE
	
	if hour >= 22.0 or hour < 4.0: light_color = Color(0.12, 0.12, 0.20)
	elif hour >= 4.0 and hour < 7.0: light_color = Color(0.12, 0.12, 0.20).lerp(Color(1.0, 0.9, 0.8), (hour - 4.0) / 3.0)
	elif hour >= 7.0 and hour < 18.0: light_color = Color(1.0, 1.0, 1.0)
	elif hour >= 18.0 and hour < 20.0: light_color = Color(1.0, 1.0, 1.0).lerp(Color(0.8, 0.4, 0.2), (hour - 18.0) / 2.0)
	elif hour >= 20.0 and hour < 22.0: light_color = Color(0.8, 0.4, 0.2).lerp(Color(0.12, 0.12, 0.20), (hour - 20.0) / 2.0)
		
	day_night.color = light_color
	if time_label: time_label.text = "%02d:%02d" % [int(current_time/60)%24, int(current_time)%60]

func update_tooltip():
	if not tooltip_label: return
	var mouse_pos = get_global_mouse_position()
	var buildings_layer = get_tree().current_scene.find_child("BuildingsLayer", true, false)
	if buildings_layer:
		for b in buildings_layer.get_children():
			if b.has_meta("b_info") and b.has_meta("b_radius"):
				var r = b.get_meta("b_radius")
				var dx = abs(mouse_pos.x - b.global_position.x)
				var dy = abs(mouse_pos.y - b.global_position.y)
				if dx <= r and dy <= r:
					tooltip_label.text = b.get_meta("b_info")
					tooltip_label.visible = true
					tooltip_label.position = get_viewport().get_mouse_position() + Vector2(15, 15)
					return 
					
	if world_map:
		var cell = world_map.local_to_map(world_map.to_local(mouse_pos))
		var tile_id = world_map.get_cell_source_id(cell)
		if tile_id == -1: 
			tooltip_label.visible = false
			return
		if biome_stats.has(tile_id): 
			tooltip_label.text = biome_stats[tile_id]["name"]
		else: 
			tooltip_label.text = "Unknown zone (ID: " + str(tile_id) + ")"
		tooltip_label.visible = true
		tooltip_label.position = get_viewport().get_mouse_position() + Vector2(15, 15)

func update_ui_bars():
	current_energy = max(0.0, current_energy)
	current_hunger = max(0.0, current_hunger)
	current_thirst = max(0.0, current_thirst)
	
	if energy_bar: energy_bar.value = current_energy
	if hunger_bar: hunger_bar.value = current_hunger
	if thirst_bar: thirst_bar.value = current_thirst
	stats_updated.emit(current_energy, current_hunger, current_thirst)

func _draw():
	if not is_moving or path.size() < 2 or current_path_index >= path.size(): return
	var path_len = path.size()
	for i in range(current_path_index, path_len):
		var map_pos = path[i]
		var global_p = world_map.to_global(world_map.map_to_local(map_pos))
		var local_pos = to_local(global_p)
		
		if i == path_len - 1:
			var prev_map_pos = path[i - 1] if i > 0 else world_map.local_to_map(world_map.to_local(global_position))
			var prev_global = world_map.to_global(world_map.map_to_local(prev_map_pos))
			var prev_local = to_local(prev_global)
			var dir = (local_pos - prev_local).normalized()
			if dir == Vector2.ZERO: dir = Vector2(1, 0)
			var angle = dir.angle()
			
			var p1 = Vector2(28, 0).rotated(angle) + local_pos
			var p2 = Vector2(-24, -24).rotated(angle) + local_pos
			var p3 = Vector2(-24, 24).rotated(angle) + local_pos
			var points = PackedVector2Array([p1, p2, p3])
			var colors = PackedColorArray([Color(0.1, 0.6, 1.0, 0.4)])
			draw_polygon(points, colors)
			
			var outline_points = PackedVector2Array([p1, p2, p3, p1])
			draw_polyline(outline_points, Color(0.1, 0.6, 1.0, 0.8), 2.0, true)
		else:
			draw_rect(Rect2(local_pos.x - 32, local_pos.y - 32, 64, 64), Color(0.1, 0.6, 1.0, 0.4))
			draw_rect(Rect2(local_pos.x - 32, local_pos.y - 32, 64, 64), Color(0.1, 0.6, 1.0, 0.8), false, 2.0)
