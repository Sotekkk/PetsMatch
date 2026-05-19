import 'package:PetsMatch/animation/delayed_animation.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_google_places_hoc081098/flutter_google_places_hoc081098.dart';

class VerificationRegistrationPage extends StatelessWidget {
  const VerificationRegistrationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final status = data['verificationStatus'] ?? 'pending';
        final rejectionReason = data['rejectionReason'] ?? '';

        if (status == 'approved' || (data['isValidate'] ?? false)) {
          // Compte approuvé — l'AuthWrapper redirigera vers BottomNav
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        if (status == 'rejected') {
          return _RejectedPage(reason: rejectionReason);
        }

        return _PendingPage();
      },
    );
  }
}

class _PendingPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Center(
          child: DelayedAnimation(
            delay: 0,
            child: Column(
              children: [
                _Header(),
                SizedBox(
                    height:
                        UTILS.calculHeight(14, UTILS.heightReference(context))),
                Align(
                  alignment: const Alignment(-0.8, 0),
                  child: Text(
                    'Vérification',
                    style: TextStyle(
                        fontSize: UTILS.calculWidth(
                            30, UTILS.widthReference(context)),
                        fontFamily: 'Galey',
                        color: const Color.fromARGB(174, 0, 0, 0),
                        fontWeight: FontWeight.w500),
                  ),
                ),
                SizedBox(
                    height:
                        UTILS.calculHeight(35, UTILS.heightReference(context))),
                SizedBox(
                  height:
                      UTILS.calculHeight(286, UTILS.heightReference(context)),
                  width: UTILS.calculWidth(286, UTILS.widthReference(context)),
                  child: Image.asset('assets/page/verification.png'),
                ),
                SizedBox(
                    height: UTILS.calculHeight(
                        19.6, UTILS.heightReference(context))),
                Container(
                  width:
                      UTILS.calculWidth(350, UTILS.widthReference(context)),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.hourglass_empty,
                          color: Colors.orange, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Votre dossier est en cours d\'examen par notre équipe. Vous recevrez un e-mail dès que votre compte sera activé.',
                          style: TextStyle(
                            fontFamily: 'Galey',
                            fontSize: UTILS.calculHeight(
                                16.0, UTILS.heightReference(context)),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                    height: UTILS.calculHeight(
                        180, UTILS.heightReference(context))),
                _Footer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RejectedPage extends StatelessWidget {
  final String reason;

  const _RejectedPage({required this.reason});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Center(
          child: DelayedAnimation(
            delay: 0,
            child: Column(
              children: [
                _Header(),
                SizedBox(
                    height:
                        UTILS.calculHeight(14, UTILS.heightReference(context))),
                Align(
                  alignment: const Alignment(-0.8, 0),
                  child: Text(
                    'Dossier refusé',
                    style: TextStyle(
                        fontSize: UTILS.calculWidth(
                            28, UTILS.widthReference(context)),
                        fontFamily: 'Galey',
                        color: Colors.red.withOpacity(0.8),
                        fontWeight: FontWeight.w500),
                  ),
                ),
                SizedBox(
                    height:
                        UTILS.calculHeight(30, UTILS.heightReference(context))),
                SizedBox(
                  width: UTILS.calculWidth(80, UTILS.widthReference(context)),
                  height: UTILS.calculWidth(80, UTILS.widthReference(context)),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0x1AFF0000),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.cancel, color: Colors.red, size: 48),
                  ),
                ),
                SizedBox(
                    height:
                        UTILS.calculHeight(24, UTILS.heightReference(context))),
                Container(
                  width:
                      UTILS.calculWidth(350, UTILS.widthReference(context)),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Motif du refus :',
                        style: TextStyle(
                          fontFamily: 'Galey',
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        reason.isNotEmpty
                            ? reason
                            : 'Aucun motif précisé. Contactez le support.',
                        style: const TextStyle(
                          fontFamily: 'Galey',
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                    height:
                        UTILS.calculHeight(20, UTILS.heightReference(context))),
                SizedBox(
                  width: UTILS.calculWidth(350, UTILS.widthReference(context)),
                  child: const Text(
                    'Vous pouvez corriger votre dossier et contacter notre support à support@petsmatch.fr pour soumettre à nouveau votre demande.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Galey',
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                  ),
                ),
                SizedBox(
                    height: UTILS.calculHeight(
                        120, UTILS.heightReference(context))),
                ElevatedButton.icon(
                  icon: const Icon(Icons.logout, color: Colors.black),
                  label: const Text(
                    'Se déconnecter',
                    style: TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        const Color.fromARGB(255, 250, 192, 187),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 14),
                  ),
                  onPressed: () => FirebaseAuth.instance.signOut(),
                ),
                SizedBox(
                    height:
                        UTILS.calculHeight(40, UTILS.heightReference(context))),
                _Footer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: UTILS.widthReference(context),
      height: UTILS.calculHeight(104, UTILS.heightReference(context)),
      child: Stack(children: [
        Image.asset(
          'assets/deco/arrondi_rose_2.png',
          fit: BoxFit.cover,
          width: UTILS.calculWidth(211, UTILS.widthReference(context)),
          height: UTILS.calculHeight(104, UTILS.heightReference(context)),
        ),
        Positioned(
          top: UTILS.calculHeight(53, UTILS.heightReference(context)),
          left: 0,
          right: 0,
          child: Align(
            alignment: Alignment.center,
            child: Text(
              'INSCRIPTION',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w500,
                fontSize: UTILS.calculWidth(20, UTILS.widthReference(context)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Footer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/deco/arrondi_green_deco_2.png',
      fit: BoxFit.cover,
      width: UTILS.calculWidth(233, UTILS.widthReference(context)),
      height: UTILS.calculHeight(52, UTILS.heightReference(context)),
    );
  }
}
