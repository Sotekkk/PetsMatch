import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pro_detail.dart';

const _kCatLabels = <String, String>{
  '': 'Tous',
  'sante': 'Santé',
  'veterinaire': 'Vétérinaire',
  'education': 'Éducation',
  'garde': 'Pension / Garde',
  'referencement': 'Référencement',
  'autre': 'Autre',
};

const _kTeal = Color(0xFF0C5C6C);

class ProList extends StatefulWidget {
  const ProList({super.key});

  @override
  State<ProList> createState() => _ProListState();
}

class _ProListState extends State<ProList> {
  final _supa = Supabase.instance.client;

  String _catFilter = '';
  String _search = '';
  Map<String, Map<String, dynamic>> _supaData = {};
  bool _loadingSupabase = true;

  @override
  void initState() {
    super.initState();
    _loadSupaData();
  }

  Future<void> _loadSupaData() async {
    setState(() => _loadingSupabase = true);
    try {
      final rows = await _supa
          .from('users')
          .select('uid, cat_pro, statut_pro, rayon_intervention, especes_acceptees, certifications, profession_pro, name_elevage');
      final map = <String, Map<String, dynamic>>{};
      for (final row in (rows as List)) {
        final uid = row['uid']?.toString() ?? '';
        if (uid.isNotEmpty) map[uid] = Map<String, dynamic>.from(row);
      }
      if (mounted) setState(() { _supaData = map; _loadingSupabase = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingSupabase = false);
    }
  }

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
              hintText: 'Rechercher par nom...',
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
                    side: BorderSide(
                        color: selected ? _kTeal : Colors.grey.shade300),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        if (_loadingSupabase)
          const LinearProgressIndicator(color: _kTeal, minHeight: 2),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('isPro', isEqualTo: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: _kTeal));
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(
                    child: Text('Aucun professionnel.',
                        style: TextStyle(fontFamily: 'Galey', color: Colors.grey)));
              }

              final docs = snapshot.data!.docs.where((doc) {
                final supaRow = _supaData[doc.id] ?? {};
                final cat = supaRow['cat_pro']?.toString() ?? '';
                if (_catFilter.isNotEmpty && cat != _catFilter) return false;
                if (_search.isNotEmpty) {
                  final data = doc.data() as Map<String, dynamic>;
                  final name =
                      '${data['firstname'] ?? ''} ${data['lastname'] ?? ''}'
                          .toLowerCase();
                  final struct = (supaRow['name_elevage'] ?? '').toString().toLowerCase();
                  if (!name.contains(_search) && !struct.contains(_search)) return false;
                }
                return true;
              }).toList();

              if (docs.isEmpty) {
                return const Center(
                    child: Text('Aucun résultat.',
                        style: TextStyle(fontFamily: 'Galey', color: Colors.grey)));
              }

              return RefreshIndicator(
                onRefresh: _loadSupaData,
                color: _kTeal,
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    final uid = docs[i].id;
                    final supaRow = _supaData[uid] ?? {};
                    return _ProCard(
                      uid: uid,
                      fireData: data,
                      supaRow: supaRow,
                      onRefresh: _loadSupaData,
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ProCard extends StatelessWidget {
  final String uid;
  final Map<String, dynamic> fireData;
  final Map<String, dynamic> supaRow;
  final VoidCallback onRefresh;

  const _ProCard({
    required this.uid,
    required this.fireData,
    required this.supaRow,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final name =
        '${fireData['firstname'] ?? ''} ${fireData['lastname'] ?? ''}'.trim();
    final email = fireData['email'] ?? '';
    final ppUrl = fireData['profilePictureUrl'] ?? '';
    final cat = supaRow['cat_pro']?.toString() ?? '';
    final catLabel = _kCatLabels[cat] ?? (cat.isNotEmpty ? cat : '—');
    final statut = supaRow['statut_pro']?.toString() ?? 'actif';
    final struct = supaRow['name_elevage']?.toString() ?? '';

    final (statutColor, statutLabel) = switch (statut) {
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
              uid: uid,
              fireData: fireData,
              supaRow: supaRow,
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
            CircleAvatar(
              radius: 26,
              backgroundColor: _kTeal,
              child: ClipOval(
                child: ppUrl.isNotEmpty
                    ? Image.network(ppUrl,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.work, color: Colors.white))
                    : const Icon(Icons.work, color: Colors.white),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.isNotEmpty ? name : 'Nom inconnu',
                        style: const TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w500,
                            fontSize: 15)),
                    if (struct.isNotEmpty)
                      Text(struct,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF0C5C6C))),
                    Text(email,
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Wrap(spacing: 4, runSpacing: 2, children: [
                      if (cat.isNotEmpty) _badge(catLabel, _kTeal),
                      _badge(statutLabel, statutColor),
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
                fontSize: 11,
                color: color,
                fontFamily: 'Galey',
                fontWeight: FontWeight.w500)),
      );
}
