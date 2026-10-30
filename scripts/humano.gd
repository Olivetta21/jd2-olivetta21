extends CharacterBody2D

var alvo_posicao := Vector2.ZERO
var ultima_direcao := Vector2.DOWN

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	alvo_posicao = global_position
	anim.play("baixo")

func atualizar_rede(posicao: Vector2, direcao: Vector2) -> void:
	alvo_posicao = posicao
	if direcao.length_squared() > 0.01:
		ultima_direcao = direcao

func _physics_process(delta: float) -> void:
	global_position = global_position.lerp(alvo_posicao, min(1.0, delta * 14.0))
	if ultima_direcao.length_squared() <= 0.01:
		return
	if abs(ultima_direcao.x) > abs(ultima_direcao.y):
		anim.play("direita" if ultima_direcao.x > 0.0 else "esquerda")
	else:
		anim.play("baixo" if ultima_direcao.y > 0.0 else "cima")
