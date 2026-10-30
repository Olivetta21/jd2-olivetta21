extends Control

const JOYSTICK_RADIUS := 58.0
const KNOB_RADIUS := 25.0
const ATTACK_RADIUS := 42.0
const MARGIN := 28.0

var joystick_center := Vector2.ZERO
var joystick_knob := Vector2.ZERO
var joystick_touch := -1
var attack_touch := -1
var ataque_solicitado := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = OS.has_feature("web") or DisplayServer.is_touchscreen_available()
	_recalcular_posicoes()
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_recalcular_posicoes()
		queue_redraw()

func _recalcular_posicoes() -> void:
	var tamanho := size
	joystick_center = Vector2(MARGIN + JOYSTICK_RADIUS, tamanho.y - MARGIN - JOYSTICK_RADIUS)
	if joystick_touch == -1:
		joystick_knob = joystick_center

func _draw() -> void:
	if not visible:
		return

	draw_circle(joystick_center, JOYSTICK_RADIUS, Color(0.1, 0.1, 0.1, 0.45))
	draw_arc(joystick_center, JOYSTICK_RADIUS, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.7), 2.0)
	draw_circle(joystick_knob, KNOB_RADIUS, Color(0.85, 0.85, 0.85, 0.8))

	var ataque_center := Vector2(size.x - MARGIN - ATTACK_RADIUS, size.y - MARGIN - ATTACK_RADIUS)
	draw_circle(ataque_center, ATTACK_RADIUS, Color(0.75, 0.15, 0.15, 0.7))
	draw_arc(ataque_center, ATTACK_RADIUS, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.85), 2.0)
	draw_string(ThemeDB.fallback_font, ataque_center - Vector2(17.0, -7.0), "ATK", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_iniciar_toque(event.index, event.position)
		else:
			_finalizar_toque(event.index)
	elif event is InputEventScreenDrag:
		if event.index == joystick_touch:
			_atualizar_joystick(event.position)

func _iniciar_toque(indice: int, posicao: Vector2) -> void:
	var ataque_center := Vector2(size.x - MARGIN - ATTACK_RADIUS, size.y - MARGIN - ATTACK_RADIUS)
	if posicao.distance_to(ataque_center) <= ATTACK_RADIUS and attack_touch == -1:
		attack_touch = indice
		ataque_solicitado = true
	elif posicao.distance_to(joystick_center) <= JOYSTICK_RADIUS * 1.5 and joystick_touch == -1:
		joystick_touch = indice
		_atualizar_joystick(posicao)

func _atualizar_joystick(posicao: Vector2) -> void:
	var deslocamento := posicao - joystick_center
	if deslocamento.length() > JOYSTICK_RADIUS:
		deslocamento = deslocamento.normalized() * JOYSTICK_RADIUS
	joystick_knob = joystick_center + deslocamento
	queue_redraw()

func _finalizar_toque(indice: int) -> void:
	if indice == joystick_touch:
		joystick_touch = -1
		joystick_knob = joystick_center
		queue_redraw()
	elif indice == attack_touch:
		attack_touch = -1

func get_direction() -> Vector2:
	if joystick_touch == -1:
		return Vector2.ZERO
	return (joystick_knob - joystick_center) / JOYSTICK_RADIUS

func consume_attack() -> bool:
	if not ataque_solicitado:
		return false
	ataque_solicitado = false
	return true
