extends Node

@export var starting_distance : float = 150.0
@export var approach_speed : float = 2.5
@export var peek_penalty : float = 15.0

var creature_distance : float
var is_game_over : bool = false

var hero_node
var villain_node

func _ready():
	creature_distance = starting_distance

	hero_node = get_parent().get_node("hero")
	villain_node = get_parent().get_node("villain")


func _process(delta):

	if is_game_over:
		return

	# Increase pressure near end
	var current_speed = approach_speed
	if creature_distance < 40:
		current_speed = 3.5

	creature_distance -= current_speed * delta

	if creature_distance <= 0:
		game_over()


# ===============================
# PEEK SYSTEM
# ===============================

func peek_trigger():

	if is_game_over:
		return

	# PERFECT TIMING
	if creature_distance <= 16:

		var push_back = randi_range(50, 80)
		creature_distance += push_back
		creature_distance = clamp(creature_distance, 0, starting_distance)

		print("PERFECT")
		shake_camera()

	# MID RANGE
	elif creature_distance <= 60:
		creature_distance -= 5
		print("GOOD")

	# BAD PEEK
	else:
		creature_distance -= peek_penalty
		print("BAD")

	creature_distance = clamp(creature_distance, 0, starting_distance)


func shake_camera():

	var cam = hero_node.get_node("Camera2D")

	for i in 6:
		cam.offset = Vector2(
			randf_range(-6, 6),
			randf_range(-6, 6)
		)
		await get_tree().create_timer(0.03).timeout

	cam.offset = Vector2.ZERO


# ===============================
# GAME OVER (Villain Catches Hero)
# ===============================

func game_over():

	if is_game_over:
		return

	is_game_over = true

	hero_node.set_physics_process(false)

	villain_node.visible = true
	villain_node.global_position = hero_node.global_position + Vector2(-20, 0)

	# Small dramatic delay before death
	await get_tree().create_timer(0.1).timeout

	villain_node.get_node("AnimatedSprite2D").play("attack")
	await get_tree().create_timer(0.15).timeout
	hero_node.get_node("AnimatedSprite2D").play("death")

	await get_tree().create_timer(2.2).timeout
	get_tree().reload_current_scene()


# ===============================
# WIN GAME (Dark Cinematic Ending)
# ===============================

func win_game():

	if is_game_over:
		return

	is_game_over = true
	hero_node.set_physics_process(false)

	# === Create cinematic layer (screen space) ===
	var cinematic_layer = CanvasLayer.new()
	cinematic_layer.layer = 10
	get_tree().current_scene.add_child(cinematic_layer)

	# === Black background ===
	var bg = ColorRect.new()
	bg.color = Color.BLACK
	bg.size = get_viewport().get_visible_rect().size
	bg.position = Vector2.ZERO
	cinematic_layer.add_child(bg)
	

	# Fade in
	bg.modulate.a = 0
	for i in 15:
		bg.modulate.a += 0.07
		await get_tree().create_timer(0.03).timeout

	# Hide gameplay
	hero_node.visible = false
	villain_node.visible = true

	# === Move villain into screen space ===
	var old_parent = villain_node.get_parent()
	old_parent.remove_child(villain_node)
	cinematic_layer.add_child(villain_node)

# Center villain on screen

	villain_node.position = bg.size / 4

# Scale up villain for dramatic effect
	villain_node.scale = Vector2(10, 10)  # adjust 2.5–4 depending on taste

# Make sure pivot is centered
	villain_node.get_node("AnimatedSprite2D").centered = true

	await get_tree().create_timer(0.3).timeout

	villain_node.get_node("AnimatedSprite2D").play("death")

	await get_tree().create_timer(2.5).timeout
	get_tree().reload_current_scene()
