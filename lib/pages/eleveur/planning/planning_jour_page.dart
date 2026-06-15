import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:PetsMatch/services/planning_service.dart';
import 'package:PetsMatch/pages/eleveur/planning/plan_template_list_page.dart';

class PlanningJourPage extends StatefulWidget {
  const PlanningJourPage({super.key});
  @override
  State<PlanningJourPage> createState() => _PlanningJourPageState();
}

class _PlanningJourPageState extends State<PlanningJourPage> {
  static const _green = Color(0xFF6E9E57);
  static const _dark  = Color(0xFF1F2A2E);

  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _taches = [];
  bool _loading = true;
  String? _uid;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _load();
  }

  Future<void> _load() async {
    if (_uid == null) return;
    setState(() => _loading = true);
    final rows = await PlanningService.getTachesJour(_uid!, _selectedDate);
    if (mounted) setState(() { _taches = rows; _loading = false; });
  }

  Future<void> _valider(Map<String, dynamic> t, {String? notes}) async {
    await PlanningService.validerTache(
      t['id'] as String,
      validateurUid: _uid!,
      notes: notes,
      tacheData: t,
      uid: _uid!,
    );
    _load();
  }

  Future<void> _reporter(Map<String, dynamic> t) async {
    final date = DateTime.tryParse(t['date_prevue'] as String) ?? DateTime.now();
    await PlanningService.reporterTache(t['id'] as String, date);
    _load();
  }

  Future<void> _validerAvecNotes(Map<String, dynamic> t) async {
    final ctrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Valider la tâche', style: TextStyle(fontFamily: 'Galey')),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Notes (optionnel)', border: OutlineInputBorder()),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _green),
            child: const Text('Valider', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) await _valider(t, notes: ctrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('EEEE d MMMM', 'fr_FR');
    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _dark,
        foregroundColor: Colors.white,
        title: const Text('Planning', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt_outlined),
            tooltip: 'Mes protocoles',
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const PlanTemplateListPage(),
            )).then((_) => _load()),
          ),
        ],
      ),
      body: Column(
        children: [
          // Sélecteur de date
          _DateStrip(
            selected: _selectedDate,
            onSelected: (d) { setState(() { _selectedDate = d; _loading = true; }); _load(); },
          ),
          // En-tête du jour
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Text(
                  isToday ? 'Aujourd\'hui' : fmt.format(_selectedDate),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 18, fontWeight: FontWeight.w700, color: _dark),
                ),
                const Spacer(),
                if (_taches.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_taches.length} tâche${_taches.length > 1 ? 's' : ''}',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _green, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Liste des tâches
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _green))
                : _taches.isEmpty
                    ? _EmptyState(date: _selectedDate)
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _taches.length,
                        itemBuilder: (_, i) => _TacheCard(
                          tache: _taches[i],
                          onValider: () => _validerAvecNotes(_taches[i]),
                          onReporter: () => _reporter(_taches[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ─── Sélecteur de date (7 jours glissants) ───────────────────────────────────

class _DateStrip extends StatelessWidget {
  final DateTime selected;
  final ValueChanged<DateTime> onSelected;

  const _DateStrip({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = List.generate(7, (i) => today.subtract(Duration(days: 2)).add(Duration(days: i)));

    return Container(
      color: const Color(0xFF1F2A2E),
      height: 72,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: days.length,
        itemBuilder: (_, i) {
          final d = days[i];
          final active = DateUtils.isSameDay(d, selected);
          final isToday = DateUtils.isSameDay(d, today);
          return GestureDetector(
            onTap: () => onSelected(d),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 46,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: active ? const Color(0xFF6E9E57) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: isToday && !active
                    ? Border.all(color: const Color(0xFF6E9E57), width: 1.5)
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('EEE', 'fr_FR').format(d).substring(0, 2).toUpperCase(),
                    style: TextStyle(
                      fontFamily: 'Galey', fontSize: 10,
                      color: active ? Colors.white : Colors.grey.shade400,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${d.day}',
                    style: TextStyle(
                      fontFamily: 'Galey', fontSize: 18, fontWeight: FontWeight.w700,
                      color: active ? Colors.white : (isToday ? const Color(0xFF6E9E57) : Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Carte de tâche ──────────────────────────────────────────────────────────

class _TacheCard extends StatelessWidget {
  final Map<String, dynamic> tache;
  final VoidCallback onValider;
  final VoidCallback onReporter;

  const _TacheCard({required this.tache, required this.onValider, required this.onReporter});

  static const _green  = Color(0xFF6E9E57);
  static const _orange = Color(0xFFD97706);

  String get _typeEmoji {
    return switch (tache['type_acte']?.toString() ?? '') {
      'vermifuge'       => '💊',
      'vaccination'     => '💉',
      'antiparasitaire' => '🛡️',
      'traitement'      => '🩺',
      'visite'          => '🏥',
      'nettoyage'       => '🧹',
      'promenade'       => '🦮',
      'socialisation'   => '🐾',
      _                 => '📋',
    };
  }

  @override
  Widget build(BuildContext context) {
    final ref = (tache['plans_actifs'] as Map<String, dynamic>?)?['reference_label'] as String?;
    final totalJours = (tache['total_jours'] as num? ?? 1).toInt();
    final jourTraitement = (tache['jour_traitement'] as num? ?? 1).toInt();
    final isMultiJours = totalJours > 1;
    final statut = tache['statut']?.toString() ?? 'en_attente';
    final reporte = statut == 'reporte';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
        border: reporte ? Border.all(color: _orange.withValues(alpha: 0.4)) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Emoji type
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(child: Text(_typeEmoji, style: const TextStyle(fontSize: 20))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tache['label'] ?? '',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1F2A2E)),
                  ),
                  if (ref != null) ...[
                    const SizedBox(height: 3),
                    Text(ref, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
                  ],
                  if (isMultiJours) ...[
                    const SizedBox(height: 6),
                    _ProgressBar(current: jourTraitement, total: totalJours),
                  ],
                  if (reporte) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('Reporté', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: _orange)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Actions
            Column(
              children: [
                _ActionBtn(
                  icon: Icons.check_circle_outline,
                  color: _green,
                  tooltip: 'Valider',
                  onTap: onValider,
                ),
                const SizedBox(height: 6),
                _ActionBtn(
                  icon: Icons.schedule_outlined,
                  color: _orange,
                  tooltip: 'Reporter',
                  onTap: onReporter,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final int current;
  final int total;
  const _ProgressBar({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: current / total,
              backgroundColor: const Color(0xFF6E9E57).withValues(alpha: 0.15),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF6E9E57)),
              minHeight: 5,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'J$current/$total',
          style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6E9E57), fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionBtn({required this.icon, required this.color, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }
}

// ─── État vide ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final DateTime date;
  const _EmptyState({required this.date});

  @override
  Widget build(BuildContext context) {
    final isToday = DateUtils.isSameDay(date, DateTime.now());
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_available_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            isToday ? 'Aucune tâche aujourd\'hui' : 'Aucune tâche ce jour',
            style: TextStyle(fontFamily: 'Galey', fontSize: 16, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 8),
          Text(
            'Créez des protocoles pour générer\ndes tâches automatiquement',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const PlanTemplateListPage(),
            )),
            icon: const Icon(Icons.add, size: 18, color: Color(0xFF6E9E57)),
            label: const Text('Créer un protocole', style: TextStyle(fontFamily: 'Galey', color: Color(0xFF6E9E57))),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF6E9E57))),
          ),
        ],
      ),
    );
  }
}
