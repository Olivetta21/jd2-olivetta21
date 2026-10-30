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

Os inimigos controlados pelo host escolhem o jogador conectado mais próximo
como alvo, incluindo jogadores remotos. O dano contra um jogador remoto é
encaminhado ao cliente responsável por ele. Os demais clientes interpolam e
extrapolam levemente os snapshots dos inimigos para manter o movimento visual
contínuo.

O cliente envia um heartbeat a cada 0,5 segundo. Se o servidor não receber
mensagens do host por 4 segundos, considera que o processo congelou e
promove automaticamente o próximo jogador. A conexão do host antigo não é
encerrada; ele permanece na sala, mas suas mensagens de autoridade são
ignoradas até o fim da partida.

Cada jogador possui vida própria, mas as mortes são contabilizadas em um
contador global da partida. Ao morrer, o jogador renasce na posição inicial
após um segundo. A partida termina para todos quando o contador global
alcança 5 mortes. O tempo restante e a quantidade de abates também são
compartilhados e sincronizados pelo host.

## Logs de conexão

O diagnóstico pode ser ligado ou desligado diretamente no código:

- Cliente: `DEBUG_LOGGING` em [scripts/cemiterio.gd](./scripts/cemiterio.gd).
- Servidor: `DEBUG_LOGGING` em [Servidor/websocket.py](./Servidor/websocket.py).

Com o diagnóstico ligado, o cliente registra estados do WebSocket, tipos de
mensagens, falhas de envio e código/motivo de fechamento. O servidor registra
conexões recusadas, clientes conectados/desconectados, mensagens inválidas,
falhas de broadcast e exceções.