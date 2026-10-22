-- Cadastro público: autorização do pai/responsável para GVV de juniores e adolescentes (2026-10-22).
BEGIN;
ALTER TABLE public.gvv_candidates ADD COLUMN IF NOT EXISTS guardian_name text NOT NULL DEFAULT '';
ALTER TABLE public.gvv_candidates ADD COLUMN IF NOT EXISTS guardian_member boolean;
ALTER TABLE public.gvv_candidates ADD COLUMN IF NOT EXISTS guardian_agrees boolean;
CREATE OR REPLACE FUNCTION public.gvv_submit_candidate(p jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  k text := p->>'kind';
  nm text := btrim(coalesce(p->>'name',''));
  ph text := btrim(coalesce(p->>'phone',''));
  digits text := regexp_replace(coalesce(p->>'phone',''), '\D', '', 'g');
  net text := p->>'network';
  addr text := left(btrim(coalesce(p->>'address','')), 250);
  new_id uuid;
BEGIN
  IF k NOT IN ('leader','host','both') THEN RAISE EXCEPTION 'Escolha a função.'; END IF;
  IF char_length(nm) < 5 OR char_length(nm) > 120 THEN RAISE EXCEPTION 'Nome inválido.'; END IF;
  IF char_length(digits) NOT BETWEEN 10 AND 13 THEN RAISE EXCEPTION 'WhatsApp inválido.'; END IF;
  IF net IS NOT NULL AND net NOT IN ('misto','jovens','adolescentes','juniores') THEN net := NULL; END IF;
  IF k IN ('host','both') AND char_length(addr) < 5 THEN RAISE EXCEPTION 'Informe o endereço da residência.'; END IF;

  -- Mesmo WhatsApp em menos de 10 minutos: não duplica.
  SELECT id INTO new_id FROM gvv_candidates
   WHERE regexp_replace(phone, '\D', '', 'g') = digits AND created_at > now() - interval '10 minutes' LIMIT 1;
  IF new_id IS NOT NULL THEN RETURN new_id; END IF;

  INSERT INTO gvv_candidates (
    name, kind, leader_status, host_status, network,
    address, home_address, audience, availability, days, shifts, capacity, fits_15,
    phone, email, birth_date, sex, marital_status, member_since, residence_type,
    cep, neighborhood, city, reference_point, source_text, review_notes, origin_list,
    approx_lat, approx_lng)
  VALUES (
    nm, k, 'pending', 'pending', net,
    CASE WHEN k IN ('host','both') THEN addr ELSE '' END,
    CASE WHEN k = 'leader' THEN addr ELSE '' END,
    left(coalesce(p->>'audience',''), 120),
    left(coalesce(p->>'availability',''), 200),
    left(coalesce(p->>'days',''), 120), left(coalesce(p->>'shifts',''), 60),
    CASE WHEN k IN ('host','both') AND (p->>'fits_15') = 'true' THEN 15 ELSE NULL END,
    CASE WHEN k IN ('host','both') THEN (p->>'fits_15')::boolean ELSE NULL END,
    ph, left(lower(btrim(coalesce(p->>'email',''))), 120),
    CASE WHEN (p->>'birth_date') ~ '^\d{4}-\d{2}-\d{2}$' AND (p->>'birth_date')::date < current_date THEN (p->>'birth_date')::date ELSE NULL END,
    left(coalesce(p->>'sex',''), 20), left(coalesce(p->>'marital_status',''), 30),
    left(coalesce(p->>'member_since',''), 40), left(coalesce(p->>'residence_type',''), 30),
    left(coalesce(p->>'cep',''), 12), left(coalesce(p->>'neighborhood',''), 80), left(coalesce(p->>'city',''), 80),
    left(coalesce(p->>'reference_point',''), 150), left(coalesce(p->>'notes',''), 1000), '',
    'Formulário do site',
    CASE WHEN (p->>'lat') ~ '^-?\d+(\.\d+)?$' THEN (p->>'lat')::numeric ELSE NULL END,
    CASE WHEN (p->>'lng') ~ '^-?\d+(\.\d+)?$' THEN (p->>'lng')::numeric ELSE NULL END)
  RETURNING id INTO new_id;
  -- Juniores/Adolescentes: autorização do pai ou responsável
  IF nullif(btrim(coalesce(p->>'guardian_name','')), '') IS NOT NULL THEN
    UPDATE gvv_candidates SET guardian_name = left(btrim(p->>'guardian_name'), 120),
           guardian_member = CASE WHEN (p->>'guardian_member') IN ('true','false') THEN (p->>'guardian_member')::boolean END,
           guardian_agrees = CASE WHEN (p->>'guardian_agrees') IN ('true','false') THEN (p->>'guardian_agrees')::boolean END
     WHERE id = new_id;
  END IF;
  RETURN new_id;
END $$;
REVOKE ALL ON FUNCTION public.gvv_submit_candidate(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gvv_submit_candidate(jsonb) TO anon, authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;
