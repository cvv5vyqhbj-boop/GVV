-- Mapa para todos os usuários ativos, sem notas ou dados de acompanhamento.
BEGIN;
ALTER TABLE public.cells ADD COLUMN IF NOT EXISTS audience text
  CHECK (audience IN ('Mista','Adultos','Jovens','Adolescentes','Mulheres','Idosos'));
CREATE OR REPLACE FUNCTION public.gvv_map_overview() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'id', c.id, 'name', c.name, 'audience', c.audience,
  'weekday', c.weekday, 'time', c.time,
  'address', c.address, 'neighborhood', c.neighborhood, 'city', c.city,
  'lat', c.lat, 'lng', c.lng
 ) ORDER BY c.name), '[]'::jsonb)
 FROM public.cells c
 WHERE c.active = true AND EXISTS (
  SELECT 1 FROM public.profiles p WHERE p.user_id = auth.uid() AND p.active = true
 );
$$;
REVOKE ALL ON FUNCTION public.gvv_map_overview() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gvv_map_overview() TO authenticated;
COMMIT;
