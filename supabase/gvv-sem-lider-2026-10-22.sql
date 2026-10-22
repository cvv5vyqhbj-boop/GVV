-- GVV sem líder e mudar pessoa de GVV (2026-10-22). Rodar no SQL Editor.
--  · um GVV pode ficar sem líder (a casa continua; escolha outro depois);
--  · gvv_release_candidate tira a pessoa do GVV onde ela é líder ou vice, para poder ir para outro;
--  · os mapas aceitam GVV sem líder.
BEGIN;
ALTER TABLE public.gvv_connections ALTER COLUMN leader_candidate_id DROP NOT NULL;

CREATE OR REPLACE FUNCTION public.gvv_release_candidate(p_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE c gvv_connections;
BEGIN
  IF public.my_role() NOT IN ('super_admin','pastor','secretaria','administrativo','coordenador') THEN
    RAISE EXCEPTION 'Sem permissão.';
  END IF;
  FOR c IN SELECT * FROM gvv_connections WHERE leader_candidate_id = p_id OR (to_jsonb(gvv_connections)->>'vice_candidate_id')::uuid = p_id LOOP
    IF c.host_candidate_id = p_id THEN
      RAISE EXCEPTION 'Esta pessoa é a casa de um GVV. Desfaça aquele GVV antes de mudá-la.';
    END IF;
    IF c.leader_candidate_id = p_id THEN UPDATE gvv_connections SET leader_candidate_id = NULL WHERE id = c.id; END IF;
    IF (to_jsonb(c)->>'vice_candidate_id')::uuid = p_id THEN UPDATE gvv_connections SET vice_candidate_id = NULL WHERE id = c.id; END IF;
  END LOOP;
  DELETE FROM gvv_connection_people WHERE candidate_id = p_id
    AND NOT EXISTS (SELECT 1 FROM gvv_connections WHERE host_candidate_id = p_id);
END $$;
REVOKE ALL ON FUNCTION public.gvv_release_candidate(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gvv_release_candidate(uuid) TO authenticated;

-- Trocar ou TIRAR o líder (p_leader NULL = GVV fica sem líder)
CREATE OR REPLACE FUNCTION public.gvv_set_leader(p_conn uuid, p_leader uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE c gvv_connections; l gvv_candidates;
BEGIN
  IF public.my_role() NOT IN ('super_admin','pastor','secretaria','administrativo','coordenador') THEN
    RAISE EXCEPTION 'Sem permissão para trocar o líder.';
  END IF;
  SELECT * INTO c FROM gvv_connections WHERE id = p_conn FOR UPDATE;
  IF c.id IS NULL THEN RAISE EXCEPTION 'GVV não encontrado.'; END IF;
  IF p_leader IS NOT DISTINCT FROM c.leader_candidate_id THEN RETURN; END IF;
  IF p_leader IS NOT NULL THEN
    SELECT * INTO l FROM gvv_candidates WHERE id = p_leader;
    IF l.id IS NULL OR l.kind NOT IN ('leader','both') OR l.leader_status <> 'approved' THEN
      RAISE EXCEPTION 'O líder precisa ser um líder aprovado.';
    END IF;
    IF p_leader <> c.host_candidate_id AND EXISTS (SELECT 1 FROM gvv_connection_people WHERE candidate_id = p_leader AND connection_id <> c.id) THEN
      RAISE EXCEPTION 'Este líder já está em outro GVV.';
    END IF;
    IF p_leader = (to_jsonb(c)->>'vice_candidate_id')::uuid THEN
      UPDATE gvv_connections SET vice_candidate_id = NULL WHERE id = c.id;
    END IF;
  END IF;
  IF c.leader_candidate_id IS NOT NULL AND c.leader_candidate_id <> c.host_candidate_id THEN
    DELETE FROM gvv_connection_people WHERE candidate_id = c.leader_candidate_id AND connection_id = c.id;
  END IF;
  IF p_leader IS NOT NULL AND p_leader <> c.host_candidate_id THEN
    INSERT INTO gvv_connection_people(candidate_id, connection_id) VALUES (p_leader, c.id) ON CONFLICT (candidate_id) DO NOTHING;
  END IF;
  UPDATE gvv_connections SET leader_candidate_id = p_leader WHERE id = c.id;
END $$;
REVOKE ALL ON FUNCTION public.gvv_set_leader(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gvv_set_leader(uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.gvv_public_map() RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $$
DECLARE out jsonb := '[]'::jsonb; r record; p double precision[]; o public.gvv_public_offsets;
BEGIN
  -- GVVs formados
  FOR r IN
    SELECT c.id, h AS host, l AS leader, to_jsonb(c) AS cj
    FROM gvv_connections c
    JOIN gvv_candidates h ON h.id = c.host_candidate_id
    LEFT JOIN gvv_candidates l ON l.id = c.leader_candidate_id
  LOOP
    p := gvv_conn_point(r.host);
    CONTINUE WHEN p IS NULL OR p[1] IS NULL OR p[2] IS NULL;
    o := gvv_offset_of(r.id, p[1]);
    out := out || jsonb_build_object(
      'id', r.id,
      'name', 'GVV ' || lpad(coalesce(to_jsonb(r.host)->>'house_no', '?'), 2, '0') || ' · ' || (CASE coalesce(nullif(to_jsonb(r.host)->>'network', ''), 'misto') WHEN 'misto' THEN 'Misto' WHEN 'jovens' THEN 'Jovens' WHEN 'adolescentes' THEN 'Adolescentes' WHEN 'juniores' THEN 'Juniores' ELSE 'Misto' END),
      'audience', CASE coalesce(nullif(to_jsonb(r.host)->>'network', ''), 'misto') WHEN 'misto' THEN 'Mista' ELSE initcap(to_jsonb(r.host)->>'network') END,
      'weekday', r.cj->>'meeting_day', 'time', r.cj->>'meeting_time',
      'neighborhood', to_jsonb(r.host)->>'neighborhood',
      'leader_first', split_part(btrim(to_jsonb(r.leader)->>'name'), ' ', 1),
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
      'gvv_id', (CASE coalesce(to_jsonb(h)->>'network', 'misto') WHEN 'jovens' THEN 'JOVENS' WHEN 'adolescentes' THEN 'ADOL' WHEN 'juniores' THEN 'JUNIOR' ELSE 'MISTO' END)
        || ' ' || lpad(coalesce(to_jsonb(h)->>'network_no', '?'), 2, '0') || ' · CASA ' || lpad(coalesce(to_jsonb(h)->>'house_no', '?'), 2, '0'),
      'name', (CASE coalesce(to_jsonb(h)->>'network', 'misto') WHEN 'jovens' THEN 'JOVENS' WHEN 'adolescentes' THEN 'ADOL' WHEN 'juniores' THEN 'JUNIOR' ELSE 'MISTO' END)
        || ' ' || lpad(coalesce(to_jsonb(h)->>'network_no', '?'), 2, '0') || ' · CASA ' || lpad(coalesce(to_jsonb(h)->>'house_no', '?'), 2, '0') || ' · ' || split_part(btrim(h.name), ' ', 1),
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
      'conversions', (SELECT coalesce(sum((to_jsonb(r)->>'conversions')::int), 0) FROM gvv_reports r WHERE r.connection_id = g.id),
      'baptisms', (SELECT coalesce(sum(r.baptisms), 0) FROM gvv_reports r WHERE r.connection_id = g.id),
      'visitors_90', (SELECT coalesce(sum(r.visitors), 0) FROM gvv_reports r WHERE r.connection_id = g.id AND r.meeting_date >= current_date - 90),
      'lat', (gvv_conn_point(h))[1], 'lng', (gvv_conn_point(h))[2]) AS x
    FROM gvv_connections g
    JOIN gvv_candidates h ON h.id = g.host_candidate_id
    LEFT JOIN gvv_candidates l ON l.id = g.leader_candidate_id
    LEFT JOIN gvv_candidates v ON v.id = (to_jsonb(g)->>'vice_candidate_id')::uuid
  ) s;
  RETURN out;
END $$;
REVOKE ALL ON FUNCTION public.gvv_map_overview() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gvv_map_overview() TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
