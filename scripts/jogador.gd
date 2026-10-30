extends CharacterBody2D

@export var velocidade: float = 70.0
@export var vida: int = 3
@export var vida_maxima: int = 3
@export var dano: int = 1

enum PlayerState {
	IDLE,
	MOVING,
	ATTACK,
	HURT,
	DEATH
}

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var ataque: Area2D = $Ataque
@onready var anim_golpe: AnimatedSprite2D = $Ataque/AnimatedSprite2D
@onready var controles_moveis: Control = get_tree().get_first_node_in_group("controles_moveis") as Control

var status: PlayerState = PlayerState.IDLE
var invencivel := false
var em_respawn := false
var tempo_no_estado := 0.0
var dano_do_ataque_aplicado := false

const TEMPO_HURT := 1.0

func _ready() -> void:
	anim.stop()
	anim_golpe.stop()
	anim_golpe.visible = false
	anim_golpe.animation_finished.connect(_on_golpe_animation_finished)
	mudar_estado(PlayerState.IDLE)

func mudar_estado(novo_estado: PlayerState) -> void:
	if status == novo_estado and novo_estado != PlayerState.ATTACK:
		return

	status = novo_estado
	tempo_no_estado = 0.0

	match status:
		PlayerState.IDLE:
			velocity = Vector2.ZERO
			anim.stop()
		PlayerState.MOVING:
			pass
		PlayerState.ATTACK:
			dano_do_ataque_aplicado = false
			anim_golpe.visible = true
			anim_golpe.play("golpe")
			var cena := get_tree().current_scene
			if cena.has_method("jogador_atacou"):
				cena.jogador_atacou(self)
		PlayerState.HURT:
			invencivel = true
			modulate.a = 0.4
		PlayerState.DEATH:
			velocity = Vector2.ZERO
			em_respawn = true
			set_physics_process(false)
			collision_layer = 0
			collision_mask = 0
			ataque.set_deferred("monitoring", false)
			var hurtbox := get_node_or_null("Hurtbox") as Area2D
			if hurtbox != null:
				hurtbox.set_deferred("monitoring", false)
			anim_golpe.stop()
			anim_golpe.visible = false

func _physics_process(delta: float) -> void:
	match status:
		PlayerState.IDLE:
			estado_parado()
		PlayerState.MOVING:
			estado_movendo()
		PlayerState.ATTACK:
			estado_atacando()
		PlayerState.HURT:
			estado_ferido(delta)
		PlayerState.DEATH:
			return

	move_and_slide()

func estado_parado() -> void:
	if ataque_solicitado():
		mudar_estado(PlayerState.ATTACK)
		return

	var direcao := ler_direcao()
	if direcao != Vector2.ZERO:
		mudar_estado(PlayerState.MOVING)

func estado_movendo() -> void:
	if ataque_solicitado():
		mudar_estado(PlayerState.ATTACK)
		return

	var direcao := ler_direcao()
	if direcao == Vector2.ZERO:
		mudar_estado(PlayerState.IDLE)

func estado_atacando() -> void:
	ler_direcao()

	if not dano_do_ataque_aplicado:
		aplicar_dano_do_ataque()
		dano_do_ataque_aplicado = true

func _on_golpe_animation_finished() -> void:
	if status != PlayerState.ATTACK or anim_golpe.animation != &"golpe":
		return

	anim_golpe.visible = false
	var proximo_estado := PlayerState.MOVING if get_direcao() != Vector2.ZERO else PlayerState.IDLE
	mudar_estado(proximo_estado)

func estado_ferido(delta: float) -> void:
	tempo_no_estado += delta
	ler_direcao()
	if tempo_no_estado >= TEMPO_HURT:
		invencivel = false
		modulate.a = 1.0
		var proximo_estado := PlayerState.MOVING if get_direcao() != Vector2.ZERO else PlayerState.IDLE
		mudar_estado(proximo_estado)

func ler_direcao() -> Vector2:
	var direcao := get_direcao()
	velocity = direcao * velocidade

	if direcao == Vector2.ZERO:
		anim.stop()
	elif abs(direcao.x) > abs(direcao.y):
		anim.play("direita" if direcao.x > 0 else "esquerda")
	else:
		anim.play("baixo" if direcao.y > 0 else "cima")

	return direcao

func get_direcao() -> Vector2:
	var direcao := Input.get_vector("left", "right", "up", "down")
	if controles_moveis != null:
		var direcao_toque: Vector2 = controles_moveis.get_direction()
		if direcao_toque != Vector2.ZERO:
			return direcao_toque
	return direcao

func ataque_solicitado() -> bool:
	if Input.is_action_just_pressed("atacar"):
		return true
	return controles_moveis != null and controles_moveis.consume_attack()

func aplicar_dano_do_ataque() -> void:
	var dano_atual := dano
	var cena := get_tree().current_scene
	if cena.has_method("calcular_dano_jogador"):
		dano_atual = cena.calcular_dano_jogador(dano)
	for alvo in ataque.get_overlapping_bodies():
		if alvo.is_in_group("inimigo") and alvo.has_method("levar_golpe"):
			alvo.levar_golpe(dano_atual)

func levar_dano(valor: int) -> void:
	if invencivel or em_respawn or status == PlayerState.DEATH:
		return

	vida -= valor
	if vida <= 0:
		mudar_estado(PlayerState.DEATH)
		var cena := get_tree().current_scene
		if cena.has_method("jogador_morreu"):
			cena.jogador_morreu(self)
		return
	mudar_estado(PlayerState.HURT)

func renascer(posicao: Vector2) -> void:
	em_respawn = false
	set_physics_process(true)
	collision_layer = 2
	collision_mask = 3
	ataque.set_deferred("monitoring", true)
	var hurtbox := get_node_or_null("Hurtbox") as Area2D
	if hurtbox != null:
		hurtbox.set_deferred("monitoring", true)
	vida = vida_maxima
	global_position = posicao
	velocity = Vector2.ZERO
	invencivel = true
	modulate.a = 0.4
	mudar_estado(PlayerState.HURT)
