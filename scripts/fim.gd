extends Control

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_accept"):
		print("[JOGO] Reiniciando partida")
		get_tree().change_scene_to_file("res://scenes/cemiterio.tscn")
