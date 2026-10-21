-- Mapa público: nome do GVV igual ao cadastro (GVV 01 · Juniores).
BEGIN;
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
NOTIFY pgrst, 'reload schema';
COMMIT;
