import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/search/quick_search_page.dart';
import 'package:PetsMatch/pages/agenda/agenda_page.dart';
import 'package:PetsMatch/pages/association/animaux/mes_animaux_asso.dart';
import 'package:PetsMatch/pages/association/association_detail_page.dart';
import 'package:PetsMatch/pages/association/equipe/equipe_page.dart';
import 'package:PetsMatch/pages/association/familles_accueil/familles_accueil_page.dart';
import 'package:PetsMatch/pages/association/post/create_annonce_asso_page.dart';
import 'package:PetsMatch/pages/association/profil_association_edit.dart';
import 'package:PetsMatch/pages/eleveur/admin/registre_entree_sortie.dart';
import 'package:PetsMatch/pages/eleveur/admin/registre_sanitaire.dart';
import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart';
import 'package:PetsMatch/pages/eleveur/eleveur_dashboard.dart' show TbBloc, TbListe, TbLigneSimple, TbRaccourci;
import 'package:PetsMatch/pages/eleveur/planning/planning_jour_page.dart';
import 'package:PetsMatch/pages/eleveur/post/mes_annonces_page.dart';
import 'package:PetsMatch/utils/tableau_bord_eleveur.dart';
import 'package:PetsMatch/widgets/agenda/rdv_veto_sheets.dart';
import 'package:PetsMatch/widgets/dashboard/dashboard_kit.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Accueil de l'association (refonte, miroir site app/association/page.tsx) :
/// accès rapides, alertes et actions, compteurs, prochains rendez-vous,
/// animaux récents, entrées et sorties, annonces d'adoption.
class AssociationHomePage extends StatefulWidget {
  const AssociationHomePage({super.key});
  @override
  State<AssociationHomePage> createState() => _AssociationHomePageState();
}

/// Animaux qui ne sont plus à l'association (onglet « Anciens » de la liste).
const _anciens = {'adopte', 'transfere', 'sorti', 'decede'};
const _libelleSortie = {'adopte': 'Adoption', 'transfere': 'Transfert', 'decede': 'Décès'};
const _maxRecents = 5;

class _Mouvement {
  final String animalId, nom, libelle;
  final DateTime date;
  final bool sortie;
  const _Mouvement(this.animalId, this.nom, this.libelle, this.date, this.sortie);
}

class _AssociationHomePageState extends State<AssociationHomePage> with RouteAware {
  final _supa = Supabase.instance.client;

  int _nbPresents = 0;
  int _nbDisponibles = 0;
  int _nbEnSoin = 0;
  int _nbEnFa = 0;
  int _nbAdoptes = 0;
  int _nbBenevoles = 0;
  List<Map<String, dynamic>> _recentAnimaux = [];
  List<_Mouvement>? _mouvements;
  List<LigneTB>? _alertes;
  List<LigneTB>? _rdv;
  List<Map<String, dynamic>> _annonces = [];
  bool _loading = true;

  static const _teal = Color(0xFF0C5C6C);

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context) as PageRoute);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  // Recharge quand on revient sur l'accueil après avoir modifié quelque chose
  // ailleurs (placer un animal en FA ou en enclos…).
  @override
  void didPopNext() {
    _loadStats();
  }

  DateTime? _jour(dynamic v) {
    final s = v?.toString() ?? '';
    final d = DateTime.tryParse(s.length >= 10 ? s.substring(0, 10) : s);
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }

  Future<void> _loadStats() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Requêtes indépendantes — une erreur n'annule pas les autres.
    final animauxRes = await _supa
        .from('animaux')
        .select('id, nom, espece, photo_url, statut, fa_id, date_entree, date_sortie, created_at, updated_at')
        .eq('uid_eleveur', uid)
        .eq('is_association', true)
        .eq('profile_id', User_Info.activeProfileId)
        .catchError((_) => <dynamic>[]);

    // Équipe : mêmes membres que la page Équipe (employés + bénévoles actifs
    // du profil association).
    List<dynamic> benevoles = [];
    try {
      final asso = await _supa.from('user_profiles_complet')
          .select('id').eq('uid', uid).eq('profile_type', 'association').maybeSingle();
      var q = _supa.from('employes').select('id')
          .eq('actif', true).eq('profil_source', 'association');
      q = asso?['id'] != null ? q.eq('eleveur_profile_id', asso!['id']) : q.eq('uid_eleveur', uid);
      benevoles = await q;
    } catch (_) {}

    // Annonces d'adoption de l'association
    final annoncesRes = await _supa
        .from('annonces')
        .select('id, titre, espece, race, photos, prix, statut')
        .eq('uid_eleveur', uid)
        .eq('profil_source', 'association')
        .eq('statut', 'disponible')
        .order('created_at', ascending: false)
        .limit(6)
        .catchError((_) => <dynamic>[]);

    final list = [for (final a in animauxRes as List) Map<String, dynamic>.from(a as Map)];
    // Compteurs = mêmes règles que la liste des animaux : les présents seulement
    // (un adopté reste dans l'historique, compté à part) ; un animal en FA reste
    // aussi « disponible » ou « en soin » (fa_id est un état indépendant).
    final presents = list.where((a) => !_anciens.contains(a['statut'])).toList();
    String maj(Map a) => (a['updated_at'] ?? a['created_at'] ?? '').toString();
    final recents = [...list]..sort((a, b) => maj(b).compareTo(maj(a)));

    if (mounted) {
      setState(() {
        _nbPresents    = presents.length;
        _nbDisponibles = presents.where((a) => a['statut'] == 'disponible').length;
        _nbEnSoin      = presents.where((a) => a['statut'] == 'en_soin').length;
        _nbEnFa        = presents.where((a) => a['fa_id'] != null).length;
        _nbAdoptes     = list.where((a) => a['statut'] == 'adopte').length;
        _nbBenevoles   = benevoles.length;
        _recentAnimaux = recents.take(_maxRecents).toList();
        _annonces      = List<Map<String, dynamic>>.from(annoncesRes as List);
        _loading = false;
      });
    }

    // Entrées et sorties : dates d'entrée des fiches + sorties du registre.
    final mvts = <_Mouvement>[];
    final parId = {for (final a in list) a['id'].toString(): a};
    for (final a in list) {
      final d = _jour(a['date_entree']);
      if (d == null) continue;
      final enFa = a['fa_id'] != null && !_anciens.contains(a['statut']);
      mvts.add(_Mouvement(a['id'].toString(), (a['nom'] ?? '').toString(),
          enFa ? "Placé en famille d'accueil" : 'Entrée', d, false));
    }
    final sortis = <String>{};
    if (list.isNotEmpty) {
      try {
        final reg = await _supa.from('registre_mouvements')
            .select('id, animal_id, date_mouvement, eleveur_profile_id')
            .eq('uid_eleveur', uid).eq('type', 'sortie')
            .inFilter('animal_id', parId.keys.take(500).toList())
            .order('date_mouvement', ascending: false).limit(50);
        final pid = User_Info.activeProfileId;
        for (final m in reg as List) {
          final mp = m['eleveur_profile_id']?.toString() ?? '';
          if (mp.isNotEmpty && pid.isNotEmpty && mp != pid) continue;
          final a = parId[m['animal_id'].toString()];
          final d = _jour(m['date_mouvement']);
          if (a == null || d == null || sortis.contains(a['id'].toString())) continue;
          sortis.add(a['id'].toString());
          mvts.add(_Mouvement(a['id'].toString(), (a['nom'] ?? '').toString(),
              _libelleSortie[a['statut']] ?? 'Sortie', d, true));
        }
      } catch (_) {}
    }
    for (final a in list) {
      final d = _jour(a['date_sortie']);
      if (sortis.contains(a['id'].toString()) || !_anciens.contains(a['statut']) || d == null) continue;
      mvts.add(_Mouvement(a['id'].toString(), (a['nom'] ?? '').toString(), _libelleSortie[a['statut']] ?? 'Sortie', d, true));
    }
    mvts.sort((x, y) => y.date.compareTo(x.date));
    if (mounted) setState(() => _mouvements = mvts.take(_maxRecents).toList());

    // Alertes et rendez-vous : même moteur que l'accueil éleveur, limité à l'association.
    try {
      final tb = await chargerTableauBord(userUid: uid, ownerUid: uid, activeProfileId: User_Info.activeProfileId,
          animauxAssociation: [for (final a in presents) a['id'].toString()]);
      final alertes = [...tb.soins, ...tb.aFaire].where((l) => !l.fait).toList()
        ..sort((a, b) {
          if (a.retard != b.retard) return a.retard ? -1 : 1;
          final c = a.date.compareTo(b.date);
          return c != 0 ? c : (a.heure ?? '99').compareTo(b.heure ?? '99');
        });
      if (mounted) setState(() { _alertes = alertes; _rdv = tb.agenda.where((l) => !l.fait).toList(); });
    } catch (e) {
      debugPrint('Accueil association, tableau de bord : $e');
      if (mounted) setState(() { _alertes = []; _rdv = []; });
    }
  }

  static const _statutConfig = {
    'en_soin':    ('En soin',    Color(0xFFFFF3E0), Color(0xFFE65100)),
    'disponible': ('Disponible', Color(0xFFE8F5E9), Color(0xFF2E7D32)),
    'en_fa':      ('En FA',      Color(0xFFF3E5F5), Color(0xFF6A1B9A)),
    'adopte':     ('Adopté',     Color(0xFFE0F2F1), Color(0xFF00695C)),
    'transfere':  ('Transféré',  Color(0xFFE3F2FD), Color(0xFF1565C0)),
    'sorti':      ('Sorti',      Color(0xFFE3F2FD), Color(0xFF1565C0)),
    'decede':     ('Décédé',     Color(0xFFFFEBEE), Color(0xFFC62828)),
  };

  void _ouvrir(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  Future<void> _modifierProfil() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilAssociationEditPage()));
    if (mounted) setState(() {});
  }

  void _ouvrirAgenda({DateTime? jour}) => Navigator.push(context, MaterialPageRoute(
      builder: (ctx) => AgendaPage(onBack: () => Navigator.pop(ctx), isAssociation: true, jourInitial: jour,
          initialViewMode: jour != null ? 1 : 0)));

  void _ouvrirFiche(String id) => _ouvrir(AnimalFichePage(animalId: id, isAssociation: true));

  void _ouvrirLigne(LigneTB l) {
    switch (l.cible) {
      case CibleTB.planning:
      case CibleTB.protocole:
        _ouvrir(PlanningJourPage(initialDate: l.date, isAssociation: true));
      case CibleTB.fiche:
      case CibleTB.soin:
        // Un animal : sa fiche ; rappel groupé : la liste des animaux.
        final ids = l.soin?.animalIds ?? [if (l.animalId != null) l.animalId!];
        ids.length == 1 ? _ouvrirFiche(ids.first) : _ouvrir(const MesAnimauxAssoPage());
      case CibleTB.animaux:
        _ouvrir(const MesAnimauxAssoPage());
      case CibleTB.jour:
        _ouvrirAgenda(jour: l.date);
    }
  }

  Future<void> _planifierRdv() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ok = await showNouveauRdvVeto(context, uid: uid,
        profileId: User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null,
        profilSource: 'association');
    if (ok && mounted) _loadStats();
  }

  @override
  Widget build(BuildContext context) {
    final nom = User_Info.nameElevage.isNotEmpty
        ? User_Info.nameElevage
        : '${User_Info.firstname} ${User_Info.lastname}'.trim();
    final photo = User_Info.profilePictureUrlElevage.isNotEmpty ? User_Info.profilePictureUrlElevage : null;
    final ville = User_Info.ville.isNotEmpty ? User_Info.ville : User_Info.villeElevage;
    final enRetard = (_alertes ?? const []).where((l) => l.retard).length;

    final compteurs = Column(children: [
      Row(children: [
        _StatCard('Pris en charge', _nbPresents, Icons.pets, _teal, onTap: () =>
            _ouvrir(const MesAnimauxAssoPage())),
        const SizedBox(width: 10),
        _StatCard('Disponibles', _nbDisponibles, Icons.favorite_border, const Color(0xFF15803D), onTap: () =>
            _ouvrir(const MesAnimauxAssoPage(initialFilterStatut: 'disponible'))),
        const SizedBox(width: 10),
        _StatCard('En soin', _nbEnSoin, Icons.medical_services_outlined, const Color(0xFFC2410C), onTap: () =>
            _ouvrir(const MesAnimauxAssoPage(initialFilterStatut: 'en_soin'))),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _StatCard("En famille d'accueil", _nbEnFa, Icons.home_outlined, const Color(0xFF7E22CE), onTap: () =>
            _ouvrir(const MesAnimauxAssoPage(initialFilterStatut: 'en_fa'))),
        const SizedBox(width: 10),
        _StatCard('Adoptés', _nbAdoptes, Icons.celebration_outlined, const Color(0xFF0F766E), onTap: () =>
            _ouvrir(const MesAnimauxAssoPage(initialFilterStatut: 'adopte'))),
        const SizedBox(width: 10),
        _StatCard('Équipe', _nbBenevoles, Icons.volunteer_activism_outlined, _teal, onTap: () =>
            _ouvrir(const EquipePage())),
      ]),
    ]);

    final alertes = TbBloc(
      titre: 'Alertes et actions', icone: Icons.notifications_active_outlined,
      compteur: enRetard > 0 ? enRetard : null, compteurAlerte: true,
      libelleVoirTout: 'Suivi sanitaire',
      voirTout: () => _ouvrir(const RegistreSanitairePage(isAssociation: true)),
      child: TbListe(lignes: _alertes, vide: 'Aucun soin ni tâche en retard ou prévu dans les $kHorizonJours jours.',
          rendu: (l) => TbLigneSimple(l: l, onTap: () => _ouvrirLigne(l))),
    );
    final rdv = TbBloc(
      titre: 'Prochains rendez-vous', icone: Icons.event_outlined,
      libelleVoirTout: 'Agenda', voirTout: () => _ouvrirAgenda(),
      child: TbListe(lignes: _rdv, vide: 'Aucun rendez-vous dans les $kHorizonJours jours.',
          rendu: (l) => TbLigneSimple(l: l, onTap: () => _ouvrirLigne(l))),
    );
    final animaux = TbBloc(
      titre: 'Animaux récents', icone: Icons.pets_outlined,
      libelleVoirTout: 'Voir tous', voirTout: () => _ouvrir(const MesAnimauxAssoPage()),
      child: _recentAnimaux.isEmpty
          ? const Padding(padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('Aucun animal enregistré.', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: kDashMuted)))
          : Column(children: [
              for (var i = 0; i < _recentAnimaux.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: Color(0xFFEEF0EE)),
                _ligneAnimal(_recentAnimaux[i]),
              ],
            ]),
    );
    final mouvements = TbBloc(
      titre: 'Entrées et sorties récentes', icone: Icons.swap_horiz_outlined,
      libelleVoirTout: 'Registre', voirTout: () => _ouvrir(const RegistreEntreeSortiePage(isAssociation: true)),
      child: _mouvements == null
          ? const Padding(padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: kDashTeal))))
          : _mouvements!.isEmpty
              ? const Padding(padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text('Aucun mouvement enregistré.', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: kDashMuted)))
              : Column(children: [
                  for (var i = 0; i < _mouvements!.length; i++) ...[
                    if (i > 0) const Divider(height: 1, color: Color(0xFFEEF0EE)),
                    _ligneMouvement(_mouvements![i]),
                  ],
                ]),
    );

    return Scaffold(
      backgroundColor: kDashFond,
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(
            pinned: true,
            backgroundColor: _teal,
            surfaceTintColor: _teal,
            actions: [QuickSearchButton()],
          ),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: dashMargeLaterale(context), vertical: 14),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                DashEnteteAccueil(
                  nom: nom,
                  photoUrl: photo,
                  onAvatarTap: _modifierProfil,
                  lignes: const ['Association / Refuge'],
                  lieu: ville,
                  action: Wrap(spacing: 8, runSpacing: 8, children: [
                    DashBoutonPilule(label: 'Fiche publique', icon: Icons.visibility_outlined, onTap: () {
                      final uid = FirebaseAuth.instance.currentUser?.uid;
                      if (uid == null) return;
                      _ouvrir(AssociationDetailPage(uid: uid,
                          profileId: User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null,
                          name: nom, avatar: photo ?? '', ville: ville));
                    }),
                    DashBoutonPilule(label: 'Modifier', icon: Icons.settings_outlined, onTap: _modifierProfil),
                  ]),
                ),
                const SizedBox(height: 12),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  // Non bloquant : un dossier en attente garde l'accès normal
                  // à l'appli (cf. AuthWrapper, lib/main.dart) — seule sa
                  // visibilité auprès des autres est restreinte tant qu'il
                  // n'a pas été examiné par un admin.
                  if (!User_Info.isValidate) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.orange.shade200),
                        boxShadow: kDashOmbre,
                      ),
                      child: Row(children: [
                        CircleAvatar(
                          backgroundColor: Colors.orange.shade50,
                          child: Icon(Icons.hourglass_empty, color: Colors.orange.shade800, size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Dossier en cours d\'examen',
                                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                                    fontSize: 14, color: Colors.orange.shade900)),
                            Text(
                              'Vous pouvez utiliser votre compte normalement, mais votre profil n\'est pas encore visible par les autres.',
                              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.orange.shade800),
                            ),
                          ]),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Accès rapides : formulaires existants.
                  IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: TbRaccourci(label: 'Ajouter un animal', icon: Icons.add_circle_outline,
                        onTap: () => _ouvrir(const AnimalFichePage(isAssociation: true)))),
                    const SizedBox(width: 8),
                    Expanded(child: TbRaccourci(label: 'Planifier un rendez-vous', icon: Icons.event_available_outlined,
                        onTap: _planifierRdv)),
                    const SizedBox(width: 8),
                    Expanded(child: TbRaccourci(label: "Ajouter une famille d'accueil", icon: Icons.house_outlined,
                        onTap: () => _ouvrir(const FamillesAccueilPage(ouvrirAjout: true)))),
                    const SizedBox(width: 8),
                    Expanded(child: TbRaccourci(label: 'Publier une annonce', icon: Icons.campaign_outlined,
                        onTap: () => _ouvrir(const CreateAnnonceAssoPage()))),
                  ])),
                  const SizedBox(height: 14),

                  // Tablette : compteurs puis deux colonnes ; téléphone : actions,
                  // compteurs, rendez-vous, animaux, mouvements.
                  LayoutBuilder(builder: (context, c) {
                    if (c.maxWidth >= 840) {
                      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        compteurs,
                        const SizedBox(height: 14),
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(child: Column(children: [animaux, const SizedBox(height: 14), mouvements])),
                          const SizedBox(width: 14),
                          Expanded(child: Column(children: [alertes, const SizedBox(height: 14), rdv])),
                        ]),
                      ]);
                    }
                    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      alertes,
                      const SizedBox(height: 14),
                      compteurs,
                      const SizedBox(height: 14),
                      rdv,
                      const SizedBox(height: 14),
                      animaux,
                      const SizedBox(height: 14),
                      mouvements,
                    ]);
                  }),
                  const SizedBox(height: 20),

                  // Annonces d'adoption
                  if (_annonces.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Mes annonces d\'adoption',
                            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                                fontSize: 17, color: kDashInk)),
                        TextButton(
                          onPressed: () => _ouvrir(MesAnnoncesPage(isAssociation: true)),
                          child: const Text('Voir toutes →',
                              style: TextStyle(fontFamily: 'Galey', fontSize: 13.5, fontWeight: FontWeight.w600, color: _teal)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: kDashBorder),
                        boxShadow: kDashOmbre,
                      ),
                      child: Column(
                        children: _annonces.asMap().entries.map((entry) {
                          final i = entry.key;
                          final ann = entry.value;
                          final photos = List<String>.from(ann['photos'] ?? []);
                          return Column(children: [
                            ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: photos.isNotEmpty
                                    ? CachedNetworkImage(imageUrl: photos.first,
                                        width: 44, height: 44, fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) => Container(width: 44, height: 44,
                                            color: Colors.grey.shade100,
                                            child: const Icon(Icons.pets, size: 18, color: Colors.grey)))
                                    : Container(width: 44, height: 44, color: Colors.grey.shade100,
                                        child: const Icon(Icons.pets, size: 18, color: Colors.grey)),
                              ),
                              title: Text(ann['titre'] as String? ?? '${ann['espece']} ${ann['race'] ?? ''}'.trim(),
                                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                ann['prix'] != null && (ann['prix'] as num) > 0
                                    ? '${ann['prix']}€ — Adoption'
                                    : 'Gratuit — Adoption',
                                style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8F5E9),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text('Disponible',
                                    style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                                        color: Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
                              ),
                            ),
                            if (i < _annonces.length - 1)
                              Divider(height: 1, indent: 60, color: Colors.grey.shade200),
                          ]);
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ligneAnimal(Map<String, dynamic> a) {
    final cfg = _statutConfig[a['statut'] as String?];
    final photo = (a['photo_url'] ?? '').toString();
    final espece = (a['espece'] ?? '').toString();
    final enFa = a['fa_id'] != null && !_anciens.contains(a['statut']);
    return InkWell(
      onTap: () => _ouvrirFiche(a['id'].toString()),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(width: 46, height: 46,
              child: photo.isNotEmpty
                  ? CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: const Color(0xFFE8F4F6)),
                      errorWidget: (_, __, ___) => Container(color: const Color(0xFFE8F4F6),
                          child: const Icon(Icons.pets_outlined, color: _teal, size: 22)))
                  : Container(color: const Color(0xFFE8F4F6),
                      child: const Icon(Icons.pets_outlined, color: _teal, size: 22)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((a['nom'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14, color: kDashInk)),
            const SizedBox(height: 5),
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (cfg != null) DashPuce(cfg.$1, fg: cfg.$3, bg: cfg.$2, point: true),
              if (enFa) const DashPuce('En FA', fg: Color(0xFF6A1B9A), bg: Color(0xFFF3E5F5), point: true),
              if (espece.isNotEmpty)
                Text(espece[0].toUpperCase() + espece.substring(1),
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: kDashMuted)),
            ]),
          ])),
          const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
        ]),
      ),
    );
  }

  Widget _ligneMouvement(_Mouvement m) => InkWell(
        onTap: () => _ouvrirFiche(m.animalId),
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Row(children: [
          Container(width: 10, height: 10, margin: const EdgeInsets.only(left: 4, right: 12),
              decoration: BoxDecoration(color: m.sortie ? const Color(0xFF0F766E) : _teal, shape: BoxShape.circle)),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.nom, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600, color: kDashInk)),
            Text(m.libelle, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: kDashMuted)),
          ])),
          Text(DateFormat('d MMM yyyy', 'fr').format(m.date),
              style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, fontWeight: FontWeight.w600, color: kDashMuted)),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
        ])),
      );
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard(this.label, this.value, this.icon, this.color, {this.onTap});

  @override
  Widget build(BuildContext context) =>
      Expanded(child: DashStat(valeur: '$value', label: label, icon: icon, teinte: color, onTap: onTap));
}
