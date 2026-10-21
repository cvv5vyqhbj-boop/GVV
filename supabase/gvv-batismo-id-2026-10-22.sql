-- GVV (2026-10-22, parte 2) · rodar DEPOIS de gvv-mapas-2026-10-22.sql
-- Relatório do líder ganha "optaram pelo batismo" e o mapa ADM passa a mostrar o ID do GVV
-- (rede + número na rede + casa, ex.: JOVENS 03 · CASA 12), aceitaram Jesus e batismos.
BEGIN;
ALTER TABLE public.gvv_reports ADD COLUMN IF NOT EXISTS conversions int NOT NULL DEFAULT 0;
ALTER TABLE public.gvv_reports ADD COLUMN IF NOT EXISTS conversion_names text NOT NULL DEFAULT '';
ALTER TABLE public.gvv_reports ADD COLUMN IF NOT EXISTS baptisms int NOT NULL DEFAULT 0 CHECK (baptisms BETWEEN 0 AND 200);
ALTER TABLE public.gvv_reports ADD COLUMN IF NOT EXISTS baptism_names text NOT NULL DEFAULT '';

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
    JOIN gvv_candidates l ON l.id = g.leader_candidate_id
    LEFT JOIN gvv_candidates v ON v.id = (to_jsonb(g)->>'vice_candidate_id')::uuid
  ) s;
  RETURN out;
END $$;
REVOKE ALL ON FUNCTION public.gvv_map_overview() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gvv_map_overview() TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
