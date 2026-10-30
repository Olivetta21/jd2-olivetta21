"""Relay WebSocket for the cemetery game.

The server deliberately does not simulate the game. The first client is the
enemy authority; the server only validates the room size and relays snapshots.
"""

import asyncio
import json
import logging
import os
from dataclasses import dataclass

from websockets.server import serve

MAX_PLAYERS = 40
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

    def state(self) -> dict:
        return {
            "t": "player",
            "id": self.player_id,
            "x": self.x,
            "y": self.y,
            "dx": self.dx,
            "dy": self.dy,
        }


clients: dict[int, Client] = {}
next_id = 1


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
    global next_id
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
    client = Client(websocket, player_id)
    was_empty = not clients
    clients[player_id] = client
    logger.info("cliente conectado id=%d caminho=%s jogadores=%d host=%s",
                player_id, request_path, len(clients), was_empty)
    await send(websocket, {
        "t": "welcome",
        "id": player_id,
        "host": was_empty,
        "players": [other.state() for other_id, other in clients.items()
                    if other_id != player_id],
    })
    await broadcast(client.state(), excluded=player_id)

    try:
        async for raw_message in websocket:
            try:
                message = json.loads(raw_message)
            except (TypeError, json.JSONDecodeError):
                logger.warning("mensagem JSON invalida id=%d bytes=%d", player_id, len(raw_message))
                continue
            if not isinstance(message, dict):
                logger.warning("mensagem nao-objeto id=%d tipo=%s", player_id, type(message).__name__)
                continue
            message_type = message.get("t")
            if message_type == "player":
                try:
                    client.x = float(message.get("x", client.x))
                    client.y = float(message.get("y", client.y))
                    client.dx = max(-1.0, min(1.0, float(message.get("dx", 0.0))))
                    client.dy = max(-1.0, min(1.0, float(message.get("dy", 0.0))))
                except (TypeError, ValueError):
                    logger.warning("estado de jogador invalido id=%d", player_id)
                    continue
                await broadcast(client.state(), excluded=player_id)
            elif message_type == "enemies" and player_id == min(clients):
                message.pop("id", None)
                await broadcast(message, excluded=player_id)
            elif message_type == "attack" and player_id != min(clients):
                message.pop("id", None)
                await broadcast(message, excluded=player_id)
            else:
                logger.debug("mensagem ignorada id=%d tipo=%s", player_id, message_type)
    except Exception:
        logger.exception("erro inesperado na conexao id=%d", player_id)
    finally:
        clients.pop(player_id, None)
        close_code = getattr(websocket, "close_code", None)
        close_reason = getattr(websocket, "close_reason", None)
        logger.info("cliente desconectado id=%d codigo=%s motivo=%s jogadores=%d",
                    player_id, close_code, close_reason, len(clients))
        await broadcast({"t": "leave", "id": player_id})
        if clients:
            logger.info("novo host id=%d", min(clients))
            await broadcast({"t": "host", "id": min(clients)})


async def main() -> None:
    port = int(os.environ.get("PORT", "8765"))
    async with serve(handler, "0.0.0.0", port, max_size=2**20, ping_interval=20):
        logger.info("servidor iniciado porta=%d caminho=%s limite=%d debug=%s",
                    port, PATH, MAX_PLAYERS, DEBUG_LOGGING)
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
