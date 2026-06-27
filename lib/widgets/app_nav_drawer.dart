import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/services/plan_service.dart';
import 'package:PetsMatch/widgets/profile_switcher_header.dart';
import 'package:PetsMatch/pages/connect_page.dart';
import 'package:PetsMatch/pages/liked_page.dart';
import 'package:PetsMatch/pages/mes_alertes_page.dart';
import 'package:PetsMatch/pages/marketplace/marketplace_page.dart';
import 'package:PetsMatch/pages/services/services_page.dart';
import 'package:PetsMatch/pages/settings/main_settings.dart';
import 'package:PetsMatch/pages/eleveur_list_page.dart';
import 'package:PetsMatch/pages/lieux/mon_etablissement_page.dart';
// Particulier pages
import 'package:PetsMatch/pages/particulier/user_feed.dart';
import 'package:PetsMatch/pages/particulier/animaux_perdus_page.dart';
import 'package:PetsMatch/pages/particulier/animal_trouve_form_page.dart';
import 'package:PetsMatch/pages/particulier/mes_contrats_page.dart';
import 'package:PetsMatch/pages/particulier/animaux_acquis_page.dart';
import 'package:PetsMatch/pages/particulier/animaux_en_accueil_page.dart';
import 'package:PetsMatch/pages/particulier/mes_associations_benevole.dart';
import 'package:PetsMatch/pages/petfriends/petfriends_page.dart';
import 'package:PetsMatch/pages/association/associations_list_page.dart';
import 'package:PetsMatch/pages/association/post/annonces_asso_feed_page.dart';
import 'package:PetsMatch/pages/eleveur/post/trouver_compagnon_page.dart';
// Eleveur pages
import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart';
import 'package:PetsMatch/pages/eleveur/abonnement_page.dart';
import 'package:PetsMatch/pages/eleveur/planning/planning_mois_page.dart';
import 'package:PetsMatch/pages/eleveur/employes/employes_page.dart';
import 'package:PetsMatch/pages/eleveur/inventaire/inventaire_page.dart';
import 'package:PetsMatch/pages/eleveur/post/mes_annonces_page.dart';
import 'package:PetsMatch/pages/eleveur/post/create_annonce_page.dart';
import 'package:PetsMatch/pages/eleveur/post/annonces_public_page.dart';
import 'package:PetsMatch/pages/eleveur/admin/facturation.dart';
import 'package:PetsMatch/pages/eleveur/admin/contrat_reservation.dart';
import 'package:PetsMatch/pages/eleveur/admin/registre_sanitaire.dart';
import 'package:PetsMatch/pages/eleveur/admin/registre_entree_sortie.dart';
import 'package:PetsMatch/pages/eleveur/profil_eleveur_edit.dart';
// Pro pages
import 'package:PetsMatch/pages/pro/pro_profile_edit.dart';
import 'package:PetsMatch/pages/pro/pro_agenda.dart';
import 'package:PetsMatch/pages/pro/registre_pension_page.dart';
import 'package:PetsMatch/pages/pro/fiches_pension_page.dart';
import 'package:PetsMatch/pages/pro/pension_documents_page.dart';
import 'package:PetsMatch/pages/pro/vet_patients_page.dart';
import 'package:PetsMatch/pages/pro/pro_clients_page.dart';

class AppNavDrawer extends StatefulWidget {
  const AppNavDrawer({super.key});

  @override
  State<AppNavDrawer> createState() => _AppNavDrawerState();
}

class _AppNavDrawerState extends State<AppNavDrawer> {
  bool _isEmploye = false;
  bool _isBenevole = false;
  bool _isFa = false;
  String _planCode = 'free';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final supa = Supabase.instance.client;

    final futures = <Future>[
      supa.from('employes').select('id, type').eq('uid_employe', uid).eq('actif', true),
      if (!User_Info.isElevage)
        supa.from('familles_accueil').select('id').eq('fa_uid', uid).eq('actif', true).limit(1),
    ];

    final results = await Future.wait(futures);
    final employes = results[0] as List;
    final bool isEmploye = employes.any((e) => e['type'] != 'benevole');
    final bool isBenevole = employes.any((e) => e['type'] == 'benevole');
    final bool isFa = (!User_Info.isElevage && results.length > 1)
        ? (results[1] as List).isNotEmpty
        : false;

    String planCode = 'free';
    if (User_Info.isElevage) {
      planCode = await PlanService.getPlanCode(uid);
    }

    if (mounted) {
      setState(() {
        _isEmploye = isEmploye;
        _isBenevole = isBenevole;
        _isFa = isFa;
        _planCode = planCode;
      });
    }
  }

  void _push(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  void _popToRoot() {
    Navigator.popUntil(context, (r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.82,
      backgroundColor: Colors.white,
      child: Column(
        children: [
          ProfileSwitcherHeader(
            onClose: () => Scaffold.of(context).closeEndDrawer(),
            onEditTap: () {
              if (User_Info.isElevage) {
                _push(User_Info.isPro
                    ? ProProfileEditPage(
                        secondaryProfileId: User_Info.activeProfileId.isNotEmpty
                            ? User_Info.activeProfileId
                            : null)
                    : const ProfilEleveurEditPage());
              } else {
                _push(const UserParticulierFeed(initialTab: 0));
              }
            },
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _DrawerItem(
                  icon: Icons.home_outlined,
                  label: 'Accueil',
                  onTap: _popToRoot,
                ),
                if (!User_Info.isElevage) ..._particulierItems(),
                if (User_Info.isElevage) ..._eleveurItems(),
                const Divider(height: 8),
                _DrawerItem(
                  icon: Icons.settings_outlined,
                  label: 'Paramètres',
                  onTap: () => _push(SettingsMainPage()),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.gavel_outlined, color: Color(0xFF9CA3AF), size: 20),
            title: const Text('CGU & Confidentialité',
                style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF9CA3AF))),
            onTap: () async {
              await launchUrl(Uri.parse('https://www.petsmatchapp.com/cgu'),
                  mode: LaunchMode.externalApplication);
            },
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent, size: 22),
            title: const Text('Déconnexion',
                style: TextStyle(
                    fontFamily: 'Galey',
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                    color: Colors.redAccent)),
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => WelcomePage()),
                  (route) => false,
                );
              }
            },
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ─── Particulier drawer content ───────────────────────────────────────────

  List<Widget> _particulierItems() => [
        _DrawerSection(
          icon: Icons.person_outline,
          label: 'Mon Profil',
          initiallyExpanded: true,
          children: [
            _DrawerSubItem(
              label: 'Mon Profil',
              icon: Icons.edit_outlined,
              onTap: () => _push(const UserParticulierFeed(initialTab: 0)),
            ),
            _DrawerSubItem(
              label: 'Mes Animaux',
              icon: Icons.pets_outlined,
              onTap: () => _push(const UserParticulierFeed(initialTab: 1)),
            ),
            _DrawerSubItem(
              label: 'Mes Animaux Acquis',
              icon: Icons.handshake_outlined,
              onTap: () => _push(const AnimauxAcquisPage()),
            ),
            if (_isFa)
              _DrawerSubItem(
                label: 'Animaux en accueil',
                icon: Icons.house_outlined,
                onTap: () => _push(const AnimauxEnAccueilPage()),
              ),
          ],
        ),
        _DrawerSection(
          icon: Icons.search_off_rounded,
          label: 'Perdus & Trouvés',
          children: [
            _DrawerSubItem(
              label: 'Mes déclarations perdues/trouvées',
              icon: Icons.manage_search_outlined,
              onTap: () => _push(const MesAlertesPage()),
            ),
            _DrawerSubItem(
              label: 'Animaux perdus/trouvés',
              icon: Icons.location_searching,
              onTap: () => _push(const AnimauxPerdusPage()),
            ),
            _DrawerSubItem(
              label: "J'ai trouvé un animal",
              icon: Icons.pets,
              onTap: () => _push(const AnimalTrouveFormPage()),
            ),
          ],
        ),
        _DrawerSection(
          icon: Icons.campaign_outlined,
          label: 'Annonces',
          children: [
            _DrawerSubItem(
              label: 'Trouver un compagnon',
              icon: Icons.favorite_border,
              onTap: () => _push(const TrouverCompagnonPage()),
            ),
            _DrawerSubItem(
              label: 'Carte des élevages',
              icon: Icons.map_outlined,
              onTap: () => _push(const EleveurListPage()),
            ),
            _DrawerSubItem(
              label: "Annonces d'adoption",
              icon: Icons.favorite_border,
              onTap: () => _push(const AnnoncesAssoFeedPage()),
            ),
            _DrawerSubItem(
              label: 'Carte des associations',
              icon: Icons.map_outlined,
              onTap: () => _push(const AssociationsListPage()),
            ),
          ],
        ),
        if (_isEmploye)
          _DrawerItem(
            icon: Icons.work_outline,
            label: 'Mes Employeurs',
            onTap: () => _push(const MesEmployeursPage()),
          ),
        if (_isBenevole)
          _DrawerItem(
            icon: Icons.volunteer_activism_outlined,
            label: 'Mes Associations',
            onTap: () => _push(const MesAssociationsBenevole()),
          ),
        _DrawerItem(
          icon: Icons.people_outline,
          label: 'Mes PetFriends',
          onTap: () => _push(const PetFriendsPage()),
        ),
        _DrawerItem(
          icon: Icons.favorite_border,
          label: 'Favoris',
          onTap: () => _push(LikesPage()),
        ),
        _DrawerItem(
          icon: Icons.storefront_outlined,
          label: 'Services',
          onTap: () => _push(const ServicesPage()),
        ),
        _DrawerItem(
          icon: Icons.local_offer_outlined,
          label: 'Marketplace',
          onTap: () => _push(const MarketplacePage()),
        ),
        _DrawerSection(
          icon: Icons.folder_outlined,
          label: 'Administratif',
          children: [
            _DrawerSubItem(
              label: 'Mes Contrats',
              icon: Icons.description_outlined,
              onTap: () => _push(const MesContratsParticulierPage()),
            ),
          ],
        ),
        if (User_Info.isPro) ...[
          const Divider(height: 16),
          _DrawerItem(
            icon: Icons.store_outlined,
            label: 'Mon Établissement',
            onTap: () => _push(const MonEtablissementPage()),
          ),
        ],
      ];

  // ─── Eleveur drawer content ───────────────────────────────────────────────

  List<Widget> _eleveurItems() => [
        if (!User_Info.isPro) ...[
          _DrawerSection(
            icon: Icons.pets,
            label: 'Mon Élevage',
            children: [
              _DrawerSubItem(
                label: 'Mes Animaux',
                icon: Icons.cruelty_free_outlined,
                onTap: () => _push(const MesAnimauxPage()),
              ),
              _DrawerSubItem(
                label: 'Agenda',
                icon: Icons.calendar_month_outlined,
                onTap: _popToRoot,
              ),
              _DrawerSubItem(
                label: 'Protocoles',
                icon: Icons.event_note_outlined,
                locked: _planCode != 'premium',
                badgeLabel: 'Premium',
                onTap: () => _push(_planCode != 'premium'
                    ? const AbonnementPage()
                    : const PlanningMoisPage()),
              ),
              _DrawerSubItem(
                label: 'Suivi sanitaire',
                icon: Icons.health_and_safety_outlined,
                locked: _planCode == 'free',
                onTap: () => _push(_planCode == 'free'
                    ? const AbonnementPage()
                    : const RegistreSanitairePage()),
              ),
              _DrawerSubItem(
                label: 'Inventaire',
                icon: Icons.inventory_2_outlined,
                onTap: () => _push(const InventairePage()),
              ),
              _DrawerSubItem(
                label: 'Mes Employés',
                icon: Icons.groups_outlined,
                onTap: () => _push(const EmployesPage()),
              ),
              _DrawerSubItem(
                label: 'Entrée - Sortie',
                icon: Icons.swap_horiz_outlined,
                locked: _planCode == 'free',
                onTap: () => _push(_planCode == 'free'
                    ? const AbonnementPage()
                    : const RegistreEntreeSortiePage()),
              ),
              if (_isEmploye)
                _DrawerSubItem(
                  label: 'Mes Employeurs',
                  icon: Icons.work_outline,
                  onTap: () => _push(const MesEmployeursPage()),
                ),
              if (_isBenevole)
                _DrawerSubItem(
                  label: 'Mes Associations',
                  icon: Icons.volunteer_activism_outlined,
                  onTap: () => _push(const MesAssociationsBenevole()),
                ),
            ],
          ),
          _DrawerSection(
            icon: Icons.folder_outlined,
            label: 'Administratif',
            children: [
              _DrawerSubItem(
                label: 'Mes Contrats',
                icon: Icons.description_outlined,
                onTap: () => _push(ContratReservationPage()),
              ),
              _DrawerSubItem(
                label: 'Mes Achats',
                icon: Icons.shopping_bag_outlined,
                onTap: () => _push(const MesContratsParticulierPage()),
              ),
              _DrawerSubItem(
                label: 'Facturation',
                icon: Icons.receipt_long_outlined,
                onTap: () => _push(const FacturationPage()),
              ),
            ],
          ),
          _DrawerSection(
            icon: Icons.campaign_outlined,
            label: 'Annonces',
            children: [
              _DrawerSubItem(
                label: 'Mes Annonces',
                icon: Icons.campaign_outlined,
                onTap: () => _push(const MesAnnoncesPage()),
              ),
              _DrawerSubItem(
                label: 'Déposer une annonce',
                icon: Icons.add_circle_outline_rounded,
                onTap: () => _push(const CreateAnnoncePage()),
              ),
              _DrawerSubItem(
                label: 'Trouver un compagnon',
                icon: Icons.pets_outlined,
                onTap: () => _push(const TrouverCompagnonPage()),
              ),
              _DrawerSubItem(
                label: 'Saillie',
                icon: Icons.diversity_1_outlined,
                onTap: () => _push(const AnnoncesPublicPage(typeFilter: 'saillie')),
              ),
              _DrawerSubItem(
                label: 'Carte des élevages',
                icon: Icons.map_outlined,
                onTap: () => _push(const EleveurListPage()),
              ),
            ],
          ),
        ],
        _DrawerSection(
          icon: Icons.search_off_rounded,
          label: 'Animaux perdus / trouvés',
          children: [
            _DrawerSubItem(
              label: 'Mes déclarations perdues/trouvées',
              icon: Icons.manage_search_outlined,
              onTap: () => _push(const MesAlertesPage()),
            ),
            _DrawerSubItem(
              label: 'Animaux perdus/trouvés',
              icon: Icons.location_searching,
              onTap: () => _push(const AnimauxPerdusPage()),
            ),
            _DrawerSubItem(
              label: "J'ai trouvé un animal",
              icon: Icons.pets,
              onTap: () => _push(const AnimalTrouveFormPage()),
            ),
          ],
        ),
        if (!User_Info.isPro)
          _DrawerItem(
            icon: Icons.favorite_border,
            label: 'Favoris',
            onTap: () => _push(LikesPage()),
          ),
        _DrawerItem(
          icon: Icons.storefront_outlined,
          label: 'Services',
          onTap: () => _push(const ServicesPage()),
        ),
        _DrawerItem(
          icon: Icons.local_offer_outlined,
          label: 'Marketplace',
          onTap: () => _push(const MarketplacePage()),
        ),
        if (User_Info.isPro) ...[
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
            child: Text('Espace pro',
                style: TextStyle(
                    fontFamily: 'Galey',
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    letterSpacing: 0.8)),
          ),
          _DrawerItem(
            icon: Icons.calendar_month_outlined,
            label: 'Mon agenda RDV',
            onTap: () => _push(const ProAgendaPage()),
          ),
          if (User_Info.catPro == 'garde' || User_Info.catPro == 'pension')
            _DrawerItem(
              icon: Icons.home_work_outlined,
              label: 'Registre pension',
              onTap: () => _push(const RegistrePensionPage()),
            ),
          if (User_Info.catPro == 'veterinaire')
            _DrawerItem(
              icon: Icons.medical_information_outlined,
              label: 'Mes patients',
              onTap: () => _push(const VetPatientsPage()),
            ),
          if (User_Info.catPro == 'sante' ||
              User_Info.catPro == 'education' ||
              User_Info.catPro == 'garde')
            _DrawerItem(
              icon: User_Info.catPro == 'education'
                  ? Icons.psychology_outlined
                  : User_Info.catPro == 'garde'
                      ? Icons.directions_walk_outlined
                      : Icons.self_improvement_outlined,
              label: User_Info.catPro == 'education'
                  ? 'Mes animaux suivis'
                  : User_Info.catPro == 'garde'
                      ? 'Mes animaux en garde'
                      : 'Mes patients',
              onTap: () => _push(const ProClientsPage()),
            ),
          if (User_Info.catPro == 'pension')
            _DrawerItem(
              icon: Icons.folder_shared_outlined,
              label: 'Fiches accessibles',
              onTap: () => _push(const FichesPensionPage()),
            ),
          if (User_Info.catPro == 'pension')
            _DrawerItem(
              icon: Icons.folder_outlined,
              label: 'Documents',
              onTap: () => _push(const PensionDocumentsPage()),
            ),
        ],
        const Divider(height: 24),
        _DrawerItem(
          icon: Icons.person_outline,
          label: 'Mon Profil',
          onTap: () => _push(User_Info.isPro
              ? ProProfileEditPage(
                  secondaryProfileId: User_Info.activeProfileId.isNotEmpty
                      ? User_Info.activeProfileId
                      : null)
              : const ProfilEleveurEditPage()),
        ),
        if (User_Info.isPro) ...[
          const Divider(height: 8),
          _DrawerItem(
            icon: Icons.store_outlined,
            label: 'Mon Établissement',
            onTap: () => _push(const MonEtablissementPage()),
          ),
        ],
      ];
}

// ─── Shared drawer widgets ────────────────────────────────────────────────────

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _DrawerItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: const Color(0xFF0C5C6C), size: 22),
        title: Text(label,
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w500, fontSize: 15)),
        onTap: onTap,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      );
}

class _DrawerSection extends StatefulWidget {
  final IconData icon;
  final String label;
  final List<Widget> children;
  final bool initiallyExpanded;

  const _DrawerSection({
    required this.icon,
    required this.label,
    required this.children,
    this.initiallyExpanded = false,
  });

  @override
  State<_DrawerSection> createState() => _DrawerSectionState();
}

class _DrawerSectionState extends State<_DrawerSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          ListTile(
            leading: Icon(widget.icon, color: const Color(0xFF0C5C6C), size: 22),
            title: Text(widget.label,
                style: const TextStyle(
                    fontFamily: 'Galey', fontWeight: FontWeight.w500, fontSize: 15)),
            trailing: AnimatedRotation(
              turns: _expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF0C5C6C)),
            ),
            onTap: () => setState(() => _expanded = !_expanded),
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              color: const Color(0xFFF8F8F6),
              child: Column(children: widget.children),
            ),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      );
}

class _DrawerSubItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool locked;
  final String badgeLabel;

  const _DrawerSubItem({
    required this.label,
    required this.icon,
    required this.onTap,
    this.locked = false,
    this.badgeLabel = 'Pro',
  });

  @override
  Widget build(BuildContext context) => ListTile(
        leading: const SizedBox(width: 22),
        title: Row(
          children: [
            Icon(icon, color: locked ? Colors.grey.shade400 : const Color(0xFF6E9E57), size: 18),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                    fontFamily: 'Galey',
                    fontSize: 14,
                    color: locked ? Colors.grey.shade400 : const Color(0xFF1F2A2E))),
            if (locked) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                    color: const Color(0xFFD97706).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(badgeLabel,
                    style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Galey',
                        color: Color(0xFFD97706))),
              ),
            ],
          ],
        ),
        onTap: onTap,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
      );
}
