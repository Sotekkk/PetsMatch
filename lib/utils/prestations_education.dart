import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;

// Éducateur / comportementaliste : « Prestations & tarifs » est la source
// unique des prix — catalogue `prestations_education` (cours, bilans),
// `forfaits_education`, et options tarifaires du profil
// (`tarifs_education.domicile_supplement`, `tarifs_education_extra`).
// Lus par la réservation, la fiche publique et le devis.
// Miroir site : website/src/lib/prestations-education.ts.

/// Profil éducateur : le profil actif, sinon le profil éducateur du compte
/// (profil actif vide = profil principal).
String profilEducationId() {
  final actif = User_Info.activeProfileId;
  if (actif.isNotEmpty) return actif;
  final edu = User_Info.availableProfiles.where((p) => p['profile_type'] == 'education');
  return edu.isNotEmpty ? edu.first['id']?.toString() ?? '' : '';
}

/// Cours non supprimés d'un pro, dans l'ordre du catalogue.
/// [reservablesSeulement] : sans les cours en pause.
Future<List<Map<String, dynamic>>> chargerPrestationsEducation(String proUid,
    {String? profileId, bool reservablesSeulement = false, bool publiquesSeulement = false}) async {
  var q = Supabase.instance.client.from('prestations_education').select()
      .eq('pro_uid', proUid).eq('actif', true);
  if (profileId != null && profileId.isNotEmpty) q = q.eq('pro_profile_id', profileId);
  if (reservablesSeulement || publiquesSeulement) q = q.eq('reservable', true);
  if (publiquesSeulement) q = q.eq('affiche_public', true);
  final rows = await q.order('ordre', ascending: true).order('created_at', ascending: true);
  return List<Map<String, dynamic>>.from(rows as List);
}

/// Supplément à domicile (option tarifaire), 0 si aucun.
double supplementDomicile(dynamic tarifs) {
  if (tarifs is! Map) return 0;
  final v = (tarifs['domicile_supplement'] as num?)?.toDouble() ?? 0;
  return v > 0 ? v : 0;
}

String uniteTarif(Map<String, dynamic> p) => p['type'] == 'collectif' ? 'par participant' : 'par séance';

String typeAffiche(Map<String, dynamic> p) =>
    p['bilan_requis'] == true ? 'Bilan' : p['type'] == 'collectif' ? 'Collectif' : 'Individuel';

/// Lignes de tarifs de la fiche publique : cours affichés + options.
List<({String label, String prix})> lignesTarifsPublics(List<Map<String, dynamic>> prestations,
    dynamic tarifs, dynamic extra) {
  final sup = supplementDomicile(tarifs);
  String eur(num v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  return [
    for (final p in prestations)
      if (((p['prix'] as num?) ?? 0) > 0)
        (label: '${p['nom']} (${p['duree_minutes']} min)', prix: '${eur(p['prix'] as num)} € ${uniteTarif(p)}'),
    if (sup > 0) (label: 'Supplément à domicile', prix: '${eur(sup)} €'),
    if (extra is List)
      for (final e in extra)
        if (e is Map && (e['label']?.toString().trim() ?? '').isNotEmpty)
          (
            label: (e['description']?.toString().trim() ?? '').isNotEmpty
                ? '${e['label'].toString().trim()} — ${e['description'].toString().trim()}'
                : e['label'].toString().trim(),
            prix: ((e['prix'] as num?) ?? 0) > 0 ? '${eur(e['prix'] as num)} €' : '—',
          ),
  ];
}
