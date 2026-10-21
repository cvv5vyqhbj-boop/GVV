-- GVV · arquivar e excluir cadastros (2026-10-22)
-- Arquivado some das listas, do quadro e da impressão, mas pode voltar.
-- Excluir apaga de vez. Os dois só funcionam para quem não está num GVV formado.
BEGIN;
ALTER TABLE public.gvv_candidates ADD COLUMN IF NOT EXISTS archived_at timestamptz;

CREATE OR REPLACE FUNCTION public.gvv_archive_candidate(p_id uuid, p_archive boolean) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.my_role() NOT IN ('super_admin','pastor','secretaria','administrativo','coordenador') THEN
    RAISE EXCEPTION 'Sem permissão para arquivar.';
  END IF;
  IF p_archive AND EXISTS (SELECT 1 FROM gvv_connections c WHERE p_id IN (c.leader_candidate_id, c.host_candidate_id)
                           OR (to_jsonb(c)->>'vice_candidate_id')::uuid = p_id) THEN
    RAISE EXCEPTION 'Esta pessoa está num GVV formado. Desconecte o GVV antes de arquivar.';
  END IF;
  UPDATE gvv_candidates SET archived_at = CASE WHEN p_archive THEN now() END WHERE id = p_id;
END $$;
REVOKE ALL ON FUNCTION public.gvv_archive_candidate(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gvv_archive_candidate(uuid, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.gvv_delete_candidate(p_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.my_role() NOT IN ('super_admin','pastor','secretaria','administrativo') THEN
    RAISE EXCEPTION 'Só a administração pode excluir cadastros.';
  END IF;
  IF EXISTS (SELECT 1 FROM gvv_connections c WHERE p_id IN (c.leader_candidate_id, c.host_candidate_id)
             OR (to_jsonb(c)->>'vice_candidate_id')::uuid = p_id) THEN
    RAISE EXCEPTION 'Esta pessoa está num GVV formado. Desconecte o GVV antes de excluir.';
  END IF;
  UPDATE profiles SET gvv_candidate_id = NULL WHERE gvv_candidate_id = p_id;
  DELETE FROM gvv_connection_people WHERE candidate_id = p_id;
  DELETE FROM gvv_candidates WHERE id = p_id;
END $$;
REVOKE ALL ON FUNCTION public.gvv_delete_candidate(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gvv_delete_candidate(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
