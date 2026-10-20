-- Sistema GVV — redes, número fixo de casa e supervisor de rede (20/10/2026)
-- Rodar uma vez no Supabase → SQL Editor. Pode rodar de novo sem estragar.
--
-- Níveis de acesso:
--   super_admin / pastor → ADM supremo (tudo)
--   coordenador          → Supervisor geral (todas as redes)
--   lider + gvv_network  → Supervisor de rede (só a própria rede)
BEGIN;

-- 1) Rede do supervisor
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS gvv_network text
  CHECK (gvv_network IN ('misto','jovens','adolescentes','juniores'));

-- 2) Rede e números fixos de cada cadastro
ALTER TABLE public.gvv_candidates
  ADD COLUMN IF NOT EXISTS network text CHECK (network IN ('misto','jovens','adolescentes','juniores')),
  ADD COLUMN IF NOT EXISTS house_no integer,
  ADD COLUMN IF NOT EXISTS network_no integer;
CREATE UNIQUE INDEX IF NOT EXISTS gvv_candidates_house_no ON public.gvv_candidates(house_no) WHERE house_no IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS gvv_candidates_network_no ON public.gvv_candidates(network, network_no) WHERE network_no IS NOT NULL;

CREATE OR REPLACE FUNCTION public.gvv_network_of(p_audience text, p_name text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN coalesce(p_audience,'') ~* 'junior' OR coalesce(p_name,'') ~* 'junior' THEN 'juniores'
    WHEN coalesce(p_audience,'') LIKE '%,%' THEN 'misto'
    WHEN coalesce(p_audience,'') ~* 'adolesc' THEN 'adolescentes'
    WHEN coalesce(p_audience,'') ~* 'jove' THEN 'jovens'
    ELSE 'misto' END
$$;

CREATE OR REPLACE FUNCTION public.gvv_network_order(n text) RETURNS int LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE n WHEN 'misto' THEN 1 WHEN 'jovens' THEN 2 WHEN 'adolescentes' THEN 3 WHEN 'juniores' THEN 4 ELSE 9 END
$$;

UPDATE public.gvv_candidates SET network = public.gvv_network_of(audience, name) WHERE network IS NULL;

-- Numeração inicial (só quem tem casa): geral e por rede. Quem já tem número não muda.
WITH ord AS (
  SELECT id, (SELECT coalesce(max(house_no),0) FROM public.gvv_candidates) +
         row_number() OVER (ORDER BY public.gvv_network_order(network), name) AS n
  FROM public.gvv_candidates WHERE kind IN ('host','both') AND house_no IS NULL
) UPDATE public.gvv_candidates c SET house_no = ord.n FROM ord WHERE c.id = ord.id;
WITH ord AS (
  SELECT c.id, (SELECT coalesce(max(x.network_no),0) FROM public.gvv_candidates x WHERE x.network = c.network) +
         row_number() OVER (PARTITION BY c.network ORDER BY c.house_no) AS n
  FROM public.gvv_candidates c WHERE c.kind IN ('host','both') AND c.network_no IS NULL
) UPDATE public.gvv_candidates c SET network_no = ord.n FROM ord WHERE c.id = ord.id;

-- Casa nova (ou que mudou de rede) recebe o próximo número automaticamente.
CREATE OR REPLACE FUNCTION public.gvv_assign_numbers() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.network IS NULL THEN NEW.network := gvv_network_of(NEW.audience, NEW.name); END IF;
  IF NEW.kind IN ('host','both') THEN
    IF NEW.house_no IS NULL THEN
      NEW.house_no := (SELECT coalesce(max(house_no),0) + 1 FROM gvv_candidates);
    END IF;
    IF NEW.network_no IS NULL OR (TG_OP = 'UPDATE' AND NEW.network IS DISTINCT FROM OLD.network) THEN
      NEW.network_no := (SELECT coalesce(max(network_no),0) + 1 FROM gvv_candidates WHERE network = NEW.network AND id <> NEW.id);
    END IF;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS gvv_assign_numbers ON public.gvv_candidates;
CREATE TRIGGER gvv_assign_numbers BEFORE INSERT OR UPDATE OF kind, network ON public.gvv_candidates
  FOR EACH ROW EXECUTE FUNCTION public.gvv_assign_numbers();

-- 3) Supervisor de rede: vê e conecta só a própria rede
CREATE OR REPLACE FUNCTION public.my_gvv_network() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT gvv_network FROM profiles WHERE user_id = auth.uid() AND active = true LIMIT 1
$$;

DROP POLICY IF EXISTS gvv_candidates_network_read ON public.gvv_candidates;
CREATE POLICY gvv_candidates_network_read ON public.gvv_candidates FOR SELECT TO authenticated
  USING (public.my_role() = 'lider' AND public.my_gvv_network() IS NOT NULL AND network = public.my_gvv_network());

DROP POLICY IF EXISTS gvv_connections_network_read ON public.gvv_connections;
CREATE POLICY gvv_connections_network_read ON public.gvv_connections FOR SELECT TO authenticated
  USING (public.my_role() = 'lider' AND EXISTS (
    SELECT 1 FROM public.gvv_candidates h WHERE h.id = host_candidate_id AND h.network = public.my_gvv_network()));
DROP POLICY IF EXISTS gvv_connections_network_delete ON public.gvv_connections;
CREATE POLICY gvv_connections_network_delete ON public.gvv_connections FOR DELETE TO authenticated
  USING (public.my_role() = 'lider' AND EXISTS (
    SELECT 1 FROM public.gvv_candidates h WHERE h.id = host_candidate_id AND h.network = public.my_gvv_network()));

CREATE OR REPLACE FUNCTION public.gvv_connect_candidates(p_leader uuid,p_host uuid,p_notes text DEFAULT '') RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE l public.gvv_candidates; h public.gvv_candidates; result uuid; r text := public.my_role(); net text := public.my_gvv_network();
BEGIN
 IF r IS NULL OR (r NOT IN ('super_admin','pastor','secretaria','administrativo','coordenador') AND NOT (r = 'lider' AND net IS NOT NULL)) THEN
   RAISE EXCEPTION 'Acesso restrito à equipe GVV.'; END IF;
 PERFORM id FROM public.gvv_candidates WHERE id IN (p_leader,p_host) ORDER BY id FOR UPDATE;
 SELECT * INTO l FROM public.gvv_candidates WHERE id=p_leader;
 SELECT * INTO h FROM public.gvv_candidates WHERE id=p_host;
 IF l.id IS NULL OR h.id IS NULL THEN RAISE EXCEPTION 'Cadastro não encontrado.'; END IF;
 IF r = 'lider' AND (h.network IS DISTINCT FROM net OR l.network IS DISTINCT FROM net) THEN
   RAISE EXCEPTION 'Você só pode conectar casas e líderes da sua rede.'; END IF;
 IF l.kind NOT IN ('leader','both') OR l.leader_status<>'approved' THEN RAISE EXCEPTION 'Escolha uma liderança aprovada.'; END IF;
 IF h.kind NOT IN ('host','both') OR h.host_status<>'approved' THEN RAISE EXCEPTION 'Escolha uma casa aprovada.'; END IF;
 INSERT INTO public.gvv_connections(leader_candidate_id,host_candidate_id,notes) VALUES(p_leader,p_host,coalesce(p_notes,'')) RETURNING id INTO result;
 INSERT INTO public.gvv_connection_people(candidate_id,connection_id) SELECT DISTINCT x,result FROM unnest(ARRAY[p_leader,p_host]) x;
 RETURN result;
EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'Uma dessas pessoas já está conectada. Atualize o quadro.';
END $$;
REVOKE ALL ON FUNCTION public.gvv_connect_candidates(uuid,uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gvv_connect_candidates(uuid,uuid,text) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;

-- Conferência: casas por rede
SELECT network, count(*) FILTER (WHERE kind IN ('host','both')) AS casas, count(*) FILTER (WHERE kind = 'leader') AS lideres
FROM public.gvv_candidates GROUP BY 1 ORDER BY public.gvv_network_order(network);
