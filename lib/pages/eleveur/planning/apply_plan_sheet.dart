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

  DateTime _dateRef     = DateTime.now();
  String?  _animalId;
  bool     _saving      = false;
  bool     _loadingRefs = false;

  List<Map<String, dynamic>> _animaux = [];

  String get _cibleType => widget.template['cible_type'] as String? ?? 'individuel';
  String get _refEvent  => widget.template['reference_event'] as String? ?? 'manuel';

  @override
  void initState() {
    super.initState();
    if (_needsManualSelection) _loadRefs();
  }

  bool get _needsManualSelection => _cibleType == 'individuel';

  bool get _showDatePicker =>
    _refEvent == 'manuel' || _refEvent == 'saillie' || _cibleType == 'individuel';

  String get _cibleDescription => switch (_cibleType) {
    'cheptel'   => 'Tout le cheptel${_especeLabel}',
    'males'     => 'Tous les mâles${_especeLabel}',
    'femelles'  => 'Toutes les femelles${_especeLabel}',
    'gestantes' => 'Femelles gestantes — tâches calculées par rapport à la date de mise bas prévue',
    'bebes'     => 'Bébés/jeunes — tâches calculées selon l\'âge de chaque animal',
    _           => 'Sélectionner un animal',
  };

  String get _especeLabel {
    final e = widget.template['espece'] as String?;
    return (e != null && e.isNotEmpty) ? ' ($e)' : '';
  }

  String get _refLabel => switch (_refEvent) {
    'saillie'   => 'Date de saillie',
    'mise_bas'  => 'Date de référence (mise bas prévue)',
    'naissance' => 'Date de naissance',
    _           => 'Date J0',
  };

  Future<void> _loadRefs() async {
    setState(() => _loadingRefs = true);
    try {
      final supa = Supabase.instance.client;
      final espece = widget.template['espece'] as String?;
      var q = supa.from('animaux').select('id, nom, espece, sexe').eq('uid_eleveur', widget.uid);
      if (espece != null && espece.isNotEmpty) q = q.eq('espece', espece);
      final rows = await q.order('nom');
      if (mounted) setState(() {
        _animaux = List<Map<String, dynamic>>.from(rows);
        _loadingRefs = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingRefs = false);
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

  Future<void> _apply() async {
    if (_cibleType == 'individuel' && _animalId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sélectionnez un animal')));
      return;
    }
    setState(() => _saving = true);
    try {
      final count = await PlanningService.applyTemplate(
        uid: widget.uid,
        template: widget.template,
        dateReference: _dateRef,
        forcedAnimalId: _animalId,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$count tâche${count > 1 ? 's' : ''} générée${count > 1 ? 's' : ''} !'),
          backgroundColor: _green,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy', 'fr_FR');
    final etapes = (widget.template['plan_template_etapes'] as List? ?? []);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text('Appliquer : ${widget.template['nom']}',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 17, fontWeight: FontWeight.w700, color: _dark)),
              const SizedBox(height: 6),

              // ── Cible
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: _green.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    const Icon(Icons.group_outlined, size: 18, color: _green),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_cibleDescription, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF3A6B2A)))),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ── Sélection animale (seulement si individuel)
              if (_cibleType == 'individuel') ...[
                _Label('Animal'),
                const SizedBox(height: 6),
                if (_loadingRefs)
                  const Center(child: CircularProgressIndicator(color: _green))
                else
                  DropdownButtonFormField<String>(
                    initialValue: _animalId,
                    decoration: _inputDeco('Sélectionner un animal'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('— Choisir —', style: TextStyle(fontFamily: 'Galey'))),
                      ..._animaux.map((a) => DropdownMenuItem(
                        value: a['id'] as String,
                        child: Text('${a['nom']} (${a['espece'] ?? ''})', style: const TextStyle(fontFamily: 'Galey', fontSize: 13), overflow: TextOverflow.ellipsis),
                      )),
                    ],
                    onChanged: (v) {
                      setState(() {
                        _animalId = v;
                      });
                    },
                  ),
                const SizedBox(height: 14),
              ],

              // ── Date de référence (si applicable)
              if (_showDatePicker) ...[
                _Label(_refLabel),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [
                      const Icon(Icons.calendar_today_outlined, size: 18, color: _green),
                      const SizedBox(width: 10),
                      Text(fmt.format(_dateRef), style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
                    ]),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // ── Aperçu
              if (etapes.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: _green.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: _green.withValues(alpha: 0.2))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Aperçu des tâches', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: _green)),
                      const SizedBox(height: 8),
                      ...etapes.take(4).map((e) {
                        final direction   = e['offset_direction'] as String? ?? 'apres';
                        final produit     = e['produit']?.toString() ?? '';
                        final typeActe    = e['type_acte']?.toString() ?? '';
                        final frequence   = e['frequence']?.toString() ?? 'ponctuel';
                        final dureeJours  = (e['duree_jours'] as num? ?? 1).toInt();
                        final dureeS      = (e['duree_semaines'] as num? ?? 1).toInt();
                        final nbFois      = (e['nb_fois_semaine'] as num? ?? 1).toInt();
                        final ageSem      = e['age_min_semaines'] as int?;

                        String dateLabel;
                        if (ageSem != null) {
                          dateLabel = 'À $ageSem semaines';
                        } else {
                          dateLabel = '${direction == 'avant' ? 'J-' : 'J+'}${(e['jour_offset'] as num? ?? 0).toInt()}';
                        }

                        String freqLabel = '';
                        if (frequence == 'quotidien')    freqLabel = '× $dureeS sem.';
                        if (frequence == 'hebdomadaire') freqLabel = '${nbFois}x/sem. × $dureeS sem.';
                        if (frequence == 'mensuel')      freqLabel = '× $dureeS mois';
                        if (frequence == 'ponctuel' && dureeJours > 1) freqLabel = '× $dureeJours j';

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(children: [
                            SizedBox(width: 64, child: Text(dateLabel, style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: _green, fontWeight: FontWeight.w600))),
                            Expanded(child: Text(
                              [typeActe, if (produit.isNotEmpty) produit, if (freqLabel.isNotEmpty) freqLabel].join(' '),
                              style: const TextStyle(fontFamily: 'Galey', fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            )),
                          ]),
                        );
                      }),
                      if (etapes.length > 4)
                        Text('... et ${etapes.length - 4} autre${etapes.length - 4 > 1 ? 's' : ''} étape${etapes.length - 4 > 1 ? 's' : ''}',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

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

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151)));
}

InputDecoration _inputDeco(String label) => InputDecoration(
  labelText: label,
  labelStyle: const TextStyle(fontFamily: 'Galey'),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6E9E57))),
  filled: true, fillColor: Colors.white,
);
