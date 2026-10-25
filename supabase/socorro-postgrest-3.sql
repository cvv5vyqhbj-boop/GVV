-- SOCORRO 3: dá mais tempo para o PostgREST ler o banco (padrão do Supabase é 8 segundos).
-- O sistema GVV tem muitas tabelas e funções; num servidor NANO lento a leitura passa de 8 s e o site cai.
ALTER ROLE authenticator SET statement_timeout = '60s';
NOTIFY pgrst, 'reload config';
NOTIFY pgrst, 'reload schema';
