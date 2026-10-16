// Galeries photo du client : liste des galeries privées que des
// photographes ont partagées sur son compte, et consultation (aperçus en URL
// signées courtes délivrées par le serveur, agrandissement). Aucune galerie
// n'est publique. Sélection et livraison : étape suivante.
// Miroir site : /mes-galeries et /galerie/[id].
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/galeries_api.dart';

const _teal = Color(0xFF0C5C6C);
const _ink = Color(0xFF1F2A2E);

class MesGaleriesPhotoPage extends StatefulWidget {
  const MesGaleriesPhotoPage({super.key});

  @override
  State<MesGaleriesPhotoPage> createState() => _MesGaleriesPhotoPageState();
}

class _MesGaleriesPhotoPageState extends State<MesGaleriesPhotoPage> {
  List<Map<String, dynamic>>? _galeries;
  final Map<String, String> _studios = {};

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final supa = Supabase.instance.client;
    var liste = <Map<String, dynamic>>[];
    try {
      // RLS : seules les galeries partagées sur MON compte sont lisibles.
      liste = List<Map<String, dynamic>>.from(await supa.from('albums_photo')
          .select('id, titre, date_seance, pro_profile_id, client_profile_id')
          .eq('client_uid', uid).eq('partage_client', true).neq('statut', 'archivee')
          .order('updated_at', ascending: false));
      final pid = User_Info.activeProfileId;
      liste = liste.where((g) => pid.isEmpty || g['client_profile_id'] == null || g['client_profile_id'] == pid).toList();
      final ids = liste.map((g) => g['pro_profile_id']?.toString()).whereType<String>().toSet().toList();
      if (ids.isNotEmpty) {
        for (final p in await supa.from('user_profiles_complet').select('id, nom, firstname, lastname').inFilter('id', ids)) {
          final nom = (p['nom']?.toString() ?? '').trim();
          _studios[p['id'].toString()] = nom.isNotEmpty ? nom : '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _galeries = liste);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
          title: const Text('Mes galeries photo', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700))),
      body: _galeries == null
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _galeries!.isEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(
                  'Aucune galerie partagée pour le moment. Votre photographe vous préviendra dès qu\'une galerie sera disponible.',
                  textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade600))))
              : ListView(padding: const EdgeInsets.all(12), children: [
                  for (final g in _galeries!)
                    Card(
                      elevation: 0, margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE6E8E6))),
                      child: ListTile(
                        leading: const Icon(Icons.photo_library_outlined, color: _teal),
                        title: Text(g['titre']?.toString() ?? 'Galerie', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: _ink)),
                        subtitle: Text([
                          if (_studios[g['pro_profile_id']?.toString()] != null) _studios[g['pro_profile_id']?.toString()]!,
                          if (DateTime.tryParse(g['date_seance']?.toString() ?? '') != null)
                            DateFormat('d MMM yyyy', 'fr_FR').format(DateTime.parse(g['date_seance'].toString())),
                        ].join(' · '), style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GalerieClientPage(albumId: g['id'].toString()))),
                      ),
                    ),
                ]),
    );
  }
}

class GalerieClientPage extends StatefulWidget {
  final String albumId;
  const GalerieClientPage({super.key, required this.albumId});

  @override
  State<GalerieClientPage> createState() => _GalerieClientPageState();
}

class _GalerieClientPageState extends State<GalerieClientPage> {
  Map<String, dynamic>? _g;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    GaleriesApi.charger(widget.albumId).then((g) { if (mounted) setState(() => _g = g); })
        .catchError((e) { if (mounted) setState(() => _erreur = e.toString().replaceFirst('Exception: ', '')); });
  }

  @override
  Widget build(BuildContext context) {
    final album = (_g?['album'] as Map?) ?? {};
    final photos = ((_g?['photos'] as List?) ?? []).cast<Map>();
    final studio = (_g?['studio'] as Map?)?['nom']?.toString() ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
          title: Text(album['titre']?.toString() ?? 'Galerie', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700))),
      body: _erreur != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_erreur!, textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Galey', color: Colors.grey))))
          : _g == null
              ? const Center(child: CircularProgressIndicator(color: _teal))
              : CustomScrollView(slivers: [
                  SliverToBoxAdapter(child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text([if (studio.isNotEmpty) studio, '${photos.length} photo${photos.length > 1 ? 's' : ''}'].join(' · '),
                          style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade700)),
                      if ((album['description']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(album['description'].toString(), style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: _ink)),
                      ],
                      const SizedBox(height: 6),
                      Text('Aperçus en qualité réduite. Les fichiers définitifs vous seront remis par votre photographe.',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade500)),
                    ]),
                  )),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4),
                      delegate: SliverChildBuilderDelegate((_, i) => GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _Visionneuse(photos: photos, depart: i))),
                        child: Container(
                          color: const Color(0xFFF0F1EF),
                          child: Image.network(photos[i]['url'].toString(), fit: BoxFit.cover, cacheWidth: 400),
                        ),
                      ), childCount: photos.length),
                    ),
                  ),
                ]),
    );
  }
}

class _Visionneuse extends StatelessWidget {
  final List<Map> photos;
  final int depart;
  const _Visionneuse({required this.photos, required this.depart});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, elevation: 0),
        body: PageView.builder(
          controller: PageController(initialPage: depart),
          itemCount: photos.length,
          itemBuilder: (_, i) => InteractiveViewer(
            maxScale: 4,
            child: Center(child: Image.network(photos[i]['url'].toString(), fit: BoxFit.contain)),
          ),
        ),
      );
}
