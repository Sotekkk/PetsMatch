import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart';
import 'package:PetsMatch/pages/eleveur/post/annonce_detail_page.dart';
import 'package:PetsMatch/pages/eleveur/post/create_annonce_page.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MesAnnoncesPage extends StatefulWidget {
  const MesAnnoncesPage({super.key});
  @override
  State<MesAnnoncesPage> createState() => _MesAnnoncesPageState();
}

class _MesAnnoncesPageState extends State<MesAnnoncesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  int _refreshKey = 0;

  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
      body: TabBarView(
        controller: _tabController,
        children: [
          _AnnoncesList(uid: _uid, filter: 'all',      refreshKey: _refreshKey),
          _AnnoncesList(uid: _uid, filter: 'actives',  refreshKey: _refreshKey),
          _AnnoncesList(uid: _uid, filter: 'pause',    refreshKey: _refreshKey),
          _AnnoncesList(uid: _uid, filter: 'terminees',refreshKey: _refreshKey),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const CreateAnnoncePage()))
            .then((_) { if (mounted) setState(() => _refreshKey++); }),
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle annonce',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
      ),
    );
  }
}

// ─── Liste filtrée ────────────────────────────────────────────────────────────

class _AnnoncesList extends StatefulWidget {
  final String? uid;
  final String filter;
  final int refreshKey;
  const _AnnoncesList({required this.uid, required this.filter, required this.refreshKey});

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
      final data = await Supabase.instance.client
          .from('annonces')
          .select()
          .eq('uid_eleveur', widget.uid!)
          .order('created_at', ascending: false);
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
            id: _rows[i]['id'] as String, data: _rows[i], onRefresh: _load),
      ),
    );
  }
}

// ─── Card annonce avec stats + actions ───────────────────────────────────────

class _AnnonceCard extends StatefulWidget {
  final String id;
  final Map<String, dynamic> data;
  final VoidCallback onRefresh;
  const _AnnonceCard({required this.id, required this.data, required this.onRefresh});
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
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => CreateAnnoncePage(annonceId: widget.id, initialData: widget.data))),
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
