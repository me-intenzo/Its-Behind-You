extends Node

@export var starting_distance : float = 150.0
@export var approach_speed : float = 9.0        # base closing speed — raised: Normal starts tenser
@export var approach_ramp : float = 0.08        # closing speed gained per second (difficulty climb)
@export var max_approach_speed : float = 21.0   # higher ceiling → sharper late-game reactions
@export var close_boost : float = 3.0           # extra speed when it is right on you (in the danger zone)

# --- Peek timing (a peek only helps while it's ON you; the game TELLS you when) ---
@export var danger_range : float = 22.0     # tighter reaction window than before (was 27) — the core "harder" lever
@export var save_range_mult : float = 1.8   # a look-back still saves while the creature is THIS × danger_range away — stops "it's right there but TOO EARLY"
@export var good_pushback : float = 52.0    # a timed peek wards it off hard (kept so victory stays reachable)
@export var early_cost_mult : float = 0.5   # a wasted (too-early) peek only burns half nerve, never a death

# --- Nerve / stamina (kills the mash-to-win exploit, but stays sustainable on good play) ---
@export var max_stamina : float = 100.0
@export var peek_cost : float = 30.0          # each real peek spends this much
@export var stamina_regen : float = 13.0      # per second — kept high so faster cycles stay sustainable (victory achievable)
@export var peek_cooldown : float = 0.45      # min seconds between peeks (key + touch)

# --- Grab event (a hand bursts from the ground; tap to break free, peek disabled) ---
@export var grab_min_gap : float = 11.0       # min seconds between grab events
@export var grab_max_gap : float = 19.0       # max seconds between grab events
@export var grab_taps_needed : int = 3        # taps to break free
@export var grab_time_limit : float = 3.0     # seconds to break free before it drags you under

# --- Falling stone threat ---
@export var stone_min_gap : float = 14.0
@export var stone_max_gap : float = 21.0
@export var stone_warning_time : float = 0.9
@export var stone_fall_time : float = 0.65
const STONE_DROP_HEIGHT := 230.0

var creature_distance : float
var is_game_over : bool = false

var stamina : float
var peek_cooldown_timer : float = 0.0
var feedback_active : bool = false
var in_danger : bool = false   # true while the creature is inside danger_range (drives the tell)
var elapsed : float = 0.0   # time since the run started, drives the difficulty ramp
var show_tell : bool = true   # whether the "LOOK BEHIND YOU!" warning shows (off in HARD)

# grab-event state
var grab_enabled : bool = true   # EASY turns the hand off entirely
var is_grabbed : bool = false
var grab_taps : int = 0
var grab_timer : float = 0.0
var grab_time_left : float = 0.0
var grab_timing : bool = false   # countdown only runs once the hand has actually clenched
var grab_sprite : AnimatedSprite2D

var stone_timer : float = 0.0
var stone_warning_left : float = 0.0
var stone_fall_elapsed : float = 0.0
var stone_warning_active : bool = false
var stone_falling : bool = false
var stone_visual : Node2D
var stone_sprite : Sprite2D
var stone_shadow : Polygon2D

# stamina bar (built in code, added to the UI layer) — vertical, fills upward
var stamina_fill : ColorRect
var nerve_fill_x : float = 0.0
var nerve_fill_top : float = 0.0
var nerve_fill_w : float = 0.0
var nerve_fill_h : float = 1.0

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
var cave_player : AudioStreamPlayer
var rockfall_player : AudioStreamPlayer
var enemy_growl_player : AudioStreamPlayer
var attack_stinger_player : AudioStreamPlayer
var dash_whoosh_player : AudioStreamPlayer
var stone_footstep_streams : Array[AudioStream] = []

var footstep_timer : float = 0.0
var footstep_interval : float = 2.5

# --- pause / tutorial / progress (all built in code, like the nerve bar) ---
var is_paused : bool = false
var in_tutorial : bool = false

var overlay_layer : CanvasLayer    # holds the tutorial + pause screens
var tutorial_root : Control
var pause_root : Control

var progress_fill : ColorRect      # top-centre "distance to door" bar
var progress_bar_w : float = 460.0
var hero_start_x : float = 0.0
var door_x : float = 1.0

var overlay_font = load("res://asset/font/PirataOne-Regular.ttf")

func _make_added_audio_player(player_name: String, stream_path: String, start_volume_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.stream = load(stream_path) as AudioStream
	player.volume_db = start_volume_db
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	return player

func _ready():
	# GameManager keeps running while the tree is paused so it can drive the
	# pause/tutorial screens and catch ESC; its own loop is gated below instead.
	process_mode = Node.PROCESS_MODE_ALWAYS

	creature_distance = starting_distance
	stamina = max_stamina

	_apply_difficulty()

	hero_node = get_parent().get_node("hero")
	villain_node = get_parent().get_node("villain")
	feedback_label = get_parent().get_node("UI/FeedbackLabel")
	# the feedback label is stretched full-screen; let taps pass through it so a
	# click/tap anywhere still peeks (peeking now runs in _unhandled_input)
	feedback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	end_ui = get_parent().get_node("EndUI")
	end_label = end_ui.get_node("Panel/VBoxContainer/EndLabel")
	
	restart_button = end_ui.get_node("Panel/VBoxContainer/RestartButton")
	menu_button = end_ui.get_node("Panel/VBoxContainer/MenuButton")

	wind_player = get_parent().get_node("WindPlayer")
	music_player = get_parent().get_node("MusicPlayer")
	footstep_player = get_parent().get_node("FootstepPlayer")
	heartbeat_player = get_parent().get_node("HeartbeatPlayer")
	peek_player = get_parent().get_node("PeekPlayer")

	for step_name in ["Fantozzi-StoneL1.ogg", "Fantozzi-StoneL2.ogg", "Fantozzi-StoneL3.ogg", "Fantozzi-StoneR1.ogg", "Fantozzi-StoneR2.ogg", "Fantozzi-StoneR3.ogg"]:
		var step_stream: AudioStream = load("res://asset/sound/SFX/stone_footsteps/%s" % step_name)
		if step_stream != null:
			stone_footstep_streams.append(step_stream)
	if not stone_footstep_streams.is_empty():
		footstep_player.stream = stone_footstep_streams[0]

	cave_player = _make_added_audio_player("CaveAmbiencePlayer", "res://asset/sound/Ambient/dark_cavern_ambient_002.ogg", -32.0)
	var cave_loop: AudioStreamOggVorbis = cave_player.stream as AudioStreamOggVorbis
	if cave_loop != null:
		cave_loop.loop = true
	rockfall_player = _make_added_audio_player("RockfallPlayer", "res://asset/sound/SFX/falling_rock.wav", -12.0)
	enemy_growl_player = _make_added_audio_player("EnemyGrowlPlayer", "res://asset/sound/SFX/enemy_growl.mp3", -14.0)
	attack_stinger_player = _make_added_audio_player("AttackStingerPlayer", "res://asset/sound/SFX/attack_stinger.mp3", -12.0)
	dash_whoosh_player = _make_added_audio_player("DashWhooshPlayer", "res://asset/sound/SFX/dash_whoosh.mp3", -17.0)

	wind_player.play()
	music_player.play()
	cave_player.play()

	footstep_player.play()
	footstep_player.volume_db = -15

	_build_stamina_bar()
	_build_grab_hand()
	grab_timer = randf_range(grab_min_gap, grab_max_gap)
	_build_stone_threat()
	stone_timer = randf_range(4.0, 6.0)

	# capture the run's start / finish X so the top bar can show how far to go
	hero_start_x = hero_node.global_position.x
	door_x = get_parent().get_node("door").global_position.x

	_build_progress_bar()
	_build_pause_button()
	_build_overlays()

	# show the tutorial on the first run of the session, unless the player
	# has chosen to skip it (choice persists in the Difficulty autoload)
	if Difficulty.skip_tutorial:
		in_tutorial = false
	else:
		_show_tutorial()

func play_dash_sound():
	dash_whoosh_player.play()

func _stop_run_audio():
	wind_player.stop()
	music_player.stop()
	cave_player.stop()
	heartbeat_player.stop()
	footstep_player.stop()
	rockfall_player.stop()

# ===============================
# DIFFICULTY
# ===============================

# Reads the mode picked on the difficulty menu (held in the Difficulty
# autoload) and tunes the run. The base (@export) values ARE Normal.
# HARD closes faster, gives a tighter reaction window and no "LOOK BEHIND
# YOU!" tell — but a timed peek still shoves it back hard, so a skilled
# player can still win. EASY widens every margin.
func _apply_difficulty():
	# NOTE: use if/elif, not match. `Difficulty` is an autoload singleton, so
	# `Difficulty.Mode.EASY` is a runtime lookup, not a compile-time constant —
	# and match patterns must be constant, which is what broke compilation here.
	var mode = Difficulty.current
	if mode == Difficulty.Mode.EASY:
		approach_speed *= 0.70
		approach_ramp *= 0.55
		max_approach_speed *= 0.80
		danger_range *= 1.30          # more time to react
		good_pushback *= 1.15         # peeks relieve more
		grab_enabled = false          # no underground hand on Easy
		stone_min_gap *= 1.3
		stone_max_gap *= 1.3
		stone_warning_time *= 1.2
		show_tell = true
	elif mode == Difficulty.Mode.HARD:
		approach_speed *= 1.45         # closes in noticeably faster
		approach_ramp *= 1.35
		max_approach_speed *= 1.40
		close_boost *= 1.20
		danger_range *= 0.82           # razor-thin reaction window
		good_pushback *= 1.30          # a perfect look-back still saves you → still winnable
		grab_min_gap *= 0.70           # grabs come more often
		grab_max_gap *= 0.70
		grab_taps_needed = 5           # 5 taps to break free (was 3)
		grab_time_limit *= 1.10        # a little more time, since it takes more taps
		stone_min_gap *= 0.75
		stone_max_gap *= 0.75
		stone_warning_time *= 0.85
		show_tell = false              # no warning: you must feel it coming
	else:
		# NORMAL — use the exported defaults as-is
		show_tell = true

# ===============================
# NERVE BAR (built in code)
# ===============================

func _build_stamina_bar():
	var ui = get_parent().get_node("UI")

	# vertical bar standing on the left edge; it empties from the top as nerve drains
	var bar_x := 30.0
	var bar_top := 70.0
	var bar_w := 26.0
	var bar_h := 220.0

	var label = Label.new()
	label.text = "NERVE"
	label.position = Vector2(bar_x - 6, 42)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.90, 0.82, 0.62))       # torchlit parchment
	label.add_theme_color_override("font_shadow_color", Color(0.04, 0.03, 0.02))
	label.add_theme_constant_override("shadow_offset_y", 2)
	ui.add_child(label)

	# moon-lit frame behind the bar
	var frame = ColorRect.new()
	frame.color = Color(0.45, 0.36, 0.25, 0.5)   # bronze / iron rim
	frame.position = Vector2(bar_x - 2, bar_top - 2)
	frame.size = Vector2(bar_w + 4, bar_h + 4)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(frame)

	var bg = ColorRect.new()
	bg.color = Color(0.06, 0.05, 0.04, 0.85)       # dark stone
	bg.position = Vector2(bar_x, bar_top)
	bg.size = Vector2(bar_w, bar_h)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bg)

	# the fill rect's geometry — update grows it from the bottom up
	nerve_fill_x = bar_x + 2
	nerve_fill_top = bar_top + 2
	nerve_fill_w = bar_w - 4
	nerve_fill_h = bar_h - 4

	stamina_fill = ColorRect.new()
	stamina_fill.color = Color(0.83, 0.58, 0.22)   # torch gold
	stamina_fill.position = Vector2(nerve_fill_x, nerve_fill_top)
	stamina_fill.size = Vector2(nerve_fill_w, nerve_fill_h)
	stamina_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(stamina_fill)

func _update_stamina_bar():
	if stamina_fill == null:
		return

	var ratio = clamp(stamina / max_stamina, 0.0, 1.0)
	var h = nerve_fill_h * ratio
	# shrink from the top so the column drains downward
	stamina_fill.size = Vector2(nerve_fill_w, h)
	stamina_fill.position = Vector2(nerve_fill_x, nerve_fill_top + (nerve_fill_h - h))

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

	# frozen while reading the tutorial or sitting on the pause screen
	if in_tutorial or is_paused:
		return

	# nerve recovers over time; peek cooldown ticks down
	stamina = min(stamina + stamina_regen * delta, max_stamina)
	if peek_cooldown_timer > 0.0:
		peek_cooldown_timer -= delta
	_update_stamina_bar()
	_update_progress_bar()

	# a hand has you — everything else (running, the creature, peeking) is on
	# hold until you break free or get dragged under
	if is_grabbed:
		_process_grab(delta)
		return

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
		if in_danger and show_tell:
			enemy_growl_player.play()
		if not in_danger and not feedback_active:
			feedback_label.visible = false
	if show_tell and in_danger and not feedback_active:
		feedback_label.text = "LOOK BEHIND YOU!"
		feedback_label.modulate = Color(1.0, 0.25, 0.22)
		feedback_label.visible = true

	if creature_distance <= 0:
		game_over()

	var tension = clamp(1.0 - (creature_distance / starting_distance), 0.0, 1.0)

	update_audio(tension)

	update_footsteps(delta)

	# schedule the next grab — never while the creature is already on you
	# (no stacked threats) and never in the opening seconds. Off on Easy.
	if grab_enabled:
		grab_timer -= delta
		if grab_timer <= 0.0 and creature_distance > danger_range + 20.0 and not stone_warning_active:
			_start_grab()

	# Schedule stones separately, but never stack them on a grab or the creature.
	if not stone_warning_active and not is_grabbed:
		stone_timer -= delta
		var stone_safety_margin := (max_approach_speed + close_boost) * (stone_warning_time + stone_fall_time) + 10.0
		if stone_timer <= 0.0 and creature_distance > danger_range + stone_safety_margin and not villain_node.visible:
			_start_stone_warning()

	_process_stone(delta)

# ===============================
# FALLING STONES
# ===============================

func _build_stone_threat():
	stone_visual = Node2D.new()
	stone_visual.visible = false
	stone_visual.z_index = 20
	get_parent().add_child.call_deferred(stone_visual)

	stone_sprite = Sprite2D.new()
	# Rocks (Rework) by patvanmackelberg and AntumDeluge; released as CC0.
	stone_sprite.texture = load("res://asset/object/environment/falling_rocks.png")
	stone_sprite.region_enabled = true
	stone_sprite.region_rect = Rect2(0, 0, 64, 64)
	stone_visual.add_child(stone_sprite)

	stone_shadow = Polygon2D.new()
	stone_shadow.color = Color(0.02, 0.02, 0.02, 0.55)
	var shadow_points := PackedVector2Array()
	for i in 20:
		var angle := TAU * float(i) / 20.0
		shadow_points.append(Vector2(cos(angle) * 42.0, sin(angle) * 9.0))
	stone_shadow.polygon = shadow_points
	stone_shadow.visible = false
	stone_shadow.z_index = 10
	get_parent().add_child.call_deferred(stone_shadow)

func _start_stone_warning():
	stone_warning_active = true
	stone_warning_left = stone_warning_time
	stone_falling = false
	stone_fall_elapsed = 0.0
	stone_visual.rotation = 0.0
	stone_shadow.global_position = hero_node.global_position + Vector2(0, 8)
	stone_shadow.visible = true
	stone_visual.global_position = hero_node.global_position + Vector2(0, -STONE_DROP_HEIGHT)
	stone_visual.visible = true
	feedback_active = true
	feedback_label.text = "RUMBLE..."
	feedback_label.modulate = Color(0.95, 0.76, 0.35)
	feedback_label.visible = true

func _process_stone(delta: float):
	if not stone_warning_active:
		return

	if not stone_falling:
		stone_warning_left -= delta
		stone_shadow.global_position = hero_node.global_position + Vector2(0, 8)
		stone_visual.global_position = hero_node.global_position + Vector2(0, -STONE_DROP_HEIGHT)
		if stone_warning_left <= 0.0:
			stone_falling = true
			stone_fall_elapsed = 0.0
			stone_visual.global_position = hero_node.global_position + Vector2(0, -STONE_DROP_HEIGHT)
			feedback_label.text = "STONEFALL!  DASH NOW!"
			feedback_label.modulate = Color(1.0, 0.28, 0.2)
			rockfall_player.play()
			shake_camera()
		return

	stone_fall_elapsed += delta
	var fall_ratio: float = clampf(stone_fall_elapsed / stone_fall_time, 0.0, 1.0)
	stone_visual.global_position.x = hero_node.global_position.x
	stone_visual.global_position.y = hero_node.global_position.y - STONE_DROP_HEIGHT * (1.0 - fall_ratio)
	stone_visual.rotation = fall_ratio * 0.25
	if fall_ratio >= 1.0:
		stone_warning_active = false
		stone_visual.visible = false
		stone_shadow.visible = false
		feedback_active = false
		feedback_label.visible = false
		if hero_node.is_dashing:
			show_feedback("DODGED!", Color(0.3, 1.0, 0.3))
		else:
			stone_game_over()
		stone_timer = randf_range(stone_min_gap, stone_max_gap)
# ===============================
# GRAB EVENT
# ===============================

func _build_grab_hand():
	var tex = load("res://asset/object/hand/spr_hand_strip7.png")
	var frames = SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("appear")
	frames.set_animation_loop("appear", false)
	frames.set_animation_speed("appear", 12.0)
	for i in range(0, 4):
		var at = AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * 64, 0, 64, 64)
		frames.add_frame("appear", at)
	frames.add_animation("grab")
	frames.set_animation_loop("grab", false)
	frames.set_animation_speed("grab", 10.0)
	for i in range(4, 7):
		var at = AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * 64, 0, 64, 64)
		frames.add_frame("grab", at)

	grab_sprite = AnimatedSprite2D.new()
	grab_sprite.sprite_frames = frames
	grab_sprite.visible = false
	grab_sprite.z_index = 2000        # draws over the hero
	grab_sprite.position = Vector2(0, 10)   # seats the dirt mound on the floor line
	hero_node.add_child(grab_sprite)

func _start_grab():
	is_grabbed = true
	grab_timing = false            # timer starts only after the burst, so the clock is fair
	grab_taps = grab_taps_needed
	grab_time_left = grab_time_limit
	feedback_active = false        # take sole ownership of the prompt label

	hero_node.set_physics_process(false)           # freeze the run
	hero_node.get_node("AnimatedSprite2D").play("idle")

	grab_sprite.visible = true
	grab_sprite.play("appear")

	peek_player.pitch_scale = 0.7
	peek_player.volume_db = -2
	peek_player.play()
	shake_camera()
	_show_grab_prompt()

	await grab_sprite.animation_finished
	if is_grabbed:                                 # didn't break free during the burst
		grab_sprite.play("grab")
		grab_time_left = grab_time_limit
		grab_timing = true                         # NOW the break-free clock starts

func _process_grab(delta):
	if not grab_timing:
		return
	grab_time_left -= delta
	if grab_time_left <= 0.0:
		_grab_fail()

func _show_grab_prompt():
	feedback_label.text = "BREAK FREE!  TAP x%d" % grab_taps
	feedback_label.modulate = Color(1.0, 0.3, 0.25)
	feedback_label.scale = Vector2.ONE
	feedback_label.visible = true

# called by the hero on every tap/press while grabbed
func grab_tap():
	if not is_grabbed:
		return
	grab_taps -= 1

	peek_player.pitch_scale = randf_range(1.0, 1.2)
	peek_player.volume_db = -6
	peek_player.play()
	shake_camera()

	if grab_taps <= 0:
		_end_grab()
	else:
		_show_grab_prompt()

func _end_grab():
	is_grabbed = false
	grab_timing = false
	feedback_active = false                        # release the label lock
	feedback_label.visible = false                 # clear the prompt immediately
	grab_sprite.play_backwards("appear")           # hand recoils back underground
	hero_node.set_physics_process(true)
	hero_node.get_node("AnimatedSprite2D").play("run")
	grab_timer = randf_range(grab_min_gap, grab_max_gap)
	show_feedback("FREE!", Color(0.3, 1.0, 0.3))
	await get_tree().create_timer(0.45).timeout
	if not is_grabbed:                             # not re-grabbed in the meantime
		grab_sprite.visible = false

func _grab_fail():
	if is_game_over:
		return
	is_game_over = true
	is_grabbed = false
	grab_timing = false

	grab_sprite.play("grab")                        # clenched, dragging you under
	hero_node.get_node("AnimatedSprite2D").play("death")
	feedback_label.visible = false

	await get_tree().create_timer(0.6).timeout
	_stop_run_audio()
	enemy_growl_player.stop()
	attack_stinger_player.play()
	await fade_to_black()

	end_label.text = "DRAGGED UNDER"
	end_label.modulate = Color(0.85, 0.1, 0.1)

# ===============================
# PEEK SYSTEM
# ===============================

# Returns true only if the peek was actually accepted (used by the hero to
# play the look-back animation). Spamming is rejected here, so both the key
# and the touch input paths are safe.
func peek_trigger() -> bool:

	if is_game_over:
		return false

	# a hand has you — peeking is disabled until you break free
	if is_grabbed:
		return false

	# on cooldown -> ignore, so mashing does nothing
	if peek_cooldown_timer > 0.0:
		return false

	# the creature is scared off if the look-back lands while it's genuinely
	# close — a window wider than the razor-thin tell range, so peeking when it
	# LOOKS right behind you saves you instead of reading "TOO EARLY"
	var save_range := danger_range * save_range_mult
	var in_zone := creature_distance <= save_range
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

	if in_zone:
		# it was close enough -> the look-back scares it off
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

	# never fight the grab prompt for the label
	if feedback_active or is_grabbed:
		return
	feedback_active = true

	feedback_label.text = text
	feedback_label.modulate = color
	feedback_label.visible = true
	feedback_label.scale = Vector2(1.3, 1.3)

	var tween = create_tween()
	tween.tween_property(feedback_label, "scale", Vector2.ONE, 0.2)

	await get_tree().create_timer(0.4).timeout
	feedback_active = false
	if not is_grabbed:                 # a grab may have taken the label mid-wait
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
	villain_node.global_position = hero_node.global_position + Vector2(-46, 0)

	await get_tree().create_timer(0.2).timeout

	villain_node.get_node("AnimatedSprite2D").play("attack")
	enemy_growl_player.stop()
	attack_stinger_player.play()
	await get_tree().create_timer(0.3).timeout
	hero_node.get_node("AnimatedSprite2D").play("death")

	await get_tree().create_timer(0.6).timeout
	_stop_run_audio()
	await fade_to_black()

	end_label.text = "YOU FAILED"
	end_label.modulate = Color(1, 0.1, 0.1)

func stone_game_over():
	if is_game_over:
		return

	is_game_over = true
	hero_node.set_physics_process(false)
	villain_node.visible = false
	hero_node.get_node("AnimatedSprite2D").play("death")
	_stop_run_audio()
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

	_stop_run_audio()
	
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
	cave_player.volume_db = lerp(-32, -25, tension)

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
		if not stone_footstep_streams.is_empty():
			footstep_player.stream = stone_footstep_streams[randi_range(0, stone_footstep_streams.size() - 1)]
		footstep_player.pitch_scale = randf_range(0.95, 1.05)
		footstep_player.play()

		# Dynamic interval based on tension
		var tension = 1.0 - (creature_distance / starting_distance)

		# Early game slower steps, late game slightly faster
		footstep_interval = lerp(3.0, 1.5, tension)

		# Add randomness
		footstep_timer = footstep_interval + randf_range(0.2, 0.8)
		

func _on_restart_button_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_menu_button_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scene/main_menu.tscn")


# ===============================
# PAUSE  (ESC toggles; also exposed as buttons)
# ===============================

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()

func _toggle_pause():
	# never pause over an end screen, mid-grab, or while the tutorial is up
	if is_game_over or is_grabbed or in_tutorial:
		return
	if is_paused:
		_resume_game()
	else:
		_open_pause()

func _open_pause():
	is_paused = true
	pause_root.visible = true
	get_tree().paused = true

func _resume_game():
	is_paused = false
	pause_root.visible = false
	get_tree().paused = false

func _on_resume_pressed():
	_resume_game()

# ===============================
# PROGRESS BAR  (top-centre: how far the hero is to the door)
# ===============================

func _build_progress_bar():
	var ui = get_parent().get_node("UI")
	var left = 640.0 - progress_bar_w * 0.5

	var label = Label.new()
	label.text = "DISTANCE TO THE DOOR"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if overlay_font:
		label.add_theme_font_override("font", overlay_font)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.90, 0.82, 0.62))
	label.add_theme_color_override("font_shadow_color", Color(0.04, 0.03, 0.02))
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(left, 14)
	label.size = Vector2(progress_bar_w, 20)
	ui.add_child(label)

	var frame = ColorRect.new()
	frame.color = Color(0.45, 0.36, 0.25, 0.5)   # bronze / iron rim
	frame.position = Vector2(left - 2, 40)
	frame.size = Vector2(progress_bar_w + 4, 22)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(frame)

	var bg = ColorRect.new()
	bg.color = Color(0.06, 0.05, 0.04, 0.85)      # dark stone
	bg.position = Vector2(left, 42)
	bg.size = Vector2(progress_bar_w, 18)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bg)

	progress_fill = ColorRect.new()
	progress_fill.color = Color(0.55, 0.78, 0.45)  # eerie safe-green
	progress_fill.position = Vector2(left, 42)
	progress_fill.size = Vector2(0, 18)
	progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(progress_fill)

# the on-screen pause button (☰) — the touch-friendly way in; ESC does the same
func _build_pause_button():
	var ui = get_parent().get_node("UI")

	var btn = Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(52, 44)
	btn.size = Vector2(52, 44)
	btn.position = Vector2(1280 - 66, 14)

	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.08, 0.06, 0.85)
	sb.border_color = Color(0.45, 0.36, 0.25)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", sb)
	var sb_hover = sb.duplicate()
	sb_hover.bg_color = Color(0.16, 0.12, 0.08, 0.95)
	sb_hover.border_color = Color(0.80, 0.60, 0.30)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("focus", sb_hover)
	var sb_pressed = sb.duplicate()
	sb_pressed.bg_color = Color(0.22, 0.08, 0.06, 1.0)
	btn.add_theme_stylebox_override("pressed", sb_pressed)

	# three bars drawn by hand, so the icon never depends on a font glyph
	for i in 3:
		var bar = ColorRect.new()
		bar.color = Color(0.90, 0.82, 0.62)
		bar.size = Vector2(26, 4)
		bar.position = Vector2(13, 12 + i * 9)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(bar)

	btn.pressed.connect(_toggle_pause)
	ui.add_child(btn)

func _update_progress_bar():
	if progress_fill == null:
		return
	var span = door_x - hero_start_x
	if span <= 0.0:
		return
	var ratio = clamp((hero_node.global_position.x - hero_start_x) / span, 0.0, 1.0)
	progress_fill.size.x = progress_bar_w * ratio
	# flares to torch-gold on the final stretch to the door
	progress_fill.color = Color(0.95, 0.85, 0.35) if ratio > 0.85 else Color(0.55, 0.78, 0.45)

# ===============================
# OVERLAYS  (tutorial + pause, built in code on their own layer)
# ===============================

func _build_overlays():
	overlay_layer = CanvasLayer.new()
	overlay_layer.layer = 90        # above the HUD, below the end screen (100)
	# deferred: `main` is still setting up its children during our _ready,
	# so attaching straight to the parent now would be rejected
	get_parent().add_child.call_deferred(overlay_layer)

	tutorial_root = _make_screen_root()
	tutorial_root.visible = false
	overlay_layer.add_child(tutorial_root)
	_build_tutorial_content(tutorial_root)

	pause_root = _make_screen_root()
	pause_root.visible = false
	overlay_layer.add_child(pause_root)
	_build_pause_content(pause_root)

func _build_tutorial_content(root: Control):
	var vb = root.get_node("Center/Box")
	vb.add_child(_make_title("HOW TO SURVIVE"))

	var lines = [
		"A dark hall. A locked door at the far end.",
		"Something is behind you — and it is closing in.",
		"",
		"You RUN on your own.  Just reach the door.",
		"[ SPACE / CLICK / TAP ]  glance back to scare it off —",
		"      but only when it is right on you. Mind your NERVE.",
		"When a stone falls, press [ V ] during the impact to dash clear.",
		"A hand may burst from the floor:  TAP fast to break free.",
		"[ ESC ]  pause  ·  restart  ·  quit",
	]
	for t in lines:
		vb.add_child(_make_info_label(t))

	var skip = CheckBox.new()
	skip.text = "  Skip this tutorial for the rest of the session"
	skip.button_pressed = Difficulty.skip_tutorial
	skip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if overlay_font:
		skip.add_theme_font_override("font", overlay_font)
	skip.add_theme_font_size_override("font_size", 18)
	skip.add_theme_color_override("font_color", Color(0.85, 0.78, 0.6))
	skip.toggled.connect(_on_skip_toggled)
	vb.add_child(skip)

	var begin = _make_overlay_button("BEGIN")
	begin.pressed.connect(_on_begin_pressed)
	vb.add_child(begin)

func _build_pause_content(root: Control):
	var vb = root.get_node("Center/Box")
	vb.add_child(_make_title("PAUSED"))

	var resume = _make_overlay_button("RESUME")
	resume.pressed.connect(_on_resume_pressed)
	vb.add_child(resume)

	var restart = _make_overlay_button("RESTART")
	restart.pressed.connect(_on_restart_button_pressed)
	vb.add_child(restart)

	var quit = _make_overlay_button("QUIT TO MENU")
	quit.pressed.connect(_on_menu_button_pressed)
	vb.add_child(quit)

func _show_tutorial():
	in_tutorial = true
	tutorial_root.visible = true
	get_tree().paused = true

func _on_begin_pressed():
	in_tutorial = false
	tutorial_root.visible = false
	get_tree().paused = false

func _on_skip_toggled(pressed: bool):
	Difficulty.set_skip_tutorial(pressed)

# ===============================
# OVERLAY BUILDING BLOCKS
# ===============================

func _make_screen_root() -> Control:
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.process_mode = Node.PROCESS_MODE_ALWAYS   # keeps working while paused

	var dim = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.03, 0.85)
	root.add_child(dim)

	var center = CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var box = VBoxContainer.new()
	box.name = "Box"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	return root

func _make_title(text: String) -> Label:
	var l = Label.new()
	l.text = text
	if overlay_font:
		l.add_theme_font_override("font", overlay_font)
	l.add_theme_font_size_override("font_size", 56)
	l.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	l.add_theme_color_override("font_shadow_color", Color(0.70, 0.14, 0.16, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return l

func _make_info_label(text: String) -> Label:
	var l = Label.new()
	l.text = text
	if overlay_font:
		l.add_theme_font_override("font", overlay_font)
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color(0.86, 0.82, 0.72))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return l

func _make_overlay_button(text: String) -> Button:
	var b = Button.new()
	b.text = text
	if overlay_font:
		b.add_theme_font_override("font", overlay_font)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", Color(0.9, 0.82, 0.62))
	b.add_theme_color_override("font_hover_color", Color(0.95, 0.78, 0.4))
	b.add_theme_color_override("font_pressed_color", Color(0.8, 0.3, 0.25))
	b.custom_minimum_size = Vector2(320, 54)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.08, 0.06, 0.95)
	sb.border_color = Color(0.45, 0.36, 0.25)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	b.add_theme_stylebox_override("normal", sb)

	var sb_hover = sb.duplicate()
	sb_hover.bg_color = Color(0.16, 0.12, 0.08, 0.98)
	sb_hover.border_color = Color(0.80, 0.60, 0.30)
	b.add_theme_stylebox_override("hover", sb_hover)
	b.add_theme_stylebox_override("focus", sb_hover)

	var sb_pressed = sb.duplicate()
	sb_pressed.bg_color = Color(0.22, 0.08, 0.06, 1.0)
	b.add_theme_stylebox_override("pressed", sb_pressed)

	return b
