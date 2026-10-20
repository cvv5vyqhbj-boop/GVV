-- Conserta acentos quebrados (Boqueir√£o -> Boqueirão) nos cadastros GVV.
CREATE OR REPLACE FUNCTION pg_temp.fix_acentos(x text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(x, '√°', 'á'), '√†', 'à'), '√¢', 'â'), '√£', 'ã'), '√§', 'ä'), '√©', 'é'), '√™', 'ê'), '√®', 'è'), '√´', 'ë'), '√≠', 'í'), '√¨', 'ì'), '√Æ', 'î'), '√Ø', 'ï'), '√≥', 'ó'), '√≤', 'ò'), '√¥', 'ô'), '√µ', 'õ'), '√∂', 'ö'), '√∫', 'ú'), '√π', 'ù'), '√ª', 'û'), '√º', 'ü'), '√ß', 'ç'), '√±', 'ñ'), '√Å', 'Á'), '√Ä', 'À'), '√Ç', 'Â'), '√É', 'Ã'), '√Ñ', 'Ä'), '√â', 'É'), '√ä', 'Ê'), '√à', 'È'), '√ç', 'Í'), '√ì', 'Ó'), '√î', 'Ô'), '√ï', 'Õ'), '√ñ', 'Ö'), '√ö', 'Ú'), '√ú', 'Ü'), '√á', 'Ç'), '√ë', 'Ñ'), '¬∑', '·'), '¬∫', 'º'), '¬™', 'ª'), '¬∞', '°'), '‚Äì', '–'), '‚Äî', '—'), '‚Äú', '“'), '‚Äù', '”'), '‚Äò', '‘'), '‚Äô', '’'), '‚Ä¶', '…')
$$;
UPDATE public.gvv_candidates SET
  name = pg_temp.fix_acentos(name),
  address = pg_temp.fix_acentos(address),
  home_address = pg_temp.fix_acentos(home_address),
  audience = pg_temp.fix_acentos(audience),
  availability = pg_temp.fix_acentos(availability),
  review_notes = pg_temp.fix_acentos(review_notes),
  source_text = pg_temp.fix_acentos(source_text),
  neighborhood = pg_temp.fix_acentos(neighborhood),
  city = pg_temp.fix_acentos(city),
  reference_point = pg_temp.fix_acentos(reference_point),
  member_since = pg_temp.fix_acentos(member_since),
  residence_type = pg_temp.fix_acentos(residence_type),
  marital_status = pg_temp.fix_acentos(marital_status),
  sex = pg_temp.fix_acentos(sex),
  origin_list = pg_temp.fix_acentos(origin_list);

SELECT name, neighborhood, availability FROM public.gvv_candidates ORDER BY name LIMIT 8;
