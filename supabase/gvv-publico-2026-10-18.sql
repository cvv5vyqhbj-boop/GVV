-- Sistema GVV — área pública (sem login)
--  1) Formulário "Faça parte de um GVV": qualquer pessoa envia; só a liderança lê.
--  2) Mapa público "GVVs perto de mim": nome genérico (GVV + bairro), público, dia, horário
--     e localização aproximada (~110 m). Nunca nome real, endereço, anfitrião, líder ou telefone.
-- Rodar uma vez no Supabase → SQL Editor.
BEGIN;

CREATE TABLE IF NOT EXISTS public.gvv_interests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  full_name text NOT NULL CHECK (char_length(btrim(full_name)) BETWEEN 3 AND 120),
  phone text NOT NULL CHECK (char_length(regexp_replace(phone, '\D', '', 'g')) BETWEEN 10 AND 13),
  age int CHECK (age BETWEEN 1 AND 120),
  marital_status text CHECK (marital_status IN ('solteiro','casado','divorciado','viuvo')),
  sex text CHECK (sex IN ('masculino','feminino')),
  is_member boolean,
  address text NOT NULL DEFAULT '' CHECK (char_length(address) <= 200),
  number text NOT NULL DEFAULT '' CHECK (char_length(number) <= 20),
  preferred_cell_id uuid REFERENCES public.cells(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'novo' CHECK (status IN ('novo','contatado','encaminhado','arquivado')),
  assigned_cell_id uuid REFERENCES public.cells(id) ON DELETE SET NULL,
  notes text NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS gvv_interests_created ON public.gvv_interests(created_at DESC);

ALTER TABLE public.gvv_interests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS gvv_interests_manage ON public.gvv_interests;
CREATE POLICY gvv_interests_manage ON public.gvv_interests FOR ALL TO authenticated
  USING (public.my_role() IN ('super_admin','pastor','secretaria','administrativo','coordenador','lider'))
  WITH CHECK (public.my_role() IN ('super_admin','pastor','secretaria','administrativo','coordenador','lider'));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.gvv_interests TO authenticated;
REVOKE ALL ON public.gvv_interests FROM anon;

-- Envio público: só pela função (anon não toca na tabela).
CREATE OR REPLACE FUNCTION public.gvv_submit_interest(
  p_full_name text, p_phone text, p_age int, p_marital_status text, p_sex text,
  p_is_member boolean, p_address text, p_number text, p_preferred_cell_id uuid DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE new_id uuid; digits text := regexp_replace(coalesce(p_phone,''), '\D', '', 'g');
BEGIN
  -- Mesmo telefone em menos de 10 minutos: não duplica.
  SELECT id INTO new_id FROM gvv_interests
   WHERE regexp_replace(phone, '\D', '', 'g') = digits AND created_at > now() - interval '10 minutes'
   LIMIT 1;
  IF new_id IS NOT NULL THEN RETURN new_id; END IF;
  INSERT INTO gvv_interests (full_name, phone, age, marital_status, sex, is_member, address, number, preferred_cell_id)
  VALUES (btrim(p_full_name), btrim(p_phone), p_age, p_marital_status, p_sex, p_is_member,
          btrim(coalesce(p_address,'')), btrim(coalesce(p_number,'')),
          (SELECT id FROM cells WHERE id = p_preferred_cell_id AND active = true))
  RETURNING id INTO new_id;
  RETURN new_id;
END $$;
REVOKE ALL ON FUNCTION public.gvv_submit_interest(text,text,int,text,text,boolean,text,text,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gvv_submit_interest(text,text,int,text,text,boolean,text,text,uuid) TO anon, authenticated;

-- Mapa público: sem endereço, sem anfitrião, coordenada arredondada.
CREATE OR REPLACE FUNCTION public.gvv_public_map() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    -- Nome genérico: o nome real costuma levar o nome do anfitrião.
    'id', c.id, 'name', 'GVV ' || coalesce(nullif(btrim(c.neighborhood), ''), c.audience, 'Curitiba'), 'audience', c.audience,
    'weekday', c.weekday, 'time', c.time,
    'neighborhood', c.neighborhood, 'city', c.city,
    'lat', round(c.lat::numeric, 3), 'lng', round(c.lng::numeric, 3)
  ) ORDER BY c.name), '[]'::jsonb)
  FROM public.cells c
  WHERE c.active = true AND c.lat IS NOT NULL AND c.lng IS NOT NULL;
$$;
REVOKE ALL ON FUNCTION public.gvv_public_map() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gvv_public_map() TO anon, authenticated;

COMMIT;
