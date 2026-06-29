import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// S05 — Pro view : accès carnet santé d'un animal.
/// Vérifie si le pro a accès, propose de le demander sinon.
class AnimalAccesPage extends StatefulWidget {
  final String animalId;
  final String ownerUid;
  final Color categoryColor;

  const AnimalAccesPage({
    super.key,
    required this.animalId,
    required this.ownerUid,
    required this.categoryColor,
  });

  @override
  State<AnimalAccesPage> createState() => _AnimalAccesPageState();
}

class _AnimalAccesPageState extends State<AnimalAccesPage> {
  static const _teal = Color(0xFF0C5C6C);
  final _supa = Supabase.instance.client;

  bool _loading = true;
  bool _hasAccess = false;
  bool _requesting = false;
  Map<String, dynamic>? _animal;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final proUid = FirebaseAuth.instance.currentUser?.uid;
    if (proUid == null) { setState(() => _loading = false); return; }

    // Récupérer le profile_id du pro
    final proProfile = await _supa.from('user_profiles')
        .select('id').eq('uid', proUid).eq('is_main', true).maybeSingle();
    final proProfileId = proProfile?['id'] as String?;

    try {
      if (proProfileId == null) { setState(() => _loading = false); return; }
      final acces = await _supa.from('animal_access')
          .select()
          .eq('animal_id', widget.animalId)
          .eq('pro_profile_id', proProfileId)
          .eq('statut', 'active')
          .maybeSingle();

      if (acces != null) {
        final animal = await _supa
            .from('animaux')
            .select()
            .eq('id', widget.animalId)
            .maybeSingle();
        if (mounted) setState(() { _hasAccess = true; _animal = animal; _loading = false; });
      } else {
        if (mounted) setState(() { _hasAccess = false; _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestAccess() async {
    final proUid = FirebaseAuth.instance.currentUser?.uid;
    if (proUid == null) return;
    setState(() => _requesting = true);
    try {
      // Profil pro actif
      final proProfile = await _supa.from('user_profiles')
          .select('id').eq('uid', proUid).eq('is_main', true).maybeSingle();
      final proProfileId = proProfile?['id'] as String?;

      // Profil propriétaire depuis animaux_proprietes
      final ownerData = await _supa.from('animaux_proprietes')
          .select('uid_proprio, profile_id_proprio')
          .eq('animal_id', widget.animalId)
          .maybeSingle();
      final ownerProfileId = ownerData?['profile_id_proprio'] as String?;
      final ownerUid = ownerData?['uid_proprio'] as String? ?? widget.ownerUid;

      if (proProfileId == null || ownerProfileId == null) throw Exception('Profils introuvables');
      await _supa.from('animal_access').upsert({
        'animal_id':             widget.animalId,
        'pro_profile_id':        proProfileId,
        'granted_by_profile_id': ownerProfileId,
        'permissions':           ['read_basic', 'write_notes'],
        'statut':                'pending',
      }, onConflict: 'animal_id,pro_profile_id');
      await _check();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: widget.categoryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Carnet de santé',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _hasAccess
              ? _buildCarnet()
              : _buildNoAccess(),
    );
  }

  Widget _buildNoAccess() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded, size: 72, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text('Accès restreint',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20)),
            const SizedBox(height: 8),
            Text(
              'Vous n\'avez pas encore accès au carnet de santé de cet animal.\n'
              'En demandant l\'accès, le propriétaire sera informé.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey.shade600, height: 1.5),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _requesting ? null : _requestAccess,
                icon: _requesting
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.lock_open_outlined),
                label: Text(_requesting ? 'Demande en cours…' : 'Demander l\'accès',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.categoryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCarnet() {
    final a = _animal;
    if (a == null) {
      return const Center(child: Text('Animal introuvable',
          style: TextStyle(fontFamily: 'Galey', color: Colors.grey)));
    }

    final nom     = a['nom']?.toString() ?? 'Animal';
    final espece  = a['espece']?.toString() ?? '';
    final race    = a['race']?.toString() ?? '';
    final sexe    = a['sexe']?.toString() ?? '';
    final dob     = a['date_naissance']?.toString() ?? '';
    final puce    = a['puce']?.toString() ?? '';
    final couleur = a['couleur']?.toString() ?? '';
    final photo   = a['photo_url']?.toString() ?? '';

    DateTime? dobDate = dob.isNotEmpty ? DateTime.tryParse(dob) : null;
    String age = '';
    if (dobDate != null) {
      final diff = DateTime.now().difference(dobDate);
      final years = (diff.inDays / 365).floor();
      final months = ((diff.inDays % 365) / 30).floor();
      age = years > 0 ? '$years an${years > 1 ? 's' : ''}' : '$months mois';
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header animal
        _card(
          child: Row(children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: widget.categoryColor.withValues(alpha: 0.12),
              ),
              child: photo.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(photo, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(Icons.pets, color: widget.categoryColor, size: 36)))
                  : Icon(Icons.pets, color: widget.categoryColor, size: 36),
            ),
            const SizedBox(width: 16),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nom, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20)),
                if (espece.isNotEmpty || race.isNotEmpty)
                  Text('$espece${race.isNotEmpty ? ' · $race' : ''}',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: widget.categoryColor, fontWeight: FontWeight.w600)),
                if (age.isNotEmpty)
                  Text(age, style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500)),
              ],
            )),
          ]),
        ),
        const SizedBox(height: 12),

        // Infos identité
        _card(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Identité'),
            const SizedBox(height: 10),
            if (sexe.isNotEmpty) _infoRow(Icons.transgender, 'Sexe', sexe),
            if (dob.isNotEmpty && dobDate != null)
              _infoRow(Icons.cake_outlined, 'Naissance', '${dobDate.day}/${dobDate.month}/${dobDate.year}'),
            if (couleur.isNotEmpty) _infoRow(Icons.color_lens_outlined, 'Couleur / robe', couleur),
            if (puce.isNotEmpty) _infoRow(Icons.memory_outlined, 'Puce / tatouage', puce),
            if (sexe.isEmpty && dob.isEmpty && couleur.isEmpty && puce.isEmpty)
              Text('Aucune information disponible',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500)),
          ],
        )),
        const SizedBox(height: 12),

        // Accès accordé
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            const Icon(Icons.verified_outlined, color: Color(0xFF388E3C), size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(
              'Accès carnet de santé accordé par le propriétaire.',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF2E7D32)),
            )),
          ]),
        ),
      ],
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1E2025)));

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(icon, size: 16, color: Colors.grey.shade400),
        const SizedBox(width: 8),
        Text('$label : ', style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600)),
        Expanded(child: Text(value, style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade700))),
      ]),
    );
  }
}
