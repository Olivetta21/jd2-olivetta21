"""Relay WebSocket for the cemetery game.

The server deliberately does not simulate the game. The first client is the
enemy authority; the server only validates the room size and relays snapshots.
"""

import asyncio
import contextlib
import json
import logging
import os
import time
from dataclasses import dataclass

from websockets.exceptions import ConnectionClosed
from websockets.server import serve

MAX_PLAYERS = 40
MAX_DEATHS = 5
HOST_TIMEOUT_SECONDS = 4.0
HOST_WATCHDOG_INTERVAL = 1.0
PATH = "/ws/cemiterio"
DEBUG_LOGGING = True

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s [cemiterio-ws] %(message)s",
)
logger = logging.getLogger("cemiterio-ws")
logger.setLevel(logging.DEBUG if DEBUG_LOGGING else logging.INFO)
logging.getLogger("websockets").setLevel(logging.WARNING)


@dataclass
class Client:
    websocket: object
    player_id: int
    x: float = 0.0
    y: float = 0.0
    dx: float = 0.0
    dy: float = 0.0
    last_seen: float = 0.0
    name: str = "Jogador"
    active: bool = False

    def state(self) -> dict:
        return {
            "t": "player",
            "id": self.player_id,
            "name": self.name,
            "x": self.x,
            "y": self.y,
            "dx": self.dx,
            "dy": self.dy,
        }


clients: dict[int, Client] = {}
total_deaths = 0
total_kills = 0
game_over = False
host_id: int | None = None
dead_players: set[int] = set()
next_id = 1


def clientes_ativos() -> dict[int, Client]:
    return {player_id: client for player_id, client in clients.items() if client.active}


async def promover_host(novo_host_id: int | None, motivo: str) -> None:
    global host_id
    if novo_host_id is None or novo_host_id not in clients or novo_host_id == host_id:
        return
    host_id = novo_host_id
    logger.info("novo host id=%d motivo=%s", host_id, motivo)
    await broadcast({"t": "host", "id": host_id})
    await broadcast({"t": "game", "kills": total_kills, "deaths": total_deaths})


async def host_watchdog() -> None:
    while True:
        await asyncio.sleep(HOST_WATCHDOG_INTERVAL)
        ativos = clientes_ativos()
        if not ativos:
            continue
        if host_id is None or host_id not in ativos:
            await promover_host(min(ativos), "host ausente")
            continue
        host = ativos[host_id]
        elapsed = time.monotonic() - host.last_seen
        if elapsed > HOST_TIMEOUT_SECONDS:
            logger.warning(
                "host congelado id=%d sem mensagens por %.1fs; promovendo proximo",
                host.player_id,
                elapsed,
            )
            candidatos = [player_id for player_id in ativos if player_id != host_id]
            if candidatos:
                await promover_host(min(candidatos), "host sem heartbeat")


async def send(websocket: object, message: dict) -> None:
    message_type = message.get("t", "?")
    try:
        await websocket.send(json.dumps(message, separators=(",", ":")))
    except Exception:
        logger.exception("falha ao enviar tipo=%s", message_type)
        raise


async def broadcast(message: dict, excluded: int | None = None) -> None:
    payload = json.dumps(message, separators=(",", ":"))
    resultados = await asyncio.gather(
        *(client.websocket.send(payload) for player_id, client in clients.items()
          if player_id != excluded),
        return_exceptions=True,
    )
    for resultado in resultados:
        if isinstance(resultado, Exception):
            logger.warning("falha em broadcast tipo=%s erro=%r", message.get("t", "?"), resultado)


async def handler(websocket: object) -> None:
    global game_over, host_id, next_id, total_deaths, total_kills
    request = getattr(websocket, "request", None)
    request_path = getattr(request, "path", None)
    if request_path is None:
        request_path = getattr(websocket, "path", None)
    if request_path != PATH or len(clients) >= MAX_PLAYERS:
        logger.warning("conexao recusada caminho=%s jogadores=%d", request_path, len(clients))
        await websocket.close(code=1013, reason="Sala cheia ou caminho invalido")
        return

    player_id = next_id
    next_id += 1
    client = Client(websocket, player_id, last_seen=time.monotonic())
    was_empty = not clients
    if was_empty:
        total_deaths = 0
        total_kills = 0
        game_over = False
        dead_players.clear()
    clients[player_id] = client
    logger.info("cliente conectado id=%d caminho=%s jogadores=%d host=%s",
                player_id, request_path, len(clients), False)
    await send(websocket, {
        "t": "welcome",
        "id": player_id,
        "host": False,
        "deaths": total_deaths,
        "kills": total_kills,
        "players": [other.state() for other_id, other in clients.items()
                    if other_id != player_id and other.active],
    })
    if game_over:
        await send(websocket, {"t": "game_over", "result": "defeat"})

    try:
        async for raw_message in websocket:
            client.last_seen = time.monotonic()
            try:
                message = json.loads(raw_message)
            except (TypeError, json.JSONDecodeError):
                logger.warning("mensagem JSON invalida id=%d bytes=%d", player_id, len(raw_message))
                continue
            if not isinstance(message, dict):
                logger.warning("mensagem nao-objeto id=%d tipo=%s", player_id, type(message).__name__)
                continue
            message_type = message.get("t")
            if message_type == "heartbeat":
                continue
            if message_type == "set_name":
                nome = str(message.get("name", "")).strip()[:20]
                if not nome:
                    logger.warning("nome vazio rejeitado id=%d", player_id)
                    continue
                iniciar_nova_partida = not clientes_ativos()
                if iniciar_nova_partida:
                    total_deaths = 0
                    total_kills = 0
                    game_over = False
                    dead_players.clear()
                tornou_ativo = not client.active
                client.name = nome
                client.active = True
                if host_id is None or host_id not in clientes_ativos():
                    host_id = player_id
                if tornou_ativo:
                    logger.info("jogador ativo id=%d nome=%s host=%s",
                                player_id, client.name, player_id == host_id)
                    ativos = clientes_ativos()
                    await send(websocket, {
                        "t": "activated",
                        "id": player_id,
                        "host": player_id == host_id,
                        "deaths": total_deaths,
                        "kills": total_kills,
                        "players": [other.state() for other_id, other in ativos.items()
                                    if other_id != player_id],
                    })
                    await broadcast(client.state(), excluded=player_id)
                    await broadcast({"t": "notice", "kind": "join", "name": client.name},
                                    excluded=player_id)
                    await broadcast({"t": "host", "id": host_id})
                continue
            if message_type == "player" and client.active:
                try:
                    name = str(message.get("name", client.name)).strip()
                    if name:
                        client.name = name[:20]
                    client.x = float(message.get("x", client.x))
                    client.y = float(message.get("y", client.y))
                    client.dx = max(-1.0, min(1.0, float(message.get("dx", 0.0))))
                    client.dy = max(-1.0, min(1.0, float(message.get("dy", 0.0))))
                except (TypeError, ValueError):
                    logger.warning("estado de jogador invalido id=%d", player_id)
                    continue
                await broadcast(client.state(), excluded=player_id)
            elif message_type == "enemies" and client.active and player_id == host_id:
                message.pop("id", None)
                await broadcast(message, excluded=player_id)
            elif message_type == "attack" and client.active:
                message["id"] = player_id
                await broadcast(message, excluded=player_id)
            elif message_type == "damage" and client.active and player_id == host_id:
                await broadcast(message, excluded=player_id)
            elif message_type == "respawn" and client.active:
                dead_players.discard(player_id)
            elif message_type == "death" and client.active and not game_over and player_id not in dead_players:
                dead_players.add(player_id)
                total_deaths += 1
                logger.info("morte registrada id=%d total da partida=%d/%d",
                            player_id, total_deaths, MAX_DEATHS)
                await broadcast({
                    "t": "death",
                    "id": player_id,
                    "name": client.name,
                    "count": total_deaths,
                })
                await broadcast({
                    "t": "game",
                    "kills": total_kills,
                    "deaths": total_deaths,
                })
                await broadcast({"t": "notice", "kind": "death", "name": client.name})
                if total_deaths >= MAX_DEATHS:
                    game_over = True
                    await broadcast({"t": "game_over", "result": "defeat", "id": player_id})
            elif message_type == "kill" and client.active and player_id == host_id:
                total_kills += 1
                logger.debug("abate registrado pelo host id=%d total=%d", player_id, total_kills)
                await broadcast({"t": "game", "kills": total_kills})
            elif message_type == "game" and client.active and player_id == host_id:
                message["kills"] = total_kills
                message["deaths"] = total_deaths
                await broadcast(message)
            elif message_type == "game_over" and client.active and player_id == host_id:
                await broadcast(message, excluded=player_id)
            else:
                logger.debug("mensagem ignorada id=%d tipo=%s", player_id, message_type)
    except ConnectionClosed as error:
        logger.info("conexao encerrada id=%d codigo=%s motivo=%s",
                    player_id, error.code, error.reason)
    except Exception:
        logger.exception("erro inesperado na conexao id=%d", player_id)
    finally:
        clients.pop(player_id, None)
        close_code = getattr(websocket, "close_code", None)
        close_reason = getattr(websocket, "close_reason", None)
        logger.info("cliente desconectado id=%d codigo=%s motivo=%s jogadores=%d",
                    player_id, close_code, close_reason, len(clients))
        if client.active:
            await broadcast({"t": "leave", "id": player_id})
            await broadcast({"t": "notice", "kind": "leave", "name": client.name})
        if player_id == host_id:
            host_id = None
            ativos = clientes_ativos()
            if ativos:
                await promover_host(min(ativos), "host desconectado")
        if not clients:
            host_id = None
            total_deaths = 0
            total_kills = 0
            game_over = False
            dead_players.clear()


async def main() -> None:
    port = int(os.environ.get("PORT", "8765"))
    watchdog_task = asyncio.create_task(host_watchdog())
    async with serve(handler, "0.0.0.0", port, max_size=2**20, ping_interval=20):
        logger.info("servidor iniciado porta=%d caminho=%s limite=%d debug=%s",
                    port, PATH, MAX_PLAYERS, DEBUG_LOGGING)
        try:
            await asyncio.Future()
        finally:
            watchdog_task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await watchdog_task


if __name__ == "__main__":
    asyncio.run(main())
