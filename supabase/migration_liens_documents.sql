-- ════════════════════════════════════════════════════════════════════════
-- Lien sécurisé par document — lot 6 des documents vétérinaires. 03/11/2026.
--
--   • liens_documents : un lien individuel par document (jeton aléatoire),
--     limité dans le temps (7 jours par défaut), révocable ; il n'ouvre QUE
--     ce document (doc_url), jamais le reste du dossier ;
--   • liens_documents_acces : traçabilité des ouvertures (date, empreinte
--     de l'adresse IP, navigateur) ;
--   • tout passe par les routes serveur du site (clé de service) :
--     /api/liens-documents (création, liste, révocation — jeton Firebase
--     vérifié et droits sur la clinique contrôlés) et
--     /api/document-partage/[jeton] (ouverture sans compte → lien signé 10 min) ;
--     RLS activée sans aucune policy : rien n'est lisible directement.
-- Idempotent. Staging d'abord, puis prod AVANT le déploiement.
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE IF NOT EXISTS public.liens_documents (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  jeton              TEXT NOT NULL UNIQUE,
  doc_url            TEXT NOT NULL,
  document_type      TEXT NOT NULL,
  titre              TEXT NOT NULL,
  animal_id          TEXT,
  animal_nom         TEXT,
  pro_uid            TEXT NOT NULL,
  pro_profile_id     UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
  expediteur_nom     TEXT,
  cree_par_uid       TEXT NOT NULL,
  destinataire_email TEXT,
  expire_le          TIMESTAMPTZ NOT NULL,
  revoque_le         TIMESTAMPTZ,
  revoque_par_uid    TEXT,
  nb_acces           INTEGER NOT NULL DEFAULT 0,
  dernier_acces_le   TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS liens_documents_doc_idx ON public.liens_documents (doc_url);
CREATE INDEX IF NOT EXISTS liens_documents_pro_idx ON public.liens_documents (pro_uid);

CREATE TABLE IF NOT EXISTS public.liens_documents_acces (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lien_id    UUID NOT NULL REFERENCES public.liens_documents(id) ON DELETE CASCADE,
  acces_le   TIMESTAMPTZ NOT NULL DEFAULT now(),
  ip_hash    TEXT,
  navigateur TEXT
);
CREATE INDEX IF NOT EXISTS liens_documents_acces_lien_idx ON public.liens_documents_acces (lien_id);

ALTER TABLE public.liens_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.liens_documents_acces ENABLE ROW LEVEL SECURITY;
-- Aucune policy : accès uniquement par les routes serveur (clé de service).
REVOKE ALL ON public.liens_documents, public.liens_documents_acces FROM anon, authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
