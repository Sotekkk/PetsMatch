// Dossier de la séance : « Prochain rendez-vous » (facultatif) — le pro peut
// programmer le suivant tout de suite, sinon le client le prend plus tard.
// Miroir site : website/src/lib/prochain-rdv.ts.
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Prochain RDV déjà pris avec ce pro pour l'animal du RDV, ou null.
Future<DateTime?> prochainRdvDate(Map<String, dynamic> rdv) async {
  final animalId = rdv['animal_id']?.toString();
  final debut = rdv['date_heure']?.toString();
  if (animalId == null || animalId.isEmpty || debut == null) return null;
  try {
    var q = Supabase.instance.client.from('rdv').select('date_heure').eq('animal_id', animalId)
        .gt('date_heure', debut).inFilter('statut', ['demande', 'confirme', 'contre_proposition']);
    final pid = rdv['pro_profile_id']?.toString() ?? '';
    q = pid.isNotEmpty ? q.eq('pro_profile_id', pid) : q.eq('pro_uid', rdv['pro_uid']?.toString() ?? '');
    final r = await q.order('date_heure').limit(1).maybeSingle();
    return DateTime.tryParse(r?['date_heure']?.toString() ?? '')?.toLocal();
  } catch (_) {
    return null;
  }
}

String libelleProchainRdv(DateTime? d) => d == null
    ? 'Facultatif — le client peut aussi le prendre plus tard.'
    : 'Prévu le ${DateFormat('EEE d MMM', 'fr_FR').format(d)} à ${DateFormat('HH:mm').format(d)}.';
