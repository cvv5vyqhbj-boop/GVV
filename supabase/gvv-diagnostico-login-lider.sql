-- Diagnóstico do login do líder 41996253224. Não altera nada.
-- Troque 000000 pelo PIN que você está tentando e rode no SQL Editor.

-- 1) Quem tem esse WhatsApp no cadastro
SELECT 'cadastro' AS onde, id, name, kind, phone, leader_status
FROM gvv_candidates WHERE regexp_replace(phone, '\D', '', 'g') LIKE '%996253224%';

-- 2) Login criado para esse número e se o PIN confere
SELECT 'login' AS onde, u.email, u.email_confirmed_at IS NOT NULL AS email_confirmado, u.banned_until,
       p.active AS perfil_ativo, p.role, p.gvv_candidate_id,
       (SELECT name FROM gvv_candidates WHERE id = p.gvv_candidate_id) AS ligado_ao_lider,
       u.encrypted_password = extensions.crypt('000000', u.encrypted_password) AS pin_confere   -- ← troque 000000 pelo PIN
FROM auth.users u LEFT JOIN profiles p ON p.user_id = u.id
WHERE u.email LIKE '%996253224%';
