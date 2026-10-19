-- Execute após gvv-candidatos.sql. Preserva cadastros, aprovações e GVVs.
BEGIN;
ALTER TABLE public.gvv_candidates
 ADD COLUMN IF NOT EXISTS home_address text NOT NULL DEFAULT '',
 ADD COLUMN IF NOT EXISTS home_lat numeric,
 ADD COLUMN IF NOT EXISTS home_lng numeric,
 ADD COLUMN IF NOT EXISTS host_lat numeric,
 ADD COLUMN IF NOT EXISTS host_lng numeric,
 ADD COLUMN IF NOT EXISTS audience text NOT NULL DEFAULT '',
 ADD COLUMN IF NOT EXISTS availability text NOT NULL DEFAULT '',
 ADD COLUMN IF NOT EXISTS capacity integer;
CREATE TABLE IF NOT EXISTS public.gvv_connections (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 leader_candidate_id uuid NOT NULL REFERENCES public.gvv_candidates(id),
 host_candidate_id uuid NOT NULL REFERENCES public.gvv_candidates(id),
 notes text NOT NULL DEFAULT '',
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(leader_candidate_id), UNIQUE(host_candidate_id)
);
-- Cada pessoa participa de somente uma conexão, inclusive quem oferece ambas as funções.
CREATE TABLE IF NOT EXISTS public.gvv_connection_people (
 candidate_id uuid PRIMARY KEY REFERENCES public.gvv_candidates(id),
 connection_id uuid NOT NULL REFERENCES public.gvv_connections(id) ON DELETE CASCADE
);
ALTER TABLE public.gvv_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gvv_connection_people ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS gvv_connections_manage ON public.gvv_connections;
CREATE POLICY gvv_connections_manage ON public.gvv_connections FOR ALL TO authenticated
 USING (public.my_role() IN ('super_admin','pastor','secretaria','administrativo','coordenador'))
 WITH CHECK (public.my_role() IN ('super_admin','pastor','secretaria','administrativo','coordenador'));
GRANT SELECT, DELETE ON public.gvv_connections TO authenticated;
REVOKE INSERT, UPDATE ON public.gvv_connections FROM authenticated;
REVOKE ALL ON public.gvv_connection_people FROM anon, authenticated;
CREATE OR REPLACE FUNCTION public.gvv_connect_candidates(p_leader uuid,p_host uuid,p_notes text DEFAULT '') RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE l public.gvv_candidates; h public.gvv_candidates; result uuid;
BEGIN
 IF public.my_role() IS NULL OR public.my_role() NOT IN ('super_admin','pastor','secretaria','administrativo','coordenador') THEN RAISE EXCEPTION 'Acesso restrito à equipe GVV.'; END IF;
 PERFORM id FROM public.gvv_candidates WHERE id IN (p_leader,p_host) ORDER BY id FOR UPDATE;
 SELECT * INTO l FROM public.gvv_candidates WHERE id=p_leader;
 SELECT * INTO h FROM public.gvv_candidates WHERE id=p_host;
 IF l.id IS NULL OR h.id IS NULL THEN RAISE EXCEPTION 'Cadastro não encontrado.'; END IF;
 IF l.kind NOT IN ('leader','both') OR l.leader_status<>'approved' THEN RAISE EXCEPTION 'Escolha uma liderança aprovada.'; END IF;
 IF h.kind NOT IN ('host','both') OR h.host_status<>'approved' THEN RAISE EXCEPTION 'Escolha uma casa aprovada.'; END IF;
 INSERT INTO public.gvv_connections(leader_candidate_id,host_candidate_id,notes) VALUES(p_leader,p_host,coalesce(p_notes,'')) RETURNING id INTO result;
 INSERT INTO public.gvv_connection_people(candidate_id,connection_id) SELECT DISTINCT x,result FROM unnest(ARRAY[p_leader,p_host]) x;
 RETURN result;
EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'Uma dessas pessoas já está conectada. Atualize o quadro.';
END $$;
REVOKE ALL ON FUNCTION public.gvv_connect_candidates(uuid,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.gvv_connect_candidates(uuid,uuid,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.gvv_guard_connected_candidate() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM public.gvv_connections WHERE leader_candidate_id=OLD.id) AND
 (NEW.kind NOT IN ('leader','both') OR NEW.leader_status<>'approved') THEN
 RAISE EXCEPTION 'Desfaça a conexão antes de alterar a aprovação da liderança.'; END IF;
 IF EXISTS(SELECT 1 FROM public.gvv_connections WHERE host_candidate_id=OLD.id) AND
 (NEW.kind NOT IN ('host','both') OR NEW.host_status<>'approved' OR NEW.address IS DISTINCT FROM OLD.address) THEN
 RAISE EXCEPTION 'Desfaça a conexão antes de alterar a casa ou sua aprovação.'; END IF;
 IF (NEW.home_lat IS NOT NULL AND abs(NEW.home_lat)>90) OR (NEW.host_lat IS NOT NULL AND abs(NEW.host_lat)>90) OR
 (NEW.home_lng IS NOT NULL AND abs(NEW.home_lng)>180) OR (NEW.host_lng IS NOT NULL AND abs(NEW.host_lng)>180) OR
 (NEW.capacity IS NOT NULL AND NEW.capacity<1) THEN RAISE EXCEPTION 'Confira coordenadas e capacidade.'; END IF;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS gvv_guard_connected_candidate ON public.gvv_candidates;
CREATE TRIGGER gvv_guard_connected_candidate BEFORE UPDATE ON public.gvv_candidates FOR EACH ROW EXECUTE FUNCTION public.gvv_guard_connected_candidate();
ALTER TABLE public.cells ADD COLUMN IF NOT EXISTS gvv_connection_id uuid UNIQUE REFERENCES public.gvv_connections(id);
CREATE OR REPLACE FUNCTION public.gvv_validate_connection_cell() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE link public.gvv_connections; leader public.gvv_candidates;
BEGIN
 IF NEW.gvv_connection_id IS NOT NULL THEN
  SELECT * INTO link FROM public.gvv_connections WHERE id=NEW.gvv_connection_id;
  SELECT * INTO leader FROM public.gvv_candidates WHERE id=link.leader_candidate_id;
  IF link.id IS NULL OR NEW.host_candidate_id IS DISTINCT FROM link.host_candidate_id OR
   leader.profile_id IS NULL OR NEW.leader_profile_id IS DISTINCT FROM leader.profile_id THEN
   RAISE EXCEPTION 'O GVV deve manter o líder e a casa da conexão escolhida.';
  END IF;
 END IF;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS gvv_validate_connection_cell ON public.cells;
CREATE TRIGGER gvv_validate_connection_cell BEFORE INSERT OR UPDATE ON public.cells FOR EACH ROW EXECUTE FUNCTION public.gvv_validate_connection_cell();
COMMIT;
