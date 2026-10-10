import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/eleveur/post/annonce_detail_page.dart';
import 'package:PetsMatch/pages/eleveur/post/mes_annonces_page.dart';
import 'package:PetsMatch/widgets/dashboard/dashboard_kit.dart';
import 'package:PetsMatch/pages/particulier/create_annonce_cheval_page.dart';
import 'package:PetsMatch/services/plan_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Ancien accès « Mes annonces (cheval) » : ouvre « Mes annonces » (animaux
/// et matériel & équipements regroupés), filtré sur les animaux.
class MesAnnoncesParticulierPage extends StatelessWidget {
  const MesAnnoncesParticulierPage({super.key});

  @override
  Widget build(BuildContext context) => const MesAnnoncesPage(typeInitial: 'animaux');
}

/// Annonces chevaux du particulier (vente / location / demi-pension /
/// pension / valorisation) publiées via [CreateAnnonceChevalPage], scopées au
/// profil particulier actif. Intégrées à « Mes annonces ».
/// [statut] : 'all', 'actives', 'pause', 'terminees'.
class MesAnnoncesChevalListe extends StatefulWidget {
  final String statut;
  final int refreshKey;
  final ValueChanged<int>? onCompte;
  const MesAnnoncesChevalListe({super.key, this.statut = 'all', this.refreshKey = 0, this.onCompte});

  @override
  State<MesAnnoncesChevalListe> createState() => _MesAnnoncesChevalListeState();
}

class _MesAnnoncesChevalListeState extends State<MesAnnoncesChevalListe> {
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

  @override
  void didUpdateWidget(MesAnnoncesChevalListe old) {
    super.didUpdateWidget(old);
    if (old.refreshKey != widget.refreshKey) _load();
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
      if (mounted) {
        setState(() { _rows = rows; _loading = false; });
        widget.onCompte?.call(rows.length);
      }
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

  // Paiement in-app interdit : le boost se finalise sur le site (fiche annonce).
  Future<void> _boost(Map<String, dynamic> r) async {
    final id = r['id'] as String?;
    final until = DateTime.tryParse(r['boost_until']?.toString() ?? '');
    final active = until != null && until.isAfter(DateTime.now());
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).padding.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(
                color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 18),
            Row(children: [
              const Icon(Icons.bolt, color: Color(0xFFFF8A00), size: 22),
              const SizedBox(width: 8),
              Text(active ? 'Annonce boostée' : 'Booster mon annonce',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18, color: _teal)),
            ]),
            const SizedBox(height: 8),
            Text(
              active
                  ? 'Votre annonce est mise en avant jusqu\'au '
                      '${DateFormat('dd/MM/yyyy à HH:mm').format(until.toLocal())}. '
                      'Vous pouvez prolonger la mise en avant sur le site.'
                  : 'Un boost place votre annonce en tête des résultats de recherche '
                      'et du fil. Le paiement se fait sur le site, en quelques secondes.',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, color: Color(0xFF41525A), height: 1.4),
            ),
            const SizedBox(height: 18),
            SizedBox(width: double.infinity, child: ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                final uri = Uri.parse('${PlanService.kWebsiteUrl}/annonces/${id ?? ''}');
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(active ? 'Prolonger sur le site' : 'Booster sur le site',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF8A00), foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            )),
            const SizedBox(height: 6),
            Center(child: TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Plus tard',
                  style: TextStyle(fontFamily: 'Galey', color: Color(0xFF9CA3AF))),
            )),
          ]),
        ),
      ),
    );
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

  bool _garde(Map<String, dynamic> r) {
    final s = (r['statut'] as String?) ?? 'disponible';
    switch (widget.statut) {
      case 'actives': return s == 'disponible' || s == 'reserve';
      case 'pause': return s == 'pause';
      case 'terminees': return s == 'vendu' || s == 'cede' || s == 'expiree';
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
            child: const Icon(Icons.pets_outlined, color: _teal, size: 21),
          ),
          const SizedBox(height: 10),
          Text(widget.statut == 'all' ? 'Aucune annonce de cheval pour le moment.' : 'Aucune annonce de cheval avec ce statut.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, color: kDashMuted)),
          if (widget.statut == 'all') ...[
            const SizedBox(height: 12),
            DashBoutonPilule(label: 'Publier une annonce cheval', icon: Icons.add, onTap: () => _openCreate()),
          ],
        ]),
      );
    }
    return Column(children: liste.map(_card).toList());
  }

  Widget _card(Map<String, dynamic> r) {
    final photos = List<String>.from(r['photos'] ?? []);
    final titre  = (r['titre'] as String?) ?? '';
    final statut = (r['statut'] as String?) ?? 'disponible';
    final isPause = statut == 'pause';
    final isBrouillon = statut == 'brouillon';
    final created = DateTime.tryParse(r['created_at']?.toString() ?? '')?.toLocal();
    final boostUntil = DateTime.tryParse(r['boost_until']?.toString() ?? '');
    final isBoosted = boostUntil != null && boostUntil.isAfter(DateTime.now());
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
                  if (isBoosted) _badge('Boostée', const Color(0xFFB45309)),
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
            else ...[
              _act(isPause ? Icons.play_arrow_outlined : Icons.pause_outlined,
                  isPause ? 'Activer' : 'Mettre en pause', isPause ? _green : const Color(0xFF4B5563),
                  () => _togglePause(r)),
              const SizedBox(width: 6),
              _act(Icons.bolt, isBoosted ? 'Boostée' : 'Booster',
                  const Color(0xFFFF8A00), () => _boost(r)),
            ],
            const Spacer(),
            _act(Icons.delete_outline, 'Supprimer', Colors.redAccent, () => _delete(r)),
          ]),
        ),
      ]),
    );
  }

  Widget _ph() => Container(
    color: const Color(0xFFEEF5EA),
    child: const Center(child: Icon(Icons.pets_outlined, color: _teal, size: 26)),
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
