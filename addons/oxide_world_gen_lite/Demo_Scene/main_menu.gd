extends Control

@export var map_config: MapConfig
@export var map_generator: Node2D
@export var background_texture: Texture2D 

var lake_slider: HSlider
var river_slider: HSlider
var forest_slider: HSlider
var pine_slider: HSlider 
var hill_slider: HSlider
var swamp_slider: HSlider

var lake_label: Label
var river_label: Label
var forest_label: Label
var pine_label: Label    
var hill_label: Label
var swamp_label: Label

var seed_input: LineEdit
var preset_options: OptionButton
var fog_toggle: CheckBox 

# 🔥 ТЕПЕРЬ БЕСКОНЕЧНАЯ ЭНЕРГИЯ ВКЛЮЧЕНА ПО УМОЛЧАНИЮ
var energy_toggle: CheckBox
var infinite_energy: bool = true

var return_btn: Button 
var generate_btn: Button
var get_pro_btn: Button
var quit_btn: Button
var bg_overlay: ColorRect
var bg_texture_rect: TextureRect 

func _ready():
	_build_ui()
	
	if map_config == null and map_generator != null and "config" in map_generator:
		map_config = map_generator.get("config")
		
	if map_config == null:
		map_config = MapConfig.new()
	
	lake_slider.value_changed.connect(_on_lake_changed)
	river_slider.value_changed.connect(_on_river_changed)
	forest_slider.value_changed.connect(_on_forest_changed)
	pine_slider.value_changed.connect(_on_pine_changed)
	hill_slider.value_changed.connect(_on_hill_changed)
	swamp_slider.value_changed.connect(_on_swamp_changed)
	
	return_btn.pressed.connect(_on_return_pressed)
	generate_btn.pressed.connect(_on_generate_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)
	
	energy_toggle.toggled.connect(func(pressed): infinite_energy = pressed)
	
	get_pro_btn.pressed.connect(func(): OS.shell_open("https://boosty.to/твоя_страница"))
	
	update_sliders_from_config()
	
	if map_generator == null or map_generator.get("generated_tiles") == null or map_generator.get("generated_tiles").is_empty():
		return_btn.visible = false
		return_btn.disabled = true
	else:
		return_btn.visible = true
		return_btn.disabled = false
		
	_set_ui_clickable(true)

func update_sliders_from_config():
	lake_slider.set_value_no_signal(map_config.lake_amount)
	river_slider.set_value_no_signal(map_config.river_amount)
	forest_slider.set_value_no_signal(map_config.forest_amount)
	pine_slider.set_value_no_signal(map_config.pine_amount)
	hill_slider.set_value_no_signal(map_config.hill_amount)
	swamp_slider.set_value_no_signal(map_config.swamp_amount)
	
	lake_label.text = "Lakes: %d%%" % int(map_config.lake_amount * 100)
	river_label.text = "Rivers: %d%%" % int(map_config.river_amount * 100)
	forest_label.text = "Overall Forest: %d%%" % int(map_config.forest_amount * 100)
	pine_label.text = "Taiga Ratio: %d%%" % int(map_config.pine_amount * 100)
	hill_label.text = "Hills: %d%%" % int(map_config.hill_amount * 100)
	swamp_label.text = "Swamps: %d%%" % int(map_config.swamp_amount * 100)

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		if not self.visible:
			open_menu()
		elif return_btn.visible and not return_btn.disabled:
			_on_return_pressed()

func open_menu():
	_set_ui_clickable(true)
	self.visible = true
	
	if map_generator and map_generator.get("generated_tiles") != null and not map_generator.get("generated_tiles").is_empty():
		return_btn.visible = true
		return_btn.disabled = false
	else:
		return_btn.visible = false
		return_btn.disabled = true
		
	if map_generator and map_generator.get("current_global_seed") != 0:
		seed_input.text = str(map_generator.get("current_global_seed"))
		
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.2)

func _set_ui_clickable(enabled: bool):
	if enabled:
		self.mouse_filter = Control.MOUSE_FILTER_STOP
		if bg_overlay: bg_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		self.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if bg_overlay: bg_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _build_ui():
	self.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	if background_texture != null:
		bg_texture_rect = TextureRect.new()
		bg_texture_rect.texture = background_texture
		bg_texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED 
		add_child(bg_texture_rect)
	
	bg_overlay = ColorRect.new()
	bg_overlay.color = Color(0, 0, 0, 0.60) 
	bg_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg_overlay)
	
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.grow_horizontal = Control.GROW_DIRECTION_END
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.11, 0.13, 0.96)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 60) 
	panel.add_child(margin)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 12) 
	margin.add_child(main_vbox)
	
	var title = Label.new()
	title.text = "OXIDE LITE EDITION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	main_vbox.add_child(title)
	main_vbox.add_child(HSeparator.new())
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll)
	
	var settings_vbox = VBoxContainer.new()
	settings_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(settings_vbox)
	
	var seed_label = Label.new()
	seed_label.text = "WORLD SEED (EMPTY FOR RANDOM)"
	seed_label.add_theme_font_size_override("font_size", 12)
	settings_vbox.add_child(seed_label)
	
	seed_input = LineEdit.new()
	seed_input.placeholder_text = "Enter text or number..."
	seed_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var seed_style = StyleBoxFlat.new()
	seed_style.bg_color = Color(0.16, 0.16, 0.19, 1.0)
	seed_style.border_width_bottom = 2
	seed_style.border_color = Color(0.35, 0.35, 0.4)
	seed_input.add_theme_stylebox_override("normal", seed_style)
	settings_vbox.add_child(seed_input)
	
	settings_vbox.add_child(HSeparator.new())
	energy_toggle = CheckBox.new()
	energy_toggle.text = "Disable Squad Energy Drain"
	# 🔥 ГАЛОЧКА ТЕПЕРЬ ВКЛЮЧЕНА СТАРТОВО
	energy_toggle.button_pressed = true 
	energy_toggle.add_theme_font_size_override("font_size", 13)
	settings_vbox.add_child(energy_toggle)
	
	settings_vbox.add_child(HSeparator.new())
	
	lake_label = Label.new(); settings_vbox.add_child(lake_label)
	lake_slider = _create_slider(); settings_vbox.add_child(lake_slider)
	
	river_label = Label.new(); settings_vbox.add_child(river_label)
	river_slider = _create_slider(); settings_vbox.add_child(river_slider)
	
	forest_label = Label.new(); settings_vbox.add_child(forest_label)
	forest_slider = _create_slider(); settings_vbox.add_child(forest_slider)
	
	pine_label = Label.new(); settings_vbox.add_child(pine_label)
	pine_slider = _create_slider(); settings_vbox.add_child(pine_slider)
	
	hill_label = Label.new(); settings_vbox.add_child(hill_label)
	hill_slider = _create_slider(); settings_vbox.add_child(hill_slider)
	
	swamp_label = Label.new(); settings_vbox.add_child(swamp_label)
	swamp_slider = _create_slider(); settings_vbox.add_child(swamp_slider)
	
	main_vbox.add_child(HSeparator.new())
	
	get_pro_btn = Button.new()
	get_pro_btn.text = "⭐ GET PRO VERSION ⭐\n(Cities, Roads, Fog, Saves)"
	get_pro_btn.custom_minimum_size = Vector2(0, 56)
	var pro_style = StyleBoxFlat.new()
	pro_style.bg_color = Color(0.68, 0.44, 0.1) 
	get_pro_btn.add_theme_font_size_override("font_size", 14)
	get_pro_btn.add_theme_stylebox_override("normal", pro_style)
	main_vbox.add_child(get_pro_btn)
	
	return_btn = Button.new()
	return_btn.text = "RETURN TO MAP"
	return_btn.custom_minimum_size = Vector2(0, 42)
	var ret_style = StyleBoxFlat.new()
	ret_style.bg_color = Color(0.35, 0.35, 0.38)
	return_btn.add_theme_font_size_override("font_size", 15)
	return_btn.add_theme_stylebox_override("normal", ret_style)
	main_vbox.add_child(return_btn)
	return_btn.visible = false 
	return_btn.disabled = true 
	
	generate_btn = Button.new()
	generate_btn.text = "GENERATE NEW WORLD"
	generate_btn.custom_minimum_size = Vector2(0, 48)
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.18, 0.48, 0.28)
	generate_btn.add_theme_font_size_override("font_size", 16)
	generate_btn.add_theme_stylebox_override("normal", btn_style)
	main_vbox.add_child(generate_btn)
	
	quit_btn = Button.new()
	quit_btn.text = "QUIT GAME"
	quit_btn.custom_minimum_size = Vector2(0, 42)
	var quit_style = StyleBoxFlat.new()
	quit_style.bg_color = Color(0.55, 0.16, 0.16) 
	quit_btn.add_theme_font_size_override("font_size", 15)
	quit_btn.add_theme_stylebox_override("normal", quit_style)
	main_vbox.add_child(quit_btn)

func _create_slider() -> HSlider:
	var slider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.1
	return slider

func _on_lake_changed(value: float):
	map_config.lake_amount = value
	lake_label.text = "Lakes: %d%%" % int(value * 100)

func _on_river_changed(value: float):
	map_config.river_amount = value
	river_label.text = "Rivers: %d%%" % int(value * 100)

func _on_forest_changed(value: float):
	map_config.forest_amount = value
	forest_label.text = "Overall Forest: %d%%" % int(value * 100)

func _on_pine_changed(value: float):
	map_config.pine_amount = value
	pine_label.text = "Taiga Ratio: %d%%" % int(value * 100)

func _on_hill_changed(value: float):
	map_config.hill_amount = value
	hill_label.text = "Hills: %d%%" % int(value * 100)

func _on_swamp_changed(value: float):
	map_config.swamp_amount = value
	swamp_label.text = "Swamps: %d%%" % int(value * 100)

func _on_return_pressed():
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	await tween.finished
	self.visible = false

func _on_generate_pressed():
	_set_ui_clickable(false)
	
	var squad_node = get_tree().current_scene.find_child("SurvivalPlayer", true, false)
	if squad_node and squad_node.has_method("reset_player_data"):
		squad_node.reset_player_data()
	
	if map_generator != null and map_generator.has_method("refresh_map"):
		map_generator.set("config", map_config)
		
		var text_seed = seed_input.text.strip_edges()
		if text_seed != "":
			if text_seed.is_valid_int():
				map_generator.set("custom_menu_seed", text_seed.to_int())
			else:
				map_generator.set("custom_menu_seed", text_seed.hash())
		else:
			map_generator.set("custom_menu_seed", -1) 
		
		map_generator.refresh_map()
		seed_input.text = str(map_generator.get("current_global_seed"))
		
		return_btn.visible = true
		return_btn.disabled = false
		
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	await tween.finished
	self.visible = false

func _on_quit_pressed():
	print("🚪 Exiting application...")
	get_tree().quit()
