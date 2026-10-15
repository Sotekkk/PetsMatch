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

/// Arrivée : heure réelle, déposant, hébergement, apports, consignes.
Future<bool> confirmerArriveePension(BuildContext context, Map<String, dynamic> entree) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return false;
  final supa = Supabase.instance.client;
  final connus = await _personnesConnues(entree);
  List<Map<String, dynamic>> logements = [];
  try {
    logements = List<Map<String, dynamic>>.from(await supa.from('enclos_chenil').select('id, nom, type').eq('uid_eleveur', uid).order('nom'));
  } catch (_) {}
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
        if (logements.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: DropdownButtonFormField<String?>(
              initialValue: logementId, isExpanded: true, decoration: _deco('Hébergement'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Sans hébergement attribué', style: TextStyle(fontFamily: 'Galey', fontSize: 13))),
                for (final l in logements)
                  DropdownMenuItem(value: l['id'].toString(),
                      child: Text('${l['nom']}${(l['type'] ?? '').toString().isNotEmpty ? ' (${l['type']})' : ''}',
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
          child: const Text("Enregistrer l'arrivée", style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
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
  return true;
}

/// Départ : heure réelle, personne qui récupère (autorisée ?), restitutions,
/// observations finales, règlement — puis séjour clôturé (statut sorti).
Future<bool> enregistrerDepartPension(BuildContext context, Map<String, dynamic> entree) async {
  final connus = await _personnesConnues(entree);
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
  await _maj(context, entree['id'].toString(), {
    'statut': 'sorti',
    'date_sortie_effective': dateStr,
    'depart_reel_le': heure.toUtc().toIso8601String(),
    'recupere_par': recupCtrl.text.trim().isEmpty ? null : recupCtrl.text.trim(),
    'observations_depart': obs.isEmpty ? null : obs,
  }, {'statut': 'sorti', 'date_sortie_effective': dateStr});
  return true;
}
