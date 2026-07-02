-- ============================================================
-- PetsMatch — "En FA" devient indépendant du statut
-- Un animal peut être à la fois en famille d'accueil ET disponible
-- à l'adoption : l'appartenance à une FA est portée par fa_id,
-- plus par une valeur de statut dédiée.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

-- Les animaux encore marqués statut='en_fa' (ancien modèle) repassent
-- à 'disponible' — leur présence en FA reste visible via fa_id (déjà renseigné).
UPDATE animaux
SET statut = 'disponible'
WHERE statut = 'en_fa';
