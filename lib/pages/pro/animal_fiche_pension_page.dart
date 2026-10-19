import 'package:PetsMatch/widgets/animal/pro_animal_entete.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:PetsMatch/pages/eleveur/animaux/animal_fiche.dart' show AddVermifugeDialog, AddAntiparasitaireDialog;
import 'package:PetsMatch/pages/pro/pension_tarifs_page.dart' show pensionLogementTypeLabel;
import 'package:PetsMatch/pages/pro/registre_pension_page.dart' show alimSejourFromRaw, alimSejourFournisParLabel;
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/sante_couleurs.dart';
import 'package:PetsMatch/pages/pro/pension_arrivee_depart.dart';
import 'package:PetsMatch/pages/pro/pension_journal_page.dart';

class AnimalFichePensionPage extends StatefulWidget {
  final String animalId;
  final String? animalNom;

  const AnimalFichePensionPage({
    super.key,
    required this.animalId,
    this.animalNom,
  });

  @override
  State<AnimalFichePensionPage> createState() => _AnimalFichePensionPageState();
}

class _AnimalFichePensionPageState extends State<AnimalFichePensionPage>
    with SingleTickerProviderStateMixin {
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);
  static const _purple = Color(0xFF7B5EA7);

  final _supa = Supabase.instance.client;
  late TabController _tabs;

  bool _loading = true;
  bool _hasAccess = false;

  // Identity
  Map<String, dynamic>? _animal;

  // Health
  List<Map<String, dynamic>> _vaccinations    = [];
  List<Map<String, dynamic>> _vermifuges      = [];
  List<Map<String, dynamic>> _antiparasitaires = [];
  List<Map<String, dynamic>> _traitements     = [];
  List<Map<String, dynamic>> _allergies       = [];
  List<Map<String, dynamic>> _visites         = [];
  List<Map<String, dynamic>> _chirurgies      = [];
  List<Map<String, dynamic>> _poids           = [];

  // Alimentation
  Map<String, dynamic>? _alimentation;

  // Propriétaire réel (animaux_proprietes → user_profiles) + séjour en cours
  // (pension_entrees) — au lieu du texte libre saisi manuellement à l'entrée.
  Map<String, dynamic>? _proprietaire;
  Map<String, dynamic>? _sejourActuel;
  Map<String, dynamic>? _sejourLogement; // enclos_chenil {nom, type} du séjour
  /// Tous les séjours de l'animal dans CETTE pension (à venir, en cours, terminés).
  List<Map<String, dynamic>> _sejours = [];
  final Map<String, String> _logementsNoms = {};
  /// Tâches (protocoles) et observations du suivi quotidien.
  List<Map<String, dynamic>> _taches = [];
  List<Map<String, dynamic>> _observations = [];
  String _consignesVue = 'alimentation';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Vérifier l'accès avant de charger quoi que ce soit — animal_access
      // doit être 'active' (validé par le propriétaire), sinon la fiche
      // santé/alimentation reste inaccessible même en lecture.
      // Repli (profil actif inconnu) : le profil pension / pet-sitter du
      // compte — jamais is_main (souvent l'élevage, accès d'un autre profil).
      var proProfileId = User_Info.activeProfileId;
      if (proProfileId.isEmpty) {
        final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
        final proProfile = myUid.isEmpty ? null : await _supa.from('user_profiles_complet')
            .select('id').eq('uid', myUid).inFilter('profile_type', ['pension', 'garde']).limit(1).maybeSingle();
        proProfileId = proProfile?['id'] as String? ?? '';
      }
      final acc = proProfileId.isEmpty ? null : await _supa.from('animal_access')
          .select('statut').eq('animal_id', widget.animalId).eq('pro_profile_id', proProfileId)
          .eq('statut', 'active').maybeSingle();
      if (acc == null) {
        if (mounted) setState(() { _hasAccess = false; _loading = false; });
        return;
      }
      _hasAccess = true;

      final results = await Future.wait([
        _supa.from('animaux').select('*').eq('id', widget.animalId).single(),
        _supa.from('vaccinations').select().eq('animal_id', widget.animalId).order('date', ascending: false),
        _supa.from('vermifuges').select().eq('animal_id', widget.animalId).order('date', ascending: false),
        _supa.from('antiparasitaires').select().eq('animal_id', widget.animalId).order('date', ascending: false),
        _supa.from('traitements').select().eq('animal_id', widget.animalId).order('date', ascending: false),
        _supa.from('allergies').select().eq('animal_id', widget.animalId).order('date', ascending: false),
        _supa.from('poids').select().eq('animal_id', widget.animalId).order('date', ascending: false),
        _supa.from('visites').select().eq('animal_id', widget.animalId).order('date', ascending: false),
        _supa.from('alimentations').select().eq('animal_id', widget.animalId).maybeSingle(),
        _supa.from('chirurgies').select().eq('animal_id', widget.animalId).order('date', ascending: false),
      ]);
      if (!mounted) return;
      setState(() {
        _animal           = results[0] as Map<String, dynamic>?;
        _vaccinations     = _toList(results[1]);
        _vermifuges       = _toList(results[2]);
        _antiparasitaires = _toList(results[3]);
        _traitements      = _toList(results[4]);
        _allergies        = _toList(results[5]);
        _poids            = _toList(results[6]);
        _visites          = _toList(results[7]);
        _alimentation     = results[8] as Map<String, dynamic>?;
        _chirurgies       = _toList(results[9]);
        _loading          = false;
      });

      // Propriétaire réel + séjour en cours — chargés à part, ne doivent pas
      // bloquer l'affichage du reste de la fiche s'ils échouent.
      _loadProprietaireEtSejour();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadProprietaireEtSejour() async {
    try {
      final lien = await _supa.from('animaux_proprietes').select()
          .eq('animal_id', widget.animalId).isFilter('date_fin', null)
          .order('date_debut', ascending: false).limit(1).maybeSingle();

      Map<String, dynamic>? profil;
      if (lien != null) {
        final profileId = lien['profile_id_proprio'] as String?;
        if (profileId != null && profileId.isNotEmpty) {
          profil = await _supa.from('user_profiles_complet').select()
              .eq('id', profileId).maybeSingle();
        }
        // Repli : uid seul (données antérieures au multi-profil) → profil principal.
        profil ??= await _supa.from('user_profiles_complet').select()
            .eq('uid', lien['uid_proprio']).eq('is_main', true).maybeSingle();

        // Repli téléphone : user_profiles.phone_number contient parfois le
        // placeholder "0000000000" jamais mis à jour depuis users (vraie donnée
        // saisie à l'inscription).
        final tel = (profil?['phone_number'] as String?)?.trim() ?? '';
        if (profil != null && (tel.isEmpty || tel == '0000000000')) {
          try {
            final u = await _supa.from('users_complet').select('phone_number')
                .eq('uid', lien['uid_proprio']).maybeSingle();
            final uTel = (u?['phone_number'] as String?)?.trim() ?? '';
            if (uTel.isNotEmpty) profil = {...profil, 'phone_number': uTel};
          } catch (_) {}
        }
      }

      // Séjours de CETTE pension uniquement (pro_uid + profil actif).
      final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final tous = List<Map<String, dynamic>>.from((await _supa.from('pension_entrees').select()
          .eq('animal_id', widget.animalId).eq('pro_uid', myUid)
          .order('date_entree', ascending: false)) as List).where(sejourDuProfil).toList();
      final enPension = tous.where((e) => e['statut'] == 'en_pension').toList();
      final jourStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final sejour = enPension.where((e) => (e['date_entree']?.toString() ?? '').compareTo(jourStr) <= 0).firstOrNull
          ?? (enPension.isEmpty ? null : enPension.last);
      try {
        final logs = await _supa.from('enclos_chenil').select('id, nom').eq('uid_eleveur', myUid);
        for (final l in logs as List) { _logementsNoms[l['id'].toString()] = l['nom']?.toString() ?? ''; }
      } catch (_) {}
      try {
        _taches = List<Map<String, dynamic>>.from(await _supa.from('taches_elevage').select()
            .eq('animal_id', widget.animalId).eq('profil_source', 'pension')
            .gte('date', DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 7))))
            .order('date', ascending: false));
      } catch (_) { _taches = []; }
      try {
        _observations = List<Map<String, dynamic>>.from(await _supa.from('pension_updates').select()
            .eq('animal_id', widget.animalId).eq('pro_uid', myUid)
            .order('created_at', ascending: false).limit(30));
      } catch (_) { _observations = []; }

      Map<String, dynamic>? logement;
      final logementId = sejour?['logement_id']?.toString();
      if (logementId != null && logementId.isNotEmpty) {
        try {
          logement = await _supa.from('enclos_chenil')
              .select('nom, type').eq('id', logementId).maybeSingle();
        } catch (_) {}
      }

      if (mounted) setState(() {
        _proprietaire = profil;
        _sejourActuel = sejour;
        _sejourLogement = logement;
        _sejours = tous;
      });
    } catch (_) {}
  }

  // Recharge uniquement vermifuges/antiparasitaires après un ajout, sans
  // repasser par _load() (évite de réinitialiser tout le reste de la fiche).
  Future<void> _reloadTraitements() async {
    try {
      final results = await Future.wait([
        _supa.from('vermifuges').select().eq('animal_id', widget.animalId).order('date', ascending: false),
        _supa.from('antiparasitaires').select().eq('animal_id', widget.animalId).order('date', ascending: false),
      ]);
      if (!mounted) return;
      setState(() {
        _vermifuges       = _toList(results[0]);
        _antiparasitaires = _toList(results[1]);
      });
    } catch (_) {}
  }

  Future<void> _addVermifuge({Map<String, dynamic>? renouvellementDe}) async {
    await showDialog(
      context: context,
      builder: (_) => AddVermifugeDialog(
        animalId: widget.animalId,
        prefillProduit: renouvellementDe?['produit'] as String?,
        prefillDosage: renouvellementDe?['dosage'] as String?,
      ),
    );
    _reloadTraitements();
  }

  Future<void> _addAntiparasitaire({Map<String, dynamic>? renouvellementDe}) async {
    await showDialog(
      context: context,
      builder: (_) => AddAntiparasitaireDialog(
        animalId: widget.animalId,
        prefillProduit: renouvellementDe?['produit'] as String?,
        prefillType: renouvellementDe?['type'] as String?,
      ),
    );
    _reloadTraitements();
  }

  List<Map<String, dynamic>> _toList(dynamic raw) =>
      raw is List ? List<Map<String, dynamic>>.from(raw) : [];

  static String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try { return DateFormat('dd/MM/yyyy').format(DateTime.parse(iso)); } catch (_) { return iso; }
  }



  @override
  Widget build(BuildContext context) {
    final nom = _animal?['nom'] ?? widget.animalNom ?? 'Animal';
    final espece = (_animal?['espece'] ?? '').toString();
    final photoUrl = _animal?['photo_url'] as String?;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _purple,
        foregroundColor: Colors.white,
        title: Text(nom,
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: (!_loading && !_hasAccess) ? null : TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(
              fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13),
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Synthèse'),
            Tab(text: 'Séjours'),
            Tab(text: 'Consignes & soins'),
            Tab(text: 'Suivi quotidien'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _purple))
          : !_hasAccess
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.lock_clock_outlined, size: 56, color: Color(0xFFBFC5C9)),
                      const SizedBox(height: 16),
                      const Text('Accès non validé',
                          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17, color: Color(0xFF1F2A2E))),
                      const SizedBox(height: 8),
                      Text(
                        'La demande d\'accès à la fiche de ${widget.animalNom ?? "cet animal"} est en attente de validation par le propriétaire.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500, height: 1.4),
                      ),
                    ]),
                  ),
                )
              : Column(children: [
                  _ReadOnlyBanner(espece: espece, photoUrl: photoUrl),
                  // En-tête commun : identité + propriétaire, urgence, personnes autorisées.
                  ProAnimalEntete(animalId: widget.animalId, catPro: 'pension',
                      statut: _sejourActuel != null ? 'En pension' : null),
                  Expanded(
                    child: TabBarView(controller: _tabs, children: [
                      _syntheseTab(),
                      _sejoursTab(),
                      _consignesTab(),
                      _suiviTab(),
                    ]),
                  ),
                ]),
    );
  }

  // ── Synthèse ──────────────────────────────────────────────────────────────

  bool get _present {
    final s = _sejourActuel;
    if (s == null || s['statut'] != 'en_pension') return false;
    final d = DateTime.tryParse(s['date_entree']?.toString() ?? '');
    return d != null && !d.isAfter(DateTime.now());
  }

  String _heure(dynamic iso) {
    final d = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
    return d == null ? '' : DateFormat('HH:mm').format(d);
  }

  Widget _carte(String titre, IconData ic, Widget child, {Widget? action}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE6E8E6))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(ic, size: 17, color: _teal),
            const SizedBox(width: 8),
            Expanded(child: Text(titre, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1F2A2E)))),
            if (action != null) action,
          ]),
          const SizedBox(height: 8),
          child,
        ]),
      );

  Widget _discret(String t) => Text(t, style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600));
  Widget _ligne(String t, {Color? couleur, FontWeight? poids}) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t, style: TextStyle(fontFamily: 'Galey', fontSize: 13.5, color: couleur ?? const Color(0xFF1F2A2E), fontWeight: poids)),
      );

  Future<void> _arrivee() async {
    final s = _sejourActuel;
    if (s != null && await confirmerArriveePension(context, s)) _loadProprietaireEtSejour();
  }

  Future<void> _depart() async {
    final s = _sejourActuel;
    if (s != null && await enregistrerDepartPension(context, s)) _loadProprietaireEtSejour();
  }

  Widget _syntheseTab() {
    final s = _sejourActuel;
    final jour = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final tachesJour = _taches.where((t) => t['date']?.toString() == jour).toList();
    final traitementsEnCours = _traitements.where((t) {
      final fin = DateTime.tryParse(t['date_fin']?.toString() ?? '');
      return fin == null || !fin.isBefore(DateTime.now());
    }).toList();
    final consignes = (s?['consignes_sejour']?.toString() ?? '').trim();
    return RefreshIndicator(
      onRefresh: () async { await _load(); },
      color: _teal,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 40), children: [
        _carte('Présence', Icons.home_work_outlined, s == null
            ? _discret('Aucun séjour en cours ni à venir dans votre pension.')
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _ligne(_present ? 'En pension' : 'Arrivée prévue le ${_fmtDate(s['date_entree']?.toString())}',
                    couleur: _present ? _green : _purple, poids: FontWeight.w700),
                _ligne('Arrivée : ${_fmtDate(s['date_entree']?.toString())}${s['arrivee_reelle_le'] != null ? ' à ${_heure(s['arrivee_reelle_le'])}' : ''}'
                    '${(s['depose_par']?.toString() ?? '').isNotEmpty ? ' · déposé par ${s['depose_par']}' : ''}'),
                _ligne('Départ prévu : ${(s['date_sortie_prevue']?.toString() ?? '').isEmpty ? 'non renseigné' : _fmtDate(s['date_sortie_prevue']?.toString())}'),
                _ligne('Hébergement : ${_logementsNoms[s['logement_id']?.toString()] ?? 'non attribué'}'),
                const SizedBox(height: 6),
                Wrap(spacing: 8, children: [
                  if (s['arrivee_reelle_le'] == null)
                    FilledButton.tonal(onPressed: _arrivee, child: const Text("Enregistrer l'arrivée", style: TextStyle(fontFamily: 'Galey'))),
                  if (_present)
                    FilledButton.tonal(onPressed: _depart, child: const Text('Enregistrer le départ', style: TextStyle(fontFamily: 'Galey'))),
                ]),
              ])),
        _carte('Consignes prioritaires', Icons.priority_high_rounded, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (consignes.isNotEmpty) _ligne(consignes),
          for (final a in _allergies) _ligne('Allergie : ${a['nom'] ?? a['allergene'] ?? a['description'] ?? ''}', couleur: const Color(0xFFB3261E)),
          for (final t in traitementsEnCours) _ligne('Traitement : ${t['nom'] ?? ''}${(t['posologie']?.toString() ?? '').isNotEmpty ? ' — ${t['posologie']}' : ''}'),
          if (consignes.isEmpty && _allergies.isEmpty && traitementsEnCours.isEmpty)
            _discret('Aucune consigne particulière renseignée.'),
        ]), action: TextButton(onPressed: () => _tabs.animateTo(2), child: const Text('Détail', style: TextStyle(fontFamily: 'Galey')))),
        _carte("Tâches du jour", Icons.checklist_rtl_outlined, tachesJour.isEmpty
            ? _discret("Aucune tâche prévue aujourd'hui.")
            : Column(children: [for (final t in tachesJour) _tacheLigne(t)]),
            action: TextButton(onPressed: () => _tabs.animateTo(3), child: const Text('Suivi', style: TextStyle(fontFamily: 'Galey')))),
        _carte('Dernières observations', Icons.visibility_outlined, _observations.isEmpty
            ? _discret('Aucune observation partagée.')
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final o in _observations.take(3))
                  _ligne('${_fmtDate(o['created_at']?.toString())} ${_heure(o['created_at'])} — ${(o['note']?.toString() ?? '').trim().isEmpty ? 'Photo / vidéo' : o['note']}'),
              ])),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Identité', style: TextStyle(fontFamily: 'Galey')),
                backgroundColor: _purple, foregroundColor: Colors.white),
            body: _IdentiteTab(animal: _animal, proprietaire: _proprietaire, sejourActuel: _sejourActuel, sejourLogement: _sejourLogement),
          ))),
          icon: const Icon(Icons.badge_outlined, size: 18),
          label: const Text('Identité complète', style: TextStyle(fontFamily: 'Galey')),
        ),
      ]),
    );
  }

  // ── Séjours ───────────────────────────────────────────────────────────────

  Widget _sejoursTab() {
    final jour = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final aVenir = _sejours.where((e) => e['statut'] == 'en_pension' && (e['date_entree']?.toString() ?? '').compareTo(jour) > 0).toList();
    final enCours = _sejours.where((e) => e['statut'] == 'en_pension' && (e['date_entree']?.toString() ?? '').compareTo(jour) <= 0).toList();
    final termines = _sejours.where((e) => e['statut'] != 'en_pension').toList();
    Widget bloc(String titre, List<Map<String, dynamic>> l) => _carte(titre, Icons.event_note_outlined, l.isEmpty
        ? _discret('Aucun.')
        : Column(children: [
            for (final e in l)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Du ${_fmtDate(e['date_entree']?.toString())} au ${_fmtDate((e['date_sortie_effective'] ?? e['date_sortie_prevue'])?.toString())}',
                        style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13.5)),
                    Text([
                      _logementsNoms[e['logement_id']?.toString()] ?? 'Sans hébergement attribué',
                      if (e['arrivee_reelle_le'] != null) 'arrivé à ${_heure(e['arrivee_reelle_le'])}',
                      if (e['depart_reel_le'] != null) 'parti à ${_heure(e['depart_reel_le'])}',
                      if ((e['recupere_par']?.toString() ?? '').isNotEmpty) 'récupéré par ${e['recupere_par']}',
                    ].join(' · '), style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade700)),
                    if ((e['observations_depart']?.toString() ?? '').isNotEmpty)
                      Text(e['observations_depart'].toString(), style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                  ])),
                ]),
              ),
          ]));
    return RefreshIndicator(
      onRefresh: () async { await _load(); },
      color: _teal,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 40), children: [
        bloc('En cours', enCours),
        bloc('À venir', aVenir),
        bloc('Terminés', termines),
      ]),
    );
  }

  // ── Consignes & soins ─────────────────────────────────────────────────────

  Widget _consignesTab() {
    final consignesSejour = (_sejourActuel?['consignes_sejour']?.toString() ?? '').trim();
    Widget seg(String v, String label) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w600,
                color: _consignesVue == v ? Colors.white : const Color(0xFF1F2A2E))),
            selected: _consignesVue == v, showCheckmark: false,
            selectedColor: _teal, backgroundColor: const Color(0xFFF1F4F3), side: BorderSide.none,
            onSelected: (_) => setState(() => _consignesVue = v),
          ),
        );
    return Column(children: [
      if (consignesSejour.isNotEmpty || (_sejourActuel?['effets_personnels']?.toString() ?? '').isNotEmpty)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFFF8E8), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Consignes de ce séjour', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13)),
            if (consignesSejour.isNotEmpty) Text(consignesSejour, style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
            if ((_sejourActuel?['effets_personnels']?.toString() ?? '').isNotEmpty)
              Text('Effets personnels : ${_sejourActuel!['effets_personnels']}', style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5)),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Row(children: [seg('alimentation', 'Alimentation (permanente)'), seg('sante', 'Santé & soins')]),
      ),
      Expanded(child: _consignesVue == 'sante'
          ? _SanteTab(
                        vaccinations: _vaccinations,
                        vermifuges: _vermifuges,
                        antiparasitaires: _antiparasitaires,
                        traitements: _traitements,
                        allergies: _allergies,
                        visites: _visites,
                        chirurgies: _chirurgies,
                        poids: _poids,
                        fmtDate: _fmtDate,
                        onAddVermifuge: ({renouvellementDe}) => _addVermifuge(renouvellementDe: renouvellementDe),
                        onAddAntiparasitaire: ({renouvellementDe}) => _addAntiparasitaire(renouvellementDe: renouvellementDe),
                      )
          : _AlimentationTab(alimentation: _alimentation, alimentationSejour: _sejourActuel?['alimentation_sejour'])),
    ]);
  }

  // ── Suivi quotidien ───────────────────────────────────────────────────────

  Widget _tacheLigne(Map<String, dynamic> t) {
    final fait = t['statut'] == 'fait';
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero, dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      value: fait, activeColor: _green,
      title: Text((t['titre'] ?? 'Tâche').toString(), style: TextStyle(fontFamily: 'Galey', fontSize: 13.5,
          decoration: fait ? TextDecoration.lineThrough : null, color: fait ? Colors.grey : const Color(0xFF1F2A2E))),
      subtitle: Text(_fmtDate(t['date']?.toString()), style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5)),
      onChanged: (v) async {
        final statut = v == true ? 'fait' : 'a_faire';
        setState(() => t['statut'] = statut);
        try {
          await _supa.from('taches_elevage').update({
            'statut': statut,
            if (statut == 'fait' && User_Info.activeProfileId.isNotEmpty) 'fait_par_profile_id': User_Info.activeProfileId,
          }).eq('id', t['id']);
        } catch (_) { _loadProprietaireEtSejour(); }
      },
    );
  }

  Widget _suiviTab() {
    return RefreshIndicator(
      onRefresh: () async { await _load(); },
      color: _teal,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 40), children: [
        _carte('Tâches et soins (7 derniers jours)', Icons.checklist_rtl_outlined, _taches.isEmpty
            ? _discret('Aucune tâche pour cet animal.')
            : Column(children: [for (final t in _taches) _tacheLigne(t)])),
        _carte('Observations et photos', Icons.photo_library_outlined, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_observations.isEmpty) _discret('Aucune observation pour le moment.'),
          for (final o in _observations.take(10))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if ((o['photo_url']?.toString() ?? '').isNotEmpty) ...[
                  ClipRRect(borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(imageUrl: o['photo_url'].toString(), width: 48, height: 48, fit: BoxFit.cover)),
                  const SizedBox(width: 10),
                ],
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${_fmtDate(o['created_at']?.toString())} à ${_heure(o['created_at'])}${o['incident'] == true ? ' · incident' : ''}',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: o['incident'] == true ? const Color(0xFFB3261E) : Colors.grey.shade600)),
                  if ((o['note']?.toString() ?? '').isNotEmpty)
                    Text(o['note'].toString(), style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                ])),
              ]),
            ),
          const SizedBox(height: 4),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => PensionJournalPage(
                animalId: widget.animalId,
                pensionEntreeId: _sejourActuel?['id']?.toString(),
                animalNom: (_animal?['nom'] ?? widget.animalNom ?? 'Animal').toString(),
              )));
              _loadProprietaireEtSejour();
            },
            icon: const Icon(Icons.add_a_photo_outlined, size: 18),
            label: const Text('Ajouter une observation ou une photo', style: TextStyle(fontFamily: 'Galey')),
          )),
        ])),
      ]),
    );
  }
}

// ── Bannière lecture seule ────────────────────────────────────────────────────

class _ReadOnlyBanner extends StatelessWidget {
  final String espece;
  final String? photoUrl;

  const _ReadOnlyBanner({required this.espece, this.photoUrl});

  static const _purple = Color(0xFF7B5EA7);

  @override
  Widget build(BuildContext context) {
    final emoji = {
      'chien': '🐕', 'chat': '🐈', 'lapin': '🐇',
      'oiseau': '🦜', 'cheval': '🐴', 'nac': '🐹',
    }[espece] ?? '🐾';

    return Container(
      color: _purple.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        if (photoUrl != null && photoUrl!.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: photoUrl!,
              width: 40, height: 40, fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _speciesIcon(emoji),
            ),
          )
        else
          _speciesIcon(emoji),
        const SizedBox(width: 12),
        const Expanded(
          child: Text('Accès accordé par le propriétaire · vermifuges/antiparasitaires modifiables',
              style: TextStyle(
                  fontFamily: 'Galey', fontSize: 12,
                  color: _purple, fontWeight: FontWeight.w600)),
        ),
        const Icon(Icons.visibility_outlined, size: 16, color: _purple),
      ]),
    );
  }

  Widget _speciesIcon(String emoji) => Container(
    width: 40, height: 40,
    decoration: BoxDecoration(
      color: _purple.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
  );
}

// ── Onglet Identité ────────────────────────────────────────────────────────────

class _IdentiteTab extends StatelessWidget {
  final Map<String, dynamic>? animal;
  final Map<String, dynamic>? proprietaire;
  final Map<String, dynamic>? sejourActuel;
  final Map<String, dynamic>? sejourLogement;

  const _IdentiteTab({required this.animal, this.proprietaire, this.sejourActuel, this.sejourLogement});

  // Le nom d'affichage diffère selon le type de profil propriétaire :
  // un éleveur/asso a un nom d'établissement (colonne "nom"), un particulier
  // un nom de personne (souvent aussi dans "nom", sinon firstname/lastname).
  static String _ownerName(Map<String, dynamic> p) {
    final nom = (p['nom'] as String?)?.trim();
    if (nom != null && nom.isNotEmpty) return nom;
    final label = (p['profile_label'] as String?)?.trim();
    if (label != null && label.isNotEmpty) return label;
    final full = '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
    return full.isNotEmpty ? full : 'Propriétaire';
  }

  static String? _ownerPhone(Map<String, dynamic> p) =>
      (p['phone_number'] as String?)?.trim().isNotEmpty == true ? p['phone_number'] as String
      : (p['phone'] as String?)?.trim().isNotEmpty == true ? p['phone'] as String
      : (p['telephone'] as String?)?.trim().isNotEmpty == true ? p['telephone'] as String
      : null;

  static String _fmt(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try { return DateFormat('dd/MM/yyyy').format(DateTime.parse(iso)); } catch (_) { return iso; }
  }

  static String _age(String? iso) {
    if (iso == null) return '';
    try {
      final dob = DateTime.parse(iso);
      final now = DateTime.now();
      final m = (now.year - dob.year) * 12 + now.month - dob.month;
      if (m < 12) return '$m mois';
      final y = m ~/ 12; final r = m % 12;
      return r == 0 ? '$y an${y > 1 ? 's' : ''}' : '$y an${y > 1 ? 's' : ''} $r mois';
    } catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) {
    if (animal == null) {
      return const Center(child: Text('Données non disponibles',
          style: TextStyle(fontFamily: 'Galey', color: Colors.grey)));
    }
    final d = animal!;
    final dob = d['date_naissance'] as String?;
    final age = _age(dob);

    final contacts = d['contacts_urgence'];
    final urgList = contacts is List ? contacts : [];

    return ListView(padding: const EdgeInsets.fromLTRB(16, 20, 16, 40), children: [
      if (proprietaire != null) ...[
        _Section(title: 'Propriétaire', children: [
          _Row(proprietaire!['profile_type'] == 'eleveur' || proprietaire!['profile_type'] == 'association'
              ? 'Établissement' : 'Nom', _ownerName(proprietaire!)),
          _Row('Téléphone', _ownerPhone(proprietaire!)),
          _Row('Email', proprietaire!['email_contact']?.toString()),
        ]),
        const SizedBox(height: 16),
      ],
      if (sejourActuel != null) ...[
        _Section(title: 'Séjour en cours', children: [
          _Row('Entré le', _fmt(sejourActuel!['date_entree']?.toString())),
          _Row('Sortie prévue', _fmt(sejourActuel!['date_sortie_prevue']?.toString())),
          if (sejourLogement != null)
            _Row('Logement', [
              sejourLogement!['nom']?.toString(),
              pensionLogementTypeLabel(sejourLogement!['type']?.toString()),
            ].where((s) => (s ?? '').isNotEmpty).join(' · ')),
        ]),
        const SizedBox(height: 16),
      ],
      _Section(title: 'Informations générales', children: [
        _Row('Espèce',      _capitalise(d['espece']?.toString())),
        _Row('Race',        d['race']?.toString()),
        _Row('Sexe',        _sexeLabel(d['sexe']?.toString())),
        _Row('Stérilisé(e)', d['sterilise'] == true ? 'Oui' : 'Non'),
        _Row('Naissance',   dob != null ? '${_fmt(dob)}${age.isNotEmpty ? '  ·  $age' : ''}' : null),
        _Row('Couleur / robe', d['couleur']?.toString()),
        _Row('Couleur des yeux', d['couleur_yeux']?.toString()),
        _Row('Type de poil', d['type_poil']?.toString()),
        _Row('Poids',       d['poids'] != null ? '${d['poids']} kg' : null),
        _Row('Taille',      d['taille'] != null ? '${d['taille']} cm' : null),
      ]),
      const SizedBox(height: 16),
      _Section(title: 'Identification', children: [
        _Row('Puce électronique',   d['identification']?.toString()),
        _Row('Passeport européen',  d['passeport_europeen']?.toString()),
      ]),
      if (d['notes'] != null && d['notes'].toString().isNotEmpty) ...[
        const SizedBox(height: 16),
        _Section(title: 'Notes du propriétaire', children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(d['notes'].toString(),
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14, height: 1.5,
                    color: Color(0xFF374151))),
          ),
        ]),
      ],
      if (urgList.isNotEmpty) ...[
        const SizedBox(height: 16),
        _Section(title: 'Contacts d\'urgence', children: [
          for (final c in urgList)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                const Icon(Icons.phone_outlined, size: 16, color: Color(0xFF0C5C6C)),
                const SizedBox(width: 8),
                Text(
                  [(c['nom'] ?? ''), (c['tel'] ?? '')]
                      .where((s) => s.toString().isNotEmpty).join(' — '),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                ),
              ]),
            ),
        ]),
      ],
    ]);
  }

  static String _capitalise(String? s) {
    if (s == null || s.isEmpty) return '';
    return s[0].toUpperCase() + s.substring(1);
  }

  static String _sexeLabel(String? s) {
    switch (s) {
      case 'male':   return 'Mâle';
      case 'femelle': return 'Femelle';
      default: return s ?? '';
    }
  }
}

// ── Onglet Santé ──────────────────────────────────────────────────────────────

class _SanteTab extends StatelessWidget {
  final List<Map<String, dynamic>> vaccinations;
  final List<Map<String, dynamic>> vermifuges;
  final List<Map<String, dynamic>> antiparasitaires;
  final List<Map<String, dynamic>> traitements;
  final List<Map<String, dynamic>> allergies;
  final List<Map<String, dynamic>> visites;
  final List<Map<String, dynamic>> chirurgies;
  final List<Map<String, dynamic>> poids;
  final String Function(String?) fmtDate;
  final void Function({Map<String, dynamic>? renouvellementDe}) onAddVermifuge;
  final void Function({Map<String, dynamic>? renouvellementDe}) onAddAntiparasitaire;

  const _SanteTab({
    required this.vaccinations,
    required this.vermifuges,
    required this.antiparasitaires,
    required this.traitements,
    required this.allergies,
    required this.visites,
    required this.chirurgies,
    required this.poids,
    required this.fmtDate,
    required this.onAddVermifuge,
    required this.onAddAntiparasitaire,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(16, 20, 16, 40), children: [
      _PanneauSante(children: [
        _HealthSection(
          title: 'Vaccinations',
          color: SanteCouleurs.vaccinations,
          icon: Icons.vaccines_outlined,
          items: vaccinations,
          buildRow: (v) => _MedRow(
            label: v['vaccin']?.toString() ?? v['nom_vaccin']?.toString() ?? '',
            sub: v['veterinaire']?.toString(),
            date: fmtDate(v['date'] as String?),
            extra: v['date_rappel'] != null ? 'Rappel : ${fmtDate(v['date_rappel'] as String?)}' : null,
          ),
        ),
        _HealthSection(
          title: 'Vermifuges',
          color: SanteCouleurs.vermifuges,
          icon: Icons.pest_control_outlined,
          items: vermifuges,
          onAdd: () => onAddVermifuge(),
          buildRow: (v) => _MedRow(
            label: v['produit']?.toString() ?? '',
            sub: v['dosage']?.toString() ?? v['remarques']?.toString(),
            date: fmtDate(v['date'] as String?),
            extra: v['date_rappel'] != null ? 'Rappel : ${fmtDate(v['date_rappel'] as String?)}' : null,
            onRappel: () => onAddVermifuge(renouvellementDe: v),
          ),
        ),
        _HealthSection(
          title: 'Antiparasitaires',
          color: SanteCouleurs.antiparasitaires,
          icon: Icons.bug_report_outlined,
          items: antiparasitaires,
          onAdd: () => onAddAntiparasitaire(),
          buildRow: (a) => _MedRow(
            label: a['produit']?.toString() ?? '',
            sub: a['type']?.toString(),
            date: fmtDate(a['date'] as String?),
            extra: a['date_rappel'] != null ? 'Rappel : ${fmtDate(a['date_rappel'] as String?)}' : null,
            onRappel: () => onAddAntiparasitaire(renouvellementDe: a),
          ),
        ),
        _HealthSection(
          title: 'Traitements',
          color: SanteCouleurs.traitements,
          icon: Icons.medication_outlined,
          items: traitements,
          buildRow: (t) {
            final traitementExtra = [
              if (t['date_fin'] != null) 'Fin : ${fmtDate(t['date_fin'] as String?)}',
              if ((t['notes'] as String?)?.isNotEmpty == true) t['notes'].toString(),
            ].join(' · ');
            return _MedRow(
              label: t['nom']?.toString() ?? t['type']?.toString() ?? '',
              sub: t['posologie']?.toString(),
              date: fmtDate(t['date'] as String?),
              extra: traitementExtra.isEmpty ? null : traitementExtra,
            );
          },
        ),
        _HealthSection(
          title: 'Chirurgie / Hospitalisation',
          color: SanteCouleurs.chirurgies,
          icon: Icons.local_hospital_outlined,
          items: chirurgies,
          buildRow: (c) {
            final st = c['statut']?.toString();
            final label = st == 'realise' ? 'Réalisée' : st == 'annule' ? 'Annulée' : 'Prévue';
            final t = c['type'] == 'hospitalisation' ? 'Hospitalisation' : 'Chirurgie';
            final proto = [
              if ((c['protocole_preop'] ?? '').toString().isNotEmpty) 'Pré-op : ${c['protocole_preop']}',
              if ((c['protocole_postop'] ?? '').toString().isNotEmpty) 'Post-op : ${c['protocole_postop']}',
            ].join('\n');
            return _MedRow(
              label: c['intitule']?.toString() ?? t,
              sub: '$t · $label${(c['clinique'] ?? '').toString().isNotEmpty ? ' — ${c['clinique']}' : ''}',
              date: fmtDate(c['date'] as String?),
              extra: proto.isNotEmpty ? proto : null,
            );
          },
        ),
        _HealthSection(
          title: 'Allergies',
          color: SanteCouleurs.allergies,
          icon: Icons.warning_amber_rounded,
          items: allergies,
          buildRow: (a) => _MedRow(
            label: a['description']?.toString() ?? a['allergene']?.toString() ?? '',
            sub: [a['type']?.toString(), a['severite']?.toString()]
                .where((s) => s != null && s.isNotEmpty).join(' · '),
            date: fmtDate(a['date'] as String?),
          ),
        ),
        _PoidsSection(poids: poids, fmtDate: fmtDate),
        _HealthSection(
          title: 'Visites vétérinaires',
          color: SanteCouleurs.visites,
          icon: Icons.local_hospital_outlined,
          items: visites,
          buildRow: (v) => _MedRow(
            label: v['motif']?.toString() ?? 'Consultation',
            sub: v['veterinaire']?.toString(),
            date: fmtDate(v['date'] as String?),
            extra: (v['diagnostic'] ?? '').toString().isNotEmpty ? v['diagnostic'].toString() : null,
          ),
        ),
      ]),
    ]);
  }
}

// ── Section poids collapsible ────────────────────────────────────────────────

class _PoidsSection extends StatefulWidget {
  final List<Map<String, dynamic>> poids;
  final String Function(String?) fmtDate;

  const _PoidsSection({required this.poids, required this.fmtDate});

  @override
  State<_PoidsSection> createState() => _PoidsSectionState();
}

class _PoidsSectionState extends State<_PoidsSection> {

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.poids]..sort((a, b) {
      final da = DateTime.tryParse(a['date']?.toString() ?? '') ?? DateTime(2000);
      final db = DateTime.tryParse(b['date']?.toString() ?? '') ?? DateTime(2000);
      return db.compareTo(da); // plus récent en premier
    });

    final dernier = sorted.isEmpty ? null : double.tryParse(sorted.first['valeur']?.toString() ?? '');
    return _HealthSection(
      title: 'Courbe de poids',
      color: SanteCouleurs.poids,
      items: widget.poids,
      resume: dernier == null ? null
          : '${widget.poids.length} pesée${widget.poids.length > 1 ? 's' : ''} · dernier : ${dernier.toStringAsFixed(dernier.truncateToDouble() == dernier ? 0 : 1)} kg',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final p in sorted.take(10)) () {
          final v = double.tryParse(p['valeur']?.toString() ?? '');
          if (v == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(widget.fmtDate(p['date'] as String?),
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13,
                        color: Color(0xFF6B7280))),
                Text('${v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1)} kg',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                        fontSize: 14, color: Color(0xFF1F2A2E))),
              ]),
              const SizedBox(height: 8),
              const Divider(height: 1, color: Color(0xFFF3F4F6)),
            ]),
          );
        }(),
        const SizedBox(height: 6),
      ]),
    );
  }
}

// ── Onglet Alimentation ───────────────────────────────────────────────────────

class _AlimentationTab extends StatelessWidget {
  final Map<String, dynamic>? alimentation;
  final Map<String, dynamic>? alimentationSejour;

  const _AlimentationTab({required this.alimentation, this.alimentationSejour});

  static const _teal = Color(0xFF0C5C6C);

  Map<String, dynamic> get _sejour => alimSejourFromRaw(alimentationSejour);

  Widget _sejourCard() {
    final s = _sejour;
    final rows = <(String, String)>[
      if ((s['fournis_par'] as String?)?.isNotEmpty ?? false)
        ('Prise en charge', alimSejourFournisParLabel(s['fournis_par'] as String?)),
      if ((s['foin'] as String?)?.isNotEmpty ?? false) ('Foin', s['foin'] as String),
      if ((s['granules'] as String?)?.isNotEmpty ?? false) ('Granulés / concentrés', s['granules'] as String),
      if ((s['complements'] as String?)?.isNotEmpty ?? false) ('Compléments', s['complements'] as String),
      if ((s['autres'] as String?)?.isNotEmpty ?? false) ('Autres', s['autres'] as String),
      if ((s['consignes'] as String?)?.isNotEmpty ?? false) ('Consignes', s['consignes'] as String),
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F5EC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE8D4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('🌾  Alimentation pour ce séjour (pension)',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1F2A2E))),
        const SizedBox(height: 8),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 130, child: Text(r.$1,
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600))),
              Expanded(child: Text(r.$2,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1F2A2E)))),
            ]),
          ),
      ]),
    );
  }

  static Widget _statChip(String label, String value) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
          color: const Color(0xFF0C5C6C).withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 10, color: Color(0xFF6F767B))),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontFamily: 'Galey', fontSize: 14,
            fontWeight: FontWeight.w700, color: Color(0xFF0C5C6C))),
      ]),
    ),
  );

  static String _rationLabel(String? t) {
    switch (t) {
      case 'croquettes': return 'Croquettes';
      case 'barf':       return 'BARF (viande crue)';
      case 'mixte':      return 'Mixte';
      case 'menagere':   return 'Ration ménagère';
      case 'paturage':   return 'Pâturage';
      case 'foin':       return 'Foin';
      case 'complement': return 'Complément';
      case 'granules':   return 'Granulés';
      default:           return t ?? '';
    }
  }

  static String _activiteLabel(String? a) {
    switch (a) {
      case 'repos':       return 'Repos / faible';
      case 'leger':       return 'Léger';
      case 'modere':      return 'Modéré';
      case 'actif':       return 'Actif';
      case 'tres_actif':  return 'Très actif';
      default:            return a ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSejour = _sejour.isNotEmpty;
    if (alimentation == null) {
      if (hasSejour) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
          children: [
            _sejourCard(),
            Text('Régime habituel non renseigné par le propriétaire.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500)),
          ],
        );
      }
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.restaurant_menu_outlined, size: 48, color: Color(0xFFCCCCCC)),
          SizedBox(height: 12),
          Text('Aucune information sur l\'alimentation',
              style: TextStyle(fontFamily: 'Galey', fontSize: 15, color: Colors.grey)),
        ]),
      );
    }

    final a = alimentation!;
    final ration      = a['type_ration']?.toString();
    final activite    = a['niveau_activite']?.toString();
    final marque      = a['marque']?.toString() ?? '';
    final gamme       = a['gamme']?.toString() ?? '';
    final reference   = a['reference_produit']?.toString() ?? '';
    final complements = a['complements']?.toString() ?? '';

    // Le champ "notes" encode l'état du calculateur :
    // [0]=pctFoin [1]=pctGran [2]=pctComp [3]=nb_repas [4]=separe
    // [5]=dose_manuelle_g [6]=dose2 [7]=typeMixte2 ...
    final notesRaw = a['notes']?.toString() ?? '';
    final notesParts = notesRaw.contains('|') ? notesRaw.split('|') : <String>[];

    // nb_repas : colonne dédiée OU position [3] dans notes
    final nbRepasRaw = a['nb_repas'];
    int nbRepas = nbRepasRaw is num ? nbRepasRaw.round()
        : int.tryParse(nbRepasRaw?.toString() ?? '') ?? 0;
    if (nbRepas == 0 && notesParts.length > 3) {
      nbRepas = int.tryParse(notesParts[3]) ?? 0;
    }

    // ration_grammes : colonne dédiée OU dose manuelle dans notes[5]
    final rationGRaw    = a['ration_grammes'];
    final rationKcalRaw = a['ration_kcal'];
    int totalG = rationGRaw != null
        ? (double.tryParse(rationGRaw.toString()) ?? 0).round() : 0;
    if (totalG == 0 && notesParts.length > 5) {
      totalG = (double.tryParse(notesParts[5]) ?? 0).round();
    }
    final totalKcal = rationKcalRaw != null
        ? (double.tryParse(rationKcalRaw.toString()) ?? 0).round() : 0;

    // Composant 2 pour ration mixte (chien/chat)
    // notes[0]=pctCroq, [4]=separe, [6]=dose2_g, [7]=typeMixte2
    final isMixte   = ration == 'mixte';
    final pctCroq   = notesParts.isNotEmpty ? (double.tryParse(notesParts[0]) ?? 0) : 0.0;
    final separe    = notesParts.length > 4 && notesParts[4] == '1';
    // 2e composant : ration enregistrée par le propriétaire, sinon dose manuelle (notes[6]).
    final dose2Stockee = (double.tryParse(a['ration2_grammes']?.toString() ?? '') ?? 0).round();
    final dose2     = dose2Stockee > 0 ? dose2Stockee
        : notesParts.length > 6 ? (double.tryParse(notesParts[6]) ?? 0).round() : 0;
    final typeMixte2 = (notesParts.length > 7 && notesParts[7].isNotEmpty) ? notesParts[7] : 'patee';
    final secondLabel = typeMixte2 == 'barf' ? 'BARF'
        : typeMixte2 == 'menagere' ? 'Ration ménagère' : 'Pâtée';
    final secondEmoji = typeMixte2 == 'barf' ? '🥩'
        : typeMixte2 == 'menagere' ? '🍲' : '🥫';

    // Labels repas identiques à la fiche éleveur
    const repasLabels = [
      ['Repas unique 🍽️'],
      ['Matin 🌅', 'Soir 🌇'],
      ['Matin 🌅', 'Midi ☀️', 'Soir 🌇'],
      ['Matin 🌅', 'Midi ☀️', 'Après-midi 🌤️', 'Soir 🌇'],
    ];
    const mealColors = [
      Color(0xFF0C5C6C), Color(0xFF6E9E57),
      Color(0xFFB8860B), Color(0xFF8D6E63),
    ];

    final produitLabel = [
      if (marque.isNotEmpty) marque,
      if (gamme.isNotEmpty) gamme,
    ].join(' — ');
    final rationEmoji = const {
      'croquettes': '🥜', 'barf': '🥩', 'mixte': '🥜',
      'menagere': '🍲', 'foin': '🌾', 'paturage': '🌿',
      'granules': '🌾', 'complement': '💊',
    }[ration ?? ''] ?? '🍽️';

    return ListView(padding: const EdgeInsets.fromLTRB(16, 20, 16, 40), children: [

      if (hasSejour) _sejourCard(),
      if (hasSejour)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('Régime habituel — renseigné par le propriétaire',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
        ),

      // ── Carte produit ─────────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(rationEmoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                produitLabel.isNotEmpty ? produitLabel : _rationLabel(ration),
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14,
                    fontWeight: FontWeight.w700, color: Color(0xFF1F2A2E)),
              ),
              if (produitLabel.isNotEmpty && ration != null && ration.isNotEmpty)
                Text(_rationLabel(ration),
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
            ])),
            if (activite != null && activite.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: _teal.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(_activiteLabel(activite),
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 11,
                        fontWeight: FontWeight.w600, color: _teal)),
              ),
          ]),
          if (reference.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Réf. $reference',
                style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
          ],
          const Divider(height: 18),
          // Totaux journaliers
          Row(children: [
            _statChip(
              isMixte ? '🥜 Croquettes/jour' : '📦 Quantité/jour',
              totalG > 0 ? '$totalG g' : 'Non renseigné',
            ),
            const SizedBox(width: 10),
            if (isMixte && dose2 > 0)
              _statChip('$secondEmoji $secondLabel/jour', '$dose2 g')
            else if (totalKcal > 0)
              _statChip('🔥 Énergie/jour', '$totalKcal kcal'),
          ]),
        ]),
      ),

      // ── Cartes repas (Matin / Midi / Soir) ───────────────────────────────
      const SizedBox(height: 16),
      Row(children: [
        const Text('Rations journalières',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                fontSize: 13, color: Color(0xFF1F2A2E))),
        const Spacer(),
        if (nbRepas > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: _teal.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
            child: Text('$nbRepas repas/jour',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 11,
                    fontWeight: FontWeight.w600, color: _teal)),
          ),
      ]),
      const SizedBox(height: 10),

      if (nbRepas > 0 && (totalG > 0 || (isMixte && dose2 > 0))) ...[
        ...List.generate(nbRepas.clamp(1, 4), (i) {
          final labels_ = repasLabels[(nbRepas.clamp(1, 4)) - 1];
          final label   = labels_[i];
          final color   = mealColors[i % 4];

          // Build items list for this meal
          final List<Map<String, String>> items;
          if (isMixte) {
            if (separe && nbRepas >= 2) {
              final nCroq = ((nbRepas * pctCroq / 100).round()).clamp(1, nbRepas - 1);
              if (i < nCroq) {
                final rcPar = totalG > 0 ? (totalG / nCroq).round() : 0;
                items = rcPar > 0
                    ? [{'emoji': rationEmoji, 'label': produitLabel.isNotEmpty ? produitLabel : 'Croquettes', 'qte': '$rcPar g'}]
                    : [];
              } else {
                final nSec = nbRepas - nCroq;
                final rsPar = dose2 > 0 ? (dose2 / nSec).round() : 0;
                items = rsPar > 0
                    ? [{'emoji': secondEmoji, 'label': secondLabel, 'qte': '$rsPar g'}]
                    : [];
              }
            } else {
              final rcPar = totalG > 0 ? (totalG / nbRepas).round() : 0;
              final rsPar = dose2 > 0 ? (dose2 / nbRepas).round() : 0;
              items = [
                if (rcPar > 0) {'emoji': rationEmoji, 'label': produitLabel.isNotEmpty ? produitLabel : 'Croquettes', 'qte': '$rcPar g'},
                if (rsPar > 0) {'emoji': secondEmoji, 'label': secondLabel, 'qte': '$rsPar g'},
              ];
            }
          } else {
            final qteG = (totalG / nbRepas).round();
            items = [{'emoji': rationEmoji, 'label': produitLabel.isNotEmpty ? produitLabel : _rationLabel(ration), 'qte': '$qteG g'}];
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade100),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Text(label, style: TextStyle(fontFamily: 'Galey',
                    fontSize: 13, fontWeight: FontWeight.w700, color: color)),
              ),
              ...items.map((item) => Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                child: Row(children: [
                  Text(item['emoji']!, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(item['label']!,
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1F2A2E)))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: _teal.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(item['qte']!,
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 13,
                            fontWeight: FontWeight.w700, color: _teal)),
                  ),
                ]),
              )),
              const SizedBox(height: 2),
            ]),
          );
        }),
      ] else ...[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200)),
          child: Row(children: [
            Icon(Icons.info_outline, size: 16, color: Colors.grey.shade400),
            const SizedBox(width: 8),
            Expanded(child: Text(
              nbRepas == 0
                  ? 'Nombre de repas non renseigné par le propriétaire'
                  : 'Quantité journalière non renseignée par le propriétaire',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500),
            )),
          ]),
        ),
      ],

      // ── Compléments ──────────────────────────────────────────────────────
      if (complements.isNotEmpty) ...[
        const SizedBox(height: 16),
        _Section(title: 'Compléments alimentaires', children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(complements,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 14, height: 1.5)),
          ),
        ]),
      ],
    ]);
  }
}

// ── Composants partagés ───────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE5E7EB)),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 6, offset: const Offset(0, 2))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: Text(title,
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                fontSize: 13, color: Color(0xFF6B7280), letterSpacing: 0.3)),
      ),
      const SizedBox(height: 8),
      ...children,
      const SizedBox(height: 8),
    ]),
  );
}

class _Row extends StatelessWidget {
  final String? label;
  final String? value;

  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 130,
              child: Text(label ?? '', style: const TextStyle(
                  fontFamily: 'Galey', fontSize: 13, color: Color(0xFF9CA3AF))),
            ),
            Expanded(child: Text(value!, style: const TextStyle(
                fontFamily: 'Galey', fontSize: 14, color: Color(0xFF1F2A2E),
                fontWeight: FontWeight.w600))),
          ]),
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
      ]),
    );
  }
}

/// Panneau blanc unique du carnet : lignes séparées par des traits gris fins.
class _PanneauSante extends StatelessWidget {
  final List<Widget> children;
  const _PanneauSante({required this.children});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade300),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
        children[i],
      ],
    ]),
  );
}

class _HealthSection extends StatefulWidget {
  final String title;
  final Color color;
  final IconData? icon;
  final List<Map<String, dynamic>> items;
  final Widget Function(Map<String, dynamic>)? buildRow;
  final VoidCallback? onAdd;
  final Widget? body;
  final String? resume;

  const _HealthSection({
    required this.title,
    required this.color,
    this.icon,
    required this.items,
    this.buildRow,
    this.onAdd,
    this.body,
    this.resume,
  });

  @override
  State<_HealthSection> createState() => _HealthSectionState();
}

class _HealthSectionState extends State<_HealthSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final n = widget.items.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(children: [
              Container(width: 12, height: 12,
                  decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(widget.title, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                    fontSize: 15, color: Color(0xFF1F2A2E))),
                const SizedBox(height: 2),
                Text(widget.resume ?? '$n enregistrement${n > 1 ? 's' : ''}',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade600)),
              ])),
              // Ajouter : ouvre le formulaire sans déplier la ligne
              if (widget.onAdd != null)
                TextButton(
                  onPressed: widget.onAdd,
                  style: TextButton.styleFrom(
                    foregroundColor: widget.color,
                    minimumSize: const Size(48, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('+ Ajouter',
                      style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13.5)),
                ),
              SizedBox(
                width: 40, height: 44,
                child: Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: Colors.grey.shade500, size: 22),
              ),
            ]),
          ),
        ),
      ),
      if (_expanded) ...[
        Divider(height: 1, thickness: 1, color: Colors.grey.shade100),
        if (widget.body != null && n > 0)
          widget.body!
        else if (n == 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(42, 12, 16, 14),
            child: Text('Aucun enregistrement',
                style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500)),
          )
        else ...[
          for (final item in widget.items) widget.buildRow!(item),
          const SizedBox(height: 10),
        ],
      ],
    ]);
  }
}

class _MedRow extends StatelessWidget {
  final String label;
  final String? sub;
  final String date;
  final String? extra;
  final VoidCallback? onRappel;

  const _MedRow({
    required this.label,
    required this.date,
    this.sub,
    this.extra,
    this.onRappel,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(label,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14,
                fontWeight: FontWeight.w600, color: Color(0xFF1F2A2E)))),
        Text(date,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF9CA3AF))),
        if (onRappel != null)
          IconButton(
            icon: const Icon(Icons.add_alarm_outlined, size: 16, color: Color(0xFF6E9E57)),
            tooltip: 'Renouvellement',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: onRappel,
          ),
      ]),
      if (sub != null && sub!.isNotEmpty)
        Text(sub!, style: const TextStyle(fontFamily: 'Galey', fontSize: 12,
            color: Color(0xFF6B7280))),
      if (extra != null)
        Text(extra!, style: const TextStyle(fontFamily: 'Galey', fontSize: 11,
            color: Color(0xFF6E9E57), fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      const Divider(height: 1, color: Color(0xFFF3F4F6)),
    ]),
  );
}
