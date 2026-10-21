-- GVV · trocar o líder de um GVV formado (2026-10-22)
-- O vice continua sendo trocado por gvv_update_group.
BEGIN;
CREATE OR REPLACE FUNCTION public.gvv_set_leader(p_conn uuid, p_leader uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE c gvv_connections; l gvv_candidates;
BEGIN
  IF public.my_role() NOT IN ('super_admin','pastor','secretaria','administrativo','coordenador') THEN
    RAISE EXCEPTION 'Sem permissão para trocar o líder.';
  END IF;
  SELECT * INTO c FROM gvv_connections WHERE id = p_conn FOR UPDATE;
  IF c.id IS NULL THEN RAISE EXCEPTION 'GVV não encontrado.'; END IF;
  IF p_leader = c.leader_candidate_id THEN RETURN; END IF;
  SELECT * INTO l FROM gvv_candidates WHERE id = p_leader;
  IF l.id IS NULL OR l.kind NOT IN ('leader','both') OR l.leader_status <> 'approved' THEN
    RAISE EXCEPTION 'O líder precisa ser um líder aprovado.';
  END IF;
  -- Anfitrião só pode liderar a própria casa.
  IF l.kind = 'both' AND p_leader <> c.host_candidate_id AND EXISTS (SELECT 1 FROM gvv_connection_people WHERE candidate_id = p_leader) THEN
    RAISE EXCEPTION 'Este líder já está em outro GVV.';
  END IF;
  IF p_leader <> c.host_candidate_id AND EXISTS (SELECT 1 FROM gvv_connection_people WHERE candidate_id = p_leader AND connection_id <> c.id) THEN
    RAISE EXCEPTION 'Este líder já está em outro GVV.';
  END IF;
  IF p_leader = (to_jsonb(c)->>'vice_candidate_id')::uuid THEN
    UPDATE gvv_connections SET vice_candidate_id = NULL WHERE id = c.id;
  END IF;
  IF c.leader_candidate_id <> c.host_candidate_id THEN
    DELETE FROM gvv_connection_people WHERE candidate_id = c.leader_candidate_id AND connection_id = c.id;
  END IF;
  IF p_leader <> c.host_candidate_id THEN
    INSERT INTO gvv_connection_people(candidate_id, connection_id) VALUES (p_leader, c.id)
    ON CONFLICT (candidate_id) DO NOTHING;
  END IF;
  UPDATE gvv_connections SET leader_candidate_id = p_leader WHERE id = c.id;
END $$;
REVOKE ALL ON FUNCTION public.gvv_set_leader(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gvv_set_leader(uuid, uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;
