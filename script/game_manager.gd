extends Node

@export var starting_distance : float = 150.0
@export var approach_speed : float = 2.5
@export var peek_penalty : float = 18.0

var creature_distance : float
var is_game_over : bool = false

var hero_node
var villain_node
var feedback_label
var restart_button
var menu_button

var end_ui
var end_label

var wind_player
var music_player
var footstep_player
var heartbeat_player
var peek_player

var footstep_timer : float = 0.0
var footstep_interval : float = 2.5

func _ready():
	creature_distance = starting_distance

	hero_node = get_parent().get_node("hero")
	villain_node = get_parent().get_node("villain")
	feedback_label = get_parent().get_node("UI/FeedbackLabel")

	end_ui = get_parent().get_node("EndUI")
	end_label = end_ui.get_node("Panel/VBoxContainer/EndLabel")
	
	restart_button = end_ui.get_node("Panel/VBoxContainer/RestartButton")
	menu_button = end_ui.get_node("Panel/VBoxContainer/MenuButton")

	wind_player = get_parent().get_node("WindPlayer")
	music_player = get_parent().get_node("MusicPlayer")
	footstep_player = get_parent().get_node("FootstepPlayer")
	heartbeat_player = get_parent().get_node("HeartbeatPlayer")
	peek_player = get_parent().get_node("PeekPlayer")

	wind_player.play()
	music_player.play()

	footstep_player.play()
	footstep_player.volume_db = -15
# ===============================
# CORE LOOP
# ===============================

func _process(delta):

	if is_game_over:
		return

	var current_speed = approach_speed
	if creature_distance < 40:
		current_speed = 3.5

	creature_distance -= current_speed * delta

	if creature_distance <= 0:
		game_over()

	var tension = 1.0 - (creature_distance / starting_distance)
	tension = clamp(tension, 0.0, 1.0)

	update_audio(tension)
	
	update_footsteps(delta)
# ===============================
# PEEK SYSTEM
# ===============================

func peek_trigger():
	peek_player.pitch_scale = randf_range(0.95, 1.1)
	peek_player.play()
	footstep_timer = 3.0
	
	if is_game_over:
		return

	if creature_distance <= 16:

		var push_back = randi_range(50, 80)
		creature_distance += push_back
		show_feedback("PERFECT", Color(0.2, 1, 0.2))
		if creature_distance <= 16:
			peek_player.volume_db = -2
		else:
			peek_player.volume_db = -8
		shake_camera()

	elif creature_distance <= 60:
		creature_distance -= 5
		show_feedback("VALID", Color(1, 1, 0.2))

	else:
		creature_distance -= peek_penalty
		show_feedback("BAD", Color(1, 0.2, 0.2))

	creature_distance = clamp(creature_distance, 0, starting_distance)

# ===============================
# CAMERA SHAKE
# ===============================

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
# FEEDBACK
# ===============================

func show_feedback(text: String, color: Color):

	feedback_label.text = text
	feedback_label.modulate = color
	feedback_label.visible = true
	feedback_label.scale = Vector2(1.3, 1.3)

	var tween = create_tween()
	tween.tween_property(feedback_label, "scale", Vector2.ONE, 0.2)

	await get_tree().create_timer(0.6).timeout
	feedback_label.visible = false

# ===============================
# GAME OVER (CINEMATIC)
# ===============================

func game_over():

	if is_game_over:
		return

	is_game_over = true
	hero_node.set_physics_process(false)

	villain_node.visible = true
	villain_node.global_position = hero_node.global_position + Vector2(-100, 0)

	await get_tree().create_timer(0.2).timeout

	villain_node.get_node("AnimatedSprite2D").play("attack")
	await get_tree().create_timer(0.3).timeout
	hero_node.get_node("AnimatedSprite2D").play("death")

	await get_tree().create_timer(0.6).timeout
	wind_player.stop()
	music_player.stop()
	heartbeat_player.stop()
	footstep_player.stop()
	await fade_to_black()

	end_label.text = "YOU FAILED"
	end_label.modulate = Color(1, 0.1, 0.1)
# ===============================
# SHARED FADE
# ===============================

func fade_to_black():

	end_ui.visible = true   # Make UI layer active

	# Create fade behind panel
	var fade = ColorRect.new()
	fade.color = Color.BLACK
	fade.size = get_viewport().get_visible_rect().size
	fade.modulate.a = 0

	# Add FIRST so it stays behind
	end_ui.add_child(fade)

	# Ensure panel stays on top
	end_ui.get_node("Panel").move_to_front()

	var tween = create_tween()
	tween.tween_property(fade, "modulate:a", 1.0, 1.0)

	await tween.finished
# ===============================
# WIN GAME 
# ===============================

func win_game():

	if is_game_over:
		return

	is_game_over = true
	hero_node.set_physics_process(false)


	hero_node.visible = false

	villain_node.visible = true
	villain_node.global_position = hero_node.global_position + Vector2(-150, 0)
	await get_tree().create_timer(0.2).timeout
	
	villain_node.get_node("AnimatedSprite2D").play("death")

	await get_tree().create_timer(3).timeout

	footstep_player.stop()
	
	await fade_to_black()
	
	end_label.text = "YOU ESCAPED"
	end_label.modulate = Color(0.6, 1, 0.6)
	
	

# ===============================
# MUSIC SYSTEM 
# ===============================
func update_audio(tension: float):

	# WIND gets louder slightly
	wind_player.volume_db = lerp(-25, -10, tension)

	# MUSIC gets stronger
	music_player.volume_db = lerp(-22, -4, tension)

	# Subtle pitch increase for anxiety
	music_player.pitch_scale = lerp(1.0, 1.1, tension)

	# HEARTBEAT activates near danger
	if tension > 0.7:
		if not heartbeat_player.playing:
			heartbeat_player.play()
		heartbeat_player.volume_db = lerp(-22, -5, (tension - 0.7) / 0.3)
	else:
		heartbeat_player.stop()
		
	# Footstep volume
	footstep_player.volume_db = lerp(-18, -10, tension)
	
func update_footsteps(delta):

	if is_game_over:
		return

	footstep_timer -= delta

	if footstep_timer <= 0:

		# Play footstep
		footstep_player.pitch_scale = randf_range(0.95, 1.05)
		footstep_player.play()

		# Dynamic interval based on tension
		var tension = 1.0 - (creature_distance / starting_distance)

		# Early game slower steps, late game slightly faster
		footstep_interval = lerp(3.0, 1.5, tension)

		# Add randomness
		footstep_timer = footstep_interval + randf_range(0.2, 0.8)
		

func _on_restart_button_pressed() -> void:
	get_tree().reload_current_scene()


func _on_menu_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scene/main_menu.tscn")
