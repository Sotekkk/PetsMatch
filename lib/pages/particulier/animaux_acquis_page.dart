import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart';
import 'package:PetsMatch/pages/eleveur/animaux/cession_sheet.dart';

class AnimauxAcquisPage extends StatefulWidget {
  const AnimauxAcquisPage({super.key});
  @override
  State<AnimauxAcquisPage> createState() => _AnimauxAcquisPageState();
}

class _AnimauxAcquisPageState extends State<AnimauxAcquisPage> {
  final _supa = Supabase.instance.client;
  final _uid  = FirebaseAuth.instance.currentUser!.uid;

  static const _teal  = Color(0xFF0C5C6C);
  static const _dark  = Color(0xFF1F2A2E);
  static const _bg    = Color(0xFFF8F8F6);
  static const _green = Color(0xFF6E9E57);

  bool _loading = true;
  List<Map<String, dynamic>> _animaux = [];
  String _nomCedant = '';
  Map<String, String> _cedantNames = {};

  final _espEmoji = <String, String>{
    'chien': '🐕', 'chat': '🐈', 'cheval': '🐴', 'lapin': '🐰',
    'nac': '🦎', 'oiseau': '🦜', 'ovin': '🐑', 'caprin': '🐐', 'porcin': '🐷',
  };

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _supa.from('animaux')
            .select('id, nom, espece, race, sexe, date_naissance, photo_url, uid_eleveur, statut, date_sortie, cession_prix, destinataire_nom')
            .eq('uid_acquereur', _uid)
            .order('date_sortie', ascending: false),
        _supa.from('user_profiles')
            .select('firstname, lastname, nom')
            .eq('uid', _uid)
            .eq('is_main', true)
            .maybeSingle(),
      ]);
      final rows = List<Map<String, dynamic>>.from(results[0] as List);
      final profil = results[1] as Map<String, dynamic>?;
      if (profil != null) {
        final elevage = profil['nom'] as String?;
        final nom = '${profil['firstname'] ?? ''} ${profil['lastname'] ?? ''}'.trim();
        _nomCedant = elevage?.isNotEmpty == true ? elevage! : nom;
      }

      // Batch-fetch noms des cédants (uid_eleveur de chaque animal)
      final cedantUids = rows
          .map((a) => a['uid_eleveur'] as String?)
          .where((u) => u != null && u != _uid)
          .toSet().cast<String>().toList();
      final Map<String, String> names = {};
      if (cedantUids.isNotEmpty) {
        final users = await _supa.from('user_profiles')
            .select('uid, firstname, lastname, nom')
            .inFilter('uid', cedantUids).eq('is_main', true);
        for (final u in (users as List)) {
          final elevage = u['nom'] as String?;
          final nom = '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
          names[u['uid'] as String] = (elevage?.isNotEmpty == true) ? elevage! : nom;
        }
      }
      if (mounted) setState(() { _animaux = rows; _cedantNames = names; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: _dark, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Mes animaux acquis',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18, color: _dark)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : RefreshIndicator(
              onRefresh: _load,
              color: _teal,
              child: _animaux.isEmpty
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Text('🐾', style: TextStyle(fontSize: 56)),
                      const SizedBox(height: 16),
                      Text('Aucun animal acquis',
                          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18, color: _dark)),
                      const SizedBox(height: 8),
                      Text('Les animaux qui vous sont cédés apparaîtront ici.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
                    ]))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _animaux.length,
                      itemBuilder: (_, i) {
                        final animal = _animaux[i];
                        final statut = animal['statut'] as String? ?? '';
                        return _AnimalCard(
                          data: animal,
                          teal: _teal, dark: _dark, green: _green,
                          espEmoji: _espEmoji,
                          canCeder: statut != 'cession_en_cours',
                          cedantNom: _cedantNames[animal['uid_eleveur'] as String?],
                          onTap: () async {
                            await Navigator.push(context, MaterialPageRoute(
                              builder: (_) => AnimalFichePage(
                                animalId: animal['id'] as String,
                                readOnly: false,
                                eleveurUidOverride: animal['uid_eleveur'] as String?,
                              ),
                            ));
                            _load();
                          },
                          onCeder: () => showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => CessionSheet(
                              animal: {
                                'id': animal['id'],
                                'nom': animal['nom'],
                                'espece': animal['espece'],
                                'race': animal['race'],
                                'sexe': animal['sexe'],
                                'identification': null,
                                'date_naissance': animal['date_naissance'],
                              },
                              uid: _uid,
                              nomElevage: _nomCedant,
                              onCeded: _load,
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

class _AnimalCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color teal, dark, green;
  final Map<String, String> espEmoji;
  final VoidCallback onTap;
  final VoidCallback onCeder;
  final bool canCeder;
  final String? cedantNom;

  const _AnimalCard({
    required this.data, required this.teal, required this.dark,
    required this.green, required this.espEmoji, required this.onTap,
    required this.onCeder, required this.canCeder, this.cedantNom,
  });

  @override
  Widget build(BuildContext context) {
    final nom = data['nom'] as String? ?? '—';
    final espece = data['espece'] as String? ?? '';
    final race = data['race'] as String? ?? '';
    final photo = data['photo_url'] as String?;
    final dateStr = data['date_sortie'] as String?;
    final dt = dateStr != null ? DateTime.tryParse(dateStr) : null;
    final emoji = espEmoji[espece] ?? '🐾';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 64, height: 64,
              child: photo != null
                  ? CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover)
                  : Container(
                      color: teal.withOpacity(0.08),
                      child: Center(child: Text(emoji, style: const TextStyle(fontSize: 28)))),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(nom, style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: dark)),
            if (race.isNotEmpty || espece.isNotEmpty)
              Text('$espece${race.isNotEmpty ? ' · $race' : ''}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            if (dt != null)
              Text('Acquis le ${dt.day}/${dt.month}/${dt.year}',
                  style: TextStyle(fontSize: 11, color: green)),
            if (cedantNom != null)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: green.withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
                child: Text('Cédé par $cedantNom', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: green, fontFamily: 'Galey')),
              ),
          ])),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.chevron_right, color: Colors.grey.shade300),
            if (canCeder)
              GestureDetector(
                onTap: onCeder,
                child: Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: teal.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: teal.withOpacity(0.3)),
                  ),
                  child: Text('Céder', style: TextStyle(fontSize: 10, fontFamily: 'Galey',
                      fontWeight: FontWeight.w700, color: teal)),
                ),
              ),
          ]),
        ]),
      ),
    );
  }
}
