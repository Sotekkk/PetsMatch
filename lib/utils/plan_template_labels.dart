// Libellés partagés entre l'écran de lecture d'un protocole
// (plan_template_view_page.dart) et son export PDF (planning_pdf_service.dart)
// — les deux doivent rester identiques visuellement.
library;

String planTemplateActeLabel(String? v) => switch (v) {
  'vermifuge'       => 'Vermifuge',
  'vaccination'     => 'Vaccination',
  'antiparasitaire' => 'Antiparasitaire',
  'traitement'      => 'Traitement',
  'visite'          => 'Visite vétérinaire',
  'nettoyage'       => 'Nettoyage',
  'promenade'       => 'Promenade',
  'socialisation'   => 'Socialisation',
  _                 => 'Autre',
};

String planTemplateTrancheLabel(String? v) => switch (v) {
  'matin'      => 'Matin',
  'midi'       => 'Midi',
  'apres_midi' => 'Après-midi',
  'soir'       => 'Soir',
  _            => '—',
};

String planTemplateFreqLabel(Map<String, dynamic> e) {
  final freq = e['frequence'] as String? ?? '';
  final dS = e['duree_semaines'] as int? ?? 1;
  final dJ = e['duree_jours'] as int? ?? 1;
  final nb = e['nb_fois_semaine'] as int? ?? 1;
  return switch (freq) {
    'ponctuel'     => 'Ponctuel ($dJ j)',
    'quotidien'    => 'Quotidien ($dS sem)',
    'hebdomadaire' => '${nb}x/sem × $dS sem',
    'mensuel'      => 'Mensuel × $dS mois',
    _              => freq,
  };
}

String planTemplateTimingLabel(Map<String, dynamic> e) {
  final ageSem = e['age_min_semaines'] as int?;
  if (ageSem != null) return 'À $ageSem semaines';
  final dir = e['offset_direction'] as String? ?? 'apres';
  final off = e['jour_offset'] as int? ?? 0;
  return '${dir == 'avant' ? 'Avant' : 'Après'} J0 + ${off}j';
}
