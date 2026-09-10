import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/data/annonce_objet_categories.dart';
import 'package:PetsMatch/pages/chatScreen.dart';
import 'package:PetsMatch/utils/messaging_helper.dart';
import 'package:PetsMatch/pages/particulier/create_annonce_objet_page.dart';

const _teal  = Color(0xFF0C5C6C);
const _green = Color(0xFF6E9E57);
const _orange = Color(0xFFFF8A00);

/// Fil public des petites annonces « objets & matériel » liées aux animaux.
/// Ouvert à tous les profils.
class AnnoncesObjetsFeedPage extends StatefulWidget {
  const AnnoncesObjetsFeedPage({super.key});
  @override
  State<AnnoncesObjetsFeedPage> createState() => _AnnoncesObjetsFeedPageState();
}

class _AnnoncesObjetsFeedPageState extends State<AnnoncesObjetsFeedPage> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String _cat = 'tous';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      var q = _supa.from('annonces_objets').select().eq('statut', 'disponible');
      if (_cat != 'tous') q = q.eq('categorie', _cat);
      final data = await q.order('created_at', ascending: false).limit(120);
      var rows = List<Map<String, dynamic>>.from(data as List);
      rows = [
        ...rows.where((r) => annonceObjetBoostActif(r['boost_until'])),
        ...rows.where((r) => !annonceObjetBoostActif(r['boost_until'])),
      ];
      if (mounted) setState(() { _rows = rows; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F4),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Petites annonces — matériel',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _teal,
        onPressed: () async {
          final ok = await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const CreateAnnonceObjetPage()));
          if (ok == true) _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('Publier', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: Column(children: [
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              _catChip('tous', 'Tout', '🔎'),
              for (final c in kAnnonceObjetCategories) _catChip(c.slug, c.label, c.emoji),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _teal))
              : _rows.isEmpty
                  ? const Center(child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Aucune annonce dans cette catégorie.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: 'Galey', color: Colors.grey))))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12,
                          childAspectRatio: 0.72,
                        ),
                        itemCount: _rows.length,
                        itemBuilder: (_, i) => _card(_rows[i]),
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _catChip(String slug, String label, String emoji) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text('$emoji $label'),
          selected: _cat == slug,
          onSelected: (_) { setState(() => _cat = slug); _load(); },
          selectedColor: _teal.withValues(alpha: 0.15),
          labelStyle: TextStyle(
              fontFamily: 'Galey', fontSize: 12,
              color: _cat == slug ? _teal : Colors.grey.shade700,
              fontWeight: FontWeight.w600),
        ),
      );

  Widget _card(Map<String, dynamic> r) {
    final photos = List<String>.from(r['photos'] ?? const []);
    final boosted = annonceObjetBoostActif(r['boost_until']);
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => AnnonceObjetDetailPage(data: r))),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              child: AspectRatio(
                aspectRatio: 1.1,
                child: photos.isNotEmpty
                    ? CachedNetworkImage(imageUrl: photos.first, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _ph())
                    : _ph(),
              ),
            ),
            if (boosted)
              Positioned(top: 6, left: 6, child: _tag('⚡ Boostée', _orange)),
            Positioned(
              bottom: 6, left: 6,
              child: _tag(annonceObjetCategorieEmoji(r['categorie'] as String?), Colors.black54),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((r['titre'] ?? '').toString(),
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1F2A2E))),
              const SizedBox(height: 4),
              Text(annonceObjetPrixLabel(r),
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: _teal)),
              if ((r['ville'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('📍 ${r['ville']}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _ph() => Container(
        color: const Color(0xFFEEF3F0),
        child: const Center(child: Text('📦', style: TextStyle(fontSize: 34))),
      );

  Widget _tag(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: const TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────

class AnnonceObjetDetailPage extends StatefulWidget {
  final Map<String, dynamic> data;
  const AnnonceObjetDetailPage({super.key, required this.data});
  @override
  State<AnnonceObjetDetailPage> createState() => _AnnonceObjetDetailPageState();
}

class _AnnonceObjetDetailPageState extends State<AnnonceObjetDetailPage> {
  final _supa = Supabase.instance.client;
  int _photo = 0;
  bool _contacting = false;

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  bool get _isOwner {
    final d = widget.data;
    final pid = (d['profile_id'] ?? '').toString();
    return d['uid'] == _myUid &&
        (pid.isEmpty || User_Info.activeProfileId.isEmpty || pid == User_Info.activeProfileId);
  }

  @override
  void initState() {
    super.initState();
    final id = widget.data['id'];
    if (id != null && !_isOwner) {
      _supa.from('annonces_objets').select('vues').eq('id', id).maybeSingle().then((row) {
        if (row != null) {
          _supa.from('annonces_objets')
              .update({'vues': ((row['vues'] as int?) ?? 0) + 1}).eq('id', id);
        }
      }).catchError((_) {});
    }
  }

  Future<void> _contact() async {
    final d = widget.data;
    final ownerUid = d['uid'] as String?;
    if (ownerUid == null || ownerUid.isEmpty) return;
    if (_myUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Connectez-vous pour contacter le vendeur.', style: TextStyle(fontFamily: 'Galey'))));
      return;
    }
    setState(() => _contacting = true);
    _supa.from('annonces_objets').select('contacts').eq('id', d['id']).maybeSingle().then((row) {
      if (row != null) {
        _supa.from('annonces_objets')
            .update({'contacts': ((row['contacts'] as int?) ?? 0) + 1}).eq('id', d['id']);
      }
    }).catchError((_) {});
    try {
      final convId = await MessagingHelper.openOrCreateConversation(
        otherUid: ownerUid,
        categorie: 'annonces-materiel',
        myProfileId: User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null,
      );
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ChatScreen(conversationId: convId, eleveurId: ownerUid),
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _contacting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final photos = List<String>.from(d['photos'] ?? const []);
    final created = DateTime.tryParse(d['created_at']?.toString() ?? '');
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F4),
      appBar: AppBar(
        backgroundColor: _teal, foregroundColor: Colors.white,
        title: Text((d['titre'] ?? 'Annonce').toString(),
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
        actions: [
          if (_isOwner)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final ok = await Navigator.push(context, MaterialPageRoute(
                    builder: (_) => CreateAnnonceObjetPage(
                        annonceId: d['id'] as String?, initialData: d)));
                if (ok == true && mounted) Navigator.pop(context, true);
              },
            ),
        ],
      ),
      body: ListView(children: [
        if (photos.isNotEmpty)
          Column(children: [
            SizedBox(
              height: 280,
              child: PageView.builder(
                itemCount: photos.length,
                onPageChanged: (i) => setState(() => _photo = i),
                itemBuilder: (_, i) => CachedNetworkImage(
                    imageUrl: photos[i], fit: BoxFit.cover, width: double.infinity),
              ),
            ),
            if (photos.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < photos.length; i++)
                    Container(
                      width: i == _photo ? 16 : 6, height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i == _photo ? _teal : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ]),
              ),
          ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              _chip('${annonceObjetCategorieEmoji(d['categorie'] as String?)} '
                  '${annonceObjetCategorieLabel(d['categorie'] as String?)}', _teal),
              _chip(kAnnonceObjetTransactions[d['type_transaction']] ?? 'Vente', _green),
              if (d['etat'] != null)
                _chip(kAnnonceObjetEtats[d['etat']] ?? d['etat'].toString(), Colors.blueGrey),
            ]),
            const SizedBox(height: 12),
            Text((d['titre'] ?? '').toString(),
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 20, color: Color(0xFF1F2A2E))),
            const SizedBox(height: 6),
            Text(annonceObjetPrixLabel(d),
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 18, color: _teal)),
            const SizedBox(height: 12),
            if ((d['description'] ?? '').toString().isNotEmpty)
              Text(d['description'].toString(),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14, height: 1.5, color: Color(0xFF2C3A40))),
            const SizedBox(height: 16),
            Row(children: [
              const Icon(Icons.place_outlined, size: 16, color: Colors.grey),
              const SizedBox(width: 4),
              Text([d['ville'], d['code_postal']].where((s) => (s ?? '').toString().isNotEmpty).join(' · '),
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.person_outline, size: 16, color: Colors.grey),
              const SizedBox(width: 4),
              Text((d['nom_vendeur'] ?? 'Particulier').toString(),
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600)),
              if (created != null) ...[
                const Spacer(),
                Text(DateFormat('dd/MM/yyyy').format(created),
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade400)),
              ],
            ]),
            const SizedBox(height: 24),
            if (!_isOwner)
              SizedBox(
                width: double.infinity, height: 50,
                child: ElevatedButton.icon(
                  onPressed: _contacting ? null : _contact,
                  icon: const Icon(Icons.chat_outlined, size: 18),
                  label: Text(_contacting ? 'Ouverture…' : 'Contacter le vendeur',
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _teal, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: c)),
      );
}
