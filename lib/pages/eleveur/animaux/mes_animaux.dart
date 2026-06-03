import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart';
import 'package:PetsMatch/pages/eleveur/animaux/portee_form_page.dart';
import 'package:PetsMatch/services/chip_scanner_service.dart';
import 'package:PetsMatch/pages/eleveur/animaux/portee_poids_page.dart';
import 'package:PetsMatch/services/chaleurs_notif_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─── Données espèces ──────────────────────────────────────────────────────────

const kSpeciesData = [
  (value: 'tous',   label: 'Tous',     color: Color(0xFF1F2A2E)),
  (value: 'chien',  label: 'Chiens',   color: Color(0xFF6E9E57)),
  (value: 'chat',   label: 'Chats',    color: Color(0xFF0C5C6C)),
  (value: 'cheval', label: 'Chevaux',  color: Color(0xFF5B8648)),
  (value: 'lapin',  label: 'Lapins',   color: Color(0xFFE08080)),
  (value: 'ovin',   label: 'Ovins',    color: Color(0xFF5F9EAA)),
  (value: 'caprin', label: 'Caprins',  color: Color(0xFF8D6E63)),
  (value: 'porcin', label: 'Porcins',  color: Color(0xFFE25C5C)),
  (value: 'nac',    label: 'NAC',      color: Color(0xFFF4B400)),
  (value: 'oiseau', label: 'Oiseaux',  color: Color(0xFF26A69A)),
  (value: 'autre',  label: 'Autres',   color: Color(0xFF6F767B)),
];

String speciesLabel(String value) =>
    kSpeciesData.where((s) => s.value == value).firstOrNull?.label ?? value;

Color speciesColor(String value) =>
    kSpeciesData.where((s) => s.value == value).firstOrNull?.color ?? const Color(0xFF6E9E57);

Widget speciesIcon(String espece, double size, Color color) {
  switch (espece) {
    case 'chien':  return FaIcon(FontAwesomeIcons.dog,   size: size, color: color);
    case 'chat':   return FaIcon(FontAwesomeIcons.cat,   size: size, color: color);
    case 'cheval': return FaIcon(FontAwesomeIcons.horse, size: size, color: color);
    case 'lapin':  return FaIcon(FontAwesomeIcons.paw,   size: size, color: color);
    case 'oiseau': return FaIcon(FontAwesomeIcons.dove,  size: size, color: color);
    case 'nac':    return FaIcon(FontAwesomeIcons.bug,   size: size, color: color);
    case 'ovin':   return FaIcon(FontAwesomeIcons.leaf,  size: size, color: color);
    case 'caprin': return Icon(Icons.grass,              size: size, color: color);
    case 'porcin': return Icon(Icons.circle,             size: size, color: color);
    default:       return Icon(Icons.pets,               size: size, color: color);
  }
}

// ─── Page principale ──────────────────────────────────────────────────────────

class MesAnimauxPage extends StatefulWidget {
  const MesAnimauxPage({super.key});
  @override
  State<MesAnimauxPage> createState() => _MesAnimauxPageState();
}

class _MesAnimauxPageState extends State<MesAnimauxPage>
    with SingleTickerProviderStateMixin {
  // Présents filters
  String _filterEspece  = 'tous';
  String _filterSexe    = 'tous';
  String _filterRace     = '';
  String _presentsSubTab = 'tous'; // 'tous', 'repro', 'bebes'
  bool   _selectMode    = false;
  final Set<String> _selectedIds = {};

  // Anciens filters
  String    _anciensEspece = 'tous';
  String    _anciensStatut = 'tous'; // 'tous', 'sorti', 'decede'
  DateTime? _anciensDtDebut;
  DateTime? _anciensDtFin;

  String _search = '';
  final TextEditingController _searchController = TextEditingController();

  late TabController _tabController;
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  List<Map<String, dynamic>> _animauxData = [];
  Map<String, bool> _chaleurFlags  = {};
  Map<String, bool> _gestanteFlags = {};
  bool _loading = true;

  static const _green = Color(0xFF6E9E57);
  static const _teal  = Color(0xFF0C5C6C);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() { _selectMode = false; _selectedIds.clear(); });
      }
    });
    _loadAnimaux();
  }

  static int _intervalChaleurs(String espece) {
    switch (espece.toLowerCase()) {
      case 'chien':  return 182;
      case 'chat':   return 21;
      case 'lapin':  return 14;
      case 'ovin':   return 17;
      case 'caprin': return 21;
      case 'porcin': return 21;
      case 'cheval': return 21;
      default:       return 0;
    }
  }

  Future<void> _loadAnimaux() async {
    if (_uid == null) { setState(() => _loading = false); return; }
    if (_animauxData.isEmpty) setState(() => _loading = true);
    try {
      final supa = Supabase.instance.client;
      final rows = await supa.from('animaux').select().eq('uid_eleveur', _uid!);
      final animaux = List<Map<String, dynamic>>.from(rows as List);

      // IDs des femelles présentes
      final femIds = animaux
          .where((a) => a['sexe'] == 'femelle' &&
              !['sorti','decede'].contains(a['statut'] ?? ''))
          .map((a) => a['id'] as String)
          .toList();

      Map<String, bool> cFlags = {};
      Map<String, bool> gFlags = {};

      if (femIds.isNotEmpty) {
        // Dernières chaleurs
        final chaleurs = await supa.from('chaleurs')
            .select('animal_id, date')
            .inFilter('animal_id', femIds)
            .order('date', ascending: false);

        final Map<String, DateTime> lastChaleur = {};
        for (final c in chaleurs) {
          final aid = c['animal_id']?.toString() ?? '';
          final d = DateTime.tryParse(c['date'] ?? '');
          if (d != null && !lastChaleur.containsKey(aid)) lastChaleur[aid] = d;
        }

        final now = DateTime.now();
        for (final a in animaux) {
          final id = a['id'] as String? ?? '';
          if (!femIds.contains(id)) continue;
          final espece = a['espece'] as String? ?? '';
          final customInterval = a['intervalle_chaleurs_jours'] as int?;
          final interval = customInterval ?? _intervalChaleurs(espece);
          if (interval == 0) continue;
          final last = lastChaleur[id];
          if (last == null) continue;
          final diff = last.add(Duration(days: interval)).difference(now).inDays;
          if (diff <= 7) cFlags[id] = true;
        }

        // Gestantes confirmées sans date_naissance
        final gests = await supa.from('gestations')
            .select('animal_id')
            .inFilter('animal_id', femIds)
            .eq('gestation_confirmee', true)
            .isFilter('date_naissance', null);
        for (final g in gests) {
          final aid = g['animal_id']?.toString() ?? '';
          if (aid.isNotEmpty) gFlags[aid] = true;
        }
      }

      if (mounted) setState(() {
        _animauxData    = animaux;
        _chaleurFlags   = cFlags;
        _gestanteFlags  = gFlags;
        _loading        = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteAnimal(String id) async {
    try {
      await Supabase.instance.client.from('animaux').delete().eq('id', id);
      if (mounted) _loadAnimaux();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la suppression')),
        );
      }
    }
  }

  Future<void> _toggleReproducteur(String id, bool current) async {
    try {
      await Supabase.instance.client.from('animaux')
          .update({'reproducteur': !current}).eq('id', id);
      if (mounted) setState(() {
        final idx = _animauxData.indexWhere((a) => a['id']?.toString() == id);
        if (idx >= 0) _animauxData[idx] = {..._animauxData[idx], 'reproducteur': !current};
      });
    } catch (_) {}
  }

  Future<void> _regrouperEnPortee() async {
    if (_selectedIds.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sélectionne au moins 2 animaux')),
      );
      return;
    }
    final n = _selectedIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Regrouper en portée ?',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: Text(
          '$n animal${n > 1 ? 'aux' : ''} seront liés dans la même portée.',
          style: const TextStyle(fontFamily: 'Galey'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Regrouper',
                style: TextStyle(fontFamily: 'Galey', color: Color(0xFF0C5C6C),
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final porteeId = 'portee_${DateTime.now().millisecondsSinceEpoch}';
    try {
      await Supabase.instance.client.from('animaux')
          .update({'portee_id': porteeId})
          .inFilter('id', _selectedIds.toList());
      setState(() { _selectMode = false; _selectedIds.clear(); });
      _loadAnimaux();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors du regroupement')),
        );
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  int get _presentsFilterCount {
    int c = 0;
    if (_filterEspece != 'tous') c++;
    if (_filterSexe != 'tous')   c++;
    if (_filterRace.isNotEmpty)  c++;
    return c;
  }

  int get _anciensFilterCount {
    int c = 0;
    if (_anciensEspece != 'tous') c++;
    if (_anciensStatut != 'tous') c++;
    if (_anciensDtDebut != null || _anciensDtFin != null) c++;
    return c;
  }

  // ── Filter Présents sheet ────────────────────────────────────────────────────

  Future<void> _openPresentsFilterSheet() async {
    Map<String, List<String>> racesByEspece = {};
    Set<String> availableSpeciesSet = {};

    for (final d in _animauxData) {
      final statut = d['statut'] as String? ?? '';
      if (statut == 'sorti' || statut == 'decede') continue;
      final esp  = (d['espece'] ?? '') as String;
      final race = (d['race']   ?? '') as String;
      if (esp.isNotEmpty) {
        availableSpeciesSet.add(esp);
        if (race.isNotEmpty) {
          racesByEspece.putIfAbsent(esp, () => []);
          if (!racesByEspece[esp]!.contains(race)) racesByEspece[esp]!.add(race);
        }
      }
    }
    for (final k in racesByEspece.keys) racesByEspece[k]!.sort();
    if (!mounted) return;

    String tmpEspece = _filterEspece;
    String tmpSexe   = _filterSexe;
    String tmpRace   = _filterRace;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void apply({String? espece, String? sexe, String? race}) {
            setSheet(() {
              if (espece != null) {
                tmpEspece = espece;
                final newRaces = racesByEspece[espece] ?? [];
                if (!newRaces.contains(tmpRace)) tmpRace = '';
              }
              if (sexe != null) tmpSexe = sexe;
              if (race != null) tmpRace = (tmpRace == race) ? '' : race;
            });
            setState(() {
              _filterEspece = tmpEspece;
              _filterSexe   = tmpSexe;
              _filterRace   = tmpRace;
            });
          }

          final races = tmpEspece != 'tous' ? (racesByEspece[tmpEspece] ?? <String>[]) : <String>[];

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(children: [
                const Text('Filtrer mes animaux',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                        fontSize: 17, color: Color(0xFF1F2A2E))),
                const Spacer(),
                if (tmpEspece != 'tous' || tmpSexe != 'tous' || tmpRace.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      setSheet(() { tmpEspece = 'tous'; tmpSexe = 'tous'; tmpRace = ''; });
                      setState(() { _filterEspece = 'tous'; _filterSexe = 'tous'; _filterRace = ''; });
                    },
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    child: const Text('Réinitialiser',
                        style: TextStyle(fontFamily: 'Galey', color: Color(0xFF6E9E57))),
                  ),
              ]),
              const SizedBox(height: 16),
              const Text('Espèce', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                  fontSize: 13, color: Color(0xFF6F767B))),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8,
                  children: kSpeciesData
                      .where((sp) => sp.value == 'tous' || availableSpeciesSet.contains(sp.value))
                      .map((sp) {
                final active = tmpEspece == sp.value;
                return GestureDetector(
                  onTap: () => apply(espece: sp.value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: active ? sp.color : Colors.transparent,
                      border: Border.all(color: active ? sp.color : Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (sp.value != 'tous') ...[
                        speciesIcon(sp.value, 13, active ? Colors.white : sp.color),
                        const SizedBox(width: 5),
                      ],
                      Text(sp.label, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                          color: active ? Colors.white : Colors.black87,
                          fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
                    ]),
                  ),
                );
              }).toList()),
              const SizedBox(height: 18),
              const Text('Sexe', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                  fontSize: 13, color: Color(0xFF6F767B))),
              const SizedBox(height: 10),
              Row(children: [
                _SexeChip(label: 'Tous',       active: tmpSexe == 'tous',    onTap: () => apply(sexe: 'tous')),
                const SizedBox(width: 8),
                _SexeChip(label: '♂  Mâle',    active: tmpSexe == 'male',    onTap: () => apply(sexe: 'male')),
                const SizedBox(width: 8),
                _SexeChip(label: '♀  Femelle',  active: tmpSexe == 'femelle', onTap: () => apply(sexe: 'femelle')),
              ]),
              if (races.isNotEmpty) ...[
                const SizedBox(height: 18),
                const Text('Race', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                    fontSize: 13, color: Color(0xFF6F767B))),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: races.map((r) {
                  final active = tmpRace == r;
                  return GestureDetector(
                    onTap: () => apply(race: r),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: active ? _teal : Colors.transparent,
                        border: Border.all(color: active ? _teal : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(r, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                          color: active ? Colors.white : Colors.black87,
                          fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
                    ),
                  );
                }).toList()),
              ],
              const SizedBox(height: 8),
            ]),
          );
        },
      ),
    );
  }

  // ── Filter Anciens sheet ─────────────────────────────────────────────────────

  Future<void> _openAnciensFilterSheet() async {
    Set<String> availableSpeciesSet = {};

    for (final d in _animauxData) {
      final statut = d['statut'] as String? ?? '';
      if (statut != 'sorti' && statut != 'decede') continue;
      final esp = (d['espece'] ?? '') as String;
      if (esp.isNotEmpty) availableSpeciesSet.add(esp);
    }
    if (!mounted) return;

    String    tmpEspece = _anciensEspece;
    String    tmpStatut = _anciensStatut;
    DateTime? tmpDebut  = _anciensDtDebut;
    DateTime? tmpFin    = _anciensDtFin;
    final fmt = DateFormat('dd/MM/yyyy');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void apply() {
            setState(() {
              _anciensEspece  = tmpEspece;
              _anciensStatut  = tmpStatut;
              _anciensDtDebut = tmpDebut;
              _anciensDtFin   = tmpFin;
            });
          }

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(children: [
                const Text('Filtrer les anciens',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                        fontSize: 17, color: Color(0xFF1F2A2E))),
                const Spacer(),
                if (tmpEspece != 'tous' || tmpStatut != 'tous' || tmpDebut != null || tmpFin != null)
                  TextButton(
                    onPressed: () {
                      setSheet(() { tmpEspece = 'tous'; tmpStatut = 'tous'; tmpDebut = null; tmpFin = null; });
                      setState(() { _anciensEspece = 'tous'; _anciensStatut = 'tous'; _anciensDtDebut = null; _anciensDtFin = null; });
                    },
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    child: const Text('Réinitialiser',
                        style: TextStyle(fontFamily: 'Galey', color: Color(0xFF6E9E57))),
                  ),
              ]),
              const SizedBox(height: 16),

              // Espèce
              const Text('Espèce', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                  fontSize: 13, color: Color(0xFF6F767B))),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8,
                  children: kSpeciesData
                      .where((sp) => sp.value == 'tous' || availableSpeciesSet.contains(sp.value))
                      .map((sp) {
                final active = tmpEspece == sp.value;
                return GestureDetector(
                  onTap: () { setSheet(() => tmpEspece = sp.value); apply(); },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: active ? sp.color : Colors.transparent,
                      border: Border.all(color: active ? sp.color : Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (sp.value != 'tous') ...[
                        speciesIcon(sp.value, 13, active ? Colors.white : sp.color),
                        const SizedBox(width: 5),
                      ],
                      Text(sp.label, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                          color: active ? Colors.white : Colors.black87,
                          fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
                    ]),
                  ),
                );
              }).toList()),
              const SizedBox(height: 18),

              // Statut
              const Text('Statut', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                  fontSize: 13, color: Color(0xFF6F767B))),
              const SizedBox(height: 10),
              Row(children: [
                _SexeChip(label: 'Tous',    active: tmpStatut == 'tous',   onTap: () { setSheet(() => tmpStatut = 'tous');   apply(); }),
                const SizedBox(width: 8),
                _SexeChip(label: 'Sorti',   active: tmpStatut == 'sorti',  onTap: () { setSheet(() => tmpStatut = 'sorti');  apply(); }),
                const SizedBox(width: 8),
                _SexeChip(label: 'Décédé',  active: tmpStatut == 'decede', onTap: () { setSheet(() => tmpStatut = 'decede'); apply(); }),
              ]),
              const SizedBox(height: 18),

              // Période de sortie
              const Text('Période de sortie', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                  fontSize: 13, color: Color(0xFF6F767B))),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: tmpDebut ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) { setSheet(() => tmpDebut = picked); apply(); }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: tmpDebut != null ? _teal : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        Icon(Icons.calendar_today_outlined, size: 14,
                            color: tmpDebut != null ? _teal : Colors.grey),
                        const SizedBox(width: 6),
                        Text(tmpDebut != null ? fmt.format(tmpDebut!) : 'Du...',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                                color: tmpDebut != null ? _teal : Colors.grey)),
                        if (tmpDebut != null) ...[
                          const Spacer(),
                          GestureDetector(
                            onTap: () { setSheet(() => tmpDebut = null); apply(); },
                            child: const Icon(Icons.close, size: 14, color: Colors.grey),
                          ),
                        ],
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: tmpFin ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) { setSheet(() => tmpFin = picked); apply(); }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: tmpFin != null ? _teal : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        Icon(Icons.calendar_today_outlined, size: 14,
                            color: tmpFin != null ? _teal : Colors.grey),
                        const SizedBox(width: 6),
                        Text(tmpFin != null ? fmt.format(tmpFin!) : 'Au...',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                                color: tmpFin != null ? _teal : Colors.grey)),
                        if (tmpFin != null) ...[
                          const Spacer(),
                          GestureDetector(
                            onTap: () { setSheet(() => tmpFin = null); apply(); },
                            child: const Icon(Icons.close, size: 14, color: Colors.grey),
                          ),
                        ],
                      ]),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
            ]),
          );
        },
      ),
    );
  }

  Future<void> _openFilterSheet() async {
    if (_tabController.index == 0) {
      await _openPresentsFilterSheet();
    } else {
      await _openAnciensFilterSheet();
    }
  }

  Widget _buildSearchField() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
        style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Nom ou numéro de puce...',
          hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFFB0B8C1)),
          prefixIcon: const Icon(Icons.search, color: Color(0xFF6E9E57), size: 20),
          suffixIcon: _search.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Color(0xFF6F767B)),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _search = '');
                  },
                )
              : null,
          filled: true,
          fillColor: const Color(0xFFF8F8F6),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF6E9E57), width: 1.5),
          ),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isPresents  = _tabController.index == 0;
    final filterCount = isPresents ? _presentsFilterCount : _anciensFilterCount;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        title: _selectMode
            ? Text('${_selectedIds.length} sélectionné${_selectedIds.length != 1 ? 's' : ''}',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700))
            : const Text('Mes Animaux',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: _selectMode ? [
          IconButton(
            icon: Icon(Icons.group_work_outlined,
                color: _selectedIds.isNotEmpty ? Colors.white : Colors.white38),
            onPressed: _selectedIds.isNotEmpty ? _regrouperEnPortee : null,
            tooltip: 'Regrouper en portée',
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() { _selectMode = false; _selectedIds.clear(); }),
            tooltip: 'Annuler',
          ),
        ] : [
          if (isPresents)
            IconButton(
              icon: const Icon(Icons.checklist_outlined),
              onPressed: () => setState(() { _selectMode = true; _selectedIds.clear(); }),
              tooltip: 'Sélectionner',
            ),
          if (_uid != null)
            IconButton(
              icon: const Icon(Icons.sensors_rounded),
              onPressed: () => ChipScannerService.scanFromElevage(context, _uid),
              tooltip: 'Scanner une puce',
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: const Icon(Icons.tune),
                  onPressed: _openFilterSheet,
                  tooltip: 'Filtres',
                ),
                if (filterCount > 0)
                  Positioned(
                    right: 4, top: 4,
                    child: Container(
                      width: 16, height: 16,
                      decoration: const BoxDecoration(
                          color: Color(0xFF6E9E57), shape: BoxShape.circle),
                      child: Center(
                        child: Text('$filterCount',
                            style: const TextStyle(color: Colors.white,
                                fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Présents'),
            Tab(text: 'Anciens'),
          ],
          indicatorColor: const Color(0xFF6E9E57),
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14),
          unselectedLabelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 14),
        ),
      ),
      floatingActionButton: isPresents && !_selectMode
          ? FloatingActionButton(
              onPressed: () => _showAddSheet(context),
              backgroundColor: _green,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPresentsTab(),
          _buildAnciensTab(),
        ],
      ),
    );
  }

  // ── Présents tab ──────────────────────────────────────────────────────────────

  Widget _buildPresentsTab() {
    return Column(children: [
      _buildSearchField(),
      _buildPresentsSubTabs(),
      if (_presentsFilterCount > 0) _buildPresentsFiltersRow(),
      Expanded(child: _buildPresentsList()),
    ]);
  }

  Widget _buildPresentsSubTabs() {
    const tabs = [
      ('tous',  'Tous'),
      ('repro', '⭐ Repro'),
      ('bebes', '🐣 Bébés'),
    ];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Row(children: tabs.map((t) {
        final active = _presentsSubTab == t.$1;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => setState(() => _presentsSubTab = t.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: active ? _teal : Colors.transparent,
                border: Border.all(color: active ? _teal : Colors.grey.shade300),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(t.$2, style: TextStyle(
                fontFamily: 'Galey', fontSize: 13,
                color: active ? Colors.white : Colors.black87,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              )),
            ),
          ),
        );
      }).toList()),
    );
  }

  Widget _buildPresentsFiltersRow() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          if (_filterEspece != 'tous')
            _ActiveChip(
              label: speciesLabel(_filterEspece),
              color: speciesColor(_filterEspece),
              onRemove: () => setState(() { _filterEspece = 'tous'; _filterRace = ''; }),
            ),
          if (_filterSexe != 'tous') ...[
            if (_filterEspece != 'tous') const SizedBox(width: 6),
            _ActiveChip(
              label: _filterSexe == 'male' ? '♂ Mâle' : '♀ Femelle',
              color: const Color(0xFF5F9EAA),
              onRemove: () => setState(() => _filterSexe = 'tous'),
            ),
          ],
          if (_filterRace.isNotEmpty) ...[
            const SizedBox(width: 6),
            _ActiveChip(
              label: _filterRace,
              color: const Color(0xFF0C5C6C),
              onRemove: () => setState(() => _filterRace = ''),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _buildPresentsList() {
    if (_uid == null) return const Center(child: Text('Non connecté'));
    if (_loading) return const Center(child: CircularProgressIndicator(color: _green));

    // Base filter: présents only + search + espèce/sexe/race
    var base = _animauxData.where((data) {
      final statut = data['statut'] as String? ?? '';
      if (statut == 'sorti' || statut == 'decede') return false;
      if (_filterEspece != 'tous' && data['espece'] != _filterEspece) return false;
      if (_filterSexe != 'tous' && data['sexe'] != _filterSexe) return false;
      if (_filterRace.isNotEmpty &&
          (data['race'] ?? '').toString().toLowerCase() != _filterRace.toLowerCase()) return false;
      if (_search.isNotEmpty) {
        final nom  = (data['nom']            ?? '').toString().toLowerCase();
        final puce = (data['identification'] ?? '').toString().toLowerCase();
        if (!nom.contains(_search) && !puce.contains(_search)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => (a['nom'] ?? '').toString().compareTo((b['nom'] ?? '').toString()));

    // Sub-tab filtering
    List<Map<String, dynamic>> docs;
    if (_presentsSubTab == 'repro') {
      docs = base.where((d) => d['reproducteur'] == true).toList();
    } else if (_presentsSubTab == 'bebes') {
      docs = base.where((d) {
        final pid = d['portee_id'] as String? ?? '';
        return pid.isNotEmpty && d['reproducteur'] != true;
      }).toList();
    } else {
      docs = base;
    }

    if (docs.isEmpty) {
      String emptyMsg;
      if (_presentsSubTab == 'repro') {
        emptyMsg = 'Aucun animal reproducteur\nAppui long sur une carte pour en marquer un';
      } else if (_presentsSubTab == 'bebes') {
        emptyMsg = 'Aucun bébé dans une portée';
      } else {
        emptyMsg = _presentsFilterCount > 0
            ? 'Aucun animal présent\ncorrespondant aux filtres'
            : 'Vous n\'avez aucun animal présent';
      }
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          speciesIcon(_filterEspece == 'tous' ? 'autre' : _filterEspece, 56, Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(emptyMsg, textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500, fontFamily: 'Galey', fontSize: 15)),
          const SizedBox(height: 16),
          if (_presentsSubTab == 'tous' && _presentsFilterCount == 0)
            ElevatedButton.icon(
              onPressed: () => _showAddSheet(context),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un animal', style: TextStyle(fontFamily: 'Galey')),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _green, foregroundColor: Colors.white),
            )
          else if (_presentsSubTab == 'tous' && _presentsFilterCount > 0)
            TextButton(
              onPressed: () => setState(() {
                _filterEspece = 'tous'; _filterSexe = 'tous'; _filterRace = '';
              }),
              child: const Text('Réinitialiser les filtres',
                  style: TextStyle(fontFamily: 'Galey', color: Color(0xFF6E9E57))),
            ),
        ]),
      );
    }

    if (_presentsSubTab == 'bebes') return _buildPorteeGroupedView(docs);

    return RefreshIndicator(
      onRefresh: _loadAnimaux,
      color: _green,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.68,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: docs.length,
        itemBuilder: (_, i) {
          final data = docs[i];
          final id = data['id'] as String? ?? '';
          return _AnimalCard(
            id: id,
            data: data,
            reproducteur: data['reproducteur'] == true,
            chaleurFlag:  _chaleurFlags[id]  ?? false,
            gestanteFlag: _gestanteFlags[id] ?? false,
            selectMode: _selectMode,
            selected: _selectedIds.contains(id),
            onTap: _selectMode
                ? () => setState(() {
                    if (_selectedIds.contains(id)) _selectedIds.remove(id);
                    else _selectedIds.add(id);
                  })
                : () => _openFiche(context, id, data: data),
            onDelete: id.isEmpty ? null : () => _deleteAnimal(id),
            onToggleReproducteur: id.isEmpty ? null : () => _toggleReproducteur(id, data['reproducteur'] == true),
          );
        },
      ),
    );
  }

  Widget _buildPorteeGroupedView(List<Map<String, dynamic>> docs) {
    final fmt = DateFormat('dd/MM/yyyy');
    // Grouper par portee_id
    final Map<String, List<Map<String, dynamic>>> groups = {};
    for (final d in docs) {
      final pid = (d['portee_id'] as String?) ?? '';
      if (pid.isEmpty) continue;
      groups.putIfAbsent(pid, () => []).add(d);
    }
    // Trier les groupes par date de naissance décroissante
    final sortedKeys = groups.keys.toList()
      ..sort((a, b) {
        final da = DateTime.tryParse(groups[a]!.first['date_naissance'] as String? ?? '') ?? DateTime(0);
        final db = DateTime.tryParse(groups[b]!.first['date_naissance'] as String? ?? '') ?? DateTime(0);
        return db.compareTo(da);
      });

    return RefreshIndicator(
      onRefresh: _loadAnimaux,
      color: _green,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sortedKeys.length,
        itemBuilder: (_, gi) {
        final pid      = sortedKeys[gi];
        final members  = groups[pid]!;
        final first    = members.first;
        final dn       = DateTime.tryParse(first['date_naissance'] as String? ?? '');
        final race     = (first['race'] as String?) ?? '';
        final espece   = (first['espece'] as String?) ?? '';

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (gi > 0) const SizedBox(height: 20),
          // Header portée
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _teal.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _teal.withOpacity(0.2)),
            ),
            child: Row(children: [
              const Icon(Icons.diversity_3, size: 18, color: _teal),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    [
                      'Portée',
                      if (race.isNotEmpty) race,
                      if (espece.isNotEmpty) '· ${speciesLabel(espece)}',
                    ].join(' '),
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                        fontSize: 13, color: _teal),
                  ),
                  if (dn != null)
                    Text('Nés le ${fmt.format(dn)}',
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 11,
                            color: Color(0xFF5F9EAA))),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _teal.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${members.length}',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                        fontSize: 13, color: _teal)),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => PorteePoidsPage(
                    animals: members,
                    dateNaissance: dn,
                  ),
                )),
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: _teal.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.bar_chart, size: 18, color: _teal),
                ),
              ),
            ]),
          ),
          // Grille animaux de la portée
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.68,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: members.length,
            itemBuilder: (_, i) {
              final data = members[i];
              final id = data['id'] as String? ?? '';
              return _AnimalCard(
                id: id,
                data: data,
                showPorteeBadge: true,
                reproducteur: data['reproducteur'] == true,
                chaleurFlag:  _chaleurFlags[id]  ?? false,
                gestanteFlag: _gestanteFlags[id] ?? false,
                selectMode: _selectMode,
                selected: _selectedIds.contains(id),
                onTap: _selectMode
                    ? () => setState(() {
                        if (_selectedIds.contains(id)) _selectedIds.remove(id);
                        else _selectedIds.add(id);
                      })
                    : () => _openFiche(context, id, data: data),
                onDelete: id.isEmpty ? null : () => _deleteAnimal(id),
                onToggleReproducteur: id.isEmpty ? null : () => _toggleReproducteur(id, data['reproducteur'] == true),
              );
            },
          ),
        ]);
        },
      ),
    );
  }

  // ── Anciens tab ───────────────────────────────────────────────────────────────

  Widget _buildAnciensTab() {
    return Column(children: [
      _buildSearchField(),
      if (_anciensFilterCount > 0) _buildAnciensFiltersRow(),
      Expanded(child: _buildAnciensList()),
    ]);
  }

  Widget _buildAnciensFiltersRow() {
    final fmt = DateFormat('dd/MM/yy');
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          if (_anciensEspece != 'tous')
            _ActiveChip(
              label: speciesLabel(_anciensEspece),
              color: speciesColor(_anciensEspece),
              onRemove: () => setState(() => _anciensEspece = 'tous'),
            ),
          if (_anciensStatut != 'tous') ...[
            if (_anciensEspece != 'tous') const SizedBox(width: 6),
            _ActiveChip(
              label: _anciensStatut == 'sorti' ? 'Sorti' : 'Décédé',
              color: _anciensStatut == 'sorti' ? _teal : Colors.redAccent,
              onRemove: () => setState(() => _anciensStatut = 'tous'),
            ),
          ],
          if (_anciensDtDebut != null || _anciensDtFin != null) ...[
            const SizedBox(width: 6),
            _ActiveChip(
              label: [
                if (_anciensDtDebut != null) 'Du ${fmt.format(_anciensDtDebut!)}',
                if (_anciensDtFin != null) 'au ${fmt.format(_anciensDtFin!)}',
              ].join(' '),
              color: const Color(0xFF5F9EAA),
              onRemove: () => setState(() { _anciensDtDebut = null; _anciensDtFin = null; }),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _buildAnciensList() {
    if (_uid == null) return const Center(child: Text('Non connecté'));
    if (_loading) return const Center(child: CircularProgressIndicator(color: _green));

    var docs = _animauxData.where((data) {
      final statut = data['statut'] as String? ?? '';
      if (statut != 'sorti' && statut != 'decede') return false;
      if (_anciensEspece != 'tous' && data['espece'] != _anciensEspece) return false;
      if (_anciensStatut != 'tous' && statut != _anciensStatut) return false;
      if (_anciensDtDebut != null || _anciensDtFin != null) {
        final ds = data['date_sortie'] as String?;
        if (ds == null || ds.isEmpty) return false;
        final dt = DateTime.tryParse(ds);
        if (dt == null) return false;
        if (_anciensDtDebut != null && dt.isBefore(_anciensDtDebut!)) return false;
        if (_anciensDtFin != null &&
            dt.isAfter(_anciensDtFin!.add(const Duration(days: 1)))) return false;
      }
      if (_search.isNotEmpty) {
        final nom  = (data['nom']            ?? '').toString().toLowerCase();
        final puce = (data['identification'] ?? '').toString().toLowerCase();
        if (!nom.contains(_search) && !puce.contains(_search)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final da = DateTime.tryParse(a['date_sortie'] as String? ?? '') ?? DateTime(0);
        final db = DateTime.tryParse(b['date_sortie'] as String? ?? '') ?? DateTime(0);
        return db.compareTo(da);
      });

    if (docs.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.history, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            _anciensFilterCount > 0
                ? 'Aucun ancien animal\ncorrespondant aux filtres'
                : 'Aucun animal sorti ou décédé',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontFamily: 'Galey', fontSize: 15),
          ),
          if (_anciensFilterCount > 0) ...[
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => setState(() {
                _anciensEspece = 'tous'; _anciensStatut = 'tous';
                _anciensDtDebut = null; _anciensDtFin = null;
              }),
              child: const Text('Réinitialiser les filtres',
                  style: TextStyle(fontFamily: 'Galey', color: Color(0xFF6E9E57))),
            ),
          ],
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAnimaux,
      color: _green,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.68,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: docs.length,
        itemBuilder: (_, i) {
          final data = docs[i];
          final id = data['id'] as String? ?? '';
          return _AnimalCard(
            id: id,
            data: data,
            showStatut: true,
            chaleurFlag:  _chaleurFlags[id]  ?? false,
            gestanteFlag: _gestanteFlags[id] ?? false,
            onTap: () => _openFiche(context, id, data: data),
            onDelete: id.isEmpty ? null : () => _deleteAnimal(id),
          );
        },
      ),
    );
  }

  void _openFiche(BuildContext context, String? animalId, {Map<String, dynamic>? data}) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => AnimalFichePage(
        animalId: animalId,
        initialData: data,
        preselectedEspece: _filterEspece != 'tous' ? _filterEspece : null,
      ),
    )).then((_) => _loadAnimaux());
  }

  void _showAddSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          const Text('Ajouter des animaux',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                  fontSize: 17, color: Color(0xFF1F2A2E))),
          const SizedBox(height: 20),
          _AddOptionTile(
            icon: Icons.pets,
            color: _green,
            title: 'Ajouter un animal',
            subtitle: 'Fiche individuelle complète',
            onTap: () {
              Navigator.pop(context);
              _openFiche(context, null);
            },
          ),
          const SizedBox(height: 12),
          _AddOptionTile(
            icon: Icons.diversity_3,
            color: _teal,
            title: 'Charger une portée',
            subtitle: 'Créer plusieurs animaux d\'un coup\navec parents communs',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => const PorteeFormPage(),
              )).then((created) {
                if (created == true) _loadAnimaux();
              });
            },
          ),
        ]),
      ),
    );
  }
}

// ─── Card animal ──────────────────────────────────────────────────────────────

class _AnimalCard extends StatelessWidget {
  final String id;
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleReproducteur;
  final bool showStatut;
  final bool showPorteeBadge;
  final bool reproducteur;
  final bool chaleurFlag;
  final bool gestanteFlag;
  final bool selectMode;
  final bool selected;
  const _AnimalCard({
    required this.id,
    required this.data,
    required this.onTap,
    this.onDelete,
    this.onToggleReproducteur,
    this.showStatut = false,
    this.showPorteeBadge = false,
    this.reproducteur = false,
    this.chaleurFlag = false,
    this.gestanteFlag = false,
    this.selectMode = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final photoUrl = data['photo_url'] as String?;
    final nom    = data['nom']    as String? ?? 'Sans nom';
    final espece = data['espece'] as String? ?? '';
    final race   = data['race']   as String? ?? '';
    final sexe   = data['sexe']   as String? ?? '';
    final statut = data['statut'] as String? ?? '';
    final color  = speciesColor(espece);

    return GestureDetector(
      onTap: onTap,
      onLongPress: selectMode || (onDelete == null && onToggleReproducteur == null) ? null : () {
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (_) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 14),
              Text(nom, style: const TextStyle(fontFamily: 'Galey',
                  fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF1F2A2E))),
              const SizedBox(height: 6),
              const Divider(),
              if (onToggleReproducteur != null)
                ListTile(
                  leading: Icon(Icons.star,
                      color: reproducteur ? Colors.amber : Colors.grey.shade400),
                  title: Text(
                    reproducteur ? 'Retirer reproducteur' : 'Marquer reproducteur',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 15),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    onToggleReproducteur!();
                  },
                ),
              if (onDelete != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  title: const Text('Supprimer',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 15,
                          color: Colors.redAccent)),
                  onTap: () async {
                    Navigator.pop(context);
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        title: const Text('Supprimer cet animal ?',
                            style: TextStyle(fontFamily: 'Galey',
                                fontWeight: FontWeight.w700)),
                        content: Text(
                            'La fiche de $nom sera définitivement supprimée.',
                            style: const TextStyle(fontFamily: 'Galey')),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Annuler',
                                style: TextStyle(fontFamily: 'Galey')),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Supprimer',
                                style: TextStyle(fontFamily: 'Galey',
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) onDelete!();
                  },
                ),
            ]),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: AspectRatio(
                aspectRatio: 1.0,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    photoUrl != null
                        ? CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.cover)
                        : Container(
                            color: color.withOpacity(0.12),
                            child: Center(child: speciesIcon(espece, 44, color)),
                          ),
                    if (showStatut && (statut == 'sorti' || statut == 'decede'))
                      Positioned(
                        top: 6, right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: statut == 'decede' ? Colors.redAccent : const Color(0xFF0C5C6C),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            statut == 'decede' ? 'Décédé' : 'Sorti',
                            style: const TextStyle(color: Colors.white, fontSize: 9,
                                fontFamily: 'Galey', fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    if (!showStatut && reproducteur)
                      Positioned(
                        top: 6, right: 6,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.92),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.star, size: 11, color: Colors.white),
                        ),
                      ),
                    if (showPorteeBadge && (data['portee_id'] as String? ?? '').isNotEmpty)
                      Positioned(
                        top: 6, left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0C5C6C).withOpacity(0.85),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.diversity_3, size: 8, color: Colors.white),
                            SizedBox(width: 3),
                            Text('Portée', style: TextStyle(color: Colors.white, fontSize: 8,
                                fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                    if (selectMode)
                      Positioned.fill(
                        child: Container(
                          color: selected
                              ? const Color(0xFF0C5C6C).withOpacity(0.18)
                              : Colors.transparent,
                        ),
                      ),
                    if (selectMode)
                      Positioned(
                        top: 6, left: 6,
                        child: Container(
                          width: 22, height: 22,
                          decoration: BoxDecoration(
                            color: selected ? const Color(0xFF0C5C6C) : Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: selected ? const Color(0xFF0C5C6C) : Colors.grey.shade400,
                                width: 2),
                          ),
                          child: selected
                              ? const Icon(Icons.check, size: 13, color: Colors.white)
                              : null,
                        ),
                      ),
                    if (gestanteFlag || chaleurFlag)
                      Positioned(
                        bottom: 6, left: 6,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (gestanteFlag)
                              Container(
                                margin: const EdgeInsets.only(bottom: 2),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6E9E57).withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text('🤰 Gestante',
                                    style: TextStyle(color: Colors.white, fontSize: 8,
                                        fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                              ),
                            if (chaleurFlag)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.pink.shade400.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text('🌸 Chaleurs',
                                    style: TextStyle(color: Colors.white, fontSize: 8,
                                        fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nom,
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                        fontSize: 14, color: Color(0xFF1F2A2E)),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                if (race.isNotEmpty)
                  Text(race,
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6F767B)),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 5),
                Row(children: [
                  _Chip(speciesLabel(espece), color),
                  if (sexe.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    _Chip(sexe == 'male' ? '♂' : '♀', const Color(0xFF5F9EAA)),
                  ],
                ]),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Widgets helpers ──────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
      child: Text(label,
          style: TextStyle(fontSize: 10, color: color,
              fontFamily: 'Galey', fontWeight: FontWeight.w600)),
    );
  }
}

class _SexeChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SexeChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF5F9EAA) : Colors.transparent,
          border: Border.all(color: active ? const Color(0xFF5F9EAA) : Colors.grey.shade300),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(
            fontFamily: 'Galey', fontSize: 13,
            color: active ? Colors.white : Colors.black87,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }
}

class _AddOptionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _AddOptionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                fontSize: 15, color: color)),
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
                color: Color(0xFF6F767B))),
          ])),
          Icon(Icons.chevron_right, color: color.withOpacity(0.6)),
        ]),
      ),
    );
  }
}

class _ActiveChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onRemove;
  const _ActiveChip({required this.label, required this.color, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
            color: color, fontWeight: FontWeight.w600)),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: onRemove,
          child: Icon(Icons.close, size: 13, color: color),
        ),
      ]),
    );
  }
}
