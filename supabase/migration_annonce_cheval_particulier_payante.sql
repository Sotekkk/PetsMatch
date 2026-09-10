-- ═══════════════════════════════════════════════════════════════════════════
-- Annonce cheval particulier — publication PAYANTE (paiement à l'annonce)
-- ───────────────────────────────────────────────────────────────────────────
-- Un particulier paie ~4,99 € par annonce cheval, visible 60 jours. Paiement
-- WEB uniquement (commission Apple/Google) : l'app crée un brouillon et
-- redirige vers le site. Le webhook Stripe publie l'annonce.
-- Réutilise la plomberie « achat ponctuel » (produits_ponctuels + branche
-- produit_code de /api/stripe/checkout + session.mode==='payment' du webhook).
-- Idempotent, relançable.
-- ═══════════════════════════════════════════════════════════════════════════

-- Produit ponctuel : publication d'une annonce cheval par un particulier.
-- Le stripe_price_id se saisit dans /admin → Produits ponctuels.
INSERT INTO public.produits_ponctuels (code, label, prix, duree_heures, description, actif)
VALUES ('annonce_cheval_particulier', 'Annonce cheval (particulier)', 4.99, 1440,
        'Publication d''une annonce cheval — visible 60 jours', true)
ON CONFLICT (code) DO NOTHING;

-- Suivi du paiement sur l'annonce (idempotence webhook + affichage).
--   NULL   = annonce gratuite (éleveur, perdu/trouvé, association…)
--   attente = brouillon particulier en attente de paiement
--   paye    = payée, publiée
ALTER TABLE public.annonces
  ADD COLUMN IF NOT EXISTS paiement_statut TEXT;

-- Garde-fou serveur : la RLS de `annonces` est allow-all (Firebase Auth, clé
-- anon côté client) → sans ça, le paywall ne serait qu'au niveau client. Ce
-- trigger force en brouillon toute annonce cheval de particulier non payée,
-- même insérée/màj directement via Supabase. Le webhook (service_role) pose
-- statut='disponible' ET paiement_statut='paye' dans le même UPDATE → passe.
CREATE OR REPLACE FUNCTION public.annonce_cheval_particulier_gate()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.profil_source = 'particulier'
     AND NEW.espece = 'cheval'
     AND COALESCE(NEW.paiement_statut, '') <> 'paye'
     AND NEW.statut = 'disponible' THEN
    NEW.statut := 'brouillon';
    NEW.paiement_statut := COALESCE(NEW.paiement_statut, 'attente');
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_annonce_cheval_particulier_gate ON public.annonces;
CREATE TRIGGER trg_annonce_cheval_particulier_gate
  BEFORE INSERT OR UPDATE ON public.annonces
  FOR EACH ROW EXECUTE FUNCTION public.annonce_cheval_particulier_gate();
