extends CharacterBody2D

var alvo_posicao := Vector2.ZERO
var ultima_direcao := Vector2.DOWN
var velocidade_rede := Vector2.ZERO
var nome := ""
const SUAVIZACAO := 14.0

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var anim_ataque: AnimatedSprite2D = $Ataque/AnimatedSprite2D
@onready var texto_nome: Label = $Nome

func _ready() -> void:
	alvo_posicao = global_position
	anim.play("baixo")
	anim_ataque.animation_finished.connect(_on_ataque_finished)
	anim_ataque.visible = false

func get_nome() -> String:
	return nome

func atualizar_rede(posicao: Vector2, direcao: Vector2, nome_recebido: String = "") -> void:
	velocidade_rede = (posicao - alvo_posicao) / 0.05
	alvo_posicao = posicao
	if direcao.length_squared() > 0.01:
		ultima_direcao = direcao
	if nome_recebido != "":
		nome = nome_recebido
		texto_nome.text = nome

func atacar(direcao: Vector2) -> void:
	if direcao.length_squared() > 0.01:
		ultima_direcao = direcao
	anim_ataque.visible = true
	anim_ataque.play("golpe")

func _on_ataque_finished() -> void:
	anim_ataque.visible = false

func _physics_process(delta: float) -> void:
	var alvo_visual := alvo_posicao + velocidade_rede * 0.05
	global_position = global_position.lerp(alvo_visual, 1.0 - exp(-SUAVIZACAO * delta))
	if ultima_direcao.length_squared() <= 0.01:
		return
	if abs(ultima_direcao.x) > abs(ultima_direcao.y):
		anim.play("direita" if ultima_direcao.x > 0.0 else "esquerda")
	else:
		anim.play("baixo" if ultima_direcao.y > 0.0 else "cima")
