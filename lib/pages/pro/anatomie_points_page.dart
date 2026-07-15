import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;

// Catégories de points — mirror du légende "Points d'ostéopathie" des
// schémas anatomiques d'origine.
const List<(String, String, Color)> kCategoriesOsteo = [
  ('tension_cervicale', 'Tension cervicale', Color(0xFFE67E22)),
  ('tension_thoracique', 'Tension thoracique', Color(0xFFF39C12)),
  ('tension_lombaire', 'Tension lombaire', Color(0xFF3498DB)),
  ('tension_sacro_iliaque', 'Tension sacro-iliaque', Color(0xFF9B59B6)),
  ('trigger', 'Point trigger', Color(0xFF795548)),
  ('acupuncture', 'Point d\'acupuncture', Color(0xFF8BC34A)),
  ('autre', 'Autre', Color(0xFF9E9E9E)),
];

Color colorForCategorie(String cat) =>
    kCategoriesOsteo.firstWhere((c) => c.$1 == cat, orElse: () => kCategoriesOsteo.last).$3;

String labelForCategorie(String cat) =>
    kCategoriesOsteo.firstWhere((c) => c.$1 == cat, orElse: () => kCategoriesOsteo.last).$2;

class _SpeciesAsset {
  final String asset;
  final double ratio;
  const _SpeciesAsset(this.asset, this.ratio);
}

// Une seule vue par espèce (silhouette squelette pleine page, sans découpe).
const Map<String, _SpeciesAsset> _speciesAssets = {
  'chien':  _SpeciesAsset('assets/anatomie/chien_squelette.png', 1536 / 1024),
  'chat':   _SpeciesAsset('assets/anatomie/chat_squelette.png', 1402 / 1122),
  'cheval': _SpeciesAsset('assets/anatomie/cheval_squelette.png', 1536 / 1024),
};

String? _speciesKey(String espece) {
  final e = espece.toLowerCase();
  if (e.contains('chien')) return 'chien';
  if (e.contains('chat')) return 'chat';
  if (e.contains('cheval')) return 'cheval';
  return null;
}

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

// ── Onglet "Anatomie" (pro) — liste des séances datées ───────────────────────
//
// Chaque séance = un compte rendu de visite. Le pro touche le schéma pour
// noter les points travaillés ce jour-là ; l'historique complet reste
// consultable séance par séance plutôt que mélangé sur un canvas unique.
class AnatomieSeancesTab extends StatefulWidget {
  final String animalId;
  final String espece;
  const AnatomieSeancesTab({super.key, required this.animalId, required this.espece});

  @override
  State<AnatomieSeancesTab> createState() => _AnatomieSeancesTabState();
}

class _AnatomieSeancesTabState extends State<AnatomieSeancesTab> {
  static const _teal = Color(0xFF0C5C6C);
  final _supa = Supabase.instance.client;

  bool _loading = true;
  bool _creating = false;
  List<Map<String, dynamic>> _seances = [];
  Map<String, int> _pointCounts = {};

  String? get _speciesK => _speciesKey(widget.espece);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _supa.from('seances_osteo').select()
          .eq('animal_id', widget.animalId).order('date_seance', ascending: false);
      final seances = List<Map<String, dynamic>>.from(rows as List);
      final ids = seances.map((s) => s['id'].toString()).toList();
      final counts = <String, int>{};
      if (ids.isNotEmpty) {
        final pts = await _supa.from('points_osteo').select('seance_id').inFilter('seance_id', ids);
        for (final p in pts as List) {
          final sid = p['seance_id']?.toString();
          if (sid != null) counts[sid] = (counts[sid] ?? 0) + 1;
        }
      }
      if (mounted) setState(() { _seances = seances; _pointCounts = counts; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _nouvelleSeance() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _speciesK == null) return;
    setState(() => _creating = true);
    try {
      final pid = User_Info.activeProfileId;
      final inserted = await _supa.from('seances_osteo').insert({
        'animal_id': widget.animalId,
        'pro_uid': uid,
        if (pid.isNotEmpty) 'pro_profile_id': pid,
        'date_seance': DateTime.now().toIso8601String().split('T').first,
      }).select().single();
      if (mounted) {
        setState(() => _creating = false);
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => AnatomieSeanceDetailPage(
            seanceId: inserted['id'] as String,
            animalId: widget.animalId,
            espece: widget.espece,
            dateSeance: inserted['date_seance'] as String,
            readOnly: false,
          ),
        ));
        _load();
      }
    } catch (_) {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _openSeance(Map<String, dynamic> s) async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => AnatomieSeanceDetailPage(
        seanceId: s['id'] as String,
        animalId: widget.animalId,
        espece: widget.espece,
        dateSeance: s['date_seance'] as String,
        readOnly: false,
      ),
    ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_speciesK == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Schéma anatomique non disponible pour cette espèce.\n(chien, chat et cheval uniquement)',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
        ),
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator(color: _teal));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _creating ? null : _nouvelleSeance,
              icon: _creating
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.add, size: 18),
              label: const Text('Nouvelle séance', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
        Expanded(
          child: _seances.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Aucune séance enregistrée pour l\'instant.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: _seances.length,
                  itemBuilder: (_, i) => _SeanceCard(
                    seance: _seances[i],
                    pointCount: _pointCounts[_seances[i]['id'].toString()] ?? 0,
                    onTap: () => _openSeance(_seances[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _SeanceCard extends StatelessWidget {
  final Map<String, dynamic> seance;
  final int pointCount;
  final VoidCallback onTap;
  const _SeanceCard({required this.seance, required this.pointCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(seance['date_seance']?.toString() ?? '');
    final note = seance['note'] as String?;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(color: const Color(0xFF0C5C6C).withValues(alpha: 0.08), shape: BoxShape.circle),
              child: const Icon(Icons.event_note_outlined, color: Color(0xFF0C5C6C), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(date != null ? _fmtDate(date) : '—',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                Text(
                  pointCount == 0 ? 'Aucun point noté' : '$pointCount point${pointCount > 1 ? 's' : ''} noté${pointCount > 1 ? 's' : ''}',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500),
                ),
                if (note != null && note.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 2),
                      child: Text(note, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600))),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ]),
        ),
      ),
    );
  }
}

// ── Détail d'une séance — schéma interactif + note ───────────────────────────
//
// [readOnly] = true pour la vue propriétaire (consultation seule, aucun
// ajout/édition/suppression possible).
class AnatomieSeanceDetailPage extends StatefulWidget {
  final String seanceId;
  final String animalId;
  final String espece;
  final String dateSeance;
  final bool readOnly;
  const AnatomieSeanceDetailPage({
    super.key,
    required this.seanceId,
    required this.animalId,
    required this.espece,
    required this.dateSeance,
    required this.readOnly,
  });

  @override
  State<AnatomieSeanceDetailPage> createState() => _AnatomieSeanceDetailPageState();
}

class _AnatomieSeanceDetailPageState extends State<AnatomieSeanceDetailPage> {
  static const _teal = Color(0xFF0C5C6C);
  final _supa = Supabase.instance.client;
  final _noteCtrl = TextEditingController();

  bool _loading = true;
  bool _deleting = false;
  List<Map<String, dynamic>> _points = [];
  late DateTime _dateSeance;

  String? get _speciesK => _speciesKey(widget.espece);

  @override
  void initState() {
    super.initState();
    _dateSeance = DateTime.tryParse(widget.dateSeance) ?? DateTime.now();
    _load();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final seance = await _supa.from('seances_osteo').select('note').eq('id', widget.seanceId).maybeSingle();
      final rows = await _supa.from('points_osteo').select()
          .eq('seance_id', widget.seanceId).order('created_at', ascending: false);
      _noteCtrl.text = (seance?['note'] as String?) ?? '';
      if (mounted) setState(() { _points = List<Map<String, dynamic>>.from(rows as List); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveSeanceNote() async {
    await _supa.from('seances_osteo').update({'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim()})
        .eq('id', widget.seanceId);
  }

  Future<void> _editDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateSeance,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    final iso = picked.toIso8601String().split('T').first;
    await _supa.from('seances_osteo').update({'date_seance': iso}).eq('id', widget.seanceId);
    if (mounted) setState(() => _dateSeance = picked);
  }

  Future<void> _deleteSeance() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer la séance', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: const Text('Cette séance et tous ses points seront définitivement supprimés.',
            style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey'))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Supprimer', style: TextStyle(fontFamily: 'Galey', color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _deleting = true);
    await _supa.from('seances_osteo').delete().eq('id', widget.seanceId);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _addPoint(double xPct, double yPct) async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _EditPointSheet(),
    );
    if (result == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final pid = User_Info.activeProfileId;
    try {
      final inserted = await _supa.from('points_osteo').insert({
        'animal_id': widget.animalId,
        'seance_id': widget.seanceId,
        'pro_uid': uid,
        if (pid.isNotEmpty) 'pro_profile_id': pid,
        'espece': _speciesK,
        'vue': 'squelette',
        'x_pct': xPct,
        'y_pct': yPct,
        'categorie': result['categorie'],
        'note': (result['note']?.trim().isEmpty ?? true) ? null : result['note']!.trim(),
      }).select().single();
      if (mounted) setState(() => _points = [inserted, ..._points]);
    } catch (_) {}
  }

  Future<void> _showPoint(Map<String, dynamic> p) async {
    if (widget.readOnly) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _PointDetailSheet(point: p, readOnly: true),
      );
      return;
    }
    // Côté pro : le point s'ouvre directement en édition (catégorie + note
    // modifiables, plus bouton supprimer) — pas d'étape de consultation
    // intermédiaire.
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditPointSheet(
        initialCategorie: p['categorie'] as String?,
        initialNote: p['note'] as String?,
        showDelete: true,
      ),
    );
    if (result == null) return;
    if (result == 'delete') {
      await _supa.from('points_osteo').delete().eq('id', p['id']);
      if (mounted) setState(() => _points.removeWhere((x) => x['id'] == p['id']));
      return;
    }
    final map = result as Map<String, String>;
    final updated = await _supa.from('points_osteo').update({
      'categorie': map['categorie'],
      'note': (map['note']?.trim().isEmpty ?? true) ? null : map['note']!.trim(),
    }).eq('id', p['id']).select().single();
    if (mounted) {
      setState(() {
        final idx = _points.indexWhere((x) => x['id'] == p['id']);
        if (idx != -1) _points[idx] = updated;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: Text(_fmtDate(_dateSeance),
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        actions: widget.readOnly ? null : [
          IconButton(icon: const Icon(Icons.edit_calendar_outlined), tooltip: 'Modifier la date', onPressed: _editDate),
          IconButton(
            icon: _deleting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.delete_outline),
            tooltip: 'Supprimer la séance',
            onPressed: _deleting ? null : _deleteSeance,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _speciesK == null
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Schéma anatomique non disponible pour cette espèce.',
                        textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!widget.readOnly) ...[
                        TextField(
                          controller: _noteCtrl,
                          maxLines: 2,
                          onEditingComplete: _saveSeanceNote,
                          onTapOutside: (_) => _saveSeanceNote(),
                          decoration: InputDecoration(
                            hintText: 'Notes sur la séance (optionnel)',
                            hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                            filled: true, fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                            contentPadding: const EdgeInsets.all(12),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ] else if (_noteCtrl.text.isNotEmpty) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
                          child: Text(_noteCtrl.text, style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5)),
                        ),
                        const SizedBox(height: 14),
                      ],
                      Text(
                        widget.readOnly ? 'Points travaillés lors de cette séance' : 'Touchez le schéma pour noter un point travaillé',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey),
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: AspectRatio(
                          aspectRatio: _speciesAssets[_speciesK]!.ratio,
                          child: Container(
                            color: const Color(0xFFFAF9F6),
                            child: LayoutBuilder(builder: (context, constraints) {
                              return GestureDetector(
                                onTapUp: widget.readOnly ? null : (details) {
                                  final xPct = (details.localPosition.dx / constraints.maxWidth * 100).clamp(0.0, 100.0);
                                  final yPct = (details.localPosition.dy / constraints.maxHeight * 100).clamp(0.0, 100.0);
                                  _addPoint(xPct, yPct);
                                },
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.asset(_speciesAssets[_speciesK]!.asset, fit: BoxFit.contain),
                                    ..._points.map((p) {
                                      final xPct = (p['x_pct'] as num).toDouble();
                                      final yPct = (p['y_pct'] as num).toDouble();
                                      final color = colorForCategorie(p['categorie'] as String? ?? 'autre');
                                      return Positioned(
                                        left: (xPct / 100 * constraints.maxWidth) - 9,
                                        top: (yPct / 100 * constraints.maxHeight) - 9,
                                        child: GestureDetector(
                                          onTap: () => _showPoint(p),
                                          child: Container(
                                            width: 18, height: 18,
                                            decoration: BoxDecoration(
                                              color: color, shape: BoxShape.circle,
                                              border: Border.all(color: Colors.white, width: 2),
                                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
                                            ),
                                          ),
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(spacing: 10, runSpacing: 8, children: kCategoriesOsteo.map((c) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 10, height: 10, decoration: BoxDecoration(color: c.$3, shape: BoxShape.circle)),
                          const SizedBox(width: 5),
                          Text(c.$2, style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey)),
                        ],
                      )).toList()),
                      if (_points.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Align(alignment: Alignment.centerLeft,
                            child: Text('Points de cette séance', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14))),
                        const SizedBox(height: 8),
                        ..._points.map((p) => _PointHistoryTile(point: p, onTap: () => _showPoint(p))),
                      ],
                    ],
                  ),
                ),
    );
  }
}

// ── Section propriétaire (lecture seule) — embarquée dans l'onglet
// Consultations de la fiche animal côté propriétaire.
class AnatomieOwnerSection extends StatefulWidget {
  final String animalId;
  final String espece;
  const AnatomieOwnerSection({super.key, required this.animalId, required this.espece});

  @override
  State<AnatomieOwnerSection> createState() => _AnatomieOwnerSectionState();
}

class _AnatomieOwnerSectionState extends State<AnatomieOwnerSection> {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _seances = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _supa.from('seances_osteo').select()
          .eq('animal_id', widget.animalId).order('date_seance', ascending: false);
      if (mounted) setState(() { _seances = List<Map<String, dynamic>>.from(rows as List); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_seances.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text('🦴 Séances d\'ostéopathie / kiné',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
        ),
        ..._seances.map((s) => _SeanceCard(
              seance: s,
              pointCount: 0,
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => AnatomieSeanceDetailPage(
                  seanceId: s['id'] as String,
                  animalId: widget.animalId,
                  espece: widget.espece,
                  dateSeance: s['date_seance'] as String,
                  readOnly: true,
                ),
              )),
            )),
      ],
    );
  }
}

class _PointHistoryTile extends StatelessWidget {
  final Map<String, dynamic> point;
  final VoidCallback onTap;
  const _PointHistoryTile({required this.point, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cat = point['categorie'] as String? ?? 'autre';
    final note = point['note'] as String?;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: colorForCategorie(cat), shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(labelForCategorie(cat), style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
                if (note != null && note.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 2),
                      child: Text(note, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600))),
              ]),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
          ]),
        ),
      ),
    );
  }
}

class _EditPointSheet extends StatefulWidget {
  final String? initialCategorie;
  final String? initialNote;
  final bool showDelete;
  const _EditPointSheet({this.initialCategorie, this.initialNote, this.showDelete = false});
  @override
  State<_EditPointSheet> createState() => _EditPointSheetState();
}

class _EditPointSheetState extends State<_EditPointSheet> {
  String? _categorie;
  late final TextEditingController _noteCtrl;

  @override
  void initState() {
    super.initState();
    _categorie = widget.initialCategorie;
    _noteCtrl = TextEditingController(text: widget.initialNote ?? '');
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.initialCategorie != null;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_isEdit ? 'Modifier le point' : 'Nouveau point', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: kCategoriesOsteo.map((c) {
            final selected = _categorie == c.$1;
            return ChoiceChip(
              label: Text(c.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: selected ? Colors.white : Colors.grey.shade700)),
              selected: selected,
              selectedColor: c.$3,
              backgroundColor: c.$3.withValues(alpha: 0.12),
              side: BorderSide(color: c.$3.withValues(alpha: selected ? 1 : 0.4)),
              onSelected: (_) => setState(() => _categorie = c.$1),
            );
          }).toList()),
          const SizedBox(height: 14),
          TextField(
            controller: _noteCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Note (optionnel)',
              hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13),
              filled: true, fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _categorie == null ? null : () => Navigator.pop(context, {'categorie': _categorie!, 'note': _noteCtrl.text}),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0C5C6C), foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            ),
          ),
          if (widget.showDelete) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, 'delete'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red, side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Supprimer ce point', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _PointDetailSheet extends StatelessWidget {
  final Map<String, dynamic> point;
  final bool readOnly;
  const _PointDetailSheet({required this.point, required this.readOnly});

  @override
  Widget build(BuildContext context) {
    final cat = point['categorie'] as String? ?? 'autre';
    final note = point['note'] as String?;
    final createdAt = DateTime.tryParse(point['created_at']?.toString() ?? '');
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 14, height: 14, decoration: BoxDecoration(color: colorForCategorie(cat), shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(child: Text(labelForCategorie(cat), style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15))),
        ]),
        if (createdAt != null) ...[
          const SizedBox(height: 6),
          Text('${createdAt.day.toString().padLeft(2,'0')}/${createdAt.month.toString().padLeft(2,'0')}/${createdAt.year} à ${createdAt.hour.toString().padLeft(2,'0')}:${createdAt.minute.toString().padLeft(2,'0')}',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
        ],
        if (note != null && note.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(note, style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5)),
        ] else if (readOnly) ...[
          const SizedBox(height: 12),
          Text('Aucune note', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade400)),
        ],
        if (!readOnly) ...[
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, 'edit'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0C5C6C), side: const BorderSide(color: Color(0xFF0C5C6C)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Modifier', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, 'delete'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red, side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Supprimer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}
