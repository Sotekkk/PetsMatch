import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/bottom_nav.dart';
import 'package:PetsMatch/pages/eleveur/info_elevage.dart';
import 'package:PetsMatch/pages/eleveur/verification_page.dart';
import 'package:PetsMatch/pages/particulier/description_page.dart';
import 'package:PetsMatch/utils/french_geo.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

class VerifyEmailPage extends StatefulWidget {
  final String email;

  const VerifyEmailPage({super.key, required this.email});

  @override
  _VerifyEmailPageState createState() => _VerifyEmailPageState();
}



Future<bool> registerUser(String email, String password) async {
  try {
    String uid = User_Info.uid;

    // Ajouter des informations à Firestore dans la collection 'users'
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'uid': uid,
      'role': 'user',
      'isAdmin': false,
      'verificationStatus': 'none',
      'firstname': User_Info.firstname,
      'lastname': User_Info.lastname,
      'dateofbirth': User_Info.dateofbirth,
      'codeISO': User_Info.codeISO,
      'codeISOElevage': User_Info.codeISOElevage,
      'phone_number': User_Info.phone_number,
      'adress': User_Info.adress,
      'profilePictureUrl': User_Info.profilePictureUrl,
      'profilePictureUrlElevage': User_Info.profilePictureUrlElevage,
      'isElevage': User_Info.isElevage,
      'isAssociation': User_Info.isAssociation,
      'adressElevage': User_Info.adressElevage,
      'nameElevage': User_Info.nameElevage,
      'numeroElevage': User_Info.numeroElevage,
      'isDev': User_Info.isDev,
      'email': User_Info.email,
      'isValidate': User_Info.isValidate,
      'siret': User_Info.siret,
      'numeroTVA': User_Info.numeroTVA,

      // 'password': User_Info.password,
      'desc': User_Info.desc,
      'documentElevage': User_Info.documentElevage,
      'validateAccountElevage': User_Info.validateAccountElevage,
      'adoptProject': User_Info.adoptProject,
      'descEntreprise': User_Info.descEntreprise,
      'isPub': User_Info.isPub,
      'isPro': User_Info.isPro,
      'catPro': User_Info.catPro,
      'professionPro': User_Info.professionPro,
      'isPartenaire': User_Info.isPartenaire,

      'CGU': true,
      'mentionlegal': true,
    });

    // Sync Supabase (particulier — pas d'élevage ni pro)
    try {
      await Supabase.instance.client.from('users').upsert({
        'uid':                 uid,
        'firstname':           User_Info.firstname,
        'lastname':            User_Info.lastname,
        'email':               User_Info.email,
        'phone_number':        User_Info.phone_number,
        'code_iso':            User_Info.codeISO,
        'adress':              User_Info.adress,
        'profile_picture_url': User_Info.profilePictureUrl,
        'is_elevage':          false,
        'is_validate':         true,
        'is_pub':              User_Info.isPub,
        'is_pro':              false,
        'is_partenaire':       false,
        'is_admin':            false,
        'is_dev':              User_Info.isDev,
        'is_association':      false,
        'cgu_accepted_at':     DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint("Supabase sync error (particulier): $e");
    }

    return true;
  } catch (e) {
    print("Erreur lors de la création de l'utilisateur: $e");
    return false;
  }
}

Future<Object> registerElevage(String email, String password) async {
  try {
    String uid = User_Info.uid;

    // Ajouter des informations à Firestore dans la collection 'users'
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'uid': uid,
      'role': 'user',
      'isAdmin': false,
      // Particuliers auto-validés, seuls éleveurs/pros/assos nécessitent review admin
      'verificationStatus': (User_Info.isElevage || User_Info.isPro || User_Info.isAssociation) ? 'pending' : 'approved',
      'kbisUrl': User_Info.kbisUrl,
      'firstname': User_Info.firstname,
      'lastname': User_Info.lastname,
      'dateofbirth': User_Info.dateofbirth,
      'codeISO': User_Info.codeISO,
      'codeISOElevage': User_Info.codeISOElevage,
      'phone_number': User_Info.phone_number,
      'adress': User_Info.adress,
      'profilePictureUrl': User_Info.profilePictureUrl,
      'profilePictureUrlElevage': User_Info.profilePictureUrlElevage,
      'isElevage': User_Info.isElevage,
      'isAssociation': User_Info.isAssociation,
      'adressElevage': User_Info.adressElevage,
      'nameElevage': User_Info.nameElevage,
      'numeroElevage': User_Info.numeroElevage,
      'isDev': User_Info.isDev,
      'email': User_Info.email,
      'isValidate': !User_Info.isElevage && !User_Info.isPro && !User_Info.isAssociation,
      'siret': User_Info.siret,
      'numeroTVA': User_Info.numeroTVA,
      // 'password': User_Info.password,
      'desc': User_Info.desc,
      'documentElevage': User_Info.documentElevage,
      'validateAccountElevage': User_Info.validateAccountElevage,
      'adoptProject': User_Info.adoptProject,
      'descEntreprise': User_Info.descEntreprise,
      'isPub': User_Info.isPub,
      'isPro': User_Info.isPro,
      'catPro': User_Info.catPro,
      'professionPro': User_Info.professionPro,
      'isPartenaire': User_Info.isPartenaire,
      'rna': User_Info.rna,
      'agrementPrefectoral': User_Info.agrementPrefectoral,
      'acacedNumero': User_Info.acacedNumero,
      'acacedDateObtention': User_Info.acacedDateObtention,
      'acacedDocUrl': User_Info.acacedDocUrl,
      'isDog': User_Info.isDog,
      'isCat': User_Info.isCat,
      'dogBreeds': User_Info.dogBreeds,
      'catBreeds': User_Info.catBreeds,
      'especesElevees': User_Info.especesElevees,
      if (User_Info.bannerUrl.isNotEmpty) 'bannerUrl': User_Info.bannerUrl,

      // Adresse de l'élevage (dénormalisée pour les filtres)
      'rueElevage':          User_Info.rueElevage,
      'codePostalElevage':   User_Info.codePostalElevage,
      'villeElevage':        User_Info.villeElevage,
      'paysElevage':         User_Info.paysElevage,
      'city':                User_Info.villeElevage,
      ...() {
        final geo = FrenchGeo.fromPostalCode(User_Info.codePostalElevage);
        return {
          'departementElevage': geo?.departement ?? '',
          'regionElevage':      geo?.region      ?? '',
        };
      }(),

      'CGU': true,
      'mentionlegal': true,
      // Ajouter d'autres champs comme nécessaire
    });

    // Sync to Supabase users table
    try {
      final geoPerso  = FrenchGeo.fromPostalCode(User_Info.codePostal);
      final geoElev   = FrenchGeo.fromPostalCode(User_Info.codePostalElevage);

      // especes_elevees : format [{espece, races}] pour éleveurs
      final especesEleveesJson = User_Info.isElevage
          ? User_Info.especesElevees.map((e) => {
              'espece': e,
              'races': e == 'chien'
                  ? User_Info.dogBreeds
                  : e == 'chat'
                      ? User_Info.catBreeds
                      : <String>[],
            }).toList()
          : null;

      // especes_acceptees : liste capitalisée pour pros
      final especesAccepteesJson = User_Info.isPro
          ? User_Info.especesElevees
              .map((e) => e.isEmpty ? e : e[0].toUpperCase() + e.substring(1))
              .toList()
          : null;

      await Supabase.instance.client.from('users').upsert({
        'uid':                   uid,
        'firstname':             User_Info.firstname,
        'lastname':              User_Info.lastname,
        'email':                 User_Info.email,
        'phone_number':          User_Info.phone_number,
        'code_iso':              User_Info.codeISO,
        'adress':                User_Info.adress,
        'rue':                   User_Info.rue,
        'ville':                 User_Info.ville,
        'code_postal':           User_Info.codePostal,
        'pays':                  User_Info.pays,
        'departement':           geoPerso?.departement ?? '',
        'region':                geoPerso?.region      ?? '',
        'profile_picture_url':   User_Info.profilePictureUrl,
        'is_elevage':            User_Info.isElevage,
        'is_validate':           !User_Info.isElevage && !User_Info.isPro && !User_Info.isAssociation,
        'name_elevage':          User_Info.nameElevage,
        'adress_elevage':        User_Info.adressElevage,
        'rue_elevage':           User_Info.rueElevage,
        'ville_elevage':         User_Info.villeElevage,
        'code_postal_elevage':   User_Info.codePostalElevage,
        'pays_elevage':          User_Info.paysElevage,
        'departement_elevage':   geoElev?.departement ?? '',
        'region_elevage':        geoElev?.region      ?? '',
        'numero_elevage':        User_Info.numeroElevage,
        'code_iso_elevage':      User_Info.codeISOElevage,
        'is_pub':                User_Info.isPub,
        'is_pro':                User_Info.isPro,
        'is_partenaire':         User_Info.isPartenaire,
        'is_admin':              false,
        'is_dev':                User_Info.isDev,
        // Champs pro/éleveur
        'cat_pro':               User_Info.catPro,
        'profession_pro':        User_Info.professionPro,
        'desc_entreprise':       User_Info.descEntreprise,
        'siret':                 User_Info.siret,
        'numero_tva':            User_Info.numeroTVA,
        'is_dog':                User_Info.isDog,
        'is_cat':                User_Info.isCat,
        'dog_breeds':            User_Info.dogBreeds,
        'cat_breeds':            User_Info.catBreeds,
        if (especesEleveesJson != null)    'especes_elevees':    especesEleveesJson,
        if (especesAccepteesJson != null)  'especes_acceptees':  especesAccepteesJson,
        if (User_Info.certifications.isNotEmpty) 'certifications': User_Info.certifications,
        if (User_Info.isPro || User_Info.isElevage) 'statut_pro': 'en_attente',
        if (User_Info.bannerUrl.isNotEmpty) 'banner_url': User_Info.bannerUrl,
        'is_association': User_Info.isAssociation,
        if (User_Info.isAssociation) ...{
          'rna':                  User_Info.rna,
          'agrement_prefectoral': User_Info.agrementPrefectoral,
          'capacite_accueil':     User_Info.capaciteAccueil,
          'especes_accueillies':  User_Info.especesElevees,
          'statut_pro':           'en_attente',
        },
        if (User_Info.profilePictureUrlElevage.isNotEmpty)
          'profile_picture_url_elevage': User_Info.profilePictureUrlElevage,
        'cgu_accepted_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print("Supabase user sync error: $e");
      // Affiche l'erreur en développement pour diagnostic
      // ignore: avoid_print
      debugPrint("Supabase sync DETAIL: ${e.toString()}");
    }

    // Le numéro d'ordre vétérinaire saisi à l'inscription n'est packé que
    // dans `certifications` (JSONB sur `users`) — le trigger d'auto-création
    // du profil principal (create_main_profile_on_signup) ne copie pas cette
    // colonne, donc `user_profiles.numero_ordre` (colonne dédiée, déjà en
    // base) resterait vide. On le reporte ici explicitement.
    if (User_Info.catPro == 'veterinaire') {
      final ordre = User_Info.certifications.firstWhere(
        (c) => c['nom'] == 'Numéro d\'ordre vétérinaire',
        orElse: () => const {},
      )['numero'] as String?;
      if (ordre != null && ordre.isNotEmpty) {
        try {
          await Supabase.instance.client.from('user_profiles')
              .update({'numero_ordre': ordre})
              .eq('uid', uid).eq('is_main', true);
        } catch (_) {}
      }
    }

    return uid; // Succès de l'enregistrement
  } catch (e) {
    print("Erreur lors de la création de l'utilisateur: $e");
    return false; // Échec de l'enregistrement
  }
}

class _VerifyEmailPageState extends State<VerifyEmailPage> with WidgetsBindingObserver {
  static const _teal = Color(0xFF0C5C6C);
  bool _isVerified = false;
  bool _isResendEnabled = true;
  late Timer _timer;
  Timer? _pollTimer;
  // Adresse affichée — distincte de widget.email une fois corrigée (une
  // testeuse bêta s'était trompée d'adresse à l'inscription et devait tout
  // recommencer faute de pouvoir la corriger ici).
  late String _currentEmail = widget.email;
  bool _editingEmail = false;
  bool _savingEmail = false;
  String? _emailError;
  final _newEmailCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
    _checkEmailVerified();
    // Cliquer le lien de vérification ouvre le navigateur/l'app mail, pas cet
    // écran directement : on ne peut pas compter uniquement sur un retour au
    // premier plan (fiable sur iOS après « quitter/rouvrir », pas toujours
    // détecté sur Android où l'app reste en mémoire) — un sondage périodique
    // en filet de sécurité garantit qu'on ne reste jamais bloqué ici.
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_isVerified) _checkEmailVerified();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isVerified) {
      _checkEmailVerified();
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        if (_isResendEnabled) {
          _isResendEnabled = false;
          Future.delayed(Duration(minutes: 1), () {
            setState(() {
              _isResendEnabled = true;
            });
          });
        }
      });
    });
  }

  Future<void> _checkEmailVerified() async {
    User? user = FirebaseAuth.instance.currentUser;
    await user?.reload();
    if (!mounted || user == null || !user.emailVerified) return;
    setState(() {
      _isVerified = true;
    });
    _timer.cancel();
    _pollTimer?.cancel();
    if (User_Info.isElevage || User_Info.isPro || User_Info.isAssociation) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => VerificationRegistrationPage()),
      );
    } else {
      bool isRegistered = await registerUser(User_Info.email, User_Info.password);
      if (!mounted) return;
      if (isRegistered) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => BottomNav()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Échec de l\'enregistrement. Veuillez réessayer.')),
        );
      }
    }
  }

  Future<void> _resendVerificationEmail() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
      setState(() {
        _isResendEnabled = false;
        Future.delayed(Duration(minutes: 1), () {
          setState(() {
            _isResendEnabled = true;
          });
        });
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer.cancel();
    _pollTimer?.cancel();
    _newEmailCtrl.dispose();
    super.dispose();
  }

  /// Corrige une adresse mal saisie à l'inscription sans repartir de zéro.
  /// `verifyBeforeUpdateEmail` envoie le lien de vérification à la NOUVELLE
  /// adresse et ne met à jour `user.email` qu'une fois ce lien cliqué — le
  /// compte reste donc bloqué sur cet écran (par emailVerified) jusque-là,
  /// cohérent avec le reste du parcours.
  Future<void> _changeEmail() async {
    final newEmail = _newEmailCtrl.text.trim();
    if (newEmail.isEmpty || !newEmail.contains('@')) {
      setState(() => _emailError = 'Adresse e-mail invalide.');
      return;
    }
    if (newEmail == _currentEmail) {
      setState(() => _editingEmail = false);
      return;
    }
    setState(() { _savingEmail = true; _emailError = null; });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Session expirée, reconnectez-vous.');
      await user.verifyBeforeUpdateEmail(newEmail);
      User_Info.email = newEmail;
      if (!mounted) return;
      setState(() {
        _currentEmail = newEmail;
        _editingEmail = false;
        _savingEmail = false;
        _isResendEnabled = false;
      });
      Future.delayed(const Duration(minutes: 1), () {
        if (mounted) setState(() => _isResendEnabled = true);
      });
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'email-already-in-use':
          msg = 'Cette adresse est déjà utilisée par un autre compte.';
          break;
        case 'invalid-email':
          msg = "Cette adresse n'est pas valide.";
          break;
        case 'requires-recent-login':
          msg = 'Reconnectez-vous puis réessayez.';
          break;
        default:
          msg = 'Erreur : ${e.message ?? e.code}';
      }
      if (!mounted) return;
      setState(() { _emailError = msg; _savingEmail = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _emailError = 'Erreur : $e'; _savingEmail = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Vérification de l\'e-mail',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 84, height: 84,
                decoration: BoxDecoration(
                  color: _teal.withValues(alpha: _isVerified ? 1 : 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isVerified ? Icons.check_circle : Icons.mark_email_unread_outlined,
                  color: _isVerified ? Colors.white : _teal,
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _isVerified ? 'E-mail vérifié !' : 'Vérifiez votre boîte mail',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20, color: Color(0xFF1F2A2E)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _isVerified
                    ? 'Redirection en cours…'
                    : "Un e-mail de vérification a été envoyé à $_currentEmail. Cliquez sur le lien qu'il contient — cette page se met à jour automatiquement.",
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Galey', fontSize: 14, color: Colors.grey.shade600, height: 1.4),
              ),
              if (!_isVerified && !_editingEmail) ...[
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () {
                    _newEmailCtrl.text = _currentEmail;
                    setState(() { _editingEmail = true; _emailError = null; });
                  },
                  child: const Text("Ce n'est pas la bonne adresse ? Corriger",
                      style: TextStyle(fontFamily: 'Galey', fontSize: 13, decoration: TextDecoration.underline)),
                ),
              ],
              if (!_isVerified && _editingEmail) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _newEmailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Nouvelle adresse e-mail',
                    errorText: _emailError,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _savingEmail ? null : () => setState(() => _editingEmail = false),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: const Text('Annuler'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _savingEmail ? null : _changeEmail,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _teal, foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _savingEmail
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Valider'),
                    ),
                  ),
                ]),
              ],
              const SizedBox(height: 22),
              if (!_isVerified && !_editingEmail) ...[
                const SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: _teal),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _isResendEnabled ? _resendVerificationEmail : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _teal,
                      side: const BorderSide(color: _teal),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    child: Text(_isResendEnabled ? 'Renvoyer l\'e-mail de vérification' : 'E-mail renvoyé — patientez un instant'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _checkEmailVerified,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    child: const Text("J'ai déjà validé mon e-mail",
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
