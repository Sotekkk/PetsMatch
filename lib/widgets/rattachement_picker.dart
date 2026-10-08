// Rattachement d'une tâche à des animaux OU à des portées (jamais mélangés) :
// menu à recherche, filtre espèce et cases à cocher, défilement interne.
// Miroir site : MultiSelectRattachement (src/components/agenda/AddTacheModal.tsx).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _teal = Color(0xFF0C5C6C);
const _dark = Color(0xFF1F2A2E);

/// Animaux de l'élevage (propriété directe + reçus par cession), triés par nom.
/// Chargés seulement quand l'utilisateur choisit « Animal » ou « Portée ».
Future<List<Map<String, dynamic>>> chargerAnimauxRattachement(String uid, String? profileId) async {
  final supa = Supabase.instance.client;
  var q = supa.from('animaux')
      .select('id, nom, espece, race, portee_id, nom_mere')
      .or('uid_eleveur.eq.$uid,uid_proprietaire.eq.$uid');
  if (profileId != null && profileId.isNotEmpty) q = q.eq('profile_id', profileId);
  final direct = List<Map<String, dynamic>>.from(
      (await q as List).map((e) => Map<String, dynamic>.from(e as Map)));
  var ownQ = supa.from('animaux_proprietes').select('animal_id').eq('uid_proprio', uid).isFilter('date_fin', null);
  if (profileId != null && profileId.isNotEmpty) ownQ = ownQ.eq('profile_id_proprio', profileId);
  final ownIds = (await ownQ as List).map((r) => r['animal_id']?.toString()).whereType<String>().toSet();
  final missing = ownIds.difference(direct.map((a) => a['id']?.toString() ?? '').toSet());
  if (missing.isNotEmpty) {
    final rows = await supa.from('animaux').select('id, nom, espece, race, portee_id, nom_mere')
        .inFilter('id', missing.toList());
    direct.addAll((rows as List).map((e) => Map<String, dynamic>.from(e as Map)));
  }
  direct.sort((a, b) => (a['nom'] ?? '').toString().compareTo((b['nom'] ?? '').toString()));
  return direct;
}

class PorteeRattachement {
  final String id;
  final String label;
  final List<Map<String, dynamic>> membres;
  const PorteeRattachement(this.id, this.label, this.membres);
}

List<PorteeRattachement> porteesDepuis(List<Map<String, dynamic>> animaux) {
  final map = <String, List<Map<String, dynamic>>>{};
  for (final a in animaux) {
    final pid = a['portee_id']?.toString();
    if (pid == null || pid.isEmpty) continue;
    map.putIfAbsent(pid, () => []).add(a);
  }
  return map.entries.map((e) {
    final mere = e.value.map((a) => (a['nom_mere'] ?? '').toString()).firstWhere((n) => n.isNotEmpty, orElse: () => '');
    var label = mere.isNotEmpty ? 'Portée de $mere' : 'Portée';
    if (mere.isEmpty) {
      final ms = int.tryParse(e.key.replaceFirst('portee_', ''));
      if (ms != null) label = 'Portée du ${DateFormat('d MMM yyyy', 'fr').format(DateTime.fromMillisecondsSinceEpoch(ms))}';
    }
    return PorteeRattachement(e.key, label, e.value);
  }).toList()
    ..sort((a, b) => a.label.compareTo(b.label));
}

class ItemRattachement {
  final String id;
  final String label;
  final String? detail;
  final String filtre;
  const ItemRattachement(this.id, this.label, this.filtre, {this.detail});
}

/// Menu multi-sélection : renvoie les ids cochés, ou null si fermé sans valider.
Future<List<String>?> showRattachementSheet(
  BuildContext context, {
  required String titre,
  required String recherche,
  required List<ItemRattachement> items,
  required List<String> initial,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _RattachementSheet(titre: titre, recherche: recherche, items: items, initial: initial),
  );
}

class _RattachementSheet extends StatefulWidget {
  final String titre;
  final String recherche;
  final List<ItemRattachement> items;
  final List<String> initial;
  const _RattachementSheet({required this.titre, required this.recherche, required this.items, required this.initial});
  @override
  State<_RattachementSheet> createState() => _RattachementSheetState();
}

class _RattachementSheetState extends State<_RattachementSheet> {
  late final Set<String> _sel = {...widget.initial};
  String _q = '';
  String _filtre = '';

  @override
  Widget build(BuildContext context) {
    final filtres = widget.items.map((i) => i.filtre).toSet().toList()..sort();
    final visibles = widget.items.where((i) =>
        (_filtre.isEmpty || i.filtre == _filtre) &&
        (_q.isEmpty || i.label.toLowerCase().contains(_q.toLowerCase()))).toList();
    final toutVisible = visibles.isNotEmpty && visibles.every((i) => _sel.contains(i.id));

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              Text(widget.titre, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 16, color: _dark)),
              const SizedBox(height: 10),
              TextField(
                onChanged: (v) => setState(() => _q = v.trim()),
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                decoration: InputDecoration(
                  hintText: widget.recherche,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              if (filtres.length > 1) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 32,
                  child: ListView(scrollDirection: Axis.horizontal, children: ['', ...filtres].map((f) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(f.isEmpty ? 'Toutes' : f, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                          color: _filtre == f ? Colors.white : Colors.grey.shade700)),
                      selected: _filtre == f,
                      showCheckmark: false,
                      selectedColor: _teal,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _filtre = f),
                    ),
                  )).toList()),
                ),
              ],
            ]),
          ),
          const Divider(height: 1),
          Flexible(
            child: visibles.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Aucun résultat', style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500)),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: visibles.length,
                    itemBuilder: (_, i) {
                      final it = visibles[i];
                      return CheckboxListTile(
                        value: _sel.contains(it.id),
                        onChanged: (v) => setState(() => v == true ? _sel.add(it.id) : _sel.remove(it.id)),
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: _teal,
                        dense: true,
                        title: Text(it.label, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: _dark)),
                        secondary: it.detail == null ? null
                            : Text(it.detail!, style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade500)),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 16, 10),
              child: Row(children: [
                TextButton(
                  onPressed: visibles.isEmpty ? null : () => setState(() {
                    if (toutVisible) {
                      _sel.removeAll(visibles.map((v) => v.id));
                    } else {
                      _sel.addAll(visibles.map((v) => v.id));
                    }
                  }),
                  style: TextButton.styleFrom(foregroundColor: _teal),
                  child: Text(toutVisible ? 'Tout décocher' : 'Tout cocher',
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, _sel.toList()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _teal, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(_sel.isEmpty ? 'Valider' : 'Valider (${_sel.length})',
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
