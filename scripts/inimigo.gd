extends CharacterBody2D
@export var velocidade: float = 40.0
@export var dano: int = 1

func _physics_process(_delta: float) -> void:
	var jogador := get_tree().get_first_node_in_group("player") as Node2D
	if jogador == null:
		return
	velocity = global_position.direction_to(jogador.global_position) * velocidade
	move_and_slide()

	var hurtbox := jogador.get_node("Hurtbox") as Area2D
	if hurtbox.get_overlapping_bodies().has(self):
		jogador.call("levar_dano", dano)
