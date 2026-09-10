import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/data/annonce_objet_categories.dart';
import 'package:PetsMatch/pages/annonces/annonces_objets_feed_page.dart';
import 'package:PetsMatch/pages/particulier/create_annonce_objet_page.dart';

const _teal  = Color(0xFF0C5C6C);
const _green = Color(0xFF6E9E57);
const _orange = Color(0xFFFF8A00);

/// « Mes annonces (matériel) » — gestion de ses petites annonces objets.
/// Disponible pour tous les profils (particulier, éleveur, association, pro).
class MesAnnoncesObjetsPage extends StatefulWidget {
  const MesAnnoncesObjetsPage({super.key});
  @override
  State<MesAnnoncesObjetsPage> createState() => _MesAnnoncesObjetsPageState();
}

class _MesAnnoncesObjetsPageState extends State<MesAnnoncesObjetsPage> {
  final _supa = Supabase.instance.client;
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_uid == null) { setState(() => _loading = false); return; }
    if (mounted) setState(() => _loading = true);
    try {
      final pid = User_Info.activeProfileId;
      // Scope par profil si des lignes avec profile_id existent pour ce compte.
      final migrated = await _supa.from('annonces_objets').select('id')
          .eq('uid', _uid).not('profile_id', 'is', null).limit(1);
      var q = _supa.from('annonces_objets').select().neq('statut', 'supprime');
      if ((migrated as List).isNotEmpty && pid.isNotEmpty) {
        q = q.eq('profile_id', pid);
      } else {
        q = q.eq('uid', _uid);
      }
      final data = await q.order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _rows = List<Map<String, dynamic>>.from(data as List);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create({Map<String, dynamic>? edit}) async {
    final ok = await Navigator.push(context, MaterialPageRoute(
      builder: (_) => CreateAnnonceObjetPage(
          annonceId: edit?['id'] as String?, initialData: edit),
    ));
    if (ok == true) _load();
  }

  Future<void> _togglePause(Map<String, dynamic> r) async {
    final next = r['statut'] == 'pause' ? 'disponible' : 'pause';
    try {
      await _supa.from('annonces_objets').update({'statut': next}).eq('id', r['id']);
      _load();
    } catch (_) {}
  }

  Future<void> _delete(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer l\'annonce ?', style: TextStyle(fontFamily: 'Galey')),
        content: const Text('Cette action est définitive.', style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _supa.from('annonces_objets').update({'statut': 'supprime'}).eq('id', r['id']);
      _load();
    } catch (_) {}
  }

  bool _boosted(Map<String, dynamic> r) {
    final d = DateTime.tryParse(r['boost_until']?.toString() ?? '');
    return d != null && d.isAfter(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F4),
      appBar: AppBar(
        backgroundColor: _teal, foregroundColor: Colors.white,
        title: const Text('Mes annonces — matériel',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
        actions: [
          IconButton(
            tooltip: 'Voir le fil public',
            icon: const Icon(Icons.travel_explore_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AnnoncesObjetsFeedPage())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _teal,
        onPressed: () => _create(),
        icon: const Icon(Icons.add),
        label: const Text('Publier', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _rows.isEmpty
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('📦', style: TextStyle(fontSize: 44)),
                    const SizedBox(height: 12),
                    const Text('Aucune annonce matériel',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 6),
                    Text('Cage, harnais, foin, location de prairie, matériel agricole… '
                        'Publiez gratuitement. Pas d\'animaux ici.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade500)),
                  ]),
                ))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                    itemCount: _rows.length,
                    itemBuilder: (_, i) => _card(_rows[i]),
                  ),
                ),
    );
  }

  Widget _card(Map<String, dynamic> r) {
    final photos = List<String>.from(r['photos'] ?? const []);
    final statut = (r['statut'] ?? 'disponible').toString();
    final isPause = statut == 'pause';
    final created = DateTime.tryParse(r['created_at']?.toString() ?? '');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => AnnonceObjetDetailPage(data: r))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16), bottomLeft: Radius.circular(16)),
              child: SizedBox(
                width: 92, height: 100,
                child: photos.isNotEmpty
                    ? CachedNetworkImage(imageUrl: photos.first, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _ph())
                    : _ph(),
              ),
            ),
            Expanded(child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 6, runSpacing: 4, children: [
                  _badge(isPause ? 'En pause' : 'En ligne', isPause ? const Color(0xFF9CA3AF) : _green),
                  if (_boosted(r)) _badge('⚡ Boostée', _orange),
                  _badge(annonceObjetCategorieLabel(r['categorie'] as String?), _teal),
                ]),
                const SizedBox(height: 6),
                Text((r['titre'] ?? '').toString(),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1F2A2E))),
                const SizedBox(height: 3),
                Row(children: [
                  Text(annonceObjetPrixLabel(r),
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: _teal)),
                  const Spacer(),
                  if (created != null)
                    Text(DateFormat('dd/MM/yy').format(created),
                        style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade400)),
                ]),
              ]),
            )),
          ]),
        ),
        Divider(height: 1, color: Colors.grey.shade100),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(children: [
            _act(Icons.edit_outlined, 'Modifier', _teal, () => _create(edit: r)),
            const SizedBox(width: 6),
            _act(isPause ? Icons.play_arrow_outlined : Icons.pause_outlined,
                isPause ? 'Activer' : 'Pause',
                isPause ? _green : const Color(0xFF9CA3AF), () => _togglePause(r)),
            const Spacer(),
            _act(Icons.delete_outline, 'Supprimer', Colors.redAccent, () => _delete(r)),
          ]),
        ),
      ]),
    );
  }

  Widget _ph() => Container(
        color: const Color(0xFFEEF3F0),
        child: const Center(child: Text('📦', style: TextStyle(fontSize: 28))),
      );

  Widget _badge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
        child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      );

  Widget _act(IconData icon, String label, Color color, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          ]),
        ),
      );
}
