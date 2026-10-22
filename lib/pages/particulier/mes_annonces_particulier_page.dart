import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/eleveur/post/annonce_detail_page.dart';
import 'package:PetsMatch/pages/eleveur/post/mes_annonces_page.dart';
import 'package:PetsMatch/widgets/dashboard/dashboard_kit.dart';
import 'package:PetsMatch/widgets/annonces/gestion_annonces_kit.dart';
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
  /// Texte de la barre de recherche (titre, race, ville).
  final String recherche;
  final int refreshKey;
  final ValueChanged<int>? onCompte;
  const MesAnnoncesChevalListe({super.key, this.statut = 'all', this.recherche = '', this.refreshKey = 0, this.onCompte});

  @override
  State<MesAnnoncesChevalListe> createState() => _MesAnnoncesChevalListeState();
}

class _MesAnnoncesChevalListeState extends State<MesAnnoncesChevalListe> {
  static const _teal  = Color(0xFF0C5C6C);
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

  // Paiement in-app interdit : le boost se finalise sur le site (offres de
  // « Mes annonces », ouvertes directement).
  Future<void> _boost(Map<String, dynamic> r) => ouvrirBoostAnnonce(context,
      annonceId: (r['id'] ?? '').toString(), boostUntil: r['boost_until']?.toString());

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
    final liste = _rows.where(_garde).where((r) => correspondRecherche(widget.recherche,
        [r['titre'] as String?, r['race'] as String?, r['ville_eleveur'] as String?])).toList();
    if (liste.isEmpty) {
      return Column(children: [
        GestionVide(icon: Icons.pets_outlined, texte: widget.recherche.trim().isNotEmpty
            ? 'Aucune annonce de cheval ne correspond à la recherche.'
            : widget.statut == 'all' ? 'Aucune annonce de cheval pour le moment.' : 'Aucune annonce de cheval avec ce statut.'),
        if (widget.statut == 'all' && widget.recherche.trim().isEmpty) ...[
          const SizedBox(height: 12),
          DashBoutonPilule(label: 'Publier une annonce cheval', icon: Icons.add, onTap: () => _openCreate()),
        ],
      ]);
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
    final vues = (r['vues'] as num?)?.toInt() ?? 0;
    final contacts = (r['contacts'] as num?)?.toInt() ?? 0;
    void voir() => Navigator.push(context, MaterialPageRoute(
        builder: (_) => AnnonceDetailPage(annonceId: r['id'] as String, initialData: r)));
    final supprimer = GestionAction('Supprimer', Icons.delete_outline, () => _delete(r), danger: true);
    return GestionCarteAnnonce(
      onTap: voir,
      photo: photos.isNotEmpty
          ? CachedNetworkImage(imageUrl: photos.first, fit: BoxFit.cover, errorWidget: (_, __, ___) => _ph())
          : _ph(),
      titre: titre.isEmpty ? 'Cheval' : titre,
      sousTitre: [r['race'] as String? ?? '', r['ville_eleveur'] as String? ?? ''].where((e) => e.isNotEmpty).join(' · '),
      etiquettes: [
        isBrouillon ? puceStatut('Brouillon · à publier', 'ambre')
            : isPause ? puceStatut('En pause', 'gris') : puceStatut('En ligne', 'vert'),
        if (isBoosted) const DashPuce('Boostée', fg: Color(0xFFB45309), bg: Color(0xFFFEF3C7), icon: Icons.bolt),
      ],
      prix: _prixLabel(r),
      indicateurs: [
        (Icons.visibility_outlined, '$vues vue${vues > 1 ? 's' : ''}'),
        (Icons.chat_bubble_outline, '$contacts contact${contacts > 1 ? 's' : ''}'),
        if (created != null) (Icons.calendar_today_outlined, DateFormat('dd/MM/yy').format(created)),
      ],
      principales: isBrouillon
          ? [
              GestionAction('Finaliser sur le site', Icons.open_in_new, _finaliserSurSite),
              GestionAction('Modifier', Icons.edit_outlined, () => _openCreate(edit: r)),
            ]
          : [
              GestionAction('Voir', Icons.visibility_outlined, voir),
              GestionAction('Modifier', Icons.edit_outlined, () => _openCreate(edit: r)),
            ],
      menu: isBrouillon
          ? [supprimer]
          : [
              GestionAction(isPause ? 'Activer' : 'Mettre en pause',
                  isPause ? Icons.play_arrow_outlined : Icons.pause_outlined, () => _togglePause(r)),
              GestionAction(isBoosted ? 'Prolonger le boost' : 'Booster l\'annonce', Icons.bolt, () => _boost(r), actif: isBoosted),
              supprimer,
            ],
    );
  }

  Widget _ph() => Container(
    color: const Color(0xFFEEF5EA),
    child: const Center(child: Icon(Icons.pets_outlined, color: _teal, size: 26)),
  );
}
