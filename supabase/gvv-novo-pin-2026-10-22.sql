-- GVV · "Gerar novo PIN" do líder (2026-10-22)
-- Troca o PIN (senha) do login do líder direto no banco. Só a coordenação/administração pode.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE OR REPLACE FUNCTION public.gvv_reset_leader_pin(p_candidate uuid, p_pin text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE uid uuid;
BEGIN
  IF public.my_role() NOT IN ('super_admin','pastor','secretaria','administrativo','coordenador') THEN
    RAISE EXCEPTION 'Sem permissão para gerar PIN.';
  END IF;
  IF p_pin !~ '^[0-9]{6}$' THEN RAISE EXCEPTION 'O PIN precisa ter 6 números.'; END IF;
  SELECT user_id INTO uid FROM profiles WHERE gvv_candidate_id = p_candidate AND user_id IS NOT NULL LIMIT 1;
  IF uid IS NULL THEN RAISE EXCEPTION 'Este líder ainda não tem acesso criado.'; END IF;
  UPDATE auth.users SET encrypted_password = extensions.crypt(p_pin, extensions.gen_salt('bf')), updated_at = now() WHERE id = uid;
END $$;
REVOKE ALL ON FUNCTION public.gvv_reset_leader_pin(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gvv_reset_leader_pin(uuid, text) TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;
