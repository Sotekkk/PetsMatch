import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/eleveur/post/annonce_detail_page.dart';
import 'package:PetsMatch/pages/particulier/create_annonce_cheval_page.dart';
import 'package:PetsMatch/services/plan_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Mes annonces (particulier) — aujourd'hui uniquement les annonces chevaux
/// (vente / location / demi-pension / pension / valorisation) publiées via
/// [CreateAnnonceChevalPage]. Scopé au profil particulier actif.
class MesAnnoncesParticulierPage extends StatefulWidget {
  const MesAnnoncesParticulierPage({super.key});

  @override
  State<MesAnnoncesParticulierPage> createState() => _MesAnnoncesParticulierPageState();
}

class _MesAnnoncesParticulierPageState extends State<MesAnnoncesParticulierPage> {
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);
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
      // Migration profile_id jouée ? (au moins une annonce particulier avec profile_id)
      final migrated = await _supa.from('annonces').select('id')
          .eq('uid_eleveur', _uid).eq('profil_source', 'particulier')
          .not('profile_id', 'is', null).limit(1);
      var q = _supa.from('annonces').select().eq('profil_source', 'particulier');
      if ((migrated as List).isNotEmpty && pid.isNotEmpty) {
        q = q.eq('profile_id', pid);
      } else {
        q = q.eq('uid_eleveur', _uid);
      }
      final data = await q.order('created_at', ascending: false);
      final rows = (data as List)
          .map((r) => Map<String, dynamic>.from(r))
          .where((r) => (r['statut'] as String?) != 'supprime')
          .toList();
      if (mounted) setState(() { _rows = rows; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreate({Map<String, dynamic>? edit}) async {
    final changed = await Navigator.push(context, MaterialPageRoute(
      builder: (_) => CreateAnnonceChevalPage(
        annonceId: edit?['id'] as String?,
        initialData: edit,
      ),
    ));
    if (changed == true && mounted) _load();
  }

  Future<void> _finaliserSurSite() async {
    final uri = Uri.parse('${PlanService.kWebsiteUrl}/mes-annonces');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _togglePause(Map<String, dynamic> r) async {
    final next = (r['statut'] == 'pause') ? 'disponible' : 'pause';
    try {
      await _supa.from('annonces').update({'statut': next}).eq('id', r['id']);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey'))));
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer l\'annonce',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
        content: const Text('Cette action est irréversible.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler', style: TextStyle(color: Colors.grey, fontFamily: 'Galey'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer',
                  style: TextStyle(color: Colors.redAccent, fontFamily: 'Galey', fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _supa.from('annonces').update({'statut': 'supprime'}).eq('id', r['id']);
      _load();
    } catch (_) {}
  }

  String _prixLabel(Map<String, dynamic> r) {
    final tv = (r['type_vente'] as String?) ?? 'vente';
    final prix = (r['prix'] as num?)?.toDouble();
    final unite = (r['prix_unite'] as String?) ?? 'total';
    if (tv == 'valorisation') return 'Valorisation';
    final suffix = switch (unite) { 'mois' => ' / mois', 'semaine' => ' / sem.', _ => '' };
    final base = prix != null && prix > 0 ? '${prix.toStringAsFixed(0)} €$suffix' : '';
    final label = switch (tv) {
      'location' => 'Location', 'demi_pension' => 'Demi-pension',
      'pension_complete' => 'Pension', _ => '',
    };
    if (base.isEmpty) return label.isEmpty ? 'Prix à convenir' : '$label — à convenir';
    return label.isEmpty ? base : '$label · $base';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Mes annonces',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreate(),
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Annonce cheval',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
      ),
      body: _loading && _rows.isEmpty
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _rows.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.campaign_outlined, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('Aucune annonce',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 16, color: Colors.grey.shade500)),
                  const SizedBox(height: 6),
                  Text('Appuyez sur + pour publier une annonce cheval',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade400)),
                ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: _teal,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: _rows.length,
                    itemBuilder: (_, i) => _card(_rows[i]),
                  ),
                ),
    );
  }

  Widget _card(Map<String, dynamic> r) {
    final photos = List<String>.from(r['photos'] ?? []);
    final titre  = (r['titre'] as String?) ?? '';
    final statut = (r['statut'] as String?) ?? 'disponible';
    final isPause = statut == 'pause';
    final isBrouillon = statut == 'brouillon';
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
          onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => AnnonceDetailPage(annonceId: r['id'] as String, initialData: r))),
          borderRadius: BorderRadius.circular(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16), bottomLeft: Radius.circular(16)),
              child: SizedBox(
                width: 90, height: 108,
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
                  _badge(
                    isBrouillon ? 'Brouillon · à publier'
                        : isPause ? 'En pause' : 'En ligne',
                    isBrouillon ? const Color(0xFFB45309)
                        : isPause ? const Color(0xFF9CA3AF) : _green),
                ]),
                const SizedBox(height: 6),
                Text(titre.isEmpty ? 'Cheval' : titre,
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                        fontSize: 14, color: Color(0xFF1F2A2E)),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Row(children: [
                  Text(_prixLabel(r),
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                          fontSize: 13, color: _teal)),
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
            _act(Icons.edit_outlined, 'Modifier', _teal, () => _openCreate(edit: r)),
            const SizedBox(width: 6),
            if (isBrouillon)
              _act(Icons.open_in_new, 'Finaliser sur le site', const Color(0xFFB45309),
                  _finaliserSurSite)
            else
              _act(isPause ? Icons.play_arrow_outlined : Icons.pause_outlined,
                  isPause ? 'Activer' : 'Pause', isPause ? _green : const Color(0xFF9CA3AF),
                  () => _togglePause(r)),
            const Spacer(),
            _act(Icons.delete_outline, 'Supprimer', Colors.redAccent, () => _delete(r)),
          ]),
        ),
      ]),
    );
  }

  Widget _ph() => Container(
    color: const Color(0xFFEEF5EA),
    child: const Center(child: Text('🐴', style: TextStyle(fontSize: 30))),
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
