extends CharacterBody2D
@export var velocidade: float = 40.0
@export var vida: int = 1
@export var dano: int = 1
@export var forca_arremesso: float = 180.0
@export var atraso_morte: float = 0.3

@onready var agente: NavigationAgent2D = $NavigationAgent2D
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

enum EnemyState {
	IDLE,
	MOVING,
	ATTACK,
	THROWN,
	DEATH
}

var status: EnemyState = EnemyState.IDLE
var velocidade_arremesso := Vector2.ZERO
var morreu := false
var tempo_no_estado := 0.0
var jogador: Node2D

const TEMPO_ATAQUE := 0.4

func _ready() -> void:
	anim.stop()
	mudar_estado(EnemyState.IDLE)

func mudar_estado(novo_estado: EnemyState) -> void:
	if status == novo_estado:
		return
	status = novo_estado
	tempo_no_estado = 0.0

	match status:
		EnemyState.IDLE:
			velocity = Vector2.ZERO
			anim.stop()
		EnemyState.MOVING:
			anim.play("walk")
		EnemyState.ATTACK:
			velocity = Vector2.ZERO
		EnemyState.THROWN:
			pass
		EnemyState.DEATH:
			velocity = Vector2.ZERO

func _physics_process(_delta: float) -> void:
	if morreu:
		return

	match status:
		EnemyState.IDLE, EnemyState.MOVING:
			estado_perseguindo()
		EnemyState.ATTACK:
			estado_atacando(_delta)
		EnemyState.THROWN:
			estado_arremessado(_delta)
		EnemyState.DEATH:
			return

	move_and_slide()

func estado_perseguindo() -> void:
	jogador = get_tree().current_scene.get_alvo_inimigo(global_position)
	if jogador == null:
		mudar_estado(EnemyState.IDLE)
		return

	var proximo := agente.get_next_path_position()
	velocity = global_position.direction_to(proximo) * velocidade
	if velocity.length_squared() > 0.0:
		mudar_estado(EnemyState.MOVING)
	else:
		mudar_estado(EnemyState.IDLE)

	if global_position.distance_squared_to(jogador.global_position) <= 18.0 * 18.0:
		mudar_estado(EnemyState.ATTACK)

func estado_atacando(delta: float) -> void:
	tempo_no_estado += delta
	if jogador == null:
		mudar_estado(EnemyState.IDLE)
		return

	if global_position.distance_squared_to(jogador.global_position) > 20.0 * 20.0:
		mudar_estado(EnemyState.IDLE)
	elif tempo_no_estado >= TEMPO_ATAQUE:
		get_tree().current_scene.aplicar_dano_jogador(jogador, dano)
		tempo_no_estado = 0.0

func estado_arremessado(delta: float) -> void:
	velocity = velocidade_arremesso
	velocidade_arremesso = velocidade_arremesso.move_toward(Vector2.ZERO, forca_arremesso * 4.0 * delta)
	if velocidade_arremesso == Vector2.ZERO:
		mudar_estado(EnemyState.IDLE)

func levar_golpe(dano_recebido: int) -> void:
	if morreu:
		return

	vida -= dano_recebido
	var jogador_atual := get_tree().current_scene.get_alvo_inimigo(global_position) as Node2D
	if jogador_atual != null:
		var direcao_arremesso := jogador_atual.global_position.direction_to(global_position)
		velocidade_arremesso = direcao_arremesso * forca_arremesso
		mudar_estado(EnemyState.THROWN)

	if vida <= 0:
		morreu = true
		mudar_estado(EnemyState.DEATH)
		get_tree().current_scene.inimigo_morreu(self)
		await get_tree().create_timer(atraso_morte).timeout
		queue_free()

func _on_timer_timeout() -> void:
	if jogador == null:
		return
	
	agente.target_position = jogador.global_position
