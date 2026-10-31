-- Éducateur : forfait mixte = tant de séances individuelles + tant de séances
-- collectives, prix total. 31/10/2026.
--
-- forfaits_education.nb_seances_indiv / nb_seances_coll : répartition d'un
-- forfait mixte (nb_seances = somme). NULL = pas de répartition (ancien
-- forfait mixte : toutes séances confondues).
-- forfaits_souscrits.nb_indiv_total / nb_coll_total (+ _utilisees) : compteurs
-- par type, recopiés à l'attribution.
-- rdv.forfait_type_decompte : compteur décompté pour ce RDV (individuel |
-- collectif), pour annuler le décompte au bon endroit.
-- Idempotent.

ALTER TABLE public.forfaits_education
  ADD COLUMN IF NOT EXISTS nb_seances_indiv integer,
  ADD COLUMN IF NOT EXISTS nb_seances_coll integer;
ALTER TABLE public.forfaits_souscrits
  ADD COLUMN IF NOT EXISTS nb_indiv_total integer,
  ADD COLUMN IF NOT EXISTS nb_coll_total integer,
  ADD COLUMN IF NOT EXISTS nb_indiv_utilisees integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS nb_coll_utilisees integer NOT NULL DEFAULT 0;
ALTER TABLE public.rdv
  ADD COLUMN IF NOT EXISTS forfait_type_decompte text;
