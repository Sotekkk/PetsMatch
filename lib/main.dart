import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:PetsMatch/pages/admin/admin_panel.dart';
import 'package:PetsMatch/pages/agenda/agenda_page.dart';
import 'package:PetsMatch/pages/bottom_nav.dart';
import 'package:PetsMatch/pages/connect_page.dart';
import 'package:PetsMatch/pages/eleveur/verification_page.dart';
import 'package:PetsMatch/pages/pro/pro_agenda.dart';
import 'package:PetsMatch/pages/notifications_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:PetsMatch/services/promenade_notification_service.dart';
import 'firebase_options.dart';

const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'high_importance_channel', // Identifiant du canal
  'High Importance Notifications', // Nom du canal
  description: 'Ce canal est utilisé pour les notifications importantes.',
  importance: Importance.high,
);

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
GlobalKey<ScaffoldState> drawerKey = GlobalKey<ScaffoldState>();
// Permet aux écrans persistants (ex. accueil pro) de savoir quand ils
// redeviennent visibles après un Navigator.pop, pour se recharger sans
// dépendre d'un pull-to-refresh manuel.
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

void _handleNotifNavigation(Map<String, dynamic> data) {
  final ctx = navigatorKey.currentState;
  if (ctx == null) return;

  // Si la notif est destinée à un profil secondaire spécifique, on y bascule
  final recipientProfileId = data['recipient_profile_id'] as String? ?? '';
  if (recipientProfileId.isNotEmpty) {
    final profiles = User_Info.availableProfiles;
    final target = profiles.where((p) => p['id']?.toString() == recipientProfileId).firstOrNull;
    if (target != null) {
      User_Info.applyProfile(target);
    }
  }

  ctx.push(MaterialPageRoute(builder: (_) => const NotificationsPage()));
}

Future<void> setupNotifications() async {
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
  // Canal dédié aux rappels de promenades
  await setupPromenadeNotificationChannel();
}

bool isRequestingPermission = false;
Future<void> saveFcmTokenToFirestore() async {
  try {
    String? token = await FirebaseMessaging.instance.getToken();

    if (token != null) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Firestore (messagerie)
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          {'fcmToken': token}, SetOptions(merge: true));
        // Supabase (notifications push likes/alertes)
        try {
          await Supabase.instance.client
              .from('users')
              .update({'fcm_token': token})
              .eq('uid', user.uid);
        } catch (_) {}
      }
    }
  } catch (e) {
    // ignore
  }
}

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await setupNotifications();
  print("Message reçu en arrière-plan : ${message.messageId}");
}

Future<void> requestPermissions() async {
  print("Demande de permissions");

  // Demande les permissions pour les notifications
  NotificationSettings settings =
      await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  print("Statut des notifications : ${settings.authorizationStatus}");

  // Demande les autres permissions nécessaires
  await [
    Permission.photos,
    Permission.camera,
    Permission.storage,
    Permission.locationWhenInUse
  ].request();
}

Future<void> testLocalNotification() async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'high_importance_channel', // ID du canal
    'Notifications Importantes',
    channelDescription: 'Test d\'icônes enrichies.',
    importance: Importance.high,
    priority: Priority.high,
    icon: 'ic_notification', // Petite icône monochrome pour la barre d'état
    largeIcon:
        DrawableResourceAndroidBitmap('ic_notification'), // Icône enrichie
  );

  const NotificationDetails notificationDetails =
      NotificationDetails(android: androidPlatformChannelSpecifics);

  await flutterLocalNotificationsPlugin.show(
    id: 0,
    title: 'Nouveau message',
    body: 'Ceci est une notification avec icône enrichie.',
    notificationDetails: notificationDetails,
  );
}

class User_Info {
  static String firstname = "none";
  static String lastname = "none";
  static String dateofbirth = "01/01/2002";
  static String codeISO = "+33";
  static String codeISOElevage = "+33";
  static String phone_number = "0000000000";
  static String adress = "none";
  static String rue = "";
  static String ville = "";
  static String codePostal = "";
  static String pays = "France";
  static String departement = "";
  static String region = "";
  static String profilePictureUrl = '';
  static String profilePictureUrlElevage = '';
  static bool isElevage = true;
  static String adressElevage = "";
  static String rueElevage = "";
  static String villeElevage = "";
  static String codePostalElevage = "";
  static String paysElevage = "France";
  static String departementElevage = "";
  static String regionElevage = "";
  static String nameElevage = "";
  static String numeroElevage = "0000000000";
  static bool isDev = false;
  static String email = "none";
  static String password = "none";
  static bool isValidate = false;
  static String desc = "";
  static String descEntreprise = "";
  static String siret = "";
  static String numeroTVA = "";
  static List<Map<String, dynamic>> documentElevage = [];
  static bool validateAccountElevage = true;
  static String adoptProject = "";
  static String uid = "";
  static bool isPub = false;
  static bool isPro = false;
  static String catPro = "";
  static String professionPro = "";
  static bool isPartenaire = false;
  static bool isAdmin = false;
  static bool isAssociation = false;
  static String rna = '';
  static String agrementPrefectoral = '';
  static int capaciteAccueil = 0;
  static String verificationStatus = 'none';
  static String kbisUrl = '';
  static String rejectionReason = '';
  static bool isDog = false;
  static bool isCat = false;
  static List<String> dogBreeds = [];
  static List<String> catBreeds = [];
  static String acacedNumero = "";
  static String acacedDateObtention = "";
  static String acacedDocUrl = "";
  static List<String> especesElevees = [];
  static String bannerUrl = '';

  // Champs pro avancés (S01)
  static int rayonIntervention = 0;
  static List<String> especesAcceptees = [];
  static Map<String, String> horaires = {};
  static String tarifs = '';
  static String siteWeb = '';
  static String instagram = '';
  static String facebook = '';
  static List<Map<String, dynamic>> certifications = [];
  static List<String> photosGalerie = [];
  static bool acceptNewClients = true;

  static void updateUserInfo(Map<String, dynamic> data) {
    firstname = data['firstname'] ?? firstname;
    lastname = data['lastname'] ?? lastname;
    dateofbirth = data['dateofbirth'] ?? dateofbirth;
    codeISO = data['codeISO'] ?? codeISO;
    phone_number = data['phone_number'] ?? phone_number;
    adress = data['adress'] ?? adress;
    rue = data['rue'] ?? rue;
    ville = data['ville'] ?? ville;
    codePostal = data['codePostal'] ?? codePostal;
    pays = data['pays'] ?? pays;
    departement = data['departement'] ?? departement;
    region = data['region'] ?? region;
    profilePictureUrl = data['profilePictureUrl'] ?? profilePictureUrl;
    profilePictureUrlElevage = data['profilePictureUrlElevage'] ?? data['profilePictureUrl'] ?? profilePictureUrlElevage;
    isElevage = data['isElevage'] ?? isElevage;
    nameElevage = data['nameElevage'] ?? nameElevage;
    adressElevage = data['adressElevage'] ?? adressElevage;
    rueElevage = data['rueElevage'] ?? rueElevage;
    villeElevage = data['villeElevage'] ?? villeElevage;
    codePostalElevage = data['codePostalElevage'] ?? codePostalElevage;
    paysElevage = data['paysElevage'] ?? paysElevage;
    departementElevage = data['departementElevage'] ?? departementElevage;
    regionElevage = data['regionElevage'] ?? regionElevage;
    numeroElevage = data['numeroElevage'] ?? numeroElevage;
    isValidate = data['isValidate'] ?? isValidate;
    isDev = data['isDev'] ?? isDev;
    email = data['email'] ?? email;
    password = data['password'] ?? password;
    desc = data['desc'] ?? desc;
    descEntreprise = data['descEntreprise'] ?? descEntreprise;
    documentElevage = List<Map<String, dynamic>>.from(
        data['documentElevage'] ?? documentElevage);
    validateAccountElevage =
        data['validateAccountElevage'] ?? validateAccountElevage;
    adoptProject = data['adoptProject'] ?? adoptProject;
    uid = data['uid'] ?? uid;
    isPub = data['isPud'] ?? isPub;
    isPro = data['isPro'] ?? isPro;
    catPro = data['catPro'] ?? catPro;
    siret = data['siret'] ?? siret;
    numeroTVA = data['numeroTVA'] ?? numeroTVA;
    professionPro = data['professionPro'] ?? professionPro;
    isPartenaire = data['isPartenaire'] ?? isPartenaire;
    isAdmin = data['isAdmin'] ?? isAdmin;
    isAssociation = data['isAssociation'] ?? false;
    rna = data['rna'] ?? rna;
    agrementPrefectoral = data['agrementPrefectoral'] ?? agrementPrefectoral;
    acacedNumero = data['acacedNumero'] ?? acacedNumero;
    acacedDateObtention = data['acacedDateObtention'] ?? acacedDateObtention;
    acacedDocUrl = data['acacedDocUrl'] ?? acacedDocUrl;
    verificationStatus = data['verificationStatus'] ?? verificationStatus;
    kbisUrl = data['kbisUrl'] ?? kbisUrl;
    rejectionReason = data['rejectionReason'] ?? rejectionReason;
    isDog = data['isDog'] ?? isDog;
    isCat = data['isCat'] ?? isCat;
    dogBreeds = _safeStringList(data['dogBreeds'], dogBreeds);
    catBreeds = _safeStringList(data['catBreeds'], catBreeds);
    especesElevees = _safeStringList(data['especesElevees'], especesElevees);
    bannerUrl = data['bannerUrl'] ?? bannerUrl;

    // Champs pro avancés (S01) — parsing défensif
    final rawRayon = data['rayon_intervention'];
    if (rawRayon != null) {
      rayonIntervention = rawRayon is int
          ? rawRayon
          : (int.tryParse(rawRayon.toString()) ?? rayonIntervention);
    }
    especesAcceptees = _safeStringList(data['especes_acceptees'], especesAcceptees);
    if (data['horaires'] is Map) {
      try {
        horaires = Map<String, String>.from(
          (data['horaires'] as Map).map((k, v) =>
              MapEntry(k.toString(), v?.toString() ?? '')),
        );
      } catch (_) {}
    }
    if (data['tarifs'] is String) tarifs = data['tarifs'] as String;
    if (data['site_web'] is String) siteWeb = data['site_web'] as String;
    if (data['instagram'] is String) instagram = data['instagram'] as String;
    if (data['facebook'] is String) facebook = data['facebook'] as String;
    if (data['certifications'] is List) {
      try {
        certifications = List<Map<String, dynamic>>.from(
          (data['certifications'] as List).whereType<Map>().map(
              (e) => Map<String, dynamic>.from(e)),
        );
      } catch (_) {}
    }
    photosGalerie = _safeStringList(data['photos_galerie'], photosGalerie);
    final rawAccept = data['accept_new_clients'];
    if (rawAccept is bool) acceptNewClients = rawAccept;

    // Cache profil principal (toujours réinitialisé au login)
    primaryLabel = isPro
        ? (nameElevage.isNotEmpty ? nameElevage : '$firstname $lastname'.trim())
        : isElevage
            ? (nameElevage.isNotEmpty ? nameElevage : '$firstname $lastname'.trim())
            : '$firstname $lastname'.trim();
    primaryType = isPro ? catPro : isAssociation ? 'association' : (isElevage ? 'eleveur' : 'particulier');
    activeType  = primaryType;
    primaryAvatar = profilePictureUrlElevage.isNotEmpty ? profilePictureUrlElevage : profilePictureUrl;
    activeProfileId = '';
    profileNotifier.value = '';
  }

  // ── Multi-profil ───────────────────────────────────────────────────────────

  static String activeProfileId = '';
  static String activeType      = '';  // type du profil actif (primaire ou secondaire)
  static final ValueNotifier<String> profileNotifier = ValueNotifier<String>('');
  static List<Map<String, dynamic>> availableProfiles = [];
  static String primaryLabel = '';
  static String primaryType  = '';
  static String primaryAvatar = '';

  static void applyProfile(Map<String, dynamic> p) {
    activeProfileId = p['id']?.toString() ?? '';
    final type = p['profile_type']?.toString() ?? '';
    activeType = type.isNotEmpty ? type : primaryType;
    profileNotifier.value = activeProfileId; // après activeType pour que les listeners voient le bon type

    // Contact
    final fn = p['firstname']?.toString() ?? '';
    final ln = p['lastname']?.toString() ?? '';
    if (fn.isNotEmpty) firstname = fn;
    if (ln.isNotEmpty) lastname = ln;
    final ph = p['phone']?.toString() ?? '';
    if (ph.isNotEmpty) phone_number = ph;
    final av    = p['avatar_url']?.toString() ?? '';
    final avPro = p['profile_picture_url_pro']?.toString() ?? '';
    if (av.isNotEmpty) profilePictureUrl = av;
    // photo pro (logo élevage / cabinet) distincte de l'avatar personnel —
    // écrasement inconditionnel : sinon la photo du profil précédemment
    // actif reste affichée quand le profil nouvellement actif n'en a pas.
    profilePictureUrlElevage = avPro.isNotEmpty ? avPro : av;

    // Adresse pro (remplace les deux adresses)
    adress        = p['adresse']?.toString() ?? '';
    rue           = p['rue']?.toString() ?? '';
    ville         = p['ville']?.toString() ?? '';
    codePostal    = p['code_postal']?.toString() ?? '';
    pays          = p['pays']?.toString() ?? 'France';
    departement   = p['departement']?.toString() ?? '';
    region        = p['region']?.toString() ?? '';
    adressElevage    = adress;
    rueElevage       = rue;
    villeElevage     = ville;
    codePostalElevage = codePostal;
    paysElevage      = pays;
    departementElevage = departement;
    regionElevage    = region;

    // Flags de rôle (types V2 normalisés — doit rester synchro avec
    // _profileTypes dans add_profile_page.dart, seule source de vérité
    // des profile_type réellement enregistrés en base)
    const proTypes = {
      'veterinaire', 'sante', 'education', 'garde',
      'pension', 'toilettage', 'photographe', 'marechal_ferrant',
      'restauration',
    };
    isAssociation = type == 'association';
    isPro     = proTypes.contains(type);
    isElevage = type == 'eleveur';
    catPro       = p['cat_pro']?.toString() ?? (isPro ? type : '');
    professionPro = p['profession_pro']?.toString() ?? '';

    // Éleveur — colonne renommée name_elevage → nom en V2
    nameElevage    = p['nom']?.toString().isNotEmpty == true
        ? p['nom']!.toString()
        : p['name_elevage']?.toString().isNotEmpty == true
            ? p['name_elevage']!.toString()
            : p['profile_label']?.toString() ?? '';
    numeroElevage  = p['numero_elevage']?.toString() ?? '0000000000';
    acacedNumero   = p['acaced_numero']?.toString() ?? '';
    especesElevees = _safeStringList(p['especes_elevees'], []);

    // Pro avancé — écrasement inconditionnel : un changement de profil
    // actif doit refléter fidèlement le nouveau profil, y compris vide,
    // sinon la valeur du profil précédemment actif reste affichée.
    desc      = p['description']?.toString() ?? '';
    siret     = p['siret']?.toString() ?? '';
    siteWeb   = p['site_web']?.toString() ?? '';
    instagram = p['instagram']?.toString() ?? '';
    facebook  = p['facebook']?.toString() ?? '';
    bannerUrl = p['banner_url']?.toString() ?? '';
    verificationStatus = p['verification_status']?.toString() ?? 'none';
    kbisUrl = p['kbis_url']?.toString() ?? '';
    tarifs  = p['tarifs']?.toString() ?? '';
    photosGalerie = _safeStringList(p['photos_galerie'], []);
    especesAcceptees = _safeStringList(p['especes_acceptees'], []);

    final rawRayon = p['rayon_intervention'];
    rayonIntervention = rawRayon is int
        ? rawRayon
        : (int.tryParse(rawRayon?.toString() ?? '') ?? 0);

    if (p['horaires'] is Map) {
      try {
        horaires = Map<String, String>.from(
          (p['horaires'] as Map).map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')));
      } catch (_) {}
    } else {
      horaires = {};
    }

    acceptNewClients = p['accept_new_clients'] as bool? ?? true;
  }

  // Charge tous les profils depuis Supabase et applique le profil principal.
  // À appeler après chaque connexion Firebase réussie.
  static Future<void> loadProfiles(String firebaseUid) async {
    try {
      final rows = await Supabase.instance.client
          .from('user_profiles')
          .select()
          .eq('uid', firebaseUid)
          .order('is_main', ascending: false)
          .order('created_at', ascending: true)
          .timeout(const Duration(seconds: 10));
      final profiles = List<Map<String, dynamic>>.from(rows as List);
      availableProfiles = profiles;
      if (profiles.isEmpty) return;
      // Profil principal en premier (is_main=true) sinon premier disponible
      final main = profiles.firstWhere(
        (p) => p['is_main'] == true,
        orElse: () => profiles.first,
      );
      applyProfile(main);
    } catch (_) {}
  }

  static List<String> _safeStringList(dynamic raw, List<String> fallback) {
    if (raw is! List) return fallback;
    return raw.whereType<String>().toList();
  }

  static bool isProfileComplete() {
    if (isAdmin) return true;
    if (isPro) {
      return villeElevage.isNotEmpty && codePostalElevage.isNotEmpty;
    }
    if (isElevage) {
      return numeroElevage.isNotEmpty &&
             numeroElevage != '0000000000' &&
             villeElevage.isNotEmpty &&
             codePostalElevage.isNotEmpty;
    }
    return phone_number.isNotEmpty &&
           phone_number != '0000000000' &&
           ville.isNotEmpty &&
           codePostal.isNotEmpty;
  }
}

String getApiKey() {
  if (Platform.isIOS) {
    return 'AIzaSyDLJ3f3cu2MChItj0H4un2pdl9o0kCb4QM';
  } else if (Platform.isAndroid) {
    return 'AIzaSyCbhS2noQdmSZN6QnOsEjAN73uX5vjl6sI';
  } else {
    return 'AIzaSyD2ppVQEWJNom9l9Tk-SejgH11ffoIecjw'; // Par exemple, pour le web
  }
}

class UserStatus {
  static void setOnline() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'isOnline': true,
        'lastActive': FieldValue.serverTimestamp(),
      });
    }
  }

  static void setOffline() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'isOnline': false,
        'lastActive': FieldValue.serverTimestamp(),
      });
    }
  }
}

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } on FirebaseException catch (e) {
    if (e.code == 'duplicate-app') {
      print("duplicate");
    } else {
      rethrow;
    }
  }

  // Firebase App Check (anti-bot / anti-abus)
  await FirebaseAppCheck.instance.activate(
    androidProvider: kDebugMode
        ? AndroidProvider.debug
        : AndroidProvider.playIntegrity,
    appleProvider: kDebugMode
        ? AppleProvider.debug
        : AppleProvider.appAttest,
  );

  // Supabase
  await Supabase.initialize(
    url: 'https://zyvpngcvzrkdytypjlyq.supabase.co',
    anonKey: 'sb_publishable_a48hAJ3vGsQsgWVUbkReYQ_J71heKGK',
  );

  // Gestion des messages en arrière-plan
  try {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (_) {}

  // Initialiser les notifications locales
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  final DarwinInitializationSettings initializationSettingsIOS =
      DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true
          // Removed onDidReceiveLocalNotification as it might be deprecated or moved.
          );

  final InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid, iOS: initializationSettingsIOS);

  try {
    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        if (response.payload != null) {
          print('Notification cliquée avec payload : ${response.payload}');
        }
      },
    );
  } catch (_) {}

// Écoute des messages en premier plan
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print("Message reçu en premier plan : ${message.notification?.title}");

    RemoteNotification? notification = message.notification;
    if (notification != null) {
      flutterLocalNotificationsPlugin.show(
        id: 0,
        title: notification.title,
        body: notification.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'high_importance_channel',
            'High Importance Notifications',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
        payload: message.data['conversationId'],
      );
    }
  });

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    _handleNotifNavigation(message.data);
  });

  // App ouverte depuis une notif (état terminé)
  final initialMsg = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMsg != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleNotifNavigation(initialMsg.data));
  }
  WidgetsBinding.instance.addObserver(AppLifecycleObserver());
  try {
    await requestPermissions();
  } catch (_) {}

  // Sauvegarde immédiate si l'user est déjà connecté (timeout 5s max)
  try {
    await saveFcmTokenToFirestore().timeout(const Duration(seconds: 5));
  } catch (_) {}

  // Rafraîchir le token à chaque changement (reinstall, rotation clé FCM…)
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid)
          .set({'fcmToken': newToken}, SetOptions(merge: true));
      await Supabase.instance.client.from('users')
          .update({'fcm_token': newToken}).eq('uid', user.uid);
    } catch (_) {}
  });
  await Future.delayed(const Duration(seconds: 1));
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]).then((_) {
    runApp(MyApp());
  });

  await Future.delayed(const Duration(seconds: 1));
  FlutterNativeSplash.remove();
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [routeObserver],
          locale:
              Locale('fr', 'FR'), // Force l'application à utiliser le français
          supportedLocales: [
            Locale('en', 'US'),
            Locale('fr', 'FR'),
          ],

          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],

          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(1.0),
            ),
            child: child!,
          ),

          theme: ThemeData(
            colorScheme: ColorScheme.fromSwatch().copyWith(
              primary: const Color(0xFF6E9E57),
              secondary: const Color(0xFF0C5C6C),
            ),
            dividerColor: Colors.transparent,
            scaffoldBackgroundColor: const Color(0xFFF8F8F6),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xFF6E9E57),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
            buttonTheme: const ButtonThemeData(
              splashColor: Colors.transparent,
            ),
            primaryColor: const Color(0xFF6E9E57),
            listTileTheme: const ListTileThemeData(
              iconColor: Color(0xFF0C5C6C),
              textColor: Color(0xFF1F2A2E),
            ),
            cardTheme: CardThemeData(
              color: Colors.white,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFA7C79A)),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF6E9E57), width: 2),
              ),
            ),
          ),
          debugShowCheckedModeBanner: false,
          home: AuthWrapper(),
        );
  }
}

class AuthWrapper extends StatefulWidget {
  @override
  _AuthWrapperState createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  Future<bool>? _loadFuture;
  String? _loadedUid;

  Future<bool> _loadAll(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists) {
        User_Info.updateUserInfo(doc.data() as Map<String, dynamic>);
      }
      await User_Info.loadProfiles(uid);
    } catch (_) {}
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          _loadFuture = null;
          _loadedUid = null;
          return WelcomePage();
        }

        // Crée le Future une seule fois par UID pour éviter les rechargements
        if (_loadFuture == null || _loadedUid != user.uid) {
          _loadedUid = user.uid;
          _loadFuture = _loadAll(user.uid);
        }

        return FutureBuilder<bool>(
          future: _loadFuture,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (!snap.hasData) return WelcomePage();

            // Profil actif dans Supabase (contourne isValidate Firestore)
            final hasActiveProfile = User_Info.availableProfiles.any((p) {
              final s = (p['statut_pro'] ?? '').toString().toLowerCase();
              return s == 'actif' || s == 'validated';
            });
            final needsValidation = User_Info.isElevage || User_Info.isPro;

            if (User_Info.isAdmin || User_Info.isValidate || !needsValidation || hasActiveProfile) {
              return BottomNav();
            } else {
              return VerificationRegistrationPage();
            }
          },
        );
      },
    );
  }
}

class AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // L'application est ouverte
      UserStatus.setOnline();
    } else if (state == AppLifecycleState.paused) {
      // L'application est en arrière-plan
      UserStatus.setOffline();
    }
  }
}
