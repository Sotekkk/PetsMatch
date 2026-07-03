import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/pages/pro/registre_pension_page.dart' show PensionEntreeSheet, pickAnimalForAdmission;

class PensionPlanningPage extends StatefulWidget {
  const PensionPlanningPage({super.key});
  @override
  State<PensionPlanningPage> createState() => _PensionPlanningPageState();
}

enum _StaySt { aVenir, entreeAujourdhui, enCours, sortieAujourdhui, sortieRetard, sortieFaiteAujourdhui, passe }

const Map<_StaySt, Color> _stColors = {
  _StaySt.aVenir: Color(0xFF3B82F6),
  _StaySt.entreeAujourdhui: Color(0xFF06B6D4),
  _StaySt.enCours: Color(0xFF6E9E57),
  _StaySt.sortieAujourdhui: Color(0xFFEAB308),
  _StaySt.sortieRetard: Color(0xFFEA580C),
  _StaySt.sortieFaiteAujourdhui: Color(0xFF4B5563),
  _StaySt.passe: Color(0xFFD1D5DB),
};

const Map<_StaySt, String> _stLabels = {
  _StaySt.aVenir: 'Séjour à venir',
  _StaySt.entreeAujourdhui: 'Entrée aujourd\'hui',
  _StaySt.enCours: 'Séjour en cours',
  _StaySt.sortieAujourdhui: 'Sortie aujourd\'hui',
  _StaySt.sortieRetard: 'Sortie en retard',
  _StaySt.sortieFaiteAujourdhui: 'Sortie faite aujourd\'hui',
  _StaySt.passe: 'Séjour passé',
};

const _typeLabels = {'box': 'Box', 'enclos': 'Enclos', 'parc': 'Parc', 'chatterie': 'Chatterie', 'cage': 'Cage'};

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
DateTime? _parseDate(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

_StaySt _computeStatus(Map<String, dynamic> e, DateTime today) {
  final statut = e['statut'] as String? ?? 'en_pension';
  final dateEntree = _parseDate(e['date_entree']);
  final dateSortiePrevue = _parseDate(e['date_sortie_prevue']);
  final dateSortieEff = _parseDate(e['date_sortie_effective']);

  if (statut == 'sorti') {
    if (dateSortieEff != null && _sameDay(dateSortieEff, today)) return _StaySt.sortieFaiteAujourdhui;
    return _StaySt.passe;
  }
  if (dateEntree != null && dateEntree.isAfter(today)) return _StaySt.aVenir;
  if (dateEntree != null && _sameDay(dateEntree, today)) return _StaySt.entreeAujourdhui;
  if (dateSortiePrevue != null && _sameDay(dateSortiePrevue, today)) return _StaySt.sortieAujourdhui;
  if (dateSortiePrevue != null && dateSortiePrevue.isBefore(today)) return _StaySt.sortieRetard;
  return _StaySt.enCours;
}

class _PensionPlanningPageState extends State<PensionPlanningPage> {
  final _supa = Supabase.instance.client;
  static const _teal = Color(0xFF0C5C6C);

  List<Map<String, dynamic>> _logements = [];
  List<Map<String, dynamic>> _entrees = [];
  bool _loading = true;
  DateTime _windowStart = DateTime.now();
  String? _filterEspece;

  static const int _days = 14;
  static const _especesList = ['Chien', 'Chat', 'Lapin', 'Oiseau', 'Reptile', 'Rongeur', 'Cheval', 'Autre'];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _windowStart = DateTime(now.year, now.month, now.day);
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _loading = true);
    try {
      final windowEnd = _windowStart.add(const Duration(days: _days));
      final results = await Future.wait([
        _supa.from('enclos_chenil').select().eq('uid_eleveur', uid).order('nom'),
        _supa.from('pension_entrees').select().eq('pro_uid', uid)
            .lte('date_entree', DateFormat('yyyy-MM-dd').format(windowEnd))
            .order('date_entree'),
      ]);
      if (mounted) {
        setState(() {
          _logements = List<Map<String, dynamic>>.from(results[0] as List);
          // Exclut les séjours déjà sortis avant le début de la fenêtre affichée
          _entrees = List<Map<String, dynamic>>.from(results[1] as List).where((e) {
            final sortieEff = _parseDate(e['date_sortie_effective']);
            return sortieEff == null || !sortieEff.isBefore(_windowStart);
          }).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _shiftWindow(int days) {
    setState(() => _windowStart = _windowStart.add(Duration(days: days)));
    _load();
  }

  List<Map<String, dynamic>> _entreesFor(String? logementId) =>
      _entrees.where((e) => e['logement_id'] == logementId).toList();

  @override
  Widget build(BuildContext context) {
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final days = List.generate(_days, (i) => _windowStart.add(Duration(days: i)));
    final visibleLogements = _filterEspece == null
        ? _logements
        : _logements.where((l) => List<String>.from(l['especes'] as List? ?? []).contains(_filterEspece)).toList();
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final l in visibleLogements) {
      final type = l['type'] as String? ?? 'box';
      grouped.putIfAbsent(type, () => []).add(l);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Planning occupation', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        actions: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _shiftWindow(-7)),
          IconButton(icon: const Icon(Icons.today_outlined), tooltip: 'Aujourd\'hui', onPressed: () {
            setState(() => _windowStart = today);
            _load();
          }),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _shiftWindow(7)),
        ],
      ),
      body: _logements.isEmpty && !_loading
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.calendar_view_week_outlined, size: 60, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text('Aucun logement enregistré', style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500)),
            ]))
          : Column(children: [
              if (_logements.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: Colors.white,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      _PlanningFilterChip(label: 'Toutes espèces', active: _filterEspece == null, onTap: () => setState(() => _filterEspece = null)),
                      const SizedBox(width: 6),
                      for (final e in _especesList) ...[
                        _PlanningFilterChip(label: e, active: _filterEspece == e, onTap: () => setState(() => _filterEspece = e)),
                        const SizedBox(width: 6),
                      ],
                    ]),
                  ),
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: _teal))
                    : Column(children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        // Colonne fixe : noms des logements
                        SizedBox(
                          width: 120,
                          child: Column(children: [
                            const SizedBox(height: 40), // aligne avec l'en-tête de dates
                            for (final type in grouped.keys) ...[
                              Container(
                                height: 28, alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                color: const Color(0xFFEEF5EA),
                                child: Text(_typeLabels[type] ?? type,
                                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 11, color: _teal)),
                              ),
                              for (final l in grouped[type]!)
                                Container(
                                  height: 40, alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
                                  child: Text(l['nom'] as String? ?? '', overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600)),
                                ),
                            ],
                          ]),
                        ),
                        // Grille scrollable horizontalement : dates + barres
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: _days * 56.0,
                              child: Column(children: [
                                // En-tête dates
                                Row(children: [
                                  for (final d in days)
                                    Container(
                                      width: 56, height: 40, alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: _sameDay(d, today) ? const Color(0xFFEEF5EA) : null,
                                        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                                      ),
                                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                        Text(DateFormat('E', 'fr_FR').format(d),
                                            style: TextStyle(fontFamily: 'Galey', fontSize: 9, color: Colors.grey.shade500)),
                                        Text(DateFormat('d/MM').format(d),
                                            style: const TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600)),
                                      ]),
                                    ),
                                ]),
                                for (final type in grouped.keys) ...[
                                  Container(height: 28, color: const Color(0xFFEEF5EA)),
                                  for (final l in grouped[type]!)
                                    _LogementRow(
                                      days: days,
                                      entrees: _entreesFor(l['id'] as String?),
                                      today: today,
                                      onTapEntree: _showEntreeInfo,
                                      onTapEmpty: (d) => _openCreationSheet(l['id'] as String, d),
                                    ),
                                ],
                              ]),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  _Legend(),
                ]),
              ),
            ]),
    );
  }

  Future<void> _openCreationSheet(String logementId, DateTime date) async {
    final prefill = await pickAnimalForAdmission(context);
    if (prefill == null || !mounted) return; // annulé au choix scan/manuel/sans puce

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PensionEntreeSheet(
        initialLogementId: logementId,
        initialDateEntree: date,
        initialNom:                 prefill['nom'] as String?,
        initialEspece:              prefill['espece'] as String?,
        initialRace:                prefill['race'] as String?,
        initialPuce:                prefill['puce'] as String?,
        initialPhotoUrl:            prefill['photoUrl'] as String?,
        initialAnimalId:            prefill['animalId'] as String?,
        initialOwnerUid:            prefill['ownerUid'] as String?,
        initialProprietaireNom:     prefill['proprietaireNom'] as String?,
        initialProprietaireContact: prefill['proprietaireContact'] as String?,
        initialProprietaireEmail:   prefill['proprietaireEmail'] as String?,
        initialProprietaireAdresse: prefill['proprietaireAdresse'] as String?,
      ),
    );
    if (created == true) _load();
  }

  void _showEntreeInfo(Map<String, dynamic> e, _StaySt st) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(e['animal_nom'] as String? ?? '', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: _stColors[st]!.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
            child: Text(_stLabels[st]!, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: _stColors[st], fontWeight: FontWeight.w700)),
          ),
          Text('Propriétaire : ${e['proprietaire_nom'] ?? '—'}', style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
          const SizedBox(height: 4),
          Text('Entrée : ${e['date_entree'] ?? '—'}', style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
          Text('Sortie prévue : ${e['date_sortie_prevue'] ?? '—'}', style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
        ],
      ),
    );
  }
}

class _LogementRow extends StatelessWidget {
  final List<DateTime> days;
  final List<Map<String, dynamic>> entrees;
  final DateTime today;
  final void Function(Map<String, dynamic>, _StaySt) onTapEntree;
  final void Function(DateTime) onTapEmpty;

  const _LogementRow({required this.days, required this.entrees, required this.today, required this.onTapEntree, required this.onTapEmpty});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(children: [
        for (final d in days) _dayCell(d),
      ]),
    );
  }

  Widget _dayCell(DateTime d) {
    Map<String, dynamic>? match;
    for (final e in entrees) {
      final entree = _parseDate(e['date_entree']);
      final sortie = _parseDate(e['date_sortie_effective']) ?? _parseDate(e['date_sortie_prevue']);
      if (entree == null) continue;
      final startOk = !d.isBefore(DateTime(entree.year, entree.month, entree.day));
      final endOk = sortie == null || !d.isAfter(DateTime(sortie.year, sortie.month, sortie.day));
      if (startOk && endOk) { match = e; break; }
    }
    if (match == null) {
      return GestureDetector(
        onTap: () => onTapEmpty(d),
        child: Container(
          width: 56, height: 40,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100), right: BorderSide(color: Colors.grey.shade50))),
          child: const Center(child: Icon(Icons.add, size: 14, color: Color(0xFFD1D5DB))),
        ),
      );
    }
    final st = _computeStatus(match, today);
    return GestureDetector(
      onTap: () => onTapEntree(match!, st),
      child: Container(
        width: 56, height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
        child: Container(
          decoration: BoxDecoration(color: _stColors[st], borderRadius: BorderRadius.circular(4)),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey.shade200))),
      child: Wrap(spacing: 12, runSpacing: 6, children: [
        for (final st in _StaySt.values)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: _stColors[st], borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 4),
            Text(_stLabels[st]!, style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.grey.shade600)),
          ]),
      ]),
    );
  }
}

class _PlanningFilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _PlanningFilterChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF0C5C6C);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? teal : Colors.white,
          border: Border.all(color: active ? teal : Colors.grey.shade300),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
            color: active ? Colors.white : Colors.black87, fontWeight: FontWeight.w500)),
      ),
    );
  }
}
