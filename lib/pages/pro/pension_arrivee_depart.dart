// Pension — enregistrer l'arrivée / le départ d'un animal sur son séjour
// (pension_entrees), avec heure réelle, personne qui dépose / récupère,
// hébergement, effets personnels, consignes du séjour et observations.
// Partagé par le tableau de bord pension et la fiche pension de l'animal.
// Miroir site : components/pension/ArriveeDepartModal.tsx.
// Le registre (registre_pension_page) garde son propre bouton « Sorti ».
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/pension_protocoles.dart' show appliquerProtocolesSejour, terminerTachesSejour;
import 'package:PetsMatch/pages/pro/pension_tarifs_page.dart' show logementAccepteEspece;

const _teal = Color(0xFF0C5C6C);

/// Séjours de ce profil pension (pro_profile_id vide = données antérieures).
bool sejourDuProfil(Map<String, dynamic> e) {
  final pid = User_Info.activeProfileId;
  final p = e['pro_profile_id']?.toString() ?? '';
  return pid.isEmpty || p.isEmpty || p == pid;
}

String hmFr(DateTime d) => DateFormat('HH:mm').format(d);

Future<List<String>> _personnesConnues(Map<String, dynamic> entree) async {
  final noms = <String>[
    if ((entree['proprietaire_nom']?.toString() ?? '').trim().isNotEmpty) entree['proprietaire_nom'].toString().trim(),
  ];
  final animalId = entree['animal_id']?.toString();
  if (animalId != null && animalId.isNotEmpty) {
    try {
      final a = await Supabase.instance.client.from('animaux').select('personnes_autorisees').eq('id', animalId).maybeSingle();
      for (final c in (a?['personnes_autorisees'] as List? ?? const [])) {
        final n = (c is Map ? c['nom'] : null)?.toString().trim() ?? '';
        if (n.isNotEmpty && !noms.contains(n)) noms.add(n);
      }
    } catch (_) {}
  }
  return noms;
}

InputDecoration _deco(String label) => InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      isDense: true,
    );

Widget _champ(TextEditingController c, String label, {int lignes = 1}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(controller: c, minLines: 1, maxLines: lignes,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14), decoration: _deco(label)),
    );

Future<void> _maj(BuildContext context, String id, Map<String, dynamic> complet, Map<String, dynamic> minimal) async {
  final supa = Supabase.instance.client;
  try {
    await supa.from('pension_entrees').update(complet).eq('id', id);
  } on PostgrestException {
    // migration_pension_fiche.sql pas encore passée : on garde l'essentiel.
    await supa.from('pension_entrees').update(minimal).eq('id', id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enregistré sans le détail (migration_pension_fiche.sql à passer).')));
    }
  }
}

/// Séjours enregistrés lors de la dernière arrivée / du dernier départ (cet
/// animal + ceux du même client cochés) : finalisation groupée.
List<String> dernierGroupePension = [];

/// Autres animaux du même client (e-mail ou nom), même pension : attendus le
/// même jour (arrivée) ou présents et partant le même jour (départ).
Future<List<Map<String, dynamic>>> _compagnons(Map<String, dynamic> entree, {required bool arrivee}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return [];
  final supa = Supabase.instance.client;
  try {
    final moi = await supa.from('pension_entrees').select('proprietaire_email, proprietaire_nom, date_entree, date_sortie_prevue, pro_profile_id')
        .eq('id', entree['id'].toString()).maybeSingle();
    final email = (moi?['proprietaire_email']?.toString() ?? '').trim(), nom = (moi?['proprietaire_nom']?.toString() ?? '').trim();
    if (email.isEmpty && nom.isEmpty) return [];
    var q = supa.from('pension_entrees').select('id, animal_nom, espece, logement_id, date_entree, date_sortie_prevue, arrivee_reelle_le, pro_profile_id')
        .eq('pro_uid', uid).eq('statut', 'en_pension').neq('id', entree['id'].toString());
    q = email.isNotEmpty ? q.eq('proprietaire_email', email) : q.eq('proprietaire_nom', nom);
    q = arrivee ? q.isFilter('arrivee_reelle_le', null).eq('date_entree', moi?['date_entree']?.toString() ?? '') : q.not('arrivee_reelle_le', 'is', null);
    final pid = moi?['pro_profile_id']?.toString() ?? '';
    return [
      for (final c in await q)
        if ((pid.isEmpty || (c['pro_profile_id']?.toString() ?? '').isEmpty || c['pro_profile_id'].toString() == pid)
            && (arrivee || moi?['date_sortie_prevue'] == null || c['date_sortie_prevue'] == moi?['date_sortie_prevue']))
          Map<String, dynamic>.from(c),
    ];
  } catch (_) {
    return [];
  }
}

/// Arrivée / départ groupé : cases à cocher des autres animaux du même client
/// (logement de chacun à l'arrivée, selon son espèce).
Widget _blocCompagnons(List<Map<String, dynamic>> compagnons, Map<String, bool> coches, Map<String, String?> logs,
    List<Map<String, dynamic>> logements, void Function(void Function()) setS, {required bool arrivee}) {
  if (compagnons.isEmpty) return const SizedBox.shrink();
  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE4E7E2))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(arrivee ? 'Arrivent aussi (même client)' : 'Partent aussi (même client)',
          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13)),
      for (final c in compagnons) Row(children: [
        Checkbox(value: coches[c['id'].toString()] ?? false, activeColor: _teal, visualDensity: VisualDensity.compact,
            onChanged: (v) => setS(() => coches[c['id'].toString()] = v ?? false)),
        Expanded(child: Text(c['animal_nom']?.toString() ?? 'Animal', style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5))),
        if (arrivee && (coches[c['id'].toString()] ?? false) && logements.isNotEmpty)
          SizedBox(width: 150, child: DropdownButton<String?>(
            value: logs[c['id'].toString()], isExpanded: true, isDense: true,
            hint: const Text('Logement…', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5)),
            items: [
              for (final l in logements)
                if (logementAccepteEspece(l['especes'] as List?, c['espece']?.toString()) || l['id'].toString() == logs[c['id'].toString()])
                  DropdownMenuItem(value: l['id'].toString(), child: Text(l['nom']?.toString() ?? 'Logement', style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5))),
            ],
            onChanged: (v) => setS(() => logs[c['id'].toString()] = v),
          )),
      ]),
      if (arrivee)
        Text("Même heure et même personne ; les apports ci-dessous concernent cet animal.",
            style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
    ]),
  );
}

/// Arrivée : heure réelle, déposant, hébergement, apports, consignes.
Future<bool> confirmerArriveePension(BuildContext context, Map<String, dynamic> entree) async {
  dernierGroupePension = [];
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return false;
  final supa = Supabase.instance.client;
  // Arrivée déjà enregistrée (autre appareil, double appui) : pas de second enregistrement.
  try {
    final deja = await supa.from('pension_entrees').select('arrivee_reelle_le').eq('id', entree['id'].toString()).maybeSingle();
    final le = DateTime.tryParse(deja?['arrivee_reelle_le']?.toString() ?? '')?.toLocal();
    if (le != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
            "L'arrivée est déjà enregistrée (le ${DateFormat('dd/MM').format(le)} à ${hmFr(le)}).", style: const TextStyle(fontFamily: 'Galey'))));
      }
      return false;
    }
  } catch (_) {}
  final connus = await _personnesConnues(entree);
  List<Map<String, dynamic>> logements = [];
  try {
    logements = List<Map<String, dynamic>>.from(await supa.from('enclos_chenil').select('id, nom, type, especes').eq('uid_eleveur', uid).order('nom'));
  } catch (_) {}
  // Espèce de l'animal : seuls les logements qui l'acceptent sont proposés
  // (+ celui déjà attribué).
  String? espece = entree['espece']?.toString();
  if ((espece ?? '').isEmpty && entree['animal_id'] != null) {
    try {
      final a = await supa.from('animaux').select('espece').eq('id', entree['animal_id'].toString()).maybeSingle();
      espece = a?['espece']?.toString();
    } catch (_) {}
  }
  final dejaAttribue = entree['logement_id']?.toString();
  final logementsTous = logements;
  final compagnons = await _compagnons(entree, arrivee: true);
  final coches = {for (final c in compagnons) c['id'].toString(): true};
  final logsComp = <String, String?>{for (final c in compagnons) c['id'].toString(): c['logement_id']?.toString()};
  logements = [for (final l in logementsTous) if (logementAccepteEspece(l['especes'] as List?, espece) || l['id'].toString() == dejaAttribue) l];
  if (!context.mounted) return false;
  var heure = DateTime.now();
  final deposeCtrl = TextEditingController(text: connus.isNotEmpty ? connus.first : '');
  final alimCtrl = TextEditingController();
  final traitCtrl = TextEditingController();
  final effetsCtrl = TextEditingController(text: entree['effets_personnels']?.toString() ?? '');
  final consignesCtrl = TextEditingController(text: entree['consignes_sejour']?.toString() ?? '');
  final obsCtrl = TextEditingController();
  String? logementId = entree['logement_id']?.toString();
  if (logementId != null && !logements.any((l) => l['id'].toString() == logementId)) logementId = null;

  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("Arrivée — ${entree['animal_nom'] ?? 'Animal'}",
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 17, color: _teal)),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero, dense: true,
          leading: const Icon(Icons.schedule, color: _teal),
          title: Text('Heure réelle : ${DateFormat('dd/MM').format(heure)} à ${hmFr(heure)}',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
          trailing: const Text('Modifier', style: TextStyle(fontFamily: 'Galey', color: _teal)),
          onTap: () async {
            final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(heure));
            if (t != null) setS(() => heure = DateTime(heure.year, heure.month, heure.day, t.hour, t.minute));
          },
        ),
        if (connus.length > 1)
          Wrap(spacing: 6, children: [
            for (final n in connus) ActionChip(label: Text(n, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                onPressed: () => setS(() => deposeCtrl.text = n)),
          ]),
        _champ(deposeCtrl, 'Déposé par'),
        _blocCompagnons(compagnons, coches, logsComp, logementsTous, setS, arrivee: true),
        if (logementsTous.isNotEmpty && logements.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text("Aucun logement n'accepte cette espèce : cochez-la sur un logement (Chenil / logements).",
                style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Color(0xFFB45309))),
          ),
        if (logements.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: DropdownButtonFormField<String?>(
              initialValue: logementId, isExpanded: true, decoration: _deco('Hébergement'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Sans hébergement attribué', style: TextStyle(fontFamily: 'Galey', fontSize: 13))),
                for (final l in logements)
                  DropdownMenuItem(value: l['id'].toString(),
                      child: Text('${l['nom']}${(l['type'] ?? '').toString().isNotEmpty ? ' (${l['type']})' : ''}'
                          '${logementAccepteEspece(l['especes'] as List?, espece) ? '' : ' — espèce non prévue'}',
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 13))),
              ],
              onChanged: (v) => setS(() => logementId = v),
            ),
          ),
        _champ(alimCtrl, 'Alimentation apportée'),
        _champ(traitCtrl, 'Traitements apportés'),
        _champ(effetsCtrl, 'Effets personnels (panier, laisse, jouets…)'),
        _champ(consignesCtrl, 'Consignes pour ce séjour', lignes: 3),
        _champ(obsCtrl, 'Observations à l\'arrivée', lignes: 3),
        const SizedBox(height: 4),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: Text("Enregistrer l'arrivée${coches.values.any((v) => v) ? ' (${1 + coches.values.where((v) => v).length} animaux)' : ''}",
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        )),
      ])),
    )),
  );
  if (ok != true || !context.mounted) return false;
  String? t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
  final consignes = [
    if (t(consignesCtrl) != null) t(consignesCtrl)!,
    if (t(alimCtrl) != null) 'Alimentation apportée : ${t(alimCtrl)}',
    if (t(traitCtrl) != null) 'Traitements apportés : ${t(traitCtrl)}',
  ].join('\n');
  await _maj(context, entree['id'].toString(), {
    'statut': 'en_pension',
    'arrivee_reelle_le': heure.toUtc().toIso8601String(),
    'depose_par': t(deposeCtrl),
    'logement_id': logementId,
    'effets_personnels': t(effetsCtrl),
    'consignes_sejour': consignes.isEmpty ? null : consignes,
    'observations_arrivee': t(obsCtrl),
  }, {'logement_id': logementId});
  // Autres animaux du même client cochés : même heure, même personne, leur logement.
  final ids = [entree['id'].toString()];
  for (final c in compagnons) {
    final id = c['id'].toString();
    if (coches[id] != true) continue;
    try {
      final deja = await supa.from('pension_entrees').select('arrivee_reelle_le').eq('id', id).maybeSingle();
      if (deja?['arrivee_reelle_le'] != null) continue;
      await supa.from('pension_entrees').update({
        'statut': 'en_pension', 'arrivee_reelle_le': heure.toUtc().toIso8601String(),
        'depose_par': t(deposeCtrl), 'logement_id': logsComp[id],
      }).eq('id', id);
      ids.add(id);
    } catch (_) {}
  }
  dernierGroupePension = ids;
  // Protocoles de séjour : appliqués tout seuls à l'arrivée.
  await appliquerProtocolesSejour(ids);
  return true;
}

/// Départ : heure réelle, personne qui récupère (autorisée ?), restitutions,
/// observations finales, règlement — puis séjour clôturé (statut sorti).
Future<bool> enregistrerDepartPension(BuildContext context, Map<String, dynamic> entree) async {
  dernierGroupePension = [];
  final connus = await _personnesConnues(entree);
  final compagnons = await _compagnons(entree, arrivee: false);
  final coches = {for (final c in compagnons) c['id'].toString(): true};
  if (!context.mounted) return false;
  var heure = DateTime.now();
  final recupCtrl = TextEditingController(text: connus.isNotEmpty ? connus.first : '');
  final obsCtrl = TextEditingController();
  bool effetsRendus = false, traitementsRendus = false, reglement = false;

  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final autorise = connus.any((n) => n.toLowerCase() == recupCtrl.text.trim().toLowerCase());
      return Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Départ — ${entree['animal_nom'] ?? 'Animal'}",
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 17, color: _teal)),
          const SizedBox(height: 12),
          _blocCompagnons(compagnons, coches, const {}, const [], setS, arrivee: false),
          ListTile(
            contentPadding: EdgeInsets.zero, dense: true,
            leading: const Icon(Icons.schedule, color: _teal),
            title: Text('Heure réelle : ${DateFormat('dd/MM').format(heure)} à ${hmFr(heure)}',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
            trailing: const Text('Modifier', style: TextStyle(fontFamily: 'Galey', color: _teal)),
            onTap: () async {
              final tm = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(heure));
              if (tm != null) setS(() => heure = DateTime(heure.year, heure.month, heure.day, tm.hour, tm.minute));
            },
          ),
          if (connus.isNotEmpty) ...[
            const Text('Personnes autorisées', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700)),
            Wrap(spacing: 6, children: [
              for (final n in connus) ActionChip(label: Text(n, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                  onPressed: () => setS(() => recupCtrl.text = n)),
            ]),
            const SizedBox(height: 6),
          ],
          TextField(controller: recupCtrl, onChanged: (_) => setS(() {}),
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14), decoration: _deco('Récupéré par')),
          if (recupCtrl.text.trim().isNotEmpty && !autorise)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text("Cette personne n'est ni le propriétaire ni une personne autorisée : vérifiez son identité.",
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFFB3261E))),
            ),
          const SizedBox(height: 6),
          CheckboxListTile(contentPadding: EdgeInsets.zero, dense: true, value: effetsRendus,
              onChanged: (v) => setS(() => effetsRendus = v ?? false),
              title: Text('Effets personnels restitués${(entree['effets_personnels']?.toString() ?? '').isNotEmpty ? ' (${entree['effets_personnels']})' : ''}',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13))),
          CheckboxListTile(contentPadding: EdgeInsets.zero, dense: true, value: traitementsRendus,
              onChanged: (v) => setS(() => traitementsRendus = v ?? false),
              title: const Text('Alimentation et traitements restants restitués', style: TextStyle(fontFamily: 'Galey', fontSize: 13))),
          CheckboxListTile(contentPadding: EdgeInsets.zero, dense: true, value: reglement,
              onChanged: (v) => setS(() => reglement = v ?? false),
              title: const Text('Situation administrative vérifiée (règlement)', style: TextStyle(fontFamily: 'Galey', fontSize: 13))),
          const SizedBox(height: 6),
          _champ(obsCtrl, 'Observations finales', lignes: 3),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Enregistrer le départ', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          )),
        ])),
      );
    }),
  );
  if (ok != true || !context.mounted) return false;
  final obs = [
    if (obsCtrl.text.trim().isNotEmpty) obsCtrl.text.trim(),
    if (!effetsRendus) 'Effets personnels non cochés comme restitués.',
    if (!reglement) 'Règlement non vérifié au départ.',
  ].join('\n');
  final dateStr = DateFormat('yyyy-MM-dd').format(heure);
  final depart = {
    'statut': 'sorti',
    'date_sortie_effective': dateStr,
    'depart_reel_le': heure.toUtc().toIso8601String(),
    'recupere_par': recupCtrl.text.trim().isEmpty ? null : recupCtrl.text.trim(),
    'observations_depart': obs.isEmpty ? null : obs,
  };
  await _maj(context, entree['id'].toString(), depart, {'statut': 'sorti', 'date_sortie_effective': dateStr});
  // Autres animaux du même client cochés : même départ.
  final ids = [entree['id'].toString()];
  for (final c in compagnons) {
    final id = c['id'].toString();
    if (coches[id] != true) continue;
    try {
      await Supabase.instance.client.from('pension_entrees').update(depart).eq('id', id);
      ids.add(id);
    } catch (_) {}
  }
  dernierGroupePension = ids;
  // Protocoles de séjour : tâches restantes après le départ retirées.
  await terminerTachesSejour(ids, dateStr);
  return true;
}
