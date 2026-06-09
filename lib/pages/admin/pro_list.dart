import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pro_detail.dart';

const _kCatLabels = <String, String>{
  '': 'Tous',
  'sante': 'Santé',
  'veterinaire': 'Vétérinaire',
  'education': 'Éducation',
  'garde': 'Pet sitter / Promeneur',
  'pension': 'Pension pour animaux',
  'toilettage': 'Toilettage',
  'photographe': 'Photographe',
  'marechal_ferrant': 'Maréchal-ferrant',
  'referencement': 'Commerce / Animalerie',
  'autre': 'Autre',
};

const _kTeal = Color(0xFF0C5C6C);

/// Unified profile entry for the admin list (primary or secondary)
class _ProfileEntry {
  final String uid;
  final bool isSecondary;
  final String? profileTableId; // user_profiles.id for secondary
  final String catPro;
  final String statutPro;
  final String nameElevage;
  final String professionPro;
  final List<String> especesAcceptees;
  final List certifications;
  final dynamic rayonIntervention;
  final String firstName;
  final String lastName;
  final String email;
  final String photoUrl;

  const _ProfileEntry({
    required this.uid,
    required this.isSecondary,
    this.profileTableId,
    required this.catPro,
    required this.statutPro,
    required this.nameElevage,
    required this.professionPro,
    required this.especesAcceptees,
    required this.certifications,
    required this.rayonIntervention,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.photoUrl,
  });
}

class ProList extends StatefulWidget {
  const ProList({super.key});

  @override
  State<ProList> createState() => _ProListState();
}

class _ProListState extends State<ProList> {
  final _supa = Supabase.instance.client;

  String _catFilter = '';
  String _search = '';
  bool _loading = true;
  List<_ProfileEntry> _entries = [];


  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      // 1. Load all primary pros from Supabase users
      final primaryRows = await _supa
          .from('users')
          .select('uid, cat_pro, statut_pro, rayon_intervention, especes_acceptees, certifications, profession_pro, name_elevage')
          .not('cat_pro', 'is', null)
          .inFilter('cat_pro', ['veterinaire', 'sante', 'education', 'garde', 'pension', 'toilettage', 'photographe', 'marechal_ferrant', 'referencement', 'autre']);

      // 2. Load all secondary profiles from user_profiles
      final secondaryRows = await _supa
          .from('user_profiles')
          .select('id, uid, profile_type, cat_pro, statut_pro, rayon_intervention, especes_acceptees, certifications, profession_pro, name_elevage')
          .not('profile_type', 'is', null);

      // 3. Collect all UIDs to fetch Firestore data
      final allUids = <String>{};
      for (final r in (primaryRows as List)) {
        if (r['uid'] != null) allUids.add(r['uid'] as String);
      }
      for (final r in (secondaryRows as List)) {
        if (r['uid'] != null) allUids.add(r['uid'] as String);
      }

      // 4. Load Firestore data for all UIDs
      final fireMap = <String, Map<String, dynamic>>{};
      // Also load from Supabase users for email/name (more reliable)
      if (allUids.isNotEmpty) {
        try {
          final userRows = await _supa
              .from('users')
              .select('uid, firstname, lastname, email, profile_picture_url_elevage, profile_picture_url')
              .inFilter('uid', allUids.toList());
          for (final u in (userRows as List)) {
            fireMap[u['uid'] as String] = Map<String, dynamic>.from(u);
          }
        } catch (_) {}
      }

      // 5. Build unified entries
      final entries = <_ProfileEntry>[];
      for (final r in (primaryRows as List)) {
        final uid = r['uid']?.toString() ?? '';
        final user = fireMap[uid] ?? {};
        entries.add(_ProfileEntry(
          uid: uid,
          isSecondary: false,
          profileTableId: null,
          catPro: r['cat_pro']?.toString() ?? '',
          statutPro: r['statut_pro']?.toString() ?? 'actif',
          nameElevage: r['name_elevage']?.toString() ?? '',
          professionPro: r['profession_pro']?.toString() ?? '',
          especesAcceptees: List<String>.from(r['especes_acceptees'] ?? []),
          certifications: List.from(r['certifications'] ?? []),
          rayonIntervention: r['rayon_intervention'],
          firstName: user['firstname']?.toString() ?? '',
          lastName: user['lastname']?.toString() ?? '',
          email: user['email']?.toString() ?? '',
          photoUrl: (user['profile_picture_url_elevage'] ?? user['profile_picture_url'] ?? '').toString(),
        ));
      }
      for (final r in (secondaryRows as List)) {
        final uid = r['uid']?.toString() ?? '';
        final user = fireMap[uid] ?? {};
        entries.add(_ProfileEntry(
          uid: uid,
          isSecondary: true,
          profileTableId: r['id']?.toString(),
          catPro: r['profile_type']?.toString() ?? r['cat_pro']?.toString() ?? '',
          statutPro: r['statut_pro']?.toString() ?? 'en_attente',
          nameElevage: r['name_elevage']?.toString() ?? '',
          professionPro: r['profession_pro']?.toString() ?? '',
          especesAcceptees: List<String>.from(r['especes_acceptees'] ?? []),
          certifications: List.from(r['certifications'] ?? []),
          rayonIntervention: r['rayon_intervention'],
          firstName: user['firstname']?.toString() ?? '',
          lastName: user['lastname']?.toString() ?? '',
          email: user['email']?.toString() ?? '',
          photoUrl: (user['profile_picture_url_elevage'] ?? user['profile_picture_url'] ?? '').toString(),
        ));
      }

      // Sort: en_attente first, then by name
      entries.sort((a, b) {
        final aWaiting = a.statutPro == 'en_attente' ? 0 : 1;
        final bWaiting = b.statutPro == 'en_attente' ? 0 : 1;
        if (aWaiting != bWaiting) return aWaiting - bWaiting;
        return '${a.firstName} ${a.lastName}'.compareTo('${b.firstName} ${b.lastName}');
      });

      if (mounted) setState(() { _entries = entries; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_ProfileEntry> get _filtered => _entries.where((e) {
    if (_catFilter.isNotEmpty && e.catPro != _catFilter) return false;
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      if (!e.firstName.toLowerCase().contains(q) &&
          !e.lastName.toLowerCase().contains(q) &&
          !e.nameElevage.toLowerCase().contains(q) &&
          !e.email.toLowerCase().contains(q)) { return false; }
    }
    return true;
  }).toList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: const Color(0xFFF8F8F6),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            onChanged: (v) => setState(() => _search = v.toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Rechercher par nom, structure, email...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Container(
          color: const Color(0xFFF8F8F6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _kCatLabels.entries.map((e) {
                final selected = _catFilter == e.key;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(e.value,
                        style: TextStyle(
                          fontFamily: 'Galey',
                          fontSize: 13,
                          color: selected ? Colors.white : Colors.black87,
                        )),
                    selected: selected,
                    onSelected: (_) => setState(() => _catFilter = e.key),
                    backgroundColor: Colors.white,
                    selectedColor: _kTeal,
                    checkmarkColor: Colors.white,
                    side: BorderSide(color: selected ? _kTeal : Colors.grey.shade300),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        if (_loading) const LinearProgressIndicator(color: _kTeal, minHeight: 2),
        Expanded(
          child: _loading
              ? const SizedBox.shrink()
              : _filtered.isEmpty
                  ? const Center(
                      child: Text('Aucun professionnel.',
                          style: TextStyle(fontFamily: 'Galey', color: Colors.grey)))
                  : RefreshIndicator(
                      onRefresh: _loadAll,
                      color: _kTeal,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final e = _filtered[i];
                          return _ProCard(
                            entry: e,
                            onRefresh: _loadAll,
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}

class _ProCard extends StatelessWidget {
  final _ProfileEntry entry;
  final VoidCallback onRefresh;

  const _ProCard({required this.entry, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final name = '${entry.firstName} ${entry.lastName}'.trim();
    final catLabel = _kCatLabels[entry.catPro] ?? (entry.catPro.isNotEmpty ? entry.catPro : '—');

    final (statutColor, statutLabel) = switch (entry.statutPro) {
      'refuse' => (Colors.red, 'Refusé'),
      'suspendu' => (Colors.orange, 'Suspendu'),
      'en_attente' => (Colors.blue, 'En attente'),
      _ => (Colors.green, 'Actif'),
    };

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProDetail(
              uid: entry.uid,
              nameDisplay: name.isNotEmpty ? name : 'Utilisateur',
              email: entry.email,
              photoUrl: entry.photoUrl,
              supaRow: {
                'cat_pro': entry.catPro,
                'statut_pro': entry.statutPro,
                'name_elevage': entry.nameElevage,
                'profession_pro': entry.professionPro,
                'especes_acceptees': entry.especesAcceptees,
                'certifications': entry.certifications,
                'rayon_intervention': entry.rayonIntervention,
              },
              isSecondary: entry.isSecondary,
              profileTableId: entry.profileTableId,
            ),
          ),
        );
        onRefresh();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Stack(clipBehavior: Clip.none, children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: _kTeal,
                child: ClipOval(
                  child: entry.photoUrl.isNotEmpty
                      ? Image.network(entry.photoUrl,
                          width: 52, height: 52, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.work, color: Colors.white))
                      : const Icon(Icons.work, color: Colors.white),
                ),
              ),
              if (entry.isSecondary)
                Positioned(
                  bottom: -2, right: -2,
                  child: Container(
                    width: 16, height: 16,
                    decoration: BoxDecoration(
                      color: Colors.purple.shade400,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: const Icon(Icons.layers, size: 9, color: Colors.white),
                  ),
                ),
            ]),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name.isNotEmpty ? name : 'Nom inconnu',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w500, fontSize: 15)),
                if (entry.nameElevage.isNotEmpty)
                  Text(entry.nameElevage,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF0C5C6C))),
                Text(entry.email, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 4),
                Wrap(spacing: 4, runSpacing: 2, children: [
                  if (entry.catPro.isNotEmpty) _badge(catLabel, _kTeal),
                  _badge(statutLabel, statutColor),
                  if (entry.isSecondary)
                    _badge('Secondaire', Colors.purple.shade400),
                ]),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ]),
        ),
      ),
    );
  }

  Widget _badge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8)),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, color: color,
                fontFamily: 'Galey', fontWeight: FontWeight.w500)),
      );
}
