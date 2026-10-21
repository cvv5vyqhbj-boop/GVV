-- Sistema GVV — vice-líder, membros do GVV, relatórios e login do líder (21/10/2026)
-- Rodar uma vez no Supabase → SQL Editor. Pode rodar de novo sem estragar.
--
-- Líder de GVV com login = perfil com role 'membro' + gvv_candidate_id (o cadastro dele).
-- Ele vê e edita só os GVVs onde é líder ou vice.
BEGIN;

-- 1) Vice-líder e dados do encontro no GVV
ALTER TABLE public.gvv_connections
  ADD COLUMN IF NOT EXISTS vice_candidate_id uuid REFERENCES public.gvv_candidates(id),
  ADD COLUMN IF NOT EXISTS meeting_day text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS meeting_time text NOT NULL DEFAULT '';
CREATE UNIQUE INDEX IF NOT EXISTS gvv_connections_vice_unique ON public.gvv_connections(vice_candidate_id) WHERE vice_candidate_id IS NOT NULL;

-- 2) Login do líder ligado ao cadastro
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS gvv_candidate_id uuid REFERENCES public.gvv_candidates(id) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION public.my_gvv_connections() RETURNS SETOF uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT c.id FROM gvv_connections c
  JOIN profiles p ON p.user_id = auth.uid() AND p.active AND p.gvv_candidate_id IS NOT NULL
  WHERE p.gvv_candidate_id IN (c.leader_candidate_id, c.vice_candidate_id, c.host_candidate_id)
$$;

CREATE OR REPLACE FUNCTION public.gvv_can_manage(p_conn uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.my_role() IN ('super_admin','pastor','secretaria','administrativo','coordenador')
      OR (public.my_role() = 'lider' AND EXISTS (SELECT 1 FROM gvv_connections c JOIN gvv_candidates h ON h.id = c.host_candidate_id
                                                 WHERE c.id = p_conn AND h.network = public.my_gvv_network()))
      OR p_conn IN (SELECT public.my_gvv_connections())
$$;

-- Líder vê o próprio GVV e as pessoas ligadas a ele
DROP POLICY IF EXISTS gvv_connections_leader_read ON public.gvv_connections;
CREATE POLICY gvv_connections_leader_read ON public.gvv_connections FOR SELECT TO authenticated
  USING (id IN (SELECT public.my_gvv_connections()));
DROP POLICY IF EXISTS gvv_candidates_leader_read ON public.gvv_candidates;
CREATE POLICY gvv_candidates_leader_read ON public.gvv_candidates FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM gvv_connections c WHERE c.id IN (SELECT public.my_gvv_connections())
                 AND gvv_candidates.id IN (c.leader_candidate_id, c.vice_candidate_id, c.host_candidate_id)));

-- Vice-líder, dia e horário (equipe ou líder do GVV)
CREATE OR REPLACE FUNCTION public.gvv_update_group(p_conn uuid, p_vice uuid, p_day text, p_time text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE c gvv_connections; v gvv_candidates;
BEGIN
  IF NOT public.gvv_can_manage(p_conn) OR public.my_role() = 'membro' AND p_vice IS DISTINCT FROM (SELECT vice_candidate_id FROM gvv_connections WHERE id = p_conn) THEN
    RAISE EXCEPTION 'Sem permissão para alterar este GVV.'; END IF;
  SELECT * INTO c FROM gvv_connections WHERE id = p_conn FOR UPDATE;
  IF c.id IS NULL THEN RAISE EXCEPTION 'GVV não encontrado.'; END IF;
  IF p_vice IS DISTINCT FROM c.vice_candidate_id THEN
    IF c.vice_candidate_id IS NOT NULL THEN DELETE FROM gvv_connection_people WHERE candidate_id = c.vice_candidate_id AND connection_id = c.id; END IF;
    IF p_vice IS NOT NULL THEN
      SELECT * INTO v FROM gvv_candidates WHERE id = p_vice;
      IF v.id IS NULL OR v.kind NOT IN ('leader','both') OR v.leader_status <> 'approved' THEN RAISE EXCEPTION 'O vice precisa ser um líder aprovado.'; END IF;
      IF p_vice IN (c.leader_candidate_id, c.host_candidate_id) THEN RAISE EXCEPTION 'O vice precisa ser outra pessoa.'; END IF;
      IF EXISTS (SELECT 1 FROM gvv_connection_people WHERE candidate_id = p_vice) THEN RAISE EXCEPTION 'Este líder já está em outro GVV.'; END IF;
      INSERT INTO gvv_connection_people(candidate_id, connection_id) VALUES (p_vice, c.id);
    END IF;
  END IF;
  UPDATE gvv_connections SET vice_candidate_id = p_vice, meeting_day = coalesce(p_day,''), meeting_time = coalesce(p_time,'') WHERE id = p_conn;
END $$;
REVOKE ALL ON FUNCTION public.gvv_update_group(uuid,uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gvv_update_group(uuid,uuid,text,text) TO authenticated;

-- 3) Membros do GVV (pessoas que participam)
CREATE TABLE IF NOT EXISTS public.gvv_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  connection_id uuid NOT NULL REFERENCES public.gvv_connections(id) ON DELETE CASCADE,
  interest_id uuid REFERENCES public.gvv_interests(id) ON DELETE SET NULL,
  full_name text NOT NULL CHECK (char_length(btrim(full_name)) BETWEEN 2 AND 120),
  phone text NOT NULL DEFAULT '',
  age int, sex text NOT NULL DEFAULT '',
  status text NOT NULL DEFAULT 'ativo' CHECK (status IN ('ativo','inativo')),
  joined_at date NOT NULL DEFAULT current_date,
  notes text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS gvv_members_conn ON public.gvv_members(connection_id);
CREATE UNIQUE INDEX IF NOT EXISTS gvv_members_interest_unique ON public.gvv_members(interest_id) WHERE interest_id IS NOT NULL;
ALTER TABLE public.gvv_members ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS gvv_members_manage ON public.gvv_members;
CREATE POLICY gvv_members_manage ON public.gvv_members FOR ALL TO authenticated
  USING (public.gvv_can_manage(connection_id)) WITH CHECK (public.gvv_can_manage(connection_id));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.gvv_members TO authenticated;
REVOKE ALL ON public.gvv_members FROM anon;

-- Interessada → membro do GVV (marca a interessada como encaminhada)
CREATE OR REPLACE FUNCTION public.gvv_add_interest(p_conn uuid, p_interest uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE i gvv_interests; m uuid;
BEGIN
  IF NOT public.gvv_can_manage(p_conn) THEN RAISE EXCEPTION 'Sem permissão para este GVV.'; END IF;
  SELECT * INTO i FROM gvv_interests WHERE id = p_interest;
  IF i.id IS NULL THEN RAISE EXCEPTION 'Interessado não encontrado.'; END IF;
  SELECT id INTO m FROM gvv_members WHERE interest_id = p_interest;
  IF m IS NOT NULL THEN
    UPDATE gvv_members SET connection_id = p_conn, status = 'ativo' WHERE id = m;
  ELSE
    INSERT INTO gvv_members(connection_id, interest_id, full_name, phone, age, sex)
    VALUES (p_conn, i.id, i.full_name, i.phone, i.age, coalesce(i.sex,'')) RETURNING id INTO m;
  END IF;
  UPDATE gvv_interests SET status = 'encaminhado' WHERE id = p_interest;
  RETURN m;
END $$;
REVOKE ALL ON FUNCTION public.gvv_add_interest(uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gvv_add_interest(uuid,uuid) TO authenticated;

-- Líder do GVV também pode ver os interessados ainda não encaminhados (para chamar para o grupo)
DROP POLICY IF EXISTS gvv_interests_leader_read ON public.gvv_interests;
CREATE POLICY gvv_interests_leader_read ON public.gvv_interests FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.my_gvv_connections()) AND status IN ('novo','contatado'));

-- 4) Relatório do encontro
CREATE TABLE IF NOT EXISTS public.gvv_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  connection_id uuid NOT NULL REFERENCES public.gvv_connections(id) ON DELETE CASCADE,
  meeting_date date NOT NULL,
  present_ids uuid[] NOT NULL DEFAULT '{}',
  visitors int NOT NULL DEFAULT 0 CHECK (visitors BETWEEN 0 AND 200),
  happened boolean NOT NULL DEFAULT true,
  notes text NOT NULL DEFAULT '',
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (connection_id, meeting_date)
);
ALTER TABLE public.gvv_reports ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS gvv_reports_manage ON public.gvv_reports;
CREATE POLICY gvv_reports_manage ON public.gvv_reports FOR ALL TO authenticated
  USING (public.gvv_can_manage(connection_id)) WITH CHECK (public.gvv_can_manage(connection_id));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.gvv_reports TO authenticated;
REVOKE ALL ON public.gvv_reports FROM anon;

-- 5) Quem é líder + anfitrião aprovado já forma um GVV (ele mesmo lidera na própria casa)
WITH novos AS (
  INSERT INTO public.gvv_connections(leader_candidate_id, host_candidate_id, notes)
  SELECT c.id, c.id, 'Líder + anfitrião (ele mesmo lidera)'
  FROM public.gvv_candidates c
  WHERE c.kind = 'both' AND c.leader_status = 'approved' AND c.host_status = 'approved'
    AND NOT EXISTS (SELECT 1 FROM public.gvv_connection_people p WHERE p.candidate_id = c.id)
  RETURNING id, leader_candidate_id
)
INSERT INTO public.gvv_connection_people(candidate_id, connection_id) SELECT leader_candidate_id, id FROM novos;

NOTIFY pgrst, 'reload schema';
COMMIT;
