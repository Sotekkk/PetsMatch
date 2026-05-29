import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart';
import 'package:PetsMatch/pages/eleveur/animaux/portee_form_page.dart';
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
  String _filterRace    = '';
  bool   _filterPortee  = false;

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
  bool _loading = true;

  static const _green = Color(0xFF6E9E57);
  static const _teal  = Color(0xFF0C5C6C);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _loadAnimaux();
  }

  Future<void> _loadAnimaux() async {
    if (_uid == null) { setState(() => _loading = false); return; }
    setState(() => _loading = true);
    try {
      final rows = await Supabase.instance.client
          .from('animaux').select().eq('uid_eleveur', _uid!);
      if (mounted) setState(() {
        _animauxData = List<Map<String, dynamic>>.from(rows as List);
        _loading = false;
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
    if (_filterPortee)           c++;
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
                if (tmpEspece != 'tous' || tmpSexe != 'tous' || tmpRace.isNotEmpty || _filterPortee)
                  TextButton(
                    onPressed: () {
                      setSheet(() { tmpEspece = 'tous'; tmpSexe = 'tous'; tmpRace = ''; });
                      setState(() { _filterEspece = 'tous'; _filterSexe = 'tous'; _filterRace = ''; _filterPortee = false; });
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
              const SizedBox(height: 18),
              const Text('Portée', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                  fontSize: 13, color: Color(0xFF6F767B))),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () {
                  setSheet(() {});
                  setState(() => _filterPortee = !_filterPortee);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _filterPortee ? const Color(0xFF0C5C6C) : Colors.transparent,
                    border: Border.all(
                        color: _filterPortee ? const Color(0xFF0C5C6C) : Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.diversity_3, size: 13,
                        color: _filterPortee ? Colors.white : const Color(0xFF0C5C6C)),
                    const SizedBox(width: 5),
                    Text('Portées uniquement',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                            color: _filterPortee ? Colors.white : Colors.black87,
                            fontWeight: _filterPortee ? FontWeight.w600 : FontWeight.normal)),
                  ]),
                ),
              ),
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
        title: const Text('Mes Animaux',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
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
      floatingActionButton: isPresents
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
      if (_presentsFilterCount > 0) _buildPresentsFiltersRow(),
      Expanded(child: _buildPresentsList()),
    ]);
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
          if (_filterPortee) ...[
            const SizedBox(width: 6),
            _ActiveChip(
              label: 'Portées',
              color: const Color(0xFF0C5C6C),
              onRemove: () => setState(() => _filterPortee = false),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _buildPresentsList() {
    if (_uid == null) return const Center(child: Text('Non connecté'));
    if (_loading) return const Center(child: CircularProgressIndicator(color: _green));

    var docs = _animauxData.where((data) {
      final statut = data['statut'] as String? ?? '';
      if (statut == 'sorti' || statut == 'decede') return false;
      if (_filterEspece != 'tous' && data['espece'] != _filterEspece) return false;
      if (_filterSexe != 'tous' && data['sexe'] != _filterSexe) return false;
      if (_filterRace.isNotEmpty &&
          (data['race'] ?? '').toString().toLowerCase() != _filterRace.toLowerCase()) return false;
      if (_filterPortee && (data['portee_id'] == null || (data['portee_id'] as String).isEmpty)) return false;
      if (_search.isNotEmpty) {
        final nom  = (data['nom']            ?? '').toString().toLowerCase();
        final puce = (data['identification'] ?? '').toString().toLowerCase();
        if (!nom.contains(_search) && !puce.contains(_search)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => (a['nom'] ?? '').toString().compareTo((b['nom'] ?? '').toString()));

    if (docs.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          speciesIcon(_filterEspece == 'tous' ? 'autre' : _filterEspece, 56, Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            _presentsFilterCount > 0
                ? 'Aucun animal présent\ncorrespondant aux filtres'
                : 'Vous n\'avez aucun animal présent',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontFamily: 'Galey', fontSize: 15),
          ),
          const SizedBox(height: 16),
          if (_presentsFilterCount == 0)
            ElevatedButton.icon(
              onPressed: () => _showAddSheet(context),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un animal', style: TextStyle(fontFamily: 'Galey')),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _green, foregroundColor: Colors.white),
            )
          else
            TextButton(
              onPressed: () => setState(() {
                _filterEspece = 'tous'; _filterSexe = 'tous'; _filterRace = ''; _filterPortee = false;
              }),
              child: const Text('Réinitialiser les filtres',
                  style: TextStyle(fontFamily: 'Galey', color: Color(0xFF6E9E57))),
            ),
        ]),
      );
    }

    // Vue groupée par portée
    if (_filterPortee) return _buildPorteeGroupedView(docs);

    return GridView.builder(
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
          onTap: () => _openFiche(context, id, data: data),
          onDelete: id.isEmpty ? null : () => _deleteAnimal(id),
        );
      },
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

    return ListView.builder(
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
                onTap: () => _openFiche(context, id, data: data),
                onDelete: id.isEmpty ? null : () => _deleteAnimal(id),
              );
            },
          ),
        ]);
      },
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

    return GridView.builder(
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
          onTap: () => _openFiche(context, id, data: data),
          onDelete: id.isEmpty ? null : () => _deleteAnimal(id),
        );
      },
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
  final bool showStatut;
  final bool showPorteeBadge;
  const _AnimalCard({
    required this.id,
    required this.data,
    required this.onTap,
    this.onDelete,
    this.showStatut = false,
    this.showPorteeBadge = false,
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
      onLongPress: onDelete == null ? null : () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Supprimer cet animal ?',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            content: Text('La fiche de $nom sera définitivement supprimée.',
                style: const TextStyle(fontFamily: 'Galey')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Supprimer',
                    style: TextStyle(fontFamily: 'Galey', color: Colors.redAccent,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
        if (confirm == true) onDelete!();
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
