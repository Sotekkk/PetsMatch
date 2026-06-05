import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart';
import 'package:PetsMatch/services/chip_scanner_service.dart';

class VetPatientsPage extends StatefulWidget {
  const VetPatientsPage({super.key});

  @override
  State<VetPatientsPage> createState() => _VetPatientsPageState();
}

class _VetPatientsPageState extends State<VetPatientsPage> {
  static const _teal = Color(0xFF26A69A);
  static const _bg = Color(0xFFF8F8F8);

  bool _loading = true;
  List<Map<String, dynamic>> _patients = [];
  String _search = '';
  String? _filterEspece;

  static const _especes = ['chien','chat','cheval','lapin','oiseau','nac','ovin','caprin','porcin','ane','autre'];
  static const _especeEmoji = {'chien':'🐕','chat':'🐈','cheval':'🐴','lapin':'🐰',
      'oiseau':'🦜','nac':'🦎','ovin':'🐑','caprin':'🐐','porcin':'🐷','ane':'🐴','autre':'🐾'};

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  Future<void> _loadPatients() async {
    final vetUid = FirebaseAuth.instance.currentUser?.uid;
    if (vetUid == null) { setState(() => _loading = false); return; }
    try {
      final grants = await Supabase.instance.client
          .from('vet_access_grants')
          .select('id, animal_id, granted_at, status')
          .eq('vet_id', vetUid)
          .neq('status', 'revoked')
          .order('granted_at', ascending: false);

      final animalIds = (grants as List)
          .map((g) => g['animal_id']?.toString())
          .whereType<String>()
          .toList();

      if (animalIds.isEmpty) {
        if (mounted) setState(() { _patients = []; _loading = false; });
        return;
      }

      final animals = await Supabase.instance.client
          .from('animaux')
          .select('id, nom, espece, race, photo_url, date_naissance, identification')
          .inFilter('id', animalIds);

      final grantsMap = <String, Map<String, String>>{
        for (final g in (grants as List))
          if (g['animal_id'] != null) g['animal_id'].toString(): {
            'granted_at': (g['granted_at'] ?? '').toString(),
            'status': (g['status'] ?? 'demande').toString(),
            'grant_id': (g['id'] ?? '').toString(),
          }
      };

      final list = (animals as List).map((a) {
        final m = Map<String, dynamic>.from(a as Map);
        final info = grantsMap[a['id']?.toString()] ?? {};
        m['granted_at'] = info['granted_at'] ?? '';
        m['grant_status'] = info['status'] ?? 'demande';
        m['grant_id'] = info['grant_id'] ?? '';
        return m;
      }).toList();

      list.sort((a, b) => (b['granted_at'] as String).compareTo(a['granted_at'] as String));

      if (mounted) setState(() { _patients = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    return _patients.where((p) {
      if (_filterEspece != null && p['espece']?.toString() != _filterEspece) return false;
      if (_search.trim().isEmpty) return true;
      final q = _search.toLowerCase();
      return (p['nom'] ?? '').toString().toLowerCase().contains(q)
          || (p['espece'] ?? '').toString().toLowerCase().contains(q)
          || (p['race'] ?? '').toString().toLowerCase().contains(q)
          || (p['identification'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _revoquerPatient(Map<String, dynamic> patient) async {
    final grantId = patient['grant_id']?.toString() ?? '';
    if (grantId.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Retirer ce patient ?',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
        content: Text('${patient['nom'] ?? 'Cet animal'} sera retiré de votre liste de patients.',
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey'))),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Retirer', style: TextStyle(fontFamily: 'Galey')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await Supabase.instance.client.from('vet_access_grants')
        .update({'status': 'revoked', 'revoked_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', grantId);
    _loadPatients();
  }

  Future<void> _openPatient(Map<String, dynamic> animal) async {
    if (animal['grant_status'] != 'active') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Accès en attente d\'approbation par le propriétaire',
            style: TextStyle(fontFamily: 'Galey')),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => AnimalFichePage(
        animalId: animal['id']?.toString(),
        initialData: animal,
        readOnly: true,
        vetMode: true,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Mes patients',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.keyboard_outlined),
            tooltip: 'Saisir une puce manuellement',
            onPressed: () async {
              await ChipScannerService.enterPuceForVet(context);
              _loadPatients();
            },
          ),
          IconButton(
            icon: const Icon(Icons.sensors_rounded),
            tooltip: 'Scanner une puce',
            onPressed: () async {
              await ChipScannerService.scanFromVet(context);
              _loadPatients();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : RefreshIndicator(
              onRefresh: _loadPatients,
              color: _teal,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(children: [
                      Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: TextField(
                        onChanged: (v) => setState(() => _search = v),
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Nom, espèce, race, puce…',
                          hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey),
                          prefixIcon: const Icon(Icons.search, size: 20, color: Colors.grey),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: _teal, width: 1.5)),
                        ),
                      ),
                    ),
                    // Filtres espèce
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          _EspeceChip(label: 'Tous', selected: _filterEspece == null,
                              color: _teal, onTap: () => setState(() => _filterEspece = null)),
                          ..._especes.where((e) => _patients.any((p) => p['espece'] == e)).map((e) =>
                            _EspeceChip(
                              label: '${_especeEmoji[e] ?? ''} ${e[0].toUpperCase()}${e.substring(1)}',
                              selected: _filterEspece == e,
                              color: _teal,
                              onTap: () => setState(() => _filterEspece = e),
                            )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ])),
                  if (_filtered.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.pets_outlined, size: 72, color: Colors.grey.shade200),
                            const SizedBox(height: 16),
                            const Text('Aucun patient',
                                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                                    fontSize: 18, color: Color(0xFF1F2A2E))),
                            const SizedBox(height: 8),
                            Text(
                              'Scannez la puce d\'un animal pour\nl\'ajouter à vos patients.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                                  color: Colors.grey.shade500, height: 1.5)),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: () async {
                                await ChipScannerService.scanFromVet(context);
                                _loadPatients();
                              },
                              icon: const Icon(Icons.sensors_rounded),
                              label: const Text('Scanner une puce',
                                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _teal,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => _PatientCard(
                            animal: _filtered[i],
                            teal: _teal,
                            onTap: () => _openPatient(_filtered[i]),
                            onLongPress: () => _revoquerPatient(_filtered[i]),
                          ),
                          childCount: _filtered.length,
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

// ─── Carte patient ────────────────────────────────────────────────────────────

// ─── Chip filtre espèce ───────────────────────────────────────────────────────

class _EspeceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _EspeceChip({required this.label, required this.selected,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? color : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? color : const Color(0xFFE4E7E2)),
      ),
      child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : const Color(0xFF1F2A2E))),
    ),
  );
}

// ─── Carte patient ────────────────────────────────────────────────────────────

class _PatientCard extends StatelessWidget {
  final Map<String, dynamic> animal;
  final Color teal;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _PatientCard({required this.animal, required this.teal,
      required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final photo  = animal['photo_url']?.toString() ?? '';
    final nom    = animal['nom']?.toString() ?? 'Animal';
    final espece = animal['espece']?.toString() ?? '';
    final race   = animal['race']?.toString() ?? '';
    final puce   = animal['identification']?.toString() ?? '';
    final dob    = animal['date_naissance']?.toString();

    String age = '';
    if (dob != null) {
      final date = DateTime.tryParse(dob);
      if (date != null) {
        final diff = DateTime.now().difference(date);
        final years = (diff.inDays / 365).floor();
        final months = ((diff.inDays % 365) / 30).floor();
        age = years > 0 ? '$years an${years > 1 ? "s" : ""}' : '$months mois';
      }
    }

    final isPending = animal['grant_status']?.toString() == 'demande';

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: teal.withValues(alpha: 0.10),
            ),
            child: photo.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            Icon(Icons.pets, color: teal, size: 28)))
                : Icon(Icons.pets, color: teal, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nom,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      fontSize: 15, color: Color(0xFF1F2A2E))),
              if (espece.isNotEmpty || race.isNotEmpty)
                Text([espece, race].where((s) => s.isNotEmpty).join(' · '),
                    style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                        color: teal, fontWeight: FontWeight.w600)),
              if (age.isNotEmpty || puce.isNotEmpty)
                Text(
                  [if (age.isNotEmpty) age, if (puce.isNotEmpty) '🔖 $puce'].join('  '),
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
              if (isPending)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('En attente d\'approbation',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 10,
                        fontWeight: FontWeight.w600, color: Colors.amber.shade800)),
                ),
            ]),
          ),
          Icon(isPending ? Icons.schedule_rounded : Icons.chevron_right_rounded,
              color: isPending ? Colors.amber.shade400 : Colors.grey),
        ]),
      ),
    );
  }
}
