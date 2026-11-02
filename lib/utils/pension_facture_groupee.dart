// Facture de pension : tarif suggéré d'un séjour (prix par espèce ou ancien
// modèle par poids, réduction long séjour à part pour qu'elle apparaisse sur
// la facture) et séjours des autres animaux du même client sur la même
// période, à facturer ensemble (une section par animal).
// Miroir site : website/src/lib/pension-facture-groupee.ts.
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/pages/pro/pension_tarifs_page.dart'
    show pensionPrixNuit, pensionTarifKeyForEspece, pensionTarifPourKey;
import 'package:PetsMatch/utils/client_pension.dart';
import 'package:PetsMatch/utils/poids.dart';

final _supa = Supabase.instance.client;
String _t(Object? v) => v == null ? '' : v.toString().trim();

/// Nuits du séjour : entrée → sortie effective, sinon prévue, sinon aujourd'hui.
int nuitsSejour(Map<String, dynamic> e) {
  final debut = DateTime.tryParse(_t(e['date_entree']));
  if (debut == null) return 1;
  final fin = DateTime.tryParse(_t(e['date_sortie_effective'])) ?? DateTime.tryParse(_t(e['date_sortie_prevue'])) ?? DateTime.now();
  final n = (fin.difference(debut).inHours / 24).round();
  return n < 1 ? 1 : n;
}

/// Prix par nuit (plein tarif) et réduction long séjour (%) — null si aucun tarif configuré.
Future<({double prixNuit, double reductionPct})?> tarifPensionSuggere(Map<String, dynamic> e, Object? config, int nuits) async {
  if (config is! Map) return null;
  final seul = e['seul_dans_logement'] != false;
  double prixNuit = 0;
  final especesTarifs = config['especes'];
  if (especesTarifs is List && especesTarifs.isNotEmpty) {
    final key = pensionTarifKeyForEspece(e['espece']?.toString());
    if (key == null) return null;
    final match = pensionTarifPourKey(especesTarifs, key);
    if (match == null) return null;
    // Équidés : box ou pré selon le type du logement occupé.
    String? typeLogement;
    if (_t(e['logement_id']).isNotEmpty) {
      try {
        final lg = await _supa.from('enclos_chenil').select('type').eq('id', _t(e['logement_id'])).maybeSingle();
        typeLogement = lg?['type']?.toString();
      } catch (_) {}
    }
    prixNuit = pensionPrixNuit(match, seul: seul, hebergement: typeLogement);
  } else {
    // Rétro-compat : ancien modèle tranches de poids.
    final tranches = (config['tranches_poids'] as List?) ?? [];
    if (tranches.isEmpty) return null;
    double? poids;
    if (_t(e['animal_id']).isNotEmpty) {
      final animal = await _supa.from('animaux').select('poids').eq('id', _t(e['animal_id'])).maybeSingle();
      poids = poidsKg(animal?['poids']);
    }
    Map? tranche;
    for (final t in tranches) {
      final m = t as Map;
      final poidsMax = (m['poids_max'] as num?)?.toDouble();
      if (poids == null || poidsMax == null || poids <= poidsMax) { tranche = m; break; }
    }
    tranche ??= tranches.last as Map;
    prixNuit = ((seul ? tranche['prix_seul'] : tranche['prix_partage']) as num?)?.toDouble() ?? 0;
  }
  double reductionPct = 0;
  for (final r in (config['reductions_long_sejour'] as List?) ?? const []) {
    final m = r as Map;
    if (nuits >= ((m['min_nuits'] as num?)?.toInt() ?? 0)) reductionPct = (m['pourcentage'] as num?)?.toDouble() ?? 0;
  }
  return (prixNuit: prixNuit, reductionPct: reductionPct);
}

/// Séjours facturés par une liste de factures (rattachées au séjour, ou ligne
/// d'une facture groupée) ; `avecAcomptes` : une facture d'acompte compte aussi.
Set<String> sejoursDesFactures(Iterable<Map<String, dynamic>> factures, {bool avecAcomptes = true}) {
  final ids = <String>{};
  for (final f in factures) {
    if (f['statut'] == 'annulee' || f['type_facture'] == 'avoir' || (!avecAcomptes && f['type_facture'] == 'acompte')) continue;
    if (_t(f['source_pension_entree_id']).isNotEmpty) ids.add(_t(f['source_pension_entree_id']));
    for (final l in (f['lignes'] as List?) ?? const []) {
      if (l is Map && _t(l['pensionEntreeId']).isNotEmpty) ids.add(_t(l['pensionEntreeId']));
    }
  }
  return ids;
}

/// Autres séjours du même client qui chevauchent celui-ci (même pension),
/// pas encore facturés : proposés pour une facture groupée.
Future<List<Map<String, dynamic>>> sejoursMemeClient(Map<String, dynamic> e, String proProfileId) async {
  final debut = _t(e['date_entree']);
  if (debut.isEmpty) return [];
  final debutJ = debut.substring(0, debut.length < 10 ? debut.length : 10);
  String finDe(Map x) {
    final f = _t(x['date_sortie_effective']).isNotEmpty ? _t(x['date_sortie_effective'])
        : _t(x['date_sortie_prevue']).isNotEmpty ? _t(x['date_sortie_prevue']) : DateTime.now().toIso8601String();
    return f.substring(0, f.length < 10 ? f.length : 10);
  }
  final rows = await _supa.from('pension_entrees').select().eq('pro_profile_id', proProfileId)
      .neq('id', _t(e['id'])).lte('date_entree', finDe(e));
  final candidats = List<Map<String, dynamic>>.from(rows).where((x) => finDe(x).compareTo(debutJ) >= 0).toList();
  if (candidats.isEmpty) return [];
  final factures = await _supa.from('factures').select('source_pension_entree_id, lignes, statut, type_facture')
      .eq('profile_id', proProfileId).not('source_pension_entree_id', 'is', null);
  final deja = sejoursDesFactures(List<Map<String, dynamic>>.from(factures), avecAcomptes: false);
  final client = await clientDuSejour(e);
  final nom = _t(e['proprietaire_nom']).toLowerCase();
  final res = <Map<String, dynamic>>[];
  for (final x in candidats) {
    if (deja.contains(_t(x['id']))) continue;
    final c = await clientDuSejour(x);
    final meme = client.uid != null
        ? c.uid == client.uid && (client.profileId == null || c.profileId == null || c.profileId == client.profileId)
        : c.uid == null && nom.isNotEmpty && _t(x['proprietaire_nom']).toLowerCase() == nom;
    if (meme) res.add(x);
  }
  return res;
}
