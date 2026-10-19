# Mapa das células

`map-style.json` adapta o estilo Liberty disponibilizado pelo OpenFreeMap:
https://tiles.openfreemap.org/styles/liberty

Integração: https://openfreemap.org/quick_start/

A paleta local usa fundo claro, ruas brancas, parques verdes e água azul.
Prédios e pontos de interesse aparecem progressivamente; rótulos priorizam
português e o nome local. Nomes de parques aparecem a partir do zoom 14.
Não há edifícios 3D. Atribuições OpenFreeMap / OpenMapTiles / OpenStreetMap
continuam visíveis no mapa. Pinos e relatórios continuam no Leaflet.

MapLibre GL 5.6.1 e a ponte Leaflet 0.1.1 são fixados via CDN. O service worker
não guarda tiles vetoriais. Sem suporte a WebGL, a tela oferece o mapa raster
de compatibilidade com aviso. Street View continua sendo um link externo.

## Hierarquia de zoom

- Cidade (até 13): vias principais, bairros, parques e água.
- Região (14–15): vias secundárias, nomes de parques e principais avenidas.
- Rua (16): malha local e nomes das ruas.
- Quarteirão (17–18): prédios, transporte, caminhos e referências principais.
- Próximo (19): detalhes das ruas; pontos comerciais continuam ocultos.

Ruas usam branco e contornos suaves, sem amarelo. Ícones são pequenos e
rótulos têm espaçamento para limitar colisões. Placas de rodovias e setas
de mão única ficam ocultas.

## Curitiba e região

A abertura enquadra a região metropolitana. A paleta clara destaca vegetação
em verde e rios/lagos em azul. Camadas genéricas de POIs ficam ocultas em
todos os níveis de zoom: sem lojas, restaurantes ou outros comércios.
Parques, cidades, bairros e transporte continuam com rótulos progressivos.

A igreja tem pino próprio, nome permanente e botão de foco, separado das
células e dos indicadores de saúde. Endereço público: Rua Coronel Luiz José
dos Santos, 2018, Boqueirão. Coordenadas conferidas no Google Maps em
06/10/2026: -25.4984057, -49.2477964.
https://www.google.com/maps/place/ADVEC+Curitiba/@-25.4984057,-49.2477964,17z/
