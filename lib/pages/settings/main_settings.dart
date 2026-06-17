import 'dart:convert';
import 'dart:typed_data';

import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/connect_page.dart';
import 'package:PetsMatch/pages/pro/pro_profile_edit.dart';
import 'package:PetsMatch/pages/pro/pro_agenda.dart';
import 'package:PetsMatch/pages/settings/about_us.dart';
import 'package:PetsMatch/pages/settings/connectionSecu.dart';
import 'package:PetsMatch/pages/settings/info_utilisateur.dart';
import 'package:PetsMatch/pages/settings/parametre_config.dart';
import 'package:PetsMatch/pages/settings/utilisateurs_bloques_page.dart';
import 'package:PetsMatch/utils.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 10),
    child: Text(text, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF6B7280), letterSpacing: 0.5)),
  );
}

class SettingsMainPage extends StatefulWidget {
  const SettingsMainPage({super.key});

  @override
  State<SettingsMainPage> createState() => _SettingsMainPageState();
}

class _SettingsMainPageState extends State<SettingsMainPage>
    with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  AnimationController? _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void dispose() {
    _animationController?.dispose();
    super.dispose();
  }

  Future<void> _exportUserData(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    BuildContext? dialogCtx;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogCtx = ctx;
        return const AlertDialog(
          content: Row(children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Export en cours…'),
          ]),
        );
      },
    );

    try {
      final supa = Supabase.instance.client;
      final userProfile = await supa.from('users').select().eq('uid', uid).maybeSingle();
      final animaux = await supa.from('animaux').select().eq('uid_eleveur', uid);
      final annonces = await supa.from('annonces').select().eq('uid_eleveur', uid);
      final fsUser = await FirebaseFirestore.instance.collection('users').doc(uid).get();

      final exportData = {
        'exported_at': DateTime.now().toIso8601String(),
        'uid': uid,
        'profil': userProfile,
        'animaux': animaux,
        'annonces': annonces,
        'donnees_supplementaires': fsUser.data(),
      };

      if (dialogCtx != null && mounted) Navigator.of(dialogCtx!).pop();

      final jsonBytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(exportData));
      final xFile = XFile.fromData(
        Uint8List.fromList(jsonBytes),
        mimeType: 'application/json',
        name: 'mes_donnees_petsmatch_${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await Share.shareXFiles([xFile], subject: 'Mes données PetsMatch');
    } catch (e) {
      if (dialogCtx != null && mounted) Navigator.of(dialogCtx!).pop();
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Erreur export'),
            content: Text('$e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  void _triggerVaccinationReminder() async {
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'europe-west1');
      final HttpsCallable callable =
          functions.httpsCallable('triggerVaccinationReminder');
      // final HttpsCallable callable =
      //     FirebaseFunctions.instance.httpsCallable('triggerVaccinationReminder');
      final response = await callable();
      print('Réponse de la fonction : ${response.data}');
    } catch (e) {
      print("Erreur lors de l'appel de la fonction : $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C5C6C),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Paramètres',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20, color: Colors.white)),
      ),
      body: Center(
        child: Container(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              _SectionLabel('À propos du compte'),
              buildSettingsOption(
                context,
                icon: Icons.account_circle_outlined,
                text: 'Information utilisateur',
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (context) => InfoUserSettings()));
                },
              ),
              if (User_Info.isPro) ...[
                buildSettingsOption(
                  context,
                  icon: Icons.business_center_outlined,
                  text: 'Mon profil professionnel',
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => ProProfileEditPage(secondaryProfileId: User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null)));
                  },
                ),
                buildSettingsOption(
                  context,
                  icon: Icons.calendar_month_outlined,
                  text: 'Mon agenda RDV',
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) => const ProAgendaPage()));
                  },
                ),
              ],
              buildSettingsOption(
                context,
                icon: Icons.block_outlined,
                text: 'Utilisateurs bloqués',
                iconColor: Colors.red.shade400,
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (context) => const UtilisatesBloquesPage()));
                },
              ),
              buildSettingsOption(
                context,
                icon: Icons.security_outlined,
                text: 'Connexion et sécurité',
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (context) => SecuConnectionSetting()));
                },
              ),
              const SizedBox(height: 24),
              _SectionLabel('À propos de l\'application'),
              buildSettingsOption(
                context,
                icon: Icons.privacy_tip_outlined,
                text: 'Paramètres de confidentialité',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => ParametreConfi()),
                  );
                },
              ),
              buildSettingsOption(
                context,
                icon: Icons.info_outline,
                text: 'À propos',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => AboutUs()),
                  );
                },
              ),
              buildSettingsOption(
                context,
                icon: Icons.download_rounded,
                text: 'Exporter mes données',
                onTap: () => _exportUserData(context),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Se deconnecter',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 15)),
                  onPressed: () async {
                    await _auth.signOut();
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (context) => WelcomePage()),
                      (Route<dynamic> route) => false,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                onPressed: () async {
                  final user = FirebaseAuth.instance.currentUser;
                  final email = user?.email;

                  if (user == null || email == null) return;

                  String? passwordInput;

                  final result = await showDialog<String>(
                    context: context,
                    builder: (context) {
                      final TextEditingController passwordController =
                          TextEditingController();
                      return AlertDialog(
                        title: Text('Confirmation de suppression'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                                'Pour des raisons de sécurité, entre ton mot de passe pour confirmer la suppression de ton compte.'),
                            SizedBox(height: 12),
                            TextField(
                              controller: passwordController,
                              obscureText: true,
                              decoration:
                                  InputDecoration(labelText: 'Mot de passe'),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, null),
                            child: Text('Annuler'),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(
                                  context, passwordController.text.trim());
                            },
                            child: Text('Supprimer'),
                          ),
                        ],
                      );
                    },
                  );

                  passwordInput = result;

                  if (passwordInput == null || passwordInput.trim().isEmpty)
                    return;

                  try {
                    // Re-authenticate
                    final credential = EmailAuthProvider.credential(
                      email: email,
                      password: passwordInput,
                    );
                    await user.reauthenticateWithCredential(credential);

                    final uid = user.uid;
                    final firestore = FirebaseFirestore.instance;

                    final collectionsWithUidAsDocID = [
                      'users',
                      'dogfiche',
                      'catfiche',
                      'subscription',
                      'likedPost',
                    ];

                    for (final collection in collectionsWithUidAsDocID) {
                      await firestore
                          .collection(collection)
                          .doc(uid)
                          .delete()
                          .catchError((e) {
                        print('Erreur suppression $collection: $e');
                      });
                    }

                    final postSnapshot = await firestore
                        .collection('post')
                        .where('uidEleveur', isEqualTo: uid)
                        .get();
                    for (final doc in postSnapshot.docs) {
                      await doc.reference.delete().catchError((e) {
                        print('Erreur suppression post: $e');
                      });
                    }

                    // Cascade-delete toutes les données Supabase (ON DELETE CASCADE)
                    try {
                      await Supabase.instance.client
                          .from('users')
                          .delete()
                          .eq('uid', uid);
                    } catch (e) {
                      print('Supabase cascade delete: $e');
                    }

                    // Supprimer les fichiers Firebase Storage
                    try {
                      final folder = FirebaseStorage.instance.ref('files/$uid');
                      final listing = await folder.listAll();
                      for (final item in listing.items) {
                        await item.delete().catchError((_) {});
                      }
                      for (final sub in listing.prefixes) {
                        final subList = await sub.listAll();
                        for (final item in subList.items) {
                          await item.delete().catchError((_) {});
                        }
                      }
                    } catch (e) {
                      print('Storage delete: $e');
                    }

                    // Supprimer compte Firebase Auth
                    await user.delete();

                    // Rediriger
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (context) => WelcomePage()),
                      (Route<dynamic> route) => false,
                    );
                  } catch (e) {
                    print('Erreur : $e');
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('Erreur'),
                        content: Text('La suppression du compte a échoué.\n$e'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text('OK'),
                          )
                        ],
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: const Text(
                  'Supprimer le compte',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget buildSettingsOption(BuildContext context,
      {required IconData icon, required String text, required Function onTap, Color? iconColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => onTap(),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: (iconColor ?? const Color(0xFF0C5C6C)).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor ?? const Color(0xFF0C5C6C), size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(text,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w500, fontSize: 15, color: Color(0xFF1F2A2E))),
              ),
              const Icon(Icons.arrow_forward_ios, color: Color(0xFF9CA3AF), size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
