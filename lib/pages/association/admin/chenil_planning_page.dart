import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Planning des séjours au chenil/refuge : vue calendrier semaine + liste.
class ChenilPlanningPage extends StatefulWidget {
  const ChenilPlanningPage({super.key});
  @override
  State<ChenilPlanningPage> createState() => _ChenilPlanningPageState();
}

class _ChenilPlanningPageState extends State<ChenilPlanningPage> with SingleTickerProviderStateMixin {
  final _supa = Supabase.instance.client;

  static const _teal = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  late TabController _tabs;
  bool _loading = true;

  // Animaux actuellement au chenil (statut = present ou en_soin)
  List<Map<String, dynamic>> _enChenil = [];
  // Tous les animaux de l'association pour planifier les entrées/sorties
  List<Map<String, dynamic>> _animaux = [];

  DateTime _weekStart = _mondayOf(DateTime.now());

  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  static DateTime _mondayOf(DateTime d) {
    return d.subtract(Duration(days: d.weekday - 1));
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _loading = true);
    try {
      final allAnimaux = await _supa
          .from('animaux')
          .select('id, nom, espece, photo_url, statut, date_entree, date_sortie')
          .eq('uid_eleveur', uid)
          .order('nom');

      final list = List<Map<String, dynamic>>.from(allAnimaux as List);
      if (mounted) {
        setState(() {
          _animaux = list;
          _enChenil = list.where((a) =>
              a['statut'] == 'present' ||
              a['statut'] == 'en_soin' ||
              a['statut'] == 'disponible').toList();
          _filteredChenil = List.from(_enChenil);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateStatut(String animalId, String newStatut) async {
    await _supa.from('animaux').update({'statut': newStatut}).eq('id', animalId);
    _load();
  }

  Future<void> _updateDates(String animalId, {DateTime? entree, DateTime? sortie}) async {
    final update = <String, dynamic>{};
    if (entree != null) update['date_entree'] = entree.toIso8601String().substring(0, 10);
    if (sortie != null) update['date_sortie'] = sortie.toIso8601String().substring(0, 10);
    if (update.isNotEmpty) {
      await _supa.from('animaux').update(update).eq('id', animalId);
      _load();
    }
  }

  void _showStatutSheet(Map<String, dynamic> animal) {
    final statuts = [
      ('en_soin', 'En soin', Colors.orange),
      ('disponible', 'Disponible', _green),
      ('en_fa', 'En famille d\'accueil', Colors.purple),
      ('adopte', 'Adopté', _teal),
      ('transfere', 'Transféré', Colors.blue),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Changer le statut de ${animal['nom'] ?? '?'}',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            ...statuts.map((s) => ListTile(
              leading: CircleAvatar(backgroundColor: s.$3, radius: 8),
              title: Text(s.$2, style: const TextStyle(fontFamily: 'Galey')),
              onTap: () {
                Navigator.pop(context);
                _updateStatut(animal['id'], s.$1);
              },
            )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal,
        title: const Text('Chenil / Planning',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600),
          tabs: const [Tab(text: 'Au chenil'), Tab(text: 'Vue semaine')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _buildListView(),
                _buildWeekView(),
              ],
            ),
    );
  }

  // ── Onglet liste ──────────────────────────────────────────────────────────

  Widget _buildListView() {
    if (_enChenil.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.home_work_outlined, size: 60, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            const Text('Aucun animal au chenil',
                style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _enChenil.length,
      itemBuilder: (_, i) {
        final a = _enChenil[i];
        return _ChenilCard(
          animal: a,
          onStatut: () => _showStatutSheet(a),
          onDateEntree: () async {
            final d = await _pickDate(
                initial: a['date_entree'] != null ? DateTime.tryParse(a['date_entree']) : null);
            if (d != null) _updateDates(a['id'], entree: d);
          },
          onDateSortie: () async {
            final d = await _pickDate(
                initial: a['date_sortie'] != null ? DateTime.tryParse(a['date_sortie']) : null);
            if (d != null) _updateDates(a['id'], sortie: d);
          },
        );
      },
    );
  }

  // ── Onglet semaine ────────────────────────────────────────────────────────

  Widget _buildWeekView() {
    final days = List.generate(7, (i) => _weekStart.add(Duration(days: i)));
    final fmt = DateFormat('EEE d', 'fr_FR');
    final today = DateTime.now();

    return Column(
      children: [
        // Navigation semaine
        Container(
          color: _teal.withValues(alpha: 0.06),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Color(0xFF0C5C6C)),
                onPressed: () => setState(() => _weekStart = _weekStart.subtract(const Duration(days: 7))),
              ),
              Expanded(
                child: Text(
                  'Semaine du ${DateFormat('d MMM', 'fr_FR').format(_weekStart)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Color(0xFF0C5C6C)),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, color: Color(0xFF0C5C6C)),
                onPressed: () => setState(() => _weekStart = _weekStart.add(const Duration(days: 7))),
              ),
            ],
          ),
        ),
        // En-têtes jours
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              const SizedBox(width: 90),
              ...days.map((d) {
                final isToday = d.day == today.day && d.month == today.month && d.year == today.year;
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: isToday ? _green.withValues(alpha: 0.15) : null,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(fmt.format(d).capitalize(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontFamily: 'Galey', fontSize: 10,
                            fontWeight: isToday ? FontWeight.w700 : FontWeight.normal,
                            color: isToday ? _green : Colors.grey)),
                  ),
                );
              }),
            ],
          ),
        ),
        const Divider(height: 1),
        // Corps planning
        Expanded(
          child: _animaux.isEmpty
              ? const Center(child: Text('Aucun animal', style: TextStyle(fontFamily: 'Galey', color: Colors.grey)))
              : ListView.builder(
                  itemCount: _animaux.length,
                  itemBuilder: (_, i) {
                    final a = _animaux[i];
                    final entree = a['date_entree'] != null ? DateTime.tryParse(a['date_entree']) : null;
                    final sortie = a['date_sortie'] != null ? DateTime.tryParse(a['date_sortie']) : null;
                    return _PlanningRow(
                      animal: a,
                      days: days,
                      dateEntree: entree,
                      dateSortie: sortie,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<DateTime?> _pickDate({DateTime? initial}) => showDatePicker(
    context: context,
    initialDate: initial ?? DateTime.now(),
    firstDate: DateTime(2020),
    lastDate: DateTime(2030),
    locale: const Locale('fr', 'FR'),
  );
}

// ── Row planning semaine ──────────────────────────────────────────────────────

class _PlanningRow extends StatelessWidget {
  final Map<String, dynamic> animal;
  final List<DateTime> days;
  final DateTime? dateEntree;
  final DateTime? dateSortie;

  const _PlanningRow({
    required this.animal,
    required this.days,
    this.dateEntree,
    this.dateSortie,
  });

  static const _statusColor = {
    'en_soin': Colors.orange,
    'disponible': Color(0xFF6E9E57),
    'en_fa': Colors.purple,
    'adopte': Color(0xFF0C5C6C),
    'transfere': Colors.blue,
  };

  bool _isPresentOn(DateTime day) {
    if (dateEntree == null) return false;
    final start = DateTime(dateEntree!.year, dateEntree!.month, dateEntree!.day);
    final end = dateSortie != null
        ? DateTime(dateSortie!.year, dateSortie!.month, dateSortie!.day)
        : DateTime(2099);
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  @override
  Widget build(BuildContext context) {
    final statut = animal['statut']?.toString() ?? '';
    final color = _statusColor[statut] ?? Colors.grey;
    return Container(
      height: 40,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(animal['nom']?.toString() ?? '?',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          ...days.map((d) {
            final present = _isPresentOn(d);
            return Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 6),
                decoration: BoxDecoration(
                  color: present ? color.withValues(alpha: 0.25) : null,
                  borderRadius: BorderRadius.circular(4),
                  border: present ? Border.all(color: color.withValues(alpha: 0.5)) : null,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Carte animal au chenil ────────────────────────────────────────────────────

class _ChenilCard extends StatelessWidget {
  final Map<String, dynamic> animal;
  final VoidCallback onStatut;
  final VoidCallback onDateEntree;
  final VoidCallback onDateSortie;

  const _ChenilCard({
    required this.animal,
    required this.onStatut,
    required this.onDateEntree,
    required this.onDateSortie,
  });

  static const _statutColors = {
    'en_soin': Colors.orange,
    'disponible': Color(0xFF6E9E57),
    'en_fa': Colors.purple,
    'adopte': Color(0xFF0C5C6C),
    'transfere': Colors.blue,
    'present': Color(0xFF6E9E57),
  };
  static const _statutLabels = {
    'en_soin': 'En soin',
    'disponible': 'Disponible',
    'en_fa': 'En FA',
    'adopte': 'Adopté',
    'transfere': 'Transféré',
    'present': 'Présent',
  };

  String _fmt(dynamic d) {
    if (d == null) return '—';
    try {
      return DateFormat('dd/MM/yyyy').format(DateTime.parse(d.toString()));
    } catch (_) {
      return d.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final statut = animal['statut']?.toString() ?? '';
    final color = _statutColors[statut] ?? Colors.grey;
    final label = _statutLabels[statut] ?? statut;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(animal['nom']?.toString() ?? '?',
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                GestureDetector(
                  onTap: onStatut,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(label,
                            style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                                fontWeight: FontWeight.w700, color: color)),
                        const SizedBox(width: 4),
                        Icon(Icons.expand_more, size: 14, color: color),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _DateChip(label: 'Entrée', date: _fmt(animal['date_entree']), onTap: onDateEntree),
                const SizedBox(width: 10),
                _DateChip(label: 'Sortie prévue', date: _fmt(animal['date_sortie']), onTap: onDateSortie),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  final String label;
  final String date;
  final VoidCallback onTap;

  const _DateChip({required this.label, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F4F8),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.grey)),
            Text(date,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

extension _StringExt on String {
  String capitalize() => isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
