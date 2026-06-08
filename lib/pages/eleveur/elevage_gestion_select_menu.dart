import 'package:PetsMatch/pages/eleveur/race_selection_page.dart';
import 'package:PetsMatch/pages/eleveur/admin/main.dart';
import 'package:PetsMatch/utils.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ElevageSelectGestionPage extends StatefulWidget {
  const ElevageSelectGestionPage({super.key});

  @override
  State<ElevageSelectGestionPage> createState() =>
      _ElevageSelectGestionPageState();
}

class _ElevageSelectGestionPageState extends State<ElevageSelectGestionPage> {
  bool _isSubscribed = false;
  bool _isProcessing = false; // Pour suivre l'état du traitement

  @override
  void initState() {
    super.initState();
    _checkSubscription();
    Stripe.publishableKey =
        "pk_test_51Pagp22MpEB6OUl5WhTICWegB3ibkSKDcVlmUDMFDdm7SWnfLmI8XM1aIKXWeslNjK7CSzJwe2yu64CW1bl0s3s100iwTo71nt";
  }

  Future<void> _checkSubscription() async {
    // final userId = FirebaseAuth.instance.currentUser?.uid;
    // if (userId != null) {
    //   final subscriptionDoc = await FirebaseFirestore.instance
    //       .collection('subscriptions')
    //       .doc(userId)
    //       .get();

    //   setState(() {
    //     _isSubscribed =
    //         subscriptionDoc.exists && subscriptionDoc['status'] == 'active';
    //   });
    // }
    _isSubscribed = true;
  }

  Future<void> _subscribe() async {
    if (_isProcessing) return; // Empêche un double-clic pendant le traitement

    setState(() {
      _isProcessing = true;
    });

    try {
      // Crée une PaymentIntent avec l'API Stripe via Firebase Cloud Functions
      final functions = FirebaseFunctions.instanceFor(region: 'europe-west1');
      final HttpsCallable callable =
          functions.httpsCallable('createStripePaymentIntent');

      final response = await callable.call(<String, dynamic>{
        'amount': 1800, // 18,00 € en centimes
        'currency': 'eur', // Devise en euros
      });

      String clientSecret = response.data['clientSecret'];

      // Initialiser la feuille de paiement avec les paramètres locaux
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          style:
              ThemeMode.system, // Adapte automatiquement au thème du dispositif
          merchantDisplayName: 'PetsMatch',
        ),
      );

      // Présente la feuille de paiement à l'utilisateur
      await Stripe.instance.presentPaymentSheet();

      // Notification de succès du paiement
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Abonnement réussi.')),
      );

      // Enregistrement de l'abonnement dans Firestore
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        await FirebaseFirestore.instance
            .collection('subscriptions')
            .doc(userId)
            .set({
          'userId': userId,
          'subscriptionId':
              clientSecret, // Utilisation du clientSecret comme ID d'abonnement
          'startDate': DateTime.now(),
          'endDate': DateTime.now().add(Duration(days: 30)),
          'status': 'active',
        });

        // Mise à jour de l'état pour refléter l'abonnement
        setState(() {
          _isSubscribed = true;
        });
      }
    } catch (error) {
      // Gestion des erreurs lors du processus d'abonnement
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de l\'abonnement.')),
      );
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _cancelSubscription() async {
    if (_isProcessing) return; // Empêche un double-clic pendant le traitement

    setState(() {
      _isProcessing = true;
    });

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        // Obtenez l'ID de l'abonnement depuis Firestore
        final subscriptionDoc = await FirebaseFirestore.instance
            .collection('subscriptions')
            .doc(userId)
            .get();

        final subscriptionId = subscriptionDoc['subscriptionId'];

        // Appelez la fonction Cloud pour annuler l'abonnement
        final functions = FirebaseFunctions.instanceFor(region: 'europe-west1');
        final HttpsCallable callable =
            functions.httpsCallable('cancelStripeSubscription');

        await callable.call(<String, dynamic>{
          'subscriptionId': subscriptionId,
        });

        // Mise à jour de l'état de l'application après l'annulation
        await FirebaseFirestore.instance
            .collection('subscriptions')
            .doc(userId)
            .update({
          'status': 'canceled',
        });

        setState(() {
          _isSubscribed = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Abonnement annulé.')),
        );
      }
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Erreur lors de l\'annulation de l\'abonnement.')),
      );
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          child: Column(
            children: [
              SizedBox(
                width: UTILS.widthReference(context),
                height: UTILS.calculHeight(105, UTILS.heightReference(context)),
                child: Stack(children: [
                  Image.asset(
                    'assets/deco/arrondi_rose_2.png',
              color: const Color(0xFFA7C79A),
              colorBlendMode: BlendMode.srcIn,
                    fit: BoxFit.cover,
                    width:
                        UTILS.calculWidth(211, UTILS.widthReference(context)),
                    height:
                        UTILS.calculHeight(104, UTILS.heightReference(context)),
                  ),
                  Positioned(
                    top: UTILS.calculHeight(42, UTILS.heightReference(context)),
                    left: UTILS.calculWidth(10, UTILS.widthReference(context)),
                    child: IconButton(
                      icon: Icon(Icons.arrow_back, color: Colors.black),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                  Positioned(
                    top: UTILS.calculHeight(53, UTILS.heightReference(context)),
                    left: 0,
                    right: 0,
                    child: Align(
                      alignment: Alignment.center,
                      child: Text(
                        'GESTION',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Galey',
                          fontWeight: FontWeight.w500,
                          fontSize: UTILS.calculWidth(
                              20, UTILS.widthReference(context)),
                        ),
                      ),
                    ),
                  )
                ]),
              ),
              SizedBox(
                  height:
                      UTILS.calculHeight(58, UTILS.heightReference(context))),
              DogCatMenu(
                title: 'Gestion des animaux',
                subtitle:
                    'Gérez les fiches de vos animaux par race.',
                imagePath: 'assets/page/publication.png',
                isEnabled: _isSubscribed,
              ),
              SizedBox(
                  height:
                      UTILS.calculHeight(40, UTILS.heightReference(context))),
              ReproMenu(
                title: 'Menu administratif',
                subtitle: 'Gérez vos tâches administratives avec simplicité.',
                imagePath: 'assets/page/love_dog.png',
                isEnabled: _isSubscribed,
              ),
              if (!_isSubscribed)
                Column(
                  children: [
                    SizedBox(
                        height: UTILS.calculHeight(
                            20, UTILS.heightReference(context))),
                    Center(
                      child: Text(
                        "Vous devez être abonné(e) pour accéder à ces fonctionnalités.",
                        style: TextStyle(fontSize: 16, color: Colors.red),
                        textAlign: TextAlign
                            .center, // Assurez-vous que le texte est centré à l'intérieur du Text widget
                      ),
                    ),
                    SizedBox(
                        height: UTILS.calculHeight(
                            20, UTILS.heightReference(context))),
                    ElevatedButton(
                      onPressed: _isProcessing ? null : _subscribe,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            Color(0xFFA7C79A), // Couleur d
                      ),
                      child: Text(
                        "S'abonner à 18€ TTC par mois",
                        style: TextStyle(color: Colors.black),
                      ),
                    ),
                  ],
                ),
              if (_isSubscribed)
                Column(
                  children: [
                    SizedBox(
                        height: UTILS.calculHeight(
                            20, UTILS.heightReference(context))),
                    ElevatedButton(
                      onPressed: _isProcessing ? null : _cancelSubscription,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            Color(0xFFA7C79A), // Couleur d
                      ),
                      child: Text(
                        "Annuler l'abonnement",
                        style: TextStyle(color: Colors.black),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class DogCatMenu extends StatelessWidget {
  final String title;
  final String subtitle;
  final String imagePath;
  final bool isEnabled;

  const DogCatMenu({
    Key? key,
    required this.title,
    required this.subtitle,
    required this.imagePath,
    required this.isEnabled,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: UTILS.calculWidth(368.37, UTILS.widthReference(context)),
      height: UTILS.calculHeight(138, UTILS.heightReference(context)),
      child: InkWell(
        borderRadius: BorderRadius.circular(500),
        onTap: isEnabled
            ? () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const RaceSelectionPage()),
                );
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.all(0.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                imagePath,
                width: UTILS.calculWidth(136, UTILS.widthReference(context)),
                height: UTILS.calculHeight(136, UTILS.heightReference(context)),
                color: isEnabled
                    ? null
                    : Colors.grey, // Griser l'image si désactivé
              ),
              SizedBox(
                width: UTILS.calculWidth(16, UTILS.widthReference(context)),
              ),
              SizedBox(
                width: UTILS.calculWidth(200, UTILS.widthReference(context)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: UTILS.calculWidth(
                            20, UTILS.widthReference(context)),
                        fontFamily: 'Galey',
                        color: isEnabled
                            ? Color(0xFF0C5C6C)
                            : Colors.grey, // Texte grisé si désactivé
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(
                      height: UTILS.calculHeight(8, UTILS.heightReference(context)),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: UTILS.calculWidth(
                            18, UTILS.widthReference(context)), // Taille augmentée
                        fontFamily: 'Galey',
                        color: isEnabled
                            ? Color(0xFF0C5C6C)
                            : Colors.grey, // Texte grisé si désactivé
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class ReproMenu extends StatelessWidget {
  final String title;
  final String subtitle;
  final String imagePath;
  final bool isEnabled;

  const ReproMenu({
    Key? key,
    required this.title,
    required this.subtitle,
    required this.imagePath,
    required this.isEnabled,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: UTILS.calculWidth(368.37, UTILS.widthReference(context)),
      height: UTILS.calculHeight(138, UTILS.heightReference(context)),
      child: InkWell(
        borderRadius: BorderRadius.circular(500),
        onTap: isEnabled
            ? () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ReproMainPage()),
                );
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.all(0.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: UTILS.calculWidth(225, UTILS.widthReference(context)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: UTILS.calculWidth(
                            20, UTILS.widthReference(context)),
                        fontFamily: 'Galey',
                        color: isEnabled
                            ? Color(0xFF0C5C6C)
                            : Colors.grey, // Texte grisé si désactivé
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(
                      height: UTILS.calculHeight(8, UTILS.heightReference(context)),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: UTILS.calculWidth(
                            18, UTILS.widthReference(context)), // Taille augmentée
                        fontFamily: 'Galey',
                        color: isEnabled
                            ? Color(0xFF0C5C6C)
                            : Colors.grey, // Texte grisé si désactivé
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              Image.asset(
                imagePath,
                width: UTILS.calculWidth(136, UTILS.widthReference(context)),
                height: UTILS.calculHeight(136, UTILS.heightReference(context)),
                color: isEnabled
                    ? null
                    : Colors.grey, // Image grisée si désactivée
              ),
            ],
          ),
        ),
      ),
    );
  }
}
