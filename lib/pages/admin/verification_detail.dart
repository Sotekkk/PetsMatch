import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

class VerificationDetail extends StatefulWidget {
  final String uid;
  final Map<String, dynamic> data;

  const VerificationDetail({super.key, required this.uid, required this.data});

  @override
  State<VerificationDetail> createState() => _VerificationDetailState();
}

class _VerificationDetailState extends State<VerificationDetail> {
  bool _isLoading = false;
  final TextEditingController _rejectionController = TextEditingController();

  Future<void> _sendEmail({
    required String toEmail,
    required String subject,
    required String body,
  }) async {
    const username = 'petsmatch.contact@gmail.com';
    const password = 'dppu ctgp buve bxjd';
    final smtpServer = gmail(username, password);
    final message = Message()
      ..from = const Address(username, 'PetsMatch')
      ..recipients.add(toEmail)
      ..subject = subject
      ..text = body;
    try {
      await send(message, smtpServer);
    } catch (_) {}
  }

  Future<void> _sendApprovalEmail(String toEmail, String firstname) {
    return _sendEmail(
      toEmail: toEmail,
      subject: '✅ Votre compte PetsMatch a été approuvé',
      body: '''Bonjour $firstname,

Bonne nouvelle ! Votre dossier a été examiné et votre compte professionnel PetsMatch est maintenant activé.

Vous pouvez dès à présent vous connecter à l\'application et accéder à toutes les fonctionnalités réservées aux éleveurs et professionnels.

À très bientôt sur PetsMatch !

L\'équipe PetsMatch
petsmatch.contact@gmail.com
''',
    );
  }

  Future<void> _sendRejectionEmail(
      String toEmail, String firstname, String reason) {
    return _sendEmail(
      toEmail: toEmail,
      subject: '❌ Votre dossier PetsMatch n\'a pas été accepté',
      body: '''Bonjour $firstname,

Nous avons examiné votre dossier et nous ne sommes malheureusement pas en mesure de valider votre compte pour la raison suivante :

$reason

Si vous pensez qu\'il s\'agit d\'une erreur ou souhaitez soumettre de nouveaux documents, contactez-nous à support@petsmatch.fr en répondant à cet e-mail.

L\'équipe PetsMatch
petsmatch.contact@gmail.com
''',
    );
  }

  @override
  void dispose() {
    _rejectionController.dispose();
    super.dispose();
  }

  Future<void> _approve() async {
    setState(() => _isLoading = true);
    try {
      final now = DateTime.now();
      final validUntil = DateTime(now.year + 1, now.month, now.day);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .update({
        'verificationStatus': 'approved',
        'isValidate': true,
        'rejectionReason': '',
        'approvedAt': Timestamp.fromDate(now),
        'validUntil': Timestamp.fromDate(validUntil),
        'reminder21Sent': false,
        'reminder15Sent': false,
      });
      final email = widget.data['email'] ?? '';
      final firstname = widget.data['firstname'] ?? 'utilisateur';
      if (email.isNotEmpty) {
        await _sendApprovalEmail(email, firstname);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Compte approuvé et e-mail envoyé.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _reject() async {
    final reason = _rejectionController.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez indiquer un motif de refus.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .update({
        'verificationStatus': 'rejected',
        'isValidate': false,
        'rejectionReason': reason,
      });
      final email = widget.data['email'] ?? '';
      final firstname = widget.data['firstname'] ?? 'utilisateur';
      if (email.isNotEmpty) {
        await _sendRejectionEmail(email, firstname, reason);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Compte refusé et e-mail envoyé.'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showRejectDialog() {
    _rejectionController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFF1E3),
        title: const Text(
          'Motif de refus',
          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w500),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ce message sera visible par l\'utilisateur.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rejectionController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Ex: Documents illisibles, SIRET invalide...',
                filled: true,
                fillColor: const Color.fromARGB(255, 250, 192, 187),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler',
                style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _reject();
            },
            child: const Text('Confirmer le refus',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final name =
        '${data['firstname'] ?? ''} ${data['lastname'] ?? ''}'.trim();
    final status = data['verificationStatus'] ?? 'pending';
    final kbisUrl = data['kbisUrl'] ?? '';
    final ppUrl = data['profilePictureUrl'] ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFFFF1E3),
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 250, 192, 187),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text(
          'Dossier de vérification',
          style: TextStyle(
            fontFamily: 'Galey',
            fontWeight: FontWeight.w500,
            color: Colors.black,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Statut actuel
                  _StatusBanner(status: status),
                  const SizedBox(height: 20),

                  // Identité
                  _SectionTitle('Identité'),
                  _InfoRow(Icons.person, 'Nom complet', name),
                  _InfoRow(Icons.email, 'Email', data['email'] ?? ''),
                  _InfoRow(Icons.phone, 'Téléphone',
                      '${data['codeISO'] ?? ''} ${data['phone_number'] ?? ''}'),
                  _InfoRow(Icons.location_on, 'Adresse', data['adress'] ?? ''),
                  if (ppUrl.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(50),
                      child: Image.network(
                        ppUrl,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.person, size: 72),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // Entreprise
                  _SectionTitle('Entreprise'),
                  _InfoRow(Icons.business, 'Nom structure',
                      data['nameElevage'] ?? ''),
                  _InfoRow(Icons.numbers, 'SIRET', data['siret'] ?? ''),
                  _InfoRow(Icons.receipt, 'N° TVA', data['numeroTVA'] ?? ''),
                  _InfoRow(Icons.location_city, 'Adresse structure',
                      data['adressElevage'] ?? ''),
                  _InfoRow(Icons.description, 'Description',
                      data['descEntreprise'] ?? ''),
                  const SizedBox(height: 20),

                  // Document Kbis
                  _SectionTitle('Document officiel (Kbis / Attestation)'),
                  if (kbisUrl.isNotEmpty)
                    GestureDetector(
                      onTap: () => _showDocumentViewer(context, kbisUrl),
                      child: Container(
                        height: 180,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: const Color.fromARGB(255, 250, 192, 187),
                              width: 2),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.network(
                            kbisUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            errorBuilder: (_, __, ___) => Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.picture_as_pdf,
                                      size: 48, color: Colors.red),
                                  SizedBox(height: 8),
                                  Text('Document PDF — tap pour ouvrir',
                                      style: TextStyle(color: Colors.grey)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber, color: Colors.orange),
                          SizedBox(width: 10),
                          Text('Aucun document fourni',
                              style: TextStyle(color: Colors.orange)),
                        ],
                      ),
                    ),

                  const SizedBox(height: 32),

                  // Boutons d'action (seulement si en attente)
                  if (status == 'pending') ...[
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.check_circle,
                            color: Colors.white),
                        label: const Text(
                          'Approuver ce compte',
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        onPressed: _approve,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        icon:
                            const Icon(Icons.cancel, color: Colors.white),
                        label: const Text(
                          'Refuser ce compte',
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        onPressed: _showRejectDialog,
                      ),
                    ),
                  ],

                  if (status == 'approved')
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        icon:
                            const Icon(Icons.cancel, color: Colors.white),
                        label: const Text(
                          'Révoquer l\'approbation',
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        onPressed: _showRejectDialog,
                      ),
                    ),

                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }

  void _showDocumentViewer(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: InteractiveViewer(
          child: Image.network(url, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String status;

  const _StatusBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    String label;

    switch (status) {
      case 'approved':
        color = Colors.green;
        icon = Icons.check_circle;
        label = 'Compte approuvé';
        break;
      case 'rejected':
        color = Colors.red;
        icon = Icons.cancel;
        label = 'Compte refusé';
        break;
      default:
        color = Colors.orange;
        icon = Icons.hourglass_empty;
        label = 'En attente de validation';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontFamily: 'Galey',
              fontWeight: FontWeight.w500,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'Galey',
          fontWeight: FontWeight.w500,
          fontSize: 16,
          color: Color.fromARGB(255, 200, 100, 80),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontFamily: 'Galey',
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
