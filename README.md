# Sistema GVV — ADVEC Curitiba

Sistema separado, só da rede de GVVs, com **banco próprio**: Supabase `ctchnsskqaouihvdjlhv`
(não usa o banco nem os logins do ADVEC). Site: https://gvvadveccuritiba.netlify.app

## Área pública (sem login)
- `/` — tela inicial: **Quero fazer parte de um GVV**, **Ver GVVs perto de mim**, **Login supervisor**, e **Login ADM** (pequeno, canto direito).
- `/participar` — formulário "Faça parte de um GVV" (nome, telefone, idade, estado civil, sexo, membro, endereço/CEP, número).
- `/mapa` — só o mapa. Busca por CEP ou "Perto de mim" (GPS). Mostra GVVs mais próximos com distância.
  Localização aproximada (~150 m), sem endereço nem anfitrião.

Identidade: PDF "IDENTIDADE GVV" — azul #2B77E4, lima #C1ED28, creme #F9F4EB, preto.
Fontes: Arlen → Anton (web), Helvetica Now Display → Inter Tight (web).

## Área logada
- **GVVs** — rede, candidatos, avaliação, conexão líder × anfitrião pelo mapa, criação de GVV.
- **Mapa · visão geral** — todos os GVVs ativos no mapa.
- **Interessados** — quem preencheu o formulário: WhatsApp, etapa, encaminhar para um GVV, copiar links.
- **Meu GVV** — visão do membro/líder sobre o próprio GVV.

## Deploy (Netlify)
Sem build. Publica a pasta inteira (`netlify.toml` → `publish = "."`).
1. Netlify → Add new site → Deploy manually → arrastar esta pasta `gvv-sistema`.
   (ou criar repositório próprio no GitHub e ligar no Netlify).
2. Supabase → Authentication → URL Configuration: adicionar o domínio novo
   em **Redirect URLs** (para login por e-mail/recuperar senha funcionar).

## Banco novo (primeira vez)
1. Supabase → Authentication → Users → Add user (seu e-mail + senha, "Auto Confirm User").
2. SQL Editor → New query → colar `supabase/GVV_BANCO_NOVO.sql` inteiro → Run.
   Cria tudo vazio e transforma esse usuário em ADM geral.
3. Authentication → URL Configuration → Site URL `https://gvvadveccuritiba.netlify.app`
   e Redirect URLs `https://gvvadveccuritiba.netlify.app/**`.

## SQL (histórico, banco antigo)
**Rodar uma vez:** `supabase/gvv-publico-2026-10-18.sql` (Supabase → SQL Editor).
Cria a tabela `gvv_interests` + funções `gvv_submit_interest` e `gvv_public_map`.
Sem isso o formulário não envia e o mapa público fica vazio.
As outras migrações `supabase/gvv-*.sql` já estão aplicadas.

## Observação
Código copiado do `advec-sistema` em 2026-10-18. Correções feitas lá não aparecem aqui
automaticamente (e vice-versa).
