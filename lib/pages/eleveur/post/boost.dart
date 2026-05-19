import 'dart:typed_data';
import 'package:PetsMatch/main.dart';
import 'package:flutter/material.dart';
import 'package:PetsMatch/pages/eleveur/board.dart';
import 'package:PetsMatch/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:PetsMatch/pages/eleveur/choice_publication.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';

Future<void> signInAnonymously() async {
  try {
    UserCredential userCredential =
        await FirebaseAuth.instance.signInAnonymously();
    print("Signed in with temporary account.");
  } catch (e) {
    print("Failed to sign in anonymously: $e");
  }
}

class BoostOption {
  final String title;
  final double price;
  bool isSelected;

  BoostOption(
      {required this.title, required this.price, this.isSelected = false});
}

class BoostType {
  final String name;
  final String description;
  final List<BoostOption> options;

  BoostType(
      {required this.name, required this.description, required this.options});
}

class BoostAdPage extends StatefulWidget {
  @override
  _BoostAdPageState createState() => _BoostAdPageState();
}

class _BoostAdPageState extends State<BoostAdPage> {
  double basePrice = 3.99;
  double totalPrice = 3.99;
  bool isProcessingPayment = false;

  List<BoostType> boostTypes = [
    BoostType(
      name: 'Recommandé',
      description:
          'Boostez votre annonce pour améliorer sa visibilité auprès des utilisateurs.',
      options: [
        BoostOption(title: 'Pendant 24 heures', price: 3.99),
        BoostOption(title: 'Pendant 7 jours', price: 12.99),
        BoostOption(title: 'Pendant 15 jours', price: 19.99),
        BoostOption(title: 'Pendant 30 jours', price: 29.99),
      ],
    ),
    BoostType(
      name: 'Urgent',
      description:
          'Rendez votre annonce plus visible en la plaçant en priorité.',
      options: [
        BoostOption(title: 'Pendant 24 heures', price: 4.99),
        BoostOption(title: 'Pendant 7 jours', price: 15.99),
        BoostOption(title: 'Pendant 15 jours', price: 24.99),
        BoostOption(title: 'Pendant 30 jours', price: 34.99),
      ],
    ),
  ];

  BoostOption? selectedOption;
  @override
  void initState() {
    super.initState();
    isProcessingPayment = false;
    basePrice = 3.99;
    totalPrice = 3.99;
    NewPostClass.isBoost = false;
    NewPostClass.isUrgent = false;
    // Stripe.init call ici si tu veux l'utiliser à l’ouverture
    // Future.microtask(() => _initializeStripe());
  }

  Future<void> _initializeStripe() async {
    try {
      Stripe.publishableKey = "pk_test_xxxxxxxxxxxxxx";
      await Stripe.instance.applySettings();
    } catch (e) {
      print("Erreur d'initialisation Stripe : $e");
    }
  }

  void _onOptionChanged(
      BoostType selectedBoostType, BoostOption selectedOption) {
    setState(() {
      for (var boostType in boostTypes) {
        for (var option in boostType.options) {
          option.isSelected = false;
        }
      }

      selectedOption.isSelected = true;
      this.selectedOption = selectedOption;
      totalPrice = basePrice + selectedOption.price;

      // Met à jour le statut du boost dans NewPostClass
      if (selectedBoostType.name == 'Urgent') {
        NewPostClass.isUrgent = true;
        NewPostClass.isBoost = false;
      } else if (selectedBoostType.name == 'Recommandé') {
        NewPostClass.isBoost = true;
        NewPostClass.isUrgent = false;
      } else {
        NewPostClass.isBoost = false;
        NewPostClass.isUrgent = false;
      }
    });
  }

  Future<void> _savePostAndUploadMedia(BuildContext context) async {
    setState(() => isProcessingPayment = true);

    try {
      await _uploadMediaToFirebase(); // ⚡️ optimisé maintenant
      await _makePayment(totalPrice); // ⚠️ Stripe désactivé mais conservé
      await _savePost(context); // 📤 en base Firestore

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Publication et paiement réussis !')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isProcessingPayment = false);
      }
    }
  }

  Future<void> _uploadMediaToFirebase() async {
    final List<Future<Map<String, dynamic>>> uploadTasks = [];

    for (var media in NewPostClass.mediaStockage) {
      if (media['isPhoto']) {
        final file = File(media['path']);
        final fileName = file.path.split('/').last;

        final uploadFuture = FlutterImageCompress.compressWithFile(
          file.absolute.path,
          quality: 75,
          minWidth: 1080,
          minHeight: 1080,
        ).then((compressedData) async {
          if (compressedData == null) {
            throw Exception("Compression échouée pour $fileName");
          }

          final ref = FirebaseStorage.instance.ref().child('uploads/$fileName');
          final snapshot =
              await ref.putData(Uint8List.fromList(compressedData));
          final downloadURL = await snapshot.ref.getDownloadURL();

          return {'path': downloadURL, 'isPhoto': true};
        });

        uploadTasks.add(uploadFuture);
      }
    }

    final uploadedMedia = await Future.wait(uploadTasks);
    NewPostClass.mediaStockage = uploadedMedia;
  }

  Future<void> _savePost(BuildContext context) async {
    var user = FirebaseAuth.instance.currentUser;
    if (user?.uid == null || user!.uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : utilisateur non identifié.')),
      );
      return;
    }

    await FirebaseFirestore.instance.collection('post').add({
      'uidEleveur': user.uid,
      'desc': NewPostClass.desc,
      'mediaStockage': NewPostClass.mediaStockage,
      'tags': NewPostClass.tags,
      'isPhoto': NewPostClass.isPhoto,
      'timestamp': FieldValue.serverTimestamp(),
      'isBoost': NewPostClass.isBoost,
      'isUrgent': NewPostClass.isUrgent,
      'isCat': NewPostClass.isCat,
      'isDog': NewPostClass.isDog,
      'moreEightWeeks': NewPostClass.moreEightWeeks,
      'isAdult': NewPostClass.isAdult,
      'isSell': NewPostClass.isSell,
      'isSailli': NewPostClass.isSailli,
      'isRetraite': NewPostClass.isRetraite,
      'isLoof': NewPostClass.isLoof,
      'isLof': NewPostClass.isLof,
      'isVaccined': NewPostClass.isVaccined,
      'isMale': NewPostClass.isMale,
      'isPro': User_Info.isPro,
      'title': NewPostClass.title,
      'dateOfBirth': NewPostClass.dateOfBirth,
      'puceNumber': NewPostClass.puceNumber,
      'numberPorter': NewPostClass.numberPorter,
      'price': NewPostClass.price,
      'genealogieText': NewPostClass.genealogieText,
      'hasGenealogie': NewPostClass.hasGenealogie
    });

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => BoardMainPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final widthRef = UTILS.widthReference(context);
    final heightRef = UTILS.heightReference(context);
    final spacing16 = UTILS.calculHeight(16, heightRef);

    return Scaffold(
      appBar: AppBar(
        title: Text('BOOSTEZ VOTRE ANNONCE'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: ListView(
        padding: EdgeInsets.all(UTILS.calculWidth(16, widthRef)),
        children: [
          for (var boostType in boostTypes)
            Padding(
              padding: EdgeInsets.only(bottom: spacing16),
              child: _buildBoostCard(boostType, widthRef, heightRef),
            ),
          SizedBox(height: UTILS.calculHeight(30, heightRef)),
          _buildBottomBar(widthRef, heightRef),
        ],
      ),
    );
  }

  Widget _buildBoostCard(
      BoostType boostType, double widthRef, double heightRef) {
    return Container(
      decoration: BoxDecoration(
        color: Color.fromARGB(255, 255, 247, 240),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            offset: Offset(0, 4),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: EdgeInsets.all(UTILS.calculWidth(16, widthRef)),
            child: Column(
              children: [
                SizedBox(height: UTILS.calculHeight(30, heightRef)),
                Text('Boostez votre annonce',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                SizedBox(height: UTILS.calculHeight(8, heightRef)),
                Text(boostType.description, textAlign: TextAlign.center),
                SizedBox(height: UTILS.calculHeight(16, heightRef)),
                ...boostType.options.map((option) {
                  return _buildBoostOption(boostType, option, heightRef);
                }).toList(),
              ],
            ),
          ),
          Positioned(
            top: -UTILS.calculHeight(12, heightRef),
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: UTILS.calculWidth(110, widthRef),
                height: UTILS.calculHeight(23, heightRef),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _getLabelColor(boostType.name),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(
                  boostType.name,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoostOption(
      BoostType boostType, BoostOption option, double heightRef) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: UTILS.calculHeight(4, heightRef)),
      decoration: BoxDecoration(
        color: option.isSelected
            ? Color.fromARGB(100, 255, 132, 132)
            : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: option.isSelected
              ? Color.fromARGB(185, 255, 132, 132)
              : Colors.grey,
        ),
      ),
      child: CheckboxListTile(
        value: option.isSelected,
        onChanged: (_) => _onOptionChanged(boostType, option),
        title: Text(option.title),
        secondary: Text(
          '${option.price.toStringAsFixed(2)}€',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        activeColor: Color.fromARGB(255, 255, 132, 132),
        contentPadding: EdgeInsets.symmetric(horizontal: 12),
        controlAffinity: ListTileControlAffinity.leading,
      ),
    );
  }

  Widget _buildBottomBar(double widthRef, double heightRef) {
    final ttc = totalPrice.toStringAsFixed(2);
    final ht = (totalPrice / 1.20).toStringAsFixed(2);
    return Container(
      width: UTILS.calculWidth(428, widthRef),
      height: UTILS.calculHeight(133, heightRef),
      decoration: BoxDecoration(
        color: Color(0xFFFFF1E3),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () {},
                child: Text('Détail',
                    style: TextStyle(decoration: TextDecoration.underline)),
              ),
              Text(
                '$ttc€ TTC ($ht€ HT)',
                style: TextStyle(
                  fontSize: UTILS.calculHeight(16, heightRef),
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ],
          ),
          SizedBox(
            width: UTILS.calculWidth(375, widthRef),
            height: UTILS.calculHeight(51, heightRef),
            child: IgnorePointer(
              ignoring: isProcessingPayment,
              child: ElevatedButton(
                onPressed: () async {
                  setState(() {
                    isProcessingPayment = true;
                  });

                  await _savePostAndUploadMedia(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 255, 132, 132),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 0,
                  shadowColor: Colors.transparent,
                ),
                child: Text(
                  isProcessingPayment ? 'Envoi...' : 'Valider et payer',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  Color _getLabelColor(String labelName) {
    switch (labelName) {
      case 'Recommandé':
        return Color.fromARGB(200, 255, 132, 132);
      case 'Urgent':
        return Colors.purple[100]!;
      default:
        return Colors.grey;
    }
  }

  // Stripe désactivé ici volontairement
  Future<void> _makePayment(double amount) async {
    try {
      // Décommenter pour activer Stripe avec Firebase Functions
      /*
    final functions = FirebaseFunctions.instanceFor(region: 'europe-west1');
    final HttpsCallable callable = functions.httpsCallable('createStripePaymentIntent');
    final response = await callable.call(<String, dynamic>{
      'amount': (amount * 100).toInt(), // Convert to cents
      'currency': 'eur',
    });

    final String clientSecret = response.data['clientSecret'];

    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: clientSecret,
        style: ThemeMode.system,
        merchantDisplayName: 'PetsMatch',
      ),
    );

    await Stripe.instance.presentPaymentSheet();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Paiement réussi.')),
    );
    */
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors du paiement.')),
      );
    }
  }
}
