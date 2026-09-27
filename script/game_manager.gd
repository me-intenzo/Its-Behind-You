extends Node

@export var starting_distance : float = 150.0
@export var approach_speed : float = 8.0        # base closing speed (was far too slow)
@export var approach_ramp : float = 0.16        # closing speed gained per second (difficulty climb)
@export var max_approach_speed : float = 18.0   # cap so perfect play stays just survivable
@export var close_boost : float = 2.5           # extra speed when it is right on you (in the danger zone)

# --- Peek timing (a peek only helps while it's ON you; the game TELLS you when) ---
@export var danger_range : float = 27.0     # once it's this close, the "LOOK BACK!" tell fires (was 34 — pulled in so the tell shows for a shorter window)
@export var good_pushback : float = 52.0    # a timed peek wards it off hard
@export var early_cost_mult : float = 0.5   # a wasted (too-early) peek only burns half nerve, never a death

# --- Nerve / stamina (kills the mash-to-win exploit, but stays sustainable on good play) ---
@export var max_stamina : float = 100.0
@export var peek_cost : float = 33.6          # each real peek spends this much (+20% over the old 28)
@export var stamina_regen : float = 9.0       # per second — refills ~one peek per danger cycle, so nerve stays a real resource
@export var peek_cooldown : float = 0.45      # min seconds between peeks (key + touch)

var creature_distance : float
var is_game_over : bool = false

var stamina : float
var peek_cooldown_timer : float = 0.0
var feedback_active : bool = false
var in_danger : bool = false   # true while the creature is inside danger_range (drives the tell)
var elapsed : float = 0.0   # time since the run started, drives the difficulty ramp

# stamina bar (built in code, added to the UI layer)
var stamina_fill : ColorRect

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
	stamina = max_stamina

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

	_build_stamina_bar()

# ===============================
# NERVE BAR (built in code)
# ===============================

func _build_stamina_bar():
	var ui = get_parent().get_node("UI")

	var label = Label.new()
	label.text = "NERVE"
	label.position = Vector2(30, 24)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.90, 0.82, 0.62))       # torchlit parchment
	label.add_theme_color_override("font_shadow_color", Color(0.04, 0.03, 0.02))
	label.add_theme_constant_override("shadow_offset_y", 2)
	ui.add_child(label)

	# moon-lit frame behind the bar
	var frame = ColorRect.new()
	frame.color = Color(0.45, 0.36, 0.25, 0.5)   # bronze / iron rim
	frame.position = Vector2(28, 44)
	frame.size = Vector2(308, 28)
	ui.add_child(frame)

	var bg = ColorRect.new()
	bg.color = Color(0.06, 0.05, 0.04, 0.85)       # dark stone
	bg.position = Vector2(30, 46)
	bg.size = Vector2(304, 24)
	ui.add_child(bg)

	stamina_fill = ColorRect.new()
	stamina_fill.color = Color(0.83, 0.58, 0.22)   # torch gold
	stamina_fill.position = Vector2(32, 48)
	stamina_fill.size = Vector2(300, 20)
	ui.add_child(stamina_fill)

func _update_stamina_bar():
	if stamina_fill == null:
		return

	var ratio = clamp(stamina / max_stamina, 0.0, 1.0)
	stamina_fill.size.x = 300.0 * ratio

	# color shifts as nerve drains; can't peek below one peek's worth
	if stamina < peek_cost:
		stamina_fill.color = Color(0.70, 0.14, 0.14)   # blood red
	elif ratio < 0.5:
		stamina_fill.color = Color(0.80, 0.38, 0.14)   # ember orange
	else:
		stamina_fill.color = Color(0.83, 0.58, 0.22)   # torch gold
# ===============================
# CORE LOOP
# ===============================

func _process(delta):

	if is_game_over:
		return

	# nerve recovers over time; peek cooldown ticks down
	stamina = min(stamina + stamina_regen * delta, max_stamina)
	if peek_cooldown_timer > 0.0:
		peek_cooldown_timer -= delta
	_update_stamina_bar()

	# the creature closes faster and faster the longer the run goes on
	elapsed += delta
	var current_speed = min(approach_speed + approach_ramp * elapsed, max_approach_speed)
	if creature_distance < danger_range:
		current_speed += close_boost

	creature_distance -= current_speed * delta
	creature_distance = max(creature_distance, 0.0)

	# THE TELL: the instant it's on you, the game shouts to look back.
	# This is the whole fix for "either it catches me or I mash peek" —
	# you now peek in reaction to this, not by guessing.
	var now_danger := creature_distance <= danger_range
	if now_danger != in_danger:
		in_danger = now_danger
		if not in_danger and not feedback_active:
			feedback_label.visible = false
	if in_danger and not feedback_active:
		feedback_label.text = "LOOK BEHIND YOU!"
		feedback_label.modulate = Color(1.0, 0.25, 0.22)
		feedback_label.visible = true

	if creature_distance <= 0:
		game_over()

	var tension = clamp(1.0 - (creature_distance / starting_distance), 0.0, 1.0)

	update_audio(tension)

	update_footsteps(delta)
# ===============================
# PEEK SYSTEM
# ===============================

# Returns true only if the peek was actually accepted (used by the hero to
# play the look-back animation). Spamming is rejected here, so both the key
# and the touch input paths are safe.
func peek_trigger() -> bool:

	if is_game_over:
		return false

	# on cooldown -> ignore, so mashing does nothing
	if peek_cooldown_timer > 0.0:
		return false

	# a real (in-danger) peek costs full nerve; a wasted early one costs half
	var in_zone := creature_distance <= danger_range
	var cost := peek_cost if in_zone else peek_cost * early_cost_mult

	# out of nerve -> can't peek, warn once
	if stamina < cost:
		show_feedback("EXHAUSTED", Color(0.9, 0.3, 0.3))
		return false

	# accepted: spend nerve and start the cooldown
	stamina -= cost
	peek_cooldown_timer = peek_cooldown

	peek_player.pitch_scale = randf_range(0.95, 1.1)
	peek_player.play()
	footstep_timer = 3.0

	if creature_distance <= danger_range:
		# it was right on you -> the look-back scares it off
		creature_distance += good_pushback
		peek_player.volume_db = -2
		show_feedback("SAVED!", Color(0.2, 1, 0.2))
		shake_camera()

	else:
		# nothing was there yet -> you just flinch. it does NOT rush in,
		# so an early peek is only a small waste of nerve, never a death.
		peek_player.volume_db = -8
		show_feedback("TOO EARLY", Color(0.9, 0.75, 0.35))

	creature_distance = clamp(creature_distance, 0, starting_distance)
	return true

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

	if feedback_active:
		return
	feedback_active = true

	feedback_label.text = text
	feedback_label.modulate = color
	feedback_label.visible = true
	feedback_label.scale = Vector2(1.3, 1.3)

	var tween = create_tween()
	tween.tween_property(feedback_label, "scale", Vector2.ONE, 0.2)

	await get_tree().create_timer(0.4).timeout
	feedback_label.visible = false
	feedback_active = false

# ===============================
# GAME OVER (CINEMATIC)
# ===============================

func game_over():

	if is_game_over:
		return

	is_game_over = true
	hero_node.set_physics_process(false)

	villain_node.visible = true
	villain_node.global_position = hero_node.global_position + Vector2(-46, 0)

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
