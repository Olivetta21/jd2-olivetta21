extends CharacterBody2D
@export var velocidade: float = 40.0
@export var vida: int = 1
@export var dano: int = 1
@export var forca_arremesso: float = 180.0
@export var atraso_morte: float = 0.3
var velocidade_arremesso := Vector2.ZERO
var morreu := false

@onready var agente: NavigationAgent2D = $NavigationAgent2D

func _physics_process(_delta: float) -> void:
	if velocidade_arremesso != Vector2.ZERO:
		velocity = velocidade_arremesso
		move_and_slide()
		velocidade_arremesso = velocidade_arremesso.move_toward(Vector2.ZERO, forca_arremesso * 4.0 * _delta)
		return
	if morreu:
		return

	var jogador := get_tree().get_first_node_in_group("player") as Node2D
	if jogador == null:
		return
	
	agente.target_position = jogador.global_position
	var proximo := agente.get_next_path_position()
	velocity = global_position.direction_to(proximo) * velocidade
	move_and_slide()

	var hurtbox := jogador.get_node("Hurtbox") as Area2D
	if hurtbox.get_overlapping_bodies().has(self):
		jogador.call("levar_dano", dano)

func levar_golpe(dano_recebido: int) -> void:
	if morreu:
		return

	vida -= dano_recebido

	var jogador := get_tree().get_first_node_in_group("player") as Node2D
	if jogador != null:
		var direcao_arremesso := jogador.global_position.direction_to(global_position)
		velocidade_arremesso = direcao_arremesso * forca_arremesso

	if vida <= 0:
		morreu = true
		get_tree().current_scene.inimigo_morreu(self)
		await get_tree().create_timer(atraso_morte).timeout
		queue_free()
