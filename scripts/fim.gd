extends Control

var reiniciando := false

func _process(_delta: float) -> void:
	if not reiniciando and Input.is_action_just_pressed("ui_accept"):
		reiniciar_jogo()

func _input(event: InputEvent) -> void:
	if not reiniciando and event is InputEventScreenTouch and event.pressed:
		reiniciar_jogo()

func reiniciar_jogo() -> void:
	reiniciando = true
	get_tree().change_scene_to_file("res://scenes/cemiterio.tscn")
