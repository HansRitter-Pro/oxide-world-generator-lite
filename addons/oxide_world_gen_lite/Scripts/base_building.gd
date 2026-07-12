extends Node2D
@onready var sprite = $Sprite2D

func _ready():
	var seed_val = abs(int(global_position.x * 73856 + global_position.y * 19349))
	sprite.frame = seed_val % 100
	
	var role = ""
	if has_meta("assigned_role") and get_meta("assigned_role") != "":
		role = get_meta("assigned_role")
		
	var b_type = "Small Rural House"
	var extra_info = "\n(Abandoned)"
	
	# Если генератор назначил особую придорожную роль
	if role != "":
		b_type = role
		if role == "Gas Station": extra_info = "\n(Fuel & Scraps)"
		elif role == "Roadside Cafe" or role == "Old Diner": extra_info = "\n(Food & Supplies)"
		elif role == "Motel": extra_info = "\n(Rest Area)"
	else:
		# Обычная генерация для деревень
		var roll = (seed_val % 100) / 100.0
		if roll > 0.95: b_type = "Local Pharmacy"
		elif roll > 0.85: b_type = "Country Store"
		elif roll > 0.80: b_type = "Car Workshop"
		else: b_type = "Suburban House"
		
	set_meta("b_info", b_type + extra_info)
	set_meta("b_radius", 128.0)
