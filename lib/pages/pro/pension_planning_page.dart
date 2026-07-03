import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/pages/pro/registre_pension_page.dart' show PensionEntreeSheet, pickAnimalForAdmission, PensionEditSheet;
import 'package:PetsMatch/pages/pro/animal_fiche_pension_page.dart';

class PensionPlanningPage extends StatefulWidget {
  final String? employerUid;  // vue employé : consulte le planning d'un employeur pension
  final String? employerNom;
  const PensionPlanningPage({super.key, this.employerUid, this.employerNom});
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

bool _rangesOverlap(Map<String, dynamic> a, Map<String, dynamic> b) {
  final aStart = _parseDate(a['date_entree']);
  final bStart = _parseDate(b['date_entree']);
  if (aStart == null || bStart == null) return false;
  final aEnd = _parseDate(a['date_sortie_effective']) ?? _parseDate(a['date_sortie_prevue']) ?? DateTime(2100);
  final bEnd = _parseDate(b['date_sortie_effective']) ?? _parseDate(b['date_sortie_prevue']) ?? DateTime(2100);
  return !aStart.isAfter(bEnd) && !bStart.isAfter(aEnd);
}

/// Range dans capacite lignes les séjours d'un logement sans chevauchement
/// (façon Tetris) — les séjours "seul" ne sont pas rangés dans la grille
/// normale, ils sont traités à part (bloquent toutes les lignes).
List<List<Map<String, dynamic>>> _packEntries(List<Map<String, dynamic>> entries, int capacite) {
  final rows = List.generate(capacite < 1 ? 1 : capacite, (_) => <Map<String, dynamic>>[]);
  final normales = entries.where((e) => e['seul_dans_logement'] != true).toList()
    ..sort((a, b) {
      final da = _parseDate(a['date_entree']) ?? DateTime(2000);
      final db = _parseDate(b['date_entree']) ?? DateTime(2000);
      return da.compareTo(db);
    });
  for (final e in normales) {
    var placed = false;
    for (final row in rows) {
      if (!row.any((other) => _rangesOverlap(other, e))) { row.add(e); placed = true; break; }
    }
    if (!placed) rows.last.add(e);
  }
  return rows;
}

class _PensionPlanningPageState extends State<PensionPlanningPage> {
  final _supa = Supabase.instance.client;
  static const _teal = Color(0xFF0C5C6C);

  List<Map<String, dynamic>> _logements = [];
  List<Map<String, dynamic>> _entrees = [];
  Set<String> _nettoyages = {}; // "logementId|yyyy-MM-dd"
  bool _loading = true;
  DateTime _windowStart = DateTime.now();
  String? _filterEspece;

  static const int _days = 14;
  static const _especesList = ['Chien', 'Chat', 'Lapin', 'Oiseau', 'Reptile', 'Rongeur', 'Cheval', 'Autre'];

  bool get _readOnly => widget.employerUid != null;
  String? get _effectiveUid => widget.employerUid ?? FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _windowStart = DateTime(now.year, now.month, now.day);
    _load();
  }

  Future<void> _load() async {
    final uid = _effectiveUid;
    if (uid == null) return;
    setState(() => _loading = true);
    try {
      final windowEnd = _windowStart.add(const Duration(days: _days));
      final windowStartStr = DateFormat('yyyy-MM-dd').format(_windowStart);
      final windowEndStr = DateFormat('yyyy-MM-dd').format(windowEnd);
      final results = await Future.wait([
        _supa.from('enclos_chenil').select().eq('uid_eleveur', uid).order('nom'),
        _supa.from('pension_entrees').select().eq('pro_uid', uid)
            .lte('date_entree', windowEndStr)
            .order('date_entree'),
        _supa.from('pension_nettoyages').select('logement_id, date').eq('uid_eleveur', uid)
            .gte('date', windowStartStr).lte('date', windowEndStr),
      ]);
      if (mounted) {
        setState(() {
          _logements = List<Map<String, dynamic>>.from(results[0] as List);
          // Exclut les séjours déjà sortis avant le début de la fenêtre affichée
          _entrees = List<Map<String, dynamic>>.from(results[1] as List).where((e) {
            final sortieEff = _parseDate(e['date_sortie_effective']);
            return sortieEff == null || !sortieEff.isBefore(_windowStart);
          }).toList();
          _nettoyages = List<Map<String, dynamic>>.from(results[2] as List)
              .map((n) => '${n['logement_id']}|${n['date']}')
              .toSet();
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

  List<Map<String, dynamic>> _soloEntreesFor(String? logementId) =>
      _entrees.where((e) => e['logement_id'] == logementId && e['seul_dans_logement'] == true).toList();

  bool _estNettoye(String logementId, DateTime day) =>
      _nettoyages.contains('$logementId|${DateFormat('yyyy-MM-dd').format(day)}');

  Future<void> _toggleNettoyage(String logementId, DateTime day) async {
    if (_readOnly) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final dateStr = DateFormat('yyyy-MM-dd').format(day);
    final key = '$logementId|$dateStr';
    final nowClean = _nettoyages.contains(key);
    setState(() {
      if (nowClean) { _nettoyages.remove(key); } else { _nettoyages.add(key); }
    });
    try {
      if (nowClean) {
        await _supa.from('pension_nettoyages').delete()
            .eq('logement_id', logementId).eq('date', dateStr);
      } else {
        await _supa.from('pension_nettoyages').insert(
            {'logement_id': logementId, 'uid_eleveur': uid, 'date': dateStr});
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          if (nowClean) { _nettoyages.add(key); } else { _nettoyages.remove(key); }
        });
      }
    }
  }

  Future<void> _openEditSheet(Map<String, dynamic> entree) async {
    if (_readOnly) {
      _showReadOnlyInfo(entree);
      return;
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PensionEditSheet(entree: entree, supa: _supa),
    );
    _load();
  }

  void _showReadOnlyInfo(Map<String, dynamic> entree) {
    final animalId = entree['animal_id'] as String?;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(entree['animal_nom'] as String? ?? 'Animal',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Espèce : ${entree['espece'] ?? '—'}', style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
          Text('Race : ${entree['race'] ?? '—'}', style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
          const SizedBox(height: 6),
          Text('Propriétaire : ${entree['proprietaire_nom'] ?? '—'}', style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
          Text('Entrée : ${entree['date_entree'] ?? '—'}', style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
          Text('Sortie prévue : ${entree['date_sortie_prevue'] ?? '—'}', style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
        ]),
        actions: [
          if (animalId != null)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => AnimalFichePensionPage(animalId: animalId, animalNom: entree['animal_nom']?.toString()),
                ));
              },
              child: const Text('Voir la fiche'),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
        ],
      ),
    );
  }

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
        title: Text(_readOnly ? 'Planning — ${widget.employerNom ?? "employeur"}' : 'Planning occupation',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
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
                              for (final l in grouped[type]!) ...[
                                for (var slot = 0; slot < ((l['capacite'] as int?) ?? 1).clamp(1, 99); slot++)
                                  Container(
                                    height: 40, alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
                                    child: slot == 0
                                        ? Text(l['nom'] as String? ?? '', overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600))
                                        : const SizedBox.shrink(),
                                  ),
                                Container(
                                  height: 28, alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
                                  child: Text('Nettoyage', style: TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.grey.shade500)),
                                ),
                              ],
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
                                  for (final l in grouped[type]!) ...[
                                    for (final row in _packEntries(_entreesFor(l['id'] as String?), (l['capacite'] as int?) ?? 1))
                                      _LogementRow(
                                        days: days,
                                        entrees: row,
                                        soloEntrees: _soloEntreesFor(l['id'] as String?),
                                        today: today,
                                        onTapEntree: _openEditSheet,
                                        onTapEmpty: (d) => _openCreationSheet(l['id'] as String, d),
                                      ),
                                    _NettoyageRow(
                                      days: days,
                                      logementId: l['id'] as String,
                                      isClean: (d) => _estNettoye(l['id'] as String, d),
                                      onToggle: (d) => _toggleNettoyage(l['id'] as String, d),
                                    ),
                                  ],
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
    if (_readOnly) return;
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

}

class _LogementRow extends StatelessWidget {
  final List<DateTime> days;
  final List<Map<String, dynamic>> entrees;
  final List<Map<String, dynamic>> soloEntrees;
  final DateTime today;
  final void Function(Map<String, dynamic>) onTapEntree;
  final void Function(DateTime) onTapEmpty;

  const _LogementRow({
    required this.days, required this.entrees, required this.soloEntrees,
    required this.today, required this.onTapEntree, required this.onTapEmpty,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(children: [
        for (final d in days) _dayCell(d),
      ]),
    );
  }

  Map<String, dynamic>? _matchFor(List<Map<String, dynamic>> list, DateTime d) {
    for (final e in list) {
      final entree = _parseDate(e['date_entree']);
      final sortie = _parseDate(e['date_sortie_effective']) ?? _parseDate(e['date_sortie_prevue']);
      if (entree == null) continue;
      final startOk = !d.isBefore(DateTime(entree.year, entree.month, entree.day));
      final endOk = sortie == null || !d.isAfter(DateTime(sortie.year, sortie.month, sortie.day));
      if (startOk && endOk) return e;
    }
    return null;
  }

  Widget _dayCell(DateTime d) {
    // Un séjour "seul" bloque toutes les lignes du logement pour ses dates.
    final solo = _matchFor(soloEntrees, d);
    final match = solo ?? _matchFor(entrees, d);

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
      onTap: () => onTapEntree(match),
      child: Container(
        width: 56, height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
        child: Container(
          decoration: BoxDecoration(
            color: _stColors[st],
            borderRadius: BorderRadius.circular(4),
            border: solo != null ? Border.all(color: Colors.redAccent, width: 1.5) : null,
          ),
          child: solo != null
              ? const Center(child: Icon(Icons.lock_outline, size: 12, color: Colors.white))
              : null,
        ),
      ),
    );
  }
}

class _NettoyageRow extends StatelessWidget {
  final List<DateTime> days;
  final String logementId;
  final bool Function(DateTime) isClean;
  final void Function(DateTime) onToggle;

  const _NettoyageRow({required this.days, required this.logementId, required this.isClean, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: Row(children: [
        for (final d in days)
          GestureDetector(
            onTap: () => onToggle(d),
            child: Container(
              width: 56, height: 28, alignment: Alignment.center,
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
              child: Icon(
                isClean(d) ? Icons.check_circle : Icons.cleaning_services_outlined,
                size: 13,
                color: isClean(d) ? const Color(0xFF6E9E57) : Colors.grey.shade300,
              ),
            ),
          ),
      ]),
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
