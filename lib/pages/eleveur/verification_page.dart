import 'package:PetsMatch/main.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const _teal = Color(0xFF0C5C6C);
const _dark = Color(0xFF1F2A2E);
const _bg = Color(0xFFF8F8F6);
const _emailSupport = 'petsmatch.contact@gmail.com';

/// Écran affiché à la fin de l'inscription d'un pro / éleveur / association :
/// dossier en cours de vérification, ou refusé.
///
/// En attente, le compte PEUT utiliser l'appli (AuthWrapper ne bloque que les
/// comptes refusés / suspendus) : l'écran propose donc « Accéder à
/// l'application » et le bouton retour y mène aussi (avant : bouton retour
/// sans issue). Refusé : motif, contact du support, déconnexion.
class VerificationRegistrationPage extends StatelessWidget {
  const VerificationRegistrationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(backgroundColor: _bg, body: Center(child: CircularProgressIndicator(color: _teal)));
    }
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(backgroundColor: _bg, body: Center(child: CircularProgressIndicator(color: _teal)));
        }
        final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final status = data['verificationStatus'] ?? 'pending';
        if (status == 'approved' || (data['isValidate'] ?? false)) {
          // Compte validé : retour au routeur principal (→ application).
          WidgetsBinding.instance.addPostFrameCallback((_) => _allerAuRouteur(context));
          return const Scaffold(backgroundColor: _bg, body: Center(child: CircularProgressIndicator(color: _teal)));
        }
        if (status == 'rejected') return _EcranRefus(motif: (data['rejectionReason'] ?? '').toString());
        return const _EcranAttente();
      },
    );
  }
}

/// Routeur principal (AuthWrapper) neuf, pile de navigation vidée.
void _allerAuRouteur(BuildContext context) {
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => AuthWrapper()), (_) => false);
}

Future<void> _seDeconnecter(BuildContext context) async {
  await FirebaseAuth.instance.signOut();
  // Le changement de profil détruit l'AuthWrapper racine : on en repose un
  // neuf (même règle que les autres boutons « Déconnexion »).
  if (context.mounted) _allerAuRouteur(context);
}

class _Gabarit extends StatelessWidget {
  final IconData icone;
  final Color couleur;
  final String titre;
  final String texte;
  final List<Widget> contenu;
  final List<Widget> boutons;
  const _Gabarit({required this.icone, required this.couleur, required this.titre, required this.texte,
      this.contenu = const [], required this.boutons});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(
                  child: Container(
                    width: 84, height: 84,
                    decoration: BoxDecoration(color: couleur.withValues(alpha: 0.1), shape: BoxShape.circle),
                    child: Icon(icone, color: couleur, size: 42),
                  ),
                ),
                const SizedBox(height: 20),
                Text(titre, textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 22, fontWeight: FontWeight.w800, color: _dark)),
                const SizedBox(height: 10),
                Text(texte, textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Galey', fontSize: 14, height: 1.45, color: Colors.grey.shade700)),
                const SizedBox(height: 24),
                ...contenu,
                const SizedBox(height: 24),
                ...boutons,
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _carte(List<Widget> enfants) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: enfants),
    );

Widget _etape(int n, String texte) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 22, height: 22, alignment: Alignment.center,
          decoration: const BoxDecoration(color: _teal, shape: BoxShape.circle),
          child: Text('$n', style: const TextStyle(fontFamily: 'Galey', color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(texte, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, height: 1.4, color: _dark))),
      ]),
    );

Widget _boutonPrincipal(String label, IconData icone, VoidCallback onTap) => ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icone, size: 18),
      label: Text(label, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
      style: ElevatedButton.styleFrom(
        backgroundColor: _teal, foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );

Widget _boutonSecondaire(String label, IconData icone, VoidCallback onTap) => TextButton.icon(
      onPressed: onTap,
      icon: Icon(icone, size: 18, color: Colors.grey.shade700),
      label: Text(label, style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
    );

class _EcranAttente extends StatelessWidget {
  const _EcranAttente();

  @override
  Widget build(BuildContext context) {
    // Bouton retour : vers l'application (plus d'impasse).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _allerAuRouteur(context); },
      child: _Gabarit(
        icone: Icons.hourglass_top_rounded,
        couleur: const Color(0xFFD97706),
        titre: 'Dossier en cours de vérification',
        texte: 'Merci pour votre inscription ! Notre équipe vérifie vos informations et vos documents.',
        contenu: [
          _carte([
            const Text('Et ensuite ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _dark)),
            const SizedBox(height: 12),
            _etape(1, 'Nous vérifions votre dossier (numéros officiels, documents).'),
            _etape(2, 'Vous recevez un e-mail et une notification dès que votre compte est validé.'),
            _etape(3, 'Votre profil devient alors visible publiquement dans PetsMatch.'),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFEEF5EA), borderRadius: BorderRadius.circular(12)),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, size: 18, color: Color(0xFF4A7A32)),
              SizedBox(width: 8),
              Expanded(child: Text(
                'En attendant, vous pouvez déjà découvrir l\'application et compléter votre profil.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, height: 1.4, color: Color(0xFF2F4F22)))),
            ]),
          ),
        ],
        boutons: [
          _boutonPrincipal('Accéder à l\'application', Icons.arrow_forward_rounded, () => _allerAuRouteur(context)),
          const SizedBox(height: 6),
          _boutonSecondaire('Se déconnecter', Icons.logout, () => _seDeconnecter(context)),
        ],
      ),
    );
  }
}

class _EcranRefus extends StatelessWidget {
  final String motif;
  const _EcranRefus({required this.motif});

  @override
  Widget build(BuildContext context) {
    return _Gabarit(
      icone: Icons.cancel_outlined,
      couleur: const Color(0xFFDC2626),
      titre: 'Dossier refusé',
      texte: 'Votre dossier n\'a pas pu être validé. Vous pouvez le corriger et nous recontacter pour une nouvelle vérification.',
      contenu: [
        _carte([
          const Text('Motif du refus', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFFDC2626))),
          const SizedBox(height: 6),
          Text(motif.trim().isNotEmpty ? motif : 'Aucun motif précisé. Contactez le support.',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14, height: 1.4, color: _dark)),
        ]),
      ],
      boutons: [
        _boutonPrincipal('Contacter le support', Icons.mail_outline, () {
          launchUrl(Uri(scheme: 'mailto', path: _emailSupport,
              query: 'subject=${Uri.encodeComponent('Dossier refusé — nouvelle vérification')}'));
        }),
        const SizedBox(height: 6),
        _boutonSecondaire('Se déconnecter', Icons.logout, () => _seDeconnecter(context)),
      ],
    );
  }
}
