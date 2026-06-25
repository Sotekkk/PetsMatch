import 'package:PetsMatch/pages/association/post/create_annonce_asso_page.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/eleveur/abonnement_page.dart';
import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart';
import 'package:PetsMatch/pages/eleveur/post/annonce_detail_page.dart';
import 'package:PetsMatch/pages/eleveur/post/create_annonce_page.dart';
import 'package:PetsMatch/services/plan_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class MesAnnoncesPage extends StatefulWidget {
  final bool isAssociation;
  const MesAnnoncesPage({super.key, this.isAssociation = false});
  @override
  State<MesAnnoncesPage> createState() => _MesAnnoncesPageState();
}

class _MesAnnoncesPageState extends State<MesAnnoncesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  int _refreshKey = 0;

  String _planCode    = 'free';
  int    _activeCount = 0;
  bool   _planLoading = true;

  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadPlan();
  }

  Future<void> _loadPlan() async {
    if (_uid == null) { setState(() => _planLoading = false); return; }
    final results = await Future.wait([
      PlanService.getPlanCode(_uid!),
      PlanService.countActiveAnnonces(_uid!),
    ]);
    if (!mounted) return;
    setState(() {
      _planCode    = results[0] as String;
      _activeCount = results[1] as int;
      _planLoading = false;
    });
  }

  void _onFabTap() {
    final config = PlanService.getConfig(_planCode);
    final atLimit = config.maxAnnonces != -1 && _activeCount >= config.maxAnnonces;
    if (atLimit) {
      _showQuotaSheet();
    } else {
      final page = widget.isAssociation
          ? const CreateAnnonceAssoPage()
          : const CreateAnnoncePage();
      Navigator.push(context, MaterialPageRoute(builder: (_) => page))
          .then((_) {
        if (mounted) {
          setState(() => _refreshKey++);
          _loadPlan();
        }
      });
    }
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
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config    = PlanService.getConfig(_planCode);
    final atLimit   = config.maxAnnonces != -1 && _activeCount >= config.maxAnnonces;
    final progress  = config.maxAnnonces == -1
        ? 0.0 : (_activeCount / config.maxAnnonces).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Mes Annonces',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _green,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(text: 'Toutes'),
            Tab(text: 'En ligne'),
            Tab(text: 'En pause'),
            Tab(text: 'Terminées'),
          ],
        ),
      ),
      body: Column(children: [
        // ── Quota banner ──────────────────────────────────────────────────
        if (!_planLoading)
          GestureDetector(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AbonnementPage())),
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: atLimit ? const Color(0xFFFFF0F0) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: atLimit ? Colors.red.shade200 : Colors.grey.shade100),
                boxShadow: [BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('${config.badge} Plan ${config.label}',
                        style: const TextStyle(fontFamily: 'Galey',
                            fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1F2A2E))),
                    const SizedBox(width: 8),
                    Text(
                      config.maxAnnonces == -1
                          ? 'Illimité'
                          : '$_activeCount / ${config.maxAnnonces}',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                          color: atLimit ? Colors.red : Colors.grey.shade500),
                    ),
                    if (atLimit) ...[
                      const SizedBox(width: 4),
                      const Text('· Limite atteinte',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                              color: Colors.red, fontWeight: FontWeight.w600)),
                    ],
                  ]),
                  if (config.maxAnnonces != -1) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.grey.shade100,
                        color: atLimit ? Colors.red.shade300 : _green,
                        minHeight: 4,
                      ),
                    ),
                  ],
                ])),
                const SizedBox(width: 10),
                if (_planCode == 'free')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                        color: _teal.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20)),
                    child: const Text('⚡ Pro',
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                            fontSize: 12, color: Color(0xFF0C5C6C))),
                  ),
              ]),
            ),
          ),

        // ── Tab body ──────────────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _AnnoncesList(uid: _uid, filter: 'all',      refreshKey: _refreshKey, isAssociation: widget.isAssociation),
              _AnnoncesList(uid: _uid, filter: 'actives',  refreshKey: _refreshKey, isAssociation: widget.isAssociation),
              _AnnoncesList(uid: _uid, filter: 'pause',    refreshKey: _refreshKey, isAssociation: widget.isAssociation),
              _AnnoncesList(uid: _uid, filter: 'terminees',refreshKey: _refreshKey, isAssociation: widget.isAssociation),
            ],
          ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _onFabTap,
        backgroundColor: atLimit ? Colors.grey.shade400 : _teal,
        foregroundColor: Colors.white,
        icon: Icon(atLimit ? Icons.lock_outline : Icons.add),
        label: Text(atLimit ? 'Quota atteint' : 'Nouvelle annonce',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
      ),
    );
  }
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
          const Text('🚫', style: TextStyle(fontSize: 40)),
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
              icon: const Text('⚡', style: TextStyle(fontSize: 16)),
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
  final int refreshKey;
  final bool isAssociation;
  const _AnnoncesList({required this.uid, required this.filter, required this.refreshKey, this.isAssociation = false});

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
    if (old.refreshKey != widget.refreshKey) _load();
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
      return const Center(child: CircularProgressIndicator(color: _teal));
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
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

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

  Color _statutColor(String s) => switch (s) {
    'disponible' => _green,
    'reserve'    => const Color(0xFFF59E0B),
    'pause'      => const Color(0xFF9CA3AF),
    'vendu' || 'cede' => Colors.blueGrey,
    _            => Colors.redAccent,
  };

  String _statutLabel(String s) => switch (s) {
    'disponible' => 'En ligne',
    'reserve'    => 'Réservé',
    'pause'      => 'En pause',
    'vendu'      => 'Vendu',
    'cede'       => 'Cédé',
    'expiree'    => 'Expirée',
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
    final newExpires = DateTime.now().add(const Duration(days: 30)).toIso8601String();
    setState(() => _statut = 'disponible');
    try {
      await Supabase.instance.client.from('annonces').update({
        'statut': 'disponible', 'expires_at': newExpires,
      }).eq('id', widget.id);
      widget.onRefresh();
    } catch (e) {
      setState(() => _statut = 'expiree');
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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => AnnonceDetailPage(annonceId: widget.id, initialData: widget.data))),
        borderRadius: BorderRadius.circular(16),
        child: Column(children: [
          // ── Row principale : photo + infos ────────────────────────────────
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Photo
            ClipRRect(
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16), bottomLeft: Radius.circular(16)),
              child: SizedBox(
                width: 90, height: 110,
                child: photos.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: photos.first, fit: BoxFit.cover,
                        placeholder: (_, __) => _placeholder(espece),
                        errorWidget: (_, __, ___) => _placeholder(espece))
                    : _placeholder(espece),
              ),
            ),
            // Infos
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Badges : type + statut
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    _badge(type == 'portee' ? 'Portée' : 'Animal',
                        type == 'portee' ? _teal : _green),
                    _badge(_statutLabel(_statut), _statutColor(_statut)),
                    if (expiryLabel.isNotEmpty)
                      _badge(expiryLabel, Colors.redAccent),
                  ]),
                  const SizedBox(height: 6),
                  // Titre
                  Row(children: [
                    speciesIcon(espece, 12, _teal),
                    const SizedBox(width: 4),
                    Expanded(child: Text(displayTitle,
                        style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                            fontSize: 14, color: Color(0xFF1F2A2E)),
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
                  const SizedBox(height: 3),
                  // Prix + date
                  Row(children: [
                    if (prixLabel.isNotEmpty)
                      Text(prixLabel,
                          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                              fontSize: 14, color: typeVente == 'adoption' ? _green : _teal)),
                    const Spacer(),
                    if (createdAt != null)
                      Text(DateFormat('dd/MM/yy').format(createdAt.toDate()),
                          style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                              color: Colors.grey.shade400)),
                  ]),
                  const SizedBox(height: 6),
                  // Stats vues / contacts
                  Row(children: [
                    _statChip(Icons.visibility_outlined, '$vues vue${vues > 1 ? 's' : ''}'),
                    const SizedBox(width: 10),
                    _statChip(Icons.chat_outlined, '$contacts contact${contacts > 1 ? 's' : ''}'),
                  ]),
                ]),
              ),
            ),
          ]),

          // ── Séparateur ────────────────────────────────────────────────────
          Divider(height: 1, color: Colors.grey.shade100),

          // ── Actions ───────────────────────────────────────────────────────
          if (!isTermine)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(children: [
                // Stats
                _ActionBtn(
                  icon: Icons.bar_chart_outlined,
                  label: 'Stats',
                  color: _teal,
                  onTap: _showStats,
                ),
                const SizedBox(width: 8),
                // Pause / Activer
                _ActionBtn(
                  icon: isPaused ? Icons.play_arrow_outlined : Icons.pause_outlined,
                  label: isPaused ? 'Activer' : 'Pause',
                  color: isPaused ? _green : const Color(0xFF9CA3AF),
                  onTap: _togglePause,
                ),
                const SizedBox(width: 8),
                // Modifier
                _ActionBtn(
                  icon: Icons.edit_outlined,
                  label: 'Modifier',
                  color: _teal,
                  onTap: () {
                    if (widget.isAssociation) {
                      Navigator.push(context, MaterialPageRoute(
                          builder: (_) => CreateAnnonceAssoPage(annonceId: widget.id, initialData: widget.data)))
                          .then((_) { if (mounted) widget.onRefresh(); });
                    } else {
                      Navigator.push(context, MaterialPageRoute(
                          builder: (_) => CreateAnnoncePage(annonceId: widget.id, initialData: widget.data)));
                    }
                  },
                ),
                const Spacer(),
                // Supprimer
                _ActionBtn(
                  icon: Icons.delete_outline,
                  label: 'Supprimer',
                  color: Colors.redAccent,
                  onTap: () => _confirmDelete(context),
                ),
              ]),
            )
          else if (_statut == 'expiree')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(children: [
                _ActionBtn(
                  icon: Icons.refresh_outlined,
                  label: 'Renouveler',
                  color: _teal,
                  onTap: _renew,
                ),
                const Spacer(),
                _ActionBtn(
                  icon: Icons.delete_outline,
                  label: 'Supprimer',
                  color: Colors.redAccent,
                  onTap: () => _confirmDelete(context),
                ),
              ]),
            )
          else
            const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
    child: Text(label,
        style: TextStyle(fontFamily: 'Galey', fontSize: 11,
            fontWeight: FontWeight.w600, color: color)),
  );

  Widget _statChip(IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: Colors.grey.shade400),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
          color: Colors.grey.shade500)),
    ],
  );

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
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, sc) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF8F8F6),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          // Poignée
          Container(margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          // Header
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF0C5C6C), Color(0xFF6E9E57)]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Statistiques', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.white.withValues(alpha: 0.7))),
                Text(widget.titre.isNotEmpty ? widget.titre : 'Annonce',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                if (_typeVente != null)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      _typeVente == 'saillie' ? '🐴 Saillie' : _typeVente == 'portee' ? '🐾 Portée' : '🐾 Animal',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.white),
                    ),
                  ),
              ])),
              // Sélecteur période
              Row(children: [7, 30].map((p) => GestureDetector(
                onTap: () { setState(() => _period = p); _load(); },
                child: Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _period == p ? Colors.white : Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${p}j', style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _period == p ? _teal : Colors.white)),
                ),
              )).toList()),
            ]),
          ),
          // Contenu
          Expanded(child: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF0C5C6C)))
              : _error != null
                  ? Center(child: Text('Erreur : $_error', style: const TextStyle(color: Colors.red)))
                  : _buildContent(sc)),
        ]),
      ),
    );
  }

  Widget _buildContent(ScrollController sc) {
    final s = _stats!;
    final vues     = s['vues'] as int;
    final contacts = s['contacts'] as int;
    final favoris  = s['favoris'] as int;
    final taux     = s['tauxConversion'] as int;
    final score    = s['score'] as int;
    final portee   = s['portee'] as List<dynamic>;
    final isSaillie = _typeVente == 'saillie';

    return ListView(controller: sc, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
      // KPIs principaux
      Row(children: [
        _KpiCard(icon: '👁️', label: 'Vues', value: '$vues', color: _teal),
        const SizedBox(width: 10),
        _KpiCard(icon: isSaillie ? '🤝' : '💬', label: isSaillie ? 'Demandes' : 'Contacts', value: '$contacts', color: _green),
        const SizedBox(width: 10),
        _KpiCard(icon: '❤️', label: 'Favoris', value: '$favoris', color: const Color(0xFFEC4899)),
      ]),
      const SizedBox(height: 12),

      // Score attractivité
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100)),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('🏆 Score attractivité', style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1F2A2E))),
            const SizedBox(height: 6),
            ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(
              value: score / 100,
              minHeight: 8,
              backgroundColor: Colors.grey.shade100,
              valueColor: AlwaysStoppedAnimation(score >= 70 ? _green : score >= 40 ? Colors.amber : Colors.redAccent),
            )),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Taux contact : $taux%', style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6B7280))),
              Text('Score : $score/100', style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.bold,
                  color: score >= 70 ? _green : score >= 40 ? Colors.amber.shade700 : Colors.redAccent)),
            ]),
          ])),
        ]),
      ),
      const SizedBox(height: 12),

      // Section portée (seulement si portée, pas saillie)
      if (!isSaillie && portee.isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade100)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('🐾 Portée — podium', style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1F2A2E))),
            const SizedBox(height: 10),
            Row(children: [
              // Top vues
              Expanded(child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  const Text('🏆 Plus consulté', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFFD97706), fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('Chiot #${(portee.first['index'] as int) + 1}', style: const TextStyle(fontFamily: 'Galey', fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFB45309))),
                  Text('👁️ ${portee.first['vues']} vues', style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFFD97706))),
                ]),
              )),
              const SizedBox(width: 10),
              // Top favoris
              Expanded(child: (){
                final topFav = [...portee]..sort((a, b) => (b['favoris'] as int).compareTo(a['favoris'] as int));
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFFFF1F2), borderRadius: BorderRadius.circular(12)),
                  child: Column(children: [
                    const Text('❤️ Plus aimé', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFFE11D48), fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('Chiot #${(topFav.first['index'] as int) + 1}', style: const TextStyle(fontFamily: 'Galey', fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFBE123C))),
                    Text('❤️ ${topFav.first['favoris']} favoris', style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFFE11D48))),
                  ]),
                );
              }()),
            ]),
            // Classement complet
            if (portee.length > 1) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              ...portee.take(6).toList().asMap().entries.map((e) {
                final rank = e.key + 1;
                final b = e.value as Map<String, dynamic>;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Text('#$rank', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade400)),
                    const SizedBox(width: 8),
                    Text('Chiot #${(b['index'] as int) + 1}', style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF374151))),
                    const Spacer(),
                    Text('👁️ ${b['vues']}', style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6B7280))),
                    const SizedBox(width: 12),
                    Text('❤️ ${b['favoris']}', style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6B7280))),
                  ]),
                );
              }),
            ],
          ]),
        ),
        const SizedBox(height: 12),
      ],

      // Section saillie spécifique
      if (isSaillie) ...[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade100)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('🐴 Données saillie', style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1F2A2E))),
            const SizedBox(height: 8),
            _InfoRow('Demandes de contact', '$contacts'),
            _InfoRow('Intérêt (favoris)', '$favoris éleveurs'),
            _InfoRow('Taux de demande', '${vues > 0 ? (contacts / vues * 100).round() : 0}% des visiteurs'),
          ]),
        ),
        const SizedBox(height: 12),
      ],

      const SizedBox(height: 20),
    ]);
  }
}

Widget _InfoRow(String label, String value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 3),
  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
    Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6B7280))),
    Text(value, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1F2A2E))),
  ]),
);

class _KpiCard extends StatelessWidget {
  final String icon, label, value;
  final Color color;
  const _KpiCard({required this.icon, required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade100)),
      child: Column(children: [
        Text(icon, style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontFamily: 'Galey', fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 10, color: Color(0xFF9CA3AF))),
      ]),
    ),
  );
}

// ─── Bouton action compact ────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.label,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
            fontWeight: FontWeight.w600, color: color)),
      ]),
    ),
  );
}
