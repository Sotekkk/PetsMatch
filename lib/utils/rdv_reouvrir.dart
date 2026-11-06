// « Terminé » touché par erreur : le RDV redevient confirmé, pour tous les
// métiers. Miroir site : website/src/lib/rdv-reouvrir.ts.
//  • statut 'confirme', heure réelle de fin effacée ;
//  • garde : départ validé effacé ; intervention vétérinaire : sortie effacée ;
//  • demande d'avis envoyée au client à la clôture : retirée si elle n'est pas lue.
// Rien d'autre n'est touché (compte rendu, facture, contrat, documents envoyés,
// forfait : « Rendre au forfait » depuis le dossier).
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Renvoie null si c'est fait, sinon le message d'erreur.
Future<String?> rouvrirRdv(String rdvId, {String? clientUid}) async {
  final supa = Supabase.instance.client;
  try {
    final r = await supa.from('rdv').select('statut, depart_valide_le, sortie_le').eq('id', rdvId).maybeSingle();
    if (r == null) return 'Rendez-vous introuvable.';
    if (r['statut'] != 'termine') return null;
    await supa.from('rdv').update({
      'statut': 'confirme', 'termine_at': null,
      if (r['depart_valide_le'] != null) 'depart_valide_le': null,
      if (r['sortie_le'] != null) 'sortie_le': null,
    }).eq('id', rdvId);
  } catch (e) {
    return e.toString();
  }
  if ((clientUid ?? '').isNotEmpty) {
    try {
      await supa.from('notifications').delete().eq('uid', clientUid!).eq('type', 'avis_demande')
          .eq('read', false).contains('data', {'rdv_id': rdvId});
    } catch (_) {}
  }
  return null;
}

/// Confirmation avant « Terminé » (un appui trop rapide arrive vite).
Future<bool> confirmerTermine(BuildContext context) async {
  final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
    title: const Text('Rendez-vous terminé ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
    content: const Text('Vous pourrez l\'annuler avec « Annuler « Terminé » » sur le rendez-vous.', style: TextStyle(fontFamily: 'Galey')),
    actions: [
      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Non')),
      FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Oui, terminé')),
    ],
  ));
  return ok == true;
}

/// Confirmation avant de rouvrir.
Future<bool> confirmerRouvrir(BuildContext context) async {
  final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
    title: const Text('Annuler « Terminé » ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
    content: const Text('Le rendez-vous redevient confirmé. Compte rendu, facture et documents déjà faits ne changent pas.',
        style: TextStyle(fontFamily: 'Galey')),
    actions: [
      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Non')),
      FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Oui, rouvrir')),
    ],
  ));
  return ok == true;
}
