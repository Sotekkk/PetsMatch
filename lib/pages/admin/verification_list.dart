import 'package:PetsMatch/pages/admin/verification_detail.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class VerificationList extends StatelessWidget {
  const VerificationList({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Container(
            color: const Color(0xFFFFF1E3),
            child: const TabBar(
              labelColor: Color.fromARGB(255, 200, 100, 80),
              unselectedLabelColor: Colors.grey,
              indicatorColor: Color.fromARGB(255, 200, 100, 80),
              tabs: [
                Tab(text: 'En attente'),
                Tab(text: 'Approuvés'),
                Tab(text: 'Refusés'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _VerificationTab(status: 'pending'),
                _VerificationTab(status: 'approved'),
                _VerificationTab(status: 'rejected'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VerificationTab extends StatelessWidget {
  final String status;

  const _VerificationTab({required this.status});

  @override
  Widget build(BuildContext context) {
    final query = status == 'all'
        ? FirebaseFirestore.instance.collection('users')
        : FirebaseFirestore.instance
            .collection('users')
            .where('verificationStatus', isEqualTo: status);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inbox, size: 60, color: Colors.grey[300]),
                const SizedBox(height: 12),
                Text(
                  status == 'pending'
                      ? 'Aucune demande en attente'
                      : status == 'approved'
                          ? 'Aucun compte approuvé'
                          : 'Aucun compte refusé',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontFamily: 'Galey',
                  ),
                ),
              ],
            ),
          );
        }

        final docs = snapshot.data!.docs;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final uid = docs[index].id;
            return _VerificationCard(data: data, uid: uid, status: status);
          },
        );
      },
    );
  }
}

class _VerificationCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String uid;
  final String status;

  const _VerificationCard({
    required this.data,
    required this.uid,
    required this.status,
  });

  Color get _statusColor {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData get _statusIcon {
    switch (status) {
      case 'pending':
        return Icons.hourglass_empty;
      case 'approved':
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = '${data['firstname'] ?? ''} ${data['lastname'] ?? ''}'.trim();
    final siret = data['siret'] ?? '';
    final email = data['email'] ?? '';
    final nameElevage = data['nameElevage'] ?? '';
    final isElevage = data['isElevage'] ?? false;
    final isPro = data['isPro'] ?? false;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VerificationDetail(uid: uid, data: data),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
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
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(_statusIcon, color: _statusColor, size: 22),
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
                    if (nameElevage.isNotEmpty)
                      Text(
                        nameElevage,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color.fromARGB(255, 200, 100, 80),
                          fontFamily: 'Galey',
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    if (siret.isNotEmpty)
                      Text(
                        'SIRET: $siret',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (isElevage)
                          _TypeChip(label: 'Éleveur', color: Colors.purple),
                        if (isPro)
                          _TypeChip(label: 'Pro', color: Colors.blue),
                        if (status == 'rejected' &&
                            (data['rejectionReason'] ?? '').isNotEmpty)
                          Expanded(
                            child: Text(
                              'Motif: ${data['rejectionReason']}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.red,
                                fontStyle: FontStyle.italic,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
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

class _TypeChip extends StatelessWidget {
  final String label;
  final Color color;

  const _TypeChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
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
