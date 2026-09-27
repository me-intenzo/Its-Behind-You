class_name hero extends CharacterBody2D

@export var move_speed : float = 80.0
@export var peek_duration : float = 0.45
@export var peek_speed_mult : float = 0.4   # jog while glancing back instead of dead-stopping

var is_peeking : bool = false

@onready var sprite : AnimatedSprite2D = $AnimatedSprite2D
@onready var game_manager = get_parent().get_node("GameManager")
@onready var villain = get_parent().get_node("villain")

func _ready():
	sprite.play("run")

func _physics_process(_delta):
	# NOTE: the tiles carry no collision, so the ground is visual only —
	# the hero runs at a fixed Y (no gravity) and is grounded by placement.
	# Glance back while still jogging. A hard stop here made the run lurch
	# every time the creature closed in and you peeked — keep momentum so the
	# pace stays smooth and only the look-back sells the danger.
	if is_peeking:
		velocity.x = move_speed * peek_speed_mult
		# "idle" flipped reads as the look-back pose — a visible peek that
		# isn't identical to the normal run, without dead-stopping the world.
		sprite.play("idle")
	else:
		velocity.x = move_speed
		sprite.play("run")

	move_and_slide()

func _input(event):
	if event.is_action_pressed("peek_back"):
		try_peek()

	if event is InputEventScreenTouch and event.pressed:
		try_peek()

func try_peek():
	# already mid-peek animation -> ignore
	if is_peeking:
		return

	# the game manager owns the anti-spam gate (cooldown + nerve) and
	# tells us whether this peek actually counted
	var accepted = game_manager.peek_trigger()
	if not accepted:
		return

	start_peek()

func start_peek():
	is_peeking = true

	# Turn around
	sprite.flip_h = true

	# Reveal villain briefly
	villain.show_temporarily()

	await get_tree().create_timer(peek_duration).timeout

	# Turn back forward
	sprite.flip_h = false
	is_peeking = false
	
func die():
	velocity = Vector2.ZERO
	sprite.play("death")
