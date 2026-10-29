extends CharacterBody2D

@export var velocidade: float = 70.0
@export var vida: int = 3
var invencivel := false

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

func _physics_process(_delta: float) -> void:
	var direcao = Input.get_vector("left", "right", "up", "down")
	velocity = direcao * velocidade
	move_and_slide()

	if direcao == Vector2.ZERO:
		anim.stop()
		return

	if abs(direcao.x) > abs(direcao.y):
		if direcao.x > 0:
			anim.play("direita")
		else:
			anim.play("esquerda")
	else:
		if direcao.y > 0:
			anim.play("baixo")
		else:
			anim.play("cima")

func levar_dano(valor: int) -> void:
	if invencivel:
		return

	vida -= valor
	if vida <= 0:
		get_tree().current_scene.perder()
		return
	# Um segundo de invencibilidade, meio transparente.
	invencivel = true
	modulate.a = 0.4
	await get_tree().create_timer(1.0).timeout
	modulate.a = 1.0
	invencivel = false
