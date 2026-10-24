-- ════════════════════════════════════════════════════════════════════════
-- Demandes de retrait d'un lieu (lieu naturel, ou lieu pet-friendly sans
-- gestionnaire) : un membre signale que le lieu doit disparaître (fermé,
-- inexistant, doublon…) ; l'équipe PetsMatch accepte (lieu naturel supprimé,
-- fiche pet-friendly masquée) ou refuse, avec un motif transmis au membre.
--
-- Écriture membre : création de SA demande (en attente) et annulation tant
-- qu'elle est en attente. Décision : API admin (clé service).
-- Idempotent.
-- ════════════════════════════════════════════════════════════════════════
BEGIN;

CREATE TABLE IF NOT EXISTS public.lieux_demandes_retrait (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nature               text NOT NULL CHECK (nature IN ('naturel', 'petfriendly')),
  natural_place_id     uuid REFERENCES public.natural_places(id) ON DELETE SET NULL,
  petfriendly_place_id uuid REFERENCES public.petfriendly_places(id) ON DELETE SET NULL,
  place_nom            text,           -- conservé si le lieu est supprimé
  uid                  text NOT NULL,
  profile_id           uuid,
  raison               text NOT NULL CHECK (raison IN
                         ('ferme', 'inexistant', 'doublon', 'animaux_refuses', 'dangereux', 'prive', 'autre')),
  commentaire          text,
  statut               text NOT NULL DEFAULT 'en_attente' CHECK (statut IN ('en_attente', 'acceptee', 'refusee')),
  motif                text,           -- réponse de l'équipe
  traite_par           text,
  traite_le            timestamptz,
  created_at           timestamptz NOT NULL DEFAULT now()
);

-- Une seule demande en attente par membre et par lieu.
CREATE UNIQUE INDEX IF NOT EXISTS uq_lieux_retrait_en_attente
  ON public.lieux_demandes_retrait (uid, coalesce(natural_place_id, petfriendly_place_id))
  WHERE statut = 'en_attente';
CREATE INDEX IF NOT EXISTS idx_lieux_retrait_statut ON public.lieux_demandes_retrait (nature, statut, created_at DESC);

ALTER TABLE public.lieux_demandes_retrait ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS lieux_retrait_select ON public.lieux_demandes_retrait;
DROP POLICY IF EXISTS lieux_retrait_insert ON public.lieux_demandes_retrait;
DROP POLICY IF EXISTS lieux_retrait_delete ON public.lieux_demandes_retrait;

CREATE POLICY lieux_retrait_select ON public.lieux_demandes_retrait FOR SELECT USING (
  uid = (auth.jwt() ->> 'sub') OR public.is_admin_uid(auth.jwt() ->> 'sub')
);

-- Lieu naturel publié, ou lieu pet-friendly publié sans gestionnaire.
CREATE POLICY lieux_retrait_insert ON public.lieux_demandes_retrait FOR INSERT WITH CHECK (
  uid = (auth.jwt() ->> 'sub') AND statut = 'en_attente' AND motif IS NULL AND traite_par IS NULL
  AND (
    (nature = 'naturel' AND petfriendly_place_id IS NULL AND EXISTS (
      SELECT 1 FROM public.natural_places np WHERE np.id = natural_place_id AND np.statut = 'valide'))
    OR
    (nature = 'petfriendly' AND natural_place_id IS NULL AND EXISTS (
      SELECT 1 FROM public.petfriendly_places pf
       WHERE pf.id = petfriendly_place_id AND pf.statut = 'actif' AND pf.uid_pro IS NULL))
  )
);

-- Annuler sa demande tant qu'elle n'est pas traitée.
CREATE POLICY lieux_retrait_delete ON public.lieux_demandes_retrait FOR DELETE USING (
  uid = (auth.jwt() ->> 'sub') AND statut = 'en_attente'
);

COMMIT;
