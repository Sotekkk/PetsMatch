-- ═══════════════════════════════════════════════════════════════════════════
-- Petites annonces « objets & matériel » liées aux animaux (profil particulier)
--
-- Un particulier peut publier GRATUITEMENT une annonce pour du matériel lié
-- aux animaux : cage à lapin, harnais, foin/fourrage, location de prairie ou
-- de parcelle, matériel agricole (tracteur, remorque)… JAMAIS un animal
-- vivant (les animaux passent par `annonces`).
--
-- App + site : création / gestion (« Mes annonces ») + fil public de recherche.
-- À exécuter dans Supabase SQL Editor (une seule fois).
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.annonces_objets (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  uid              text NOT NULL,                 -- Firebase uid du vendeur
  profile_id       uuid,                          -- profil particulier actif
  titre            text NOT NULL,
  categorie        text NOT NULL,                 -- slug (cf. app/site : annonce_objet_categories)
  type_transaction text NOT NULL DEFAULT 'vente', -- vente | location | don | recherche
  prix             numeric,                       -- null si don / recherche / « à convenir »
  prix_unite       text,                          -- ex. '/mois', '/jour' (location)
  prix_negociable  boolean DEFAULT false,
  etat             text,                          -- neuf | tres_bon | bon | usage | NULL
  description      text,
  photos           text[] DEFAULT '{}'::text[],
  ville            text,
  code_postal      text,
  departement      text,
  region           text,
  nom_vendeur      text,
  statut           text NOT NULL DEFAULT 'disponible',  -- disponible | pause | vendu | supprime
  boost_until      timestamptz,
  vues             integer DEFAULT 0,
  contacts         integer DEFAULT 0,
  is_suspect       boolean DEFAULT false,
  suspect_reasons  text[],
  created_at       timestamptz DEFAULT now(),
  updated_at       timestamptz DEFAULT now(),
  expires_at       timestamptz
);

CREATE INDEX IF NOT EXISTS idx_annonces_objets_statut
  ON public.annonces_objets (statut, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_annonces_objets_uid
  ON public.annonces_objets (uid);
CREATE INDEX IF NOT EXISTS idx_annonces_objets_categorie
  ON public.annonces_objets (categorie);
CREATE INDEX IF NOT EXISTS idx_annonces_objets_boost
  ON public.annonces_objets (boost_until) WHERE boost_until IS NOT NULL;

-- Firebase Auth (pas de Supabase Auth) : auth.uid() est NULL côté client.
-- Sécurité assurée par la clé service_role côté serveur ; clé anon en lecture.
-- Convention projet : RLS activé + policy permissive.
ALTER TABLE public.annonces_objets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "annonces_objets_all" ON public.annonces_objets;
CREATE POLICY "annonces_objets_all" ON public.annonces_objets
  FOR ALL USING (true) WITH CHECK (true);
