-- ════════════════════════════════════════════════════════════════════════
-- Bucket media : accepter les PDF et les vidéos.
--
-- Le bucket n'acceptait que des images (5 Mo) alors que :
--   • l'appli y dépose des PDF : contrat signé (contrat_signature_page),
--     facture (facturation), attestation / exercices d'éducation ;
--   • le site y dépose des vidéos : journal de pension (PensionJournal).
-- Ces dépôts échouaient (415 invalid_mime_type) : aucun PDF dans media.
-- Taille max portée à 50 Mo pour les vidéos.
-- ════════════════════════════════════════════════════════════════════════

UPDATE storage.buckets
SET allowed_mime_types = ARRAY[
      'image/jpeg', 'image/png', 'image/webp', 'image/gif',
      'application/pdf',
      'video/mp4', 'video/quicktime', 'video/webm'
    ],
    file_size_limit = 52428800
WHERE id = 'media';
