-- CORREÇÃO URGENTE: regra do líder causava laço (recursão) entre gvv_candidates e gvv_connections.
-- Nada foi apagado; as consultas só falhavam. Esta correção troca a regra por funções seguras.
BEGIN;

CREATE OR REPLACE FUNCTION public.my_gvv_candidate_ids() RETURNS SETOF uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT x FROM gvv_connections c
  JOIN profiles p ON p.user_id = auth.uid() AND p.active AND p.gvv_candidate_id IS NOT NULL
  CROSS JOIN LATERAL unnest(ARRAY[c.leader_candidate_id, c.vice_candidate_id, c.host_candidate_id]) AS x
  WHERE p.gvv_candidate_id IN (c.leader_candidate_id, c.vice_candidate_id, c.host_candidate_id) AND x IS NOT NULL
$$;

CREATE OR REPLACE FUNCTION public.gvv_conn_in_my_network(p_conn uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM gvv_connections c JOIN gvv_candidates h ON h.id = c.host_candidate_id
                 WHERE c.id = p_conn AND h.network = public.my_gvv_network())
$$;

DROP POLICY IF EXISTS gvv_candidates_leader_read ON public.gvv_candidates;
CREATE POLICY gvv_candidates_leader_read ON public.gvv_candidates FOR SELECT TO authenticated
  USING (id IN (SELECT public.my_gvv_candidate_ids()));

DROP POLICY IF EXISTS gvv_connections_network_read ON public.gvv_connections;
CREATE POLICY gvv_connections_network_read ON public.gvv_connections FOR SELECT TO authenticated
  USING (public.my_role() = 'lider' AND public.gvv_conn_in_my_network(id));
DROP POLICY IF EXISTS gvv_connections_network_delete ON public.gvv_connections;
CREATE POLICY gvv_connections_network_delete ON public.gvv_connections FOR DELETE TO authenticated
  USING (public.my_role() = 'lider' AND public.gvv_conn_in_my_network(id));

NOTIFY pgrst, 'reload schema';
COMMIT;

-- Conferência: deve mostrar seus cadastros e conexões
SELECT (SELECT count(*) FROM public.gvv_candidates) AS cadastros, (SELECT count(*) FROM public.gvv_connections) AS gvvs;
