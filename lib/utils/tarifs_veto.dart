/// Grille de tarifs du vétérinaire (user_profiles.tarifs_veto) — clés
/// partagées par l'édition du profil (pro_profile_edit.dart) et la fiche
/// publique (service_detail_page.dart). Miroir site : website/src/lib/tarifs-veto.ts.
/// Stérilisations chien par tranche de poids : le tarif dépend du gabarit.
const kTarifsVetoGroupes = <(String, List<(String, String)>)>[
  ('Consultations', [
    ('consultation',          'Consultation'),
    ('consultation_urgence',  "Consultation d'urgence"),
    ('visite_domicile',       'Visite à domicile'),
  ]),
  ('Vaccins & identification', [
    ('vaccin_chien',          'Vaccin chien'),
    ('vaccin_chat',           'Vaccin chat'),
    ('identification',        'Identification (puce)'),
  ]),
  ('Stérilisation chat', [
    ('castration_chat',       'Castration chat'),
    ('sterilisation_chatte',  'Stérilisation chatte'),
  ]),
  ('Castration chien (selon le poids)', [
    ('castration_chien_10',   'Moins de 10 kg'),
    ('castration_chien_25',   '10 à 25 kg'),
    ('castration_chien_45',   '25 à 45 kg'),
    ('castration_chien_45p',  'Plus de 45 kg'),
  ]),
  ('Stérilisation chienne (selon le poids)', [
    ('sterilisation_chienne_10',  'Moins de 10 kg'),
    ('sterilisation_chienne_25',  '10 à 25 kg'),
    ('sterilisation_chienne_45',  '25 à 45 kg'),
    ('sterilisation_chienne_45p', 'Plus de 45 kg'),
  ]),
];

/// Libellé complet d'une prestation (« Castration chien — 10 à 25 kg »).
String libelleTarifVeto(String groupe, String label) =>
    groupe.contains('(selon le poids)')
        ? '${groupe.replaceAll(' (selon le poids)', '')} — $label'
        : label;
