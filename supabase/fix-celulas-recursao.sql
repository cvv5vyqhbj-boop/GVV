-- ============================================================
-- CORREÇÃO: "infinite recursion detected in policy for relation cells"
--
-- Rode este arquivo INTEIRO no Supabase → SQL Editor → Run.
-- Pode rodar mais de uma vez sem problema.
--
-- Causa: a policy de leitura de `cells` consultava `members` direto,
-- e a policy de `members` consulta `cells` de volta → laço.
-- Aqui toda consulta cruzada passa por funções SECURITY DEFINER,
-- que não acionam RLS, então o laço não existe mais.
-- (É a mesma correção da seção 34 do SUPABASE_SETUP.sql, mas
--  apagando antes QUALQUER policy antiga de cells — inclusive as
--  criadas pelo painel do Supabase.)
-- ============================================================

-- 1) Funções auxiliares (todas SECURITY DEFINER)
CREATE OR REPLACE FUNCTION is_my_cell(c UUID) RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM cells ce
    JOIN profiles p ON p.user_id = auth.uid() AND p.active = true
    WHERE ce.id = c AND (ce.leader_profile_id = p.id OR ce.vice_leader_profile_id = p.id)
  );
$$;

CREATE OR REPLACE FUNCTION is_my_member_cell(c UUID) RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT c IS NOT NULL AND EXISTS (
    SELECT 1 FROM members m
    WHERE m.id = my_member_id() AND m.cell_id = c
  );
$$;

-- 2) Apaga todas as policies existentes de cells (qualquer nome)
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'cells' LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.cells', pol.policyname);
  END LOOP;
END $$;

ALTER TABLE cells ENABLE ROW LEVEL SECURITY;

-- 3) Leitura: equipe vê todas; líder/vice vê as dele; membro vê a própria
CREATE POLICY cells_select ON cells FOR SELECT TO authenticated
  USING (
    is_staff()
    OR is_my_cell(id)
    OR is_my_member_cell(id)
  );

-- 4) Escrita: gestores de célula, ou líder/vice da própria célula
CREATE POLICY cells_write ON cells FOR ALL TO authenticated
  USING (my_role() IN ('super_admin','pastor','secretaria','administrativo','coordenador')
         OR is_my_cell(id))
  WITH CHECK (my_role() IN ('super_admin','pastor','secretaria','administrativo','coordenador')
              OR is_my_cell(id));

NOTIFY pgrst, 'reload schema';

-- Conferência (deve listar só cells_select e cells_write):
SELECT policyname, cmd FROM pg_policies WHERE schemaname = 'public' AND tablename = 'cells';
