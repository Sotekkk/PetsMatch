import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;

/// Pension — tarification automatisée (Phase 2 item 1/4) : tranches de poids
/// (prix seul vs partagé) + réductions séjour long. Utilisé pour pré-remplir
/// le tarif dans la facturation (registre_pension_page.dart::_FacturationSheet).
class PensionTarifsPage extends StatefulWidget {
  const PensionTarifsPage({super.key});

  @override
  State<PensionTarifsPage> createState() => _PensionTarifsPageState();
}

class _TrancheCtrl {
  final TextEditingController poidsMax;
  final TextEditingController prixSeul;
  final TextEditingController prixPartage;
  _TrancheCtrl({String poidsMax = '', String prixSeul = '', String prixPartage = ''})
      : poidsMax = TextEditingController(text: poidsMax),
        prixSeul = TextEditingController(text: prixSeul),
        prixPartage = TextEditingController(text: prixPartage);
  void dispose() { poidsMax.dispose(); prixSeul.dispose(); prixPartage.dispose(); }
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
  final _supa = Supabase.instance.client;

  bool _loading = true;
  bool _saving = false;
  final List<_TrancheCtrl> _tranches = [];
  final List<_ReductionCtrl> _reductions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final t in _tranches) t.dispose();
    for (final r in _reductions) r.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final pid = User_Info.activeProfileId;
    if (pid.isEmpty) { setState(() => _loading = false); return; }
    try {
      final row = await _supa.from('user_profiles')
          .select('tarifs_pension').eq('id', pid).maybeSingle();
      final data = row?['tarifs_pension'];
      if (data is Map) {
        final tranches = data['tranches_poids'] as List? ?? [];
        for (final t in tranches) {
          final m = t as Map;
          _tranches.add(_TrancheCtrl(
            poidsMax: m['poids_max']?.toString() ?? '',
            prixSeul: m['prix_seul']?.toString() ?? '',
            prixPartage: m['prix_partage']?.toString() ?? '',
          ));
        }
        final reductions = data['reductions_long_sejour'] as List? ?? [];
        for (final r in reductions) {
          final m = r as Map;
          _reductions.add(_ReductionCtrl(
            minNuits: m['min_nuits']?.toString() ?? '',
            pourcentage: m['pourcentage']?.toString() ?? '',
          ));
        }
      }
      if (_tranches.isEmpty) _tranches.add(_TrancheCtrl());
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final pid = User_Info.activeProfileId;
    if (pid.isEmpty) return;
    setState(() => _saving = true);
    try {
      final tranches = _tranches.where((t) => t.prixSeul.text.trim().isNotEmpty).map((t) => {
        'poids_max': double.tryParse(t.poidsMax.text.replaceAll(',', '.')),
        'prix_seul': double.tryParse(t.prixSeul.text.replaceAll(',', '.')) ?? 0,
        'prix_partage': double.tryParse(t.prixPartage.text.replaceAll(',', '.')) ??
            double.tryParse(t.prixSeul.text.replaceAll(',', '.')) ?? 0,
      }).toList()
        ..sort((a, b) {
          final am = a['poids_max'] as double?;
          final bm = b['poids_max'] as double?;
          if (am == null) return 1;
          if (bm == null) return -1;
          return am.compareTo(bm);
        });
      final reductions = _reductions.where((r) => r.minNuits.text.trim().isNotEmpty).map((r) => {
        'min_nuits': int.tryParse(r.minNuits.text) ?? 0,
        'pourcentage': double.tryParse(r.pourcentage.text.replaceAll(',', '.')) ?? 0,
      }).toList()
        ..sort((a, b) => (a['min_nuits'] as int).compareTo(b['min_nuits'] as int));

      await _supa.from('user_profiles').update({
        'tarifs_pension': {
          'tranches_poids': tranches,
          'reductions_long_sejour': reductions,
        },
      }).eq('id', pid);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tarifs enregistrés.', style: TextStyle(fontFamily: 'Galey')),
          backgroundColor: Color(0xFF6E9E57),
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
                const Text('Tranches de poids',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                Text('Le tarif suggéré à la facturation dépend du poids de l\'animal et '
                    'de s\'il est seul ou partage son logement. Laisser le dernier poids max vide = "et plus".',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 12),
                for (int i = 0; i < _tranches.length; i++)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Expanded(child: TextField(
                        controller: _tranches[i].poidsMax,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Poids max (kg)', isDense: true, border: OutlineInputBorder()),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(
                        controller: _tranches[i].prixSeul,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Prix seul (€/nuit)', isDense: true, border: OutlineInputBorder()),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(
                        controller: _tranches[i].prixPartage,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Prix partagé (€/nuit)', isDense: true, border: OutlineInputBorder()),
                      )),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => setState(() {
                          _tranches[i].dispose();
                          _tranches.removeAt(i);
                        }),
                      ),
                    ]),
                  ),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _tranches.add(_TrancheCtrl())),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Ajouter une tranche', style: TextStyle(fontFamily: 'Galey')),
                ),
                const SizedBox(height: 24),
                const Text('Réductions séjour long',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                Text('Réduction appliquée sur le tarif total à partir d\'un nombre de nuits.',
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
}
