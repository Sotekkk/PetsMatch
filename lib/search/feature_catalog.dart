// Catalogue central des fonctionnalités de l'appli, pour la recherche rapide
// (loupe dans l'AppBar de l'accueil). Chaque entrée = un écran ou une action
// atteignable via un menu, avec ses mots-clés (synonymes) et sa visibilité
// selon le profil actif.
//
// ⚠️ À garder synchronisé avec les tiroirs : eleveur_nav.dart,
// particulier_nav.dart, association_nav.dart, communaute_hub_page.dart.

import 'package:flutter/material.dart';
import 'package:PetsMatch/main.dart' show User_Info;

import 'package:PetsMatch/pages/agenda/agenda_page.dart';
import 'package:PetsMatch/pages/message.dart';
import 'package:PetsMatch/pages/notifications_page.dart';
import 'package:PetsMatch/pages/settings/main_settings.dart';
import 'package:PetsMatch/pages/settings/info_utilisateur.dart';
import 'package:PetsMatch/pages/liked_page.dart';
import 'package:PetsMatch/pages/services/services_page.dart';
import 'package:PetsMatch/pages/marketplace/marketplace_page.dart';
import 'package:PetsMatch/pages/eleveur_list_page.dart';

import 'package:PetsMatch/pages/communaute/communaute_hub_page.dart';
import 'package:PetsMatch/pages/communaute/forum_page.dart';
import 'package:PetsMatch/pages/communaute/groupes_page.dart';
import 'package:PetsMatch/pages/promenades/promenades_page.dart';
import 'package:PetsMatch/pages/balades_ludiques/balades_ludiques_hub_page.dart';
import 'package:PetsMatch/pages/evenements/evenements_page.dart';
import 'package:PetsMatch/pages/lieux/lieux_pet_friendly_page.dart';
import 'package:PetsMatch/pages/nature/natural_places_page.dart';
import 'package:PetsMatch/pages/petfriends/petfriends_page.dart';

import 'package:PetsMatch/pages/mes_alertes_page.dart';
import 'package:PetsMatch/pages/particulier/animaux_perdus_page.dart';
import 'package:PetsMatch/pages/particulier/animal_trouve_form_page.dart';
import 'package:PetsMatch/pages/particulier/user_feed.dart';
import 'package:PetsMatch/pages/particulier/animaux_acquis_page.dart';
import 'package:PetsMatch/pages/particulier/animaux_en_accueil_page.dart';
import 'package:PetsMatch/pages/particulier/mes_associations_benevole.dart';
import 'package:PetsMatch/pages/particulier/mes_contrats_page.dart';

import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart';
import 'package:PetsMatch/pages/eleveur/post/mes_annonces_page.dart';
import 'package:PetsMatch/pages/eleveur/post/create_annonce_page.dart';
import 'package:PetsMatch/pages/eleveur/post/trouver_compagnon_page.dart';
import 'package:PetsMatch/pages/eleveur/post/annonces_public_page.dart';
import 'package:PetsMatch/pages/eleveur/post/annonces_feed_page.dart';
import 'package:PetsMatch/pages/eleveur/admin/contrat_reservation.dart';
import 'package:PetsMatch/pages/eleveur/admin/facturation.dart';
import 'package:PetsMatch/pages/eleveur/admin/registre_sanitaire.dart';
import 'package:PetsMatch/pages/eleveur/admin/registre_entree_sortie.dart';
import 'package:PetsMatch/pages/eleveur/admin/certificats_engagement_page.dart';
import 'package:PetsMatch/pages/eleveur/inventaire/inventaire_page.dart';
import 'package:PetsMatch/pages/eleveur/planning/plan_template_list_page.dart';
import 'package:PetsMatch/pages/eleveur/employes/employes_page.dart';
import 'package:PetsMatch/pages/eleveur/abonnement_page.dart';
import 'package:PetsMatch/pages/eleveur/profil_eleveur_edit.dart';

import 'package:PetsMatch/pages/pro/pro_profile_edit.dart';
import 'package:PetsMatch/pages/pro/pro_agenda.dart';
import 'package:PetsMatch/pages/pro/pro_clients_page.dart';
import 'package:PetsMatch/pages/pro/vet_patients_page.dart';
import 'package:PetsMatch/pages/pro/registre_pension_page.dart';
import 'package:PetsMatch/pages/pro/fiches_pension_page.dart';
import 'package:PetsMatch/pages/pro/pension_chenil_page.dart';
import 'package:PetsMatch/pages/pro/pension_planning_page.dart';
import 'package:PetsMatch/pages/pro/pension_entree_sortie_page.dart';
import 'package:PetsMatch/pages/pro/pension_mes_taches_page.dart';
import 'package:PetsMatch/pages/pro/pension_factures_page.dart';
import 'package:PetsMatch/pages/pro/pension_tarifs_page.dart';
import 'package:PetsMatch/pages/pro/pension_documents_page.dart';
import 'package:PetsMatch/pages/pro/pension_abonnement_page.dart';
import 'package:PetsMatch/pages/pro/education_planning_page.dart';
import 'package:PetsMatch/pages/pro/education_contrats_page.dart';
import 'package:PetsMatch/pages/pro/education_devis_page.dart';
import 'package:PetsMatch/pages/pro/education_abonnement_page.dart';
import 'package:PetsMatch/pages/pro/registre_visites_page.dart';
import 'package:PetsMatch/pages/pro/tournee_page.dart';
import 'package:PetsMatch/pages/pro/cles_clients_page.dart';
import 'package:PetsMatch/pages/pro/tarifs_clients_page.dart';
import 'package:PetsMatch/pages/pro/garde_abonnement_page.dart';
import 'package:PetsMatch/pages/pro/taxi_trajets_page.dart';
import 'package:PetsMatch/pages/pro/taxi_tournee_page.dart';
import 'package:PetsMatch/pages/pro/photographe_prestations_page.dart';
import 'package:PetsMatch/pages/pro/photographe_dashboard_page.dart';
import 'package:PetsMatch/pages/pro/toilettage_prestations_page.dart';
import 'package:PetsMatch/pages/pro/toilettage_employes_page.dart';
import 'package:PetsMatch/pages/pro/toilettage_planning_employes_page.dart';
import 'package:PetsMatch/pages/pro/toilettage_dashboard_page.dart';
import 'package:PetsMatch/pages/pro/toilettage_abonnement_page.dart';
import 'package:PetsMatch/pages/lieux/mon_etablissement_page.dart';

import 'package:PetsMatch/pages/association/animaux/mes_animaux_asso.dart';
import 'package:PetsMatch/pages/association/familles_accueil/familles_accueil_page.dart';
import 'package:PetsMatch/pages/association/admin/chenil_planning_page.dart';
import 'package:PetsMatch/pages/association/equipe/equipe_page.dart';
import 'package:PetsMatch/pages/association/post/create_annonce_asso_page.dart';
import 'package:PetsMatch/pages/association/post/annonces_asso_feed_page.dart';
import 'package:PetsMatch/pages/association/associations_list_page.dart';
import 'package:PetsMatch/pages/association/admin/contrat_adoption_page.dart';
import 'package:PetsMatch/pages/association/profil_association_edit.dart';

// ── Contexte de profil ───────────────────────────────────────────────────────

bool get _asso =>
    User_Info.activeType == 'association' ||
    (User_Info.activeType.isEmpty && User_Info.isAssociation);

bool get _particulier =>
    User_Info.activeType == 'particulier' ||
    (User_Info.activeType.isEmpty &&
        !User_Info.isElevage &&
        !User_Info.isPro &&
        !User_Info.isAssociation);

String get _catPro => User_Info.catPro;

/// Profil pro « métier » (pension, garde, éducateur, véto…), hors éleveur.
bool get _pro => User_Info.isPro && _catPro.isNotEmpty && _catPro != 'eleveur';

/// Éleveur (compte élevage non-pro), ou fallback.
bool get _eleveur => !_asso && !_particulier && !_pro;

// ── Modèle ───────────────────────────────────────────────────────────────────

class QuickAction {
  final String label;
  final List<String> keywords;
  final IconData icon;
  final String group;
  final bool Function() visible;
  final void Function(BuildContext) open;
  final bool isAction; // true = déclenche une action (créer…), false = écran

  const QuickAction({
    required this.label,
    required this.keywords,
    required this.icon,
    required this.group,
    required this.visible,
    required this.open,
    this.isAction = false,
  });
}

void _push(BuildContext c, Widget page) =>
    Navigator.push(c, MaterialPageRoute(builder: (_) => page));

// ── Le catalogue ─────────────────────────────────────────────────────────────

List<QuickAction> _all(BuildContext ctx) => [
  // ── Commun à tous les profils ──────────────────────────────────────────────
  QuickAction(
    label: 'Messages',
    keywords: ['messagerie', 'discussion', 'chat', 'conversation', 'contacter'],
    icon: Icons.chat_bubble_outline, group: 'Général',
    visible: () => true, open: (c) => _push(c, MessagePage()),
  ),
  QuickAction(
    label: 'Notifications',
    keywords: ['alertes', 'rappels', 'cloche'],
    icon: Icons.notifications_outlined, group: 'Général',
    visible: () => true, open: (c) => _push(c, const NotificationsPage()),
  ),
  QuickAction(
    label: 'Mon agenda',
    keywords: ['calendrier', 'planning', 'rendez-vous', 'rdv', 'événements', 'tâches', 'rappels'],
    icon: Icons.calendar_month_outlined, group: 'Général',
    visible: () => true,
    open: (c) => _push(c, AgendaPage(
        onBack: () => Navigator.pop(c),
        isParticulier: _particulier, isAssociation: _asso)),
  ),
  QuickAction(
    label: 'Paramètres',
    keywords: ['réglages', 'compte', 'confidentialité', 'notifications', 'langue', 'mot de passe', 'supprimer mon compte'],
    icon: Icons.settings_outlined, group: 'Général',
    visible: () => true, open: (c) => _push(c, const SettingsMainPage()),
  ),
  QuickAction(
    label: 'Favoris',
    keywords: ['aimés', 'likes', 'coeur', 'sauvegardés', 'annonces favorites'],
    icon: Icons.favorite_border, group: 'Général',
    visible: () => true, open: (c) => _push(c, LikesPage()),
  ),
  QuickAction(
    label: 'Annuaire des professionnels',
    keywords: ['services', 'pros', 'vétérinaire', 'toiletteur', 'éducateur', 'pension', 'pet sitter', 'trouver un pro', 'près de chez moi'],
    icon: Icons.storefront_outlined, group: 'Annuaire & Communauté',
    visible: () => true, open: (c) => _push(c, const ServicesPage()),
  ),
  QuickAction(
    label: 'Marketplace',
    keywords: ['boutique', 'produits', 'accessoires', 'alimentation', 'partenaires', 'acheter'],
    icon: Icons.local_offer_outlined, group: 'Annuaire & Communauté',
    visible: () => true, open: (c) => _push(c, const MarketplacePage()),
  ),

  // ── Communauté ─────────────────────────────────────────────────────────────
  QuickAction(
    label: 'Communauté',
    keywords: ['forum', 'groupes', 'balades', 'événements', 'petfriends', 'communaute'],
    icon: Icons.groups_outlined, group: 'Annuaire & Communauté',
    visible: () => true, open: (c) => _push(c, const CommunauteHubPage()),
  ),
  QuickAction(
    label: 'Balades ludiques',
    keywords: ['chasse au trésor', 'parcours', 'défis', 'jeu', 'gps', 'énigmes', 'balade dog friendly', 'balde ludique'],
    icon: Icons.explore_outlined, group: 'Annuaire & Communauté',
    visible: () => true, open: (c) => _push(c, const BaladesLudiquesHubPage()),
  ),
  QuickAction(
    label: 'Balades canines',
    keywords: ['promenade', 'sortie', 'groupe', 'rencontre chiens', 'marche'],
    icon: Icons.directions_walk_outlined, group: 'Annuaire & Communauté',
    visible: () => true, open: (c) => _push(c, const PromenadePage()),
  ),
  QuickAction(
    label: 'Forums',
    keywords: ['discussion', 'entraide', 'questions', 'sujets', 'conseils'],
    icon: Icons.forum_outlined, group: 'Annuaire & Communauté',
    visible: () => true, open: (c) => _push(c, const ForumPage()),
  ),
  QuickAction(
    label: 'Groupes',
    keywords: ['communautés', 'race', 'région', 'loisir', 'rejoindre un groupe'],
    icon: Icons.groups_2_outlined, group: 'Annuaire & Communauté',
    visible: () => true, open: (c) => _push(c, const GroupesPage()),
  ),
  QuickAction(
    label: 'Événements',
    keywords: ['expositions', 'concours', 'rencontres', 'agenda', 'salon'],
    icon: Icons.event_outlined, group: 'Annuaire & Communauté',
    visible: () => true, open: (c) => _push(c, const EvenementsPage()),
  ),
  QuickAction(
    label: 'Lieux Pet-Friendly',
    keywords: ['dogfriendly', 'dog friendly', 'restaurants', 'hôtels', 'bars', 'commerces', 'accepte les chiens', 'lieu dogfriendly', 'où aller avec mon chien'],
    icon: Icons.location_on_outlined, group: 'Annuaire & Communauté',
    visible: () => true, open: (c) => _push(c, const LieuxPetFriendlyPage()),
  ),
  QuickAction(
    label: 'Lieux Naturels',
    keywords: ['plages', 'lacs', 'forêts', 'parcs', 'baignade', 'nature', 'cyanobactéries', 'où promener', 'sentiers'],
    icon: Icons.forest_outlined, group: 'Annuaire & Communauté',
    visible: () => true, open: (c) => _push(c, const NaturalPlacesPage()),
  ),
  QuickAction(
    label: 'PetFriends',
    keywords: ['amis', 'réseau', 'passionnés', 'contacts', 'demandes d\'amis'],
    icon: Icons.people_outline, group: 'Annuaire & Communauté',
    visible: () => true, open: (c) => _push(c, const PetFriendsPage()),
  ),

  // ── Perdus & Trouvés ───────────────────────────────────────────────────────
  QuickAction(
    label: 'Animaux perdus / trouvés',
    keywords: ['fugue', 'disparu', 'retrouver', 'carte', 'alerte perdu', 'chat perdu', 'chien perdu'],
    icon: Icons.location_searching, group: 'Perdus & Trouvés',
    visible: () => true, open: (c) => _push(c, const AnimauxPerdusPage()),
  ),
  QuickAction(
    label: 'Mes déclarations perdus / trouvés',
    keywords: ['mes alertes', 'signalements', 'mes annonces perdu'],
    icon: Icons.manage_search_outlined, group: 'Perdus & Trouvés',
    visible: () => true, open: (c) => _push(c, const MesAlertesPage()),
  ),
  QuickAction(
    label: 'J\'ai trouvé un animal',
    keywords: ['signaler', 'déclarer', 'recueilli', 'errant'],
    icon: Icons.pets, group: 'Perdus & Trouvés', isAction: true,
    visible: () => true, open: (c) => _push(c, const AnimalTrouveFormPage()),
  ),

  // ── Mes animaux — particulier ──────────────────────────────────────────────
  QuickAction(
    label: 'Mes animaux',
    keywords: ['mes compagnons', 'chien', 'chat', 'fiche animal', 'ajouter un animal'],
    icon: Icons.pets_outlined, group: 'Mes animaux',
    visible: () => _particulier,
    open: (c) => _push(c, const UserParticulierFeed(initialTab: 1)),
  ),
  QuickAction(
    label: 'Carnet de santé',
    keywords: ['santé', 'vaccin', 'vaccination', 'vermifuge', 'antiparasitaire', 'poids', 'chirurgie', 'hospitalisation', 'allergie', 'traitement', 'radio', 'visite véto', 'anesthésie', 'protocole'],
    icon: Icons.medical_services_outlined, group: 'Mes animaux',
    visible: () => _particulier,
    open: (c) => _push(c, const UserParticulierFeed(initialTab: 1)),
  ),
  QuickAction(
    label: 'Mes animaux acquis',
    keywords: ['adoptés', 'achetés', 'cession', 'reçus', 'suivi éleveur'],
    icon: Icons.handshake_outlined, group: 'Mes animaux',
    visible: () => _particulier, open: (c) => _push(c, const AnimauxAcquisPage()),
  ),
  QuickAction(
    label: 'Animaux en accueil',
    keywords: ['famille d\'accueil', 'fa', 'accueil temporaire'],
    icon: Icons.house_outlined, group: 'Mes animaux',
    visible: () => _particulier, open: (c) => _push(c, const AnimauxEnAccueilPage()),
  ),
  QuickAction(
    label: 'Mes contrats',
    keywords: ['documents', 'signature', 'certificat', 'adoption', 'achat', 'administratif'],
    icon: Icons.description_outlined, group: 'Administratif',
    visible: () => _particulier, open: (c) => _push(c, const MesContratsParticulierPage()),
  ),
  QuickAction(
    label: 'Mes employeurs',
    keywords: ['travail', 'emploi', 'salarié', 'employé', 'missions'],
    icon: Icons.work_outline, group: 'Mes animaux',
    visible: () => _particulier, open: (c) => _push(c, const MesEmployeursPage()),
  ),
  QuickAction(
    label: 'Mes associations (bénévole)',
    keywords: ['bénévolat', 'aider', 'refuge'],
    icon: Icons.volunteer_activism_outlined, group: 'Mes animaux',
    visible: () => _particulier, open: (c) => _push(c, const MesAssociationsBenevole()),
  ),
  QuickAction(
    label: 'Modifier mon profil',
    keywords: ['éditer profil', 'nom', 'prénom', 'adresse', 'téléphone', 'email', 'coordonnées'],
    icon: Icons.edit_outlined, group: 'Mon profil',
    visible: () => _particulier,
    open: (c) => _push(c, const InfoUserSettings()),
  ),

  // ── Annonces / adoption (recherche) — commun particulier & pros ─────────────
  QuickAction(
    label: 'Trouver un compagnon',
    keywords: ['adopter', 'chiot', 'chaton', 'annonces', 'à vendre', 'portée', 'acheter un chien'],
    icon: Icons.pets_outlined, group: 'Annonces',
    visible: () => true, open: (c) => _push(c, const TrouverCompagnonPage()),
  ),
  QuickAction(
    label: 'Annonces d\'adoption (associations)',
    keywords: ['refuge', 'adoption', 'sos', 'à adopter', 'chien de refuge'],
    icon: Icons.favorite_border, group: 'Annonces',
    visible: () => true, open: (c) => _push(c, const AnnoncesAssoFeedPage()),
  ),
  QuickAction(
    label: 'Carte des élevages',
    keywords: ['éleveurs', 'près de chez moi', 'trouver un élevage'],
    icon: Icons.map_outlined, group: 'Annonces',
    visible: () => true, open: (c) => _push(c, const EleveurListPage()),
  ),
  QuickAction(
    label: 'Carte des associations',
    keywords: ['refuges', 'spa', 'près de chez moi'],
    icon: Icons.map_outlined, group: 'Annonces',
    visible: () => true, open: (c) => _push(c, const AssociationsListPage()),
  ),
  QuickAction(
    label: 'Saillie',
    keywords: ['étalon', 'reproduction', 'mâle disponible', 'monte'],
    icon: Icons.diversity_1_outlined, group: 'Annonces',
    visible: () => _eleveur,
    open: (c) => _push(c, const AnnoncesPublicPage(typeFilter: 'saillie')),
  ),

  // ── Éleveur ────────────────────────────────────────────────────────────────
  QuickAction(
    label: 'Mes animaux (élevage)',
    keywords: ['reproducteurs', 'portées', 'chiots', 'chatons', 'cheptel', 'fiche animal'],
    icon: Icons.cruelty_free_outlined, group: 'Mon élevage',
    visible: () => _eleveur, open: (c) => _push(c, const MesAnimauxPage()),
  ),
  QuickAction(
    label: 'Carnet de santé (élevage)',
    keywords: ['santé', 'vaccin', 'vermifuge', 'antiparasitaire', 'poids', 'chirurgie', 'hospitalisation', 'allergie', 'traitement', 'radio', 'anesthésie', 'protocole'],
    icon: Icons.medical_services_outlined, group: 'Mon élevage',
    visible: () => _eleveur, open: (c) => _push(c, const MesAnimauxPage()),
  ),
  QuickAction(
    label: 'Protocoles',
    keywords: ['modèles', 'planning', 'soins récurrents', 'templates', 'tâches automatiques'],
    icon: Icons.event_note_outlined, group: 'Mon élevage',
    visible: () => _eleveur || _asso, open: (c) => _push(c, PlanTemplateListPage(isAssociation: _asso)),
  ),
  QuickAction(
    label: 'Suivi sanitaire',
    keywords: ['registre sanitaire', 'actes', 'vaccinations', 'obligations', 'traçabilité'],
    icon: Icons.health_and_safety_outlined, group: 'Mon élevage',
    visible: () => _eleveur || _asso,
    open: (c) => _push(c, RegistreSanitairePage(isAssociation: _asso)),
  ),
  QuickAction(
    label: 'Entrée / Sortie (registre)',
    keywords: ['mouvements', 'registre entrée sortie', 'arrivées', 'départs', 'cessions'],
    icon: Icons.swap_horiz_outlined, group: 'Mon élevage',
    visible: () => _eleveur || _asso,
    open: (c) => _push(c, RegistreEntreeSortiePage(isAssociation: _asso)),
  ),
  QuickAction(
    label: 'Inventaire',
    keywords: ['stock', 'produits', 'médicaments', 'nourriture', 'matériel', 'alerte stock bas'],
    icon: Icons.inventory_2_outlined, group: 'Mon élevage',
    visible: () => _eleveur || _asso, open: (c) => _push(c, const InventairePage()),
  ),
  QuickAction(
    label: 'Mes employés',
    keywords: ['salariés', 'équipe', 'droits', 'accès', 'planning employés', 'apprentis'],
    icon: Icons.groups_outlined, group: 'Mon élevage',
    visible: () => _eleveur, open: (c) => _push(c, const EmployesPage()),
  ),
  QuickAction(
    label: 'Mes annonces',
    keywords: ['publications', 'mes ventes', 'mes portées en vente', 'gérer mes annonces'],
    icon: Icons.campaign_outlined, group: 'Annonces',
    visible: () => _eleveur, open: (c) => _push(c, const MesAnnoncesPage()),
  ),
  QuickAction(
    label: 'Déposer une annonce',
    keywords: ['créer annonce', 'publier', 'mettre en vente', 'nouvelle annonce'],
    icon: Icons.add_circle_outline_rounded, group: 'Annonces', isAction: true,
    visible: () => _eleveur, open: (c) => _push(c, const CreateAnnoncePage()),
  ),
  QuickAction(
    label: 'Mes contrats (cession / réservation)',
    keywords: ['contrats de vente', 'réservation', 'signature', 'documents', 'administratif', 'certificat'],
    icon: Icons.description_outlined, group: 'Administratif',
    visible: () => _eleveur, open: (c) => _push(c, ContratReservationPage()),
  ),
  QuickAction(
    label: 'Mes achats',
    keywords: ['contrats reçus', 'animaux acquis', 'mes acquisitions'],
    icon: Icons.shopping_bag_outlined, group: 'Administratif',
    visible: () => _eleveur, open: (c) => _push(c, const MesContratsParticulierPage()),
  ),
  QuickAction(
    label: 'Facturation',
    keywords: ['factures', 'devis', 'comptabilité', 'tva', 'export', 'mes factures'],
    icon: Icons.receipt_long_outlined, group: 'Administratif',
    visible: () => _eleveur, open: (c) => _push(c, const FacturationPage()),
  ),
  QuickAction(
    label: 'Mon abonnement',
    keywords: ['premium', 'formule', 'plan', 'passer premium', 'tarifs', 'paiement'],
    icon: Icons.workspace_premium_outlined, group: 'Mon profil',
    visible: () => _eleveur, open: (c) => _push(c, const AbonnementPage()),
  ),
  QuickAction(
    label: 'Modifier mon profil élevage',
    keywords: ['profil éleveur', 'affixe', 'siret', 'photos', 'réseaux sociaux', 'reproducteurs'],
    icon: Icons.edit_outlined, group: 'Mon profil',
    visible: () => _eleveur, open: (c) => _push(c, const ProfilEleveurEditPage()),
  ),

  // ── Pros — commun ──────────────────────────────────────────────────────────
  QuickAction(
    label: 'Mon agenda RDV',
    keywords: ['rendez-vous', 'demandes', 'à venir', 'historique', 'créneaux', 'planning pro'],
    icon: Icons.calendar_month_outlined, group: 'Mon espace pro',
    visible: () => _pro, open: (c) => _push(c, const ProAgendaPage()),
  ),
  QuickAction(
    label: 'Mes créneaux',
    keywords: ['disponibilités', 'horaires', 'ouverture réservations'],
    icon: Icons.schedule_outlined, group: 'Mon espace pro',
    visible: () => _pro, open: (c) => _push(c, const ProAgendaPage(initialTabIndex: 3)),
  ),
  QuickAction(
    label: 'Modifier mon profil pro',
    keywords: ['profil professionnel', 'services', 'horaires', 'tarifs', 'siret', 'zone d\'intervention'],
    icon: Icons.edit_outlined, group: 'Mon profil',
    visible: () => _pro,
    open: (c) => _push(c, ProProfileEditPage(
        secondaryProfileId: User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null)),
  ),

  // ── Pension ────────────────────────────────────────────────────────────────
  QuickAction(
    label: 'Nos pensionnaires',
    keywords: ['registre pension', 'animaux en pension', 'séjours en cours'],
    icon: Icons.home_work_outlined, group: 'Ma pension',
    visible: () => _catPro == 'pension', open: (c) => _push(c, const RegistrePensionPage()),
  ),
  QuickAction(
    label: 'Accès fiche pensionnaire',
    keywords: ['fiches', 'demander l\'accès', 'carnet de santé pensionnaire'],
    icon: Icons.folder_shared_outlined, group: 'Ma pension',
    visible: () => _catPro == 'pension', open: (c) => _push(c, const FichesPensionPage()),
  ),
  QuickAction(
    label: 'Logements / box',
    keywords: ['chenil', 'enclos', 'box', 'capacité', 'places', 'hébergements'],
    icon: Icons.home_work_outlined, group: 'Ma pension',
    visible: () => _catPro == 'pension', open: (c) => _push(c, const PensionChenilPage()),
  ),
  QuickAction(
    label: 'Planning d\'occupation',
    keywords: ['calendrier pension', 'taux d\'occupation', 'disponibilités', 'réservations'],
    icon: Icons.calendar_view_week_outlined, group: 'Ma pension',
    visible: () => _catPro == 'pension', open: (c) => _push(c, const PensionPlanningPage()),
  ),
  QuickAction(
    label: 'Entrée - Sortie (pension)',
    keywords: ['check-in', 'check-out', 'arrivées', 'départs', 'admission'],
    icon: Icons.swap_horiz_outlined, group: 'Ma pension',
    visible: () => _catPro == 'pension', open: (c) => _push(c, const PensionEntreeSortiePage()),
  ),
  QuickAction(
    label: 'Mes tâches (pension)',
    keywords: ['soins', 'à faire', 'checklist', 'planning du jour'],
    icon: Icons.check_circle_outline, group: 'Ma pension',
    visible: () => _catPro == 'pension', open: (c) => _push(c, const PensionMesTachesPage()),
  ),
  QuickAction(
    label: 'Facturation (pension)',
    keywords: ['factures', 'acompte', 'paiement', 'devis'],
    icon: Icons.receipt_long_outlined, group: 'Administratif',
    visible: () => _catPro == 'pension', open: (c) => _push(c, const PensionFacturesPage()),
  ),
  QuickAction(
    label: 'Tarification (pension)',
    keywords: ['prix', 'tarifs par espèce', 'suppléments', 'grille tarifaire'],
    icon: Icons.euro_outlined, group: 'Administratif',
    visible: () => _catPro == 'pension', open: (c) => _push(c, const PensionTarifsPage()),
  ),
  QuickAction(
    label: 'Documents (pension)',
    keywords: ['contrats pension', 'règlement', 'fichiers', 'attestations'],
    icon: Icons.folder_outlined, group: 'Administratif',
    visible: () => _catPro == 'pension', open: (c) => _push(c, const PensionDocumentsPage()),
  ),
  QuickAction(
    label: 'Suivi sanitaire (pension)',
    keywords: ['registre sanitaire', 'soins', 'vaccins pensionnaires'],
    icon: Icons.health_and_safety_outlined, group: 'Ma pension',
    visible: () => _catPro == 'pension',
    open: (c) => _push(c, const RegistreSanitairePage(isPension: true)),
  ),
  QuickAction(
    label: 'Protocoles (pension)',
    keywords: ['modèles de soins', 'planning récurrent', 'templates'],
    icon: Icons.event_note_outlined, group: 'Ma pension',
    visible: () => _catPro == 'pension', open: (c) => _push(c, const PlanTemplateListPage()),
  ),
  QuickAction(
    label: 'Mon abonnement (pension)',
    keywords: ['premium', 'formule', 'plan', 'passer premium'],
    icon: Icons.workspace_premium_outlined, group: 'Mon profil',
    visible: () => _catPro == 'pension', open: (c) => _push(c, const PensionAbonnementPage()),
  ),
  QuickAction(
    label: 'Inventaire (pension)',
    keywords: ['stock', 'nourriture', 'litière', 'matériel'],
    icon: Icons.inventory_2_outlined, group: 'Ma pension',
    visible: () => _catPro == 'pension', open: (c) => _push(c, const InventairePage()),
  ),
  QuickAction(
    label: 'Mes employés (pension)',
    keywords: ['équipe', 'salariés', 'droits', 'accès'],
    icon: Icons.groups_outlined, group: 'Ma pension',
    visible: () => _catPro == 'pension', open: (c) => _push(c, const EmployesPage(profileType: 'pension')),
  ),

  // ── Éducateur ──────────────────────────────────────────────────────────────
  QuickAction(
    label: 'Planning des cours',
    keywords: ['cours collectifs', 'séances', 'balade éducative', 'agenda cours', 'planning éducateur'],
    icon: Icons.calendar_month_outlined, group: 'Mon espace pro',
    visible: () => _catPro == 'education', open: (c) => _push(c, const EducationPlanningPage()),
  ),
  QuickAction(
    label: 'Mes animaux suivis',
    keywords: ['élèves', 'clients', 'chiens en éducation', 'dossiers'],
    icon: Icons.psychology_outlined, group: 'Mon espace pro',
    visible: () => _catPro == 'education', open: (c) => _push(c, const ProClientsPage()),
  ),
  QuickAction(
    label: 'Devis',
    keywords: ['devis', 'estimation', 'proposition', 'prix', 'envoyer un devis'],
    icon: Icons.request_quote_outlined, group: 'Administratif',
    visible: () => _catPro == 'education' || _catPro == 'garde', open: (c) => _push(c, const DevisPage()),
  ),
  QuickAction(
    label: 'Mes factures',
    keywords: ['facturation', 'comptabilité', 'tva', 'export', 'facture électronique'],
    icon: Icons.receipt_long_outlined, group: 'Administratif',
    visible: () => _catPro == 'education' || _catPro == 'garde' ||
        _catPro == 'sante' || _catPro == 'veterinaire' || _catPro == 'marechal_ferrant',
    open: (c) => _push(c, const FacturationPage()),
  ),
  QuickAction(
    label: 'Mes contrats (éducateur)',
    keywords: ['contrat de prestation', 'signature client', 'protocole', 'devis signé'],
    icon: Icons.description_outlined, group: 'Administratif',
    visible: () => _catPro == 'education', open: (c) => _push(c, const EducationContratsPage()),
  ),
  QuickAction(
    label: 'Ma formule (éducateur)',
    keywords: ['abonnement', 'premium', 'plan', 'passer premium'],
    icon: Icons.workspace_premium_outlined, group: 'Mon profil',
    visible: () => _catPro == 'education', open: (c) => _push(c, const EducationAbonnementPage()),
  ),
  QuickAction(
    label: 'Mes employés (éducateur)',
    keywords: ['équipe', 'moniteurs', 'salariés'],
    icon: Icons.groups_outlined, group: 'Mon espace pro',
    visible: () => _catPro == 'education', open: (c) => _push(c, const EmployesPage(profileType: 'education')),
  ),

  // ── Vétérinaire / santé ────────────────────────────────────────────────────
  QuickAction(
    label: 'Mes patients',
    keywords: ['dossiers', 'consultations', 'animaux suivis', 'carnet de santé patient'],
    icon: Icons.medical_information_outlined, group: 'Mon espace pro',
    visible: () => _catPro == 'veterinaire' || _catPro == 'sante',
    open: (c) => _push(c, const VetPatientsPage()),
  ),

  // ── Garde / pet sitter ─────────────────────────────────────────────────────
  QuickAction(
    label: 'Registre des visites',
    keywords: ['visites', 'promenades', 'comptes rendus', 'rapports', 'contrat de prestation'],
    icon: Icons.checklist_outlined, group: 'Mon espace pro',
    visible: () => _catPro == 'garde', open: (c) => _push(c, const RegistreVisitesPage()),
  ),
  QuickAction(
    label: 'Ma tournée',
    keywords: ['itinéraire', 'trajet', 'planning journée', 'optimisation'],
    icon: Icons.route_outlined, group: 'Mon espace pro',
    visible: () => _catPro == 'garde', open: (c) => _push(c, const TourneePage()),
  ),
  QuickAction(
    label: 'Gestion des clés',
    keywords: ['trousseau', 'clés clients', 'restitution', 'consignes accès'],
    icon: Icons.vpn_key_outlined, group: 'Mon espace pro',
    visible: () => _catPro == 'garde', open: (c) => _push(c, const ClesClientsPage()),
  ),
  QuickAction(
    label: 'Tarifs clients',
    keywords: ['prix', 'tarifs personnalisés', 'grille'],
    icon: Icons.sell_outlined, group: 'Administratif',
    visible: () => _catPro == 'garde', open: (c) => _push(c, const TarifsClientsPage()),
  ),
  QuickAction(
    label: 'Facturation (garde)',
    keywords: ['factures', 'devis', 'comptabilité'],
    icon: Icons.receipt_long_outlined, group: 'Administratif',
    visible: () => _catPro == 'garde', open: (c) => _push(c, const FacturationPage()),
  ),
  QuickAction(
    label: 'Protocoles / Tâches (garde)',
    keywords: ['modèles', 'checklist', 'soins récurrents'],
    icon: Icons.event_note_outlined, group: 'Mon espace pro',
    visible: () => _catPro == 'garde', open: (c) => _push(c, const PlanTemplateListPage()),
  ),
  QuickAction(
    label: 'Mon abonnement (garde)',
    keywords: ['premium', 'formule', 'plan'],
    icon: Icons.workspace_premium_outlined, group: 'Mon profil',
    visible: () => _catPro == 'garde', open: (c) => _push(c, const GardeAbonnementPage()),
  ),
  QuickAction(
    label: 'Mes animaux en garde',
    keywords: ['clients', 'animaux suivis', 'dossiers'],
    icon: Icons.directions_walk_outlined, group: 'Mon espace pro',
    visible: () => _catPro == 'garde', open: (c) => _push(c, const ProClientsPage()),
  ),
  QuickAction(
    label: 'Inventaire (garde)',
    keywords: ['stock', 'matériel'],
    icon: Icons.inventory_2_outlined, group: 'Mon espace pro',
    visible: () => _catPro == 'garde', open: (c) => _push(c, const InventairePage()),
  ),
  QuickAction(
    label: 'Mes employés (garde)',
    keywords: ['équipe', 'salariés'],
    icon: Icons.groups_outlined, group: 'Mon espace pro',
    visible: () => _catPro == 'garde', open: (c) => _push(c, const EmployesPage(profileType: 'garde')),
  ),

  // ── Taxi animalier ─────────────────────────────────────────────────────────
  QuickAction(
    label: 'Mes trajets',
    keywords: ['courses', 'transport', 'déplacements', 'réservations transport'],
    icon: Icons.checklist_outlined, group: 'Mon espace pro',
    visible: () => _catPro == 'taxi_animalier', open: (c) => _push(c, const TaxiTrajetsPage()),
  ),
  QuickAction(
    label: 'Ma tournée (taxi)',
    keywords: ['itinéraire', 'planning', 'optimisation trajet'],
    icon: Icons.route_outlined, group: 'Mon espace pro',
    visible: () => _catPro == 'taxi_animalier', open: (c) => _push(c, const TaxiTourneePage()),
  ),
  QuickAction(
    label: 'Mes factures (taxi)',
    keywords: ['facturation', 'comptabilité'],
    icon: Icons.receipt_long_outlined, group: 'Administratif',
    visible: () => _catPro == 'taxi_animalier', open: (c) => _push(c, const FacturationPage()),
  ),

  // ── Photographe ────────────────────────────────────────────────────────────
  QuickAction(
    label: 'Mes prestations (photo)',
    keywords: ['shootings', 'séances photo', 'forfaits', 'galeries'],
    icon: Icons.camera_alt_outlined, group: 'Mon espace pro',
    visible: () => _catPro == 'photographe', open: (c) => _push(c, const PhotographePrestationsPage()),
  ),
  QuickAction(
    label: 'Mes factures (photo)',
    keywords: ['facturation', 'comptabilité'],
    icon: Icons.receipt_long_outlined, group: 'Administratif',
    visible: () => _catPro == 'photographe', open: (c) => _push(c, const FacturationPage()),
  ),
  QuickAction(
    label: 'Tableau de bord (photo)',
    keywords: ['stats', 'chiffres', 'activité', 'dashboard'],
    icon: Icons.dashboard_outlined, group: 'Mon espace pro',
    visible: () => _catPro == 'photographe', open: (c) => _push(c, const PhotographeDashboardPage()),
  ),
  QuickAction(
    label: 'Mes clients (photo)',
    keywords: ['contacts', 'dossiers clients'],
    icon: Icons.people_outline, group: 'Mon espace pro',
    visible: () => _catPro == 'photographe', open: (c) => _push(c, const ProClientsPage()),
  ),

  // ── Toilettage ─────────────────────────────────────────────────────────────
  QuickAction(
    label: 'Mes prestations (toilettage)',
    keywords: ['forfaits', 'services', 'bain', 'coupe', 'tonte'],
    icon: Icons.content_cut, group: 'Mon espace pro',
    visible: () => _catPro == 'toilettage', open: (c) => _push(c, const ToilettagePrestationsPage()),
  ),
  QuickAction(
    label: 'Mes employés (toilettage)',
    keywords: ['équipe', 'toiletteurs', 'salariés'],
    icon: Icons.groups_outlined, group: 'Mon espace pro',
    visible: () => _catPro == 'toilettage', open: (c) => _push(c, const ToilettageEmployesPage()),
  ),
  QuickAction(
    label: 'Planning employés (toilettage)',
    keywords: ['horaires', 'planning équipe', 'rotations'],
    icon: Icons.calendar_view_day_outlined, group: 'Mon espace pro',
    visible: () => _catPro == 'toilettage', open: (c) => _push(c, const ToilettagePlanningEmployesPage()),
  ),
  QuickAction(
    label: 'Mes factures (toilettage)',
    keywords: ['facturation', 'comptabilité'],
    icon: Icons.receipt_long_outlined, group: 'Administratif',
    visible: () => _catPro == 'toilettage', open: (c) => _push(c, const FacturationPage()),
  ),
  QuickAction(
    label: 'Tableau de bord (toilettage)',
    keywords: ['stats', 'activité', 'chiffres', 'dashboard'],
    icon: Icons.bar_chart_outlined, group: 'Mon espace pro',
    visible: () => _catPro == 'toilettage', open: (c) => _push(c, const ToilettageDashboardPage()),
  ),
  QuickAction(
    label: 'Mon abonnement (toilettage)',
    keywords: ['premium', 'formule', 'plan'],
    icon: Icons.workspace_premium_outlined, group: 'Mon profil',
    visible: () => _catPro == 'toilettage', open: (c) => _push(c, const ToilettageAbonnementPage()),
  ),

  // ── Maréchal-ferrant ───────────────────────────────────────────────────────
  QuickAction(
    label: 'Mes équidés suivis',
    keywords: ['chevaux', 'clients', 'dossiers', 'ferrure'],
    icon: Icons.handyman_outlined, group: 'Mon espace pro',
    visible: () => _catPro == 'marechal_ferrant', open: (c) => _push(c, const ProClientsPage()),
  ),

  // ── Restauration / hébergement ─────────────────────────────────────────────
  QuickAction(
    label: 'Mon établissement',
    keywords: ['restaurant', 'hôtel', 'gîte', 'camping', 'fiche établissement', 'pet friendly'],
    icon: Icons.store_outlined, group: 'Mon espace pro',
    visible: () => _catPro == 'restauration' || (_particulier && User_Info.isPro),
    open: (c) => _push(c, const MonEtablissementPage()),
  ),

  // ── Association ────────────────────────────────────────────────────────────
  QuickAction(
    label: 'Mes animaux (association)',
    keywords: ['pensionnaires', 'à l\'adoption', 'refuge', 'fiche animal', 'carnet de santé'],
    icon: Icons.pets_outlined, group: 'Mon association',
    visible: () => _asso, open: (c) => _push(c, const MesAnimauxAssoPage()),
  ),
  QuickAction(
    label: 'Familles d\'accueil',
    keywords: ['fa', 'accueil temporaire', 'placements', 'bénévoles fa'],
    icon: Icons.house_outlined, group: 'Mon association',
    visible: () => _asso, open: (c) => _push(c, const FamillesAccueilPage()),
  ),
  QuickAction(
    label: 'Affectation des hébergements',
    keywords: ['chenil', 'box', 'planning refuge', 'places', 'répartition'],
    icon: Icons.home_work_outlined, group: 'Mon association',
    visible: () => _asso, open: (c) => _push(c, const ChenilPlanningPage()),
  ),
  QuickAction(
    label: 'Mes employés et bénévoles',
    keywords: ['équipe', 'bénévolat', 'salariés', 'planning', 'droits'],
    icon: Icons.groups_outlined, group: 'Mon association',
    visible: () => _asso, open: (c) => _push(c, const EquipePage()),
  ),
  QuickAction(
    label: 'Facturation (association)',
    keywords: ['factures', 'dons', 'comptabilité', 'reçus fiscaux'],
    icon: Icons.receipt_long_outlined, group: 'Administratif',
    visible: () => _asso, open: (c) => _push(c, const FacturationPage(isAssociation: true)),
  ),
  QuickAction(
    label: 'Contrats d\'adoption',
    keywords: ['contrat', 'adoption', 'signature', 'documents'],
    icon: Icons.handshake_outlined, group: 'Administratif',
    visible: () => _asso, open: (c) => _push(c, const ContratAdoptionPage()),
  ),
  QuickAction(
    label: 'Certificats d\'engagement',
    keywords: ['certificat', 'engagement', 'adoptant', 'loi'],
    icon: Icons.edit_document, group: 'Administratif',
    visible: () => _asso, open: (c) => _push(c, const CertificatsEngagementPage(isAssociation: true)),
  ),
  QuickAction(
    label: 'Mes annonces (association)',
    keywords: ['à l\'adoption', 'publications', 'gérer mes annonces'],
    icon: Icons.campaign_outlined, group: 'Annonces',
    visible: () => _asso, open: (c) => _push(c, const MesAnnoncesPage(isAssociation: true)),
  ),
  QuickAction(
    label: 'Déposer une annonce (association)',
    keywords: ['créer annonce', 'mettre à l\'adoption', 'publier'],
    icon: Icons.add_circle_outline_rounded, group: 'Annonces', isAction: true,
    visible: () => _asso, open: (c) => _push(c, const CreateAnnonceAssoPage()),
  ),
  QuickAction(
    label: 'Fil adoption associations',
    keywords: ['feed', 'autres refuges', 'à adopter'],
    icon: Icons.favorite_border, group: 'Annonces',
    visible: () => _asso, open: (c) => _push(c, const AnnoncesFeedPage(isAssociationFeed: true)),
  ),
  QuickAction(
    label: 'Suivi sanitaire (association)',
    keywords: ['registre sanitaire', 'soins', 'vaccins', 'traçabilité'],
    icon: Icons.health_and_safety_outlined, group: 'Mon association',
    visible: () => _asso, open: (c) => _push(c, const RegistreSanitairePage(isAssociation: true)),
  ),
  QuickAction(
    label: 'Entrées / Sorties (association)',
    keywords: ['mouvements', 'arrivées', 'adoptions', 'registre'],
    icon: Icons.swap_horiz_outlined, group: 'Mon association',
    visible: () => _asso, open: (c) => _push(c, const RegistreEntreeSortiePage(isAssociation: true)),
  ),
  QuickAction(
    label: 'Inventaire (association)',
    keywords: ['stock', 'dons matériels', 'nourriture', 'matériel'],
    icon: Icons.inventory_2_outlined, group: 'Mon association',
    visible: () => _asso, open: (c) => _push(c, const InventairePage()),
  ),
  QuickAction(
    label: 'Modifier le profil association',
    keywords: ['profil refuge', 'rna', 'agrément', 'photos', 'coordonnées'],
    icon: Icons.edit_outlined, group: 'Mon profil',
    visible: () => _asso, open: (c) => _push(c, const ProfilAssociationEditPage()),
  ),
];

/// Toutes les entrées visibles pour le profil actif.
List<QuickAction> visibleQuickActions(BuildContext ctx) =>
    _all(ctx).where((a) => a.visible()).toList();
