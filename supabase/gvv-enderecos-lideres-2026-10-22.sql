-- Endereços certos dos líderes (lista "Líderes GVV", 22/10/2026). Rodar no SQL Editor.
-- Atualiza endereço e ponto no mapa de cada líder. Só líder → endereço residencial; líder + anfitrião → endereço da casa.
-- A tabela do final mostra quem foi encontrado (achados = 0 → o nome não bateu com o sistema, me avise).
BEGIN;
CREATE TEMP TABLE lista_lideres (nome text, p1 text, p2 text, endereco text, bairro text, cidade text, lat float8, lng float8, ponto text) ON COMMIT DROP;
INSERT INTO lista_lideres VALUES
  ('Ana Caroline', 'ana', 'caroline', 'Rua Amazonas, 642, Água Verde, Curitiba', 'Água Verde', 'Curitiba', -25.4654655, -49.2833456, 'número'),
  ('Andreia de Quadros', 'andr', 'quadros', 'Travessa Palotina 601, Casa 16, Estados, Fazenda Rio Grande', 'Estados', 'Fazenda Rio Grande', -25.6717747, -49.336651, 'número'),
  ('Bruno César Meira', 'brun', 'meira', 'Rua Professor José Nogueira dos Santos, 1476, Boqueirão, Curitiba', 'Boqueirão', 'Curitiba', -25.4864132, -49.2588561, 'número'),
  ('Carlos Antônio Araújo', 'carl', 'araujo', 'Travessa Rafael Francisco Greca, 173 Ap 117, Água Verde, Curitiba', 'Água Verde', 'Curitiba', -25.4556496, -49.286578, 'número'),
  ('Cleiton Leandro', 'clei', 'leandro', 'Rua Luiz Carlos de Oliveira, 372, Xaxim, Curitiba', 'Xaxim', 'Curitiba', -25.5256797, -49.2647432, 'número'),
  ('Cosme Luiz Valeriote', 'cosm', 'valeriote', 'Rua Professora Magali Aparecida Pampuch 33 - 207, Pedro Moro, São José dos Pinhais', 'Pedro Moro', 'São José dos Pinhais', -25.554682, -49.1982826, 'número'),
  ('Daniel Spitale', 'dani', 'spitale', 'Avenida Cândido de Abreu, 660 - 1904, Centro Cívico, Curitiba', 'Centro Cívico', 'Curitiba', -25.4183667, -49.2683191, 'número'),
  ('David Carlos', 'davi', 'carlos', 'Rua Hugo Zen, 300 Bl 3 Ap 304, Colônia Rio Grande, São José dos Pinhais', 'Colônia Rio Grande', 'São José dos Pinhais', -25.557067, -49.2214785, 'número'),
  ('Elias Ramos', 'elia', 'ramos', 'Rua Antenor José Tedeschi, 264 casa 1, Cajuru, Curitiba', 'Cajuru', 'Curitiba', -25.4561635, -49.2009732, 'número'),
  ('Esdras de Ordelas', 'esdr', 'ordelas', 'Rua Abóbora 76 - Cond. Green Valley II, Uberaba, Curitiba', 'Uberaba', 'Curitiba', -25.4800691, -49.2101464, 'número'),
  ('Ezequias Firmino', 'ezeq', 'firmino', 'Rua Ilha Bella, 141, Cidade Industrial, Curitiba', 'Cidade Industrial', 'Curitiba', -25.497993, -49.334522, 'bairro'),
  ('Joacyr Juventino', 'joac', 'juventino', 'Rua Professor Oscar Martins Gomes, 141, Xaxim, Curitiba', 'Xaxim', 'Curitiba', -25.5083592, -49.2656024, 'número'),
  ('Kaick Hyan', 'kai', 'hyan', 'Rua Franz Kroeker, 581, Xaxim, Curitiba', 'Xaxim', 'Curitiba', -25.5237358, -49.2665584, 'número'),
  ('Kelly Teixeira da Silva', 'kell', 'silva', 'Rua Nova Aurora, 1710, Sítio Cercado, Curitiba', 'Sítio Cercado', 'Curitiba', -25.5436797, -49.2633437, 'número'),
  ('Leandro da Silva Alves', 'lean', 'alves', 'Rua Professor José Maurício Higgins, 1185, Boqueirão, Curitiba', 'Boqueirão', 'Curitiba', -25.4943121, -49.2418737, 'número'),
  ('Luan Santos', 'luan', 'santos', 'Rua Salomao Elias Feder, 500, Uberaba, Curitiba', 'Uberaba', 'Curitiba', -25.4859721, -49.2325666, 'número'),
  ('Michael Rosa', 'mich', 'rosa', 'Rua Lothario Boutin, 220 Bl 19 Ap 101, Pinheirinho, Curitiba', 'Pinheirinho', 'Curitiba', -25.5093357, -49.291816, 'número'),
  ('Oseias Ferreira', 'ose%', 'ferreira', 'Rua Vereador Narciso Mendes, 34 AP 303, Cidade Jardim, São José dos Pinhais', 'Cidade Jardim', 'São José dos Pinhais', -25.5159728, -49.2022512, 'número'),
  ('Raquel Cardoso', 'raqu', 'cardoso', 'Travessa Silvio Izair Ferro, 300, Cajuru, Curitiba', 'Cajuru', 'Curitiba', -25.4602914, -49.1985437, 'número'),
  ('Sergio Macuco', 'serg', 'macuco', 'Rua Lothario Boutin, 111 Bl 01 Ap 31, Pinheirinho, Curitiba', 'Pinheirinho', 'Curitiba', -25.5092123, -49.2931021, 'número'),
  ('Tiago Daniel dos Santos', 'tiag', 'santos', 'Boqueirão, Curitiba', 'Boqueirão', 'Curitiba', -25.500728, -49.2411054, 'bairro'),
  ('Victor Hugo', 'vict', 'hugo', 'Rua Capitão Benjamin Claudino Ferreira, 1332, Centro, São José dos Pinhais', 'Centro', 'São José dos Pinhais', -25.5338713, -49.2034065, 'bairro'),
  ('Yasmim Gabrielle', 'yasmi', 'gabriel', 'Rua Jair Coelho, 330 Bl 09 Ap 32, Cidade Industrial, Curitiba', 'Cidade Industrial', 'Curitiba', -25.4937486, -49.3489436, 'número'),
  ('Cledson Lobo', 'cled', 'lobo', 'Rua Padre Dehon, 1119, Hauer, Curitiba', 'Hauer', 'Curitiba', -25.4856755, -49.2548002, 'número');

CREATE TEMP TABLE achados ON COMMIT DROP AS
SELECT l.nome, c.id, c.name, c.kind
FROM lista_lideres l
JOIN gvv_candidates c ON c.kind IN ('leader','both')
 AND translate(lower(c.name), 'áàãâéêíóôõúüç', 'aaaaeeiooouuc') LIKE l.p1 || '%'
 AND translate(lower(c.name), 'áàãâéêíóôõúüç', 'aaaaeeiooouuc') LIKE '%' || l.p2 || '%';

UPDATE gvv_candidates c SET home_address = l.endereco, neighborhood = l.bairro, city = l.cidade,
       home_lat = coalesce(l.lat, c.home_lat), home_lng = coalesce(l.lng, c.home_lng),
       approx_lat = coalesce(l.lat, c.approx_lat), approx_lng = coalesce(l.lng, c.approx_lng)
FROM achados a JOIN lista_lideres l ON l.nome = a.nome
WHERE c.id = a.id AND c.kind = 'leader';

UPDATE gvv_candidates c SET address = l.endereco, neighborhood = l.bairro, city = l.cidade,
       host_lat = coalesce(l.lat, c.host_lat), host_lng = coalesce(l.lng, c.host_lng),
       approx_lat = coalesce(l.lat, c.approx_lat), approx_lng = coalesce(l.lng, c.approx_lng)
FROM achados a JOIN lista_lideres l ON l.nome = a.nome
WHERE c.id = a.id AND c.kind = 'both';

-- Conferência
SELECT l.nome AS na_lista, count(a.id) AS achados, string_agg(a.name || ' (' || a.kind || ')', '; ') AS no_sistema, l.ponto AS ponto_no_mapa
FROM lista_lideres l LEFT JOIN achados a ON a.nome = l.nome
GROUP BY l.nome, l.ponto ORDER BY count(a.id), l.nome;
COMMIT;
