-- Relatório do líder: lista de visitantes com nome e WhatsApp (2026-10-22).
BEGIN;
ALTER TABLE public.gvv_reports ADD COLUMN IF NOT EXISTS visitor_list jsonb NOT NULL DEFAULT '[]'::jsonb;
NOTIFY pgrst, 'reload schema';
COMMIT;
