# jd2-olivetta21

## Multiplayer

O jogo conecta automaticamente a `wss://jogos.olivetta.com.br/ws/cemiterio`.
O Apache deve encaminhar esse caminho para o processo Python em `localhost:8765`
com suporte a upgrade para WebSocket.

Para executar o relay:

```powershell
python -m pip install -r Servidor/requirements.txt
python Servidor/websocket.py
```

O servidor limita a sala a 40 jogadores e não simula o jogo. O primeiro
jogador conectado controla a geração, a movimentação e o estado dos inimigos.
Se ele sair, o servidor promove o jogador conectado há mais tempo e o novo
host continua enviando os snapshots dos inimigos.

## Logs de conexão

O diagnóstico pode ser ligado ou desligado diretamente no código:

- Cliente: `DEBUG_LOGGING` em [scripts/cemiterio.gd](./scripts/cemiterio.gd).
- Servidor: `DEBUG_LOGGING` em [Servidor/websocket.py](./Servidor/websocket.py).

Com o diagnóstico ligado, o cliente registra estados do WebSocket, tipos de
mensagens, falhas de envio e código/motivo de fechamento. O servidor registra
conexões recusadas, clientes conectados/desconectados, mensagens inválidas,
falhas de broadcast e exceções.