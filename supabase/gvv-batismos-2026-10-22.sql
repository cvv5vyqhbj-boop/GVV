-- GVV · Batismos (2026-10-22, parte 3) · rodar DEPOIS de gvv-batismo-id-2026-10-22.sql
-- A administração marca a data do próximo batismo. Quem optou pelo batismo no relatório
-- do líder entra na fila; no dia, marca-se quem batizou, quem não batizou e o acompanhamento.
BEGIN;

CREATE TABLE IF NOT EXISTS public.gvv_baptism_dates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  date date NOT NULL UNIQUE,
  place text NOT NULL DEFAULT '',
  notes text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.gvv_baptism_dates ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS gvv_baptism_dates_read ON public.gvv_baptism_dates;
CREATE POLICY gvv_baptism_dates_read ON public.gvv_baptism_dates FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS gvv_baptism_dates_admin ON public.gvv_baptism_dates;
CREATE POLICY gvv_baptism_dates_admin ON public.gvv_baptism_dates FOR ALL TO authenticated
  USING (public.my_role() IN ('super_admin','pastor','secretaria','administrativo'))
  WITH CHECK (public.my_role() IN ('super_admin','pastor','secretaria','administrativo'));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.gvv_baptism_dates TO authenticated;
REVOKE ALL ON public.gvv_baptism_dates FROM anon;

CREATE TABLE IF NOT EXISTS public.gvv_baptism_people (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  connection_id uuid NOT NULL REFERENCES public.gvv_connections(id) ON DELETE CASCADE,
  report_id uuid REFERENCES public.gvv_reports(id) ON DELETE SET NULL,
  full_name text NOT NULL CHECK (char_length(btrim(full_name)) BETWEEN 2 AND 120),
  phone text NOT NULL DEFAULT '',
  baptism_date_id uuid REFERENCES public.gvv_baptism_dates(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'aguardando' CHECK (status IN ('aguardando','batizou','nao_batizou','desistiu')),
  followup text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS gvv_baptism_people_conn ON public.gvv_baptism_people(connection_id);
CREATE UNIQUE INDEX IF NOT EXISTS gvv_baptism_people_unique ON public.gvv_baptism_people(connection_id, lower(btrim(full_name)));
ALTER TABLE public.gvv_baptism_people ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS gvv_baptism_people_manage ON public.gvv_baptism_people;
CREATE POLICY gvv_baptism_people_manage ON public.gvv_baptism_people FOR ALL TO authenticated
  USING (public.gvv_can_manage(connection_id)) WITH CHECK (public.gvv_can_manage(connection_id));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.gvv_baptism_people TO authenticated;
REVOKE ALL ON public.gvv_baptism_people FROM anon;

NOTIFY pgrst, 'reload schema';
COMMIT;
