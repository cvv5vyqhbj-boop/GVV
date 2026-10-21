-- GVVs de Juniores (lista de 22/10/2026). Rodar no Supabase → SQL Editor.
-- Cria casa (anfitrião) + líder júnior, já aprovados, e forma o GVV com dia, horário e responsável.
-- GVV 1 (Valéria/Vitória) e GVV 3 (Vanessa/Murilo) aproveitam os cadastros que já existiam.
-- Pode rodar de novo: não duplica.
BEGIN;

DO $$
DECLARE
  g record; h uuid; l uuid; conn uuid;
BEGIN
  FOR g IN SELECT * FROM (VALUES
    (1, 'Valéria',  'Vitória (Júnior)',   'Boqueirão',               'Segunda', '19:30', 'Responsável: Clarice',            '%vitoria terra rosa%'),
    (2, 'Glaucia',  'Isabela (Júnior)',   'Xaxim',                   'Segunda', '19:00', 'Responsável: Junyele e Robson',   NULL),
    (3, 'Vanessa',  'Murilo (Júnior)',    'Uberaba',                 'Quarta',  '19:00', 'Responsável: Clarice',            'murilo harteskoff%'),
    (4, 'Aline',    'Alice (Júnior)',     'Boqueirão',               'Quarta',  '19:30', 'Responsável: Aline',              NULL),
    (5, 'Josi',     'Isabel (Júnior)',    'Alto Boqueirão',          'Quinta',  '19:30', 'Responsável: Lisi e Vinicius',    NULL),
    (6, 'Crisalba', 'Arthur (Júnior)',    'Boqueirão',               'Sexta',   '19:30', 'Responsável: Fer e Eliel',        NULL),
    (7, 'Quesia',   'Gabriele (Júnior)',  'São José dos Pinhais',    'Sábado',  '15:00', 'Responsável: Quesia',             NULL),
    (8, 'Vinicius', 'Theodoro (Júnior)',  'Água Verde',              'Sábado',  '15:00', 'Responsável: Fer e Eliel',        NULL)
  ) AS t(n, host, leader, bairro, dia, hora, resp, existente)
  LOOP
    h := NULL; l := NULL;
    -- Casa: usa o cadastro antigo quando existe (ele já é líder + anfitrião da própria casa)
    IF g.existente IS NOT NULL THEN
      SELECT id INTO h FROM public.gvv_candidates WHERE lower(name) LIKE g.existente ORDER BY created_at NULLS LAST LIMIT 1;
      IF h IS NOT NULL THEN
        UPDATE public.gvv_candidates SET network = 'juniores', audience = 'Juniores', leader_status = 'approved', host_status = 'approved',
               days = g.dia, availability = g.dia || ' · Noite' WHERE id = h;
        l := h;
      END IF;
    END IF;
    IF h IS NULL THEN
      INSERT INTO public.gvv_candidates (import_key, name, kind, network, audience, leader_status, host_status, address, neighborhood, city, days, availability, origin_list)
      VALUES ('jun-casa-' || g.n, g.host, 'host', 'juniores', 'Juniores', 'pending', 'approved',
              g.bairro || CASE WHEN g.bairro = 'São José dos Pinhais' THEN '' ELSE ', Curitiba' END,
              CASE WHEN g.bairro = 'São José dos Pinhais' THEN '' ELSE g.bairro END,
              CASE WHEN g.bairro = 'São José dos Pinhais' THEN 'São José dos Pinhais' ELSE 'Curitiba' END,
              g.dia, g.dia || ' · ' || g.hora, 'GVVs Juniores (lista)')
      ON CONFLICT (import_key) DO UPDATE SET name = EXCLUDED.name
      RETURNING id INTO h;
    END IF;
    IF l IS NULL THEN
      INSERT INTO public.gvv_candidates (import_key, name, kind, network, audience, leader_status, host_status, home_address, neighborhood, city, origin_list)
      VALUES ('jun-lider-' || g.n, g.leader, 'leader', 'juniores', 'Juniores', 'approved', 'pending',
              g.bairro, CASE WHEN g.bairro = 'São José dos Pinhais' THEN '' ELSE g.bairro END,
              CASE WHEN g.bairro = 'São José dos Pinhais' THEN 'São José dos Pinhais' ELSE 'Curitiba' END, 'GVVs Juniores (lista)')
      ON CONFLICT (import_key) DO UPDATE SET name = EXCLUDED.name
      RETURNING id INTO l;
    END IF;

    -- Forma o GVV se a casa ainda não estiver em outro
    IF NOT EXISTS (SELECT 1 FROM public.gvv_connection_people WHERE candidate_id IN (h, l)) THEN
      INSERT INTO public.gvv_connections (leader_candidate_id, host_candidate_id, notes, meeting_day, meeting_time)
      VALUES (l, h, g.resp, g.dia, g.hora) RETURNING id INTO conn;
      INSERT INTO public.gvv_connection_people (candidate_id, connection_id) SELECT DISTINCT x, conn FROM unnest(ARRAY[h, l]) x;
    ELSE
      UPDATE public.gvv_connections SET notes = g.resp, meeting_day = g.dia, meeting_time = g.hora
       WHERE host_candidate_id = h;
    END IF;
  END LOOP;
END $$;

COMMIT;

-- Conferência: os 8 GVVs de Juniores
SELECT h.house_no AS casa, h.name AS anfitriao, l.name AS lider, c.meeting_day AS dia, c.meeting_time AS hora, c.notes AS responsavel
FROM public.gvv_connections c
JOIN public.gvv_candidates h ON h.id = c.host_candidate_id
JOIN public.gvv_candidates l ON l.id = c.leader_candidate_id
WHERE h.network = 'juniores' ORDER BY h.house_no;
