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
          _AnnoncesList(key: ValueKey('all_$_refreshKey'),    uid: _uid, filter: 'all'),
          _AnnoncesList(key: ValueKey('act_$_refreshKey'),    uid: _uid, filter: 'actives'),
          _AnnoncesList(key: ValueKey('pause_$_refreshKey'),  uid: _uid, filter: 'pause'),
          _AnnoncesList(key: ValueKey('fin_$_refreshKey'),    uid: _uid, filter: 'terminees'),
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

class _AnnoncesList extends StatelessWidget {
  final String? uid;
  final String filter;
  const _AnnoncesList({super.key, required this.uid, required this.filter});

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
  Widget build(BuildContext context) {
    if (uid == null) return const Center(child: Text('Non connecté'));

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client.from('annonces')
          .stream(primaryKey: ['id'])
          .eq('uid_eleveur', uid!)
          .order('created_at', ascending: false),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF0C5C6C)));
        }
        if (snap.hasError) {
          return Center(child: Text('Erreur : ${snap.error}',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.redAccent)));
        }
        var rows = (snap.data ?? []).map(_norm).toList();

        rows = rows.where((d) {
          final s = (d['statut'] as String?) ?? '';
          switch (filter) {
            case 'actives':   return s == 'disponible' || s == 'reserve';
            case 'pause':     return s == 'pause';
            case 'terminees': return s == 'vendu' || s == 'cede' || s == 'expire';
            default:          return s != 'supprime';
          }
        }).toList();

        if (rows.isEmpty) {
          return Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.campaign_outlined, size: 64, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text(
                filter == 'pause' ? 'Aucune annonce en pause'
                    : filter == 'terminees' ? 'Aucune annonce terminée'
                    : 'Aucune annonce',
                style: TextStyle(fontFamily: 'Galey', fontSize: 16, color: Colors.grey.shade500)),
              const SizedBox(height: 6),
              if (filter == 'all' || filter == 'actives')
                Text('Appuyez sur + pour créer votre première annonce',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade400),
                    textAlign: TextAlign.center),
            ]),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          itemCount: rows.length,
          itemBuilder: (context, i) => _AnnonceCard(
              id: rows[i]['id'] as String, data: rows[i]),
        );
      },
    );
  }
}

// ─── Card annonce avec stats + actions ───────────────────────────────────────

class _AnnonceCard extends StatelessWidget {
  final String id;
  final Map<String, dynamic> data;
  const _AnnonceCard({required this.id, required this.data});

  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

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
    'expire'     => 'Expiré',
    _            => s,
  };

  Future<void> _togglePause(BuildContext context, String statut) async {
    final next = statut == 'pause' ? 'disponible' : 'pause';
    try {
      await Supabase.instance.client.from('annonces').update({'statut': next}).eq('id', id);
    } catch (e) {
      if (context.mounted) {
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
        await Supabase.instance.client.from('annonces').update({'statut': 'supprime'}).eq('id', id);
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
    final statut     = (data['statut'] as String?) ?? 'disponible';
    final espece     = (data['espece'] as String?) ?? '';
    final race       = (data['race'] as String?) ?? '';
    final titre      = (data['titre'] as String?) ?? '';
    final type       = (data['type'] as String?) ?? 'animal';
    final typeVente  = (data['typeVente'] as String?) ?? 'vente';
    final photos     = List<String>.from(data['photos'] ?? []);
    final prix       = (data['prix'] as num?)?.toDouble();
    final prixMin    = (data['prixMinPortee'] as num?)?.toDouble();
    final prixMax    = (data['prixMaxPortee'] as num?)?.toDouble();
    final spRaw      = data['sailliePrix'];
    final sailliePrix = spRaw is num ? spRaw.toDouble() : spRaw is String ? double.tryParse(spRaw) : null;
    final vues       = (data['vues'] as num?)?.toInt() ?? 0;
    final contacts   = (data['contacts'] as num?)?.toInt() ?? 0;
    final createdAt  = data['createdAt'] as Timestamp?;
    final expiresAt  = data['expiresAt'] as Timestamp?;
    final isPaused   = statut == 'pause';
    final isTermine  = statut == 'vendu' || statut == 'cede' || statut == 'expire' || statut == 'supprime';

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
            builder: (_) => AnnonceDetailPage(annonceId: id, initialData: data))),
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
                    _badge(_statutLabel(statut), _statutColor(statut)),
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
                  onTap: () => _togglePause(context, statut),
                ),
                const SizedBox(width: 8),
                // Modifier
                _ActionBtn(
                  icon: Icons.edit_outlined,
                  label: 'Modifier',
                  color: _teal,
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => CreateAnnoncePage(annonceId: id, initialData: data))),
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
