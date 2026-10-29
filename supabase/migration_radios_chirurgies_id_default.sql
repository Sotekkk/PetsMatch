-- radios et chirurgies : id TEXT sans valeur par défaut. Plusieurs écrans
-- (site : radio / chirurgie saisies par le vétérinaire, radio du
-- propriétaire ; appli : radio depuis la fiche) n'envoient pas d'id →
-- insertion refusée (NOT NULL) sans message : la radio n'était jamais
-- enregistrée. Même filet que migration_health_tables_id_default.sql.
ALTER TABLE radios     ALTER COLUMN id SET DEFAULT gen_random_uuid()::text;
ALTER TABLE chirurgies ALTER COLUMN id SET DEFAULT gen_random_uuid()::text;
