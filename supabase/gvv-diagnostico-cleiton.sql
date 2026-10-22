-- Onde o Cleiton está ligado? Não altera nada.
SELECT c.id AS gvv, h.name AS casa, h.house_no,
       CASE WHEN c.leader_candidate_id = p.id THEN 'líder' WHEN c.vice_candidate_id = p.id THEN 'vice' WHEN c.host_candidate_id = p.id THEN 'casa' END AS papel
FROM gvv_candidates p
LEFT JOIN gvv_connections c ON p.id IN (c.leader_candidate_id, c.vice_candidate_id, c.host_candidate_id)
LEFT JOIN gvv_candidates h ON h.id = c.host_candidate_id
WHERE lower(p.name) LIKE 'cleiton%';
