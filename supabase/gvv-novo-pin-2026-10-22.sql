-- GVV · "Gerar novo PIN" do líder (2026-10-22, v2)
-- Troca o PIN do login do líder direto no banco e conserta o login junto:
--  · o login passa a usar o WhatsApp ATUAL do cadastro (se o telefone mudou, o antigo não entrava);
--  · confirma o e-mail interno e tira bloqueio.
-- Só a coordenação/administração pode.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
DROP FUNCTION IF EXISTS public.gvv_reset_leader_pin(uuid, text);
CREATE FUNCTION public.gvv_reset_leader_pin(p_candidate uuid, p_pin text) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE uid uuid; d text; mail text;
BEGIN
  IF public.my_role() NOT IN ('super_admin','pastor','secretaria','administrativo','coordenador') THEN
    RAISE EXCEPTION 'Sem permissão para gerar PIN.';
  END IF;
  IF p_pin !~ '^[0-9]{6}$' THEN RAISE EXCEPTION 'O PIN precisa ter 6 números.'; END IF;
  SELECT user_id INTO uid FROM profiles WHERE gvv_candidate_id = p_candidate AND user_id IS NOT NULL LIMIT 1;
  IF uid IS NULL THEN RAISE EXCEPTION 'Este líder ainda não tem acesso criado.'; END IF;
  -- mesmo cálculo do site (gvvLeaderEmail)
  SELECT regexp_replace(coalesce(phone, ''), '\D', '', 'g') INTO d FROM gvv_candidates WHERE id = p_candidate;
  IF d LIKE '55%' AND length(d) > 11 THEN d := substr(d, 3); END IF;
  IF length(d) < 10 THEN RAISE EXCEPTION 'O cadastro deste líder está sem WhatsApp válido.'; END IF;
  mail := d || '@lider.gvvadveccuritiba.online';
  IF EXISTS (SELECT 1 FROM auth.users WHERE lower(email) = mail AND id <> uid) THEN
    RAISE EXCEPTION 'Já existe outro acesso com o WhatsApp %. Fale com o suporte.', d;
  END IF;
  UPDATE auth.users SET email = mail,
         encrypted_password = extensions.crypt(p_pin, extensions.gen_salt('bf')),
         email_confirmed_at = coalesce(email_confirmed_at, now()),
         banned_until = NULL, updated_at = now()
   WHERE id = uid;
  UPDATE auth.identities SET identity_data = coalesce(identity_data, '{}'::jsonb) || jsonb_build_object('email', mail, 'email_verified', true), updated_at = now()
   WHERE user_id = uid AND provider = 'email';
  ALTER TABLE profiles DISABLE TRIGGER trg_guard_profile_self_update;
  UPDATE profiles SET email = mail, active = true WHERE user_id = uid;
  ALTER TABLE profiles ENABLE TRIGGER trg_guard_profile_self_update;
  RETURN d;
END $$;
REVOKE ALL ON FUNCTION public.gvv_reset_leader_pin(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gvv_reset_leader_pin(uuid, text) TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;
