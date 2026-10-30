extends Node2D

const ENDPOINT := "wss://jogos.olivetta.com.br/ws/cemiterio"
const DEBUG_LOGGING := true
const REMOTE_HUMAN := preload("res://scenes/humano.tscn")
const ENEMY_SNAPSHOT_INTERVAL := 0.2
const ENEMY_SMOOTHING_SPEED := 16.0
const PLAYER_SNAPSHOT_INTERVAL := 0.05
const HOST_HEARTBEAT_INTERVAL := 0.5
const DEBUG_REPORT_INTERVAL := 2.0
const MAX_DEATHS := 5
const RESPAWN_DELAY := 1.0
const GAME_STATE_INTERVAL := 0.2
const ENEMIES_PER_DAMAGE_STEP := 5
const DAMAGE_MULTIPLIER_STEP := 0.25

@export var inimigos: Array[InimigoChance] = []

@onready var horda: Timer = $Horda
@onready var relogio: Timer = $Relogio
@onready var jogador := $jogador
@onready var texto_vida: Label = $HUD/Vida
@onready var texto_tempo: Label = $HUD/Tempo
@onready var texto_inimigos: Label = $HUD/Inimigos
@onready var dica_controles: Label = $HUD/DicaControles
@onready var posicao_inicial_jogador: Vector2 = jogador.global_position

var abates := 0
var mortes := 0
var tempo_restante := 0.0
var jogo_encerrado := false
var jogador_aguardando_respawn := false
var nome_jogador := ""
var nome_confirmado := false
var entrada_nome: LineEdit
var botao_nome: Button
var socket := WebSocketPeer.new()
var meu_id := -1
var sou_autoridade := false
var tempo_snapshot_inimigos := 0.0
var tempo_snapshot_jogador := 0.0
var tempo_heartbeat := 0.0
var tempo_snapshot_estado := 0.0
var ultima_posicao_jogador := Vector2.INF
var remotos: Dictionary = {}
var inimigos_remotos: Dictionary = {}
var alvos_inimigos_remotos: Dictionary = {}
var velocidades_inimigos_remotos: Dictionary = {}
var ultimo_estado_socket := -1
var snapshot_inimigos_pendente: Array = []
var debug_tempo_relatorio := 0.0
var debug_mensagens_recebidas := 0
var debug_bytes_recebidos := 0

func _ready() -> void:
	horda.stop()
	jogador.set_physics_process(false)
	jogador.visible = false
	jogador.collision_layer = 0
	jogador.collision_mask = 0
	criar_seletor_nome()
	tempo_restante = relogio.time_left
	var erro := socket.connect_to_url(ENDPOINT)
	debug_log("conectando endpoint=%s erro=%s" % [ENDPOINT, erro])

func _process(delta: float) -> void:
	socket.poll()
	debug_tempo_relatorio += delta
	var estado_socket := socket.get_ready_state()
	if estado_socket != ultimo_estado_socket:
		ultimo_estado_socket = estado_socket
		debug_log("estado socket=%s" % nome_estado_socket(estado_socket))
		if estado_socket == WebSocketPeer.STATE_CLOSED:
			debug_log("socket fechado codigo=%d motivo=%s" % [
				socket.get_close_code(), socket.get_close_reason()
			])
	while socket.get_available_packet_count() > 0:
		var pacote := socket.get_packet().get_string_from_utf8()
		var mensagem = JSON.parse_string(pacote)
		if mensagem is Dictionary:
			debug_mensagens_recebidas += 1
			debug_bytes_recebidos += pacote.length()
			receber_mensagem(mensagem)
		else:
			debug_log("mensagem invalida bytes=%d" % pacote.length())

	if not snapshot_inimigos_pendente.is_empty() and not sou_autoridade:
		aplicar_snapshot_inimigos(snapshot_inimigos_pendente)
		snapshot_inimigos_pendente.clear()

	if debug_tempo_relatorio >= DEBUG_REPORT_INTERVAL:
		debug_tempo_relatorio = 0.0
		debug_log("trafego recebido mensagens=%d bytes=%d fila=%d inimigos_remotos=%d" % [
			debug_mensagens_recebidas,
			debug_bytes_recebidos,
			socket.get_available_packet_count(),
			inimigos_remotos.size()
		])
		debug_mensagens_recebidas = 0
		debug_bytes_recebidos = 0

	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		tempo_heartbeat += delta
		if tempo_heartbeat >= HOST_HEARTBEAT_INTERVAL:
			tempo_heartbeat = 0.0
			enviar({"t": "heartbeat"})
		tempo_snapshot_jogador += delta
		if tempo_snapshot_jogador >= PLAYER_SNAPSHOT_INTERVAL:
			tempo_snapshot_jogador = 0.0
			enviar_estado_jogador()

		if sou_autoridade:
			tempo_snapshot_inimigos += delta
			if tempo_snapshot_inimigos >= ENEMY_SNAPSHOT_INTERVAL:
				tempo_snapshot_inimigos = 0.0
				enviar_snapshot_inimigos()
			tempo_snapshot_estado += delta
			if tempo_snapshot_estado >= GAME_STATE_INTERVAL:
				tempo_snapshot_estado = 0.0
				enviar({
					"t": "game",
					"kills": abates,
					"deaths": mortes,
					"time": relogio.time_left
				})

	if not sou_autoridade:
		suavizar_inimigos_remotos(delta)

	texto_vida.text = "Vida: %d Abates: %d" % [jogador.vida, abates]
	texto_inimigos.text = "Inimigos: %d Dano: x%.2f" % [
		contar_inimigos(),
		calcular_multiplicador_dano()
	]
	texto_tempo.text = "Tempo: %d Mortes: %d/%d" % [
		ceil(tempo_restante), mortes, MAX_DEATHS
	]
	if sou_autoridade and not jogo_encerrado:
		tempo_restante = relogio.time_left

func receber_mensagem(mensagem: Dictionary) -> void:
	match mensagem.get("t", ""):
		"welcome":
			meu_id = int(mensagem.get("id", -1))
			mortes = int(mensagem.get("deaths", mortes))
			abates = int(mensagem.get("kills", abates))
			definir_autoridade(bool(mensagem.get("host", false)))
			for estado in mensagem.get("players", []):
				adicionar_remoto(estado)
		"join":
			adicionar_remoto(mensagem)
		"leave":
			remover_remoto(int(mensagem.get("id", -1)))
		"player":
			if int(mensagem.get("id", -1)) != meu_id:
				adicionar_ou_atualizar_remoto(mensagem)
		"host":
			definir_autoridade(int(mensagem.get("id", -1)) == meu_id)
		"enemies":
			if not sou_autoridade:
				snapshot_inimigos_pendente = mensagem.get("items", [])
		"attack":
			var atacante = remotos.get(int(mensagem.get("id", -1)))
			if atacante != null:
				atacante.atacar(Vector2(float(mensagem.get("dx", 0.0)), float(mensagem.get("dy", 0.0))))
			if sou_autoridade:
				aplicar_ataque_remoto(Vector2(float(mensagem.get("x", 0.0)), float(mensagem.get("y", 0.0))))
		"damage":
			if int(mensagem.get("id", -1)) == meu_id:
				jogador.levar_dano(int(mensagem.get("amount", 1)))
		"game":
			abates = int(mensagem.get("kills", abates))
			mortes = int(mensagem.get("deaths", mortes))
			tempo_restante = float(mensagem.get("time", tempo_restante))
		"game_over":
			if mensagem.get("result", "defeat") == "victory":
				vencer()
			else:
				finalizar_derrota()
		"death":
			mortes = int(mensagem.get("count", mortes))
			debug_log("jogador %d morreu total da partida=%d" % [
				int(mensagem.get("id", -1)), mortes
			])

func definir_autoridade(valor: bool) -> void:
	if sou_autoridade == valor:
		return
	sou_autoridade = valor
	if sou_autoridade:
		horda.start()
		for inimigo in inimigos_remotos.values():
			inimigo.process_mode = Node.PROCESS_MODE_INHERIT
	else:
		horda.stop()
		for inimigo in get_tree().get_nodes_in_group("inimigo"):
			if inimigo != null:
				inimigo.process_mode = Node.PROCESS_MODE_DISABLED

func enviar_estado_jogador() -> void:
	if meu_id < 0 or not nome_confirmado:
		return
	var posicao: Vector2 = jogador.global_position
	if posicao.distance_squared_to(ultima_posicao_jogador) < 0.04:
		return
	ultima_posicao_jogador = posicao
	var direcao: Vector2 = jogador.velocity.normalized()
	enviar({"t": "player", "name": nome_jogador, "x": posicao.x, "y": posicao.y,
		"dx": direcao.x, "dy": direcao.y})

func jogador_atacou(atacante: Node2D) -> void:
	if atacante == jogador and not jogador_aguardando_respawn:
		var direcao: Vector2 = jogador.velocity.normalized()
		enviar({"t": "attack", "x": atacante.global_position.x, "y": atacante.global_position.y,
			"dx": direcao.x, "dy": direcao.y})

func get_alvo_inimigo(origem: Vector2) -> Node2D:
	var alvo: Node2D = null
	var distancia := INF
	if not jogador.em_respawn:
		alvo = jogador
		distancia = origem.distance_squared_to(jogador.global_position)
	for remoto in remotos.values():
		if remoto == null or not is_instance_valid(remoto):
			continue
		var distancia_remota := origem.distance_squared_to(remoto.global_position)
		if distancia_remota < distancia:
			alvo = remoto
			distancia = distancia_remota
	return alvo

func aplicar_dano_jogador(alvo: Node2D, dano: int) -> void:
	if alvo == jogador:
		jogador.levar_dano(dano)
		return
	var id := int(alvo.get_meta("player_id", -1))
	if id >= 0:
		enviar({"t": "damage", "id": id, "amount": dano})

func jogador_morreu(alvo: Node2D) -> void:
	if alvo != jogador or jogo_encerrado or jogador_aguardando_respawn:
		return
	jogador_aguardando_respawn = true
	enviar({"t": "death"})
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	if not jogo_encerrado and is_instance_valid(jogador):
		jogador.renascer(posicao_inicial_jogador)
		jogador_aguardando_respawn = false
		enviar({"t": "respawn"})

func criar_seletor_nome() -> void:
	entrada_nome = LineEdit.new()
	entrada_nome.placeholder_text = "Digite seu nome"
	entrada_nome.max_length = 20
	entrada_nome.position = Vector2(180, 150)
	entrada_nome.size = Vector2(220, 42)
	$HUD.add_child(entrada_nome)
	botao_nome = Button.new()
	botao_nome.text = "Entrar"
	botao_nome.position = Vector2(410, 150)
	botao_nome.size = Vector2(90, 42)
	botao_nome.pressed.connect(confirmar_nome)
	$HUD.add_child(botao_nome)
	entrada_nome.grab_focus()

func confirmar_nome() -> void:
	var nome := entrada_nome.text.strip_edges()
	if nome.is_empty():
		return
	nome_jogador = nome
	nome_confirmado = true
	entrada_nome.queue_free()
	botao_nome.queue_free()
	jogador.collision_layer = 2
	jogador.collision_mask = 3
	jogador.visible = true
	jogador.set_physics_process(true)
	enviar_estado_jogador()
	mostrar_dica_controles()

func mostrar_dica_controles() -> void:
	dica_controles.text = "Controle: WASD + Espaço ou touchscreen"
	dica_controles.visible = true
	await get_tree().create_timer(4.0).timeout
	if is_instance_valid(dica_controles):
		dica_controles.visible = false

func finalizar_derrota() -> void:
	if jogo_encerrado:
		return
	jogo_encerrado = true
	horda.stop()
	get_tree().change_scene_to_file.call_deferred("res://scenes/derrota.tscn")

func aplicar_ataque_remoto(posicao: Vector2) -> void:
	var dano_atual := calcular_dano_jogador(1)
	for inimigo in get_tree().get_nodes_in_group("inimigo"):
		if not inimigo.morreu and inimigo.global_position.distance_squared_to(posicao) <= 24.0 * 24.0:
			inimigo.levar_golpe(dano_atual)

func contar_inimigos() -> int:
	if sou_autoridade:
		return get_tree().get_nodes_in_group("inimigo").size()
	return inimigos_remotos.size()

func calcular_multiplicador_dano() -> float:
	var faixas := contar_inimigos() / ENEMIES_PER_DAMAGE_STEP
	return 1.0 + faixas * DAMAGE_MULTIPLIER_STEP

func calcular_dano_jogador(dano_base: int) -> int:
	return maxi(1, ceili(float(dano_base) * calcular_multiplicador_dano()))

func enviar(mensagem: Dictionary) -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var pacote := JSON.stringify(mensagem)
		var erro := socket.send_text(pacote)
		if erro != OK:
			debug_log("falha envio tipo=%s erro=%s" % [mensagem.get("t", "?"), erro])
	elif DEBUG_LOGGING:
		debug_log("envio ignorado socket=%s tipo=%s" % [
			nome_estado_socket(socket.get_ready_state()), mensagem.get("t", "?")
		])

func debug_log(mensagem: String) -> void:
	if DEBUG_LOGGING:
		print("[WS CLIENT] %s" % mensagem)

func nome_estado_socket(estado: int) -> String:
	match estado:
		WebSocketPeer.STATE_CONNECTING:
			return "connecting"
		WebSocketPeer.STATE_OPEN:
			return "open"
		WebSocketPeer.STATE_CLOSING:
			return "closing"
		WebSocketPeer.STATE_CLOSED:
			return "closed"
	return "unknown(%d)" % estado

func adicionar_remoto(estado: Dictionary) -> void:
	var id := int(estado.get("id", -1))
	if id >= 0 and id != meu_id and not remotos.has(id):
		var humano := REMOTE_HUMAN.instantiate()
		humano.name = "humano_%d" % id
		humano.set_meta("player_id", id)
		add_child(humano)
		remotos[id] = humano
	adicionar_ou_atualizar_remoto(estado)

func adicionar_ou_atualizar_remoto(estado: Dictionary) -> void:
	var id := int(estado.get("id", -1))
	if id < 0 or id == meu_id:
		return
	if not remotos.has(id):
		adicionar_remoto(estado)
	var humano = remotos.get(id)
	if humano != null:
		humano.atualizar_rede(Vector2(float(estado.get("x", 0.0)), float(estado.get("y", 0.0))),
			Vector2(float(estado.get("dx", 0.0)), float(estado.get("dy", 0.0))),
			str(estado.get("name", "")))

func remover_remoto(id: int) -> void:
	var humano = remotos.get(id)
	remotos.erase(id)
	if humano != null:
		humano.queue_free()

func enviar_snapshot_inimigos() -> void:
	var itens: Array = []
	for inimigo in get_tree().get_nodes_in_group("inimigo"):
		if inimigo.morreu:
			continue
		itens.append({
			"id": inimigo.get_instance_id(),
			"kind": inimigo.scene_file_path,
			"x": inimigo.global_position.x,
			"y": inimigo.global_position.y,
			"hp": inimigo.vida
		})
	enviar({"t": "enemies", "items": itens})

func aplicar_snapshot_inimigos(itens: Array) -> void:
	var presentes := {}
	for item in itens:
		if not item is Dictionary:
			continue
		var id := int(item.get("id", -1))
		if id < 0:
			continue
		presentes[id] = true
		var inimigo = inimigos_remotos.get(id)
		if inimigo == null:
			var cena := load(item.get("kind", ""))
			if cena is PackedScene:
				inimigo = cena.instantiate()
				add_child(inimigo)
				inimigo.process_mode = Node.PROCESS_MODE_DISABLED
				inimigo.global_position = Vector2(float(item.get("x", 0.0)), float(item.get("y", 0.0)))
				inimigos_remotos[id] = inimigo
		if inimigo != null:
			var alvo: Vector2 = Vector2(
				float(item.get("x", 0.0)),
				float(item.get("y", 0.0))
			)
			var anterior: Vector2 = alvos_inimigos_remotos.get(id, alvo)
			velocidades_inimigos_remotos[id] = (alvo - anterior) / ENEMY_SNAPSHOT_INTERVAL
			alvos_inimigos_remotos[id] = alvo
			inimigo.vida = int(item.get("hp", 1))
	for id in inimigos_remotos.keys():
		if not presentes.has(id):
			inimigos_remotos[id].queue_free()
			inimigos_remotos.erase(id)
			alvos_inimigos_remotos.erase(id)
			velocidades_inimigos_remotos.erase(id)

func suavizar_inimigos_remotos(delta: float) -> void:
	var fator := 1.0 - exp(-ENEMY_SMOOTHING_SPEED * delta)
	for id in alvos_inimigos_remotos.keys():
		var inimigo = inimigos_remotos.get(id)
		if inimigo == null:
			alvos_inimigos_remotos.erase(id)
			continue
		var alvo: Vector2 = alvos_inimigos_remotos[id]
		var velocidade: Vector2 = velocidades_inimigos_remotos.get(id, Vector2.ZERO)
		var alvo_visual := alvo + velocidade * 0.08
		inimigo.global_position = inimigo.global_position.lerp(alvo_visual, fator)

func _on_horda_timeout() -> void:
	if not sou_autoridade:
		return
	var cena_inimigo := escolher_inimigo()
	if cena_inimigo == null:
		return
	var inimigo := cena_inimigo.instantiate()
	inimigo.global_position = $Nascedouros.get_children().pick_random().global_position
	add_child(inimigo)
	horda.wait_time = max(0.5, horda.wait_time * 0.95)

func _on_relogio_timeout() -> void:
	if sou_autoridade and not jogo_encerrado:
		enviar({"t": "game_over", "result": "victory"})
		vencer()

func vencer() -> void:
	get_tree().change_scene_to_file.call_deferred("res://scenes/vitoria.tscn")

func perder() -> void:
	get_tree().change_scene_to_file.call_deferred("res://scenes/derrota.tscn")

func escolher_inimigo() -> PackedScene:
	var total: float = 0.0
	for inimigo in inimigos:
		total += inimigo.chance
	if total <= 0.0:
		return null
	var sorteio := randf() * total
	for inimigo in inimigos:
		sorteio -= inimigo.chance
		if sorteio < 0.0:
			return inimigo.cena
	return null

func inimigo_morreu(_inimigo: Node2D) -> void:
	abates += 1
	if sou_autoridade:
		enviar({"t": "kill"})
