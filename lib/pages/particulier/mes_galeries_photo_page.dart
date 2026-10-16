// Galeries photo du client : liste des galeries privées que des
// photographes ont partagées sur son compte, et consultation (aperçus en URL
// signées courtes délivrées par le serveur, agrandissement). Aucune galerie
// n'est publique. Sélection (cœurs puis confirmation explicite) et
// téléchargement de la livraison (ZIP temporaires, URL signées 10 min).
// Miroir site : /mes-galeries et /galerie/[id].
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/galeries_api.dart';
import 'package:url_launcher/url_launcher.dart';

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
  bool _vueSelection = false;
  bool _occupe = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    try {
      final g = await GaleriesApi.charger(widget.albumId);
      if (mounted) setState(() => _g = g);
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  List<Map> get _toutes => ((_g?['photos'] as List?) ?? []).cast<Map>();
  Map get _album => (_g?['album'] as Map?) ?? {};
  bool get _client => _g?['role'] == 'client';
  bool get _selectionOuverte => _client && _album['statut'] == 'partagee' && _album['selection_confirmee_le'] == null;
  int get _nbChoisies => _toutes.where((p) => p['selectionnee'] == true).length;

  void _snack(String t) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t, style: const TextStyle(fontFamily: 'Galey'))));
  }

  Future<void> _basculer(Map p) async {
    final choisie = p['selectionnee'] != true;
    setState(() => p['selectionnee'] = choisie);
    try {
      await GaleriesApi.choisir(widget.albumId, p['id'].toString(), choisie);
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
      _charger();
    }
  }

  Future<void> _confirmer() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Confirmer ma sélection', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Vous avez choisi $_nbChoisies photo${_nbChoisies > 1 ? 's' : ''}. Une fois confirmée, la sélection est transmise à votre photographe et ne peut plus être modifiée.',
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
        const SizedBox(height: 10),
        TextField(controller: ctrl, maxLines: 3, decoration: const InputDecoration(hintText: 'Un message pour votre photographe (facultatif)',
            border: OutlineInputBorder())),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Revenir')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: _teal), child: const Text('Confirmer')),
      ],
    ));
    if (ok != true) return;
    setState(() => _occupe = true);
    try {
      await GaleriesApi.confirmerSelection(widget.albumId, ctrl.text.trim());
      _snack('Sélection envoyée à votre photographe');
      await _charger();
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
    if (mounted) setState(() => _occupe = false);
  }

  Future<void> _telecharger() async {
    setState(() => _occupe = true);
    try {
      final liens = await GaleriesApi.liensLivraison(widget.albumId);
      for (final l in liens) {
        await launchUrl(Uri.parse(l['url'].toString()), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
    if (mounted) setState(() => _occupe = false);
  }

  String _supplement(int incluses, double? prix) {
    final n = _nbChoisies - incluses;
    if (prix == null || prix <= 0) return ' Les photos supplémentaires sont facturées selon le tarif de votre photographe.';
    return ' $n photo${n > 1 ? 's' : ''} supplémentaire${n > 1 ? 's' : ''} × ${prix.toStringAsFixed(0)} € = ${(n * prix).toStringAsFixed(0)} € en plus du forfait.';
  }

  Widget _bloc(List<Widget> enfants) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE6E8E6))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: enfants),
      );

  @override
  Widget build(BuildContext context) {
    final album = _album;
    final photos = _vueSelection ? _toutes.where((p) => p['selectionnee'] == true).toList() : _toutes;
    final studio = (_g?['studio'] as Map?)?['nom']?.toString() ?? '';
    final livraison = ((_g?['livraison'] as List?) ?? []).cast<Map>();
    final incluses = (album['nb_photos_incluses'] as num?)?.toInt();
    final nbLivres = livraison.fold<int>(0, (n, l) => n + ((l['nb'] as num?)?.toInt() ?? 0));
    final tailleLivree = livraison.fold<num>(0, (n, l) => n + ((l['taille'] as num?) ?? 0));
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
          title: Text(album['titre']?.toString() ?? 'Galerie', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700))),
      bottomNavigationBar: _selectionOuverte && _nbChoisies > 0
          ? SafeArea(child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton(
                onPressed: _occupe ? null : _confirmer,
                style: FilledButton.styleFrom(backgroundColor: _teal, padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text('Confirmer ma sélection ($_nbChoisies)', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              ),
            ))
          : null,
      body: _erreur != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_erreur!, textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Galey', color: Colors.grey))))
          : _g == null
              ? const Center(child: CircularProgressIndicator(color: _teal))
              : RefreshIndicator(
                  onRefresh: _charger, color: _teal,
                  child: CustomScrollView(slivers: [
                    SliverToBoxAdapter(child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text([if (studio.isNotEmpty) studio, '${_toutes.length} photo${_toutes.length > 1 ? 's' : ''}'].join(' · '),
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
                    if (livraison.isNotEmpty)
                      SliverToBoxAdapter(child: _bloc([
                        const Text('Vos photos finales sont prêtes', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _ink)),
                        Text([
                          if (nbLivres > 0) '$nbLivres fichier${nbLivres > 1 ? 's' : ''}',
                          GaleriesApi.taille(tailleLivree),
                          livraison.length > 1 ? '${livraison.length} archives ZIP' : 'archive ZIP',
                        ].where((x) => x.isNotEmpty).join(' · '), style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade700)),
                        Text('Disponibles jusqu\'au ${DateFormat('dd/MM/yyyy').format(DateTime.parse(livraison.first['expire_le'].toString()).toLocal())}, puis supprimées : pensez à les enregistrer.',
                            style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFFB3261E))),
                        const SizedBox(height: 8),
                        FilledButton.icon(onPressed: _occupe ? null : _telecharger, style: FilledButton.styleFrom(backgroundColor: _teal),
                            icon: const Icon(Icons.download_outlined, size: 18),
                            label: const Text('Télécharger', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700))),
                      ])),
                    if (_client && (_selectionOuverte || album['selection_confirmee_le'] != null))
                      SliverToBoxAdapter(child: _bloc([
                        if (album['selection_confirmee_le'] != null) ...[
                          Text('Sélection envoyée le ${DateFormat('dd/MM/yyyy').format(DateTime.parse(album['selection_confirmee_le'].toString()).toLocal())}',
                              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _ink)),
                          Text('$_nbChoisies photo${_nbChoisies > 1 ? 's' : ''} choisie${_nbChoisies > 1 ? 's' : ''}. Votre photographe prépare vos fichiers.',
                              style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade700)),
                        ] else ...[
                          const Text('Choisissez vos photos', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _ink)),
                          Text('Touchez le cœur sur chaque photo. $_nbChoisies sélectionnée${_nbChoisies > 1 ? 's' : ''}'
                              '${incluses != null ? ' sur $incluses incluse${incluses > 1 ? 's' : ''} dans votre prestation' : ''}.'
                              '${incluses != null && _nbChoisies > incluses ? _supplement(incluses, (album['prix_photo_supp'] as num?)?.toDouble()) : ''}',
                              style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade700)),
                        ],
                        if (_nbChoisies > 0)
                          TextButton(onPressed: () => setState(() => _vueSelection = !_vueSelection), style: TextButton.styleFrom(padding: EdgeInsets.zero),
                              child: Text(_vueSelection ? 'Toutes les photos' : 'Voir ma sélection', style: const TextStyle(fontFamily: 'Galey', color: _teal))),
                      ])),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4),
                        delegate: SliverChildBuilderDelegate((_, i) {
                          final p = photos[i];
                          final choisie = p['selectionnee'] == true;
                          return Stack(children: [
                            Positioned.fill(child: GestureDetector(
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _Visionneuse(photos: photos, depart: i))),
                              child: Container(
                                decoration: BoxDecoration(color: const Color(0xFFF0F1EF),
                                    border: choisie && _client ? Border.all(color: _teal, width: 3) : null),
                                child: Image.network(p['url'].toString(), fit: BoxFit.cover, cacheWidth: 400),
                              ),
                            )),
                            if (_selectionOuverte)
                              Positioned(right: 4, top: 4, child: GestureDetector(
                                onTap: () => _basculer(p),
                                child: CircleAvatar(radius: 15, backgroundColor: choisie ? _teal : Colors.black38,
                                    child: Icon(choisie ? Icons.favorite : Icons.favorite_border, size: 16, color: Colors.white)),
                              ))
                            else if (choisie && _client)
                              const Positioned(right: 4, top: 4, child: CircleAvatar(radius: 11, backgroundColor: _teal,
                                  child: Icon(Icons.favorite, size: 12, color: Colors.white))),
                          ]);
                        }, childCount: photos.length),
                      ),
                    ),
                  ]),
                ),
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
