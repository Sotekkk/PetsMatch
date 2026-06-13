import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';

extension _Capitalize on String {
  String capitalize() => isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}

/// Planning chenil : vue boxes + calendrier semaine.
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

  // Animaux au chenil (statuts présents)
  List<Map<String, dynamic>> _animaux = [];

  // Boxes gérées par l'association (stockées en Supabase si dispo)
  List<_Box> _boxes = [];

  DateTime _weekStart = _mondayOf(DateTime.now());

  static const _assoStatuts = ['en_soin', 'disponible', 'en_fa'];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  static DateTime _mondayOf(DateTime d) =>
      d.subtract(Duration(days: d.weekday - 1));

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _loading = true);
    try {
      final allAnimaux = await _supa
          .from('animaux')
          .select('id,nom,espece,photo_url,statut,date_entree,date_sortie,box_id')
          .eq('uid_eleveur', uid)
          .eq('is_association', true)
          .order('nom');
      final list = List<Map<String, dynamic>>.from(allAnimaux as List);

      // Charge les boxes si la table existe
      List<_Box> boxes = [];
      try {
        final boxRows = await _supa
            .from('chenil_boxes')
            .select()
            .eq('association_uid', uid)
            .order('nom');
        boxes = (boxRows as List).map((r) => _Box.fromMap(r as Map<String, dynamic>)).toList();
      } catch (_) {
        // Table pas encore créée — génère des boxes virtuelles par espèce
        boxes = _generateVirtualBoxes(list);
      }

      if (mounted) setState(() { _animaux = list; _boxes = boxes; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_Box> _generateVirtualBoxes(List<Map<String, dynamic>> animaux) {
    final speciesCounts = <String, int>{};
    for (final a in animaux) {
      final esp = a['espece']?.toString() ?? 'autre';
      speciesCounts[esp] = (speciesCounts[esp] ?? 0) + 1;
    }
    final boxes = <_Box>[];
    for (final entry in speciesCounts.entries) {
      final cap = entry.value > 4 ? (entry.value + 1) : 4;
      boxes.add(_Box(id: 'virtual_${entry.key}', nom: _especeLabel(entry.key), espece: entry.key, capacite: cap));
    }
    return boxes;
  }

  Future<void> _addBox() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    String espece = 'chien';
    int capacite = 2;
    final nomCtrl = TextEditingController();

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nouvelle box', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
            const SizedBox(height: 16),
            TextField(
              controller: nomCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nom de la box',
                hintText: 'Ex : Box 1, Chatterie, Quarantaine…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: espece,
              decoration: const InputDecoration(labelText: 'Espèce', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'chien',  child: Text('Chien')),
                DropdownMenuItem(value: 'chat',   child: Text('Chat')),
                DropdownMenuItem(value: 'lapin',  child: Text('Lapin')),
                DropdownMenuItem(value: 'nac',    child: Text('NAC')),
                DropdownMenuItem(value: 'oiseau', child: Text('Oiseau')),
                DropdownMenuItem(value: 'autre',  child: Text('Autre')),
              ],
              onChanged: (v) => setSheet(() => espece = v ?? 'chien'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Text('Capacité :', style: TextStyle(fontFamily: 'Galey')),
              const SizedBox(width: 12),
              IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => setSheet(() { if (capacite > 1) capacite--; })),
              Text('$capacite', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
              IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => setSheet(() => capacite++)),
            ]),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () async {
                  final nom = nomCtrl.text.trim();
                  if (nom.isEmpty) return;
                  try {
                    await _supa.from('chenil_boxes').insert({
                      'association_uid': uid, 'nom': nom, 'espece': espece, 'capacite': capacite,
                    });
                  } catch (_) {}
                  if (ctx.mounted) Navigator.pop(ctx, true);
                },
                child: const Text('Créer la box', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      )),
    );
    if (result == true) _load();
  }

  Future<void> _assignBox(Map<String, dynamic> animal) async {
    if (_boxes.isEmpty) return;
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
            Text('Assigner ${animal['nom']} à une box',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            ..._boxes.where((b) => b.espece == animal['espece'] || b.espece == 'autre').map((b) {
              final count = _animaux.where((a) => a['box_id'] == b.id).length;
              final full  = count >= b.capacite;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: full ? Colors.red.shade100 : _green.withValues(alpha: 0.15),
                  child: Text('${count}/${b.capacite}', style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                      color: full ? Colors.red : _teal, fontWeight: FontWeight.w700)),
                ),
                title: Text(b.nom, style: const TextStyle(fontFamily: 'Galey')),
                subtitle: Text(full ? 'Box pleine' : 'Place disponible',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                        color: full ? Colors.red : Colors.grey)),
                enabled: !full,
                onTap: full ? null : () async {
                  Navigator.pop(context);
                  if (!b.id.startsWith('virtual_')) {
                    await _supa.from('animaux').update({'box_id': b.id}).eq('id', animal['id']);
                    _load();
                  }
                },
              );
            }).toList(),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Colors.grey, child: Icon(Icons.close, color: Colors.white, size: 16)),
              title: const Text('Retirer de la box', style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
              onTap: () async {
                Navigator.pop(context);
                if (animal['box_id'] != null) {
                  await _supa.from('animaux').update({'box_id': null}).eq('id', animal['id']);
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
            tooltip: 'Nouvelle box',
            onPressed: _addBox,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600),
          tabs: const [Tab(text: 'Boxes'), Tab(text: 'Vue semaine')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: _tabs, children: [
              _buildBoxesView(),
              _buildWeekView(),
            ]),
    );
  }

  // ── Vue boxes ─────────────────────────────────────────────────────────────

  Widget _buildBoxesView() {
    if (_animaux.isEmpty && _boxes.isEmpty) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.home_work_outlined, size: 60, color: Colors.grey),
          SizedBox(height: 12),
          Text('Aucun animal au chenil', style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
          SizedBox(height: 8),
          Text('Appuyez sur + pour créer une box', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
        ]),
      );
    }

    // Animaux sans box assignée
    final sansBox = _animaux.where((a) {
      final bid = a['box_id']?.toString() ?? '';
      return bid.isEmpty;
    }).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          ..._boxes.map((box) {
            final inBox = _animaux.where((a) => a['box_id'] == box.id).toList();
            return _BoxCard(
              box: box,
              animals: inBox,
              allAnimaux: _animaux,
              onAssign: (a) => _assignBox(a),
              onAnimalTap: (a) => _showAnimalSheet(a),
            );
          }),
          // Animaux non assignés
          if (sansBox.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.inbox_outlined, color: Colors.grey, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Non assignés', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: Colors.grey)),
                  ),
                  Text('${sansBox.length} animal(s)',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
                ]),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: sansBox.map((a) => _AnimalChip(
                    animal: a,
                    onTap: () => _showAnimalSheet(a),
                    onAssign: _boxes.isNotEmpty ? () => _assignBox(a) : null,
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
      ('en_fa', 'En FA', Colors.purple),
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
              Text(a['nom']?.toString() ?? '', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
              Text('${a['espece'] ?? ''} · ${a['statut'] ?? ''}',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
            ])),
          ]),
          const Divider(height: 20),
          const Text('Changer statut', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
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
                label: Text(a['date_entree'] != null ? 'Entrée : ${_fmtDate(a['date_entree'])}' : 'Date d\'entrée',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                onPressed: () async {
                  final d = await _pickDate(initial: a['date_entree'] != null ? DateTime.tryParse(a['date_entree']) : null);
                  if (d != null) { Navigator.pop(context); _updateDates(a['id'], entree: d); }
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.exit_to_app_outlined, size: 14),
                label: Text(a['date_sortie'] != null ? 'Sortie : ${_fmtDate(a['date_sortie'])}' : 'Date de sortie',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                onPressed: () async {
                  final d = await _pickDate(initial: a['date_sortie'] != null ? DateTime.tryParse(a['date_sortie']) : null);
                  if (d != null) { Navigator.pop(context); _updateDates(a['id'], sortie: d); }
                },
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  // ── Vue semaine ───────────────────────────────────────────────────────────

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
      // En-têtes
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

  static String _especeLabel(String e) => const {
    'chien': 'Chiens', 'chat': 'Chats', 'lapin': 'Lapins',
    'oiseau': 'Oiseaux', 'nac': 'NAC', 'cheval': 'Chevaux', 'autre': 'Autres',
  }[e] ?? e;

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

// ── Modèle Box ─────────────────────────────────────────────────────────────

class _Box {
  final String id;
  final String nom;
  final String espece;
  final int    capacite;

  const _Box({required this.id, required this.nom, required this.espece, required this.capacite});

  factory _Box.fromMap(Map<String, dynamic> m) => _Box(
    id:       m['id']?.toString() ?? '',
    nom:      m['nom']?.toString() ?? '',
    espece:   m['espece']?.toString() ?? 'autre',
    capacite: (m['capacite'] as num?)?.toInt() ?? 2,
  );
}

// ── Card Box ───────────────────────────────────────────────────────────────

class _BoxCard extends StatelessWidget {
  final _Box box;
  final List<Map<String, dynamic>> animals;
  final List<Map<String, dynamic>> allAnimaux;
  final void Function(Map<String, dynamic>) onAssign;
  final void Function(Map<String, dynamic>) onAnimalTap;

  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  const _BoxCard({
    required this.box,
    required this.animals,
    required this.allAnimaux,
    required this.onAssign,
    required this.onAnimalTap,
  });

  Color get _statusColor {
    final ratio = animals.length / box.capacite;
    if (ratio >= 1) return Colors.red.shade400;
    if (ratio >= 0.75) return Colors.orange;
    return _green;
  }

  @override
  Widget build(BuildContext context) {
    final pct = (animals.length / box.capacite).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
        border: Border.all(color: _statusColor.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // En-tête box
        Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: _teal.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.home_work_outlined, color: _teal, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(box.nom, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
              Text('${animals.length} / ${box.capacite} · ${box.espece}',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: _statusColor)),
            ]),
          ),
          // Indicateurs capacité
          Row(children: List.generate(box.capacite, (i) => Container(
            width: 10, height: 10,
            margin: const EdgeInsets.only(left: 3),
            decoration: BoxDecoration(
              color: i < animals.length ? _statusColor : Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
          ))),
        ]),

        // Barre de remplissage
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: Colors.grey.shade100,
            valueColor: AlwaysStoppedAnimation(_statusColor),
            minHeight: 4,
          ),
        ),

        // Animaux dans la box
        if (animals.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: animals.map((a) => _AnimalChip(
              animal: a,
              onTap: () => onAnimalTap(a),
              showBox: false,
            )).toList(),
          ),
        ] else ...[
          const SizedBox(height: 10),
          const Text('Aucun animal', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
        ],
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

// ── Planning row (vue semaine) ─────────────────────────────────────────────

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
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
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
                  left: isFirst ? const Radius.circular(6) : Radius.zero,
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
