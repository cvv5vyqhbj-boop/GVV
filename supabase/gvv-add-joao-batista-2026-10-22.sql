-- Cadastro manual: João Batista da Silva Júnior (anfitrião, Adultos → Misto). Rodar no SQL Editor.
-- Não duplica se o mesmo WhatsApp já existir. CPF não é guardado (o sistema não usa).
INSERT INTO public.gvv_candidates (
  import_key, name, kind, network, audience, leader_status, host_status,
  address, cep, neighborhood, city, reference_point, phone, email, birth_date, sex, marital_status,
  member_since, residence_type, fits_15, capacity, days, shifts, availability,
  host_lat, host_lng, approx_lat, approx_lng, origin_list, source_text, review_notes)
SELECT 'manual-joao-batista-41996409426', 'João Batista da Silva Júnior', 'host', 'misto', 'Adultos', 'pending', 'approved',
  'Rua Desembargador Westphalen, 3000, Parolin, Curitiba, CEP 80220-031', '80220-031', 'Parolin', 'Curitiba',
  'Oficina Premium Car Importados', '(41) 99640-9426', 'evolucaoj77@gmail.com', '1989-04-04', 'Masculino', 'Casado(a)',
  'De 3 a 5 anos', 'Local de Trabalho', true, 15, 'Quarta', 'Noite', 'Quarta · Noite',
  -25.4578919, -49.2612847, -25.4578919, -49.2612847, 'Cadastro manual', '', ''
WHERE NOT EXISTS (SELECT 1 FROM public.gvv_candidates WHERE regexp_replace(phone, '\D', '', 'g') IN ('41996409426', '5541996409426'));

SELECT name, kind, network, house_no, network_no, address FROM public.gvv_candidates WHERE regexp_replace(phone, '\D', '', 'g') IN ('41996409426','5541996409426');
