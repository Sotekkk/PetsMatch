import 'package:PetsMatch/pages/admin/supabase_migration_page.dart';
import 'package:PetsMatch/pages/admin/user_list.dart';
import 'package:PetsMatch/pages/admin/verification_list.dart';
import 'package:PetsMatch/pages/bottom_nav.dart';
import 'package:PetsMatch/services/renewal_service.dart';
import 'package:PetsMatch/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AdminPanel extends StatefulWidget {
  const AdminPanel({super.key});

  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const _DashboardTab(),
    const VerificationList(),
    const UserList(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFA7C79A),
        elevation: 0,
        title: const Text(
          'Administration PetsMatch',
          style: TextStyle(
            fontFamily: 'Galey',
            fontWeight: FontWeight.w500,
            color: Colors.black,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Mode utilisateur',
            icon: const Icon(Icons.person, color: Colors.black),
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => BottomNav()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFFF8F8F6),
        selectedItemColor: const Color(0xFF6E9E57),
        unselectedItemColor: Colors.grey,
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Tableau de bord',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.verified_user),
            label: 'Vérifications',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'Utilisateurs',
          ),
        ],
      ),
    );
  }
}

class _DashboardTab extends StatefulWidget {
  const _DashboardTab();

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  @override
  void initState() {
    super.initState();
    RenewalService.checkAndSendReminders();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Text(
            'Vue d\'ensemble',
            style: TextStyle(
              fontFamily: 'Galey',
              fontSize: UTILS.calculWidth(24, UTILS.widthReference(context)),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'En attente',
                  color: Colors.orange,
                  icon: Icons.hourglass_empty,
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .where('verificationStatus', isEqualTo: 'pending')
                      .snapshots(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'Approuvés',
                  color: Colors.green,
                  icon: Icons.check_circle,
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .where('verificationStatus', isEqualTo: 'approved')
                      .snapshots(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Refusés',
                  color: Colors.red,
                  icon: Icons.cancel,
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .where('verificationStatus', isEqualTo: 'rejected')
                      .snapshots(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'Utilisateurs',
                  color: Colors.blue,
                  icon: Icons.people,
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .snapshots(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Migration Supabase
          ListTile(
            tileColor: const Color(0xFF0C5C6C).withValues(alpha: 0.08),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: const Icon(Icons.cloud_upload_outlined, color: Color(0xFF0C5C6C)),
            title: const Text('Migration Supabase',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            subtitle: const Text('Exporter Firestore → Supabase',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: Color(0xFF0C5C6C)),
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => const SupabaseMigrationPage())),
          ),
          const SizedBox(height: 20),

          // Expirations à venir
          Text(
            'Expirations à venir',
            style: TextStyle(
              fontFamily: 'Galey',
              fontSize: UTILS.calculWidth(20, UTILS.widthReference(context)),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          _ExpiringAccountsList(),
          const SizedBox(height: 30),

          // Dernières demandes en attente
          Text(
            'Dernières demandes',
            style: TextStyle(
              fontFamily: 'Galey',
              fontSize: UTILS.calculWidth(20, UTILS.widthReference(context)),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('verificationStatus', isEqualTo: 'pending')
                .limit(5)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return const Text('Aucune demande en attente.',
                    style: TextStyle(color: Colors.grey, fontFamily: 'Galey'));
              }
              return Column(
                children: docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return _RecentCard(data: data, uid: doc.id);
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ExpiringAccountsList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final in21Days = Timestamp.fromDate(
        DateTime.now().add(const Duration(days: 21)));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('verificationStatus', isEqualTo: 'approved')
          .where('isElevage', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final expiring = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final validUntil = data['validUntil'];
          if (validUntil == null) return false;
          return (validUntil as Timestamp).compareTo(in21Days) <= 0;
        }).toList();

        if (expiring.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withOpacity(0.2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 18),
                SizedBox(width: 8),
                Text('Aucune expiration dans les 21 prochains jours.',
                    style: TextStyle(
                        color: Colors.green,
                        fontFamily: 'Galey',
                        fontSize: 13)),
              ],
            ),
          );
        }

        return Column(
          children: expiring.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final name =
                '${data['firstname'] ?? ''} ${data['lastname'] ?? ''}'.trim();
            final nameElevage = data['nameElevage'] ?? '';
            final validUntil =
                (data['validUntil'] as Timestamp).toDate();
            final daysLeft =
                validUntil.difference(DateTime.now()).inDays;
            final color = daysLeft <= 15 ? Colors.red : Colors.orange;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withOpacity(0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.timer, color: color, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.isNotEmpty ? name : 'Inconnu',
                          style: const TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                        if (nameElevage.isNotEmpty)
                          Text(nameElevage,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      daysLeft <= 0
                          ? 'Expiré'
                          : 'J-$daysLeft',
                      style: TextStyle(
                        color: color,
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final Stream<QuerySnapshot> stream;

  const _StatCard({
    required this.label,
    required this.color,
    required this.icon,
    required this.stream,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        return Container(
          padding: const EdgeInsets.all(16),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.grey,
                  fontFamily: 'Galey',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RecentCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String uid;

  const _RecentCard({required this.data, required this.uid});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_empty, color: Colors.orange, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${data['firstname'] ?? ''} ${data['lastname'] ?? ''}',
                  style: const TextStyle(
                    fontFamily: 'Galey',
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  data['siret'] ?? 'SIRET non renseigné',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
    );
  }
}

class _AddressMigrationButton extends StatefulWidget {
  @override
  State<_AddressMigrationButton> createState() =>
      _AddressMigrationButtonState();
}

class _AddressMigrationButtonState extends State<_AddressMigrationButton> {
  bool _running = false;
  String _status = '';

  static Map<String, String> _parseAddress(String address) {
    if (address.trim().isEmpty) return {};
    final parts = address
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return {};

    String rue = '';
    String ville = '';
    String codePostal = '';
    String pays = '';

    if (parts.isNotEmpty && !RegExp(r'\d').hasMatch(parts.last)) {
      pays = parts.last;
    }

    final endIdx = pays.isNotEmpty ? parts.length - 1 : parts.length;

    for (int i = 0; i < endIdx; i++) {
      final part = parts[i];
      final postalMatch = RegExp(r'^(\d{4,5})\s+(.+)$').firstMatch(part);
      if (postalMatch != null) {
        codePostal = postalMatch.group(1)!;
        ville = postalMatch.group(2)!;
        if (i > 0) rue = parts.sublist(0, i).join(', ');
        break;
      }
      if (i == 0 && RegExp(r'^\d').hasMatch(part)) {
        rue = part;
        continue;
      }
      if (ville.isEmpty && !RegExp(r'^\d').hasMatch(part)) {
        ville = part;
      }
    }

    return {
      if (rue.isNotEmpty) 'rue': rue,
      if (ville.isNotEmpty) 'ville': ville,
      if (codePostal.isNotEmpty) 'codePostal': codePostal,
      if (pays.isNotEmpty) 'pays': pays,
    };
  }

  Future<void> _runMigration() async {
    setState(() {
      _running = true;
      _status = 'Migration en cours...';
    });

    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('users').get();

      int updated = 0;
      int skipped = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final Map<String, dynamic> updates = {};

        final adress = (data['adress'] ?? '').toString();
        if (adress.isNotEmpty) {
          final parsed = _parseAddress(adress);
          parsed.forEach((k, v) {
            if ((data[k] ?? '').toString().isEmpty) updates[k] = v;
          });
        }

        final adressElevage = (data['adressElevage'] ?? '').toString();
        if (adressElevage.isNotEmpty) {
          final parsed = _parseAddress(adressElevage);
          parsed.forEach((k, v) {
            final elevageKey = '${k}Elevage';
            if ((data[elevageKey] ?? '').toString().isEmpty) {
              updates[elevageKey] = v;
            }
          });
        }

        if (updates.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(doc.id)
              .update(updates);
          updated++;
        } else {
          skipped++;
        }
      }

      setState(() {
        _status = '$updated utilisateur(s) migrés, $skipped déjà à jour.';
        _running = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Erreur : $e';
        _running = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.sync, color: Colors.blue, size: 18),
              SizedBox(width: 8),
              Text(
                'Migration des adresses',
                style: TextStyle(
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Remplit rue/ville/code postal/pays à partir du champ adresse existant pour tous les utilisateurs.',
            style: TextStyle(
                fontSize: 12, color: Colors.grey, fontFamily: 'Galey'),
          ),
          const SizedBox(height: 10),
          if (_status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _status,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'Galey',
                  color: _status.startsWith('Erreur')
                      ? Colors.red
                      : Colors.green.shade700,
                ),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _running ? null : _runMigration,
              icon: _running
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.play_arrow, size: 18),
              label: Text(
                _running ? 'En cours...' : 'Lancer la migration',
                style: const TextStyle(fontFamily: 'Galey'),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
