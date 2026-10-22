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
import 'package:PetsMatch/widgets/annonces/gestion_annonces_kit.dart';

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
  /// Texte de la barre de recherche (titre, catégorie).
  final String recherche;
  final int refreshKey;
  final ValueChanged<int>? onCompte;
  const MesAnnoncesObjetsListe({super.key, this.statut = 'all', this.recherche = '', this.refreshKey = 0, this.onCompte});

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
    final liste = _rows.where(_garde).where((r) => correspondRecherche(widget.recherche,
        [r['titre']?.toString(), annonceObjetCategorieLabel(r['categorie'] as String?)])).toList();
    if (liste.isEmpty) {
      // Aucune annonce du tout : « Aucune annonce » est affiché par la rubrique.
      if (_rows.isEmpty) return const SizedBox.shrink();
      // Pas de bouton ici : « Publier une annonce » (bouton principal de
      // Mes annonces) propose déjà « Matériel & équipements ».
      return GestionVide(icon: Icons.inventory_2_outlined,
          texte: widget.recherche.trim().isNotEmpty ? 'Aucune annonce de matériel ne correspond à la recherche.'
              : 'Aucune annonce de matériel avec ce statut.');
    }
    return Column(children: liste.map(_card).toList());
  }

  Widget _card(Map<String, dynamic> r) {
    final photos = List<String>.from(r['photos'] ?? const []);
    final statut = (r['statut'] ?? 'disponible').toString();
    final isPause = statut == 'pause';
    // Boost choisi à la publication, paiement pas encore confirmé : pas en ligne.
    final enAttente = statut == 'attente_boost';
    final booste = _boosted(r);
    final created = DateTime.tryParse(r['created_at']?.toString() ?? '')?.toLocal();
    final vues = (r['vues'] as num?)?.toInt() ?? 0;
    final contacts = (r['contacts'] as num?)?.toInt() ?? 0;
    void voir() => Navigator.push(context,
        MaterialPageRoute(builder: (_) => AnnonceObjetDetailPage(data: r)));
    return GestionCarteAnnonce(
      onTap: voir,
      photo: photos.isNotEmpty
          ? CachedNetworkImage(imageUrl: photos.first, fit: BoxFit.cover, errorWidget: (_, __, ___) => _ph())
          : _ph(),
      titre: (r['titre'] ?? '').toString(),
      sousTitre: annonceObjetCategorieLabel(r['categorie'] as String?),
      etiquettes: [
        enAttente ? puceStatut('En attente de paiement', 'ambre')
            : isPause ? puceStatut('En pause', 'gris') : puceStatut('En ligne', 'vert'),
        if (booste) const DashPuce('Boostée', fg: Color(0xFFB45309), bg: Color(0xFFFEF3C7), icon: Icons.bolt),
      ],
      prix: annonceObjetPrixLabel(r),
      indicateurs: [
        (Icons.visibility_outlined, '$vues vue${vues > 1 ? 's' : ''}'),
        (Icons.chat_bubble_outline, '$contacts contact${contacts > 1 ? 's' : ''}'),
        if (created != null) (Icons.calendar_today_outlined, DateFormat('dd/MM/yy').format(created)),
      ],
      principales: enAttente
          ? [GestionAction('Reprendre la publication', Icons.edit_outlined, () => _create(edit: r))]
          : [
              GestionAction('Voir', Icons.visibility_outlined, voir),
              GestionAction('Modifier', Icons.edit_outlined, () => _create(edit: r)),
            ],
      menu: enAttente ? [
        GestionAction('Supprimer', Icons.delete_outline, () => _delete(r), danger: true),
      ] : [
        GestionAction(booste ? 'Prolonger le boost' : 'Booster l\'annonce', Icons.bolt,
            () => ouvrirBoostAnnonce(context, annonceId: (r['id'] ?? '').toString(),
                boostUntil: r['boost_until']?.toString(), materiel: true),
            actif: booste),
        GestionAction(isPause ? 'Activer' : 'Mettre en pause',
            isPause ? Icons.play_arrow_outlined : Icons.pause_outlined, () => _togglePause(r)),
        GestionAction('Supprimer', Icons.delete_outline, () => _delete(r), danger: true),
      ],
    );
  }

  Widget _ph() => Container(
        color: const Color(0xFFE8F4F6),
        child: const Center(child: Icon(Icons.inventory_2_outlined, color: _teal, size: 24)),
      );
}

/// Accès au fil public depuis la page (gardé pour les anciens appels).
void ouvrirFilMateriel(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const AnnoncesObjetsFeedPage()));
