import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';

extension _Capitalize on String {
  String capitalize() => isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}

class ChenilPlanningPage extends StatefulWidget {
  const ChenilPlanningPage({super.key});
  @override
  State<ChenilPlanningPage> createState() => _ChenilPlanningPageState();
}

class _ChenilPlanningPageState extends State<ChenilPlanningPage>
    with SingleTickerProviderStateMixin {
  final _supa = Supabase.instance.client;

  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  late TabController _tabs;
  bool _loading = true;

  List<Map<String, dynamic>> _animaux = [];
  List<_Enclos> _enclos = [];

  DateTime _weekStart = _mondayOf(DateTime.now());

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  static DateTime _mondayOf(DateTime d) =>
      d.subtract(Duration(days: d.weekday - 1));

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _loading = true);
    try {
      // Récupérer le profile_id du profil association actif
      final profileData = await _supa.from('user_profiles')
          .select('id')
          .eq('uid', uid)
          .eq('profile_type', 'association')
          .eq('is_main', true)
          .maybeSingle();
      final profileId = profileData?['id'] as String?;

      final _enclosBase = _supa
          .from('enclos_chenil')
          .select('id, nom, type, capacite, dernier_nettoyage, notes')
          .eq('is_association', true);
      final enclosQuery = profileId != null
          ? _enclosBase.eq('profile_id', profileId).order('nom')
          : _enclosBase.eq('uid_eleveur', uid).order('nom');

      final results = await Future.wait([
        enclosQuery,
        _supa
            .from('animaux')
            .select('id, nom, espece, photo_url, statut, date_entree, date_sortie, enclos_id')
            .eq('uid_eleveur', uid)
            .eq('is_association', true)
            .order('nom'),
      ]);

      final enclosList = (results[0] as List)
          .map((r) => _Enclos.fromMap(r as Map<String, dynamic>))
          .toList();
      final animauxList = List<Map<String, dynamic>>.from(results[1] as List);

      if (mounted) setState(() {
        _enclos  = enclosList;
        _animaux = animauxList;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur chargement : $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _addEnclos() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final data = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _AddEnclosSheet(),
    );

    if (data == null || !mounted) return;

    try {
      final profileData = await _supa.from('user_profiles')
          .select('id')
          .eq('uid', uid)
          .eq('profile_type', 'association')
          .eq('is_main', true)
          .maybeSingle();
      final profileId = profileData?['id'] as String?;

      await _supa.from('enclos_chenil').insert({
        'uid_eleveur':    uid,
        'profile_id':     profileId,
        'is_association': true,
        'nom':            data['nom'],
        'type':           data['type'],
        'capacite':       data['capacite'],
        'notes':          data['notes']?.isNotEmpty == true ? data['notes'] : null,
      }).select();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enclos créé !'), backgroundColor: Colors.green));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red,
                duration: const Duration(seconds: 8)));
      }
    }
  }

  Future<void> _markClean(String enclosId) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await _supa.from('enclos_chenil').update({
      'dernier_nettoyage': today,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', enclosId);
    setState(() {
      _enclos = _enclos.map((e) => e.id == enclosId ? e.copyWith(dernierNettoyage: today) : e).toList();
    });
  }

  Future<void> _assignEnclos(Map<String, dynamic> animal) async {
    if (_enclos.isEmpty) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Assigner ${animal['nom']} à un enclos',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            ..._enclos.map((enc) {
              final count = _animaux.where((a) => a['enclos_id'] == enc.id).length;
              final full  = count >= enc.capacite;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: full ? Colors.red.shade100 : _green.withValues(alpha: 0.15),
                  child: Text('$count/${enc.capacite}',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                          color: full ? Colors.red : _teal, fontWeight: FontWeight.w700)),
                ),
                title: Text(enc.nom, style: const TextStyle(fontFamily: 'Galey')),
                subtitle: Text(
                  full ? 'Complet' : '${enc.typeLabel} · ${enc.capacite - count} place(s)',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                      color: full ? Colors.red : Colors.grey)),
                enabled: !full,
                onTap: full ? null : () async {
                  Navigator.pop(context);
                  await _supa.from('animaux').update({'enclos_id': enc.id}).eq('id', animal['id']);
                  _load();
                },
              );
            }),
            ListTile(
              leading: const CircleAvatar(
                  backgroundColor: Colors.grey,
                  child: Icon(Icons.close, color: Colors.white, size: 16)),
              title: const Text('Retirer de l\'enclos', style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
              onTap: () async {
                Navigator.pop(context);
                if (animal['enclos_id'] != null) {
                  await _supa.from('animaux').update({'enclos_id': null}).eq('id', animal['id']);
                  _load();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateStatut(String id, String statut) async {
    await _supa.from('animaux').update({'statut': statut}).eq('id', id);
    _load();
  }

  Future<void> _updateDates(String id, {DateTime? entree, DateTime? sortie}) async {
    final u = <String, dynamic>{};
    if (entree != null) u['date_entree'] = entree.toIso8601String().substring(0, 10);
    if (sortie != null) u['date_sortie'] = sortie.toIso8601String().substring(0, 10);
    if (u.isNotEmpty) { await _supa.from('animaux').update(u).eq('id', id); _load(); }
  }

  Future<DateTime?> _pickDate({DateTime? initial}) => showDatePicker(
    context: context,
    initialDate: initial ?? DateTime.now(),
    firstDate: DateTime(2020), lastDate: DateTime(2030),
    builder: (ctx, child) => Theme(
      data: ThemeData.light().copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF0C5C6C))),
      child: child!,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal,
        title: const Text('Chenil / Planning',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_box_outlined),
            tooltip: 'Nouvel enclos',
            onPressed: _addEnclos,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600),
          tabs: const [Tab(text: 'Enclos'), Tab(text: 'Vue semaine')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: _tabs, children: [
              _buildEnclosView(),
              _buildWeekView(),
            ]),
    );
  }

  Widget _buildEnclosView() {
    // Stats globales
    final totalPlaces = _enclos.fold(0, (s, e) => s + e.capacite);
    final occupes = _animaux.where((a) => a['enclos_id'] != null).length;
    final sansEnclos = _animaux.where((a) =>
        a['enclos_id'] == null &&
        ['present', 'en_soin', 'disponible'].contains(a['statut'])).length;

    if (_animaux.isEmpty && _enclos.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.home_work_outlined, size: 60, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('Aucun enclos configuré', style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
          const SizedBox(height: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white),
            onPressed: _addEnclos,
            child: const Text('Créer un enclos', style: TextStyle(fontFamily: 'Galey')),
          ),
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Résumé
          if (_enclos.isNotEmpty) ...[
            Row(children: [
              _StatChip(label: '$occupes/$totalPlaces', sub: 'Occupés', color: _teal),
              const SizedBox(width: 8),
              _StatChip(label: '${totalPlaces - occupes}', sub: 'Libres', color: _green),
              const SizedBox(width: 8),
              _StatChip(label: '$sansEnclos', sub: 'Sans enclos',
                  color: sansEnclos > 0 ? Colors.orange : Colors.grey),
            ]),
            const SizedBox(height: 12),
          ],
          // Cartes enclos
          ..._enclos.map((enc) {
            final inEnclos = _animaux.where((a) => a['enclos_id'] == enc.id).toList();
            return _EnclosCard(
              enclos: enc,
              animals: inEnclos,
              allAnimaux: _animaux,
              onAssign: (a) => _assignEnclos(a),
              onAnimalTap: _showAnimalSheet,
              onClean: () => _markClean(enc.id),
            );
          }),
          // Sans enclos
          if (sansEnclos > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  Text('$sansEnclos animal(s) sans enclos',
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                          fontSize: 13, color: Colors.orange)),
                ]),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: _animaux
                      .where((a) => a['enclos_id'] == null &&
                          ['present', 'en_soin', 'disponible'].contains(a['statut']))
                      .map((a) => _AnimalChip(
                        animal: a,
                        onTap: () => _showAnimalSheet(a),
                        onAssign: _enclos.isNotEmpty ? () => _assignEnclos(a) : null,
                      )).toList(),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  void _showAnimalSheet(Map<String, dynamic> a) {
    final statuts = [
      ('en_soin', 'En soin', Colors.orange),
      ('disponible', 'Disponible', _green),
      ('adopte', 'Adopté', _teal),
      ('transfere', 'Transféré', Colors.blue),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _photoWidget(a['photo_url']?.toString() ?? '', radius: 24),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a['nom']?.toString() ?? '',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
              Text('${a['espece'] ?? ''} · ${a['statut'] ?? ''}',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
            ])),
          ]),
          const Divider(height: 20),
          const Text('Changer statut',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: statuts.map((s) {
            final active = a['statut'] == s.$1;
            return GestureDetector(
              onTap: () { Navigator.pop(context); _updateStatut(a['id'], s.$1); },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: active ? s.$3 : Colors.transparent,
                  border: Border.all(color: active ? s.$3 : Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(s.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                    fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                    color: active ? Colors.white : Colors.black87)),
              ),
            );
          }).toList()),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today_outlined, size: 14),
                label: Text(
                  a['date_entree'] != null ? 'Entrée : ${_fmtDate(a['date_entree'])}' : "Date d'entrée",
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                onPressed: () async {
                  final d = await _pickDate(
                      initial: a['date_entree'] != null ? DateTime.tryParse(a['date_entree']) : null);
                  if (d != null) { if(context.mounted) Navigator.pop(context); _updateDates(a['id'], entree: d); }
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.exit_to_app_outlined, size: 14),
                label: Text(
                  a['date_sortie'] != null ? 'Sortie : ${_fmtDate(a['date_sortie'])}' : 'Date de sortie',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                onPressed: () async {
                  final d = await _pickDate(
                      initial: a['date_sortie'] != null ? DateTime.tryParse(a['date_sortie']) : null);
                  if (d != null) { if(context.mounted) Navigator.pop(context); _updateDates(a['id'], sortie: d); }
                },
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _buildWeekView() {
    final days = List.generate(7, (i) => _weekStart.add(Duration(days: i)));
    final fmt  = DateFormat('EEE d', 'fr_FR');
    final today = DateTime.now();

    return Column(children: [
      Container(
        color: _teal.withValues(alpha: 0.06),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Color(0xFF0C5C6C)),
            onPressed: () => setState(() => _weekStart = _weekStart.subtract(const Duration(days: 7))),
          ),
          Expanded(
            child: Text('Semaine du ${DateFormat('d MMM', 'fr_FR').format(_weekStart)}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Color(0xFF0C5C6C))),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Color(0xFF0C5C6C)),
            onPressed: () => setState(() => _weekStart = _weekStart.add(const Duration(days: 7))),
          ),
        ]),
      ),
      Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
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
                    style: TextStyle(fontFamily: 'Galey', fontSize: 10,
                        fontWeight: isToday ? FontWeight.w700 : FontWeight.normal,
                        color: isToday ? _green : Colors.grey)),
              ),
            );
          }),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: _animaux.isEmpty
            ? const Center(child: Text('Aucun animal', style: TextStyle(fontFamily: 'Galey', color: Colors.grey)))
            : ListView.builder(
                itemCount: _animaux.length,
                itemBuilder: (_, i) {
                  final a = _animaux[i];
                  final entree = a['date_entree'] != null ? DateTime.tryParse(a['date_entree']) : null;
                  final sortie = a['date_sortie'] != null ? DateTime.tryParse(a['date_sortie']) : null;
                  return _PlanningRow(animal: a, days: days, dateEntree: entree, dateSortie: sortie);
                },
              ),
      ),
    ]);
  }

  static String _fmtDate(dynamic d) {
    if (d == null) return '';
    try { return DateFormat('dd/MM/yy').format(DateTime.parse(d.toString())); } catch (_) { return d.toString(); }
  }

  static Widget _photoWidget(String url, {double radius = 20}) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFDCEDD5),
      backgroundImage: url.isNotEmpty ? CachedNetworkImageProvider(url) as ImageProvider : null,
      child: url.isEmpty ? Icon(Icons.pets, color: const Color(0xFF6E9E57), size: radius * 0.8) : null,
    );
  }
}

// ── Modèle Enclos ──────────────────────────────────────────────────────────

class _Enclos {
  final String  id;
  final String  nom;
  final String  type;
  final int     capacite;
  final String? dernierNettoyage;
  final String? notes;

  static const _typeLabels = {'box': 'Box', 'enclos': 'Enclos', 'chatterie': 'Chatterie', 'cage': 'Cage'};
  static const _typeIcons  = {'box': Icons.home_work_outlined, 'enclos': Icons.grass, 'chatterie': Icons.pets, 'cage': Icons.grid_view};

  const _Enclos({required this.id, required this.nom, required this.type,
      required this.capacite, this.dernierNettoyage, this.notes});

  factory _Enclos.fromMap(Map<String, dynamic> m) => _Enclos(
    id:               m['id']?.toString() ?? '',
    nom:              m['nom']?.toString() ?? '',
    type:             m['type']?.toString() ?? 'box',
    capacite:         (m['capacite'] as num?)?.toInt() ?? 1,
    dernierNettoyage: m['dernier_nettoyage']?.toString(),
    notes:            m['notes']?.toString(),
  );

  _Enclos copyWith({String? dernierNettoyage}) => _Enclos(
    id: id, nom: nom, type: type, capacite: capacite,
    dernierNettoyage: dernierNettoyage ?? this.dernierNettoyage,
    notes: notes,
  );

  String get typeLabel => _typeLabels[type] ?? type;
  IconData get typeIcon => _typeIcons[type] ?? Icons.home_work_outlined;

  int? get joursSansNettoyage {
    if (dernierNettoyage == null) return null;
    final d = DateTime.tryParse(dernierNettoyage!);
    if (d == null) return null;
    return DateTime.now().difference(d).inDays;
  }
}

// ── Widget stat ────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label, sub;
  final Color color;
  const _StatChip({required this.label, required this.sub, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(children: [
          Text(label, style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
              fontSize: 20, color: color)),
          Text(sub, style: const TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.grey)),
        ]),
      ),
    );
  }
}

// ── Card Enclos ────────────────────────────────────────────────────────────

class _EnclosCard extends StatelessWidget {
  final _Enclos enclos;
  final List<Map<String, dynamic>> animals;
  final List<Map<String, dynamic>> allAnimaux;
  final void Function(Map<String, dynamic>) onAssign;
  final void Function(Map<String, dynamic>) onAnimalTap;
  final VoidCallback onClean;

  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  const _EnclosCard({
    required this.enclos, required this.animals, required this.allAnimaux,
    required this.onAssign, required this.onAnimalTap, required this.onClean,
  });

  Color get _barColor {
    final ratio = animals.length / enclos.capacite;
    if (ratio >= 1) return Colors.red.shade400;
    if (ratio >= 0.75) return Colors.orange;
    return _green;
  }

  @override
  Widget build(BuildContext context) {
    final pct    = (animals.length / enclos.capacite).clamp(0.0, 1.0);
    final jours  = enclos.joursSansNettoyage;
    final dispo  = enclos.capacite - animals.length;

    String cleanLabel;
    Color  cleanColor;
    if (jours == null)       { cleanLabel = 'Jamais nettoyé'; cleanColor = Colors.red; }
    else if (jours == 0)     { cleanLabel = "Nettoyé aujourd'hui"; cleanColor = _green; }
    else if (jours <= 2)     { cleanLabel = 'Il y a ${jours}j'; cleanColor = _green; }
    else if (jours <= 7)     { cleanLabel = 'Il y a ${jours}j'; cleanColor = Colors.orange; }
    else                     { cleanLabel = 'Il y a ${jours}j'; cleanColor = Colors.red; }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
        border: Border.all(color: Colors.teal.shade50),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // En-tête
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(children: [
            Icon(enclos.typeIcon, color: _teal, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(enclos.nom, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
              Text(enclos.typeLabel, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.teal)),
            ])),
            Text('${animals.length}/${enclos.capacite}',
                style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: pct >= 1 ? Colors.red : _teal)),
          ]),
        ),

        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Barre capacité
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct, minHeight: 5,
                backgroundColor: Colors.grey.shade100,
                valueColor: AlwaysStoppedAnimation(_barColor),
              ),
            ),
            const SizedBox(height: 10),

            // Nettoyage
            Row(children: [
              const Text('🧹', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cleanColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(cleanLabel,
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: cleanColor, fontWeight: FontWeight.w600)),
              ),
              const Spacer(),
              TextButton(
                style: TextButton.styleFrom(
                    minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20),
                        side: BorderSide(color: _teal.withValues(alpha: 0.4))),
                    foregroundColor: _teal),
                onPressed: onClean,
                child: const Text('Marquer propre', style: TextStyle(fontFamily: 'Galey', fontSize: 11)),
              ),
            ]),

            if (enclos.notes?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(enclos.notes!,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey,
                      fontStyle: FontStyle.italic)),
            ],

            // Animaux
            if (animals.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: animals.map((a) =>
                  _AnimalChip(animal: a, onTap: () => onAnimalTap(a), showBox: false)).toList()),
            ] else ...[
              const SizedBox(height: 10),
              const Text('Aucun animal', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
            ],

            // Bouton ajouter
            if (dispo > 0) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () {
                  final available = allAnimaux.where((a) => a['enclos_id'] == null).toList();
                  if (available.isEmpty) return;
                  // Ouvre le sheet avec filtre pour cet enclos
                  onAssign(available.first);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade200, style: BorderStyle.solid),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('+ Ajouter un animal',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

// ── Animal chip ────────────────────────────────────────────────────────────

class _AnimalChip extends StatelessWidget {
  final Map<String, dynamic> animal;
  final VoidCallback onTap;
  final VoidCallback? onAssign;
  final bool showBox;

  static const _statutColors = {
    'en_soin':    Colors.orange,
    'disponible': Color(0xFF6E9E57),
    'en_fa':      Colors.purple,
    'adopte':     Color(0xFF0C5C6C),
    'transfere':  Colors.blue,
  };

  const _AnimalChip({required this.animal, required this.onTap, this.onAssign, this.showBox = true});

  @override
  Widget build(BuildContext context) {
    final nom    = animal['nom']?.toString() ?? '?';
    final photo  = animal['photo_url']?.toString() ?? '';
    final statut = animal['statut']?.toString() ?? '';
    final color  = _statutColors[statut] ?? Colors.grey;

    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Stack(children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: const Color(0xFFDCEDD5),
            backgroundImage: photo.isNotEmpty ? CachedNetworkImageProvider(photo) as ImageProvider : null,
            child: photo.isEmpty ? const Icon(Icons.pets, color: Color(0xFF6E9E57), size: 22) : null,
          ),
          Positioned(
            bottom: 0, right: 0,
            child: Container(
              width: 12, height: 12,
              decoration: BoxDecoration(
                color: color, shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
          if (onAssign != null)
            Positioned(
              top: 0, right: 0,
              child: GestureDetector(
                onTap: onAssign,
                child: Container(
                  width: 16, height: 16,
                  decoration: const BoxDecoration(color: Color(0xFF0C5C6C), shape: BoxShape.circle),
                  child: const Icon(Icons.add, color: Colors.white, size: 10),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 4),
        SizedBox(
          width: 52,
          child: Text(nom, textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 10),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}

// ── Planning row ───────────────────────────────────────────────────────────

class _PlanningRow extends StatelessWidget {
  final Map<String, dynamic> animal;
  final List<DateTime> days;
  final DateTime? dateEntree;
  final DateTime? dateSortie;

  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  const _PlanningRow({required this.animal, required this.days,
      required this.dateEntree, required this.dateSortie});

  @override
  Widget build(BuildContext context) {
    final photo = animal['photo_url']?.toString() ?? '';
    final nom   = animal['nom']?.toString() ?? '';

    return Container(
      height: 44,
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE)))),
      child: Row(children: [
        SizedBox(
          width: 90,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFFDCEDD5),
                backgroundImage: photo.isNotEmpty ? CachedNetworkImageProvider(photo) as ImageProvider : null,
                child: photo.isEmpty ? const Icon(Icons.pets, color: Color(0xFF6E9E57), size: 12) : null,
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(nom,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 11),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
          ),
        ),
        ...days.map((d) {
          final inRange = (dateEntree == null || !d.isBefore(dateEntree!)) &&
                          (dateSortie == null || !d.isAfter(dateSortie!));
          final isFirst = dateEntree != null && d.year == dateEntree!.year &&
                          d.month == dateEntree!.month && d.day == dateEntree!.day;
          final isLast  = dateSortie != null && d.year == dateSortie!.year &&
                          d.month == dateSortie!.month && d.day == dateSortie!.day;
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 10),
              decoration: BoxDecoration(
                color: inRange ? _teal.withValues(alpha: 0.18) : Colors.transparent,
                borderRadius: BorderRadius.horizontal(
                  left:  isFirst ? const Radius.circular(6) : Radius.zero,
                  right: isLast  ? const Radius.circular(6) : Radius.zero,
                ),
              ),
            ),
          );
        }),
      ]),
    );
  }
}

// ── Sheet création enclos ──────────────────────────────────────────────────

class _AddEnclosSheet extends StatefulWidget {
  const _AddEnclosSheet();
  @override
  State<_AddEnclosSheet> createState() => _AddEnclosSheetState();
}

class _AddEnclosSheetState extends State<_AddEnclosSheet> {
  static const _teal = Color(0xFF0C5C6C);

  final _nomCtrl   = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _type     = 'box';
  int    _capacite = 2;

  @override
  void dispose() { _nomCtrl.dispose(); _notesCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nouvel enclos',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
            const SizedBox(height: 16),
            TextField(
              controller: _nomCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nom *',
                hintText: 'Ex : Box 1, Chatterie A, Quarantaine…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'box',       child: Text('🏠 Box')),
                DropdownMenuItem(value: 'enclos',    child: Text('🌿 Enclos')),
                DropdownMenuItem(value: 'chatterie', child: Text('🐈 Chatterie')),
                DropdownMenuItem(value: 'cage',      child: Text('🔲 Cage')),
              ],
              onChanged: (v) => setState(() => _type = v ?? 'box'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Text('Capacité :', style: TextStyle(fontFamily: 'Galey')),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => setState(() { if (_capacite > 1) _capacite--; }),
              ),
              Text('$_capacite',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => setState(() => _capacite++),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes (optionnel)',
                hintText: 'Infos utiles…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _teal, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () {
                  final nom = _nomCtrl.text.trim();
                  if (nom.isEmpty) return;
                  Navigator.pop(context, {
                    'nom':      nom,
                    'type':     _type,
                    'capacite': _capacite,
                    'notes':    _notesCtrl.text.trim(),
                  });
                },
                child: const Text('Créer l\'enclos',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
