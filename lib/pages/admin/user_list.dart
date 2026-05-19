import 'package:PetsMatch/pages/admin/user_detail.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class UserList extends StatefulWidget {
  const UserList({super.key});

  @override
  State<UserList> createState() => _UserListState();
}

class _UserListState extends State<UserList> {
  String _search = '';
  String _filter = 'tous';

  static const _filters = [
    ('tous', 'Tous'),
    ('particulier', 'Particulier'),
    ('eleveur', 'Éleveur'),
    ('pro', 'Pro'),
    ('admin', 'Admin'),
  ];

  bool _matchesFilter(Map<String, dynamic> data) {
    switch (_filter) {
      case 'admin':
        return data['isAdmin'] == true;
      case 'eleveur':
        return data['isElevage'] == true && data['isAdmin'] != true;
      case 'pro':
        return data['isPro'] == true && data['isAdmin'] != true;
      case 'particulier':
        return data['isElevage'] != true &&
            data['isPro'] != true &&
            data['isAdmin'] != true;
      default:
        return true;
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
              hintText: 'Rechercher par nom ou email...',
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
              children: _filters.map((f) {
                final selected = _filter == f.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(
                      f.$2,
                      style: TextStyle(
                        fontFamily: 'Galey',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: selected ? Colors.white : Colors.black87,
                      ),
                    ),
                    selected: selected,
                    onSelected: (_) => setState(() => _filter = f.$1),
                    backgroundColor: Colors.white,
                    selectedColor: const Color(0xFF6E9E57),
                    checkmarkColor: Colors.white,
                    side: BorderSide(
                      color: selected
                          ? const Color(0xFF6E9E57)
                          : Colors.grey.shade300,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('users').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(
                  child: Text('Aucun utilisateur.',
                      style:
                          TextStyle(color: Colors.grey, fontFamily: 'Galey')),
                );
              }

              final docs = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                if (!_matchesFilter(data)) return false;
                if (_search.isEmpty) return true;
                final name =
                    '${data['firstname'] ?? ''} ${data['lastname'] ?? ''}'
                        .toLowerCase();
                final email =
                    (data['email'] ?? '').toString().toLowerCase();
                return name.contains(_search) || email.contains(_search);
              }).toList();

              if (docs.isEmpty) {
                return const Center(
                  child: Text('Aucun résultat.',
                      style:
                          TextStyle(color: Colors.grey, fontFamily: 'Galey')),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final uid = docs[index].id;
                  return _UserCard(data: data, uid: uid);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _UserCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String uid;

  const _UserCard({required this.data, required this.uid});

  @override
  Widget build(BuildContext context) {
    final name =
        '${data['firstname'] ?? ''} ${data['lastname'] ?? ''}'.trim();
    final email = data['email'] ?? '';
    final ppUrl = data['profilePictureUrl'] ?? '';
    final isAdmin = data['isAdmin'] == true;
    final isElevage = data['isElevage'] == true;
    final isPro = data['isPro'] == true;
    final isValidate = data['isValidate'] == true;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UserDetail(uid: uid, data: data),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor:
                    const Color(0xFFA7C79A),
                child: ClipOval(
                  child: ppUrl.isNotEmpty
                      ? Image.network(
                          ppUrl,
                          width: 52,
                          height: 52,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.person,
                              color: Colors.white),
                        )
                      : const Icon(Icons.person, color: Colors.white),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isNotEmpty ? name : 'Nom inconnu',
                      style: const TextStyle(
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      email,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: [
                        if (isAdmin)
                          _Chip(label: 'Admin', color: Colors.deepPurple),
                        if (isElevage)
                          _Chip(label: 'Éleveur', color: Color(0xFF0C5C6C)),
                        if (isPro)
                          _Chip(label: 'Pro', color: Colors.blue),
                        if (!isElevage && !isPro && !isAdmin)
                          _Chip(label: 'Particulier', color: Colors.teal),
                        if (!isValidate && (isElevage || isPro))
                          _Chip(
                              label: 'Non validé',
                              color: Colors.orange),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;

  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontFamily: 'Galey',
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
