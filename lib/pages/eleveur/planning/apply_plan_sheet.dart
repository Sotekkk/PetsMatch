import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/services/planning_service.dart';

class ApplyPlanSheet extends StatefulWidget {
  final Map<String, dynamic> template;
  final String uid;

  const ApplyPlanSheet({super.key, required this.template, required this.uid});

  @override
  State<ApplyPlanSheet> createState() => _ApplyPlanSheetState();
}

class _ApplyPlanSheetState extends State<ApplyPlanSheet> {
  static const _green = Color(0xFF6E9E57);
  static const _dark  = Color(0xFF1F2A2E);

  String _declencheur = 'saillie';
  DateTime _dateRef   = DateTime.now();
  String? _referenceId;
  String? _referenceLabel;
  bool _saving = false;

  List<Map<String, dynamic>> _saillies = [];

  @override
  void initState() {
    super.initState();
    _loadRefs();
  }

  Future<void> _loadRefs() async {
    try {
      final supa = Supabase.instance.client;
      final sailliesRows = await supa.from('saillies').select('id, date_saillie, animal_id, animaux(nom)').eq('uid_eleveur', widget.uid).order('date_saillie', ascending: false).limit(20);

      if (mounted) {
        setState(() {
          _saillies = List<Map<String, dynamic>>.from(sailliesRows);
        });
      }
    } catch (_) {
      // ignore load errors silently
    }
  }

  Future<void> _apply() async {
    setState(() => _saving = true);
    try {
      await PlanningService.applyTemplate(
        uid: widget.uid,
        templateId: widget.template['id'] as String,
        typeDeclencheur: _declencheur,
        dateReference: _dateRef,
        referenceId: _referenceId,
        referenceLabel: _referenceLabel,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Protocole appliqué ! Les tâches ont été générées.'),
            backgroundColor: _green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _dateRef,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('fr'),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: _green)),
        child: child!,
      ),
    );
    if (d != null) setState(() => _dateRef = d);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy', 'fr_FR');
    final etapes = (widget.template['plan_template_etapes'] as List? ?? []);
    final totalTaches = etapes.fold<int>(0, (acc, e) => acc + ((e['duree_jours'] as int?) ?? 1));

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text(
                'Appliquer : ${widget.template['nom']}',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 17, fontWeight: FontWeight.w700, color: _dark),
              ),
              const SizedBox(height: 4),
              Text(
                '$totalTaches tâche${totalTaches > 1 ? 's' : ''} seront générées',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 20),

              // Déclencheur
              const _Label('Événement déclencheur'),
              const SizedBox(height: 8),
              _ChipSelector(
                options: const [
                  ('saillie',   '🐕 Saillie'),
                  ('naissance', '🍼 Naissance / portée'),
                  ('manuel',    '📋 Manuel'),
                ],
                selected: _declencheur,
                onSelected: (v) => setState(() { _declencheur = v; _referenceId = null; _referenceLabel = null; }),
              ),
              const SizedBox(height: 16),

              // Date de référence
              const _Label('Date de référence (J0)'),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 18, color: _green),
                      const SizedBox(width: 10),
                      Text(fmt.format(_dateRef), style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Liaison optionnelle
              if (_declencheur == 'saillie' && _saillies.isNotEmpty) ...[
                const _Label('Lier à une saillie (optionnel)'),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _referenceId,
                  decoration: _inputDeco('Sélectionner une saillie'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Aucune', style: TextStyle(fontFamily: 'Galey'))),
                    ..._saillies.map((s) {
                      final nom = (s['animaux'] as Map?)?['nom'] ?? 'Animal';
                      final date = s['date_saillie'] ?? '';
                      final label = '$nom — $date';
                      return DropdownMenuItem(
                        value: s['id'] as String,
                        child: Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 13), overflow: TextOverflow.ellipsis),
                      );
                    }),
                  ],
                  onChanged: (v) {
                    setState(() { _referenceId = v; });
                    if (v != null) {
                      final s = _saillies.firstWhere((x) => x['id'] == v, orElse: () => {});
                      final nom = (s['animaux'] as Map?)?['nom'] ?? 'Animal';
                      final date = s['date_saillie'] ?? '';
                      setState(() => _referenceLabel = '$nom — $date');
                    }
                  },
                ),
                const SizedBox(height: 16),
              ],

              // Aperçu des tâches
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _green.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Aperçu des tâches générées', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: _green)),
                    const SizedBox(height: 8),
                    ...etapes.take(5).map((e) {
                      final offset  = (e['jour_offset'] as num? ?? 0).toInt();
                      final duree   = (e['duree_jours'] as num? ?? 1).toInt();
                      final date    = _dateRef.add(Duration(days: offset));
                      final produit = e['produit']?.toString() ?? '';
                      final typeActe = e['type_acte']?.toString() ?? '';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Text(fmt.format(date), style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: _green, fontWeight: FontWeight.w600)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(
                              [typeActe, if (produit.isNotEmpty) produit, if (duree > 1) '× $duree j'].join(' '),
                              style: const TextStyle(fontFamily: 'Galey', fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            )),
                          ],
                        ),
                      );
                    }),
                    if (etapes.length > 5)
                      Text('... et ${etapes.length - 5} autre${etapes.length - 5 > 1 ? 's' : ''} étape${etapes.length - 5 > 1 ? 's' : ''}',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _apply,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _saving
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Générer les tâches', style: TextStyle(fontFamily: 'Galey', color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Widgets ──────────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
  );
}

class _ChipSelector extends StatelessWidget {
  final List<(String, String)> options;
  final String selected;
  final ValueChanged<String> onSelected;

  const _ChipSelector({required this.options, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: options.map((o) {
        final active = o.$1 == selected;
        return GestureDetector(
          onTap: () => onSelected(o.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: active ? const Color(0xFF6E9E57) : Colors.white,
              border: Border.all(color: active ? const Color(0xFF6E9E57) : Colors.grey.shade300),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(o.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w500, color: active ? Colors.white : const Color(0xFF1F2A2E))),
          ),
        );
      }).toList(),
    );
  }
}

InputDecoration _inputDeco(String label) => InputDecoration(
  labelText: label,
  labelStyle: const TextStyle(fontFamily: 'Galey'),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6E9E57))),
  filled: true,
  fillColor: Colors.white,
);
