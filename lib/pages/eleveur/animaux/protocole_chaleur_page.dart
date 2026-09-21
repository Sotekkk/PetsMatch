import 'package:flutter/material.dart';
import 'package:PetsMatch/main.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Protocole de chaleur par race : permet à l'éleveur de définir l'intervalle
/// de chaleurs (en jours) propre à chacune des races qu'il élève, plutôt que
/// de dépendre uniquement de la moyenne par espèce (ex. Pomsky = 120j quand
/// la moyenne "chien" est de 6 mois).
class ProtocoleChaleurPage extends StatefulWidget {
  const ProtocoleChaleurPage({super.key});

  @override
  State<ProtocoleChaleurPage> createState() => _ProtocoleChaleurPageState();
}

class _ProtocoleChaleurPageState extends State<ProtocoleChaleurPage> {
  static const _green = Color(0xFF6E9E57);

  static const _especes = [
    'chien', 'chat', 'lapin', 'cheval', 'ovin', 'caprin', 'porcin',
  ];

  final _supa = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _protocoles = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _supa
          .from('protocoles_chaleur_race')
          .select()
          .eq('uid_eleveur', User_Info.uid)
          .order('espece')
          .order('race');
      if (mounted) setState(() => _protocoles = List<Map<String, dynamic>>.from(rows));
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Races déjà présentes dans l'élevage pour une espèce donnée (suggestions).
  Future<List<String>> _mesRaces(String espece) async {
    try {
      final rows = await _supa
          .from('animaux')
          .select('race')
          .eq('uid_eleveur', User_Info.uid)
          .eq('espece', espece)
          .not('race', 'is', null);
      final set = <String>{};
      for (final r in (rows as List)) {
        final race = (r as Map)['race'] as String?;
        if (race != null && race.trim().isNotEmpty) set.add(race.trim());
      }
      final list = set.toList()..sort();
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> _deleteProtocole(String id) async {
    try {
      await _supa.from('protocoles_chaleur_race').delete().eq('id', id);
      if (mounted) setState(() => _protocoles.removeWhere((p) => p['id']?.toString() == id));
    } catch (_) {}
  }

  Future<void> _openForm({Map<String, dynamic>? existing}) async {
    var espece = existing?['espece'] as String? ?? _especes.first;
    final raceCtrl = TextEditingController(text: existing?['race'] as String? ?? '');
    final joursCtrl = TextEditingController(text: existing?['intervalle_jours']?.toString() ?? '');
    var suggestions = await _mesRaces(espece);

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(existing == null ? 'Nouveau protocole chaleur' : 'Modifier le protocole',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
            const SizedBox(height: 16),
            const Text('Espèce', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: espece,
              items: _especes.map((e) => DropdownMenuItem(value: e, child: Text(_capitalize(e)))).toList(),
              onChanged: existing != null ? null : (v) async {
                if (v == null) return;
                final s = await _mesRaces(v);
                setModal(() { espece = v; suggestions = s; });
              },
              decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
            ),
            const SizedBox(height: 14),
            const Text('Race', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            Autocomplete<String>(
              initialValue: TextEditingValue(text: raceCtrl.text),
              optionsBuilder: (v) => v.text.isEmpty
                  ? suggestions
                  : suggestions.where((s) => s.toLowerCase().contains(v.text.toLowerCase())),
              onSelected: (v) => raceCtrl.text = v,
              fieldViewBuilder: (fCtx, ctrl, focus, onSubmit) {
                ctrl.text = raceCtrl.text;
                ctrl.addListener(() => raceCtrl.text = ctrl.text);
                return TextField(
                  controller: ctrl,
                  focusNode: focus,
                  decoration: InputDecoration(
                    hintText: 'Ex. Pomsky, Spitz…',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            const Text('Intervalle (jours)', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            TextField(
              controller: joursCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: 'Ex. 120',
                suffixText: 'j',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _green, padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () async {
                  final race = raceCtrl.text.trim();
                  final jours = int.tryParse(joursCtrl.text.trim());
                  if (race.isEmpty || jours == null || jours <= 0) return;
                  try {
                    if (existing != null) {
                      await _supa.from('protocoles_chaleur_race').update({
                        'race': race, 'intervalle_jours': jours,
                      }).eq('id', existing['id']);
                    } else {
                      await _supa.from('protocoles_chaleur_race').upsert({
                        'uid_eleveur': User_Info.uid,
                        'espece': espece,
                        'race': race,
                        'intervalle_jours': jours,
                      }, onConflict: 'uid_eleveur,espece,race');
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    _load();
                  } catch (_) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                          content: Text('Une erreur est survenue.', style: TextStyle(fontFamily: 'Galey'))));
                    }
                  }
                },
                child: const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _green,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Protocole chaleur',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _green,
        onPressed: () => _openForm(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _green))
          : _protocoles.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Aucun protocole personnalisé.\nPar défaut, l\'intervalle moyen par espèce est utilisé '
                      '(ex. 6 mois pour un chien). Ajoutez une race pour affiner (ex. Pomsky = 120j).',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade600),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: _protocoles.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final p = _protocoles[i];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200)),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${p['race']} (${_capitalize(p['espece'] as String? ?? '')})',
                                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14.5)),
                            const SizedBox(height: 2),
                            Text('${p['intervalle_jours']} jours',
                                style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade600)),
                          ]),
                        ),
                        IconButton(icon: const Icon(Icons.edit_outlined, size: 20, color: _green),
                            onPressed: () => _openForm(existing: p)),
                        IconButton(icon: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade400),
                            onPressed: () => _deleteProtocole(p['id'].toString())),
                      ]),
                    );
                  },
                ),
    );
  }
}
