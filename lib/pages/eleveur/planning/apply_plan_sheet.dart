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
  static const _green = Color(0xFF0C5C6C);
  static const _dark  = Color(0xFF1F2A2E);

  DateTime        _dateRef     = DateTime.now();
  final Set<String> _selectedIds = {};
  String          _sexeFilter  = 'tous';
  bool            _saving      = false;
  bool            _loadingRefs = false;

  List<Map<String, dynamic>> _animaux = [];

  String get _cibleType => widget.template['cible_type'] as String? ?? 'individuel';
  String get _refEvent  => widget.template['reference_event'] as String? ?? 'manuel';

  @override
  void initState() {
    super.initState();
    if (_cibleType == 'individuel') _loadAnimaux();
  }

  bool get _showDatePicker =>
    _refEvent == 'manuel' || _refEvent == 'saillie' || _cibleType == 'individuel';

  String get _cibleDescription => switch (_cibleType) {
    'cheptel'     => 'Tout le cheptel$_especeLabel',
    'males'       => 'Tous les mâles$_especeLabel',
    'femelles'    => 'Toutes les femelles$_especeLabel',
    'gestantes'   => 'Femelles gestantes — tâches calculées par rapport à la date de mise bas prévue',
    'allaitantes' => 'Femelles allaitantes$_especeLabel — avec portée en cours (moins de 8 semaines)',
    'bebes'       => 'Bébés/jeunes — tâches calculées selon l\'âge de chaque animal',
    _             => 'Sélectionner un ou plusieurs animaux',
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

  List<Map<String, dynamic>> get _filteredAnimaux {
    if (_sexeFilter == 'tous') return _animaux;
    return _animaux.where((a) => a['sexe'] == _sexeFilter).toList();
  }

  Future<void> _loadAnimaux() async {
    setState(() => _loadingRefs = true);
    try {
      final supa = Supabase.instance.client;
      final espece = widget.template['espece'] as String?;
      var q = supa.from('animaux').select('id, nom, espece, sexe').eq('uid_eleveur', widget.uid);
      if (espece != null && espece.isNotEmpty) q = q.eq('espece', espece);
      final rows = await q.order('nom');
      if (mounted) {
        setState(() {
          _animaux = List<Map<String, dynamic>>.from(rows);
          _loadingRefs = false;
        });
      }
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
    if (_cibleType == 'individuel' && _selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sélectionnez au moins un animal')));
      return;
    }
    setState(() => _saving = true);
    try {
      final count = await PlanningService.applyTemplate(
        uid: widget.uid,
        template: widget.template,
        dateReference: _dateRef,
        forcedAnimalIds: _cibleType == 'individuel' ? _selectedIds.toList() : null,
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
    final fmt   = DateFormat('d MMM yyyy', 'fr_FR');
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
              Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text('Appliquer : ${widget.template['nom']}',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 17, fontWeight: FontWeight.w700, color: _dark)),
              const SizedBox(height: 6),

              // ── Cible description ──────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: _green.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Icon(Icons.group_outlined, size: 18, color: _green),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_cibleDescription,
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF063D4A)))),
                ]),
              ),
              const SizedBox(height: 14),

              // ── Multi-select animaux (individuel uniquement) ────────────────────
              if (_cibleType == 'individuel') ...[
                Row(
                  children: [
                    const _Label('Animaux concernés'),
                    const Spacer(),
                    TextButton(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      onPressed: () => setState(() {
                        final ids = _filteredAnimaux.map((a) => a['id'] as String).toSet();
                        if (_selectedIds.containsAll(ids) && ids.isNotEmpty) {
                          _selectedIds.removeAll(ids);
                        } else {
                          _selectedIds.addAll(ids);
                        }
                      }),
                      child: Text(
                        _filteredAnimaux.isNotEmpty && _selectedIds.containsAll(_filteredAnimaux.map((a) => a['id'] as String))
                            ? 'Tout désélect.' : 'Tout sélect.',
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _green),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Filtre sexe
                Row(children: [
                  for (final (v, l) in [('tous', 'Tous'), ('male', 'Mâles'), ('femelle', 'Femelles')])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(l, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                        selected: _sexeFilter == v,
                        onSelected: (_) => setState(() => _sexeFilter = v),
                        selectedColor: _green.withValues(alpha: 0.15),
                        checkmarkColor: _green,
                        labelStyle: TextStyle(color: _sexeFilter == v ? _green : Colors.grey.shade600),
                        side: BorderSide(color: _sexeFilter == v ? _green : Colors.grey.shade300),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                      ),
                    ),
                ]),
                const SizedBox(height: 6),
                if (_loadingRefs)
                  const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: _green)))
                else if (_filteredAnimaux.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('Aucun animal trouvé', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500)),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _filteredAnimaux.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final a  = _filteredAnimaux[i];
                          final id = a['id'] as String;
                          final sexe = a['sexe']?.toString() ?? '';
                          final sexeLabel = sexe == 'male' ? '♂' : sexe == 'femelle' ? '♀' : '';
                          return CheckboxListTile(
                            value: _selectedIds.contains(id),
                            onChanged: (v) => setState(() {
                              if (v == true) { _selectedIds.add(id); } else { _selectedIds.remove(id); }
                            }),
                            title: Text('${a['nom'] ?? ''} $sexeLabel',
                                style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                            subtitle: Text(a['espece']?.toString() ?? '',
                                style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
                            activeColor: _green,
                            controlAffinity: ListTileControlAffinity.leading,
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                          );
                        },
                      ),
                    ),
                  ),
                if (_selectedIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('${_selectedIds.length} animal${_selectedIds.length > 1 ? 'aux' : ''} sélectionné${_selectedIds.length > 1 ? 's' : ''}',
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _green, fontWeight: FontWeight.w600)),
                  ),
                const SizedBox(height: 14),
              ],

              // ── Date de référence ──────────────────────────────────────────────
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

              // ── Aperçu étapes ──────────────────────────────────────────────────
              if (etapes.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: _green.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _green.withValues(alpha: 0.2))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Aperçu des tâches',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: _green)),
                      const SizedBox(height: 8),
                      ...etapes.take(4).map((e) {
                        final direction  = e['offset_direction'] as String? ?? 'apres';
                        final produit    = e['produit']?.toString() ?? '';
                        final typeActe   = e['type_acte']?.toString() ?? '';
                        final frequence  = e['frequence']?.toString() ?? 'ponctuel';
                        final dureeJours = (e['duree_jours'] as num? ?? 1).toInt();
                        final dureeS     = (e['duree_semaines'] as num? ?? 1).toInt();
                        final nbFois     = (e['nb_fois_semaine'] as num? ?? 1).toInt();
                        final ageSem     = e['age_min_semaines'] as int?;

                        final dateLabel = ageSem != null
                            ? 'À $ageSem sem.'
                            : '${direction == 'avant' ? 'J-' : 'J+'}${(e['jour_offset'] as num? ?? 0).toInt()}';

                        String freqLabel = '';
                        if (frequence == 'quotidien')    freqLabel = '× $dureeS sem.';
                        if (frequence == 'hebdomadaire') freqLabel = '${nbFois}x/sem. × $dureeS sem.';
                        if (frequence == 'mensuel')      freqLabel = '× $dureeS mois';
                        if (frequence == 'ponctuel' && dureeJours > 1) freqLabel = '× $dureeJours j';

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(children: [
                            SizedBox(width: 64, child: Text(dateLabel,
                                style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: _green, fontWeight: FontWeight.w600))),
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
                      : const Text('Générer les tâches',
                          style: TextStyle(fontFamily: 'Galey', color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
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

