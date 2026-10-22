import 'package:PetsMatch/services/annonce_paiement.dart';
import 'package:PetsMatch/pages/association/post/create_annonce_asso_page.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/eleveur/abonnement_page.dart';
import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart';
import 'package:PetsMatch/pages/eleveur/post/annonce_detail_page.dart';
import 'package:PetsMatch/pages/eleveur/post/create_annonce_page.dart';
import 'package:PetsMatch/pages/eleveur/post/mes_achats_page.dart';
import 'package:PetsMatch/services/plan_service.dart';
import 'package:PetsMatch/pages/annonces/mes_annonces_objets_page.dart';
import 'package:PetsMatch/pages/annonces/publier_annonce_page.dart';
import 'package:PetsMatch/pages/particulier/mes_annonces_particulier_page.dart';
import 'package:PetsMatch/utils/annonces_droits.dart';
import 'package:PetsMatch/widgets/dashboard/dashboard_kit.dart';
import 'package:PetsMatch/widgets/annonces/gestion_annonces_kit.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// Réutilisée depuis la carte annonce ET depuis le tap sur une notification
// d'expiration (voir notifications_page.dart) — évite de dupliquer la
// logique de renouvellement (+30 jours à partir de maintenant).
/// Renouvellement payant (4,99 €, +30 jours) : paiement sur le site, le
/// webhook prolonge l'annonce. true = page de paiement ouverte.
Future<bool> renewAnnonceListing(BuildContext context, String annonceId) =>
    renouvelerAnnoncePayant(context, table: 'annonces', id: annonceId);

/// « Mes annonces » : annonces d'animaux ET de matériel & équipements du
/// profil actif sur une même page, avec un filtre de type (Toutes / Animaux /
/// Matériel & équipements) et un filtre de statut. Chaque type garde ses
/// données, statuts et actions.
class MesAnnoncesPage extends StatefulWidget {
  final bool isAssociation;
  /// 'toutes', 'animaux' ou 'materiel'.
  final String typeInitial;
  const MesAnnoncesPage({super.key, this.isAssociation = false, this.typeInitial = 'toutes'});
  @override
  State<MesAnnoncesPage> createState() => _MesAnnoncesPageState();
}

class _MesAnnoncesPageState extends State<MesAnnoncesPage> {
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  int _refreshKey = 0;

  // uid Firebase RÉEL du propriétaire de l'élevage actif — jamais forcément
  // _uid : un cogérant (elevage_cogerants) a un uid différent du gérant,
  // mais la ligne user_profiles du profil emprunté (activeProfileId) reste
  // celle du gérant. Sans ça, "Mes annonces" et le quota du forfait
  // resteraient scopés sur le compte personnel du cogérant.
  String? _ownerUid;

  Future<void> _resolveOwnerUid() async {
    final pid = User_Info.activeProfileId;
    if (pid.isEmpty || _uid == null) { setState(() => _ownerUid = _uid); return; }
    try {
      final row = await Supabase.instance.client
          .from('user_profiles_complet').select('uid').eq('id', pid).maybeSingle();
      if (mounted) setState(() => _ownerUid = (row?['uid'] as String?) ?? _uid);
    } catch (_) {
      if (mounted) setState(() => _ownerUid = _uid);
    }
  }

  String _planCode    = 'free';
  int    _activeCount = 0;
  bool   _planLoading = true;
  PlanConfig? _planConfig;

  static const _teal  = Color(0xFF0C5C6C);

  late String _type = widget.typeInitial;
  String _statut = 'all';
  int? _nbAnimaux;
  int? _nbMateriel;
  String _recherche = '';

  /// Annonces d'animaux du profil : éleveur / association (liste et quota
  /// d'origine), particulier (chevaux), aucune pour un profil pro.
  late final String _animaux = widget.isAssociation ? 'association' : typeAnimauxProfilActif();

  @override
  void initState() {
    super.initState();
    if (_animaux == 'eleveur' || _animaux == 'association') {
      _resolveOwnerUid().then((_) => _loadPlan());
    } else {
      _planLoading = false;
    }
  }

  void _rafraichir() {
    if (!mounted) return;
    setState(() => _refreshKey++);
    if (_animaux == 'eleveur' || _animaux == 'association') _loadPlan();
  }

  Future<void> _publier() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const PublierAnnoncePage()));
    _rafraichir();
  }

  Future<void> _loadPlan() async {
    final ownerUid = _ownerUid ?? _uid;
    if (ownerUid == null) { setState(() => _planLoading = false); return; }
    final results = await Future.wait([
      PlanService.getPlanCode(ownerUid),
      PlanService.countActiveAnnonces(ownerUid),
    ]);
    if (!mounted) return;
    // Associations : annonces illimitées (le plan du compte est celui de
    // l'élevage quand un même compte a les deux profils → « limite atteinte »
    // affichée à tort côté association).
    final planCode = widget.isAssociation ? 'association' : results[0] as String;
    final config = widget.isAssociation
        ? const PlanConfig(code: 'association', label: 'Association', maxAnnonces: -1,
            dureeDays: 30, hasRegistres: true, badge: '')
        : await PlanService.getConfig(planCode);
    if (!mounted) return;
    setState(() {
      _planCode    = planCode;
      _activeCount = results[1] as int;
      _planConfig  = config;
      _planLoading = false;
    });
  }

  void _showQuotaSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuotaSheet(
        onBuyExtra: () async {
          Navigator.pop(context);
          final uri = Uri.parse('${PlanService.kWebsiteUrl}/abonnement?buy=annonce_sup');
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        onUpgradePro: () {
          Navigator.pop(context);
          Navigator.push(context, MaterialPageRoute(builder: (_) => const AbonnementPage()));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config    = _planConfig ?? const PlanConfig(
        code: 'free', label: 'Gratuit', maxAnnonces: 0, dureeDays: 30,
        hasRegistres: false, badge: '');
    final aAnimaux = _animaux != 'aucun';
    final voirAnimaux = _type == 'animaux' || (_type == 'toutes' && aAnimaux);
    final voirMateriel = _type != 'animaux';
    final quota = (_animaux == 'eleveur' || _animaux == 'association') && voirAnimaux && !_planLoading;
    final total = (aAnimaux ? (_nbAnimaux ?? 0) : 0) + (_nbMateriel ?? 0);

    return Scaffold(
      backgroundColor: kDashFond,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        surfaceTintColor: _teal,
        title: const Text('Mes annonces',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Mes achats',
            icon: const Icon(Icons.shopping_cart_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => MesAchatsPage(
                    abonnement: !widget.isAssociation && User_Info.isElevage ? const AbonnementPage() : null))),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: _teal,
        onRefresh: () async => _rafraichir(),
        child: ListView(
          padding: EdgeInsets.fromLTRB(dashMargeLaterale(context), 14, dashMargeLaterale(context), 100),
          children: [
            GestionEntete(total: total, onPublier: _publier),
            const SizedBox(height: 14),

            // ── Quota (annonces d'animaux, éleveur / association) ────────────
            if (quota) ...[
              GestionBandeauQuota(
                actives: _activeCount, max: config.maxAnnonces, formule: config.label,
                changerFormule: _planCode == 'free',
                onGerer: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AbonnementPage())),
              ),
              const SizedBox(height: 12),
            ],

            // ── Recherche et filtres ─────────────────────────────────────────
            GestionRecherche(onChanged: (v) => setState(() => _recherche = v)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _Liste(
                libelle: 'Type', valeur: _type,
                options: kFiltresTypeAnnonces,
                onChanged: (v) => setState(() => _type = v),
              )),
              const SizedBox(width: 10),
              Expanded(child: _Liste(
                libelle: 'Statut', valeur: _statut,
                options: const [('all', 'Tous'), ('actives', 'En ligne'), ('pause', 'En pause'), ('terminees', 'Terminées')],
                onChanged: (v) => setState(() => _statut = v),
              )),
            ]),
            const SizedBox(height: 16),

            // ── Animaux ──────────────────────────────────────────────────────
            if (voirAnimaux)
              if (!aAnimaux)
                const GestionVide(icon: Icons.pets_outlined,
                    texte: 'Les annonces d\'animaux ne sont pas proposées pour ce profil. '
                        'Vous pouvez publier du matériel et des équipements.')
              else
                GestionRubrique(
                  titre: widget.isAssociation ? 'Animaux à l\'adoption' : 'Animaux',
                  icon: Icons.pets_outlined,
                  nombre: _nbAnimaux,
                  child: _animaux == 'particulier'
                      ? MesAnnoncesChevalListe(statut: _statut, recherche: _recherche, refreshKey: _refreshKey,
                          onCompte: (n) { if (mounted && n != _nbAnimaux) setState(() => _nbAnimaux = n); })
                      : _AnnoncesList(uid: _ownerUid ?? _uid, filter: _statut, recherche: _recherche, refreshKey: _refreshKey,
                          isAssociation: widget.isAssociation, embedded: true,
                          onCompte: (n) { if (mounted && n != _nbAnimaux) setState(() => _nbAnimaux = n); }),
                ),

            // ── Matériel & équipements ───────────────────────────────────────
            if (voirMateriel)
              GestionRubrique(
                titre: 'Matériel & équipements',
                icon: Icons.inventory_2_outlined,
                nombre: _nbMateriel,
                child: MesAnnoncesObjetsListe(statut: _statut, recherche: _recherche, refreshKey: _refreshKey,
                    onCompte: (n) { if (mounted && n != _nbMateriel) setState(() => _nbMateriel = n); }),
              ),
          ],
        ),
      ),
    );
  }
}

/// Liste déroulante compacte (filtre).
class _Liste extends StatelessWidget {
  final String libelle;
  final String valeur;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;
  const _Liste({required this.libelle, required this.valeur, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        initialValue: valeur,
        isExpanded: true,
        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: kDashMuted),
        style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: kDashInk),
        decoration: InputDecoration(
          labelText: libelle,
          labelStyle: const TextStyle(fontFamily: 'Galey', color: kDashMuted),
          isDense: true,
          filled: true, fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kDashBorder)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kDashBorder)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _MesAnnoncesPageState._teal)),
        ),
        items: [for (final o in options) DropdownMenuItem(value: o.$1, child: Text(o.$2, overflow: TextOverflow.ellipsis))],
        onChanged: (v) { if (v != null) onChanged(v); },
      );
}

// ── Quota bottom sheet ───────────────────────────────────────────────────────

class _QuotaSheet extends StatelessWidget {
  final Future<void> Function() onBuyExtra;
  final VoidCallback onUpgradePro;

  const _QuotaSheet({required this.onBuyExtra, required this.onUpgradePro});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 24, 20, MediaQuery.of(context).viewInsets.bottom + 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
            child: Icon(Icons.block_outlined, color: Colors.red.shade400, size: 26),
          ),
          const SizedBox(height: 12),
          const Text('Quota atteint',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                  fontSize: 20, color: Color(0xFF1F2A2E))),
          const SizedBox(height: 8),
          const Text('Vous avez atteint la limite d\'annonces de votre plan actuel.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF6F767B))),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onBuyExtra,
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: const Text('Annonce supplémentaire — 2,99 €',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6E9E57),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onUpgradePro,
              icon: const Icon(Icons.workspace_premium_outlined, size: 18),
              label: const Text('Passer au plan Pro',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0C5C6C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler',
                style: TextStyle(fontFamily: 'Galey', color: Color(0xFF9CA3AF))),
          ),
        ],
      ),
    );
  }
}

// ─── Liste filtrée ────────────────────────────────────────────────────────────

class _AnnoncesList extends StatefulWidget {
  final String? uid;
  final String filter;
  /// Texte de la barre de recherche (titre, espèce, race, ville).
  final String recherche;
  final int refreshKey;
  final bool isAssociation;
  /// Intégrée à la page « Mes annonces » (pas de défilement propre).
  final bool embedded;
  final ValueChanged<int>? onCompte;
  const _AnnoncesList({required this.uid, required this.filter, this.recherche = '', required this.refreshKey,
      this.isAssociation = false, this.embedded = false, this.onCompte});

  @override
  State<_AnnoncesList> createState() => _AnnoncesListState();
}

class _AnnoncesListState extends State<_AnnoncesList> {
  static const _teal = Color(0xFF0C5C6C);

  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  static Timestamp? _ts(dynamic v) {
    if (v == null) return null;
    try { return Timestamp.fromDate(DateTime.parse(v.toString())); } catch (_) { return null; }
  }

  static Map<String, dynamic> _norm(Map<String, dynamic> row) => {
    ...row,
    'uidEleveur':    row['uid_eleveur'],
    'typeVente':     row['type_vente'],
    'prixMinPortee': row['prix_min_portee'],
    'prixMaxPortee': row['prix_max_portee'],
    'sailliePrix':   row['saillie_prix'],
    'animauxPortee': row['animaux_portee'] ?? [],
    'nombreBebes':   row['nombre_bebes'],
    'createdAt':     _ts(row['created_at']),
    'expiresAt':     _ts(row['expires_at']),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_AnnoncesList old) {
    super.didUpdateWidget(old);
    if (old.refreshKey != widget.refreshKey || old.filter != widget.filter || old.uid != widget.uid) _load();
  }

  Future<void> _load() async {
    if (widget.uid == null) return;
    if (mounted) setState(() => _loading = true);
    try {
      final activeProfileId = User_Info.activeProfileId;
      // Vérifie si la migration profile_id a été jouée (au moins une annonce avec profile_id)
      final checkMigration = await Supabase.instance.client
          .from('annonces').select('id')
          .eq('uid_eleveur', widget.uid!)
          .not('profile_id', 'is', null).limit(1);
      var query = Supabase.instance.client.from('annonces').select();
      if ((checkMigration as List).isNotEmpty && activeProfileId.isNotEmpty) {
        // Migration faite → filtre strict par profil actif
        query = query.eq('profile_id', activeProfileId);
      } else {
        // Fallback pré-migration → filtre par uid + profil_source
        query = query.eq('uid_eleveur', widget.uid!);
        if (widget.isAssociation) {
          query = query.eq('profil_source', 'association');
        } else {
          query = query.neq('profil_source', 'association');
        }
      }
      final data = await query.order('created_at', ascending: false);
      if (!mounted) return;
      var rows = (data as List).map((r) => _norm(Map<String, dynamic>.from(r))).toList();
      widget.onCompte?.call(rows.where((d) => (d['statut'] as String?) != 'supprime').length);
      rows = rows.where((d) {
        final s = (d['statut'] as String?) ?? '';
        switch (widget.filter) {
          case 'actives':   return s == 'disponible' || s == 'reserve';
          case 'pause':     return s == 'pause';
          case 'terminees': return s == 'vendu' || s == 'cede' || s == 'expiree';
          default:          return s != 'supprime';
        }
      }).toList();
      setState(() { _rows = rows; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.uid == null) return const Center(child: Text('Non connecté'));
    if (_loading && _rows.isEmpty) {
      return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: _teal)));
    }
    if (widget.embedded) {
      final liste = _rows.where((r) => correspondRecherche(widget.recherche,
          [r['titre'] as String?, r['espece'] as String?, r['race'] as String?, r['ville_eleveur'] as String?])).toList();
      if (liste.isEmpty) {
        return GestionVide(icon: Icons.pets_outlined, texte:
            widget.recherche.trim().isNotEmpty ? 'Aucune annonce d\'animal ne correspond à la recherche.'
                : widget.filter == 'pause' ? 'Aucune annonce d\'animal en pause.'
                : widget.filter == 'terminees' ? 'Aucune annonce d\'animal terminée.'
                : widget.filter == 'actives' ? 'Aucune annonce d\'animal en ligne.'
                : 'Aucune annonce d\'animal pour le moment.');
      }
      return Column(children: [
        for (final r in liste)
          _AnnonceCard(id: r['id'] as String, data: r, onRefresh: _load, isAssociation: widget.isAssociation),
      ]);
    }
    if (_rows.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.campaign_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            widget.filter == 'pause' ? 'Aucune annonce en pause'
                : widget.filter == 'terminees' ? 'Aucune annonce terminée'
                : 'Aucune annonce',
            style: TextStyle(fontFamily: 'Galey', fontSize: 16, color: Colors.grey.shade500)),
          const SizedBox(height: 6),
          if (widget.filter == 'all' || widget.filter == 'actives')
            Text('Appuyez sur + pour créer votre première annonce',
                style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade400),
                textAlign: TextAlign.center),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: _teal,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: _rows.length,
        itemBuilder: (context, i) => _AnnonceCard(
            id: _rows[i]['id'] as String, data: _rows[i], onRefresh: _load, isAssociation: widget.isAssociation),
      ),
    );
  }
}

// ─── Card annonce avec stats + actions ───────────────────────────────────────

class _AnnonceCard extends StatefulWidget {
  final String id;
  final Map<String, dynamic> data;
  final VoidCallback onRefresh;
  final bool isAssociation;
  const _AnnonceCard({required this.id, required this.data, required this.onRefresh, this.isAssociation = false});
  @override
  State<_AnnonceCard> createState() => _AnnonceCardState();
}

class _AnnonceCardState extends State<_AnnonceCard> {
  late String _statut;

  @override
  void initState() {
    super.initState();
    _statut = (widget.data['statut'] as String?) ?? 'disponible';
  }

  @override
  void didUpdateWidget(_AnnonceCard old) {
    super.didUpdateWidget(old);
    final incoming = (widget.data['statut'] as String?) ?? 'disponible';
    if (incoming != _statut) setState(() => _statut = incoming);
  }

  String _statutLabel(String s) => switch (s) {
    'disponible' => 'En ligne',
    'reserve'    => 'Réservé',
    'pause'      => 'En pause',
    'vendu'      => 'Vendu',
    'cede'       => 'Cédé',
    'expiree'    => 'Expirée',
    'quota_depasse' => 'Bloquée · quota dépassé',
    'brouillon'  => 'Brouillon',
    _            => s,
  };

  void _showStats() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AnnonceStatsSheet(annonceId: widget.id, titre: widget.data['titre'] as String? ?? ''),
    );
  }

  Future<void> _togglePause() async {
    final prev = _statut;
    final next = _statut == 'pause' ? 'disponible' : 'pause';
    setState(() => _statut = next);
    try {
      await Supabase.instance.client.from('annonces').update({'statut': next}).eq('id', widget.id);
      widget.onRefresh();
    } catch (e) {
      setState(() => _statut = prev);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur: $e', style: const TextStyle(fontFamily: 'Galey'))));
      }
    }
  }

  Future<void> _renew() async {
    try {
      final ouvert = await renewAnnonceListing(context, widget.id);
      if (ouvert && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(
            "Paiement ouvert : l'annonce sera prolongée dès le paiement.", style: TextStyle(fontFamily: 'Galey'))));
      }
      widget.onRefresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur: $e', style: const TextStyle(fontFamily: 'Galey'))));
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer l\'annonce',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
        content: const Text(
            'Cette annonce sera supprimée et ne sera plus visible.\nCette action est irréversible.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler', style: TextStyle(color: Colors.grey, fontFamily: 'Galey'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer',
                style: TextStyle(color: Colors.redAccent, fontFamily: 'Galey', fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok == true) {
      try {
        await Supabase.instance.client.from('annonces').update({'statut': 'supprime'}).eq('id', widget.id);
        widget.onRefresh();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Erreur: $e', style: const TextStyle(fontFamily: 'Galey'))));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final espece     = (widget.data['espece'] as String?) ?? '';
    final race       = (widget.data['race'] as String?) ?? '';
    final titre      = (widget.data['titre'] as String?) ?? '';
    final type       = (widget.data['type'] as String?) ?? 'animal';
    final typeVente  = (widget.data['typeVente'] as String?) ?? 'vente';
    final photos     = List<String>.from(widget.data['photos'] ?? []);
    final prix       = (widget.data['prix'] as num?)?.toDouble();
    final prixMin    = (widget.data['prixMinPortee'] as num?)?.toDouble();
    final prixMax    = (widget.data['prixMaxPortee'] as num?)?.toDouble();
    final spRaw      = widget.data['sailliePrix'];
    final sailliePrix = spRaw is num ? spRaw.toDouble() : spRaw is String ? double.tryParse(spRaw) : null;
    final vues       = (widget.data['vues'] as num?)?.toInt() ?? 0;
    final contacts   = (widget.data['contacts'] as num?)?.toInt() ?? 0;
    final createdAt  = widget.data['createdAt'] as Timestamp?;
    final expiresAt  = widget.data['expiresAt'] as Timestamp?;
    final isPaused   = _statut == 'pause';
    final isTermine  = _statut == 'vendu' || _statut == 'cede' || _statut == 'expiree' || _statut == 'supprime';
    final boostUntil = DateTime.tryParse(widget.data['boost_until']?.toString() ?? '');
    final isBoosted  = boostUntil != null && boostUntil.isAfter(DateTime.now());

    final displayTitle = titre.isNotEmpty ? titre
        : race.isNotEmpty ? race : speciesLabel(espece);

    String prixLabel = '';
    if (typeVente == 'vente') {
      if (type == 'portee' && (prixMin != null || prixMax != null)) {
        prixLabel = prixMin != null && prixMax != null
            ? '${prixMin.toInt()} – ${prixMax.toInt()} €'
            : prixMin != null ? 'Dès ${prixMin.toInt()} €'
            : 'Max ${prixMax!.toInt()} €';
      } else if (prix != null && prix > 0) {
        prixLabel = '${prix.toStringAsFixed(0)} €';
      }
    } else if (typeVente == 'adoption') {
      prixLabel = 'Adoption';
    } else if (typeVente == 'saillie') {
      prixLabel = sailliePrix != null && sailliePrix > 0
          ? 'Saillie · ${sailliePrix.toInt()} €'
          : 'Saillie';
    }

    // Days remaining
    String expiryLabel = '';
    if (expiresAt != null && !isTermine) {
      final remaining = expiresAt.toDate().difference(DateTime.now()).inDays;
      if (remaining <= 0) {
        expiryLabel = 'Expirée';
      } else if (remaining <= 7) {
        expiryLabel = 'Expire dans $remaining j';
      }
    }

    void voir() => Navigator.push(context, MaterialPageRoute(
        builder: (_) => AnnonceDetailPage(annonceId: widget.id, initialData: widget.data)));
    void modifier() {
      if (widget.isAssociation) {
        Navigator.push(context, MaterialPageRoute(
            builder: (_) => CreateAnnonceAssoPage(annonceId: widget.id, initialData: widget.data)))
            .then((_) { if (mounted) widget.onRefresh(); });
      } else {
        Navigator.push(context, MaterialPageRoute(
            builder: (_) => CreateAnnoncePage(annonceId: widget.id, initialData: widget.data)));
      }
    }
    final supprimer = GestionAction('Supprimer', Icons.delete_outline, () => _confirmDelete(context), danger: true);

    List<GestionAction> principales;
    List<GestionAction> menu;
    String? note;
    if (_statut == 'quota_depasse') {
      principales = [GestionAction('Passer à un plan payant', Icons.workspace_premium_outlined,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AbonnementPage())))];
      menu = [supprimer];
      note = 'Annonce bloquée : passez à un plan payant pour la republier.';
    } else if (!isTermine) {
      principales = [
        GestionAction('Voir', Icons.visibility_outlined, voir),
        GestionAction(_statut == 'brouillon' ? 'Reprendre' : 'Modifier', Icons.edit_outlined, modifier),
      ];
      menu = [
        // Boost : point d'entrée unique (retiré de la fiche de l'annonce).
        GestionAction(isBoosted ? 'Prolonger le boost' : 'Booster l\'annonce', Icons.bolt,
            () => ouvrirBoostAnnonce(context, annonceId: widget.id,
                boostUntil: widget.data['boost_until']?.toString(), association: widget.isAssociation),
            actif: isBoosted),
        GestionAction('Statistiques', Icons.bar_chart_outlined, _showStats),
        GestionAction(isPaused ? 'Activer' : 'Mettre en pause',
            isPaused ? Icons.play_arrow_outlined : Icons.pause_outlined, _togglePause),
        // Renouveler (proactif — visible dès J-7, pas besoin d'attendre
        // l'expiration complète, utile notamment pour les associations
        // dont le processus d'adoption dépasse souvent 30 jours).
        if (expiryLabel.isNotEmpty) GestionAction('Renouveler', Icons.refresh_outlined, _renew),
        supprimer,
      ];
    } else if (_statut == 'expiree') {
      principales = [GestionAction('Renouveler', Icons.refresh_outlined, _renew)];
      menu = [GestionAction('Voir', Icons.visibility_outlined, voir), supprimer];
    } else {
      principales = [GestionAction('Voir', Icons.visibility_outlined, voir)];
      menu = const [];
    }

    final ville = (widget.data['ville_eleveur'] as String?) ?? '';
    return GestionCarteAnnonce(
      onTap: voir,
      photo: photos.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: photos.first, fit: BoxFit.cover,
              placeholder: (_, __) => _placeholder(espece),
              errorWidget: (_, __, ___) => _placeholder(espece))
          : _placeholder(espece),
      titre: displayTitle,
      sousTitre: [speciesLabel(espece), if (race.isNotEmpty && race != displayTitle) race, if (ville.isNotEmpty) ville]
          .where((e) => e.isNotEmpty).join(' · '),
      etiquettes: [
        puceStatut(_statutLabel(_statut), _statutTeinte(_statut)),
        puceType(type == 'portee' ? 'Portée' : typeVente == 'saillie' ? 'Saillie' : typeVente == 'adoption' ? 'Adoption' : 'Animal'),
        if (isBoosted) const DashPuce('Boostée', fg: Color(0xFFB45309), bg: Color(0xFFFEF3C7), icon: Icons.bolt),
        if (expiryLabel.isNotEmpty) puceStatut(expiryLabel, 'rouge'),
      ],
      prix: prixLabel,
      indicateurs: [
        (Icons.visibility_outlined, '$vues vue${vues > 1 ? 's' : ''}'),
        (Icons.chat_bubble_outline, '$contacts contact${contacts > 1 ? 's' : ''}'),
        if (createdAt != null) (Icons.calendar_today_outlined, DateFormat('dd/MM/yy').format(createdAt.toDate())),
      ],
      principales: principales,
      menu: menu,
      note: note,
    );
  }

  String _statutTeinte(String s) => switch (s) {
    'disponible' => 'vert',
    'reserve'    => 'ambre',
    'pause' || 'brouillon' => 'gris',
    'vendu' || 'cede' => 'bleu',
    _            => 'rouge',
  };

  Widget _placeholder(String espece) => Container(
    color: const Color(0xFFEEF5EA),
    child: Center(child: speciesIcon(espece, 32,
        const Color(0xFF6E9E57).withValues(alpha: 0.35))),
  );
}

// ─── Stats bottom sheet ──────────────────────────────────────────────────────

class _AnnonceStatsSheet extends StatefulWidget {
  final String annonceId;
  final String titre;
  const _AnnonceStatsSheet({required this.annonceId, required this.titre});
  @override
  State<_AnnonceStatsSheet> createState() => _AnnonceStatsSheetState();
}

class _AnnonceStatsSheetState extends State<_AnnonceStatsSheet> {
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _stats;
  int _period = 30;
  String? _typeVente; // 'portee' | 'saillie' | null

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Charge le type de l'annonce
      final annonceRow = await Supabase.instance.client
          .from('annonces')
          .select('type_vente, vues, contacts')
          .eq('id', widget.annonceId)
          .maybeSingle();
      _typeVente = annonceRow?['type_vente'] as String?;

      // Charge les stats via l'API web
      final uri = Uri.parse('/api/annonces/stats?annonceId=${widget.annonceId}&period=$_period');
      // Sur mobile on passe par Supabase direct (pas d'API Next.js accessible)
      await _loadFromSupabase(annonceRow);
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadFromSupabase(Map<String, dynamic>? annonceRow) async {
    final supa = Supabase.instance.client;
    final since = DateTime.now().subtract(Duration(days: _period));
    final sinceStr = since.toIso8601String().split('T')[0];

    final futures = await Future.wait([
      supa.from('annonces_stats_daily')
          .select('date, vues, visiteurs, contacts, favoris')
          .eq('annonce_id', widget.annonceId)
          .gte('date', sinceStr)
          .order('date'),
      supa.from('animaux_portee_stats')
          .select('bebe_index, vues, favoris')
          .eq('annonce_id', widget.annonceId)
          .gte('date', sinceStr),
      supa.from('likes')
          .select('id')
          .eq('annonce_id', widget.annonceId),
    ]);

    final daily   = futures[0] as List<dynamic>;
    final porteeRaw = futures[1] as List<dynamic>;
    final likes   = futures[2] as List<dynamic>;

    final totalVues     = daily.fold<int>(0, (s, d) => s + ((d['vues'] as num?)?.toInt() ?? 0));
    final totalContacts = daily.fold<int>(0, (s, d) => s + ((d['contacts'] as num?)?.toInt() ?? 0));
    final totalFavoris  = likes.length;

    // Agréger portée
    final porteeMap = <int, Map<String, int>>{};
    for (final row in porteeRaw) {
      final i = (row['bebe_index'] as num).toInt();
      porteeMap.putIfAbsent(i, () => {'vues': 0, 'favoris': 0});
      porteeMap[i]!['vues'] = porteeMap[i]!['vues']! + ((row['vues'] as num?)?.toInt() ?? 0);
      porteeMap[i]!['favoris'] = porteeMap[i]!['favoris']! + ((row['favoris'] as num?)?.toInt() ?? 0);
    }
    final portee = porteeMap.entries
        .map((e) => {'index': e.key, 'vues': e.value['vues'], 'favoris': e.value['favoris']})
        .toList()
      ..sort((a, b) => (b['vues'] as int).compareTo(a['vues'] as int));

    final vues = (totalVues > 0 ? totalVues : (annonceRow?['vues'] as num?)?.toInt()) ?? 0;
    final contacts = (totalContacts > 0 ? totalContacts : (annonceRow?['contacts'] as num?)?.toInt()) ?? 0;
    final tauxConversion = vues > 0 ? (contacts / vues * 100).round() : 0;
    final tauxInteret    = vues > 0 ? (totalFavoris / vues * 100).round() : 0;
    final score = (tauxConversion * 0.4 + tauxInteret * 0.3 + (vues / 10).clamp(0, 100) * 0.3).round();

    if (mounted) setState(() {
      _loading = false;
      _stats = {
        'vues': vues, 'contacts': contacts, 'favoris': totalFavoris,
        'tauxConversion': tauxConversion, 'tauxInteret': tauxInteret, 'score': score,
        'daily': daily, 'portee': portee,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, sc) => Container(
        decoration: const BoxDecoration(
          color: kDashFond,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          // En-tête blanc : titre, période, fermeture
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(bottom: BorderSide(color: kDashBorder)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 12),
            child: Column(children: [
              Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: Text(
                    'Statistiques de ${widget.titre.isNotEmpty ? widget.titre : 'l\'annonce'}',
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 17, fontWeight: FontWeight.w700, color: kDashInk))),
                IconButton(
                  tooltip: 'Fermer',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: kDashMuted),
                ),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                if (_typeVente != null)
                  puceType(_typeVente == 'saillie' ? 'Saillie' : _typeVente == 'portee' ? 'Portée' : 'Animal'),
                const Spacer(),
                // Sélecteur de période
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: const Color(0xFFF3F6F5), borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [7, 30].map((p) => GestureDetector(
                    onTap: () { setState(() => _period = p); _load(); },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _period == p ? _teal : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('$p jours', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5,
                          fontWeight: FontWeight.w700, color: _period == p ? Colors.white : kDashMuted)),
                    ),
                  )).toList()),
                ),
                const SizedBox(width: 8),
              ]),
            ]),
          ),
          // Contenu
          Expanded(child: _loading
              ? const Center(child: CircularProgressIndicator(color: _teal))
              : _error != null
                  ? Center(child: Text('Erreur : $_error', style: const TextStyle(fontFamily: 'Galey', color: Colors.red)))
                  : _buildContent(sc)),
        ]),
      ),
    );
  }

  Widget _carte(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kDashBorder)),
        child: child,
      );

  Widget _titreCarte(String texte, IconData icon) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Icon(icon, size: 18, color: _teal),
          const SizedBox(width: 8),
          Text(texte, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700, color: kDashInk)),
        ]),
      );

  Widget _buildContent(ScrollController sc) {
    final s = _stats!;
    final vues     = s['vues'] as int;
    final contacts = s['contacts'] as int;
    final favoris  = s['favoris'] as int;
    final taux     = s['tauxConversion'] as int;
    final score    = s['score'] as int;
    final portee   = s['portee'] as List<dynamic>;
    final daily    = s['daily'] as List<dynamic>;
    final isSaillie = _typeVente == 'saillie';
    final couleurScore = score >= 70 ? _green : score >= 40 ? const Color(0xFFD97706) : const Color(0xFFDC2626);
    final (puceFg, puceBg, puceTexte) = taux >= 5 ? (const Color(0xFF2F7D3A), const Color(0xFFEAF5EC), 'Bon')
        : taux >= 2 ? (const Color(0xFFB45309), const Color(0xFFFEF3C7), 'Moyen')
        : (const Color(0xFFB91C1C), const Color(0xFFFEF2F2), 'Faible');

    return ListView(controller: sc, padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
      // Indicateurs principaux
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.75,
        children: [
          _KpiCard(icon: Icons.visibility_outlined, label: 'Vues', value: '$vues', color: _teal),
          _KpiCard(icon: isSaillie ? Icons.handshake_outlined : Icons.people_outline,
              label: isSaillie ? 'Demandes' : 'Contacts', value: '$contacts', color: _teal),
          _KpiCard(icon: Icons.favorite_border, label: 'Favoris', value: '$favoris', color: const Color(0xFFE0457B)),
          _KpiCard(icon: Icons.bar_chart_rounded, label: 'Conversion', value: '$taux %', color: _teal,
              puce: DashPuce(puceTexte, fg: puceFg, bg: puceBg)),
        ],
      ),
      const SizedBox(height: 12),

      // Évolution des vues (données réelles, jours sans visite = 0)
      _carte(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Évolution des vues', style: TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700, color: kDashInk)),
        const SizedBox(height: 10),
        if (daily.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: Text('Pas encore de données sur cette période.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: kDashMuted))),
          )
        else
          SizedBox(height: 170, width: double.infinity,
              child: CustomPaint(painter: _CourbeVuesPainter(_serieVues(daily)))),
      ])),
      const SizedBox(height: 12),

      // Score d'attractivité
      _carte(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _titreCarte('Score d\'attractivité', Icons.star_outline_rounded),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text('$score', style: TextStyle(fontFamily: 'Galey', fontSize: 26, fontWeight: FontWeight.w700, color: couleurScore)),
          const Text(' / 100', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: kDashMuted)),
          const Spacer(),
          Text('Taux de contact : $taux %', style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: kDashMuted)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(
          value: score / 100, minHeight: 8,
          backgroundColor: Colors.grey.shade100,
          valueColor: AlwaysStoppedAnimation(couleurScore),
        )),
      ])),
      const SizedBox(height: 12),

      // Section portée (seulement si portée, pas saillie)
      if (!isSaillie && portee.isNotEmpty) ...[
        _carte(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _titreCarte('Portée : podium', Icons.pets_outlined),
          Row(children: [
            Expanded(child: _podium('Plus consulté', 'Chiot n° ${(portee.first['index'] as int) + 1}', '${portee.first['vues']} vues')),
            const SizedBox(width: 10),
            Expanded(child: (){
              final topFav = [...portee]..sort((a, b) => (b['favoris'] as int).compareTo(a['favoris'] as int));
              return _podium('Plus aimé', 'Chiot n° ${(topFav.first['index'] as int) + 1}', '${topFav.first['favoris']} favoris');
            }()),
          ]),
          // Classement complet
          if (portee.length > 1) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: kDashBorder),
            const SizedBox(height: 8),
            ...portee.take(6).toList().asMap().entries.map((e) {
              final rank = e.key + 1;
              final b = e.value as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  SizedBox(width: 22, child: Text('$rank', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.grey.shade400))),
                  Text('Chiot n° ${(b['index'] as int) + 1}', style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: kDashInk)),
                  const Spacer(),
                  const Icon(Icons.visibility_outlined, size: 14, color: kDashMuted),
                  const SizedBox(width: 3),
                  Text('${b['vues']}', style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: kDashMuted)),
                  const SizedBox(width: 12),
                  const Icon(Icons.favorite_border, size: 14, color: kDashMuted),
                  const SizedBox(width: 3),
                  Text('${b['favoris']}', style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: kDashMuted)),
                ]),
              );
            }),
          ],
        ])),
        const SizedBox(height: 12),
      ],

      // Section saillie spécifique
      if (isSaillie) ...[
        _carte(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _titreCarte('Données saillie', Icons.handshake_outlined),
          _InfoRow('Demandes de contact', '$contacts'),
          _InfoRow('Intérêt (favoris)', '$favoris éleveurs'),
          _InfoRow('Taux de demande', '${vues > 0 ? (contacts / vues * 100).round() : 0} % des visiteurs'),
        ])),
        const SizedBox(height: 12),
      ],
    ]);
  }

  Widget _podium(String titre, String valeur, String detail) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFF3F6F5), borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Text(titre, style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: kDashMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(valeur, style: const TextStyle(fontFamily: 'Galey', fontSize: 16, fontWeight: FontWeight.w700, color: kDashInk)),
          Text(detail, style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: kDashMuted)),
        ]),
      );

  /// Vues jour par jour sur la période (jours sans ligne = 0 vue).
  List<(DateTime, int)> _serieVues(List<dynamic> daily) {
    final parJour = <String, int>{};
    for (final d in daily) {
      final k = (d['date']?.toString() ?? '');
      if (k.length >= 10) parJour[k.substring(0, 10)] = ((d['vues'] as num?)?.toInt() ?? 0);
    }
    final now = DateTime.now();
    final debut = DateTime(now.year, now.month, now.day);
    return [
      for (var i = _period - 1; i >= 0; i--)
        (debut.subtract(Duration(days: i)),
            parJour[DateFormat('yyyy-MM-dd').format(debut.subtract(Duration(days: i)))] ?? 0),
    ];
  }
}

/// Courbe des vues (aire légère, points, graduations et dates).
class _CourbeVuesPainter extends CustomPainter {
  final List<(DateTime, int)> serie;
  _CourbeVuesPainter(this.serie);

  @override
  void paint(Canvas canvas, Size size) {
    if (serie.isEmpty) return;
    const g = 26.0, b = 20.0, d = 6.0, h0 = 6.0;
    final maxV = serie.map((e) => e.$2).fold<int>(4, (a, v) => v > a ? v : a);
    final pas = maxV <= 8 ? 2 : (maxV / 4).ceil();
    final haut = (maxV / pas).ceil() * pas;
    double x(int i) => g + i * (size.width - g - d) / (serie.length > 1 ? serie.length - 1 : 1);
    double y(num v) => h0 + (size.height - b - h0) * (1 - v / haut);
    const style = TextStyle(fontFamily: 'Galey', fontSize: 10, color: kDashMuted);
    void texte(String t, Offset o, {bool droite = false, bool centre = false}) {
      final tp = TextPainter(text: TextSpan(text: t, style: style), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(droite ? o.dx - tp.width : centre ? o.dx - tp.width / 2 : o.dx, o.dy - tp.height / 2));
    }
    final grille = Paint()..color = const Color(0xFFEEF0EE)..strokeWidth = 1;
    for (var v = 0; v <= haut; v += pas) {
      canvas.drawLine(Offset(g, y(v)), Offset(size.width - d, y(v)), grille);
      texte('$v', Offset(g - 6, y(v)), droite: true);
    }
    final ligne = Path();
    for (var i = 0; i < serie.length; i++) {
      if (i == 0) {
        ligne.moveTo(x(i), y(serie[i].$2));
      } else {
        ligne.lineTo(x(i), y(serie[i].$2));
      }
    }
    final aire = Path.from(ligne)
      ..lineTo(x(serie.length - 1), y(0))
      ..lineTo(x(0), y(0))
      ..close();
    canvas.drawPath(aire, Paint()..color = kDashTeal.withValues(alpha: 0.08));
    canvas.drawPath(ligne, Paint()
      ..color = kDashTeal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round);
    final point = Paint()..color = kDashTeal;
    for (var i = 0; i < serie.length; i++) {
      canvas.drawCircle(Offset(x(i), y(serie[i].$2)), serie.length > 14 ? 2.2 : 3.2, point);
    }
    final intervalle = (serie.length / 5).round().clamp(1, 1000);
    for (var i = 0; i < serie.length; i += intervalle) {
      texte(DateFormat('d MMM', 'fr_FR').format(serie[i].$1), Offset(x(i), size.height - b / 2 + 2), centre: true);
    }
  }

  @override
  bool shouldRepaint(_CourbeVuesPainter old) => old.serie != serie;
}

Widget _InfoRow(String label, String value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 3),
  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
    Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6B7280))),
    Text(value, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1F2A2E))),
  ]),
);

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  final Widget? puce;
  const _KpiCard({required this.icon, required this.label, required this.value, required this.color, this.puce});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kDashBorder)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 20, color: color),
        const Spacer(),
        if (puce != null) puce!,
      ]),
      const Spacer(),
      Text(value, style: const TextStyle(fontFamily: 'Galey', fontSize: 20, fontWeight: FontWeight.w700, color: kDashInk)),
      Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: kDashMuted)),
    ]),
  );
}
