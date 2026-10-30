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

O servidor limita a sala a 40 conexões e não simula o jogo. Uma conexão só
entra na partida depois de informar um nome; o primeiro jogador ativo controla
a geração, a movimentação e o estado dos inimigos. A partida só começa quando
há pelo menos um jogador ativo.
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

O HUD também exibe a quantidade de inimigos vivos no mapa e o multiplicador
de dano. A cada 5 inimigos, o dano dos jogadores aumenta 25%; esses valores
podem ser ajustados pelas constantes `ENEMIES_PER_DAMAGE_STEP` e
`DAMAGE_MULTIPLIER_STEP` em `scripts/cemiterio.gd`.

Ao entrar, o jogador informa seu nome antes de aparecer no jogo. O nome é
exibido acima dos jogadores remotos, e os clientes também reproduzem a
animação de ataque dos demais jogadores.

O HUD exibe discretamente as últimas entradas, saídas e mortes dos jogadores
ativos.

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