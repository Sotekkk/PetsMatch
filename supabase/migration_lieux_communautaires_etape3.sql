-- Lieux pet-friendly — étape 3 (fiches) : signaler une fiche de lieu ou un avis
-- de lieu, avec les motifs propres aux lieux (information incorrecte, lieu
-- fermé, n'accepte pas les animaux, données personnelles, photo non autorisée).
-- À lancer après migration_lieux_communautaires.sql.
BEGIN;

ALTER TABLE signalements DROP CONSTRAINT IF EXISTS signalements_target_type_check;
ALTER TABLE signalements ADD CONSTRAINT signalements_target_type_check
  CHECK (target_type IN ('user', 'annonce', 'profil_pro', 'balade_ludique',
                         'groupe_post', 'groupe_commentaire', 'lieu', 'lieu_avis'));

ALTER TABLE signalements DROP CONSTRAINT IF EXISTS signalements_raison_check;
ALTER TABLE signalements ADD CONSTRAINT signalements_raison_check
  CHECK (raison IN ('contenu_inapproprie', 'spam', 'faux_profil', 'maltraitance',
                    'vente_interdite', 'autre',
                    'information_incorrecte', 'lieu_ferme', 'animaux_refuses',
                    'donnees_personnelles', 'photo_non_autorisee', 'faux_avis'));

COMMIT;
