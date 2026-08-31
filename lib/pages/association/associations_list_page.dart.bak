import 'package:PetsMatch/pages/association/association_detail_page.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AssociationsListPage extends StatefulWidget {
  const AssociationsListPage({super.key});

  @override
  State<AssociationsListPage> createState() => _AssociationsListPageState();
}

class _AssociationsListPageState extends State<AssociationsListPage> {
  static const _teal = Color(0xFF0C5C6C);

  List<Map<String, dynamic>> _all      = [];
  List<Map<String, dynamic>> _filtered = [];
  bool   _loading = true;
  String _search  = '';

  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Profils secondaires de type association
      final profiles = await Supabase.instance.client
          .from('user_profiles')
          .select('id,uid,profile_label,avatar_url,profile_type')
          .eq('profile_type', 'association')
          .order('profile_label');

      // Comptes primaires association (is_association = true)
      List<Map<String, dynamic>> primary = [];
      try {
        primary = await Supabase.instance.client
            .from('users')
            .select('uid,firstname,lastname,name_elevage,ville,ville_elevage,photo_profil_elevage,photo_url,description_elevage')
            .eq('is_association', true);
      } catch (_) {
        // Colonne pas encore présente (migration non appliquée)
      }

      // Enrichir les profils secondaires avec les infos de l'utilisateur parent
      final uids = (profiles as List).map((p) => p['uid']?.toString()).whereType<String>().toSet().toList();
      Map<String, Map<String, dynamic>> usersMap = {};
      if (uids.isNotEmpty) {
        final users = await Supabase.instance.client
            .from('users')
            .select('uid,firstname,lastname,ville,ville_elevage,region,region_elevage')
            .inFilter('uid', uids);
        for (final u in users as List) {
          usersMap[u['uid']?.toString() ?? ''] = u as Map<String, dynamic>;
        }
      }

      final list = <Map<String, dynamic>>[];

      // Ajouter les profils secondaires
      for (final p in profiles) {
        final uid   = p['uid']?.toString() ?? '';
        final user  = usersMap[uid] ?? {};
        final ville = (user['ville_elevage'] as String?)?.isNotEmpty == true
            ? user['ville_elevage'] as String
            : user['ville'] as String? ?? '';
        list.add({
          'uid':    uid,
          'name':   p['profile_label']?.toString() ?? 'Association',
          'avatar': p['avatar_url']?.toString() ?? '',
          'ville':  ville,
          'source': 'profile',
        });
      }

      // Ajouter les comptes primaires association (dédupliqués)
      final existingUids = list.map((e) => e['uid']?.toString()).toSet();
      for (final u in primary) {
        final uid = u['uid']?.toString() ?? '';
        if (existingUids.contains(uid)) continue;
        final name = (u['name_elevage'] as String?)?.isNotEmpty == true
            ? u['name_elevage'] as String
            : '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
        final ville = (u['ville_elevage'] as String?)?.isNotEmpty == true
            ? u['ville_elevage'] as String
            : u['ville'] as String? ?? '';
        final avatar = (u['photo_profil_elevage'] as String?)?.isNotEmpty == true
            ? u['photo_profil_elevage'] as String
            : u['photo_url'] as String? ?? '';
        list.add({
          'uid':    uid,
          'name':   name,
          'avatar': avatar,
          'ville':  ville,
          'source': 'primary',
        });
      }

      if (mounted) {
        setState(() {
          _all = list;
          _applyFilter();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openDetail(BuildContext ctx, Map<String, dynamic> asso) {
    final uid = asso['uid']?.toString() ?? '';
    if (uid.isEmpty) return;
    Navigator.push(ctx, MaterialPageRoute(
      builder: (_) => AssociationDetailPage(
        uid:    uid,
        name:   asso['name']?.toString()   ?? 'Association',
        avatar: asso['avatar']?.toString() ?? '',
        ville:  asso['ville']?.toString()  ?? '',
      ),
    ));
  }

  void _applyFilter() {
    if (_search.isEmpty) {
      _filtered = List.from(_all);
    } else {
      final q = _search.toLowerCase();
      _filtered = _all.where((a) {
        return (a['name']?.toString().toLowerCase().contains(q) ?? false) ||
               (a['ville']?.toString().toLowerCase().contains(q) ?? false);
      }).toList();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Associations & Refuges',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() { _search = v; _applyFilter(); }),
              style: const TextStyle(color: Colors.white, fontFamily: 'Galey'),
              decoration: InputDecoration(
                hintText: 'Rechercher une association…',
                hintStyle: const TextStyle(color: Colors.white70, fontFamily: 'Galey'),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white70),
                        onPressed: () { _searchCtrl.clear(); setState(() { _search = ''; _applyFilter(); }); })
                    : null,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.15),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _filtered.isEmpty
              ? const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.favorite_border, size: 60, color: Colors.grey),
                    SizedBox(height: 12),
                    Text('Aucune association trouvée',
                        style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) => _AssoCard(
                      asso: _filtered[i],
                      onTap: () => _openDetail(context, _filtered[i]),
                    ),
                  ),
                ),
    );
  }
}

class _AssoCard extends StatelessWidget {
  final Map<String, dynamic> asso;
  final VoidCallback onTap;

  static const _teal = Color(0xFF0C5C6C);

  const _AssoCard({required this.asso, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name   = asso['name']?.toString() ?? 'Association';
    final ville  = asso['ville']?.toString() ?? '';
    final avatar = asso['avatar']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 26,
          backgroundColor: const Color(0xFFDCEDD5),
          backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) as ImageProvider : null,
          child: avatar.isEmpty ? const Icon(Icons.favorite, color: Color(0xFF0C5C6C), size: 24) : null,
        ),
        title: Text(name,
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
        subtitle: ville.isNotEmpty
            ? Row(children: [
                const Icon(Icons.location_on_outlined, size: 13, color: Colors.grey),
                const SizedBox(width: 3),
                Text(ville, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
              ])
            : null,
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _teal.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text('Voir', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: _teal, fontWeight: FontWeight.w600)),
        ),
        onTap: onTap,
      ),
    );
  }
}
