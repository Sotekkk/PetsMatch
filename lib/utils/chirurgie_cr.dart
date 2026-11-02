// Comptes rendus préopératoire et opératoire d'une intervention
// (migration_chirurgies_cr.sql) : champs, préremplissage depuis la fiche
// chirurgie, contrôles, texte du PDF. Seuls les champs saisis apparaissent :
// rien n'est affirmé par défaut (pas de « aucune complication » d'office).
// Miroir site : website/src/lib/chirurgie-cr.ts.

/// (clé, libellé, texte long).
const champsCrChir = <String, List<(String, String, bool)>>{
  'preop': [
    ('intervention', 'Intervention prévue', false),
    ('antecedents', 'Antécédents pertinents', true),
    ('examen_clinique', 'Examen clinique', true),
    ('poids', 'Poids (kg)', false),
    ('evaluation_anesthesique', 'Évaluation préanesthésique', true),
    ('examens', 'Examens réalisés', true),
    ('risques', 'Risques identifiés', true),
    ('protocole', 'Protocole préopératoire', true),
    ('observations', 'Observations', true),
    ('decision', 'Décision et recommandations', true),
  ],
  'operatoire': [
    ('intervention', "Nature de l'intervention", false),
    ('indication', 'Indication', true),
    ('anesthesie', "Type d'anesthésie", false),
    ('description', "Description de l'acte", true),
    ('gestes', 'Gestes chirurgicaux réalisés', true),
    ('observations', 'Observations', true),
    ('complications', 'Complications', true),
    ('soins', 'Soins administrés', true),
    ('etat_fin', "État de l'animal en fin d'intervention", true),
    ('surveillance', 'Surveillance postopératoire', true),
    ('traitements', 'Traitements prescrits', true),
    ('controles', 'Contrôles recommandés', true),
    ('prochain_rdv', 'Prochain rendez-vous', false),
  ],
};

const titreCrChir = {'preop': 'Compte rendu préopératoire', 'operatoire': 'Compte rendu opératoire'};

String _v(dynamic d, String k) => d is Map ? (d[k] ?? '').toString().trim() : '';

/// Champs de départ : saisie existante, sinon données déjà enregistrées.
Map<String, String> prerempliCrChir(String type, Map<String, dynamic> c, {dynamic poidsFiche}) {
  final d = c[type];
  final out = {for (final f in champsCrChir[type]!) f.$1: _v(d, f.$1)};
  if (out['intervention']!.isEmpty) out['intervention'] = (c['intitule'] ?? '').toString();
  if (type == 'preop' && out['protocole']!.isEmpty) out['protocole'] = (c['protocole_preop'] ?? '').toString();
  if (type == 'preop' && out['poids']!.isEmpty && (poidsFiche?.toString().trim() ?? '').isNotEmpty) out['poids'] = poidsFiche.toString();
  if (type == 'operatoire' && out['surveillance']!.isEmpty) out['surveillance'] = (c['protocole_postop'] ?? '').toString();
  return out;
}

({List<String> bloquants, List<String> avertissements}) controlerCrChir(String type, Map<String, String> champs) {
  final bloquants = <String>[], avertissements = <String>[];
  bool rempli(String k) => (champs[k] ?? '').trim().isNotEmpty;
  if (!rempli('intervention')) bloquants.add(type == 'preop' ? 'Intervention prévue' : "Nature de l'intervention");
  if (type == 'preop') {
    if (!champsCrChir['preop']!.any((f) => f.$1 != 'intervention' && rempli(f.$1))) bloquants.add('Au moins une information clinique');
    if (!rempli('decision')) avertissements.add('Décision et recommandations non renseignées');
  } else {
    if (!rempli('description')) bloquants.add("Description de l'acte");
    if (!rempli('anesthesie')) avertissements.add("Type d'anesthésie non renseigné");
    if (!rempli('complications')) {
      avertissements.add('Complications non renseignées : le document n’indiquera rien à ce sujet (il n’affirme pas leur absence)');
    }
    if (!rempli('etat_fin')) avertissements.add("État de l'animal en fin d'intervention non renseigné");
  }
  return (bloquants: bloquants, avertissements: avertissements);
}

/// Texte du PDF (« Libellé : valeur » par paragraphe, champs vides omis).
String texteCrChir(String type, Map<String, String> champs, String? dateIntervention) {
  final lignes = <String>[];
  final d = DateTime.tryParse(dateIntervention ?? '');
  if (d != null) {
    lignes.add("Date de l'intervention : ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}");
  }
  for (final f in champsCrChir[type]!) {
    final v = (champs[f.$1] ?? '').trim();
    if (v.isEmpty) continue;
    lignes.add('${f.$2.replaceAll(RegExp(r'\s*\(kg\)$'), '')} : ${f.$1 == 'poids' ? '${v.replaceAll('.', ',')} kg' : v}');
  }
  if (type == 'preop') lignes.add("Ce compte rendu ne vaut pas consentement du propriétaire à l'intervention.");
  return lignes.join('\n\n');
}
