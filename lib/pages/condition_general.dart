import 'package:PetsMatch/animation/delayed_animation.dart';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/eleveur/verification_page.dart';
import 'package:PetsMatch/pages/particulier/verifemail.dart';
import 'package:PetsMatch/utils.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:PetsMatch/pages/bottom_nav.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

class ConditionGeneral extends StatefulWidget {
  const ConditionGeneral({super.key});

  @override
  State<ConditionGeneral> createState() => _ConditionGeneralState();
}

class _ConditionGeneralState extends State<ConditionGeneral>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isAcceptedCGU = false;
  bool _isAcceptedMentions = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Center(
          child: DelayedAnimation(
            delay: 0,
            child: Column(
              children: [
                SizedBox(
                  width: UTILS.widthReference(context),
                  height:
                      UTILS.calculHeight(104, UTILS.heightReference(context)),
                  child: Stack(
                    children: [
                      Image.asset(
                        'assets/deco/arrondi_rose_2.png',
                        fit: BoxFit.cover,
                        width: UTILS.calculWidth(
                            211, UTILS.widthReference(context)),
                        height: UTILS.calculHeight(
                            104, UTILS.heightReference(context)),
                      ),
                      Positioned(
                        top: UTILS.calculHeight(
                            42, UTILS.heightReference(context)),
                        left: UTILS.calculWidth(
                            10, UTILS.widthReference(context)),
                        child: IconButton(
                          icon: Icon(Icons.arrow_back,
                              color: Colors.black), // Icône de la flèche noire
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                        ),
                      ),
                      Positioned(
                        top: UTILS.calculHeight(
                            53, UTILS.heightReference(context)),
                        left: 0,
                        right: 0,
                        child: Align(
                          alignment: Alignment.center,
                          child: Text(
                            'CGU',
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
                    ],
                  ),
                ),
                SizedBox(
                    height:
                        UTILS.calculHeight(14, UTILS.heightReference(context))),
                Align(
                  alignment: Alignment(-0.8, 0),
                  child: Text(
                    "Conditions Générales d'Utilisation",
                    style: TextStyle(
                      fontSize:
                          UTILS.calculWidth(20, UTILS.widthReference(context)),
                      fontFamily: 'Galey',
                      color: Color.fromARGB(255, 0, 0, 0),
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.left,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    """

1. Objet
   Les présentes Conditions Générales d'Utilisation (CGU) ont pour objet de définir les conditions dans lesquelles les utilisateurs peuvent accéder et utiliser l'application mobile "PetsMatch". En accédant à l'application, vous acceptez pleinement et sans réserve les présentes CGU et des Conditions général d'utilisation EULA.

2.Éditeur de l'application
  L'application est éditée par :
    - Nom de la société : PetsMatch
    - Forme juridique : SAS
    - Capital social : 1000 euros
    - Siège social : La ville marchand, Plumieux, France
    - RCS : 931 344 816
    - Numéro de TVA intracommunautaire : FR94931344816
    - Directeurs de la publication : Mr ALLEE, Mr KSOURI
    - Contact : petsmatch.contact@gmail.com

3.Accès à l'application
  3.1. Conditions d'accès
    - L'accès à certaines fonctionnalités de l'application nécessite la création d'un compte utilisateur.
    - L'utilisation de l'application est interdite aux mineurs de moins de 18 ans sans consentement parental explicite.
    - Les utilisateurs doivent fournir des informations exactes lors de leur inscription et sont responsables de la sécurité de leurs identifiants de connexion.
  3.2. Services disponibles
    L'application propose des services de mise en relation entre particuliers, éleveurs et professionnels pour :
    - La vente et l'achat d'animaux domestiques.
    - Les services liés aux animaux (pet-sitting, dressage, etc.).

4.  Règles de conduite et charte de bienséance
  Les utilisateurs doivent respecter les règles suivantes :
    - Contenus interdits : Toute publication ou comportement à caractère haineux, discriminatoire, diffamatoire, obscène, ou incitant à des activités illégales est strictement prohibé.
    - Respect dans les échanges : Les utilisateurs doivent faire preuve de courtoisie dans leurs communications via la messagerie interne.
    - Pratiques interdites : Les spams, fraudes, et publicités non autorisées sont interdits.
  En cas de non-respect de ces règles, PetsMatch se réserve le droit de suspendre ou supprimer un compte utilisateur.

5. Droits des utilisateurs
  5.1. Droits d'accès, de rectification et de suppression des données
    Les utilisateurs disposent des droits suivants concernant leurs données personnelles :
    - Demander l'accès, la rectification ou la suppression de leurs données.
    - Retirer leur consentement pour le traitement des données.
  5.2. Opposition et portabilité
    - S'opposer au traitement de leurs données à des fins marketing.
    - Demander la portabilité de leurs données personnelles.
    Pour exercer ces droits, les utilisateurs peuvent contacter PetsMatch à petsmatch.contact@gmail.com.

6. Responsabilités
  6.1. Responsabilité de PetsMatch
    - PetsMatch met en place un système de contrôle pour vérifier les annonces publiées, mais ne peut garantir l'absence totale de contenu illicite.
    - L'application ne peut être tenue responsable des dommages directs ou indirects liés à l'utilisation de ses services.
  6.2. Responsabilité des utilisateurs
    - Les utilisateurs sont responsables des informations publiées sur l'application.
    - Ils s'engagent à respecter les lois en vigueur et les présentes CGU.


7. Propriété intellectuelle
  Tous les contenus présents sur l'application (textes, images, logos, etc.) sont protégés par les lois sur la propriété intellectuelle. Toute reproduction ou utilisation sans autorisation est interdite.

8. Données personnelles
  8.1. Traitement des données
    Les données collectées sont utilisées pour :
    - La gestion des annonces et des transactions.
    - La mise en relation entre utilisateurs.
    - L'amélioration des services.
  8.2. Conservation et sécurité
    PetsMatch s'engage à protéger les données personnelles conformément à la législation en vigueur (RGPD).

9. Modifications des CGU
  PetsMatch se réserve le droit de modifier à tout moment les présentes CGU. Les utilisateurs seront informés des changements majeurs.

10. Litiges et loi applicable
  En cas de litige, les parties s'engagent à rechercher une solution amiable. Les présentes CGU sont soumises à la loi française, et tout différend sera de la compétence exclusive des tribunaux de Paris.
  Pour toute question, veuillez nous contacter à : petsmatch.contact@gmail.com.

DROITS DES UTILISATEURS

Droits d'Accès

1. Accès aux Données Personnelles

   - Collecte de données: Les utilisateurs ont le droit de savoir quelles données personnelles sont collectées par notre application, comment elles sont utilisées, et à qui elles peuvent être divulguées.
   - Accès aux données: Les utilisateurs ont le droit de demander l'accès aux données personnelles que nous détenons à leur sujet. Cette demande peut être faite via notre formulaire de contact ou en nous envoyant un courriel à petsmatch.contact@gmail.com.
   - Rectification des données: Les utilisateurs ont le droit de demander la correction de données personnelles inexactes ou incomplètes.
   - Suppression des données: Les utilisateurs peuvent demander la suppression de leurs données personnelles, sauf si nous avons une obligation légale de les conserver.

2. Accès à l’Application

   - Création de compte: L'accès à certaines fonctionnalités de l'application nécessite la création d'un compte utilisateur. Les utilisateurs doivent fournir des informations exactes et complètes lors de l'inscription.
   - Utilisation du compte: Les utilisateurs sont responsables de la sécurité de leurs identifiants de connexion et de toutes les activités effectuées sous leur compte. Le partage de comptes est interdit.
   - Révocation d'accès: Nous nous réservons le droit de révoquer l'accès à l'application ou à certaines de ses fonctionnalités en cas de violation des conditions d'utilisation.

3. Accès des Mineurs

   - Restrictions d'âge: L'utilisation de notre application est interdite aux personnes de moins de [âge minimum] sans le consentement explicite d'un parent ou d'un tuteur.
   - Vérification du consentement: Nous pouvons demander des preuves du consentement parental pour les utilisateurs mineurs.

4. Accès au Contenu Utilisateur

   - Publication de contenu: Les utilisateurs peuvent publier du contenu sur l'application, sous réserve de respecter les règles de conduite définies dans les conditions d'utilisation.
   - Droits sur le contenu: En publiant du contenu sur notre application, les utilisateurs nous accordent une licence non exclusive, mondiale, libre de droits et transférable pour utiliser, modifier, et afficher ce contenu.

5. Accès aux Services Tiers

   - Intégration de services tiers: Notre application peut intégrer des services tiers, tels que des bibliothèques logicielles ou des API. Les utilisateurs doivent se conformer aux conditions d'utilisation de ces services tiers.
   - Données partagées avec des tiers: Les utilisateurs seront informés lorsque leurs données personnelles sont partagées avec des services tiers, et leur consentement sera obtenu lorsque requis par la loi.

6. Accès pour les Utilisateurs en Situation de Handicap

   - Accessibilité: Nous nous engageons à rendre notre application accessible à tous les utilisateurs, y compris ceux ayant des handicaps. Nous respectons les directives WCAG [Web Content Accessibility Guidelines] pour garantir l'accessibilité.
   - Assistance: Des options d'assistance sont disponibles pour aider les utilisateurs en situation de handicap à naviguer et à utiliser l'application.

Pour toute question concernant les droits d'accès ou pour exercer vos droits, veuillez contacter notre équipe de support à petsmatch.contact@gmail.com ou via notre formulaire de contact sur l'application.

Droits de Rectification

1. Droit à la Rectification des Données Personnelles

   - Exactitude des Données: Les utilisateurs ont le droit de demander la correction de toute donnée personnelle inexacte ou incomplète que nous détenons à leur sujet.
   - Procédure de Rectification: Les demandes de rectification peuvent être soumises en nous contactant à petsmatch.contact@gmail.com ou via notre formulaire de contact sur l'application. Nous traiterons ces demandes dans un délai raisonnable et informerons les utilisateurs des actions prises.
   - Confirmation de Correction: Après avoir corrigé les données personnelles, nous enverrons une confirmation aux utilisateurs indiquant que les modifications ont été effectuées.

2. Identification et Authentification

   - Vérification de l'Identité: Pour protéger la confidentialité des données personnelles, nous pouvons demander aux utilisateurs de vérifier leur identité avant de traiter une demande de rectification. Cela peut inclure la fourniture d'informations supplémentaires ou de documents d'identification.
   - Informations Exactes: Les utilisateurs doivent fournir des informations exactes et à jour lors de la soumission d'une demande de rectification.

3. Données Non Modifiables

   -Limites de Rectification: Certaines données ne peuvent pas être modifiées si elles sont nécessaires pour la gestion correcte des services ou si elles sont soumises à des obligations légales spécifiques. Dans de tels cas, nous informerons les utilisateurs des raisons pour lesquelles les données ne peuvent pas être modifiées.

4. Rectification de Contenu Utilisateur

   - Modification du Contenu Publié: Les utilisateurs ont la possibilité de modifier ou de supprimer le contenu qu'ils ont publié sur l'application, sous réserve des conditions d'utilisation.
   - Responsabilité du Contenu: Les utilisateurs sont responsables de l'exactitude des informations qu'ils publient et doivent s'assurer que toute modification respecte les règles de conduite de l'application.

5. Notifications aux Tiers

   - Communication des Modifications: Si les données personnelles corrigées ont été partagées avec des tiers, nous nous engageons à informer ces tiers des modifications, sauf si cela se révèle impossible ou implique des efforts disproportionnés.

6. Assistance à la Rectification

   - Support Utilisateur: Pour toute assistance concernant les demandes de rectification, les utilisateurs peuvent contacter notre équipe de support à petsmatch.contact@gmail.com ou via notre formulaire de contact sur l'application. Nous nous efforcerons de fournir un support rapide et efficace pour résoudre les problèmes de rectification.

7. Documentation des Modifications

   - Historique des Modifications: Nous pouvons conserver un enregistrement des modifications apportées aux données personnelles pour des raisons de sécurité et de conformité légale. Cet historique sera conservé de manière sécurisée et uniquement accessible au personnel autorisé.

Pour exercer vos droits de rectification, veuillez contacter notre équipe de support à petsmatch.contact@gmail.com ou via notre formulaire de contact sur l'application. Nous nous engageons à traiter votre demande avec diligence et à vous tenir informé des progrès réalisés.

Droits d'Effacement

1. Droit à l'Effacement des Données Personnelles

   - Demande de Suppression: Les utilisateurs ont le droit de demander la suppression de leurs données personnelles que nous détenons. Les demandes peuvent être soumises en nous contactant à petsmatch.contact@gmail.com ou via notre formulaire de contact sur l'application.
   - Conditions d'Effacement: Les demandes d'effacement seront traitées sous réserve des conditions suivantes :
     - Les données ne sont plus nécessaires pour les finalités pour lesquelles elles ont été collectées.
     - L'utilisateur retire son consentement et il n'existe pas d'autre base juridique pour le traitement.
     - Les données ont été traitées de manière illicite.
     - Les données doivent être effacées pour respecter une obligation légale.

2. Exceptions au Droit d'Effacement

   - Obligations Légales: Nous ne pourrons pas accéder à une demande de suppression si la conservation des données est nécessaire pour respecter une obligation légale, pour l'exercice ou la défense de droits en justice, ou pour des raisons d'intérêt public dans le domaine de la santé publique.
   - Intérêts Légitimes: Si nous avons des intérêts légitimes impérieux pour conserver les données, nous informerons les utilisateurs des raisons pour lesquelles la demande de suppression ne peut pas être satisfaite.

3. Procédure de Suppression

   - Vérification de l'Identité: Pour protéger la confidentialité des données personnelles, nous pouvons demander aux utilisateurs de vérifier leur identité avant de traiter une demande d'effacement. Cela peut inclure la fourniture d'informations supplémentaires ou de documents d'identification.
   - Confirmation de Suppression: Après avoir supprimé les données personnelles, nous enverrons une confirmation aux utilisateurs indiquant que les données ont été effacées.

4. Suppression de Contenu Utilisateur

   - Contenu Publié: Les utilisateurs peuvent supprimer le contenu qu'ils ont publié sur l'application, sous réserve des conditions d'utilisation. Cette suppression peut être effectuée directement via les paramètres de l'application ou en contactant notre support.
   - Responsabilité du Contenu: Les utilisateurs sont responsables des actions liées à la suppression de leur contenu et doivent s'assurer que cette suppression respecte les règles de conduite de l'application.

5. Notifications aux Tiers

   - Communication des Suppressions: Si les données personnelles supprimées ont été partagées avec des tiers, nous nous engageons à informer ces tiers de la suppression, sauf si cela se révèle impossible ou implique des efforts disproportionnés.

6. Effacement Sécurisé

   - Méthodes de Suppression: Les données personnelles seront supprimées de manière sécurisée pour éviter tout accès non autorisé, toute perte ou toute modification des données effacées.
   - Conservation Limitée: Les données nécessaires pour la documentation des demandes de suppression et pour se conformer aux obligations légales seront conservées de manière sécurisée et uniquement accessibles au personnel autorisé.

7. Assistance à l'Effacement

   - Support Utilisateur: Pour toute assistance concernant les demandes d'effacement, les utilisateurs peuvent contacter notre équipe de support à petsmatch.contact@gmail.com ou via notre formulaire de contact sur l'application. Nous nous efforcerons de fournir un support rapide et efficace pour traiter les demandes de suppression.

Pour exercer vos droits d'effacement, veuillez contacter notre équipe de support à petsmatch.contact@gmail.com ou via notre formulaire de contact sur l'application. Nous nous engageons à traiter votre demande avec diligence et à vous tenir informé des progrès réalisés.

Droits de Limitation du Traitement

1. Droit à la Limitation du Traitement des Données Personnelles

   - Demande de Limitation: Les utilisateurs ont le droit de demander la limitation du traitement de leurs données personnelles dans certaines situations. Les demandes peuvent être soumises en nous contactant à petsmatch.contact@gmail.com ou via notre formulaire de contact sur l'application.
   - Conditions de Limitation: Les demandes de limitation du traitement seront traitées sous réserve des conditions suivantes :
     - L'exactitude des données personnelles est contestée par l'utilisateur, pendant la période nécessaire pour vérifier l'exactitude des données.
     - Le traitement est illicite et l'utilisateur s'oppose à l'effacement des données et demande à la place la limitation de leur utilisation.
     - Nous n'avons plus besoin des données personnelles aux fins du traitement, mais elles sont encore nécessaires à l'utilisateur pour la constatation, l'exercice ou la défense de droits en justice.
     - L'utilisateur s'est opposé au traitement, pendant la vérification portant sur le point de savoir si les motifs légitimes poursuivis par le responsable du traitement prévalent sur ceux de l'utilisateur.

2. Effets de la Limitation du Traitement

   - Suspension du Traitement: Lorsqu'une limitation du traitement est accordée, nous cesserons de traiter les données personnelles concernées, à l'exception de leur conservation.
   - Notification des Changements: Les utilisateurs seront informés avant que la limitation du traitement ne soit levée.

3. Identification et Authentification

   - Vérification de l'Identité: Pour protéger la confidentialité des données personnelles, nous pouvons demander aux utilisateurs de vérifier leur identité avant de traiter une demande de limitation. Cela peut inclure la fourniture d'informations supplémentaires ou de documents d'identification.
   - Informations Exactes: Les utilisateurs doivent fournir des informations exactes et à jour lors de la soumission d'une demande de limitation.

4. Notifications aux Tiers

   - Communication des Limitations: Si les données personnelles dont le traitement est limité ont été partagées avec des tiers, nous nous engageons à informer ces tiers de la limitation, sauf si cela se révèle impossible ou implique des efforts disproportionnés.

5. Assistance à la Limitation du Traitement

   - Support Utilisateur: Pour toute assistance concernant les demandes de limitation du traitement, les utilisateurs peuvent contacter notre équipe de support à petsmatch.contact@gmail.com ou via notre formulaire de contact sur l'application. Nous nous efforcerons de fournir un support rapide et efficace pour traiter les demandes de limitation.

6. Documentation des Modifications

   - Historique des Modifications: Nous pouvons conserver un enregistrement des limitations appliquées aux données personnelles pour des raisons de sécurité et de conformité légale. Cet historique sera conservé de manière sécurisée et uniquement accessible au personnel autorisé.

Pour exercer vos droits de limitation du traitement, veuillez contacter notre équipe de support à petsmatch.contact@gmail.com ou via notre formulaire de contact sur l'application. Nous nous engageons à traiter votre demande avec diligence et à vous tenir informé des progrès réalisés.

Droits de Portabilité

1. Droit à la Portabilité des Données Personnelles

   - Demande de Portabilité: Les utilisateurs ont le droit de demander la portabilité de leurs données personnelles que nous détenons. Les demandes peuvent être soumises en nous contactant à petsmatch.contact@gmail.com ou via notre formulaire de contact sur l'application.
   - Conditions de Portabilité: Les données personnelles doivent être fournies par l'utilisateur, traitées de manière automatisée et sur la base du consentement de l'utilisateur ou de l'exécution d'un contrat.

2. Portabilité des Données

   - Format des Données: Les données personnelles seront fournies dans un format structuré, couramment utilisé et lisible par machine. Par exemple, les données peuvent être fournies sous forme de fichiers CSV ou JSON.
   - Transfert Direct: Les utilisateurs ont le droit de demander que leurs données personnelles soient transmises directement à un autre responsable de traitement, lorsque cela est techniquement possible.

3. Procédure de Portabilité

   - Vérification de l'Identité: Pour protéger la confidentialité des données personnelles, nous pouvons demander aux utilisateurs de vérifier leur identité avant de traiter une demande de portabilité. Cela peut inclure la fourniture d'informations supplémentaires ou de documents d'identification.
   - Délai de Traitement: Les demandes de portabilité seront traitées dans un délai raisonnable. Nous informerons les utilisateurs des actions prises et des délais estimés pour le transfert des données.

4. Données Incluses dans la Portabilité

   - Types de Données: Les données personnelles concernées par le droit à la portabilité incluent, mais ne sont pas limitées à, les informations de contact, les préférences utilisateur, l'historique des transactions, et d'autres données collectées par notre application.
   - Exclusions: Les données dérivées ou inférées par nous à partir des données fournies par l'utilisateur ne sont pas incluses dans le droit à la portabilité.

5. Notifications aux Tiers

   - Communication des Transferts: Si les données personnelles portées ont été partagées avec des tiers, nous nous engageons à informer ces tiers du transfert, sauf si cela se révèle impossible ou implique des efforts disproportionnés.

6. Assistance à la Portabilité des Données

   - Support Utilisateur: Pour toute assistance concernant les demandes de portabilité des données, les utilisateurs peuvent contacter notre équipe de support à petsmatch.contact@gmail.com ou via notre formulaire de contact sur l'application. Nous nous efforcerons de fournir un support rapide et efficace pour traiter les demandes de portabilité.

7. Documentation des Transferts

   - Historique des Transferts: Nous pouvons conserver un enregistrement des transferts de données personnelles pour des raisons de sécurité et de conformité légale. Cet historique sera conservé de manière sécurisée et uniquement accessible au personnel autorisé.

Pour exercer vos droits de portabilité, veuillez contacter notre équipe de support à petsmatch.contact@gmail.com ou via notre formulaire de contact sur l'application. Nous nous engageons à traiter votre demande avec diligence et à vous tenir informé des progrès réalisés.

Droits d'Opposition

1. Droit d'Opposition au Traitement des Données Personnelles

   - Demande d'Opposition: Les utilisateurs ont le droit de s'opposer à tout moment au traitement de leurs données personnelles pour des raisons tenant à leur situation particulière. Les demandes peuvent être soumises en nous contactant à petsmatch.contact@gmail.com ou via notre formulaire de contact sur l'application.
   - Conditions d'Opposition: Le droit d'opposition s'applique lorsque le traitement des données est basé sur l'intérêt légitime ou est effectué à des fins de marketing direct.

2. Opposition au Marketing Direct

   - Marketing Direct: Les utilisateurs peuvent s'opposer à tout moment au traitement de leurs données personnelles à des fins de marketing direct. Une telle demande sera honorée sans condition et le traitement sera arrêté immédiatement.
   - Procédure: Les utilisateurs peuvent se désabonner des communications marketing en utilisant le lien de désinscription inclus dans chaque message ou en nous contactant directement à petsmatch.contact@gmail.com.

3. Opposition pour Raisons Légitimes

   - Intérêt Légitime: Si le traitement est basé sur notre intérêt légitime, les utilisateurs peuvent s'opposer au traitement de leurs données personnelles. Nous cesserons le traitement sauf si nous pouvons démontrer des motifs légitimes impérieux pour le traitement qui prévalent sur les intérêts, droits et libertés de l'utilisateur, ou pour la constatation, l'exercice ou la défense de droits en justice.

4. Procédure d'Opposition

   - Vérification de l'Identité: Pour protéger la confidentialité des données personnelles, nous pouvons demander aux utilisateurs de vérifier leur identité avant de traiter une demande d'opposition. Cela peut inclure la fourniture d'informations supplémentaires ou de documents d'identification.
   - Délai de Traitement: Les demandes d'opposition seront traitées dans un délai raisonnable. Nous informerons les utilisateurs des actions prises et des délais estimés pour la cessation du traitement.

5. Notifications aux Tiers

   - Communication des Oppositions: Si les données personnelles concernées par l'opposition ont été partagées avec des tiers, nous nous engageons à informer ces tiers de l'opposition, sauf si cela se révèle impossible ou implique des efforts disproportionnés.

6. Assistance à l'Opposition

   - Support Utilisateur: Pour toute assistance concernant les demandes d'opposition, les utilisateurs peuvent contacter notre équipe de support à petsmatch.contact@gmail.com ou via notre formulaire de contact sur l'application. Nous nous efforcerons de fournir un support rapide et efficace pour traiter les demandes d'opposition.

7. Documentation des Oppositions

   - Historique des Oppositions: Nous pouvons conserver un enregistrement des oppositions pour des raisons de sécurité et de conformité légale. Cet historique sera conservé de manière sécurisée et uniquement accessible au personnel autorisé.

Pour exercer vos droits d'opposition, veuillez contacter notre équipe de support à petsmatch.contact@gmail.com ou via notre formulaire de contact sur l'application. Nous nous engageons à traiter votre demande avec diligence et à vous tenir informé des progrès réalisés.

Droits Après la Mort

1. Droit à la Conservation des Données Personnelles

   - Conservation des Données: Les données personnelles d'un utilisateur décédé seront conservées conformément aux lois applicables et à notre politique de conservation des données, sauf demande contraire des héritiers légaux ou du représentant autorisé de l'utilisateur.

2. Droit à la Suppression des Données

   - Demande de Suppression: Les héritiers légaux ou le représentant autorisé peuvent demander la suppression des données personnelles d'un utilisateur décédé. Les demandes peuvent être soumises en nous contactant à petsmatch.contact@gmail.com ou via notre formulaire de contact sur l'application.
   - Vérification de l'Identité: Pour protéger la confidentialité des données personnelles, nous demanderons des preuves de l'autorité légale pour agir au nom de l'utilisateur décédé, telles que des documents légaux ou des ordonnances judiciaires.

3. Droit d'Accès et de Rectification

   - Accès aux Données: Les héritiers légaux ou le représentant autorisé peuvent demander l'accès aux données personnelles de l'utilisateur décédé pour des raisons spécifiques, telles que la gestion des affaires posthumes.
   - Rectification des Données: Les héritiers légaux ou le représentant autorisé peuvent demander la rectification des données personnelles inexactes ou incomplètes de l'utilisateur décédé.

4. Droit d'Opposition au Traitement

   - Opposition au Traitement: Les héritiers légaux ou le représentant autorisé peuvent s'opposer au traitement des données personnelles de l'utilisateur décédé. Nous cesserons le traitement sauf si nous pouvons démontrer des motifs légitimes impérieux pour le traitement qui prévalent sur les intérêts et droits des héritiers légaux.

5. Instructions Posthumes

   - Respect des Instructions: Si l'utilisateur décédé a laissé des instructions spécifiques concernant la gestion de ses données personnelles après sa mort, nous nous engageons à respecter ces instructions, sous réserve des obligations légales et des capacités techniques.

6. Notifications et Assistance

   - Support aux Héritiers: Pour toute assistance concernant les droits après la mort, les héritiers légaux ou le représentant autorisé peuvent contacter notre équipe de support à petsmatch.contact@gmail.com ou via notre formulaire de contact sur l'application. Nous nous efforcerons de fournir un support rapide et efficace pour traiter les demandes.
   - Notification des Actions: Nous informerons les héritiers légaux ou le représentant autorisé des actions prises en réponse à leurs demandes et des délais estimés pour leur traitement.

7. Documentation des Actions Posthumes

   - Historique des Actions: Nous pouvons conserver un enregistrement des actions prises en réponse aux demandes concernant les données personnelles d'un utilisateur décédé pour des raisons de sécurité et de conformité légale. Cet historique sera conservé de manière sécurisée et uniquement accessible au personnel autorisé.

Pour exercer les droits concernant les données personnelles d'un utilisateur décédé, veuillez contacter notre équipe de support à petsmatch.contact@gmail.com ou via notre formulaire de contact sur l'application. Nous nous engageons à traiter votre demande avec diligence et à vous tenir informé des progrès réalisés.

Conditions Générales d'Utilisation (EULA) – PetsMatch

Dernière mise à jour : 17/04/2025

Bienvenue sur PetsMatch, une application dédiée à la mise en relation des amoureux des animaux.

En utilisant cette application, vous acceptez les présentes Conditions Générales d'Utilisation (EULA).

I. Acceptation des conditions
  L'utilisation de PetsMatch implique l'acceptation pleine et entière de ces conditions. Si vous n'acceptez pas ces termes, veuillez ne pas utiliser l'application.

II. Compte utilisateur
    - Vous devez être âgé de 18 ans ou plus pour utiliser PetsMatch.
    - Vous êtes responsable de l'exactitude des informations fournies lors de votre inscription.
    - Toute usurpation d'identité, contenu frauduleux ou non conforme pourra entraîner une suspension
      immédiate de votre compte.

III. Comportement et contenu autorisé

  Politique de tolérance zéro :
    PetsMatch applique une politique de tolérance zéro envers :
      - Les propos haineux, discriminatoires ou harcelants.
      - Les contenus violents, pornographiques, inappropriés ou abusifs.
      - Le spam, la fraude ou toute tentative de manipulation.
    Tout contenu ou comportement abusif signalé fera l’objet d’une modération sous 24 heures. Si la
    violation est confirmée, le contenu sera supprimé et l’utilisateur responsable banni définitivement.

IV. Signalement et modération

    - Chaque utilisateur peut signaler du contenu ou un autre utilisateur via les options prévues à cet
      effet.
    - Les équipes de PetsMatch traiteront les signalements dans les plus brefs délais (généralement sous
    24h).
    - L’utilisateur peut également bloquer un autre utilisateur, ce qui empêchera toute interaction entre
      eux.
V. Propriété intellectuelle

    - Tous les éléments de l'application (textes, images, logos, code) sont la propriété exclusive de
      PetsMatch, sauf indication contraire.
    - Toute reproduction ou réutilisation sans autorisation est interdite.

VI. Données personnelles

    - Vos données sont traitées avec respect, conformément à notre Politique de Confidentialité.
    - Vous pouvez à tout moment demander la suppression de vos données en nous contactant.

VII. Responsabilité
    - PetsMatch n’est pas responsable des interactions entre utilisateurs. Cependant, nous nous
      engageons à intervenir rapidement en cas de signalement conforme.
    - L'application peut contenir des liens vers des sites tiers ; nous ne sommes pas responsables de leur
      contenu.

VIII. Modification des conditions

  PetsMatch se réserve le droit de modifier ces conditions à tout moment. En cas de mise à jour, vous
  serez informé via l'application.

IX. Contact
  
Pour toute question ou réclamation, contactez-nous à l’adresse : petsmatch.contact@gmail.com
                    """,
                    style: TextStyle(fontSize: 16),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Checkbox(
                      value: _isAcceptedCGU,
                      onChanged: (bool? value) {
                        setState(() {
                          _isAcceptedCGU = value ?? false;
                        });
                      },
                    ),
                    Text("J'ai lu et j'accepte les conditions d'utilisation")
                  ],
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color.fromARGB(
                        255, 255, 192, 187), // Couleur de fond du bouton
                  ),
                  onPressed: _isAcceptedCGU
                      ? () {
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (context) => MentionsLegales()));
                        }
                      : null,
                  child: Text("Continuer"),
                ),
                SizedBox(
                    height:
                        UTILS.calculHeight(30, UTILS.heightReference(context))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MentionsLegales extends StatefulWidget {
  @override
  State<MentionsLegales> createState() => _MentionsLegalesState();
}

void _sendRegistrationEmail(Object uid) async {
  String username =
      'petsmatch.contact@gmail.com'; // Remplacez par votre adresse email
  String password =
      'dppu ctgp buve bxjd'; // Remplacez par votre mot de passe d'application (ou le mot de passe de l'email, si applicable)

  final smtpServer = gmail(username, password);

  String documents = User_Info.documentElevage.map((doc) {
    return '''
      Catégorie: ${doc['category']}
      Nom: ${doc['name']}
      Téléchargé: ${doc['uploaded']}
      URL: ${doc['url']}
    ''';
  }).join('\n');

  final message = Message()
    ..from = Address(username, 'Application PetsMatch')
    ..recipients.add('petsmatch.contact@gmail.com')
    ..subject = 'Nouvelle Inscription Professionnel'
    ..text = '''
      Détails de l'inscription:
      UID: ${uid}
      Nom: ${User_Info.firstname} ${User_Info.lastname}
      Email: ${User_Info.email}
      Date de naissance: ${User_Info.dateofbirth}
      Code ISO: ${User_Info.codeISO}
      Numéro de téléphone: ${User_Info.phone_number}
      Adresse: ${User_Info.adress}
      Élevage: ${User_Info.isElevage ? "Oui" : "Non"}
      Societé: ${User_Info.isPro ? "Oui" : "Non"}
      Adresse de l'élevage ou societé: ${User_Info.adressElevage}
      Nom de l'élevage ou société: ${User_Info.nameElevage}
      Code ISO Elevage ou société: ${User_Info.codeISOElevage}
      Numéro de l'élevage: ${User_Info.numeroElevage}
      Développeur: ${User_Info.isDev ? "Oui" : "Non"}
      Description: ${User_Info.desc}
      Projet d'adoption: ${User_Info.adoptProject}
      Description de l'entreprise: ${User_Info.descEntreprise}
      Categorie pro: ${User_Info.catPro},
      Profession pro: ${User_Info.professionPro},
      Documents d'élevage ou de societé:
      $documents
    ''';

  try {
    final sendReport = await send(message, smtpServer);
    print('Message envoyé: ' + sendReport.toString());
  } on MailerException catch (e) {
    print('Message non envoyé. $e');
    for (var p in e.problems) {
      print('Problème: ${p.code}: ${p.msg}');
    }
  }
}

class _MentionsLegalesState extends State<MentionsLegales> {
  bool _isAcceptedMentions = false;
  void _validateAndContinue() async {
    try {
      UserCredential userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: User_Info.email,
        password: User_Info.password,
      );
      User_Info.uid = userCredential.user!.uid;

      User? user = userCredential.user;
      Object isRegistered =
          await registerElevage(User_Info.email, User_Info.password);
      if (User_Info.isElevage) {
        _sendRegistrationEmail(isRegistered);
      }
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => VerifyEmailPage(email: User_Info.email),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      if (e.code == 'email-already-in-use') {
        errorMessage = "Cet e-mail est déjà enregistré.";
      } else if (e.code == 'invalid-email') {
        errorMessage = "Cet e-mail n'est pas valide.";
      } else if (e.code == 'weak-password') {
        errorMessage = "Le mot de passe est trop faible.";
      } else {
        errorMessage = "Une erreur est survenue. Veuillez réessayer.";
      }

      // Affichage du message d'erreur avec un Snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Center(
          child: DelayedAnimation(
            delay: 0,
            child: Column(
              children: [
                SizedBox(
                  width: UTILS.widthReference(context),
                  height:
                      UTILS.calculHeight(104, UTILS.heightReference(context)),
                  child: Stack(
                    children: [
                      Image.asset(
                        'assets/deco/arrondi_rose_2.png',
                        fit: BoxFit.cover,
                        width: UTILS.calculWidth(
                            211, UTILS.widthReference(context)),
                        height: UTILS.calculHeight(
                            104, UTILS.heightReference(context)),
                      ),
                      Positioned(
                        top: UTILS.calculHeight(
                            42, UTILS.heightReference(context)),
                        left: UTILS.calculWidth(
                            10, UTILS.widthReference(context)),
                        child: IconButton(
                          icon: Icon(Icons.arrow_back,
                              color: Colors.black), // Icône de la flèche noire
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                        ),
                      ),
                      Positioned(
                        top: UTILS.calculHeight(
                            53, UTILS.heightReference(context)),
                        left: 0,
                        right: 0,
                        child: Align(
                          alignment: Alignment.center,
                          child: Text(
                            'Mentions Légales',
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
                    ],
                  ),
                ),
                SizedBox(
                    height:
                        UTILS.calculHeight(14, UTILS.heightReference(context))),
                Align(
                  alignment: Alignment(-0.8, 0),
                  child: Text(
                    "Mentions Légales",
                    style: TextStyle(
                      fontSize:
                          UTILS.calculWidth(25, UTILS.widthReference(context)),
                      fontFamily: 'Galey',
                      color: Color.fromARGB(255, 0, 0, 0),
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.left,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    """
1. Éditeur de l’application
  -  Dénomination sociale : PETSMATCH (PM)
  -  Forme juridique : SAS (Société par Actions Simplifiée)
  -  Adresse du siège social : 15 La Ville Marchand, 22210 Plumieux, France
  -  SIREN : 931 344 816
  -  SIRET : 931 344 816 00018
  -  Numéro de TVA Intracommunautaire : FR94 931 344 816
  -  Date de création : 20 juillet 2024
  -  Email de contact : petsmatch.contact@gmail.com
  -  Téléphone : 07 81 03 49 84

2. Responsable de la publication
  -  Nom : Nabil Ksouri
  -  Fonction : Président de PETSMATCH SAS
  -  Nom: Mevinn Allee
  -  Fonction: Directeur général de PETSMATCH SAS

3. Hébergement de l’application
  -  Nom de l’hébergeur : Google Firebase (Google LLC)
  -  Adresse : 1600 Amphitheatre Parkway, Mountain View, CA 94043, USA
  -  Contact : support@firebase.google.com
  Si un hébergeur additionnel est utilisé pour votre site web ou d’autres services, ajoutez ses informations ici.

4. Propriété intellectuelle
  -  Tous les éléments de l’application PetsMatch, y compris les textes, graphismes, logos, images, vidéos et autres contenus, sont protégés par des droits d’auteur et appartiennent exclusivement à PETSMATCH SAS.
  -  Toute reproduction, modification, diffusion ou exploitation, totale ou partielle, sans autorisation écrite préalable, est strictement interdite.
  -  Si vous utilisez des ressources sous licence ou appartenant à des tiers, précisez que leurs droits sont respectés.

5. Données personnelles
  -  L’utilisation des données personnelles est régie par notre Politique de Confidentialité, accessible directement dans l’application https://petsmatchapp.com/404.
  -  Collecte des données : Nous collectons des informations nécessaires au bon fonctionnement de l’application, comme les données d’inscription (nom, email, téléphone), les données de profil (professionnels, éleveurs), et les interactions dans l’application.
  -  Conformité RGPD :
    -  Les utilisateurs disposent de droits d’accès, de rectification, de suppression, et d’opposition sur leurs données.
    -  Pour toute demande relative aux données personnelles, contactez-nous à petsmatch.contact@gmail.com.

6. Limitation de responsabilité
  -  PETSMATCH SAS agit en tant qu’intermédiaire entre les clients, les professionnels du monde animalier, et les éleveurs. Nous ne sommes pas responsables :
    -  Des interactions ou des transactions entre utilisateurs.
    -  Des contenus publiés par les utilisateurs (annonces, profils, avis).
    -  Des dommages liés à une mauvaise utilisation de l’application ou à des interruptions de service (notamment pour des raisons techniques).

7. Litiges et juridiction compétente
  -  En cas de litige, les parties s’efforceront de trouver une solution à l’amiable.
  -  À défaut, la juridiction compétente est celle des tribunaux de Rennes, France.

                    """,
                    style: TextStyle(fontSize: 16),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Checkbox(
                      value: _isAcceptedMentions,
                      onChanged: (bool? value) {
                        setState(() {
                          _isAcceptedMentions = value ?? false;
                        });
                      },
                    ),
                    Text("J'ai lu et j'accepte les mentions légales")
                  ],
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color.fromARGB(
                        255, 255, 192, 187), // Couleur de fond du bouton
                  ),
                  onPressed: _isAcceptedMentions
                      ? () async {
                          _validateAndContinue();
                        }
                      : null,
                  child: Text("Accepter et Continuer"),
                ),
                SizedBox(
                    height:
                        UTILS.calculHeight(30, UTILS.heightReference(context))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
