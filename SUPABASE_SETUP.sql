-- ============================================================
-- ADVEC — Ecossistema Administrativo da Igreja
-- Fase 1: Fundação (perfis, departamentos, membros, finanças, eventos, ensino)
--
-- SEGURANÇA: ao contrário do sistema de artes, aqui os dados são SENSÍVEIS
-- (membros e finanças). Por isso usamos Supabase Auth + RLS por papel:
-- ninguém vê nada sem estar logado, e cada papel só acessa o que lhe cabe.
--
-- Pode rodar TUDO de novo sem medo (idempotente).
-- ============================================================

-- ------------------------------------------------------------
-- 1) PERFIS — 1 linha por usuário do Supabase Auth
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS profiles (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  name          TEXT NOT NULL DEFAULT 'Novo usuário',
  email         TEXT,
  role          TEXT NOT NULL DEFAULT 'lider'
                CHECK (role IN ('super_admin','financeiro','secretaria','administrativo','lider','membro')),
  department_id UUID,
  active        BOOLEAN NOT NULL DEFAULT false,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- 2) DEPARTAMENTOS
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS departments (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name              TEXT NOT NULL,
  leader_profile_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
  color             TEXT DEFAULT 'amber',
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- 3) MEMBROS (cadastro da secretaria)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS members (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name     TEXT NOT NULL,
  phone         TEXT,
  email         TEXT,
  birth_date    DATE,
  address       TEXT,
  department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
  status        TEXT NOT NULL DEFAULT 'ativo'
                CHECK (status IN ('ativo','inativo','visitante')),
  entry_date    DATE DEFAULT CURRENT_DATE,
  baptized      BOOLEAN NOT NULL DEFAULT false,
  baptism_date  DATE,
  photo_url     TEXT,
  notes         TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- 4) LANÇAMENTOS FINANCEIROS
--    department_id NULL = caixa geral da igreja
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS finance_entries (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type          TEXT NOT NULL CHECK (type IN ('entrada','saida')),
  amount        NUMERIC(12,2) NOT NULL DEFAULT 0,
  description   TEXT NOT NULL DEFAULT '',
  category      TEXT,
  department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
  date          DATE NOT NULL DEFAULT CURRENT_DATE,
  created_by    UUID REFERENCES profiles(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- 5) EVENTOS  (published/payment_link são para a futura área do membro)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS events (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title         TEXT NOT NULL,
  description   TEXT,
  date          DATE NOT NULL,
  time          TIME,
  location      TEXT,
  department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
  type          TEXT NOT NULL DEFAULT 'evento'
                CHECK (type IN ('culto','evento','batismo','reuniao','ensino','outro')),
  published     BOOLEAN NOT NULL DEFAULT false,
  payment_link  TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- 6) ENSINO — schema criado agora; telas vêm na Fase 2
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS courses (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title       TEXT NOT NULL,
  description TEXT,
  cover_url   TEXT,
  published   BOOLEAN NOT NULL DEFAULT false,
  position    INT NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS lessons (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id  UUID NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  title      TEXT NOT NULL,
  content    TEXT,
  video_url  TEXT,
  position   INT NOT NULL DEFAULT 0,
  published  BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- 7) EVOLUÇÃO (Fase 1.1): papel Pastor, gênero do membro,
--    fluxo de eventos (rito de 7 etapas + aprovações)
--    Tudo idempotente — pode rodar de novo sem medo.
-- ------------------------------------------------------------

-- Papéis "pastor" e "lider_projetos" (cadeia de aprovação dos eventos)
-- Nota: o constraint definitivo (incluindo 'midia') vive na seção 11; aqui deixamos
-- a lista completa desde já pra evitar quebrar em bancos que ja tenham role='midia'.
ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE profiles ADD CONSTRAINT profiles_role_check
  CHECK (role IN ('super_admin','pastor','lider_projetos','financeiro','secretaria','administrativo','lider','membro','midia'));

-- Gênero do membro (alimenta os ministérios automáticos: Homens/Mulheres/Jovens/Adolescentes)
ALTER TABLE members ADD COLUMN IF NOT EXISTS gender TEXT
  CHECK (gender IN ('masculino','feminino') OR gender IS NULL);

-- Fluxo de eventos (rito) — colunas novas
ALTER TABLE events ADD COLUMN IF NOT EXISTS stage TEXT NOT NULL DEFAULT 'inicial';
ALTER TABLE events ADD COLUMN IF NOT EXISTS difficulty TEXT NOT NULL DEFAULT 'moderada';
ALTER TABLE events ADD COLUMN IF NOT EXISTS audience JSONB NOT NULL DEFAULT '[]'::jsonb;   -- ministérios alvo
ALTER TABLE events ADD COLUMN IF NOT EXISTS budget NUMERIC(12,2);                            -- prévia orçamentária
ALTER TABLE events ADD COLUMN IF NOT EXISTS objectives TEXT;                                 -- objetivos do evento
ALTER TABLE events ADD COLUMN IF NOT EXISTS deliverables TEXT;                               -- entregáveis pretendidos
ALTER TABLE events ADD COLUMN IF NOT EXISTS action_map TEXT;                                 -- mapa de ações/responsáveis
ALTER TABLE events ADD COLUMN IF NOT EXISTS approvals JSONB NOT NULL DEFAULT '{}'::jsonb;    -- escopo/orcamento/mapa_acoes
ALTER TABLE events ADD COLUMN IF NOT EXISTS responsible_profile_id UUID REFERENCES profiles(id) ON DELETE SET NULL;

-- ============================================================
-- FUNÇÕES AUXILIARES (SECURITY DEFINER evita recursão de RLS)
-- ============================================================
CREATE OR REPLACE FUNCTION my_role() RETURNS TEXT
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT role FROM profiles WHERE user_id = auth.uid() AND active = true LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION my_department() RETURNS UUID
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT department_id FROM profiles WHERE user_id = auth.uid() AND active = true LIMIT 1;
$$;

-- ============================================================
-- TRIGGER — cria um profile automaticamente quando alguém é
-- criado no Auth (começa INATIVO até um admin liberar o papel)
-- ============================================================
CREATE OR REPLACE FUNCTION handle_new_user() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO profiles (user_id, name, email, role, active)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'name', split_part(NEW.email,'@',1)),
          NEW.email, 'lider', false)
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ============================================================
-- RLS — liga e define políticas por papel
-- ============================================================
ALTER TABLE profiles        ENABLE ROW LEVEL SECURITY;
ALTER TABLE departments     ENABLE ROW LEVEL SECURITY;
ALTER TABLE members         ENABLE ROW LEVEL SECURITY;
ALTER TABLE finance_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE events          ENABLE ROW LEVEL SECURITY;
ALTER TABLE courses         ENABLE ROW LEVEL SECURITY;
ALTER TABLE lessons         ENABLE ROW LEVEL SECURITY;

-- ---------- PROFILES ----------
DROP POLICY IF EXISTS profiles_select ON profiles;
DROP POLICY IF EXISTS profiles_admin_write ON profiles;
-- qualquer usuário logado lê os perfis (nomes de líderes aparecem na UI)
CREATE POLICY profiles_select ON profiles FOR SELECT TO authenticated USING (true);
-- só super_admin cria/edita/remove perfis (define papéis)
CREATE POLICY profiles_admin_write ON profiles FOR ALL TO authenticated
  USING (my_role() = 'super_admin') WITH CHECK (my_role() = 'super_admin');

-- ---------- DEPARTMENTS ----------
DROP POLICY IF EXISTS departments_select ON departments;
DROP POLICY IF EXISTS departments_write ON departments;
CREATE POLICY departments_select ON departments FOR SELECT TO authenticated USING (true);
CREATE POLICY departments_write ON departments FOR ALL TO authenticated
  USING (my_role() IN ('super_admin','administrativo'))
  WITH CHECK (my_role() IN ('super_admin','administrativo'));

-- ---------- MEMBERS ----------
DROP POLICY IF EXISTS members_select ON members;
DROP POLICY IF EXISTS members_write ON members;
-- staff vê todos; líder vê só o próprio departamento
CREATE POLICY members_select ON members FOR SELECT TO authenticated USING (
  my_role() IN ('super_admin','secretaria','financeiro','administrativo')
  OR (my_role() = 'lider' AND department_id = my_department())
);
CREATE POLICY members_write ON members FOR ALL TO authenticated USING (
  my_role() IN ('super_admin','secretaria')
  OR (my_role() = 'lider' AND department_id = my_department())
) WITH CHECK (
  my_role() IN ('super_admin','secretaria')
  OR (my_role() = 'lider' AND department_id = my_department())
);

-- ---------- FINANCE ----------
DROP POLICY IF EXISTS finance_select ON finance_entries;
DROP POLICY IF EXISTS finance_write ON finance_entries;
CREATE POLICY finance_select ON finance_entries FOR SELECT TO authenticated USING (
  my_role() IN ('super_admin','financeiro','pastor')
  OR (my_role() = 'lider' AND department_id = my_department())
);
CREATE POLICY finance_write ON finance_entries FOR ALL TO authenticated USING (
  my_role() IN ('super_admin','financeiro')
  OR (my_role() = 'lider' AND department_id = my_department())
) WITH CHECK (
  my_role() IN ('super_admin','financeiro')
  OR (my_role() = 'lider' AND department_id = my_department())
);

-- ---------- EVENTS ----------
DROP POLICY IF EXISTS events_select ON events;
DROP POLICY IF EXISTS events_write ON events;
CREATE POLICY events_select ON events FOR SELECT TO authenticated USING (true);
-- Cadeia de aprovação: solicitante (líder do dept) → líder de projetos → pastor
CREATE POLICY events_write ON events FOR ALL TO authenticated USING (
  my_role() IN ('super_admin','administrativo','pastor','lider_projetos')
  OR (my_role() = 'lider' AND department_id = my_department())
) WITH CHECK (
  my_role() IN ('super_admin','administrativo','pastor','lider_projetos')
  OR (my_role() = 'lider' AND department_id = my_department())
);

-- ---------- COURSES / LESSONS (Ensino) ----------
DROP POLICY IF EXISTS courses_select ON courses;
DROP POLICY IF EXISTS courses_write ON courses;
CREATE POLICY courses_select ON courses FOR SELECT TO authenticated USING (true);
CREATE POLICY courses_write ON courses FOR ALL TO authenticated
  USING (my_role() IN ('super_admin','administrativo'))
  WITH CHECK (my_role() IN ('super_admin','administrativo'));

DROP POLICY IF EXISTS lessons_select ON lessons;
DROP POLICY IF EXISTS lessons_write ON lessons;
CREATE POLICY lessons_select ON lessons FOR SELECT TO authenticated USING (true);
CREATE POLICY lessons_write ON lessons FOR ALL TO authenticated
  USING (my_role() IN ('super_admin','administrativo'))
  WITH CHECK (my_role() IN ('super_admin','administrativo'));

-- ============================================================
-- TEMPO REAL (atualização ao vivo)
-- ============================================================
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE members;         EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE departments;     EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE finance_entries; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE events;          EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE profiles;        EXCEPTION WHEN OTHERS THEN NULL; END $$;

-- ============================================================
-- 8) CADASTRO PÚBLICO DE MEMBRO (status "pendente")
--    Visitantes preenchem um formulário sem login; o registro
--    cai como "pendente" pra Pastor e Secretaria aprovarem.
-- ============================================================
ALTER TABLE members DROP CONSTRAINT IF EXISTS members_status_check;
ALTER TABLE members ADD CONSTRAINT members_status_check
  CHECK (status IN ('ativo','inativo','visitante','pendente'));

DROP POLICY IF EXISTS members_public_signup ON members;
CREATE POLICY members_public_signup ON members FOR INSERT TO anon
  WITH CHECK (status = 'pendente');

-- ============================================================
-- 9) CORREÇÃO RLS DEPARTAMENTOS — pastor/secretaria também escrevem
--    Bug: só super_admin/administrativo conseguiam criar; pastor
--    (papel adicionado depois) recebia erro silencioso de RLS.
-- ============================================================
DROP POLICY IF EXISTS departments_write ON departments;
CREATE POLICY departments_write ON departments FOR ALL TO authenticated
  USING (my_role() IN ('super_admin','administrativo','pastor','secretaria'))
  WITH CHECK (my_role() IN ('super_admin','administrativo','pastor','secretaria'));

-- ============================================================
-- 10) FASE 1 — Tipos de evento expandidos + multi-dia + detalhes
-- ============================================================
ALTER TABLE events DROP CONSTRAINT IF EXISTS events_type_check;
ALTER TABLE events ADD CONSTRAINT events_type_check
  CHECK (type IN ('culto','evento','batismo','reuniao','ensino','outro',
                  'conferencia','viagem','retiro','externo','interno',
                  'acampamento','acampadentro','congresso','seminario'));

ALTER TABLE events ADD COLUMN IF NOT EXISTS end_date DATE;
ALTER TABLE events ADD COLUMN IF NOT EXISTS details JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE events ADD COLUMN IF NOT EXISTS daily_program JSONB NOT NULL DEFAULT '[]'::jsonb;

-- ============================================================
-- 11) CONTROLE DE ACESSO REVISADO
--   - Pastor e Líder de Projetos dirigem tudo (criam, editam, avançam).
--   - Mídia entra como papel próprio (acessa eventos a partir do Estratégico).
--   - Líder de Departamento NÃO escreve mais em eventos — só lê e participa do chat.
-- ============================================================
-- Papel "midia"
ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE profiles ADD CONSTRAINT profiles_role_check
  CHECK (role IN ('super_admin','pastor','lider_projetos','financeiro','secretaria','administrativo','lider','membro','midia'));

-- RLS de eventos: líder de depto PROPÕE (cria/edita) eventos do próprio dept;
-- direção do fluxo (avançar etapa) é controlada no frontend.
DROP POLICY IF EXISTS events_write ON events;
CREATE POLICY events_write ON events FOR ALL TO authenticated
  USING (my_role() IN ('super_admin','administrativo','pastor','lider_projetos','secretaria','midia')
         OR (my_role() = 'lider' AND (department_id IS NULL OR department_id = my_department())))
  WITH CHECK (my_role() IN ('super_admin','administrativo','pastor','lider_projetos','secretaria','midia')
              OR (my_role() = 'lider' AND (department_id IS NULL OR department_id = my_department())));

-- ============================================================
-- 12) CHAT POR EVENTO — Pastor + Líder de Projetos + Mídia escrevem.
--     Líder do departamento (responsável pelo dept do evento) responde também.
-- ============================================================
CREATE TABLE IF NOT EXISTS event_messages (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id    UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  profile_id  UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  body        TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS event_messages_event_idx ON event_messages(event_id, created_at);
ALTER TABLE event_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS messages_select ON event_messages;
CREATE POLICY messages_select ON event_messages FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS messages_insert ON event_messages;
CREATE POLICY messages_insert ON event_messages FOR INSERT TO authenticated WITH CHECK (
  -- só o dono do próprio profile envia (não dá pra postar em nome de outro)
  profile_id IN (SELECT id FROM profiles WHERE user_id = auth.uid() AND active = true)
  AND my_role() IN ('super_admin','pastor','lider_projetos','midia','administrativo','secretaria','lider')
);
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE event_messages; EXCEPTION WHEN OTHERS THEN NULL; END $$;

-- 13) COMENTÁRIOS POR ETAPA — cada mensagem fica vinculada a uma etapa (etapa1..etapa6)
ALTER TABLE event_messages ADD COLUMN IF NOT EXISTS stage_key TEXT;

-- ============================================================
-- 14) FICHA DE RECEPÇÃO DE MEMBRO — todos os campos do formulário físico
-- ============================================================
ALTER TABLE members ADD COLUMN IF NOT EXISTS rg TEXT;
ALTER TABLE members ADD COLUMN IF NOT EXISTS rg_issuer TEXT;
ALTER TABLE members ADD COLUMN IF NOT EXISTS rg_issue_date DATE;
ALTER TABLE members ADD COLUMN IF NOT EXISTS cpf TEXT;
ALTER TABLE members ADD COLUMN IF NOT EXISTS blood_type TEXT;
ALTER TABLE members ADD COLUMN IF NOT EXISTS organ_donor BOOLEAN;
ALTER TABLE members ADD COLUMN IF NOT EXISTS father_name TEXT;
ALTER TABLE members ADD COLUMN IF NOT EXISTS mother_name TEXT;
ALTER TABLE members ADD COLUMN IF NOT EXISTS education TEXT;
ALTER TABLE members ADD COLUMN IF NOT EXISTS profession TEXT;
ALTER TABLE members ADD COLUMN IF NOT EXISTS marital_status TEXT;
ALTER TABLE members ADD COLUMN IF NOT EXISTS marriage_date DATE;
ALTER TABLE members ADD COLUMN IF NOT EXISTS spouse_name TEXT;
ALTER TABLE members ADD COLUMN IF NOT EXISTS spouse_is_member BOOLEAN;
ALTER TABLE members ADD COLUMN IF NOT EXISTS cep TEXT;
ALTER TABLE members ADD COLUMN IF NOT EXISTS street TEXT;
ALTER TABLE members ADD COLUMN IF NOT EXISTS address_number TEXT;
ALTER TABLE members ADD COLUMN IF NOT EXISTS address_complement TEXT;
ALTER TABLE members ADD COLUMN IF NOT EXISTS neighborhood TEXT;
ALTER TABLE members ADD COLUMN IF NOT EXISTS city TEXT;
ALTER TABLE members ADD COLUMN IF NOT EXISTS state TEXT;
ALTER TABLE members ADD COLUMN IF NOT EXISTS home_phone TEXT;
ALTER TABLE members ADD COLUMN IF NOT EXISTS origin_church TEXT;
ALTER TABLE members ADD COLUMN IF NOT EXISTS reception_date DATE;

-- Departamentos que o membro pertence (array de UUIDs). Complementa o
-- department_id (mantido por compatibilidade). Um membro pode estar em vários
-- (ex: Música + Homens + Jovens ao mesmo tempo).
ALTER TABLE members ADD COLUMN IF NOT EXISTS department_ids JSONB NOT NULL DEFAULT '[]'::jsonb;

-- ============================================================
-- 15) RLS DE MEMBROS — pastor/secretaria vêem todos e cadastram;
--     líder vê só o próprio dept (via department_ids OU department_id) e NÃO
--     pode criar/deletar membros — só editar department_ids para incluir/
--     remover o próprio departamento.
-- ============================================================
DROP POLICY IF EXISTS members_select ON members;
CREATE POLICY members_select ON members FOR SELECT TO authenticated USING (
  my_role() IN ('super_admin','pastor','secretaria','financeiro','administrativo')
  OR (my_role() = 'lider' AND (
    department_id = my_department()
    OR department_ids @> to_jsonb(my_department()::text)
  ))
);

DROP POLICY IF EXISTS members_write ON members;
DROP POLICY IF EXISTS members_insert ON members;
DROP POLICY IF EXISTS members_update ON members;
DROP POLICY IF EXISTS members_delete ON members;

CREATE POLICY members_insert ON members FOR INSERT TO authenticated
  WITH CHECK (my_role() IN ('super_admin','pastor','secretaria'));
CREATE POLICY members_update ON members FOR UPDATE TO authenticated USING (
  my_role() IN ('super_admin','pastor','secretaria')
  OR my_role() = 'lider'   -- líder atualiza p/ incluir/remover o próprio depto (via UI)
) WITH CHECK (
  my_role() IN ('super_admin','pastor','secretaria')
  OR my_role() = 'lider'
);
CREATE POLICY members_delete ON members FOR DELETE TO authenticated
  USING (my_role() IN ('super_admin','pastor','secretaria'));

-- ============================================================
-- 16) SETOR FINANCEIRO — Fornecedores + notas com upload + parcelas
-- ============================================================

-- Fornecedores da igreja (empresas prestadoras)
CREATE TABLE IF NOT EXISTS suppliers (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  cnpj        TEXT,
  description TEXT,
  active      BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS suppliers_cnpj_key ON suppliers(cnpj) WHERE cnpj IS NOT NULL;
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS suppliers_select ON suppliers;
CREATE POLICY suppliers_select ON suppliers FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS suppliers_write ON suppliers;
CREATE POLICY suppliers_write ON suppliers FOR ALL TO authenticated
  USING (my_role() IN ('super_admin','pastor','financeiro','secretaria'))
  WITH CHECK (my_role() IN ('super_admin','pastor','financeiro','secretaria'));
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE suppliers; EXCEPTION WHEN OTHERS THEN NULL; END $$;

-- Expande finance_entries com metadados de nota, comprovante e parcelamento
ALTER TABLE finance_entries ADD COLUMN IF NOT EXISTS supplier_id UUID REFERENCES suppliers(id) ON DELETE SET NULL;
ALTER TABLE finance_entries ADD COLUMN IF NOT EXISTS invoice_number TEXT;
ALTER TABLE finance_entries ADD COLUMN IF NOT EXISTS subcategory TEXT;
ALTER TABLE finance_entries ADD COLUMN IF NOT EXISTS receipt_path TEXT;
ALTER TABLE finance_entries ADD COLUMN IF NOT EXISTS receipt_name TEXT;
ALTER TABLE finance_entries ADD COLUMN IF NOT EXISTS receipt_mime TEXT;
ALTER TABLE finance_entries ADD COLUMN IF NOT EXISTS installment_group UUID;
ALTER TABLE finance_entries ADD COLUMN IF NOT EXISTS installment_number INT;
ALTER TABLE finance_entries ADD COLUMN IF NOT EXISTS installments_total INT;
ALTER TABLE finance_entries ADD COLUMN IF NOT EXISTS event_id UUID REFERENCES events(id) ON DELETE SET NULL;
ALTER TABLE finance_entries ADD COLUMN IF NOT EXISTS destination TEXT;
ALTER TABLE finance_entries ADD COLUMN IF NOT EXISTS history JSONB NOT NULL DEFAULT '[]'::jsonb;
-- Vínculo do lançamento com o membro (usado no dízimo para saber quem é dizimista)
ALTER TABLE finance_entries ADD COLUMN IF NOT EXISTS member_id UUID REFERENCES members(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS finance_entries_member_idx ON finance_entries(member_id) WHERE member_id IS NOT NULL;

-- ============================================================
-- 17) CÉLULAS (pequenos grupos) — área do membro
-- ============================================================
CREATE TABLE IF NOT EXISTS cells (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL,
  leader_name   TEXT,
  weekday       TEXT,        -- ex: "Quinta"
  time          TEXT,        -- ex: "19:30"
  address       TEXT,
  neighborhood  TEXT,
  notes         TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE cells ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS cells_select ON cells;
CREATE POLICY cells_select ON cells FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS cells_write ON cells;
CREATE POLICY cells_write ON cells FOR ALL TO authenticated
  USING (my_role() IN ('super_admin','pastor','secretaria','administrativo'))
  WITH CHECK (my_role() IN ('super_admin','pastor','secretaria','administrativo'));
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE cells; EXCEPTION WHEN OTHERS THEN NULL; END $$;

ALTER TABLE members ADD COLUMN IF NOT EXISTS cell_id UUID REFERENCES cells(id) ON DELETE SET NULL;

-- Vincula o profile (login) a um registro de membro — habilita a área do membro
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS member_id UUID REFERENCES members(id) ON DELETE SET NULL;

-- Ensino: cursos/aulas já existem (seção 6). Garante colunas usadas pela UI nova.
ALTER TABLE lessons ADD COLUMN IF NOT EXISTS duration_min INT;

-- Não permite lançar a mesma nota do mesmo fornecedor duas vezes (saída).
CREATE UNIQUE INDEX IF NOT EXISTS finance_entries_invoice_unique
  ON finance_entries(supplier_id, invoice_number)
  WHERE supplier_id IS NOT NULL AND invoice_number IS NOT NULL AND type = 'saida';

-- Bucket privado para comprovantes de despesa (foto/PDF)
INSERT INTO storage.buckets (id, name, public)
VALUES ('receipts','receipts', false)
ON CONFLICT (id) DO NOTHING;

-- Storage policies do bucket receipts.
-- SELECT/INSERT: qualquer usuário autenticado com papel financeiro ou de liderança.
-- DELETE: só super_admin/pastor/financeiro (apagar comprovante é raro).
DROP POLICY IF EXISTS receipts_read ON storage.objects;
CREATE POLICY receipts_read ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'receipts');
DROP POLICY IF EXISTS receipts_insert ON storage.objects;
CREATE POLICY receipts_insert ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'receipts'
    AND (SELECT my_role()) IN ('super_admin','pastor','financeiro','secretaria','lider','administrativo'));
DROP POLICY IF EXISTS receipts_delete ON storage.objects;
CREATE POLICY receipts_delete ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'receipts'
    AND (SELECT my_role()) IN ('super_admin','pastor','financeiro'));

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- PRIMEIRO PASTOR (super_admin)
-- ------------------------------------------------------------
-- Passo 1: crie o usuário em Authentication → Users → Add user
--          (e-mail + senha do pastor).
-- Passo 2: troque o e-mail abaixo pelo mesmo e rode esta linha:
-- ============================================================
UPDATE profiles
   SET role = 'super_admin', active = true, name = 'Pastor'
 WHERE email = 'TROQUE_PELO_EMAIL_DO_PASTOR@exemplo.com';

-- ============================================================
-- 18) LÍDER EM MÚLTIPLOS DEPARTAMENTOS
--     Antes: profiles.department_id (um só). Agora: profiles.department_ids
--     (array). O department_id continua sendo o "principal" pra compat,
--     mas as políticas passam a considerar QUALQUER dept da lista.
-- ============================================================
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS department_ids JSONB NOT NULL DEFAULT '[]'::jsonb;

-- Retorna todos os departamentos do usuário logado (principal + secundários)
CREATE OR REPLACE FUNCTION my_departments() RETURNS JSONB
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(
    (SELECT
       CASE
         WHEN department_id IS NULL THEN COALESCE(department_ids, '[]'::jsonb)
         ELSE COALESCE(department_ids, '[]'::jsonb) || to_jsonb(department_id::text)
       END
     FROM profiles WHERE user_id = auth.uid() AND active = true LIMIT 1),
    '[]'::jsonb
  );
$$;

-- Testa se um department_id pertence ao usuário logado
CREATE OR REPLACE FUNCTION is_my_department(dept UUID) RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT dept IS NOT NULL AND my_departments() @> to_jsonb(dept::text);
$$;

-- Repõe RLS de membros com o novo helper (líder vê membros de qualquer dept que ele lidera)
DROP POLICY IF EXISTS members_select ON members;
CREATE POLICY members_select ON members FOR SELECT TO authenticated USING (
  my_role() IN ('super_admin','pastor','secretaria','financeiro','administrativo')
  OR (my_role() = 'lider' AND (
    is_my_department(department_id)
    OR EXISTS (
      SELECT 1 FROM jsonb_array_elements_text(COALESCE(department_ids, '[]'::jsonb)) x
      WHERE my_departments() @> to_jsonb(x)
    )
  ))
);

-- Repõe RLS de finanças (líder vê lançamentos de qualquer dept que ele lidera)
DROP POLICY IF EXISTS finance_select ON finance_entries;
CREATE POLICY finance_select ON finance_entries FOR SELECT TO authenticated USING (
  my_role() IN ('super_admin','financeiro','pastor')
  OR (my_role() = 'lider' AND is_my_department(department_id))
);
DROP POLICY IF EXISTS finance_write ON finance_entries;
CREATE POLICY finance_write ON finance_entries FOR ALL TO authenticated USING (
  my_role() IN ('super_admin','financeiro')
  OR (my_role() = 'lider' AND is_my_department(department_id))
) WITH CHECK (
  my_role() IN ('super_admin','financeiro')
  OR (my_role() = 'lider' AND is_my_department(department_id))
);

-- Repõe RLS de eventos
DROP POLICY IF EXISTS events_write ON events;
CREATE POLICY events_write ON events FOR ALL TO authenticated
  USING (my_role() IN ('super_admin','administrativo','pastor','lider_projetos','secretaria','midia')
         OR (my_role() = 'lider' AND (department_id IS NULL OR is_my_department(department_id))))
  WITH CHECK (my_role() IN ('super_admin','administrativo','pastor','lider_projetos','secretaria','midia')
              OR (my_role() = 'lider' AND (department_id IS NULL OR is_my_department(department_id))));

-- ============================================================
-- 21) FINANCE_WRITE — pastor e líder de projetos também escrevem
--     (necessário para o auto-post de despesas quando o pastor
--     bate o martelo do evento)
-- ============================================================
DROP POLICY IF EXISTS finance_write ON finance_entries;
CREATE POLICY finance_write ON finance_entries FOR ALL TO authenticated USING (
  my_role() IN ('super_admin','financeiro','pastor','lider_projetos')
  OR (my_role() = 'lider' AND is_my_department(department_id))
) WITH CHECK (
  my_role() IN ('super_admin','financeiro','pastor','lider_projetos')
  OR (my_role() = 'lider' AND is_my_department(department_id))
);

-- ============================================================
-- 20) LIDERANÇA — vice-líder por depto, foto do usuário, status "saiu"
-- ============================================================
ALTER TABLE departments ADD COLUMN IF NOT EXISTS vice_leader_profile_id UUID REFERENCES profiles(id) ON DELETE SET NULL;
ALTER TABLE profiles    ADD COLUMN IF NOT EXISTS photo_url TEXT;

ALTER TABLE members DROP CONSTRAINT IF EXISTS members_status_check;
ALTER TABLE members ADD CONSTRAINT members_status_check
  CHECK (status IN ('ativo','inativo','visitante','pendente','saiu'));

-- ============================================================
-- 19) EVENTOS: líder só vê eventos dos deptos que ele lidera
--     Antes: todos os autenticados liam todos os eventos.
-- ============================================================
DROP POLICY IF EXISTS events_select ON events;
CREATE POLICY events_select ON events FOR SELECT TO authenticated USING (
  my_role() IN ('super_admin','pastor','lider_projetos','financeiro','secretaria','administrativo','midia')
  OR (my_role() = 'lider' AND department_id IS NOT NULL AND is_my_department(department_id))
);

-- ============================================================
-- 22) PRESENÇA (attendance) — chamada de culto/célula/evento
--     Uma linha por membro presente numa data+tipo. Alimenta o
--     score de saúde do membro (frequência, última presença).
-- ============================================================
CREATE TABLE IF NOT EXISTS attendance (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id     UUID NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  date          DATE NOT NULL DEFAULT CURRENT_DATE,
  kind          TEXT NOT NULL DEFAULT 'culto'
                CHECK (kind IN ('culto','celula','evento','oracao','outro')),
  department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
  cell_id       UUID REFERENCES cells(id) ON DELETE SET NULL,
  event_id      UUID REFERENCES events(id) ON DELETE SET NULL,
  present       BOOLEAN NOT NULL DEFAULT true,
  note          TEXT,
  created_by    UUID REFERENCES profiles(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- Evita marcar a mesma pessoa duas vezes no mesmo dia/tipo/turma.
CREATE UNIQUE INDEX IF NOT EXISTS attendance_unique
  ON attendance(member_id, date, kind, COALESCE(cell_id, '00000000-0000-0000-0000-000000000000'::uuid), COALESCE(department_id, '00000000-0000-0000-0000-000000000000'::uuid));
CREATE INDEX IF NOT EXISTS attendance_member_idx ON attendance(member_id, date);
CREATE INDEX IF NOT EXISTS attendance_date_idx ON attendance(date);

ALTER TABLE attendance ENABLE ROW LEVEL SECURITY;
-- Leitura: staff vê tudo; líder vê presenças dos membros do seu depto.
DROP POLICY IF EXISTS attendance_select ON attendance;
CREATE POLICY attendance_select ON attendance FOR SELECT TO authenticated USING (
  my_role() IN ('super_admin','pastor','secretaria','financeiro','administrativo','lider_projetos')
  OR (my_role() = 'lider' AND (department_id IS NULL OR is_my_department(department_id)))
);
-- Escrita: staff e líder (líder só no próprio depto).
DROP POLICY IF EXISTS attendance_write ON attendance;
CREATE POLICY attendance_write ON attendance FOR ALL TO authenticated USING (
  my_role() IN ('super_admin','pastor','secretaria','administrativo')
  OR (my_role() = 'lider' AND (department_id IS NULL OR is_my_department(department_id)))
) WITH CHECK (
  my_role() IN ('super_admin','pastor','secretaria','administrativo')
  OR (my_role() = 'lider' AND (department_id IS NULL OR is_my_department(department_id)))
);
-- Leitura extra: o próprio membro (login vinculado via profiles.member_id)
-- pode ver a PRÓPRIA presença — alimenta a área do membro.
DROP POLICY IF EXISTS attendance_self_select ON attendance;
CREATE POLICY attendance_self_select ON attendance FOR SELECT TO authenticated USING (
  member_id IN (SELECT member_id FROM profiles WHERE user_id = auth.uid() AND member_id IS NOT NULL)
);
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE attendance; EXCEPTION WHEN OTHERS THEN NULL; END $$;

-- ============================================================
-- 23) PERFIL PRÓPRIO — usuário edita a própria foto (photo_url)
--     SEGURANÇA: um trigger impede que quem NÃO é super_admin altere
--     campos sensíveis (role, active, departamentos, user_id, email)
--     via auto-update. Assim a policy pode liberar o UPDATE do próprio
--     registro sem risco de escalonar privilégio.
-- ============================================================
CREATE OR REPLACE FUNCTION guard_profile_self_update() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  caller_role TEXT;
BEGIN
  SELECT role INTO caller_role FROM profiles WHERE user_id = auth.uid() AND active = true LIMIT 1;
  IF caller_role IS DISTINCT FROM 'super_admin' THEN
    -- Preserva os campos sensíveis: só nome/foto podem mudar no auto-update.
    NEW.role          := OLD.role;
    NEW.active        := OLD.active;
    NEW.department_id := OLD.department_id;
    NEW.department_ids:= OLD.department_ids;
    NEW.user_id       := OLD.user_id;
    NEW.email         := OLD.email;
    NEW.member_id     := OLD.member_id;
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_guard_profile_self_update ON profiles;
CREATE TRIGGER trg_guard_profile_self_update
  BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION guard_profile_self_update();

DROP POLICY IF EXISTS profiles_self_update ON profiles;
CREATE POLICY profiles_self_update ON profiles FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ============================================================
-- 24) MÓDULO DE CÉLULAS — cadastro completo, coordenador e
--     relatório pós-reunião (a fonte de dados mais rica do sistema)
-- ============================================================

-- 24.1 Papel "coordenador" (cuida de TODAS as células)
ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE profiles ADD CONSTRAINT profiles_role_check
  CHECK (role IN ('super_admin','pastor','lider_projetos','financeiro','secretaria',
                  'administrativo','lider','membro','midia','coordenador'));

-- 24.2 Cadastro completo da célula
ALTER TABLE cells ADD COLUMN IF NOT EXISTS leader_profile_id      UUID REFERENCES profiles(id) ON DELETE SET NULL;
ALTER TABLE cells ADD COLUMN IF NOT EXISTS vice_leader_profile_id UUID REFERENCES profiles(id) ON DELETE SET NULL;
ALTER TABLE cells ADD COLUMN IF NOT EXISTS host_name    TEXT;      -- anfitrião (dono da casa)
ALTER TABLE cells ADD COLUMN IF NOT EXISTS phone        TEXT;
ALTER TABLE cells ADD COLUMN IF NOT EXISTS cep          TEXT;
ALTER TABLE cells ADD COLUMN IF NOT EXISTS street       TEXT;
ALTER TABLE cells ADD COLUMN IF NOT EXISTS number       TEXT;
ALTER TABLE cells ADD COLUMN IF NOT EXISTS complement   TEXT;
ALTER TABLE cells ADD COLUMN IF NOT EXISTS city         TEXT;
ALTER TABLE cells ADD COLUMN IF NOT EXISTS state        TEXT;
ALTER TABLE cells ADD COLUMN IF NOT EXISTS lat          NUMERIC(10,7);
ALTER TABLE cells ADD COLUMN IF NOT EXISTS lng          NUMERIC(10,7);
ALTER TABLE cells ADD COLUMN IF NOT EXISTS active       BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE cells ADD COLUMN IF NOT EXISTS started_at   DATE;
ALTER TABLE cells ADD COLUMN IF NOT EXISTS capacity     INT;
ALTER TABLE cells ADD COLUMN IF NOT EXISTS department_id UUID REFERENCES departments(id) ON DELETE SET NULL;
ALTER TABLE cells ADD COLUMN IF NOT EXISTS color        TEXT DEFAULT 'violet';

-- 24.3 Relatório da reunião — 1 linha por encontro da célula
CREATE TABLE IF NOT EXISTS cell_meetings (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cell_id            UUID NOT NULL REFERENCES cells(id) ON DELETE CASCADE,
  date               DATE NOT NULL DEFAULT CURRENT_DATE,
  happened           BOOLEAN NOT NULL DEFAULT true,   -- false = não houve (com motivo)
  cancel_reason      TEXT,
  -- Presença agregada (o detalhe por membro vai em attendance)
  members_present    INT NOT NULL DEFAULT 0,
  members_expected   INT NOT NULL DEFAULT 0,
  -- Visitantes
  visitors_total     INT NOT NULL DEFAULT 0,
  visitors_baptized  INT NOT NULL DEFAULT 0,
  visitors_unbaptized INT NOT NULL DEFAULT 0,
  children_count     INT NOT NULL DEFAULT 0,
  -- Frutos
  decisions          INT NOT NULL DEFAULT 0,          -- decisões por Cristo
  baptism_requests   INT NOT NULL DEFAULT 0,
  reconciliations    INT NOT NULL DEFAULT 0,
  -- Conteúdo e vida
  theme              TEXT,
  had_communion      BOOLEAN NOT NULL DEFAULT false,
  had_offering       BOOLEAN NOT NULL DEFAULT false,
  offering_amount    NUMERIC(12,2),
  duration_min       INT,
  prayer_requests    TEXT,
  notes              TEXT,
  created_by         UUID REFERENCES profiles(id) ON DELETE SET NULL,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- Um relatório por célula por data
CREATE UNIQUE INDEX IF NOT EXISTS cell_meetings_unique ON cell_meetings(cell_id, date);
CREATE INDEX IF NOT EXISTS cell_meetings_date_idx ON cell_meetings(date);

-- 24.4 Helper: a célula é minha? (sou líder ou vice dela)
CREATE OR REPLACE FUNCTION is_my_cell(c UUID) RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM cells ce
    JOIN profiles p ON p.user_id = auth.uid() AND p.active = true
    WHERE ce.id = c AND (ce.leader_profile_id = p.id OR ce.vice_leader_profile_id = p.id)
  );
$$;

-- 24.5 RLS das células — coordenador entra como gestor pleno
DROP POLICY IF EXISTS cells_write ON cells;
CREATE POLICY cells_write ON cells FOR ALL TO authenticated
  USING (my_role() IN ('super_admin','pastor','secretaria','administrativo','coordenador')
         OR is_my_cell(id))
  WITH CHECK (my_role() IN ('super_admin','pastor','secretaria','administrativo','coordenador')
              OR is_my_cell(id));

-- 24.6 RLS dos relatórios
ALTER TABLE cell_meetings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS cell_meetings_select ON cell_meetings;
CREATE POLICY cell_meetings_select ON cell_meetings FOR SELECT TO authenticated USING (
  my_role() IN ('super_admin','pastor','secretaria','administrativo','coordenador','financeiro')
  OR is_my_cell(cell_id)
);
DROP POLICY IF EXISTS cell_meetings_write ON cell_meetings;
CREATE POLICY cell_meetings_write ON cell_meetings FOR ALL TO authenticated USING (
  my_role() IN ('super_admin','pastor','secretaria','administrativo','coordenador')
  OR is_my_cell(cell_id)
) WITH CHECK (
  my_role() IN ('super_admin','pastor','secretaria','administrativo','coordenador')
  OR is_my_cell(cell_id)
);
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE cell_meetings; EXCEPTION WHEN OTHERS THEN NULL; END $$;

-- 24.7 Presença de célula também pode ser escrita pelo líder da célula
DROP POLICY IF EXISTS attendance_write ON attendance;
CREATE POLICY attendance_write ON attendance FOR ALL TO authenticated USING (
  my_role() IN ('super_admin','pastor','secretaria','administrativo','coordenador')
  OR (my_role() = 'lider' AND (department_id IS NULL OR is_my_department(department_id)))
  OR (cell_id IS NOT NULL AND is_my_cell(cell_id))
) WITH CHECK (
  my_role() IN ('super_admin','pastor','secretaria','administrativo','coordenador')
  OR (my_role() = 'lider' AND (department_id IS NULL OR is_my_department(department_id)))
  OR (cell_id IS NOT NULL AND is_my_cell(cell_id))
);
DROP POLICY IF EXISTS attendance_select ON attendance;
CREATE POLICY attendance_select ON attendance FOR SELECT TO authenticated USING (
  my_role() IN ('super_admin','pastor','secretaria','financeiro','administrativo','lider_projetos','coordenador')
  OR (my_role() = 'lider' AND (department_id IS NULL OR is_my_department(department_id)))
  OR (cell_id IS NOT NULL AND is_my_cell(cell_id))
);

-- 24.8 Coordenador enxerga os membros (para gerir composição das células)
DROP POLICY IF EXISTS members_select ON members;
CREATE POLICY members_select ON members FOR SELECT TO authenticated USING (
  my_role() IN ('super_admin','pastor','secretaria','financeiro','administrativo','coordenador')
  OR (my_role() = 'lider' AND (
    is_my_department(department_id)
    OR EXISTS (
      SELECT 1 FROM jsonb_array_elements_text(COALESCE(department_ids, '[]'::jsonb)) x
      WHERE my_departments() @> to_jsonb(x)
    )
  ))
  OR EXISTS (SELECT 1 FROM cells ce WHERE ce.id = members.cell_id AND is_my_cell(ce.id))
);

-- ============================================================
-- 25) MINISTÉRIO INFANTIL — check-in seguro das crianças
--     Padrão dos sistemas de igreja: etiqueta com CÓDIGO DE
--     SEGURANÇA que precisa bater na retirada, alergias em
--     destaque, sala por faixa etária e número de chamada
--     ("pager") para acionar o responsável durante o culto.
-- ============================================================

-- 25.1 Salas por faixa etária
CREATE TABLE IF NOT EXISTS kids_rooms (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT NOT NULL,
  min_age    INT NOT NULL DEFAULT 0,
  max_age    INT NOT NULL DEFAULT 12,
  capacity   INT,
  color      TEXT DEFAULT 'sky',
  active     BOOLEAN NOT NULL DEFAULT true,
  position   INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 25.2 Crianças
CREATE TABLE IF NOT EXISTS kids (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name     TEXT NOT NULL,
  nickname      TEXT,
  birth_date    DATE,
  gender        TEXT CHECK (gender IN ('masculino','feminino') OR gender IS NULL),
  photo_url     TEXT,
  member_id     UUID REFERENCES members(id) ON DELETE SET NULL,
  allergies     TEXT,          -- aparece EM DESTAQUE na etiqueta
  medical_notes TEXT,
  special_needs TEXT,
  authorized_notes TEXT,       -- ex: "não pode ser retirado pelo pai"
  active        BOOLEAN NOT NULL DEFAULT true,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS kids_name_idx ON kids(full_name);

-- 25.3 Responsáveis autorizados
CREATE TABLE IF NOT EXISTS kid_guardians (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  kid_id       UUID NOT NULL REFERENCES kids(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  phone        TEXT,
  relationship TEXT,                                   -- mãe, pai, avó...
  can_pickup   BOOLEAN NOT NULL DEFAULT true,
  is_primary   BOOLEAN NOT NULL DEFAULT false,
  member_id    UUID REFERENCES members(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS kid_guardians_kid_idx ON kid_guardians(kid_id);
CREATE INDEX IF NOT EXISTS kid_guardians_phone_idx ON kid_guardians(phone);

-- 25.4 Check-ins (entrada e retirada)
CREATE TABLE IF NOT EXISTS kid_checkins (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  kid_id          UUID NOT NULL REFERENCES kids(id) ON DELETE CASCADE,
  room_id         UUID REFERENCES kids_rooms(id) ON DELETE SET NULL,
  date            DATE NOT NULL DEFAULT CURRENT_DATE,
  service         TEXT,                                -- culto/evento
  security_code   TEXT NOT NULL,                       -- precisa bater na retirada
  pager_number    INT,                                 -- número de chamada
  checkin_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  checkin_guardian TEXT,                               -- quem trouxe
  checkin_by      UUID REFERENCES profiles(id) ON DELETE SET NULL,
  checkout_at     TIMESTAMPTZ,
  checkout_guardian TEXT,                              -- quem retirou
  checkout_by     UUID REFERENCES profiles(id) ON DELETE SET NULL,
  status          TEXT NOT NULL DEFAULT 'presente' CHECK (status IN ('presente','retirado')),
  paged_at        TIMESTAMPTZ,                         -- responsável foi chamado
  page_reason     TEXT,
  notes           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS kid_checkins_date_idx ON kid_checkins(date, status);
CREATE INDEX IF NOT EXISTS kid_checkins_kid_idx ON kid_checkins(kid_id, date);

-- 25.5 RLS — equipe do infantil opera; líder também
ALTER TABLE kids_rooms   ENABLE ROW LEVEL SECURITY;
ALTER TABLE kids         ENABLE ROW LEVEL SECURITY;
ALTER TABLE kid_guardians ENABLE ROW LEVEL SECURITY;
ALTER TABLE kid_checkins ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['kids_rooms','kids','kid_guardians','kid_checkins'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I_select ON %I', t, t);
    EXECUTE format($f$CREATE POLICY %I_select ON %I FOR SELECT TO authenticated USING (
      my_role() IN ('super_admin','pastor','secretaria','administrativo','coordenador','lider','financeiro'))$f$, t, t);
    EXECUTE format('DROP POLICY IF EXISTS %I_write ON %I', t, t);
    EXECUTE format($f$CREATE POLICY %I_write ON %I FOR ALL TO authenticated USING (
      my_role() IN ('super_admin','pastor','secretaria','administrativo','lider')
    ) WITH CHECK (
      my_role() IN ('super_admin','pastor','secretaria','administrativo','lider'))$f$, t, t);
  END LOOP;
END $$;

DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE kids;          EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE kid_guardians; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE kids_rooms;    EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE kid_checkins;  EXCEPTION WHEN OTHERS THEN NULL; END $$;

-- 25.6 Salas padrão (só cria se ainda não houver nenhuma)
INSERT INTO kids_rooms (name, min_age, max_age, color, position)
SELECT * FROM (VALUES
  ('Berçário',        0, 2, 'rose',    1),
  ('Maternal',        3, 4, 'amber',   2),
  ('Jardim',          5, 6, 'emerald', 3),
  ('Kids',            7, 9, 'sky',     4),
  ('Pré-adolescentes',10,12,'violet',  5)
) AS v(name, min_age, max_age, color, position)
WHERE NOT EXISTS (SELECT 1 FROM kids_rooms);

-- ============================================================
-- 26) BATISMOS — fecha o ciclo do pedido que nasce na célula/culto
--     Jornada: solicitado → preparo (curso/entrevista) → agendado → batizado
-- ============================================================
CREATE TABLE IF NOT EXISTS baptism_candidates (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id      UUID REFERENCES members(id) ON DELETE SET NULL,
  name           TEXT NOT NULL,
  phone          TEXT,
  birth_date     DATE,
  source         TEXT NOT NULL DEFAULT 'celula'
                 CHECK (source IN ('celula','culto','evento','outro')),
  cell_id        UUID REFERENCES cells(id) ON DELETE SET NULL,
  requested_at   DATE NOT NULL DEFAULT CURRENT_DATE,
  status         TEXT NOT NULL DEFAULT 'solicitado'
                 CHECK (status IN ('solicitado','preparo','agendado','batizado','desistiu')),
  class_done     BOOLEAN NOT NULL DEFAULT false,   -- fez o curso/classe
  interview_done BOOLEAN NOT NULL DEFAULT false,   -- passou pela entrevista
  scheduled_date DATE,
  event_id       UUID REFERENCES events(id) ON DELETE SET NULL,
  baptized_at    DATE,
  notes          TEXT,
  created_by     UUID REFERENCES profiles(id) ON DELETE SET NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS baptism_status_idx ON baptism_candidates(status, requested_at);

ALTER TABLE baptism_candidates ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS baptism_select ON baptism_candidates;
CREATE POLICY baptism_select ON baptism_candidates FOR SELECT TO authenticated USING (
  my_role() IN ('super_admin','pastor','secretaria','administrativo','coordenador','lider')
);
DROP POLICY IF EXISTS baptism_write ON baptism_candidates;
CREATE POLICY baptism_write ON baptism_candidates FOR ALL TO authenticated USING (
  my_role() IN ('super_admin','pastor','secretaria','administrativo','coordenador')
  OR (cell_id IS NOT NULL AND is_my_cell(cell_id))
) WITH CHECK (
  my_role() IN ('super_admin','pastor','secretaria','administrativo','coordenador')
  OR (cell_id IS NOT NULL AND is_my_cell(cell_id))
);
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE baptism_candidates; EXCEPTION WHEN OTHERS THEN NULL; END $$;

-- Quando o candidato é marcado como batizado, atualiza a ficha do membro
CREATE OR REPLACE FUNCTION sync_member_baptism() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.status = 'batizado' AND NEW.member_id IS NOT NULL THEN
    UPDATE members
       SET baptized = true,
           baptism_date = COALESCE(NEW.baptized_at, CURRENT_DATE)
     WHERE id = NEW.member_id;
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_sync_member_baptism ON baptism_candidates;
CREATE TRIGGER trg_sync_member_baptism
  AFTER INSERT OR UPDATE OF status ON baptism_candidates
  FOR EACH ROW EXECUTE FUNCTION sync_member_baptism();

-- ============================================================
-- 27) MEMBROS — registro de saída e origem do cadastro
--     Saber QUANDO e POR QUE alguém saiu é dado pastoral, não só
--     um status. Também guarda como a pessoa entrou no sistema.
-- ============================================================
ALTER TABLE members ADD COLUMN IF NOT EXISTS exit_date   DATE;
ALTER TABLE members ADD COLUMN IF NOT EXISTS exit_reason TEXT;
ALTER TABLE members ADD COLUMN IF NOT EXISTS source      TEXT;  -- ex: 'importacao', 'cadastro publico'

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- Pronto! Os outros usuários (financeiro, secretaria, líderes)
-- você cria depois pelo próprio sistema, na aba "Usuários".
-- ============================================================

-- ============================================================
-- 28) ESCALA DE VOLUNTÁRIOS · PROGRESSO NO ENSINO · KIDS DO PAI
--     Três blocos independentes. Pode rodar este arquivo inteiro
--     de novo sem medo: tudo é IF NOT EXISTS / OR REPLACE.
-- ============================================================

-- 28.0 Helpers que faltavam
--      my_profile_id() → id do MEU profile (não o user_id do Auth)
--      my_member_id()  → id do meu registro em members (se vinculado)
CREATE OR REPLACE FUNCTION my_profile_id() RETURNS UUID
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT id FROM profiles WHERE user_id = auth.uid() AND active = true LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION my_member_id() RETURNS UUID
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT member_id FROM profiles WHERE user_id = auth.uid() AND active = true LIMIT 1;
$$;

-- ------------------------------------------------------------
-- 28.1 ESCALA DE VOLUNTÁRIOS
--      Uma linha = uma pessoa escalada para uma função, num dia,
--      dentro de um ministério. O voluntário confirma ou avisa
--      que não pode; o líder vê o buraco na hora.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS volunteer_slots (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  date          DATE NOT NULL,
  service       TEXT NOT NULL DEFAULT 'culto_noite',   -- culto_manha | culto_noite | evento | ensaio | outro
  department_id UUID REFERENCES departments(id) ON DELETE CASCADE,
  event_id      UUID REFERENCES events(id) ON DELETE SET NULL,
  role          TEXT NOT NULL,                          -- função: "Vocal", "Recepção porta 1", "Sala Maternal"
  member_id     UUID REFERENCES members(id) ON DELETE SET NULL,
  status        TEXT NOT NULL DEFAULT 'escalado'
                CHECK (status IN ('escalado','confirmado','recusado')),
  notes         TEXT,
  created_by    UUID REFERENCES profiles(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS volunteer_slots_date_idx   ON volunteer_slots(date);
CREATE INDEX IF NOT EXISTS volunteer_slots_member_idx ON volunteer_slots(member_id, date);
-- A mesma pessoa não entra duas vezes na mesma função, no mesmo culto
CREATE UNIQUE INDEX IF NOT EXISTS volunteer_slots_unique
  ON volunteer_slots(date, service, department_id, role, member_id)
  WHERE member_id IS NOT NULL;

ALTER TABLE volunteer_slots ENABLE ROW LEVEL SECURITY;

-- Leitura: todo mundo logado vê a escala (o voluntário precisa ver a dele,
-- e transparência de escala é o normal em igreja).
DROP POLICY IF EXISTS volunteer_slots_select ON volunteer_slots;
CREATE POLICY volunteer_slots_select ON volunteer_slots
  FOR SELECT TO authenticated USING (true);

-- Escrita: gestores + o líder DAQUELE ministério.
DROP POLICY IF EXISTS volunteer_slots_write ON volunteer_slots;
CREATE POLICY volunteer_slots_write ON volunteer_slots FOR ALL TO authenticated
USING (
  my_role() IN ('super_admin','pastor','secretaria','administrativo','coordenador')
  OR (my_role() = 'lider' AND department_id IS NOT NULL AND is_my_department(department_id))
) WITH CHECK (
  my_role() IN ('super_admin','pastor','secretaria','administrativo','coordenador')
  OR (my_role() = 'lider' AND department_id IS NOT NULL AND is_my_department(department_id))
);

-- O próprio voluntário confirma ou recusa a SUA escala (e nada mais).
-- O gatilho abaixo garante que ele só mexa no status.
DROP POLICY IF EXISTS volunteer_slots_self_update ON volunteer_slots;
CREATE POLICY volunteer_slots_self_update ON volunteer_slots FOR UPDATE TO authenticated
  USING (member_id IS NOT NULL AND member_id = my_member_id())
  WITH CHECK (member_id IS NOT NULL AND member_id = my_member_id());

CREATE OR REPLACE FUNCTION guard_volunteer_self_update() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- Gestores passam direto
  IF my_role() IN ('super_admin','pastor','secretaria','administrativo','coordenador') THEN
    RETURN NEW;
  END IF;
  IF NEW.member_id IS NOT NULL AND NEW.member_id = my_member_id() THEN
    -- voluntário só muda o próprio status
    NEW.date          := OLD.date;
    NEW.service       := OLD.service;
    NEW.department_id := OLD.department_id;
    NEW.event_id      := OLD.event_id;
    NEW.role          := OLD.role;
    NEW.member_id     := OLD.member_id;
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_guard_volunteer_self_update ON volunteer_slots;
CREATE TRIGGER trg_guard_volunteer_self_update
  BEFORE UPDATE ON volunteer_slots
  FOR EACH ROW EXECUTE FUNCTION guard_volunteer_self_update();

DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE volunteer_slots; EXCEPTION WHEN OTHERS THEN NULL; END $$;

-- ------------------------------------------------------------
-- 28.2 PROGRESSO NO ENSINO — "já assisti esta aula"
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS lesson_progress (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lesson_id    UUID NOT NULL REFERENCES lessons(id) ON DELETE CASCADE,
  profile_id   UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  completed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS lesson_progress_unique ON lesson_progress(lesson_id, profile_id);
CREATE INDEX IF NOT EXISTS lesson_progress_profile_idx ON lesson_progress(profile_id);

ALTER TABLE lesson_progress ENABLE ROW LEVEL SECURITY;

-- Cada um vê o próprio progresso; pastor/admin veem o de todos
-- (para saber quem está fazendo o discipulado).
DROP POLICY IF EXISTS lesson_progress_select ON lesson_progress;
CREATE POLICY lesson_progress_select ON lesson_progress FOR SELECT TO authenticated
  USING (profile_id = my_profile_id()
         OR my_role() IN ('super_admin','pastor','administrativo','secretaria'));

-- Marcar/desmarcar aula é só do próprio usuário.
DROP POLICY IF EXISTS lesson_progress_write ON lesson_progress;
CREATE POLICY lesson_progress_write ON lesson_progress FOR ALL TO authenticated
  USING (profile_id = my_profile_id())
  WITH CHECK (profile_id = my_profile_id());

DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE lesson_progress; EXCEPTION WHEN OTHERS THEN NULL; END $$;

-- ------------------------------------------------------------
-- 28.3 KIDS — o pai/mãe enxerga os PRÓPRIOS filhos
--      Até aqui só a equipe via a tabela kids. Estas policies são
--      ADICIONAIS (o Postgres soma as permissivas com OR), então
--      a equipe continua vendo tudo e o membro vê só os filhos
--      em que ele é responsável cadastrado.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION is_my_kid(k UUID) RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT my_member_id() IS NOT NULL AND (
    EXISTS (SELECT 1 FROM kids ki WHERE ki.id = k AND ki.member_id = my_member_id())
    OR EXISTS (SELECT 1 FROM kid_guardians g WHERE g.kid_id = k AND g.member_id = my_member_id())
  );
$$;

DROP POLICY IF EXISTS kids_select_own ON kids;
CREATE POLICY kids_select_own ON kids FOR SELECT TO authenticated USING (is_my_kid(id));

DROP POLICY IF EXISTS kid_guardians_select_own ON kid_guardians;
CREATE POLICY kid_guardians_select_own ON kid_guardians FOR SELECT TO authenticated USING (is_my_kid(kid_id));

DROP POLICY IF EXISTS kid_checkins_select_own ON kid_checkins;
CREATE POLICY kid_checkins_select_own ON kid_checkins FOR SELECT TO authenticated USING (is_my_kid(kid_id));

-- Nome da sala não é dado sensível — libera para todo mundo logado,
-- senão o pai vê o filho mas não sabe em que sala ele está.
DROP POLICY IF EXISTS kids_rooms_select_any ON kids_rooms;
CREATE POLICY kids_rooms_select_any ON kids_rooms FOR SELECT TO authenticated USING (true);

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- 29) ÁREA DO MEMBRO AMPLIADA + APP DO RESPONSÁVEL (KIDS)
--     + DISCIPULADO
--     Rode este bloco inteiro no SQL Editor do Supabase.
--     É idempotente: pode rodar de novo sem quebrar nada.
-- ============================================================

-- ------------------------------------------------------------
-- 29.1 O MEMBRO ENXERGA E EDITA A PRÓPRIA FICHA
--      Hoje o membro só aparecia na listagem se estivesse numa
--      célula. Agora ele sempre vê a PRÓPRIA linha, e pode
--      corrigir contato/endereço sem incomodar a secretaria.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS members_select_self ON members;
CREATE POLICY members_select_self ON members FOR SELECT TO authenticated
  USING (id = my_member_id());

DROP POLICY IF EXISTS members_update_self ON members;
CREATE POLICY members_update_self ON members FOR UPDATE TO authenticated
  USING (id = my_member_id())
  WITH CHECK (id = my_member_id());

-- Trava de segurança: o membro só muda contato, endereço e foto.
-- Estratégia "lista branca": parte-se de OLD e copiam-se apenas os
-- campos liberados. Coluna nova criada no futuro nasce congelada.
CREATE OR REPLACE FUNCTION guard_member_self_update() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE keep members%ROWTYPE;
BEGIN
  -- Equipe edita à vontade; a trava vale para quem está mexendo em si mesmo
  IF my_role() IN ('super_admin','pastor','secretaria','administrativo','coordenador','lider') THEN
    RETURN NEW;
  END IF;
  IF OLD.id IS DISTINCT FROM my_member_id() THEN
    RETURN NEW;
  END IF;
  keep := OLD;
  keep.phone              := NEW.phone;
  keep.home_phone         := NEW.home_phone;
  keep.email              := NEW.email;
  keep.photo_url          := NEW.photo_url;
  keep.cep                := NEW.cep;
  keep.street             := NEW.street;
  keep.address_number     := NEW.address_number;
  keep.address_complement := NEW.address_complement;
  keep.neighborhood       := NEW.neighborhood;
  keep.city               := NEW.city;
  keep.state              := NEW.state;
  keep.profession         := NEW.profession;
  keep.education          := NEW.education;
  keep.marital_status     := NEW.marital_status;
  keep.spouse_name        := NEW.spouse_name;
  keep.blood_type         := NEW.blood_type;
  keep.organ_donor        := NEW.organ_donor;
  NEW := keep;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_guard_member_self_update ON members;
CREATE TRIGGER trg_guard_member_self_update
  BEFORE UPDATE ON members
  FOR EACH ROW EXECUTE FUNCTION guard_member_self_update();

-- O membro precisa enxergar a própria célula (nome, dia, endereço)
-- e as presenças que a equipe registrou no nome dele.
DROP POLICY IF EXISTS attendance_select_self ON attendance;
CREATE POLICY attendance_select_self ON attendance FOR SELECT TO authenticated
  USING (member_id IS NOT NULL AND member_id = my_member_id());

-- ------------------------------------------------------------
-- 29.2 APP DO RESPONSÁVEL — PRÉ-CHECK-IN DO KIDS PELO CELULAR
--      O pai abre o app no carro/na fila, faz o pré-check-in e
--      chega no balcão com o código pronto. A equipe só confirma.
--      A criança NUNCA entra como "presente" pelo celular do pai:
--      quem confirma a chegada física é a equipe.
--      Fluxo: aguardando → presente → retirado  (ou cancelado)
-- ------------------------------------------------------------
ALTER TABLE kid_checkins DROP CONSTRAINT IF EXISTS kid_checkins_status_check;
ALTER TABLE kid_checkins ADD CONSTRAINT kid_checkins_status_check
  CHECK (status IN ('aguardando','presente','retirado','cancelado'));

ALTER TABLE kid_checkins ADD COLUMN IF NOT EXISTS self_checkin BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE kid_checkins ADD COLUMN IF NOT EXISTS confirmed_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS kid_checkins_pending_idx ON kid_checkins(date, status);

-- Gerador de código no servidor (alfabeto sem 0/O e 1/I).
-- O código do pré-check-in NÃO vem do celular do pai: quem gera é o banco.
CREATE OR REPLACE FUNCTION gen_kid_code() RETURNS TEXT
LANGUAGE plpgsql VOLATILE AS $$
DECLARE alfabeto TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        saida TEXT := '';
        i INT;
BEGIN
  FOR i IN 1..4 LOOP
    saida := saida || substr(alfabeto, 1 + floor(random() * length(alfabeto))::int, 1);
  END LOOP;
  RETURN saida;
END; $$;

-- Normaliza o pré-check-in feito pelo responsável
CREATE OR REPLACE FUNCTION guard_kid_self_checkin() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NEW.self_checkin THEN
    NEW.status        := 'aguardando';
    NEW.security_code := gen_kid_code();
    NEW.pager_number  := NULL;
    NEW.confirmed_at  := NULL;
    NEW.checkin_by    := my_profile_id();
    NEW.date          := CURRENT_DATE;
  END IF;
  -- Equipe confirmou a chegada → carimba a hora
  IF TG_OP = 'UPDATE' AND NEW.status = 'presente' AND OLD.status = 'aguardando' THEN
    NEW.confirmed_at := NOW();
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_guard_kid_self_checkin ON kid_checkins;
CREATE TRIGGER trg_guard_kid_self_checkin
  BEFORE INSERT OR UPDATE ON kid_checkins
  FOR EACH ROW EXECUTE FUNCTION guard_kid_self_checkin();

-- O responsável cria o pré-check-in do PRÓPRIO filho
DROP POLICY IF EXISTS kid_checkins_insert_guardian ON kid_checkins;
CREATE POLICY kid_checkins_insert_guardian ON kid_checkins FOR INSERT TO authenticated
  WITH CHECK (is_my_kid(kid_id) AND self_checkin = true);

-- ...e pode desistir enquanto a equipe não confirmou. Só isso.
DROP POLICY IF EXISTS kid_checkins_update_guardian ON kid_checkins;
CREATE POLICY kid_checkins_update_guardian ON kid_checkins FOR UPDATE TO authenticated
  USING (is_my_kid(kid_id) AND self_checkin = true AND status = 'aguardando')
  WITH CHECK (is_my_kid(kid_id) AND status = 'cancelado');

-- ------------------------------------------------------------
-- 29.3 DISCIPULADO — quem acompanha quem
--      Fecha o ciclo que já começa na célula e no batismo:
--      novo convertido → discipulador → encontros → integrado.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS discipleships (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  disciple_member_id  UUID NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  discipler_member_id UUID REFERENCES members(id) ON DELETE SET NULL,
  cell_id             UUID REFERENCES cells(id) ON DELETE SET NULL,
  stage               TEXT NOT NULL DEFAULT 'novo_convertido'
                      CHECK (stage IN ('novo_convertido','em_discipulado','pronto_batismo','integrado')),
  status              TEXT NOT NULL DEFAULT 'ativo'
                      CHECK (status IN ('ativo','concluido','pausado')),
  start_date          DATE NOT NULL DEFAULT CURRENT_DATE,
  end_date            DATE,
  goal                TEXT,                    -- objetivo combinado com a pessoa
  notes               TEXT,
  created_by          UUID REFERENCES profiles(id) ON DELETE SET NULL,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- Uma pessoa não tem dois discipulados ativos ao mesmo tempo
CREATE UNIQUE INDEX IF NOT EXISTS discipleships_active_unique
  ON discipleships(disciple_member_id) WHERE status = 'ativo';
CREATE INDEX IF NOT EXISTS discipleships_discipler_idx ON discipleships(discipler_member_id, status);
CREATE INDEX IF NOT EXISTS discipleships_cell_idx ON discipleships(cell_id);

CREATE TABLE IF NOT EXISTS discipleship_meetings (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  discipleship_id UUID NOT NULL REFERENCES discipleships(id) ON DELETE CASCADE,
  date            DATE NOT NULL DEFAULT CURRENT_DATE,
  topic           TEXT,                        -- lição / assunto do encontro
  notes           TEXT,
  prayer_requests TEXT,
  next_step       TEXT,
  attended        BOOLEAN NOT NULL DEFAULT true,
  created_by      UUID REFERENCES profiles(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS discipleship_meetings_idx ON discipleship_meetings(discipleship_id, date DESC);

ALTER TABLE discipleships          ENABLE ROW LEVEL SECURITY;
ALTER TABLE discipleship_meetings  ENABLE ROW LEVEL SECURITY;

-- Sou parte deste discipulado? (discipulado OU discipulador)
CREATE OR REPLACE FUNCTION is_my_discipleship(d UUID) RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT my_member_id() IS NOT NULL AND EXISTS (
    SELECT 1 FROM discipleships x
    WHERE x.id = d
      AND (x.disciple_member_id = my_member_id() OR x.discipler_member_id = my_member_id())
  );
$$;

-- Quem gerencia o discipulado da igreja
CREATE OR REPLACE FUNCTION is_discipleship_manager() RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT my_role() IN ('super_admin','pastor','secretaria','administrativo','coordenador','lider');
$$;

-- Leitura: gestores veem tudo; a pessoa vê o próprio; o discipulador vê os seus.
DROP POLICY IF EXISTS discipleships_select ON discipleships;
CREATE POLICY discipleships_select ON discipleships FOR SELECT TO authenticated
  USING (
    is_discipleship_manager()
    OR disciple_member_id = my_member_id()
    OR discipler_member_id = my_member_id()
  );

-- Escrita: gestores criam/remanejam. O discipulador atualiza o próprio caso.
DROP POLICY IF EXISTS discipleships_write ON discipleships;
CREATE POLICY discipleships_write ON discipleships FOR ALL TO authenticated
  USING (is_discipleship_manager() OR discipler_member_id = my_member_id())
  WITH CHECK (is_discipleship_manager() OR discipler_member_id = my_member_id());

-- O discipulado NÃO edita o próprio registro (nem muda de etapa sozinho):
-- quem conduz o processo é o discipulador. Por isso ele não entra no write.

-- Encontros: quem enxerga o discipulado enxerga os encontros.
DROP POLICY IF EXISTS discipleship_meetings_select ON discipleship_meetings;
CREATE POLICY discipleship_meetings_select ON discipleship_meetings FOR SELECT TO authenticated
  USING (is_discipleship_manager() OR is_my_discipleship(discipleship_id));

-- Registrar encontro: gestor ou o discipulador daquele par.
DROP POLICY IF EXISTS discipleship_meetings_write ON discipleship_meetings;
CREATE POLICY discipleship_meetings_write ON discipleship_meetings FOR ALL TO authenticated
  USING (
    is_discipleship_manager()
    OR EXISTS (SELECT 1 FROM discipleships x
               WHERE x.id = discipleship_id AND x.discipler_member_id = my_member_id())
  )
  WITH CHECK (
    is_discipleship_manager()
    OR EXISTS (SELECT 1 FROM discipleships x
               WHERE x.id = discipleship_id AND x.discipler_member_id = my_member_id())
  );

-- Quando o discipulado é marcado como concluído, carimba a data de fim
CREATE OR REPLACE FUNCTION stamp_discipleship_end() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'concluido' AND (OLD.status IS DISTINCT FROM 'concluido') AND NEW.end_date IS NULL THEN
    NEW.end_date := CURRENT_DATE;
  END IF;
  IF NEW.status = 'ativo' THEN
    NEW.end_date := NULL;
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_stamp_discipleship_end ON discipleships;
CREATE TRIGGER trg_stamp_discipleship_end
  BEFORE UPDATE ON discipleships
  FOR EACH ROW EXECUTE FUNCTION stamp_discipleship_end();

DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE discipleships;         EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE discipleship_meetings; EXCEPTION WHEN OTHERS THEN NULL; END $$;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- 30) TRAVAS DE VERDADE — no banco, não só na tela
--     Antes, evento aprovado e lançamento antigo eram protegidos
--     por uma senha escrita no JavaScript ("1234.9"). Qualquer um
--     que abrisse o "ver código-fonte" lia, e quem soubesse podia
--     alterar sem deixar rastro de quem foi.
--     Agora quem manda é o papel do usuário logado, verificado
--     no Postgres. A tela só evita o erro feio.
--     Idempotente: pode rodar de novo.
-- ============================================================

-- ------------------------------------------------------------
-- 30.1 FINANCEIRO — lançamento com mais de 30 dias está fechado
--      Só super_admin e pastor alteram ou apagam.
--      (LOCK_AFTER_DAYS no app = 30. Manter os dois iguais.)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION guard_finance_lock() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF my_role() IN ('super_admin','pastor') THEN
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  IF OLD.date IS NOT NULL AND OLD.date < CURRENT_DATE - 30 THEN
    RAISE EXCEPTION
      'Lançamento de % está fechado (mais de 30 dias). Só o pastor ou o administrador podem alterar ou apagar.',
      to_char(OLD.date, 'DD/MM/YYYY');
  END IF;

  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END; $$;

DROP TRIGGER IF EXISTS trg_guard_finance_lock ON finance_entries;
CREATE TRIGGER trg_guard_finance_lock
  BEFORE UPDATE OR DELETE ON finance_entries
  FOR EACH ROW EXECUTE FUNCTION guard_finance_lock();

-- ------------------------------------------------------------
-- 30.2 EVENTOS — travado depois que o Pastor aprova
--      CUIDADO: travar o evento inteiro quebraria o fluxo. Depois
--      da aprovação, Mídia (etapa 4), Análise (etapa 5) e
--      Encerramento (etapa 7) PRECISAM continuar gravando.
--      Então a trava congela ESCOPO E DINHEIRO, e deixa o fluxo
--      andar:
--        congelado → título, datas, hora, local, tipo, depto,
--                    orçamento, despesas, convidados, e o próprio
--                    estado de "travado"
--        liberado  → etapa atual, concluídas, histórico, comentários,
--                    anexos, relatório e entradas do encerramento
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION guard_event_lock() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF my_role() IN ('super_admin','pastor') THEN RETURN NEW; END IF;

  -- Evento ainda não travado: fluxo normal (inclusive o Pastor travando).
  IF NOT COALESCE((OLD.details->>'locked')::boolean, false) THEN RETURN NEW; END IF;

  IF (OLD.title, OLD.date, OLD.end_date, OLD.time, OLD.location,
      OLD.type, OLD.department_id, OLD.budget)
     IS DISTINCT FROM
     (NEW.title, NEW.date, NEW.end_date, NEW.time, NEW.location,
      NEW.type, NEW.department_id, NEW.budget)
  THEN
    RAISE EXCEPTION
      'Evento aprovado pelo Pastor: os dados do evento estão travados. Só o pastor ou o administrador podem alterar.';
  END IF;

  IF OLD.details->'expenses' IS DISTINCT FROM NEW.details->'expenses'
     OR OLD.details->'guests' IS DISTINCT FROM NEW.details->'guests'
  THEN
    RAISE EXCEPTION
      'Evento aprovado pelo Pastor: despesas e convidados estão travados. Só o pastor ou o administrador podem alterar.';
  END IF;

  -- Ninguém "destrava" por fora passando locked = false
  IF NOT COALESCE((NEW.details->>'locked')::boolean, false) THEN
    RAISE EXCEPTION
      'Só o pastor ou o administrador podem destravar um evento aprovado.';
  END IF;

  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_guard_event_lock ON events;
CREATE TRIGGER trg_guard_event_lock
  BEFORE UPDATE ON events
  FOR EACH ROW EXECUTE FUNCTION guard_event_lock();

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- 31) BACKUP AUTOMÁTICO SEMANAL
--     O plano free do Supabase NÃO tem backup automático. Até
--     aqui, a única proteção era alguém lembrar de clicar num
--     botão — com dados de membros, CRIANÇAS e finanças em jogo.
--
--     O que isto protege: exclusão acidental, UPDATE errado no
--     SQL Editor, bug do app. Ou seja, o risco real do dia a dia.
--     O que NÃO protege: perda do projeto Supabase inteiro — para
--     isso o snapshot precisa sair da plataforma (ver 31.4).
--
--     Fotos: ficam de fora do snapshot automático. São base64
--     dentro da linha e 6 snapshots com foto estouram os 500 MB
--     do plano free. Foto se reenvia; ficha de membro, não.
--     Idempotente: pode rodar de novo.
-- ============================================================

CREATE TABLE IF NOT EXISTS backups (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  kind        TEXT NOT NULL DEFAULT 'auto' CHECK (kind IN ('auto','manual')),
  taken_by    UUID REFERENCES profiles(id) ON DELETE SET NULL,
  row_counts  JSONB NOT NULL DEFAULT '{}'::jsonb,
  total_rows  INT  NOT NULL DEFAULT 0,
  size_bytes  BIGINT,
  with_photos BOOLEAN NOT NULL DEFAULT false,
  payload     JSONB NOT NULL
);
CREATE INDEX IF NOT EXISTS backups_created_idx ON backups(created_at DESC);

ALTER TABLE backups ENABLE ROW LEVEL SECURITY;

-- O payload ignora RLS (a função é SECURITY DEFINER): ele tem a igreja
-- inteira. Por isso a leitura é só de quem já pode ver tudo.
DROP POLICY IF EXISTS backups_select ON backups;
CREATE POLICY backups_select ON backups FOR SELECT TO authenticated
  USING (my_role() IN ('super_admin','pastor'));

DROP POLICY IF EXISTS backups_delete ON backups;
CREATE POLICY backups_delete ON backups FOR DELETE TO authenticated
  USING (my_role() = 'super_admin');

-- Ninguém insere direto: quem grava é a função make_backup().

-- ------------------------------------------------------------
-- 31.1 Despeja uma tabela em JSON, tirando colunas indesejadas.
--      Devolve [] se a tabela não existir — assim uma seção do
--      SQL que ainda não rodou não derruba o backup inteiro.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION dump_table(p_table TEXT, p_strip TEXT[] DEFAULT '{}')
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE res JSONB;
BEGIN
  IF to_regclass('public.' || p_table) IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  EXECUTE format('SELECT COALESCE(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) FROM %I t', p_table)
    INTO res;

  IF array_length(p_strip, 1) IS NOT NULL THEN
    SELECT COALESCE(jsonb_agg(x - p_strip), '[]'::jsonb) INTO res
    FROM jsonb_array_elements(res) x;
  END IF;

  RETURN res;
END; $$;

-- ------------------------------------------------------------
-- 31.2 Tira o snapshot
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION make_backup(p_kind TEXT DEFAULT 'auto', p_photos BOOLEAN DEFAULT false)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  sem      TEXT[] := CASE WHEN p_photos THEN '{}'::text[] ELSE ARRAY['photo_url'] END;
  dados    JSONB;
  contagem JSONB := '{}'::jsonb;
  chave    TEXT;
  total    INT := 0;
  novo     UUID;
BEGIN
  -- Backup manual: só pastor/admin. O automático roda pelo cron (sem usuário).
  IF p_kind = 'manual' AND my_role() IS DISTINCT FROM 'super_admin'
                       AND my_role() IS DISTINCT FROM 'pastor' THEN
    RAISE EXCEPTION 'Só o pastor ou o administrador podem gerar backup.';
  END IF;

  dados := jsonb_build_object(
    'departments',           dump_table('departments'),
    'members',               dump_table('members', sem),
    'profiles',              dump_table('profiles', sem),
    'cells',                 dump_table('cells'),
    'cell_meetings',         dump_table('cell_meetings'),
    'attendance',            dump_table('attendance'),
    'baptism_candidates',    dump_table('baptism_candidates'),
    'kids',                  dump_table('kids', sem),
    'kid_guardians',         dump_table('kid_guardians'),
    'kids_rooms',            dump_table('kids_rooms'),
    'kid_checkins',          dump_table('kid_checkins'),
    'finance_entries',       dump_table('finance_entries'),
    'suppliers',             dump_table('suppliers'),
    'events',                dump_table('events'),
    'event_messages',        dump_table('event_messages'),
    'courses',               dump_table('courses'),
    'lessons',               dump_table('lessons'),
    'lesson_progress',       dump_table('lesson_progress'),
    'volunteer_slots',       dump_table('volunteer_slots'),
    'discipleships',         dump_table('discipleships'),
    'discipleship_meetings', dump_table('discipleship_meetings')
  );

  FOR chave IN SELECT jsonb_object_keys(dados) LOOP
    contagem := contagem || jsonb_build_object(chave, jsonb_array_length(dados->chave));
    total := total + jsonb_array_length(dados->chave);
  END LOOP;

  INSERT INTO backups (kind, taken_by, row_counts, total_rows, size_bytes, with_photos, payload)
  VALUES (p_kind, my_profile_id(), contagem, total,
          octet_length(dados::text), p_photos, dados)
  RETURNING id INTO novo;

  -- Retenção: guarda os 6 automáticos mais recentes. Os manuais ficam
  -- (foi alguém que pediu de propósito), mas no máximo 3.
  DELETE FROM backups WHERE id IN (
    SELECT id FROM backups WHERE kind = 'auto'
    ORDER BY created_at DESC OFFSET 6
  );
  DELETE FROM backups WHERE id IN (
    SELECT id FROM backups WHERE kind = 'manual'
    ORDER BY created_at DESC OFFSET 3
  );

  RETURN novo;
END; $$;

REVOKE ALL ON FUNCTION make_backup(TEXT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION make_backup(TEXT, BOOLEAN) TO authenticated;
REVOKE ALL ON FUNCTION dump_table(TEXT, TEXT[]) FROM PUBLIC;

-- ------------------------------------------------------------
-- 31.3 Agenda: todo domingo às 03:00 (fuso do servidor, UTC).
--      Se o pg_cron não estiver disponível, o bloco avisa e o
--      resto continua valendo — o backup manual funciona igual.
-- ------------------------------------------------------------
DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_cron;
  BEGIN
    PERFORM cron.unschedule('advec-backup-semanal');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  PERFORM cron.schedule('advec-backup-semanal', '0 3 * * 0', $cron$SELECT make_backup('auto')$cron$);
  RAISE NOTICE 'Backup semanal agendado: domingos 03:00 UTC.';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron indisponivel (%). Ative em Database > Extensions e rode a secao 31.3 de novo.', SQLERRM;
END $$;

-- Primeiro snapshot agora, para não ficar uma semana sem nenhum
SELECT make_backup('auto');

-- ------------------------------------------------------------
-- 31.4 O QUE AINDA FALTA (fora do alcance do SQL)
--      Este snapshot vive DENTRO do mesmo banco. Se o projeto
--      Supabase for perdido, ele vai junto. Para backup de
--      verdade fora da plataforma, o pastor deve baixar o JSON
--      pela tela de Configurações de tempos em tempos — o app
--      avisa quando o último download passou de 30 dias.
-- ------------------------------------------------------------

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- 32) FECHANDO AS RLS QUE ESTAVAM "USING (true)"
--     Várias tabelas liberavam leitura para QUALQUER usuário
--     logado. Como o papel 'membro' também é autenticado, um
--     membro comum lia pela API coisas que a tela nunca mostrou.
--     Permissão que só existe na tela não é permissão.
--     Idempotente: pode rodar de novo.
-- ============================================================

-- Sou equipe (qualquer papel que não seja membro comum)?
CREATE OR REPLACE FUNCTION is_staff() RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(my_role(), 'membro') <> 'membro';
$$;

-- Este profile é de algum líder/vice de departamento ou célula?
-- SECURITY DEFINER de propósito: é usado DENTRO de uma policy, então
-- não pode esbarrar na RLS das tabelas que consulta.
CREATE OR REPLACE FUNCTION is_leader_profile(p UUID) RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM departments d
                 WHERE d.leader_profile_id = p OR d.vice_leader_profile_id = p)
      OR EXISTS (SELECT 1 FROM cells c
                 WHERE c.leader_profile_id = p OR c.vice_leader_profile_id = p);
$$;

-- ------------------------------------------------------------
-- 32.1 PROFILES — o membro via nome, e-mail e papel de TODO MUNDO
--      Agora vê: ele mesmo + quem lidera algo (a tela do membro
--      mostra o líder do departamento e da célula). A equipe
--      continua vendo todos.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS profiles_select ON profiles;
CREATE POLICY profiles_select ON profiles FOR SELECT TO authenticated
  USING (
    is_staff()
    OR user_id = auth.uid()
    OR is_leader_profile(id)
  );

-- ------------------------------------------------------------
-- 32.2 EVENT_MESSAGES — o chat interno das etapas do evento
--      Deliberação entre Pastor, Projetos e Mídia. O membro nunca
--      teve tela para isso, mas lia tudo pela API.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS messages_select ON event_messages;
CREATE POLICY messages_select ON event_messages FOR SELECT TO authenticated
  USING (is_staff());

-- ------------------------------------------------------------
-- 32.3 SUPPLIERS — fornecedores e contatos, assunto de tesouraria
-- ------------------------------------------------------------
DROP POLICY IF EXISTS suppliers_select ON suppliers;
CREATE POLICY suppliers_select ON suppliers FOR SELECT TO authenticated
  USING (is_staff());

-- ------------------------------------------------------------
-- 32.4 CELLS — o endereço da célula é a CASA de alguém
--      Um membro lia o endereço residencial de todos os
--      anfitriões da igreja. Agora vê só a própria célula.
--      (is_my_cell() não serve aqui: ela testa se sou LÍDER da
--      célula, não se participo dela.)
-- ------------------------------------------------------------
DROP POLICY IF EXISTS cells_select ON cells;
CREATE POLICY cells_select ON cells FOR SELECT TO authenticated
  USING (
    is_staff()
    OR is_my_cell(id)
    OR id = (SELECT m.cell_id FROM members m WHERE m.id = my_member_id())
  );

-- ------------------------------------------------------------
-- 32.5 COMPROVANTES FINANCEIROS (bucket receipts)
--      O comentário da seção 16 já dizia "papel financeiro ou de
--      liderança" — a policy de SELECT simplesmente não tinha a
--      checagem. Alinhando com a de INSERT.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS receipts_read ON storage.objects;
CREATE POLICY receipts_read ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'receipts'
    AND (SELECT my_role()) IN ('super_admin','pastor','financeiro','secretaria','lider','administrativo'));

-- ------------------------------------------------------------
-- 32.6 O QUE FICOU ABERTO DE PROPÓSITO
--      departments, courses, lessons → nome de ministério e
--        conteúdo de ensino; são para o membro ver mesmo.
--      volunteer_slots → transparência de escala é o normal em
--        igreja, e o voluntário precisa ver a dele.
--      kids_rooms → só o nome da sala; sem isso o pai vê o filho
--        e não sabe onde ele está.
--
--      AINDA EM ABERTO — events:
--      events_select continua USING (true) porque a tabela mistura
--      o que o membro PODE ver (título, data, local) com o que ele
--      NÃO deveria (budget, details.expenses, details.guests com
--      cachê de preletor). RLS filtra LINHA, não COLUNA, e todos os
--      papéis compartilham o mesmo role 'authenticated' do Postgres,
--      então GRANT por coluna também não separa.
--      A correção certa é uma view saneada para a área do membro
--      (agenda + início), o que exige mexer no useData. Fica como
--      item próprio, para não sair pela metade.
-- ------------------------------------------------------------

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- 33) DADOS DE DEMONSTRAÇÃO
--     O sistema está completo, mas o banco tem quase nada. Numa
--     demonstração isso aparece como "Nenhum registro" em toda
--     tela — dashboard sem gráfico, célula sem rede, Kids sem
--     criança. Este bloco cria uma igreja fictícia coerente.
--
--     Tudo o que for inserido fica registrado em `demo_seed`, e
--     limpar_demo() apaga exatamente isso — nada mais.
--
--     seed_demo()   → cria
--     limpar_demo() → remove
-- ============================================================

CREATE TABLE IF NOT EXISTS demo_seed (
  id         BIGSERIAL PRIMARY KEY,
  tabela     TEXT NOT NULL,
  row_id     UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE demo_seed ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demo_seed_select ON demo_seed;
CREATE POLICY demo_seed_select ON demo_seed FOR SELECT TO authenticated
  USING (my_role() = 'super_admin');

-- ------------------------------------------------------------
-- 33.0 CORREÇÃO nas travas da seção 30
--      As travas usavam só `my_role() IN ('super_admin','pastor')`.
--      No SQL Editor (e no cron) não há usuário logado, então
--      my_role() devolve NULL e a trava bloqueava até manutenção
--      administrativa legítima — inclusive limpar_demo().
--      Testar `auth.uid() IS NULL` é o certo: significa "não há JWT,
--      é contexto de serviço". Não vale usar my_role() IS NULL: um
--      usuário logado com perfil inativo também devolve NULL, e aí
--      seria um buraco.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION guard_finance_lock() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL OR my_role() IN ('super_admin','pastor') THEN
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;
  IF OLD.date IS NOT NULL AND OLD.date < CURRENT_DATE - 30 THEN
    RAISE EXCEPTION
      'Lançamento de % está fechado (mais de 30 dias). Só o pastor ou o administrador podem alterar ou apagar.',
      to_char(OLD.date, 'DD/MM/YYYY');
  END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END; $$;

CREATE OR REPLACE FUNCTION guard_event_lock() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL OR my_role() IN ('super_admin','pastor') THEN RETURN NEW; END IF;
  IF NOT COALESCE((OLD.details->>'locked')::boolean, false) THEN RETURN NEW; END IF;
  IF (OLD.title, OLD.date, OLD.end_date, OLD.time, OLD.location,
      OLD.type, OLD.department_id, OLD.budget)
     IS DISTINCT FROM
     (NEW.title, NEW.date, NEW.end_date, NEW.time, NEW.location,
      NEW.type, NEW.department_id, NEW.budget)
  THEN
    RAISE EXCEPTION 'Evento aprovado pelo Pastor: os dados do evento estão travados. Só o pastor ou o administrador podem alterar.';
  END IF;
  IF OLD.details->'expenses' IS DISTINCT FROM NEW.details->'expenses'
     OR OLD.details->'guests' IS DISTINCT FROM NEW.details->'guests'
  THEN
    RAISE EXCEPTION 'Evento aprovado pelo Pastor: despesas e convidados estão travados. Só o pastor ou o administrador podem alterar.';
  END IF;
  IF NOT COALESCE((NEW.details->>'locked')::boolean, false) THEN
    RAISE EXCEPTION 'Só o pastor ou o administrador podem destravar um evento aprovado.';
  END IF;
  RETURN NEW;
END; $$;

-- ------------------------------------------------------------
-- 33.1 LIMPAR — apaga só o que o seed criou, na ordem das FKs
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION limpar_demo() RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  t       TEXT;
  ordem   TEXT[] := ARRAY[
    'discipleship_meetings','discipleships','kid_checkins','kid_guardians','kids',
    'volunteer_slots','baptism_candidates','attendance','cell_meetings',
    'finance_entries','events','members','cells'];
  apagados INT := 0;
  n        INT;
BEGIN
  IF auth.uid() IS NOT NULL AND my_role() IS DISTINCT FROM 'super_admin' THEN
    RAISE EXCEPTION 'Só o administrador geral pode limpar os dados de demonstração.';
  END IF;

  FOREACH t IN ARRAY ordem LOOP
    EXECUTE format(
      'DELETE FROM %I WHERE id IN (SELECT row_id FROM demo_seed WHERE tabela = %L)', t, t);
    GET DIAGNOSTICS n = ROW_COUNT;
    apagados := apagados + n;
  END LOOP;

  DELETE FROM demo_seed;
  RETURN format('Demonstração removida: %s registros apagados.', apagados);
END; $$;

-- ------------------------------------------------------------
-- 33.2 SEED — cria a igreja fictícia
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION seed_demo() RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  nomes_m    TEXT[] := ARRAY['João','Pedro','Lucas','Mateus','Gabriel','Rafael','Tiago','André','Marcos','Felipe','Daniel','Bruno','Caio','Vitor','Samuel','Davi','Igor','Renato','Paulo','Sérgio'];
  nomes_f    TEXT[] := ARRAY['Maria','Ana','Beatriz','Juliana','Camila','Larissa','Fernanda','Patrícia','Renata','Aline','Bruna','Carla','Débora','Elaine','Priscila','Sara','Tatiane','Vanessa','Cristiane','Luciana'];
  sobrenomes TEXT[] := ARRAY['Silva','Santos','Oliveira','Souza','Pereira','Costa','Rodrigues','Almeida','Nascimento','Lima','Araújo','Ribeiro','Carvalho','Gomes','Martins','Rocha','Barbosa','Correia'];
  bairros    TEXT[] := ARRAY['Centro','Batel','Água Verde','Portão','Boqueirão','Cajuru','Santa Felicidade','Bacacheri','Rebouças','Xaxim'];
  ruas       TEXT[] := ARRAY['Rua das Flores','Av. Sete de Setembro','Rua XV de Novembro','Av. República Argentina','Rua Padre Anchieta','Av. Marechal Floriano','Rua Brigadeiro Franco'];
  cel_nomes  TEXT[] := ARRAY['Célula Centro','Célula Batel','Célula Água Verde','Célula Portão','Célula Boqueirão','Célula Bacacheri'];
  dias       TEXT[] := ARRAY['Segunda','Terça','Quarta','Quinta','Sexta','Sábado'];

  v_cells    UUID[] := '{}';
  v_members  UUID[] := '{}';
  v_kids     UUID[] := '{}';
  v_depts    UUID[] := '{}';
  v_events   UUID[] := '{}';
  v_disc     UUID[] := '{}';

  novo   UUID;
  i      INT;
  j      INT;
  perfil INT;
  sexo   TEXT;
  nome   TEXT;
  idade  INT;
  d      DATE;
  dom    DATE;
  mid    UUID;
  cid    UUID;
  enc    UUID;
  total  INT := 0;
BEGIN
  IF auth.uid() IS NOT NULL AND my_role() IS DISTINCT FROM 'super_admin' THEN
    RAISE EXCEPTION 'Só o administrador geral pode criar dados de demonstração.';
  END IF;
  IF EXISTS (SELECT 1 FROM demo_seed) THEN
    RAISE EXCEPTION 'Já existem dados de demonstração. Rode "SELECT limpar_demo();" antes.';
  END IF;

  PERFORM setseed(0.42);   -- reprodutível: rodar de novo dá a mesma igreja

  -- Departamentos: usa os que já existem. Se não houver nenhum, cria os
  -- padrão da ADVEC — esses são reais, então NÃO entram no demo_seed.
  SELECT array_agg(id) INTO v_depts FROM departments;
  IF v_depts IS NULL OR array_length(v_depts, 1) IS NULL THEN
    INSERT INTO departments (name, color)
    SELECT x.n, x.c FROM (VALUES
      ('Interligados Kids','amber'), ('Interligados','amber'), ('Jovens','violet'),
      ('Homens','amber'), ('Mulheres','amber'), ('Vencedores Renovados','amber'),
      ('Música','violet'), ('Acolhimento','amber'), ('Obreiros','sky')
    ) AS x(n, c);
    SELECT array_agg(id) INTO v_depts FROM departments;
  END IF;

  -- ---------- CÉLULAS ----------
  FOR i IN 1..6 LOOP
    INSERT INTO cells (name, weekday, time, address, neighborhood, city, state,
                       street, number, lat, lng, active, started_at, capacity, color, department_id)
    VALUES (cel_nomes[i], dias[1 + (i % 6)], '19:30',
            ruas[1 + (i % 7)] || ', ' || (100 + i * 37)::text,
            bairros[i], 'Curitiba', 'PR',
            ruas[1 + (i % 7)], (100 + i * 37)::text,
            -25.43 + (i * 0.012), -49.27 - (i * 0.010),
            true, CURRENT_DATE - (200 + i * 30), 15, 'violet',
            v_depts[1 + (i % array_length(v_depts, 1))])
    RETURNING id INTO novo;
    v_cells := v_cells || novo;
    INSERT INTO demo_seed (tabela, row_id) VALUES ('cells', novo);
    total := total + 1;
  END LOOP;

  -- ---------- MEMBROS ----------
  FOR i IN 1..54 LOOP
    sexo  := CASE WHEN i % 2 = 0 THEN 'masculino' ELSE 'feminino' END;
    nome  := CASE WHEN sexo = 'masculino'
                  THEN nomes_m[1 + (i % 20)] ELSE nomes_f[1 + (i % 20)] END
             || ' ' || sobrenomes[1 + (i % 18)];
    -- Idades espalhadas para acionar os ministérios automáticos
    idade  := CASE WHEN i % 9 = 0 THEN 15 + (i % 3)
                   WHEN i % 7 = 0 THEN 63 + (i % 5)
                   WHEN i % 3 = 0 THEN 20 + (i % 14)
                   ELSE 30 + (i % 25) END;
    cid    := v_cells[1 + (i % 6)];

    INSERT INTO members (
      full_name, gender, birth_date, phone, email, status, entry_date, baptized,
      baptism_date, cell_id, department_ids, cep, street, address_number,
      neighborhood, city, state, marital_status, profession, notes)
    VALUES (
      nome, sexo, CURRENT_DATE - (idade * 365 + (i * 7)),
      '4199' || lpad((100000 + i * 137)::text, 6, '0'),
      lower(split_part(nome, ' ', 1)) || i::text || '@exemplo.com',
      CASE WHEN i % 17 = 0 THEN 'visitante' ELSE 'ativo' END,
      CURRENT_DATE - CASE WHEN i % 11 = 0 THEN (i * 3) ELSE (300 + i * 12) END,
      (i % 5 <> 0),
      CASE WHEN i % 5 <> 0 THEN CURRENT_DATE - (200 + i * 9) ELSE NULL END,
      cid,
      jsonb_build_array((v_depts[1 + (i % array_length(v_depts, 1))])::text),
      '80' || lpad((i * 137 % 1000)::text, 3, '0') || '-000',
      ruas[1 + (i % 7)], (10 + i)::text, bairros[1 + (i % 10)], 'Curitiba', 'PR',
      CASE WHEN i % 3 = 0 THEN 'Casado(a)' ELSE 'Solteiro(a)' END,
      CASE WHEN i % 4 = 0 THEN 'Autônomo' WHEN i % 4 = 1 THEN 'Professor(a)'
           WHEN i % 4 = 2 THEN 'Comerciante' ELSE 'Analista' END,
      'Dados de demonstração')
    RETURNING id INTO mid;
    v_members := v_members || mid;
    INSERT INTO demo_seed (tabela, row_id) VALUES ('members', mid);
    total := total + 1;

    -- ---------- PRESENÇA: 14 semanas ----------
    -- 3 perfis para a "saúde do rebanho" mostrar as três cores
    perfil := i % 3;   -- 0 fiel · 1 regular · 2 afastado
    FOR j IN 0..13 LOOP
      dom := (CURRENT_DATE - (j * 7))::date;
      dom := dom - EXTRACT(DOW FROM dom)::int;   -- domingo daquela semana

      IF (perfil = 0 AND j % 8 <> 7)                    -- quase todo domingo
         OR (perfil = 1 AND j % 3 = 0)                  -- de vez em quando
         OR (perfil = 2 AND j >= 9 AND j % 4 = 0) THEN  -- só coisa antiga
        INSERT INTO attendance (member_id, date, kind, cell_id, present, note)
        VALUES (mid, dom, 'culto', NULL, true, 'demo')
        RETURNING id INTO novo;
        INSERT INTO demo_seed (tabela, row_id) VALUES ('attendance', novo);
        total := total + 1;
      END IF;

      IF perfil = 0 AND j % 2 = 0 THEN
        INSERT INTO attendance (member_id, date, kind, cell_id, present, note)
        VALUES (mid, dom + 3, 'celula', cid, true, 'demo')
        RETURNING id INTO novo;
        INSERT INTO demo_seed (tabela, row_id) VALUES ('attendance', novo);
        total := total + 1;
      END IF;
    END LOOP;
  END LOOP;

  -- Líder de cada célula = um dos membros
  FOR i IN 1..6 LOOP
    UPDATE cells SET leader_name = (SELECT full_name FROM members WHERE id = v_members[i * 3]),
                     host_name   = (SELECT full_name FROM members WHERE id = v_members[i * 3]),
                     phone       = (SELECT phone     FROM members WHERE id = v_members[i * 3])
    WHERE id = v_cells[i];
  END LOOP;

  -- ---------- RELATÓRIOS DE CÉLULA ----------
  FOR i IN 1..6 LOOP
    FOR j IN 0..7 LOOP
      INSERT INTO cell_meetings (cell_id, date, happened, members_present, members_expected,
                                 visitors_total, children_count, decisions, baptism_requests,
                                 theme, had_offering, offering_amount, duration_min, notes)
      VALUES (v_cells[i], CURRENT_DATE - (j * 7 + i), true,
              6 + ((i + j) % 5), 9, (j % 3), (j % 4),
              CASE WHEN (i + j) % 6 = 0 THEN 1 ELSE 0 END,
              CASE WHEN (i + j) % 7 = 0 THEN 1 ELSE 0 END,
              CASE j % 3 WHEN 0 THEN 'A videira e os ramos'
                         WHEN 1 THEN 'Fé que age' ELSE 'O bom pastor' END,
              true, round((35 + ((i * j) % 60))::numeric, 2), 90,
              'Encontro de demonstração')
      RETURNING id INTO novo;
      INSERT INTO demo_seed (tabela, row_id) VALUES ('cell_meetings', novo);
      total := total + 1;
    END LOOP;
  END LOOP;

  -- ---------- KIDS ----------
  FOR i IN 1..10 LOOP
    INSERT INTO kids (full_name, nickname, birth_date, gender, member_id,
                      allergies, special_needs, active)
    VALUES (
      CASE WHEN i % 2 = 0 THEN nomes_m[1 + (i % 20)] ELSE nomes_f[1 + (i % 20)] END
        || ' ' || sobrenomes[1 + (i % 18)],
      CASE WHEN i % 3 = 0 THEN nomes_m[1 + (i % 20)] ELSE NULL END,
      CURRENT_DATE - ((3 + (i % 8)) * 365 + i * 11),
      CASE WHEN i % 2 = 0 THEN 'masculino' ELSE 'feminino' END,
      v_members[i * 4],
      CASE WHEN i % 4 = 0 THEN 'Amendoim' WHEN i % 7 = 0 THEN 'Lactose' ELSE NULL END,
      CASE WHEN i % 9 = 0 THEN 'Usa aparelho auditivo' ELSE NULL END,
      true)
    RETURNING id INTO novo;
    v_kids := v_kids || novo;
    INSERT INTO demo_seed (tabela, row_id) VALUES ('kids', novo);
    total := total + 1;

    INSERT INTO kid_guardians (kid_id, name, phone, relationship, can_pickup, is_primary, member_id)
    SELECT novo, m.full_name, m.phone,
           CASE WHEN m.gender = 'feminino' THEN 'Mãe' ELSE 'Pai' END,
           true, true, m.id
    FROM members m WHERE m.id = v_members[i * 4]
    RETURNING id INTO novo;
    INSERT INTO demo_seed (tabela, row_id) VALUES ('kid_guardians', novo);
    total := total + 1;
  END LOOP;

  -- Check-ins dos últimos 3 domingos (já retirados) + alguns hoje
  FOR i IN 1..10 LOOP
    FOR j IN 1..3 LOOP
      dom := (CURRENT_DATE - (j * 7))::date;
      dom := dom - EXTRACT(DOW FROM dom)::int;
      IF (i + j) % 3 <> 0 THEN
        INSERT INTO kid_checkins (kid_id, room_id, date, service, security_code,
                                  pager_number, status, checkin_guardian, checkout_at)
        VALUES (v_kids[i],
                (SELECT id FROM kids_rooms ORDER BY position LIMIT 1 OFFSET (i % 3)),
                dom, 'Culto da manhã', gen_kid_code(), i, 'retirado',
                (SELECT name FROM kid_guardians WHERE kid_id = v_kids[i] LIMIT 1),
                dom + interval '2 hours')
        RETURNING id INTO novo;
        INSERT INTO demo_seed (tabela, row_id) VALUES ('kid_checkins', novo);
        total := total + 1;
      END IF;
    END LOOP;
  END LOOP;

  -- ---------- FINANCEIRO: 6 meses ----------
  FOR j IN 0..5 LOOP
    d := date_trunc('month', CURRENT_DATE - (j * 31))::date;
    FOR i IN 1..6 LOOP
      INSERT INTO finance_entries (type, amount, description, category, department_id, date)
      VALUES ('entrada',
              round((1800 + ((i * 37 + j * 91) % 2600))::numeric, 2),
              CASE i WHEN 1 THEN 'Dízimos do culto de domingo'
                     WHEN 2 THEN 'Oferta do culto de quarta'
                     WHEN 3 THEN 'Oferta missionária'
                     WHEN 4 THEN 'Dízimos — culto da noite'
                     WHEN 5 THEN 'Doação para o Kids'
                     ELSE 'Oferta especial' END,
              CASE WHEN i <= 2 THEN 'dizimo' ELSE 'oferta' END,
              v_depts[1 + ((i + j) % array_length(v_depts, 1))],
              d + (i * 4))
      RETURNING id INTO novo;
      INSERT INTO demo_seed (tabela, row_id) VALUES ('finance_entries', novo);
      total := total + 1;
    END LOOP;

    FOR i IN 1..5 LOOP
      INSERT INTO finance_entries (type, amount, description, category, department_id, date)
      VALUES ('saida',
              round((380 + ((i * 53 + j * 71) % 1500))::numeric, 2),
              CASE i WHEN 1 THEN 'Conta de energia elétrica'
                     WHEN 2 THEN 'Material de limpeza'
                     WHEN 3 THEN 'Manutenção do som'
                     WHEN 4 THEN 'Material do Kids'
                     ELSE 'Aluguel de equipamento' END,
              'despesa',
              v_depts[1 + ((i + j) % array_length(v_depts, 1))],
              d + (i * 5))
      RETURNING id INTO novo;
      INSERT INTO demo_seed (tabela, row_id) VALUES ('finance_entries', novo);
      total := total + 1;
    END LOOP;
  END LOOP;

  -- ---------- EVENTOS nas 7 etapas ----------
  FOR i IN 1..5 LOOP
    INSERT INTO events (title, description, date, time, location, department_id, type,
                        published, budget, details)
    VALUES (
      CASE i WHEN 1 THEN 'Conferência de Jovens 2026'
             WHEN 2 THEN 'Encontro de Casais'
             WHEN 3 THEN 'Culto de Batismo'
             WHEN 4 THEN 'Acampamento Kids'
             ELSE 'Seminário de Liderança' END,
      'Evento de demonstração do sistema.',
      CURRENT_DATE + (i * 12), '19:30',
      CASE WHEN i % 2 = 0 THEN 'Templo Sede' ELSE 'Chácara Betel' END,
      v_depts[1 + (i % array_length(v_depts, 1))],
      CASE i WHEN 1 THEN 'conferencia' WHEN 2 THEN 'evento' WHEN 3 THEN 'batismo'
             WHEN 4 THEN 'acampamento' ELSE 'seminario' END,
      (i <= 3), (2500 + i * 900)::numeric,
      jsonb_build_object(
        'current_stage', 'etapa' || LEAST(i + 1, 5)::text,
        'completed', (SELECT jsonb_agg('etapa' || g::text) FROM generate_series(1, i) g),
        'locked', (i >= 3),
        'programming', 'Abertura, louvor, ministração e encerramento.',
        'expenses', jsonb_build_array(
          jsonb_build_object('category','Estrutura','name','Som e iluminação','qty',1,'unit_value',1200),
          jsonb_build_object('category','Alimentação','name','Lanche','qty',80,'unit_value',18)),
        'history', jsonb_build_array(jsonb_build_object(
          'stage','etapa1','action','criou o evento','by','Demonstração','role','super_admin',
          'at', now()::text, 'note',''))))
    RETURNING id INTO novo;
    v_events := v_events || novo;
    INSERT INTO demo_seed (tabela, row_id) VALUES ('events', novo);
    total := total + 1;
  END LOOP;

  -- ---------- BATISMOS nas 5 situações ----------
  FOR i IN 1..8 LOOP
    INSERT INTO baptism_candidates (member_id, name, phone, birth_date, source, cell_id,
                                    requested_at, status, class_done, interview_done, scheduled_date)
    SELECT m.id, m.full_name, m.phone, m.birth_date, 'celula', m.cell_id,
           CURRENT_DATE - (i * 9),
           CASE WHEN i <= 2 THEN 'solicitado' WHEN i <= 4 THEN 'preparo'
                WHEN i <= 6 THEN 'agendado' ELSE 'batizado' END,
           (i > 2), (i > 3),
           CASE WHEN i BETWEEN 5 AND 6 THEN CURRENT_DATE + 20 ELSE NULL END
    FROM members m WHERE m.id = v_members[i * 5]
    RETURNING id INTO novo;
    INSERT INTO demo_seed (tabela, row_id) VALUES ('baptism_candidates', novo);
    total := total + 1;
  END LOOP;

  -- ---------- DISCIPULADO ----------
  FOR i IN 1..10 LOOP
    INSERT INTO discipleships (disciple_member_id, discipler_member_id, cell_id, stage,
                               status, start_date, goal)
    VALUES (v_members[i * 5 + 1],
            CASE WHEN i % 5 = 0 THEN NULL ELSE v_members[i * 2] END,
            v_cells[1 + (i % 6)],
            CASE WHEN i % 4 = 0 THEN 'integrado' WHEN i % 3 = 0 THEN 'pronto_batismo'
                 WHEN i % 2 = 0 THEN 'em_discipulado' ELSE 'novo_convertido' END,
            'ativo', CURRENT_DATE - (i * 21),
            'Concluir o curso de novos convertidos e ser batizado')
    RETURNING id INTO novo;
    v_disc := v_disc || novo;
    INSERT INTO demo_seed (tabela, row_id) VALUES ('discipleships', novo);
    total := total + 1;

    -- Alguns pares ficam sem encontro recente de propósito: é o alerta
    -- "sem encontro há 30d+" que o painel de gestão destaca.
    FOR j IN 1..(CASE WHEN i % 5 = 0 THEN 0 ELSE 3 END) LOOP
      INSERT INTO discipleship_meetings (discipleship_id, date, topic, notes, next_step, attended)
      VALUES (novo,
              CURRENT_DATE - (j * 14 + CASE WHEN i % 3 = 0 THEN 35 ELSE 2 END),
              CASE j WHEN 1 THEN 'Quem é Jesus' WHEN 2 THEN 'Arrependimento e fé'
                     ELSE 'Batismo nas águas' END,
              'Conversa boa, com dúvidas sobre oração e leitura bíblica.',
              'Ler o evangelho de João', true)
      RETURNING id INTO enc;
      INSERT INTO demo_seed (tabela, row_id) VALUES ('discipleship_meetings', enc);
      total := total + 1;
    END LOOP;
  END LOOP;

  -- ---------- ESCALA do próximo domingo ----------
  dom := CURRENT_DATE + (7 - EXTRACT(DOW FROM CURRENT_DATE)::int);
  FOR i IN 1..12 LOOP
    INSERT INTO volunteer_slots (date, service, department_id, role, member_id, status)
    VALUES (dom, CASE WHEN i % 2 = 0 THEN 'culto_manha' ELSE 'culto_noite' END,
            v_depts[1 + (i % array_length(v_depts, 1))],
            CASE i % 6 WHEN 0 THEN 'Recepção porta 1' WHEN 1 THEN 'Vocal'
                       WHEN 2 THEN 'Sala Maternal'    WHEN 3 THEN 'Projeção'
                       WHEN 4 THEN 'Mesa de som'      ELSE 'Diaconia' END,
            v_members[i * 3],
            CASE WHEN i % 3 = 0 THEN 'confirmado' WHEN i % 7 = 0 THEN 'recusado' ELSE 'escalado' END)
    RETURNING id INTO novo;
    INSERT INTO demo_seed (tabela, row_id) VALUES ('volunteer_slots', novo);
    total := total + 1;
  END LOOP;

  RETURN format('Demonstração criada: %s registros (54 membros, 6 células, 10 crianças, 66 lançamentos, 5 eventos, 10 discipulados).', total);
END; $$;

REVOKE ALL ON FUNCTION seed_demo()   FROM PUBLIC;
REVOKE ALL ON FUNCTION limpar_demo() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION seed_demo()   TO authenticated;
GRANT EXECUTE ON FUNCTION limpar_demo() TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- 34) CORREÇÃO: recursão infinita na policy de `cells`
--     Erro: infinite recursion detected in policy for relation "cells"
--
--     A seção 32 fechou cells_select assim:
--        OR id = (SELECT m.cell_id FROM members m WHERE m.id = my_member_id())
--     Essa subconsulta roda como o usuário logado, então dispara a
--     RLS de `members`. E members_select (seção 24.8) faz:
--        OR EXISTS (SELECT 1 FROM cells ce WHERE ... is_my_cell(ce.id))
--     que dispara a RLS de `cells` de volta. Laço fechado.
--
--     Antes da 32 isso não aparecia porque cells_select era
--     USING (true) — não avaliava nada. Fechar a política criou
--     o ciclo.
--
--     Correção: a consulta a `members` passa a morar numa função
--     SECURITY DEFINER, que roda como dona da tabela e portanto
--     não aciona a RLS de `members`. O laço se rompe sem afrouxar
--     permissão nenhuma.
-- ============================================================

CREATE OR REPLACE FUNCTION is_my_member_cell(c UUID) RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT c IS NOT NULL AND EXISTS (
    SELECT 1 FROM members m
    WHERE m.id = my_member_id() AND m.cell_id = c
  );
$$;

DROP POLICY IF EXISTS cells_select ON cells;
CREATE POLICY cells_select ON cells FOR SELECT TO authenticated
  USING (
    is_staff()               -- equipe vê todas
    OR is_my_cell(id)        -- sou líder/vice desta célula
    OR is_my_member_cell(id) -- participo desta célula
  );

NOTIFY pgrst, 'reload schema';
