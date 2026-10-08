// Retards en cascade d'une journée, par praticien : un RDV terminé après
// l'heure prévue (rdv.termine_at) ou encore en cours décale les suivants.
// Même calcul que la Cloud Function sendRetardsAutomatiques
// (functions/retards_auto.js) et le site (website/src/lib/retards-rdv.ts).

const _oubliMin = 120; // RDV non clôturé 2 h après sa fin : clôture oubliée

/// rdv id → retard estimé (minutes) des RDV à venir aujourd'hui.
Map<String, int> retardsEnCascade(List<Map<String, dynamic>> rdvs, {DateTime? maintenant}) {
  final now = maintenant ?? DateTime.now();
  final debutJour = DateTime(now.year, now.month, now.day);
  final finJour = debutJour.add(const Duration(days: 1));
  final groupes = <String, List<Map<String, dynamic>>>{};
  for (final r in rdvs) {
    if (r['statut'] != 'confirme' && r['statut'] != 'termine') continue;
    final dh = DateTime.tryParse(r['date_heure']?.toString() ?? '')?.toLocal();
    if (dh == null || dh.isBefore(debutJour) || !dh.isBefore(finJour)) continue;
    groupes.putIfAbsent(r['instructeur_profile_id']?.toString() ?? '', () => []).add(r);
  }
  final out = <String, int>{};
  for (final liste in groupes.values) {
    liste.sort((a, b) => a['date_heure'].toString().compareTo(b['date_heure'].toString()));
    DateTime? curseur;
    for (final r in liste) {
      final debut = DateTime.parse(r['date_heure'].toString()).toLocal();
      final duree = Duration(minutes: (r['duree_minutes'] as num?)?.toInt() ?? 30);
      final finPrevue = debut.add(duree);
      if (r['statut'] == 'termine') {
        curseur = DateTime.tryParse(r['termine_at']?.toString() ?? '')?.toLocal() ?? finPrevue;
        continue;
      }
      if (!debut.isAfter(now)) {
        final debutReel = curseur != null && curseur.isAfter(debut) ? curseur : debut;
        var fin = debutReel.add(duree);
        if (fin.isBefore(now)) fin = now;
        if (now.difference(finPrevue).inMinutes > _oubliMin) fin = finPrevue;
        curseur = fin;
        continue;
      }
      final debutEstime = curseur != null && curseur.isAfter(debut) ? curseur : debut;
      final retard = debutEstime.difference(debut).inMinutes;
      if (retard > 0) out[r['id'].toString()] = retard;
      curseur = debutEstime.add(duree);
    }
  }
  return out;
}
