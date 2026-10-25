-- SOCORRO 2: o banco está bem, mas o PostgREST (que entrega os dados ao site) não consegue ler o banco.
-- Só olha, não muda nada. Rode tudo e mande o print de CADA resultado (use as abas de resultado).

-- 1) O usuário que o PostgREST usa para entrar no banco está normal?
SELECT rolname, rolcanlogin, rolconfig FROM pg_roles WHERE rolname IN ('authenticator', 'anon', 'authenticated', 'service_role');

-- 2) Quantas conexões do PostgREST e em que estado
SELECT usename, application_name, state, count(*) FROM pg_stat_activity
WHERE datname = current_database() GROUP BY 1, 2, 3 ORDER BY 4 DESC;

-- 3) Configuração do PostgREST guardada no banco
SELECT rolname, unnest(rolconfig) AS config FROM pg_roles WHERE rolname = 'authenticator';
