-- Mapas dos GVVs (2026-10-22)
-- 1) Mapa público: mostra GVVs formados (conexões líder + casa) e GVVs antigos (cells).
--    Nunca devolve endereço nem coordenada real: cada GVV ganha um deslocamento aleatório
--    fixo (até 250 m) guardado numa tabela que ninguém lê. O site desenha um círculo de 300 m
--    em volta desse ponto, então a casa está sempre dentro do círculo, mas não no centro.
--    Único contato: WhatsApp do líder.
-- 2) Mapa ADM (gvv_map_overview): inclui os GVVs formados com todas as informações
--    (casa, endereço, líder, vice, telefones, membros, encontros em 90 dias).
BEGIN;

CREATE TABLE IF NOT EXISTS public.gvv_public_offsets (
  ref_id uuid PRIMARY KEY,
  dlat double precision NOT NULL,
  dlng double precision NOT NULL
);
ALTER TABLE public.gvv_public_offsets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.gvv_public_offsets FROM PUBLIC, anon, authenticated;

-- Deslocamento fixo por GVV: distância 80–250 m em direção aleatória.
CREATE OR REPLACE FUNCTION public.gvv_offset_of(p_id uuid, p_lat double precision) RETURNS public.gvv_public_offsets
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE o public.gvv_public_offsets; d double precision; a double precision;
BEGIN
  SELECT * INTO o FROM gvv_public_offsets WHERE ref_id = p_id;
  IF FOUND THEN RETURN o; END IF;
  d := 80 + random() * 170; a := random() * 2 * pi();
  INSERT INTO gvv_public_offsets(ref_id, dlat, dlng)
  VALUES (p_id, d * cos(a) / 111320.0, d * sin(a) / (111320.0 * cos(radians(p_lat))))
  ON CONFLICT (ref_id) DO NOTHING;
  SELECT * INTO o FROM gvv_public_offsets WHERE ref_id = p_id;
  RETURN o;
END $$;
REVOKE ALL ON FUNCTION public.gvv_offset_of(uuid, double precision) FROM PUBLIC, anon, authenticated;

-- Ponto real da casa de uma conexão (casa confirmada; senão aproximado pelo CEP).
CREATE OR REPLACE FUNCTION public.gvv_conn_point(h public.gvv_candidates) RETURNS double precision[]
LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT CASE
    WHEN (to_jsonb(h)->>'host_lat') IS NOT NULL AND (to_jsonb(h)->>'host_lat') <> '' THEN ARRAY[(to_jsonb(h)->>'host_lat')::float8, (to_jsonb(h)->>'host_lng')::float8]
    WHEN (to_jsonb(h)->>'home_lat') IS NOT NULL AND (to_jsonb(h)->>'home_lat') <> '' THEN ARRAY[(to_jsonb(h)->>'home_lat')::float8, (to_jsonb(h)->>'home_lng')::float8]
    WHEN (to_jsonb(h)->>'approx_lat') IS NOT NULL AND (to_jsonb(h)->>'approx_lat') <> '' THEN ARRAY[(to_jsonb(h)->>'approx_lat')::float8, (to_jsonb(h)->>'approx_lng')::float8]
  END;
$$;
REVOKE ALL ON FUNCTION public.gvv_conn_point(public.gvv_candidates) FROM PUBLIC, anon;

CREATE OR REPLACE FUNCTION public.gvv_public_map() RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $$
DECLARE out jsonb := '[]'::jsonb; r record; p double precision[]; o public.gvv_public_offsets;
BEGIN
  -- GVVs formados
  FOR r IN
    SELECT c.id, h AS host, l AS leader, to_jsonb(c) AS cj
    FROM gvv_connections c
    JOIN gvv_candidates h ON h.id = c.host_candidate_id
    JOIN gvv_candidates l ON l.id = c.leader_candidate_id
  LOOP
    p := gvv_conn_point(r.host);
    CONTINUE WHEN p IS NULL OR p[1] IS NULL OR p[2] IS NULL;
    o := gvv_offset_of(r.id, p[1]);
    out := out || jsonb_build_object(
      'id', r.id,
      'name', 'GVV ' || coalesce(nullif(btrim(to_jsonb(r.host)->>'neighborhood'), ''), 'Curitiba'),
      'audience', CASE coalesce(nullif(to_jsonb(r.host)->>'network', ''), 'misto') WHEN 'misto' THEN 'Mista' ELSE initcap(to_jsonb(r.host)->>'network') END,
      'weekday', r.cj->>'meeting_day', 'time', r.cj->>'meeting_time',
      'neighborhood', to_jsonb(r.host)->>'neighborhood',
      'leader_first', split_part(btrim(r.leader.name), ' ', 1),
      'whatsapp', regexp_replace(coalesce(to_jsonb(r.leader)->>'phone', ''), '\D', '', 'g'),
      'lat', round((p[1] + o.dlat)::numeric, 5), 'lng', round((p[2] + o.dlng)::numeric, 5),
      'radius', 300);
  END LOOP;
  -- GVVs antigos (cadastro de células) que não vieram de uma conexão
  FOR r IN
    SELECT c.* FROM cells c
    WHERE c.active = true AND c.lat IS NOT NULL AND c.lng IS NOT NULL
      AND (to_jsonb(c)->>'gvv_connection_id') IS NULL
  LOOP
    o := gvv_offset_of(r.id, r.lat::float8);
    out := out || jsonb_build_object(
      'id', r.id,
      'name', 'GVV ' || coalesce(nullif(btrim(r.neighborhood), ''), r.audience, 'Curitiba'),
      'audience', r.audience, 'weekday', r.weekday, 'time', r.time, 'neighborhood', r.neighborhood,
      'leader_first', NULL, 'whatsapp', NULL,
      'lat', round((r.lat::float8 + o.dlat)::numeric, 5), 'lng', round((r.lng::float8 + o.dlng)::numeric, 5),
      'radius', 300);
  END LOOP;
  RETURN out;
END $$;
REVOKE ALL ON FUNCTION public.gvv_public_map() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gvv_public_map() TO anon, authenticated;

-- Mapa ADM: células + GVVs formados com tudo. Detalhes pessoais só para a coordenação.
CREATE OR REPLACE FUNCTION public.gvv_map_overview() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE out jsonb; adm boolean;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles p WHERE p.user_id = auth.uid() AND p.active = true) THEN RETURN '[]'::jsonb; END IF;
  adm := public.my_role() IN ('super_admin','pastor','secretaria','administrativo','coordenador');
  SELECT coalesce(jsonb_agg(x ORDER BY x->>'name'), '[]'::jsonb) INTO out FROM (
    SELECT jsonb_build_object(
      'id', c.id, 'kind', 'cell', 'name', c.name, 'audience', c.audience,
      'weekday', c.weekday, 'time', c.time,
      'address', c.address, 'neighborhood', c.neighborhood, 'city', c.city,
      'lat', c.lat, 'lng', c.lng) AS x
    FROM cells c
    WHERE c.active = true AND (to_jsonb(c)->>'gvv_connection_id') IS NULL
    UNION ALL
    SELECT jsonb_build_object(
      'id', g.id, 'kind', 'gvv',
      'name', 'CASA ' || lpad(coalesce(to_jsonb(h)->>'house_no', ''), 2, '0') || ' · ' || split_part(btrim(h.name), ' ', 1),
      'network', coalesce(to_jsonb(h)->>'network', 'misto'),
      'audience', CASE coalesce(nullif(to_jsonb(h)->>'network', ''), 'misto') WHEN 'misto' THEN 'Mista' ELSE initcap(to_jsonb(h)->>'network') END,
      'weekday', to_jsonb(g)->>'meeting_day', 'time', to_jsonb(g)->>'meeting_time',
      'start_date', to_jsonb(g)->>'start_date', 'created_at', g.created_at,
      'neighborhood', to_jsonb(h)->>'neighborhood',
      'address', CASE WHEN adm THEN h.address END,
      'host_name', h.name, 'host_phone', CASE WHEN adm THEN to_jsonb(h)->>'phone' END,
      'leader_name', l.name, 'leader_phone', CASE WHEN adm THEN to_jsonb(l)->>'phone' END,
      'vice_name', v.name,
      'members', (SELECT count(*) FROM gvv_members m WHERE m.connection_id = g.id AND m.status = 'ativo'),
      'meetings_90', (SELECT count(*) FROM gvv_reports r WHERE r.connection_id = g.id AND r.happened AND r.meeting_date >= current_date - 90),
      'last_meeting', (SELECT max(r.meeting_date) FROM gvv_reports r WHERE r.connection_id = g.id AND r.happened),
      'visitors_90', (SELECT coalesce(sum(r.visitors), 0) FROM gvv_reports r WHERE r.connection_id = g.id AND r.meeting_date >= current_date - 90),
      'lat', (gvv_conn_point(h))[1], 'lng', (gvv_conn_point(h))[2]) AS x
    FROM gvv_connections g
    JOIN gvv_candidates h ON h.id = g.host_candidate_id
    JOIN gvv_candidates l ON l.id = g.leader_candidate_id
    LEFT JOIN gvv_candidates v ON v.id = (to_jsonb(g)->>'vice_candidate_id')::uuid
  ) s;
  RETURN out;
END $$;
REVOKE ALL ON FUNCTION public.gvv_map_overview() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gvv_map_overview() TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
