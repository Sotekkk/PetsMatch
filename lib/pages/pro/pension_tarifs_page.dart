import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;

/// Pension — tarification par espèce : prix/nuit (seul vs logement partagé)
/// pour chaque espèce acceptée + réductions séjour long. Utilisé pour
/// pré-remplir le tarif dans la facturation
/// (registre_pension_page.dart::_FacturationSheet).

/// Espèces gérées par une pension. La `key` est stockée dans
/// tarifs_pension.especes[].espece ; le `label` correspond aux valeurs de
/// user_profiles.especes_acceptees.
const List<Map<String, String>> kPensionEspeces = [
  {'key': 'chien',         'label': 'Chien',               'emoji': '🐕'},
  {'key': 'chat',          'label': 'Chat',                'emoji': '🐈'},
  {'key': 'cheval',        'label': 'Cheval',              'emoji': '🐴'},
  {'key': 'animaux_ferme', 'label': 'Animaux de la ferme', 'emoji': '🐐'},
  {'key': 'lapin',         'label': 'Lapin',               'emoji': '🐇'},
  {'key': 'ane',           'label': 'Âne',                 'emoji': '🫏'},
  {'key': 'nac',           'label': 'NAC',                 'emoji': '🐹'},
  {'key': 'oiseau',        'label': 'Oiseaux',             'emoji': '🦜'},
];

/// entree.espece (minuscule, stockée en base) -> key de tarif pension.
String? pensionTarifKeyForEspece(String? espece) {
  switch ((espece ?? '').toLowerCase().trim()) {
    case 'chien':   return 'chien';
    case 'chat':    return 'chat';
    case 'cheval':  return 'cheval';
    case 'lapin':   return 'lapin';
    case 'ane':
    case 'âne':     return 'ane';
    case 'oiseau':
    case 'oiseaux': return 'oiseau';
    case 'nac':     return 'nac';
    case 'ovin':
    case 'caprin':
    case 'porcin':
    case 'mouton':
    case 'chevre':
    case 'chèvre':
    case 'cochon':  return 'animaux_ferme';
  }
  return null;
}

class PensionTarifsPage extends StatefulWidget {
  const PensionTarifsPage({super.key});

  @override
  State<PensionTarifsPage> createState() => _PensionTarifsPageState();
}

class _EspeceTarifCtrl {
  final String key;
  final String label;
  final String emoji;
  final bool accepte;
  final TextEditingController prixSeul;
  final TextEditingController prixPartage;
  _EspeceTarifCtrl({
    required this.key,
    required this.label,
    required this.emoji,
    required this.accepte,
    String prixSeul = '',
    String prixPartage = '',
  })  : prixSeul = TextEditingController(text: prixSeul),
        prixPartage = TextEditingController(text: prixPartage);
  void dispose() { prixSeul.dispose(); prixPartage.dispose(); }
}

class _ReductionCtrl {
  final TextEditingController minNuits;
  final TextEditingController pourcentage;
  _ReductionCtrl({String minNuits = '', String pourcentage = ''})
      : minNuits = TextEditingController(text: minNuits),
        pourcentage = TextEditingController(text: pourcentage);
  void dispose() { minNuits.dispose(); pourcentage.dispose(); }
}

class _PensionTarifsPageState extends State<PensionTarifsPage> {
  static const _teal = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);
  final _supa = Supabase.instance.client;

  bool _loading = true;
  bool _saving = false;
  bool _afficherPublic = false;
  final List<_EspeceTarifCtrl> _especes = [];
  final List<_ReductionCtrl> _reductions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final e in _especes) { e.dispose(); }
    for (final r in _reductions) { r.dispose(); }
    super.dispose();
  }

  Future<void> _load() async {
    final pid = User_Info.activeProfileId;
    Map<String, dynamic>? tarifs;
    List<String> acceptees = List<String>.from(User_Info.especesAcceptees);
    try {
      if (pid.isNotEmpty) {
        final row = await _supa.from('user_profiles')
            .select('tarifs_pension, especes_acceptees').eq('id', pid).maybeSingle();
        final data = row?['tarifs_pension'];
        if (data is Map) tarifs = Map<String, dynamic>.from(data);
        if (row?['especes_acceptees'] is List) {
          acceptees = List<String>.from(row!['especes_acceptees']);
        }
      }
    } catch (_) {}

    _afficherPublic = tarifs?['afficher_public'] == true;

    // Prix déjà saisis, par key d'espèce.
    final prixParEspece = <String, Map<String, String>>{};
    final especesJson = tarifs?['especes'];
    if (especesJson is List) {
      for (final e in especesJson) {
        if (e is! Map) continue;
        final k = e['espece']?.toString() ?? '';
        if (k.isEmpty) continue;
        prixParEspece[k] = {
          'seul': e['prix_seul']?.toString() ?? '',
          'partage': e['prix_partage']?.toString() ?? '',
        };
      }
    } else {
      // Rétro-compat : ancien modèle tranches_poids -> on reprend le prix
      // de la 1re tranche comme défaut pour toutes les espèces acceptées.
      final tranches = tarifs?['tranches_poids'];
      if (tranches is List && tranches.isNotEmpty && tranches.first is Map) {
        final t = tranches.first as Map;
        final seul = t['prix_seul']?.toString() ?? '';
        final partage = t['prix_partage']?.toString() ?? '';
        for (final sp in kPensionEspeces) {
          if (acceptees.contains(sp['label'])) {
            prixParEspece[sp['key']!] = {'seul': seul, 'partage': partage};
          }
        }
      }
    }

    for (final sp in kPensionEspeces) {
      final k = sp['key']!;
      final saved = prixParEspece[k];
      _especes.add(_EspeceTarifCtrl(
        key: k,
        label: sp['label']!,
        emoji: sp['emoji']!,
        accepte: acceptees.contains(sp['label']),
        prixSeul: saved?['seul'] ?? '',
        prixPartage: saved?['partage'] ?? '',
      ));
    }

    final reductions = tarifs?['reductions_long_sejour'];
    if (reductions is List) {
      for (final r in reductions) {
        if (r is! Map) continue;
        _reductions.add(_ReductionCtrl(
          minNuits: r['min_nuits']?.toString() ?? '',
          pourcentage: r['pourcentage']?.toString() ?? '',
        ));
      }
    }

    // Espèces acceptées d'abord, ordre canonique conservé dans chaque groupe.
    int rank(String k) => kPensionEspeces.indexWhere((e) => e['key'] == k);
    _especes.sort((a, b) {
      if (a.accepte != b.accepte) return a.accepte ? -1 : 1;
      return rank(a.key).compareTo(rank(b.key));
    });

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final pid = User_Info.activeProfileId;
    if (pid.isEmpty) return;
    setState(() => _saving = true);
    try {
      final especes = _especes
          .where((e) => e.prixSeul.text.trim().isNotEmpty)
          .map((e) {
        final seul = double.tryParse(e.prixSeul.text.replaceAll(',', '.')) ?? 0;
        final partage = double.tryParse(e.prixPartage.text.replaceAll(',', '.')) ?? seul;
        return {'espece': e.key, 'prix_seul': seul, 'prix_partage': partage};
      }).toList();

      final reductions = _reductions
          .where((r) => r.minNuits.text.trim().isNotEmpty)
          .map((r) => {
                'min_nuits': int.tryParse(r.minNuits.text) ?? 0,
                'pourcentage': double.tryParse(r.pourcentage.text.replaceAll(',', '.')) ?? 0,
              })
          .toList()
        ..sort((a, b) => (a['min_nuits'] as int).compareTo(b['min_nuits'] as int));

      await _supa.from('user_profiles').update({
        'tarifs_pension': {
          'especes': especes,
          'reductions_long_sejour': reductions,
          'afficher_public': _afficherPublic,
        },
      }).eq('id', pid);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tarifs enregistrés.', style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: _green,
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Tarifs pension',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _afficherPublic ? _green.withValues(alpha: 0.4) : const Color(0xFFEEEEEE)),
                  ),
                  child: SwitchListTile.adaptive(
                    value: _afficherPublic,
                    onChanged: (v) => setState(() => _afficherPublic = v),
                    activeColor: _green,
                    title: const Text('Afficher mes tarifs sur ma fiche publique',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text('Les clients verront le prix par nuit et par espèce dans l\'annuaire des pros.',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Prix par espèce',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                Text('Tarif par nuit selon l\'espèce et selon que l\'animal est seul '
                    'ou partage son logement. Le tarif est ensuite suggéré automatiquement '
                    'à la facturation. Les espèces acceptées par votre pension sont en haut.',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 12),
                for (final e in _especes) _especeCard(e),
                const SizedBox(height: 24),
                const Text('Réductions séjour long',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                Text('Réduction appliquée sur le tarif total à partir d\'un nombre de nuits (toutes espèces).',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 12),
                for (int i = 0; i < _reductions.length; i++)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Expanded(child: TextField(
                        controller: _reductions[i].minNuits,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'À partir de (nuits)', isDense: true, border: OutlineInputBorder()),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(
                        controller: _reductions[i].pourcentage,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Réduction (%)', isDense: true, border: OutlineInputBorder()),
                      )),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => setState(() {
                          _reductions[i].dispose();
                          _reductions.removeAt(i);
                        }),
                      ),
                    ]),
                  ),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _reductions.add(_ReductionCtrl())),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Ajouter une réduction', style: TextStyle(fontFamily: 'Galey')),
                ),
                const SizedBox(height: 24),
                SizedBox(width: double.infinity, child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: Text(_saving ? '...' : 'Enregistrer',
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                )),
              ],
            ),
    );
  }

  Widget _especeCard(_EspeceTarifCtrl e) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: e.accepte ? _green.withValues(alpha: 0.4) : const Color(0xFFEEEEEE)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(e.emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Text(e.label, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(width: 8),
        if (e.accepte)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: _green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
            child: const Text('Accepté', style: TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w700, color: _green)),
          ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: TextField(
          controller: e.prixSeul,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Prix seul (€/nuit)', isDense: true, border: OutlineInputBorder()),
        )),
        const SizedBox(width: 8),
        Expanded(child: TextField(
          controller: e.prixPartage,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Prix partagé (€/nuit)', isDense: true, border: OutlineInputBorder()),
        )),
      ]),
    ]),
  );
}
