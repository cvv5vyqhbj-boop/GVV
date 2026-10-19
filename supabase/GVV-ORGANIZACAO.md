# GVV — fluxo simplificado

A estrutura usa `gvv-candidatos.sql`, `gvv-organizacao.sql` e `gvv-mapa-geral.sql`.
Se essas migrações já foram aplicadas, esta revisão não exige SQL adicional.

## Uso

- **Rede GVV** abre com o mapa dos grupos ativos e filtro por público. Indicadores de pessoas, avaliações, casas, líderes, conexões, saúde e relatórios
  ficam visíveis na primeira aba, com atalhos para cada etapa.
- **Formar novo GVV → Avaliar** separa os três perfis. Abra uma pessoa, confira
  seus dados e avance para aprovar liderança e/ou casa separadamente.
- **Conectar pelo mapa** usa o mesmo fundo discreto do mapa geral e pontos pequenos:
  azul para líder, laranja para anfitrião e roxo para líder + anfitrião. Somente aprovados podem ser conectados. Selecione a
  casa e compare os líderes: distâncias conhecidas vêm primeiro, acompanhadas
  de dias em comum e público desejado. O traço indica distância em linha reta.
- Pontos confirmados são reaproveitados. Endereços sem coordenadas usam uma
  busca automática da rua pública, sem enviar nomes, telefones ou números de
  residência. Consultas são espaçadas e armazenadas em cache. O detalhe de cada ponto
  informa quando a localização é aproximada; distâncias correspondentes são estimativas.
  Pontos aproximados nunca são gravados como coordenadas confirmadas nem
  preenchidos automaticamente no cadastro de um GVV. Confira o número e marque
  o ponto exato para confirmar. Em Conferir endereços, todos os cadastros podem
  ser visualizados, independentemente da aprovação.
- **Criar GVV** permite informar o nome e selecionar líder e anfitrião aprovados antes de
  salvar a conexão e abrir o cadastro final. O cadastro do
  GVV recebe os dados conhecidos: público, capacidade, localização e um único
  dia em comum, quando houver. Confira nome e horário. O líder precisa de um
  usuário ativo vinculado para criar o GVV.

As aprovações e vínculos continuam validados no banco. Cada pessoa participa de
uma única conexão; uma conexão usada por um GVV não pode ser excluída.

O painel principal oferece **Adicionar GVV de teste** e **Remover testes**.
Os testes são identificados no nome e nas observações, com localização fictícia
e sem atribuir liderança ou casa a pessoas reais.

## Validação

JSX completo compilado. Fluxos testados em Chromium com dados fictícios, em
1450 px e 390 px: avaliação em duas etapas, seleção no mapa, ordenação por
proximidade, linha da dupla, informações em comum, revisão, gravação da conexão,
payload sem campos temporários e formulário com dados sugeridos. Página inicial
testada com mapa, exclusão de inativos, filtro por público e acesso à formação.

Referências de desenho:
- https://design-system.service.gov.uk/patterns/complete-multiple-tasks/
- https://www.nngroup.com/articles/progressive-disclosure/
