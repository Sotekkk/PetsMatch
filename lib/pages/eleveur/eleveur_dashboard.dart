// Accueil du profil Éleveur dans l'appli : tableau de bord (présentation
// seulement). Données : utils/tableau_bord_eleveur.dart (lecture des modules
// existants) ; coche d'une tâche simple : utils/valider_tache.dart. Les soins
// et les RDV vétérinaires ouvrent leur module (inscription au carnet,
// récapitulatif du RDV). Chaque raccourci ouvre l'écran existant.
// Utilisé UNIQUEMENT pour l'éleveur (EleveurHomePage, !User_Info.isPro) :
// les autres métiers gardent leur propre tableau de bord.
// Miroir site : website/src/components/EleveurDashboard.tsx.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/widgets/dashboard/dashboard_kit.dart';
import 'package:PetsMatch/utils/tableau_bord_eleveur.dart';
import 'package:PetsMatch/utils/valider_tache.dart';
import 'package:PetsMatch/pages/agenda/agenda_page.dart';
import 'package:PetsMatch/pages/eleveur/abonnement_page.dart';
import 'package:PetsMatch/pages/eleveur/admin/contrat_reservation.dart';
import 'package:PetsMatch/pages/eleveur/admin/registre_entree_sortie.dart';
import 'package:PetsMatch/pages/eleveur/admin/registre_sanitaire.dart';
import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart';
import 'package:PetsMatch/pages/eleveur/animaux/mes_animaux.dart';
import 'package:PetsMatch/pages/eleveur/animaux/recuperations_page.dart';
import 'package:PetsMatch/pages/eleveur/planning/planning_jour_page.dart';
import 'package:PetsMatch/pages/eleveur/post/create_annonce_page.dart';
import 'package:PetsMatch/pages/eleveur/post/mes_annonces_page.dart';

const _vert = Color(0xFF6E9E57);
const _rouge = Color(0xFFB42318);
const _orange = Color(0xFFFF9800);
const _maxLignes = 5;

class EleveurDashboard extends StatefulWidget {
  final int animalCount;
  final int postCount;
  final String planCode;
  /// Liste « Dernières annonces » existante de l'accueil (rendu inchangé).
  final Widget annoncesRecentes;
  const EleveurDashboard({super.key, required this.animalCount, required this.postCount,
      required this.planCode, required this.annoncesRecentes});

  @override
  State<EleveurDashboard> createState() => _EleveurDashboardState();
}

class _EleveurDashboardState extends State<EleveurDashboard> {
  DonneesTB? _donnees;
  bool _erreur = false;
  String? _enCours;
  /// Profil pour lequel les données ont été lues : jamais celles d'un autre profil.
  String _profilCharge = '';

  @override
  void initState() {
    super.initState();
    _charger();
    User_Info.profileNotifier.addListener(_surChangementProfil);
  }

  @override
  void dispose() {
    User_Info.profileNotifier.removeListener(_surChangementProfil);
    super.dispose();
  }

  void _surChangementProfil() {
    if (!mounted) return;
    setState(() => _donnees = null);
    _charger();
  }

  /// uid réel du propriétaire du profil actif (cogérant compris) — même calcul
  /// que EleveurHomePage._loadData.
  Future<String> _ownerUid(String uid) async {
    final pid = User_Info.activeProfileId;
    final profilDuCompte = User_Info.availableProfiles.any((p) =>
        p['id']?.toString() == pid && p['_is_cogerance'] != true);
    if (pid.isEmpty || profilDuCompte) return uid;
    final row = await Supabase.instance.client.from('user_profiles_complet')
        .select('uid').eq('id', pid).maybeSingle();
    return (row?['uid'] as String?) ?? uid;
  }

  Future<void> _charger() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final pid = User_Info.activeProfileId;
    try {
      final d = await chargerTableauBord(userUid: uid, ownerUid: await _ownerUid(uid), activeProfileId: pid);
      if (!mounted || pid != User_Info.activeProfileId) return;
      setState(() { _donnees = d; _erreur = false; _profilCharge = pid; });
    } catch (_) {
      if (mounted) setState(() => _erreur = true);
    }
  }

  void _ouvrir(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page)).then((_) { if (mounted) _charger(); });

  void _ouvrirAgenda({DateTime? jour}) => Navigator.push(context, MaterialPageRoute(
      builder: (ctx) => AgendaPage(onBack: () => Navigator.pop(ctx), jourInitial: jour,
          initialViewMode: jour != null ? 1 : 0))).then((_) { if (mounted) _charger(); });

  void _ouvrirLigne(LigneTB l) => switch (l.cible) {
        CibleTB.planning => _ouvrir(PlanningJourPage(initialDate: l.date)),
        // Rappel du carnet : onglet Santé de la fiche (index 1 chez l'éleveur).
        CibleTB.fiche => _ouvrir(AnimalFichePage(animalId: l.animalId, initialTabIndex: 1)),
        CibleTB.jour => _ouvrirAgenda(jour: l.date),
      };

  Future<void> _cocher(LigneTB l) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || l.brut == null || _enCours != null) return;
    setState(() => _enCours = l.cle);
    try {
      final pid = User_Info.activeProfileId;
      final statut = l.tableCochable == 'taches_elevage'
          ? await basculerTacheManuelle(l.brut!, uid: uid, profileId: pid)
          : await basculerRoutine(l.brut!, uid: uid, profileId: pid);
      // La tâche cochée reste visible, cochée.
      if (mounted) setState(() { l.brut!['statut'] = statut; l.fait = statut == 'fait'; });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(behavior: SnackBarBehavior.floating,
            content: Text("La tâche n'a pas pu être mise à jour. Réessayez depuis l'agenda.", style: TextStyle(fontFamily: 'Galey'))));
      }
    } finally {
      if (mounted) setState(() => _enCours = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _profilCharge == User_Info.activeProfileId ? _donnees : null;
    final aFaireOuvertes = d?.aFaire.where((l) => !l.fait).length;
    final soinsOuverts = d?.soins.where((l) => !l.fait).length;
    final soinsRetard = d?.soins.where((l) => !l.fait && l.retard).length ?? 0;
    final rdv = d?.agenda.where((l) => !l.fait).length;
    final gratuit = widget.planCode == 'free';

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Indicateurs compacts, défilement horizontal.
      SizedBox(
        height: 66,
        child: ListView(scrollDirection: Axis.horizontal, clipBehavior: Clip.none, children: [
          _Indicateur(valeur: '${widget.animalCount}', label: 'Animaux', icon: Icons.cruelty_free_outlined,
              onTap: () => _ouvrir(const MesAnimauxPage())),
          _Indicateur(valeur: aFaireOuvertes?.toString() ?? '–', label: 'Tâches en attente', icon: Icons.task_alt, teinte: _vert,
              onTap: () => _ouvrirAgenda()),
          _Indicateur(valeur: rdv?.toString() ?? '–', label: 'Agenda ($kHorizonJours j)', icon: Icons.event_outlined,
              teinte: const Color(0xFF2196F3), onTap: () => _ouvrirAgenda()),
          _Indicateur(valeur: '${widget.postCount}', label: 'Annonces actives', icon: Icons.campaign_outlined,
              onTap: () => _ouvrir(const MesAnnoncesPage())),
          _Indicateur(valeur: soinsOuverts?.toString() ?? '–',
              label: soinsRetard > 0 ? 'Soins, $soinsRetard en retard' : 'Échéances sanitaires',
              icon: Icons.vaccines_outlined, teinte: soinsRetard > 0 ? _rouge : _orange,
              onTap: () => _ouvrir(gratuit ? const AbonnementPage() : const RegistreSanitairePage())),
        ]),
      ),
      const SizedBox(height: 14),

      // Accès rapides (écrans existants).
      GridView.count(
        crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1.45,
        children: [
          _Raccourci(label: 'Ajouter un animal', icon: Icons.add_circle_outline,
              onTap: () => _ouvrir(const MesAnimauxPage(ouvrirAjout: true))),
          _Raccourci(label: 'Ajouter une tâche', icon: Icons.add_task_outlined,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (ctx) =>
                  AgendaPage(onBack: () => Navigator.pop(ctx), autoOpenAddTache: true))).then((_) { if (mounted) _charger(); })),
          _Raccourci(label: 'Agenda', icon: Icons.calendar_month_outlined, onTap: () => _ouvrirAgenda()),
          _Raccourci(label: 'Créer une annonce', icon: Icons.campaign_outlined,
              onTap: () => _ouvrir(const CreateAnnoncePage())),
          _Raccourci(label: 'Entrée / Sortie', icon: Icons.swap_horiz, verrou: gratuit,
              onTap: () => _ouvrir(gratuit ? const AbonnementPage() : const RegistreEntreeSortiePage())),
          _Raccourci(label: 'Créer un contrat', icon: Icons.edit_document,
              onTap: () => _ouvrir(const ContratReservationPage())),
        ],
      ),

      if (_erreur) ...[
        const SizedBox(height: 14),
        DashCarte(child: Row(children: [
          const Expanded(child: Text("Le tableau de bord n'a pas pu être chargé.",
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: kDashMuted))),
          DashLien('Réessayer', onTap: _charger),
        ])),
      ],

      const SizedBox(height: 16),
      _Bloc(titre: 'À faire', icone: Icons.task_alt, compteur: aFaireOuvertes,
          voirTout: () => _ouvrirAgenda(),
          child: _Liste(lignes: d?.aFaire, vide: 'Aucune tâche en attente ni prévue cette semaine.',
              rendu: (l) => _LigneTache(l: l, enCours: _enCours == l.cle,
                  onCocher: () => _cocher(l), onOuvrir: () => _ouvrirLigne(l)))),
      const SizedBox(height: 14),
      _Bloc(titre: 'Soins et échéances', icone: Icons.vaccines_outlined, compteur: soinsRetard, compteurAlerte: true,
          libelleVoirTout: 'Suivi sanitaire',
          voirTout: () => _ouvrir(gratuit ? const AbonnementPage() : const RegistreSanitairePage()),
          child: _Liste(lignes: d?.soins, vide: 'Aucun soin prévu cette semaine ni en retard.',
              rendu: (l) => _LigneSimple(l: l, onTap: () => _ouvrirLigne(l)))),
      const SizedBox(height: 14),
      _Bloc(titre: 'Agenda', icone: Icons.event_outlined, voirTout: () => _ouvrirAgenda(),
          child: _Liste(lignes: d?.agenda, vide: 'Aucun événement dans les $kHorizonJours prochains jours.',
              rendu: (l) => _LigneSimple(l: l, onTap: () => _ouvrirLigne(l)))),
      const SizedBox(height: 14),
      _Bloc(titre: 'Activité', icone: Icons.description_outlined,
          compteur: d == null ? null : d.contrats.length + d.recuperations.length,
          child: d == null ? const _Chargement() : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final c in d.contrats.take(_maxLignes))
              _LigneActivite(icon: Icons.edit_document, titre: c.titre, sousTitre: c.animalNom,
                  statut: _statutContrat(c.statut), onTap: () => _ouvrir(const ContratReservationPage())),
            if (d.recuperations.isNotEmpty)
              _LigneActivite(icon: Icons.autorenew,
                  titre: '${d.recuperations.length} demande${d.recuperations.length > 1 ? 's' : ''} de récupération en attente',
                  sousTitre: d.recuperations.take(3).join(', '), onTap: () => _ouvrir(const RecuperationsPage())),
            if (d.contrats.isNotEmpty || d.recuperations.isNotEmpty) const SizedBox(height: 10),
            Row(children: [
              const Expanded(child: Text('DERNIÈRES ANNONCES', style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: 0.5, color: kDashMuted))),
              DashLien('Voir tout', onTap: () => _ouvrir(const MesAnnoncesPage())),
            ]),
            widget.annoncesRecentes,
          ])),
    ]);
  }

  (String, Color, Color) _statutContrat(String s) => switch (s) {
        'brouillon' => ('Brouillon à envoyer', const Color(0xFF6B7280), const Color(0xFFF3F4F6)),
        'partiellement_signe' => ('Signature partielle', const Color(0xFF1D4ED8), const Color(0xFFDBEAFE)),
        _ => ('En attente de signature', const Color(0xFFB45309), const Color(0xFFFEF3C7)),
      };
}

String _libelleJour(DateTime j) {
  final now = DateTime.now();
  final auj = DateTime(now.year, now.month, now.day);
  final ecart = j.difference(auj).inDays;
  if (ecart == 0) return "Aujourd'hui";
  if (ecart == 1) return 'Demain';
  if (ecart == -1) return 'Hier';
  return DateFormat(ecart > 0 && ecart < 7 ? 'EEE d MMM' : 'd MMM', 'fr').format(j);
}

class _Indicateur extends StatelessWidget {
  final String valeur, label;
  final IconData icon;
  final Color teinte;
  final VoidCallback onTap;
  const _Indicateur({required this.valeur, required this.label, required this.icon, required this.onTap, this.teinte = kDashTeal});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: Colors.white, borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14), onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minWidth: 132),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kDashBorder), boxShadow: kDashOmbre),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 32, height: 32,
                    decoration: BoxDecoration(color: teinte.withValues(alpha: 0.09), shape: BoxShape.circle),
                    child: Icon(icon, size: 17, color: teinte)),
                const SizedBox(width: 8),
                Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(valeur, style: const TextStyle(fontFamily: 'Galey', fontSize: 19, fontWeight: FontWeight.w700, color: kDashInk)),
                  Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Color(0xFF4B5563))),
                ]),
              ]),
            ),
          ),
        ),
      );
}

class _Raccourci extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool verrou;
  const _Raccourci({required this.label, required this.icon, required this.onTap, this.verrou = false});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14), onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kDashBorder), boxShadow: kDashOmbre),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Stack(clipBehavior: Clip.none, children: [
                Icon(icon, size: 24, color: verrou ? Colors.grey : kDashTeal),
                if (verrou) const Positioned(right: -8, top: -6, child: Icon(Icons.lock, size: 12, color: Colors.grey)),
              ]),
              const SizedBox(height: 6),
              Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: kDashInk, height: 1.15)),
            ]),
          ),
        ),
      );
}

class _Bloc extends StatelessWidget {
  final String titre;
  final IconData icone;
  final int? compteur;
  final bool compteurAlerte;
  final VoidCallback? voirTout;
  final String libelleVoirTout;
  final Widget child;
  const _Bloc({required this.titre, required this.icone, required this.child, this.compteur,
      this.compteurAlerte = false, this.voirTout, this.libelleVoirTout = 'Voir tout'});

  @override
  Widget build(BuildContext context) => DashCarte(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icone, size: 19, color: kDashTeal),
            const SizedBox(width: 8),
            Flexible(child: Text(titre, style: const TextStyle(fontFamily: 'Galey', fontSize: 16,
                fontWeight: FontWeight.w700, color: kDashInk))),
            if ((compteur ?? 0) > 0) ...[
              const SizedBox(width: 6),
              Container(
                constraints: const BoxConstraints(minWidth: 20), height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 6), alignment: Alignment.center,
                decoration: BoxDecoration(color: compteurAlerte ? const Color(0xFFDC2626) : const Color(0xFFE8F4F6),
                    borderRadius: BorderRadius.circular(10)),
                child: Text('$compteur', style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w700,
                    color: compteurAlerte ? Colors.white : kDashTeal)),
              ),
            ],
            const Spacer(),
            if (voirTout != null) DashLien(libelleVoirTout, onTap: voirTout) else const SizedBox(height: 40),
          ]),
          Padding(padding: const EdgeInsets.only(right: 6), child: child),
        ]),
      );
}

class _Chargement extends StatelessWidget {
  const _Chargement();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: kDashTeal))),
      );
}

class _Liste extends StatefulWidget {
  final List<LigneTB>? lignes;
  final String vide;
  final Widget Function(LigneTB) rendu;
  const _Liste({required this.lignes, required this.vide, required this.rendu});
  @override
  State<_Liste> createState() => _ListeState();
}

class _ListeState extends State<_Liste> {
  bool _tout = false;
  @override
  Widget build(BuildContext context) {
    final l = widget.lignes;
    if (l == null) return const _Chargement();
    if (l.isEmpty) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(widget.vide, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: kDashMuted)));
    }
    final visibles = _tout ? l : l.take(_maxLignes).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < visibles.length; i++) ...[
        if (i > 0) const Divider(height: 1, color: Color(0xFFEEF0EE)),
        widget.rendu(visibles[i]),
      ],
      if (l.length > _maxLignes)
        Align(alignment: Alignment.centerLeft, child: DashLien(
            _tout ? 'Réduire' : 'Afficher les ${l.length - _maxLignes} autres',
            onTap: () => setState(() => _tout = !_tout))),
    ]);
  }
}

Widget _quand(LigneTB l) => Text(
      '${l.retard ? 'En retard · ' : ''}${_libelleJour(l.date)}${l.heure != null && l.heure!.length >= 5 ? ' · ${l.heure!.substring(0, 5)}' : ''}',
      style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, fontWeight: FontWeight.w600,
          color: l.retard ? _rouge : kDashMuted));

Widget? _details(LigneTB l) {
  final infos = [l.animal, l.sousTitre, l.responsable != null ? 'Responsable : ${l.responsable}' : null]
      .where((s) => (s ?? '').isNotEmpty).join(' · ');
  return infos.isEmpty ? null : Text(infos, maxLines: 1, overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: kDashMuted));
}

Widget _titreLigne(LigneTB l) => Text(l.titre, maxLines: 2, overflow: TextOverflow.ellipsis,
    style: TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600,
        color: l.fait ? Colors.grey : kDashInk, decoration: l.fait ? TextDecoration.lineThrough : null));

class _LigneTache extends StatelessWidget {
  final LigneTB l;
  final bool enCours;
  final VoidCallback onCocher, onOuvrir;
  const _LigneTache({required this.l, required this.enCours, required this.onCocher, required this.onOuvrir});

  @override
  Widget build(BuildContext context) => Row(children: [
        // Zone tactile de 44 px pour la case à cocher.
        InkResponse(
          onTap: enCours ? null : onCocher, radius: 22,
          child: SizedBox(width: 44, height: 48, child: Center(child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 22, height: 22,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: l.fait ? _vert : Colors.transparent,
              border: Border.all(color: l.fait ? _vert : Colors.grey.shade400, width: 2),
            ),
            child: enCours
                ? const Padding(padding: EdgeInsets.all(3), child: CircularProgressIndicator(strokeWidth: 2, color: _vert))
                : (l.fait ? const Icon(Icons.check_rounded, size: 15, color: Colors.white) : null),
          ))),
        ),
        Expanded(child: InkWell(
          onTap: onOuvrir,
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 9), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            _titreLigne(l),
            if (_details(l) != null) _details(l)!,
            const SizedBox(height: 2),
            _quand(l),
          ])),
        )),
      ]);
}

class _LigneSimple extends StatelessWidget {
  final LigneTB l;
  final VoidCallback onTap;
  const _LigneSimple({required this.l, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Row(children: [
          Container(width: 10, height: 10, margin: const EdgeInsets.only(left: 4, right: 12),
              decoration: BoxDecoration(color: l.retard ? _rouge : (l.couleur ?? _orange), shape: BoxShape.circle)),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _titreLigne(l),
            if (_details(l) != null) _details(l)!,
            const SizedBox(height: 2),
            _quand(l),
          ])),
          const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
        ])),
      );
}

class _LigneActivite extends StatelessWidget {
  final IconData icon;
  final String titre;
  final String? sousTitre;
  final (String, Color, Color)? statut;
  final VoidCallback onTap;
  const _LigneActivite({required this.icon, required this.titre, required this.onTap, this.sousTitre, this.statut});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 9), child: Row(children: [
          Container(width: 34, height: 34,
              decoration: const BoxDecoration(color: Color(0xFFE8F4F6), shape: BoxShape.circle),
              child: Icon(icon, size: 17, color: kDashTeal)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titre, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600, color: kDashInk)),
            if ((sousTitre ?? '').isNotEmpty)
              Text(sousTitre!, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: kDashMuted)),
            if (statut != null) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: statut!.$3, borderRadius: BorderRadius.circular(10)),
                child: Text(statut!.$1, style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w700, color: statut!.$2)),
              ),
            ],
          ])),
          const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
        ])),
      );
}

