extends Control

var music_on = true

func _ready():
	modulate.a = 0
	
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 1.2)

func _on_start_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scene/main.tscn")


func _on_credit_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scene/credits.tscn")


func _on_Endbutton_pressed() -> void:
	get_tree().quit()
