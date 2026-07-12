extends Node2D

@export var config: MapConfig

@onready var tile_map = get_tree().current_scene.find_child("WorldMap", true, false)
@onready var squad = get_tree().current_scene.find_child("SurvivalPlayer", true, false)

var elevation_noise = FastNoiseLite.new()
var moisture_noise = FastNoiseLite.new()
var detail_noise = FastNoiseLite.new()
var river_noise = FastNoiseLite.new()
var pine_noise = FastNoiseLite.new()

var generated_tiles = {}
var render_radius = 140
var last_squad_pos = Vector2i(-999, -999)
var current_global_seed: int = 0
var custom_menu_seed: int = -1

# 🔥 ВОЗВРАЩЕНО ДЛЯ МИНИКАРТЫ (Скрытый технический слой)
var fog_map: TileMapLayer 

var building_scene = preload("res://addons/oxide_world_gen_lite/Scripts/base_building.tscn")
var buildings_container: Node2D
var active_buildings = {}

func _ready():
	buildings_container = Node2D.new()
	buildings_container.name = "BuildingsLayer"
	buildings_container.z_index = 3 
	add_child.call_deferred(buildings_container)

func refresh_map():
	if tile_map == null: tile_map = get_tree().current_scene.find_child("WorldMap", true, false)
	if squad == null: squad = get_tree().current_scene.find_child("SurvivalPlayer", true, false)
	if tile_map == null or config == null: return
	
	tile_map.clear()
	generated_tiles.clear()
	for b in active_buildings.values(): b.queue_free()
	active_buildings.clear()
	
	# 🔥 Создаем туман исключительно как математическую базу для миникарты
	if fog_map == null:
		fog_map = TileMapLayer.new()
		fog_map.name = "FogMap"
		fog_map.tile_set = tile_map.tile_set
		fog_map.z_index = 5 
		fog_map.modulate = Color(0.02, 0.02, 0.03, 1.0) 
		get_tree().current_scene.add_child.call_deferred(fog_map)
	else:
		fog_map.clear()
		
	# В LITE версии туман всегда невидим на основном экране!
	fog_map.visible = false 
	
	setup_noises()
	force_spawn_at_start_location()
	var start_pos = tile_map.local_to_map(tile_map.to_local(squad.global_position))
	generate_chunks_around(start_pos)
	print("🌍 LITE Oxide Map Loaded. Minimap completely fixed.")

func setup_noises():
	if custom_menu_seed != -1:
		current_global_seed = custom_menu_seed
	else:
		current_global_seed = randi()
		
	elevation_noise.seed = current_global_seed
	elevation_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	elevation_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	elevation_noise.fractal_octaves = 3 
	elevation_noise.frequency = 0.004 
	elevation_noise.domain_warp_enabled = true
	elevation_noise.domain_warp_amplitude = 10.0 
	moisture_noise.seed = current_global_seed + 1
	moisture_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	moisture_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	moisture_noise.fractal_octaves = 2 
	moisture_noise.frequency = 0.003 
	detail_noise.seed = current_global_seed + 2
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail_noise.fractal_octaves = 3
	detail_noise.frequency = 0.015 
	river_noise.seed = current_global_seed + 3
	river_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	river_noise.fractal_type = FastNoiseLite.FRACTAL_NONE 
	river_noise.frequency = 0.0015 
	river_noise.domain_warp_enabled = true
	river_noise.domain_warp_amplitude = 8.0 
	pine_noise.seed = current_global_seed + 4
	pine_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	pine_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	pine_noise.fractal_octaves = 2
	pine_noise.frequency = 0.002 

func force_spawn_at_start_location():
	var start_pos = Vector2i(0, 0)
	var found = false
	
	for radius in range(0, 30):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if abs(dx) == radius or abs(dy) == radius:
					var test_pos = Vector2i(dx, dy)
					var fx = float(test_pos.x)
					var fy = float(test_pos.y)
					
					var elev = elevation_noise.get_noise_2d(fx, fy)
					var lake_thresh = lerp(-1.0, 0.1, config.lake_amount)
					if elev < lake_thresh + 0.04: continue 
					
					var r_val = river_noise.get_noise_2d(fx, fy)
					var river_base_width = lerp(-0.02, 0.045, config.river_amount)
					var dist_to_lake = elev - lake_thresh
					var estuary_widen = 0.0
					if dist_to_lake > 0.0 and dist_to_lake < 0.15: estuary_widen = (0.15 - dist_to_lake) * 0.4 
					var final_river_width = river_base_width + estuary_widen
					if final_river_width > 0.0 and abs(r_val) < (final_river_width + 0.02): continue 
					
					var moist = moisture_noise.get_noise_2d(fx, fy)
					var detail = detail_noise.get_noise_2d(fx, fy)
					var swamp_thresh = lerp(0.6, -0.1, config.swamp_amount)
					var hill_thresh = lerp(0.6, 0.0, config.hill_amount)
					if moist + (detail * 0.4) > swamp_thresh and elev < (hill_thresh - 0.1): continue 
					
					start_pos = test_pos
					found = true
					break
			if found: break
		if found: break
		
	squad.global_position = tile_map.to_global(tile_map.map_to_local(start_pos))
	last_squad_pos = start_pos

func _process(_delta):
	if squad == null or tile_map == null or generated_tiles.is_empty(): return
	var current_squad_pos = tile_map.local_to_map(tile_map.to_local(squad.global_position))
	if current_squad_pos != last_squad_pos:
		last_squad_pos = current_squad_pos
		generate_chunks_around(current_squad_pos)
		cleanup_distant_tiles(current_squad_pos)

func generate_chunks_around(center_pos: Vector2i):
	for x in range(center_pos.x - render_radius, center_pos.x + render_radius + 1):
		for y in range(center_pos.y - render_radius, center_pos.y + render_radius + 1):
			var pos = Vector2i(x, y)
			if generated_tiles.has(pos): continue
			if pos.distance_to(center_pos) <= render_radius:
				generate_single_tile(pos)
				generated_tiles[pos] = true

func _is_water_or_bank_at(test_pos: Vector2i) -> bool:
	var fx = float(test_pos.x)
	var fy = float(test_pos.y)
	var elev = elevation_noise.get_noise_2d(fx, fy)
	var r_val = river_noise.get_noise_2d(fx, fy)
	var lake_thresh = lerp(-1.0, 0.1, config.lake_amount)
	if elev < lake_thresh + 0.04: return true
	var river_base_width = lerp(-0.02, 0.045, config.river_amount)
	var dist_to_lake = elev - lake_thresh
	var estuary_widen = 0.0
	if dist_to_lake > 0.0 and dist_to_lake < 0.15: estuary_widen = (0.15 - dist_to_lake) * 0.4 
	var final_river_width = river_base_width + estuary_widen
	if final_river_width > 0.0 and abs(r_val) < (final_river_width + 0.006): return true
	return false

func generate_single_tile(pos: Vector2i):
	# 🔥 Прописываем тайлы в скрытый туман, чтобы игрок мог видеть их на миникарте
	if fog_map and fog_map.get_cell_source_id(pos) == -1: 
		fog_map.set_cell(pos, 7, Vector2i(0, 0)) 
		
	var fx = float(pos.x); var fy = float(pos.y)
	var elev = elevation_noise.get_noise_2d(fx, fy)
	var moist = moisture_noise.get_noise_2d(fx, fy)
	var detail = detail_noise.get_noise_2d(fx, fy) 
	var r_val = river_noise.get_noise_2d(fx, fy)
	var p_val = pine_noise.get_noise_2d(fx, fy) 
	var lake_thresh = lerp(-1.0, 0.1, config.lake_amount) 
	var hill_thresh = lerp(0.6, 0.0, config.hill_amount)
	var forest_thresh = lerp(0.4, -0.2, config.forest_amount)
	var swamp_thresh = lerp(0.6, -0.1, config.swamp_amount)
	var pine_thresh = lerp(0.5, -0.2, config.pine_amount)
	
	var is_forest = moist + (detail * 0.4) > forest_thresh
	var river_base_width = lerp(-0.02, 0.045, config.river_amount)
	var estuary_widen = 0.0
	var dist_to_lake = elev - lake_thresh
	if dist_to_lake > 0.0 and dist_to_lake < 0.15: estuary_widen = (0.15 - dist_to_lake) * 0.4 
	var final_river_width = river_base_width + estuary_widen
	var is_river = final_river_width > 0.0 and abs(r_val) < final_river_width
	var is_river_bank = final_river_width > 0.0 and abs(r_val) >= final_river_width and abs(r_val) < (final_river_width + 0.006)
	var is_lake_shore = elev < lake_thresh + 0.04
	var is_estuary_bank = final_river_width > 0.0 and abs(r_val) < (final_river_width + 0.02) and dist_to_lake < 0.08
	
	var final_id = 7 
	
	if elev < lake_thresh: final_id = 10 
	elif is_river: final_id = 1
	elif is_lake_shore or (is_estuary_bank and detail > 0.1) or (is_river_bank and not is_forest and detail > 0.35): final_id = 5 
	elif elev > hill_thresh: final_id = 8
	elif moist + (detail * 0.4) > swamp_thresh and elev < (hill_thresh - 0.1): final_id = 0
	elif is_forest: 
		if p_val + (detail * 0.5) > pine_thresh: final_id = 14
		else: final_id = 3
	
	tile_map.set_cell(pos, final_id, Vector2i(0, 0))
	
	# 🔥 ОПТИМИЗИРОВАННЫЙ РЕДКИЙ СПАВН ДОМИКОВ
	if final_id == 7 or final_id == 3 or final_id == 14:
		if pos.x % 50 == 0 and pos.y % 50 == 0: # Теперь домик возможен только раз в 50 тайлов
			var roll = abs(pos.x * 73 + pos.y * 37 + current_global_seed) % 100
			if roll < 3: # Теперь шанс спавна всего 3%
				if _check_space(pos, 2):
					_spawn_building_at(pos)

func _check_space(center_pos: Vector2i, safe_radius: int) -> bool:
	for dx in range(-safe_radius, safe_radius + 1):
		for dy in range(-safe_radius, safe_radius + 1):
			var check_pos = center_pos + Vector2i(dx, dy)
			if active_buildings.has(check_pos): return false
			if _is_water_or_bank_at(check_pos): return false
	return true

func _spawn_building_at(pos: Vector2i):
	if active_buildings.has(pos): return
	var building = building_scene.instantiate()
	building.set_meta("assigned_role", "Abandoned Shack")
	building.position = tile_map.map_to_local(pos)
	buildings_container.add_child.call_deferred(building)
	active_buildings[pos] = building

func cleanup_distant_tiles(center_pos: Vector2i):
	var unload_radius = render_radius + 20 
	var tiles_to_erase = []
	for pos in generated_tiles.keys():
		if pos.distance_to(center_pos) > unload_radius:
			tile_map.set_cell(pos, -1)
			if fog_map: fog_map.set_cell(pos, -1) # 🔥 Очистка памяти для тумана
			if active_buildings.has(pos):
				active_buildings[pos].queue_free()
				active_buildings.erase(pos)
			tiles_to_erase.append(pos)
	for pos in tiles_to_erase: generated_tiles.erase(pos)
