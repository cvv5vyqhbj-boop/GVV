-- Sistema GVV — calendário, frequentantes, decisões e acesso do líder (21/10/2026)
-- Rodar uma vez no Supabase → SQL Editor. Não apaga nada. Pode rodar de novo.
-- Precisa ter rodado antes: gvv-membros-2026-10-21.sql e gvv-corrige-recursao-2026-10-21.sql
BEGIN;

-- Data de início do GVV (1º encontro = 15 dias depois, no dia escolhido; depois a cada 2 semanas)
ALTER TABLE public.gvv_connections ADD COLUMN IF NOT EXISTS start_date date;

-- Membro ou frequentante
ALTER TABLE public.gvv_members ADD COLUMN IF NOT EXISTS kind text NOT NULL DEFAULT 'membro';
DO $$ BEGIN
  ALTER TABLE public.gvv_members ADD CONSTRAINT gvv_members_kind_check CHECK (kind IN ('membro','frequentante'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Relatório: quem aceitou Jesus e pedidos de oração
ALTER TABLE public.gvv_reports
  ADD COLUMN IF NOT EXISTS conversions int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS conversion_names text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS prayer_requests text NOT NULL DEFAULT '';

-- Dados do GVV agora com data de início
DROP FUNCTION IF EXISTS public.gvv_update_group(uuid,uuid,text,text);
CREATE OR REPLACE FUNCTION public.gvv_update_group(p_conn uuid, p_vice uuid, p_day text, p_time text, p_start date DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE c gvv_connections; v gvv_candidates;
BEGIN
  IF NOT public.gvv_can_manage(p_conn) OR (public.my_role() = 'membro' AND p_vice IS DISTINCT FROM (SELECT vice_candidate_id FROM gvv_connections WHERE id = p_conn)) THEN
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
  UPDATE gvv_connections SET vice_candidate_id = p_vice, meeting_day = coalesce(p_day,''), meeting_time = coalesce(p_time,''),
         start_date = coalesce(p_start, start_date) WHERE id = p_conn;
END $$;
REVOKE ALL ON FUNCTION public.gvv_update_group(uuid,uuid,text,text,date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gvv_update_group(uuid,uuid,text,text,date) TO authenticated;

-- Acesso do líder: o ADM cria a conta (WhatsApp + PIN) e liga ao cadastro dele.
-- Encontra o perfil recém-criado pelo e-mail técnico e libera como "Líder de GVV".
CREATE OR REPLACE FUNCTION public.gvv_link_leader_login(p_email text, p_candidate uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.my_role() NOT IN ('super_admin','pastor') THEN RAISE EXCEPTION 'Só o ADM cria acesso de líder.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM gvv_candidates WHERE id = p_candidate AND kind IN ('leader','both')) THEN RAISE EXCEPTION 'Cadastro de líder não encontrado.'; END IF;
  ALTER TABLE profiles DISABLE TRIGGER trg_guard_profile_self_update;
  UPDATE profiles SET role = 'membro', active = true, gvv_candidate_id = p_candidate,
         name = (SELECT name FROM gvv_candidates WHERE id = p_candidate)
   WHERE lower(email) = lower(p_email);
  ALTER TABLE profiles ENABLE TRIGGER trg_guard_profile_self_update;
  IF NOT FOUND THEN RAISE EXCEPTION 'Conta não encontrada. Tente de novo em alguns segundos.'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.gvv_link_leader_login(text,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gvv_link_leader_login(text,uuid) TO authenticated;

-- Quem já tem acesso (para mostrar "acesso criado" na tela do GVV)
CREATE OR REPLACE FUNCTION public.gvv_leader_logins() RETURNS TABLE(candidate_id uuid, email text, active boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT gvv_candidate_id, email, active FROM profiles
   WHERE gvv_candidate_id IS NOT NULL AND public.my_role() IN ('super_admin','pastor','coordenador','secretaria','administrativo')
$$;
GRANT EXECUTE ON FUNCTION public.gvv_leader_logins() TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
