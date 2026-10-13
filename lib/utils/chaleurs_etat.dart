// État des chaleurs d'une femelle pour Mes animaux (filtres + étiquettes) :
//   • enChaleurs : une chaleur notée a commencé et n'est pas finie — date de
//     fin saisie, sinon durée saisie (« 18 jours »), sinon durée habituelle
//     de l'espèce ;
//   • aVerifier  : les prochaines chaleurs (dernières + intervalle) tombent
//     dans les 7 jours ou sont dépassées, sans nouvelle chaleur notée.
// Miroir site : website/src/lib/chaleurs-etat.ts.

enum EtatChaleurs { aucun, enChaleurs, aVerifier }

/// Durée habituelle des chaleurs (jours) quand ni fin ni durée n'est saisie.
int dureeChaleursJours(String espece) {
  switch (espece.toLowerCase()) {
    case 'chien':  return 21;
    case 'chat':   return 7;
    case 'cheval': return 6;
    case 'ovin':   return 2;
    case 'caprin': return 2;
    case 'porcin': return 3;
    default:       return 7;
  }
}

/// Retard au-delà duquel on ne signale plus (données trop anciennes).
const _retardMaxJours = 90;

bool estEnChaleurs({required DateTime? debut, DateTime? fin, String? dureeTexte, required String espece, DateTime? maintenant}) {
  if (debut == null) return false;
  final now = maintenant ?? DateTime.now();
  final jour = DateTime(now.year, now.month, now.day);
  final d = DateTime(debut.year, debut.month, debut.day);
  if (d.isAfter(jour)) return false;
  final duree = int.tryParse(RegExp(r'\d+').firstMatch(dureeTexte ?? '')?.group(0) ?? '');
  final finEff = fin != null
      ? DateTime(fin.year, fin.month, fin.day)
      : d.add(Duration(days: (duree ?? dureeChaleursJours(espece)) - 1));
  return !jour.isAfter(finEff);
}

bool chaleursAVerifier({required DateTime? derniere, required int intervalle, DateTime? maintenant}) {
  if (derniere == null || intervalle <= 0) return false;
  final now = maintenant ?? DateTime.now();
  final ecart = derniere.add(Duration(days: intervalle)).difference(now).inDays;
  return ecart <= 7 && ecart >= -_retardMaxJours;
}

/// Mise bas de référence d'une gestation pour le cycle des chaleurs :
/// la mise bas saisie, sinon — gestation confirmée — la date estimée
/// (date_prevue, ou fin de fenêtre). Une date future = femelle gestante :
/// le cycle reste suspendu comme pendant la lactation.
DateTime? miseBasDeReference(Map g) {
  final reelle = DateTime.tryParse(g['date_naissance']?.toString() ?? '');
  if (reelle != null) return reelle;
  if (g['gestation_confirmee'] != true) return null;
  return DateTime.tryParse(g['date_prevue']?.toString() ?? '')
      ?? DateTime.tryParse(g['date_prevue_fin']?.toString() ?? '');
}

/// Filtre PostgREST des gestations utiles : mise bas saisie ou gestation confirmée.
const filtreGestationsMiseBas = 'date_naissance.not.is.null,gestation_confirmee.eq.true';
const colonnesGestationsMiseBas = 'animal_id, date_naissance, gestation_confirmee, date_prevue, date_prevue_fin';

/// Dernière mise bas de référence par animal.
Map<String, DateTime> dernieresMisesBas(Iterable rows) {
  final out = <String, DateTime>{};
  for (final g in rows) {
    if (g is! Map) continue;
    final aid = g['animal_id']?.toString() ?? '';
    final d = miseBasDeReference(g);
    if (aid.isEmpty || d == null) continue;
    if (out[aid] == null || d.isAfter(out[aid]!)) out[aid] = d;
  }
  return out;
}
