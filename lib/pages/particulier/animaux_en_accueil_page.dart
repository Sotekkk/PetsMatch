import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

class AnimauxEnAccueilPage extends StatefulWidget {
  const AnimauxEnAccueilPage({super.key});
  @override
  State<AnimauxEnAccueilPage> createState() => _AnimauxEnAccueilPageState();
}

class _AnimauxEnAccueilPageState extends State<AnimauxEnAccueilPage> {
  final _supa = Supabase.instance.client;
  static const _teal = Color(0xFF0C5C6C);

  List<Map<String, dynamic>> _animaux = [];
  Map<String, dynamic>? _fa;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final profRow = await _supa.from('user_profiles')
          .select('id').eq('uid', uid).eq('is_main', true).maybeSingle();
      final profileId = profRow?['id'] as String?;

      // Trouver la fiche FA liée à cet utilisateur
      final faRows = profileId != null
          ? await _supa.from('familles_accueil')
              .select('id, prenom, nom, association_uid, capacite_max')
              .eq('fa_profile_id', profileId).eq('actif', true).limit(1)
          : await _supa.from('familles_accueil')
              .select('id, prenom, nom, association_uid, capacite_max')
              .eq('fa_uid', uid).eq('actif', true).limit(1);
      if ((faRows as List).isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final fa = Map<String, dynamic>.from(faRows.first);
      // Charger les animaux placés dans cette FA
      final data = await _supa
          .from('animaux')
          .select('id, nom, espece, race, sexe, statut, photo_url, date_entree, date_naissance, description, vaccines, vermifuge, identification, sterilise')
          .eq('fa_id', fa['id'])
          .eq('statut', 'en_fa');
      if (mounted) setState(() {
        _fa = fa;
        _animaux = List<Map<String, dynamic>>.from(data as List);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Animaux en accueil',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _fa == null
              ? const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.house_outlined, size: 60, color: Colors.grey),
                    SizedBox(height: 12),
                    Text('Vous n\'êtes pas famille d\'accueil',
                        style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
                  ]),
                )
              : Column(children: [
                  // Bandeau FA
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _teal,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Famille d\'accueil',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.white70)),
                      Text('${_fa!['prenom'] ?? ''} ${_fa!['nom'] ?? ''}'.trim(),
                          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                              fontSize: 18, color: Colors.white)),
                      const SizedBox(height: 4),
                      Text('${_animaux.length} / ${_fa!['capacite_max'] ?? 1} animaux en accueil',
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.white70)),
                    ]),
                  ),

                  if (_animaux.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.pets_outlined, size: 48, color: Colors.grey),
                          SizedBox(height: 10),
                          Text('Aucun animal en accueil pour l\'instant',
                              style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
                        ]),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        itemCount: _animaux.length,
                        itemBuilder: (_, i) => _AnimalCard(animal: _animaux[i]),
                      ),
                    ),
                ]),
    );
  }
}

class _AnimalCard extends StatelessWidget {
  final Map<String, dynamic> animal;
  const _AnimalCard({required this.animal});

  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  @override
  Widget build(BuildContext context) {
    final photo = animal['photo_url'] as String?;
    final nom = animal['nom'] as String? ?? 'Animal';
    final espece = animal['espece'] as String? ?? '';
    final race = animal['race'] as String? ?? '';
    final sexe = animal['sexe'] as String? ?? '';
    final desc = animal['description'] as String?;
    final dateEntreeRaw = animal['date_entree'];
    final dateEntree = dateEntreeRaw != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(dateEntreeRaw.toString()))
        : null;
    final vaccines = animal['vaccines'] == true;
    final vermifuge = animal['vermifuge'] == true;
    final identification = animal['identification'] == true;
    final sterilise = animal['sterilise'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
      ),
      child: Column(children: [
        // Photo
        if (photo != null)
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: CachedNetworkImage(
              imageUrl: photo,
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          )
        else
          Container(
            height: 100,
            decoration: const BoxDecoration(
              color: Color(0xFFEEF5EA),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: const Center(child: Icon(Icons.pets, size: 48, color: _green)),
          ),

        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(nom,
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
              ),
              if (dateEntree != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _teal.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Depuis $dateEntree',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: _teal)),
                ),
            ]),
            const SizedBox(height: 4),
            Text(
              [espece, race, sexe].where((s) => s.isNotEmpty).join(' · '),
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey),
            ),

            if (desc != null && desc.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(desc,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                  maxLines: 4, overflow: TextOverflow.ellipsis),
            ],

            // Santé
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (vaccines)       _badge('Vacciné(e)', _green),
              if (vermifuge)      _badge('Vermifugé(e)', _green),
              if (identification) _badge('Identifié(e)', _teal),
              if (sterilise)      _badge('Stérilisé(e)', Colors.blueGrey),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(label,
        style: TextStyle(fontFamily: 'Galey', fontSize: 11,
            fontWeight: FontWeight.w600, color: color)),
  );
}
