class_name hero extends CharacterBody2D

@export var move_speed : float = 80.0
@export var peek_duration : float = 0.8

var is_peeking : bool = false

@onready var sprite : AnimatedSprite2D = $AnimatedSprite2D
@onready var game_manager = get_parent().get_node("GameManager")
@onready var villain = get_parent().get_node("villain")

func _ready():
	sprite.play("run")

func _physics_process(_delta):
	if is_peeking:
		velocity.x = 0
		sprite.play("idle")
	else:
		velocity.x = move_speed
		sprite.play("run")

	move_and_slide()

func _input(event):
	if event.is_action_pressed("peek_back") and !is_peeking:
		start_peek()

func start_peek():
	is_peeking = true

	# Turn around
	sprite.flip_h = true

	# Apply distance penalty
	game_manager.peek_trigger()

	# Reveal villain briefly
	villain.show_temporarily()

	await get_tree().create_timer(peek_duration).timeout

	# Turn back forward
	sprite.flip_h = false
	is_peeking = false
	
func die():
	velocity = Vector2.ZERO
	sprite.play("death")
