import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/data/annonce_objet_categories.dart';
import 'package:PetsMatch/pages/annonces/annonces_objets_feed_page.dart';
import 'package:PetsMatch/pages/eleveur/post/mes_annonces_page.dart';
import 'package:PetsMatch/pages/particulier/create_annonce_objet_page.dart';
import 'package:PetsMatch/widgets/dashboard/dashboard_kit.dart';

const _teal = Color(0xFF0C5C6C);

/// Ancien accès « Mes annonces (matériel) » : ouvre « Mes annonces » filtré
/// sur Matériel & équipements (les deux types sont regroupés sur une page).
class MesAnnoncesObjetsPage extends StatelessWidget {
  const MesAnnoncesObjetsPage({super.key});

  @override
  Widget build(BuildContext context) => MesAnnoncesPage(
        isAssociation: User_Info.activeType == 'association',
        typeInitial: 'materiel',
      );
}

/// Annonces « Matériel & équipements » du profil actif, intégrées à « Mes
/// annonces ». Mêmes données, statuts et actions (modifier, pause / activer,
/// supprimer). [statut] : 'all', 'actives', 'pause', 'terminees'.
class MesAnnoncesObjetsListe extends StatefulWidget {
  final String statut;
  final int refreshKey;
  final ValueChanged<int>? onCompte;
  const MesAnnoncesObjetsListe({super.key, this.statut = 'all', this.refreshKey = 0, this.onCompte});

  @override
  State<MesAnnoncesObjetsListe> createState() => _MesAnnoncesObjetsListeState();
}

class _MesAnnoncesObjetsListeState extends State<MesAnnoncesObjetsListe> {
  final _supa = Supabase.instance.client;
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MesAnnoncesObjetsListe old) {
    super.didUpdateWidget(old);
    if (old.refreshKey != widget.refreshKey) _load();
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
        widget.onCompte?.call(_rows.length);
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

  bool _garde(Map<String, dynamic> r) {
    final s = (r['statut'] ?? 'disponible').toString();
    switch (widget.statut) {
      case 'actives': return s == 'disponible';
      case 'pause': return s == 'pause';
      case 'terminees': return false;
      default: return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _rows.isEmpty) {
      return const Padding(padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator(color: _teal)));
    }
    final liste = _rows.where(_garde).toList();
    if (liste.isEmpty) {
      return DashCarte(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Container(
            width: 44, height: 44,
            decoration: const BoxDecoration(color: Color(0xFFE8F4F6), shape: BoxShape.circle),
            child: const Icon(Icons.inventory_2_outlined, color: _teal, size: 21),
          ),
          const SizedBox(height: 10),
          Text(widget.statut == 'all'
                  ? 'Aucune annonce de matériel ou d\'équipement pour le moment.'
                  : 'Aucune annonce de matériel avec ce statut.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, color: kDashMuted)),
          if (widget.statut == 'all') ...[
            const SizedBox(height: 12),
            DashBoutonPilule(label: 'Publier du matériel', icon: Icons.add, onTap: () => _create()),
          ],
        ]),
      );
    }
    return Column(children: liste.map(_card).toList());
  }

  Widget _card(Map<String, dynamic> r) {
    final photos = List<String>.from(r['photos'] ?? const []);
    final statut = (r['statut'] ?? 'disponible').toString();
    final isPause = statut == 'pause';
    final created = DateTime.tryParse(r['created_at']?.toString() ?? '')?.toLocal();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kDashBorder),
        boxShadow: kDashOmbre,
      ),
      child: Column(children: [
        InkWell(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => AnnonceObjetDetailPage(data: r))),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 60, height: 60,
                  child: photos.isNotEmpty
                      ? CachedNetworkImage(imageUrl: photos.first, fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _ph())
                      : _ph(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((r['titre'] ?? '').toString(),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 15, color: kDashInk)),
                const SizedBox(height: 2),
                Text(annonceObjetCategorieLabel(r['categorie'] as String?),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: kDashMuted)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  isPause
                      ? const DashPuce('En pause', fg: Color(0xFF6B7280), bg: Color(0xFFF3F4F6), point: true)
                      : const DashPuce('En ligne', fg: Color(0xFF2F7D3A), bg: Color(0xFFEAF5EC), point: true),
                  if (_boosted(r)) const DashPuce('Boostée', fg: Color(0xFFB45309), bg: Color(0xFFFEF3C7), icon: Icons.bolt),
                ]),
              ])),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(annonceObjetPrixLabel(r),
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: _teal)),
                if (created != null) ...[
                  const SizedBox(height: 4),
                  Text(DateFormat('dd/MM/yy').format(created),
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: kDashMuted)),
                ],
              ]),
            ]),
          ),
        ),
        Divider(height: 1, color: Colors.grey.shade200),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(children: [
            _act(Icons.edit_outlined, 'Modifier', _teal, () => _create(edit: r)),
            const SizedBox(width: 4),
            _act(isPause ? Icons.play_arrow_outlined : Icons.pause_outlined,
                isPause ? 'Activer' : 'Mettre en pause', const Color(0xFF4B5563), () => _togglePause(r)),
            const Spacer(),
            _act(Icons.delete_outline, 'Supprimer', const Color(0xFFC0392B), () => _delete(r)),
          ]),
        ),
      ]),
    );
  }

  Widget _ph() => Container(
        color: const Color(0xFFE8F4F6),
        child: const Center(child: Icon(Icons.inventory_2_outlined, color: _teal, size: 24)),
      );

  Widget _act(IconData icon, String label, Color color, VoidCallback onTap) => TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: color, visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w600)),
      );
}

/// Accès au fil public depuis la page (gardé pour les anciens appels).
void ouvrirFilMateriel(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const AnnoncesObjetsFeedPage()));
