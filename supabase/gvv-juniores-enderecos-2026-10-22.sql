-- Endereços dos GVVs de Juniores (22/10/2026). Rodar no Supabase → SQL Editor.
-- O endereço é onde o GVV acontece: grava na casa (anfitrião) e no líder júnior.
-- Coordenadas conferidas no OpenStreetMap; o mapa público continua mostrando só a área de 300 m.
BEGIN;
-- A casa de um GVV formado pode mudar de endereço (mudança, correção) sem desfazer o GVV.
CREATE OR REPLACE FUNCTION public.gvv_guard_connected_candidate() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $g$
BEGIN
 IF EXISTS(SELECT 1 FROM public.gvv_connections WHERE leader_candidate_id=OLD.id) AND
 (NEW.kind NOT IN ('leader','both') OR NEW.leader_status<>'approved') THEN
 RAISE EXCEPTION 'Desfaça a conexão antes de alterar a aprovação da liderança.'; END IF;
 IF EXISTS(SELECT 1 FROM public.gvv_connections WHERE host_candidate_id=OLD.id) AND
 (NEW.kind NOT IN ('host','both') OR NEW.host_status<>'approved') THEN
 RAISE EXCEPTION 'Desfaça a conexão antes de alterar a casa ou sua aprovação.'; END IF;
 IF (NEW.home_lat IS NOT NULL AND abs(NEW.home_lat)>90) OR (NEW.host_lat IS NOT NULL AND abs(NEW.host_lat)>90) OR
 (NEW.home_lng IS NOT NULL AND abs(NEW.home_lng)>180) OR (NEW.host_lng IS NOT NULL AND abs(NEW.host_lng)>180) OR
 (NEW.capacity IS NOT NULL AND NEW.capacity<1) THEN RAISE EXCEPTION 'Confira coordenadas e capacidade.'; END IF;
 RETURN NEW;
END $g$;
DO $$
DECLARE g record; c record; n int := 0;
BEGIN
  FOR g IN SELECT * FROM (VALUES
    ('alice%',    'Rua Isaías Régis de Miranda, 1739, casa 01, Boqueirão, Curitiba',            'Boqueirão',    'Curitiba',             -25.4876567, -49.2496191),
    ('isabela%',  'Rua David Tows, 1299, casa 63, Xaxim, Curitiba',                            'Xaxim',        'Curitiba',             -25.5236887, -49.2594478),
    ('murilo%',   'Rua Major Inácio Gomes da Costa, 570, Uberaba, Curitiba',                   'Uberaba',      'Curitiba',             -25.4784438, -49.2284199),
    ('gabriel%',  'Rua Expedicionário Joaquim Lima de Amorim, Itália, São José dos Pinhais',   'Itália',       'São José dos Pinhais', -25.5657132, -49.1953125),
    ('vit%',      'Rua Joaquim Macan, 187, Boqueirão, Curitiba',                               'Boqueirão',    'Curitiba',             -25.5025544, -49.2552581),
    ('arthur%',   'Rua Irene Magnuskei Kolakowski, 719, Boqueirão, Curitiba',                  'Boqueirão',    'Curitiba',             NULL,        NULL),
    ('theodoro%', 'Rua Engenheiro Arthur Bettes, 75, Portão, Curitiba',                        'Portão',       'Curitiba',             -25.4679019, -49.2908417)
  ) AS t(lider, endereco, bairro, cidade, lat, lng)
  LOOP
    FOR c IN
      SELECT g2.host_candidate_id AS h, g2.leader_candidate_id AS l
      FROM gvv_connections g2
      JOIN gvv_candidates lc ON lc.id = g2.leader_candidate_id
      JOIN gvv_candidates hc ON hc.id = g2.host_candidate_id
      WHERE hc.network = 'juniores' AND translate(lower(lc.name), 'áàãâéêíóôõúç', 'aaaaeeiooouc') LIKE g.lider
    LOOP
      UPDATE gvv_candidates SET address = g.endereco, neighborhood = g.bairro, city = g.cidade,
             host_lat = coalesce(g.lat, host_lat), host_lng = coalesce(g.lng, host_lng),
             approx_lat = coalesce(g.lat, approx_lat), approx_lng = coalesce(g.lng, approx_lng)
       WHERE id = c.h;
      IF c.l <> c.h THEN
        UPDATE gvv_candidates SET home_address = g.endereco, neighborhood = g.bairro, city = g.cidade,
               approx_lat = coalesce(g.lat, approx_lat), approx_lng = coalesce(g.lng, approx_lng)
         WHERE id = c.l;
      END IF;
      n := n + 1;
    END LOOP;
  END LOOP;
  RAISE NOTICE '% GVV(s) de Juniores atualizados', n;
END $$;
COMMIT;

-- Conferência
SELECT h.house_no AS casa, l.name AS lider, h.address AS endereco, h.host_lat IS NOT NULL AS no_mapa
FROM gvv_connections c
JOIN gvv_candidates h ON h.id = c.host_candidate_id
JOIN gvv_candidates l ON l.id = c.leader_candidate_id
WHERE h.network = 'juniores' ORDER BY h.house_no;
