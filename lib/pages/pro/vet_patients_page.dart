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
          .select('animal_id, granted_at')
          .eq('vet_id', vetUid)
          .eq('status', 'active')
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

      final grantsMap = <String, String>{
        for (final g in (grants as List))
          if (g['animal_id'] != null) g['animal_id'].toString(): (g['granted_at'] ?? '').toString()
      };

      final list = (animals as List).map((a) {
        final m = Map<String, dynamic>.from(a as Map);
        m['granted_at'] = grantsMap[a['id']?.toString()] ?? '';
        return m;
      }).toList();

      list.sort((a, b) => (b['granted_at'] as String).compareTo(a['granted_at'] as String));

      if (mounted) setState(() { _patients = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.trim().isEmpty) return _patients;
    final q = _search.toLowerCase();
    return _patients.where((p) {
      return (p['nom'] ?? '').toString().toLowerCase().contains(q)
          || (p['espece'] ?? '').toString().toLowerCase().contains(q)
          || (p['race'] ?? '').toString().toLowerCase().contains(q)
          || (p['identification'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openPatient(Map<String, dynamic> animal) async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => AnimalFichePage(
        animalId: animal['id']?.toString(),
        initialData: animal,
        readOnly: true,
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
                    child: Padding(
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
                  ),
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

class _PatientCard extends StatelessWidget {
  final Map<String, dynamic> animal;
  final Color teal;
  final VoidCallback onTap;

  const _PatientCard({required this.animal, required this.teal, required this.onTap});

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

    return GestureDetector(
      onTap: onTap,
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
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: Colors.grey),
        ]),
      ),
    );
  }
}
