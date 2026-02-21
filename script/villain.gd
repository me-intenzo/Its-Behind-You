extends CharacterBody2D

@export var base_offset : float = 220.0
@export var min_offset : float = 20.0

@onready var player = get_parent().get_node("hero")
@onready var game_manager = get_parent().get_node("GameManager")

func _ready():
	visible = false

func _process(_delta):
	if game_manager.creature_distance <= 0:
		game_manager.game_over()
		return

	# Ratio from 0 → 1
	var ratio = game_manager.creature_distance / game_manager.starting_distance
	ratio = clamp(ratio, 0.0, 1.0)

	# Lerp offset
	var offset = lerp(min_offset, base_offset, ratio)

	# Stay behind player
	global_position.x = player.global_position.x - offset
	global_position.y = player.global_position.y

func show_temporarily():
	visible = true
	await get_tree().create_timer(0.6).timeout
	visible = false
