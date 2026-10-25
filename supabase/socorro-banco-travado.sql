-- SOCORRO: site sem dados (erro PGRST002 "Could not query the database for the schema cache").
-- O SQL Editor fala direto com o banco, então funciona mesmo com o site fora.

-- PASSO 1 (só olha, não muda nada): conexões presas há muito tempo e quem está bloqueando.
SELECT pid, usename, state, now() - xact_start AS ha_quanto_tempo, wait_event_type, wait_event,
       pg_blocking_pids(pid) AS bloqueado_por, left(query, 150) AS consulta
FROM pg_stat_activity
WHERE datname = current_database() AND pid <> pg_backend_pid() AND state <> 'idle'
ORDER BY xact_start NULLS LAST;

-- PASSO 2 (destrava): encerra transações abertas há mais de 5 minutos e reinicia o cache do site.
-- Só desfaz operações que já estavam travadas; não apaga dados salvos.
-- Para rodar: selecione só as 3 linhas abaixo e clique em Run.
-- SELECT pg_terminate_backend(pid) FROM pg_stat_activity
--  WHERE datname = current_database() AND pid <> pg_backend_pid() AND xact_start < now() - interval '5 minutes';
-- NOTIFY pgrst, 'reload schema';
