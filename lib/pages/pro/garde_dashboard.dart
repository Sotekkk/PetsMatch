// Accueil pet-sitting / garde : tableau de bord de l'activité du jour.
// Uniquement des données réelles et des modules EXISTANTS : agenda (rdv),
// registre des visites + séjours (garde_sejour_helper), Ma tournée, gestion
// des clés (cles_clients), compte rendu express (visite_rapport_sheet).
// Mêmes briques que les tableaux véto / ostéo (widgets/dashboard/dashboard_kit.dart).
// Miroir site : website/src/components/dashboard/GardeDashboard.tsx.
//
// Heures réelles : rdv.arrivee_validee_le = début effectif, rdv.depart_valide_le
// = fin effective (colonnes existantes) ; rdv.date_heure (prévu) n'est jamais
// modifié.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/itineraire.dart';
import 'package:PetsMatch/pages/pro/pro_agenda.dart';
import 'package:PetsMatch/pages/pro/pro_clients_page.dart';
import 'package:PetsMatch/pages/pro/registre_visites_page.dart';
import 'package:PetsMatch/pages/pro/tournee_page.dart';
import 'package:PetsMatch/pages/pro/cles_clients_page.dart';
import 'package:PetsMatch/pages/pro/visite_rapport_sheet.dart';
import 'package:PetsMatch/pages/pro/garde_facture_helper.dart'
    show estGardeJournee, gardePrestationKey, gardeMotifLabel, familleGarde, kFamillesGarde;
import 'package:PetsMatch/pages/pro/garde_sejour_helper.dart';
import 'package:PetsMatch/widgets/dashboard/dashboard_kit.dart';

const _teal = kDashTeal;
const _ink = kDashInk;
const _muted = kDashMuted;
const _vert = Color(0xFF2E7D5E);
const _ambre = Color(0xFFD97706);
const _or = Color(0xFFB8860B);


class GardeDashboard extends StatefulWidget {
  const GardeDashboard({super.key});
  @override
  State<GardeDashboard> createState() => _GardeDashboardState();
}

class _GardeDashboardState extends State<GardeDashboard> {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _rdvs = [];
  /// Demandes de réservation à traiter (statut demande / contre-proposition).
  List<Map<String, dynamic>> _demandes = [];
  List<Map<String, dynamic>> _cles = [];
  final Map<String, String> _clients = {};
  final Map<String, Map<String, dynamic>> _animaux = {};
  final Map<String, String> _intervenants = {};
  Set<String> _avecCompteRendu = {};
  String _famille = 'tous';
  RealtimeChannel? _canal;
  final _planningKey = GlobalKey();

  String get _pid {
    final p = User_Info.activeProfileId;
    if (p.isNotEmpty) return p;
    for (final x in User_Info.availableProfiles) {
      if (x['is_main'] == true) return x['id']?.toString() ?? '';
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    _charger();
    final pid = _pid;
    if (pid.isNotEmpty) {
      _canal = _supa.channel('dash-garde-$pid')
        ..onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'rdv',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'pro_profile_id', value: pid),
            callback: (_) { if (mounted) _charger(); })
        ..subscribe();
    }
  }

  @override
  void dispose() {
    if (_canal != null) _supa.removeChannel(_canal!);
    super.dispose();
  }

  Future<void> _charger() async {
    final pid = _pid;
    if (pid.isEmpty) { setState(() => _loading = false); return; }
    final now = DateTime.now();
    final jour = DateTime(now.year, now.month, now.day);
    try {
      // 30 jours en arrière (séjours en cours, prestations à clôturer) et
      // 30 jours en avant (séjours à venir, clés encore utiles).
      final rows = await _supa.from('rdv').select()
          .eq('pro_profile_id', pid)
          .inFilter('statut', ['confirme', 'termine'])
          .gte('date_heure', jour.subtract(const Duration(days: 30)).toUtc().toIso8601String())
          .lte('date_heure', jour.add(const Duration(days: 31)).toUtc().toIso8601String())
          .order('date_heure');
      _rdvs = List<Map<String, dynamic>>.from((rows as List).map((e) => Map<String, dynamic>.from(e as Map)));
    } catch (_) {}
    try {
      final rows = await _supa.from('rdv').select()
          .eq('pro_profile_id', pid).inFilter('statut', ['demande', 'contre_proposition'])
          .order('created_at', ascending: false);
      final toutes = List<Map<String, dynamic>>.from((rows as List).map((e) => Map<String, dynamic>.from(e as Map)));
      // Série pet-sitting (rdv.serie_id) : une seule ligne, avec le nombre de passages.
      final parSerie = <String, int>{};
      for (final r in toutes) {
        final sid = r['serie_id']?.toString() ?? '';
        if (sid.isNotEmpty) parSerie[sid] = (parSerie[sid] ?? 0) + 1;
      }
      final vus = <String>{};
      _demandes = [
        for (final r in toutes)
          if ((r['serie_id']?.toString() ?? '').isEmpty) r
          else if (vus.add(r['serie_id'].toString())) {...r, '_nb_passages': parSerie[r['serie_id'].toString()]},
      ];
    } catch (_) { _demandes = []; }
    try {
      final rows = await _supa.from('cles_clients').select()
          .eq('pro_profile_id', pid).eq('statut', 'en_possession');
      _cles = List<Map<String, dynamic>>.from(rows as List);
    } catch (_) { _cles = []; }
    await _chargerNoms();
    // Comptes rendus déjà envoyés pour les prestations du jour (rdv_id).
    try {
      final ids = _duJour(jour).map((r) => r['id'].toString()).toList();
      if (ids.isNotEmpty) {
        final cr = await _supa.from('pension_updates').select('rdv_id').inFilter('rdv_id', ids);
        _avecCompteRendu = {for (final x in cr as List) if (x['rdv_id'] != null) x['rdv_id'].toString()};
      }
    } catch (_) { _avecCompteRendu = {}; } // migration_garde_compte_rendu_express.sql
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _chargerNoms() async {
    final profils = {for (final r in [..._rdvs, ..._demandes]) if (r['client_profile_id'] != null) r['client_profile_id'].toString()};
    final animaux = {
      for (final r in [..._rdvs, ..._demandes]) if (r['animal_id'] != null) r['animal_id'].toString(),
      for (final c in _cles) if (c['animal_id'] != null) c['animal_id'].toString(),
    };
    final intervenants = {for (final r in _rdvs) if (r['instructeur_profile_id'] != null) r['instructeur_profile_id'].toString()};
    try {
      final ids = {...profils, ...intervenants}.toList();
      if (ids.isNotEmpty) {
        final rows = await _supa.from('user_profiles_complet')
            .select('id, firstname, lastname, nom, profile_type').inFilter('id', ids);
        for (final p in rows as List) {
          final perso = '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
          final structure = (p['nom']?.toString() ?? '').trim();
          final nom = p['profile_type'] != 'particulier' && structure.isNotEmpty ? structure : (perso.isNotEmpty ? perso : structure);
          _clients[p['id'].toString()] = nom;
          if (intervenants.contains(p['id'].toString())) _intervenants[p['id'].toString()] = perso.isNotEmpty ? perso : nom;
        }
      }
    } catch (_) {}
    try {
      if (animaux.isNotEmpty) {
        final rows = await _supa.from('animaux').select('id, nom, espece, photo_url').inFilter('id', animaux.toList());
        for (final a in rows as List) { _animaux[a['id'].toString()] = Map<String, dynamic>.from(a as Map); }
      }
    } catch (_) {}
    for (final r in _rdvs) {
      r['_animal_nom'] = _nomAnimal(r);
      r['_client_nom'] = _nomClient(r);
    }
  }

  // ── Sélections ──────────────────────────────────────────────────────────

  DateTime _debut(Map<String, dynamic> r) => DateTime.tryParse(r['date_heure']?.toString() ?? '')?.toLocal() ?? DateTime(2000);
  DateTime _fin(Map<String, dynamic> r) => _debut(r).add(Duration(minutes: (r['duree_minutes'] as num?)?.toInt() ?? 30));
  DateTime? _reel(Map<String, dynamic> r, String k) => DateTime.tryParse(r[k]?.toString() ?? '')?.toLocal();
  bool _memeJour(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  bool _exterieur(Map<String, dynamic> r) =>
      ((r['lieu']?.toString().trim() ?? '').isNotEmpty && r['salle_id'] == null) || r['lieu_lat'] != null;

  List<Map<String, dynamic>> _duJour(DateTime j) =>
      _rdvs.where((r) => _memeJour(_debut(r), j)).toList()..sort((a, b) => _debut(a).compareTo(_debut(b)));

  List<GardeSejour> get _sejours => groupeGardeSejours(_rdvs);

  /// Séjours en cours aujourd'hui (non terminés, jour dans [entrée, sortie]).
  List<GardeSejour> _enGarde(DateTime jour) => _sejours.where((s) {
        if (s.statut == 'termine') return false;
        final e = DateTime(s.dateEntree.year, s.dateEntree.month, s.dateEntree.day);
        final f = DateTime(s.dateSortiePrevue.year, s.dateSortiePrevue.month, s.dateSortiePrevue.day);
        return s.statut == 'en_garde' || (!jour.isBefore(e) && !jour.isAfter(f));
      }).toList();
  List<GardeSejour> _entrees(DateTime jour) => _sejours.where((s) => _memeJour(s.dateEntree, jour)).toList();
  List<GardeSejour> _sorties(DateTime jour) =>
      _sejours.where((s) => _memeJour(s.dateSortiePrevue, jour) && s.statut != 'termine').toList();

  /// Clés à gérer : clé encore en ma possession alors que le client n'a plus
  /// de prestation confirmée à venir → à restituer (statuts existants seulement).
  List<Map<String, dynamic>> _clesARestituer(DateTime jour) => _cles.where((c) {
        final owner = c['owner_uid']?.toString();
        final animal = c['animal_id']?.toString();
        return !_rdvs.any((r) => r['statut'] == 'confirme' && !_debut(r).isBefore(jour) &&
            ((owner != null && r['client_uid']?.toString() == owner) || (animal != null && r['animal_id']?.toString() == animal)));
      }).toList();

  /// Prestations passées encore « confirmées » (pas marquées terminées).
  /// Les jours de garde-journée se clôturent par le départ (registre).
  List<Map<String, dynamic>> _aCloturer(DateTime now) => _rdvs.where((r) =>
      r['statut'] == 'confirme' && !estGardeJournee(r) && _fin(r).isBefore(now)).toList();

  Map<String, dynamic>? _cle(Map<String, dynamic> r) {
    for (final c in _cles) {
      if ((c['animal_id'] != null && c['animal_id'].toString() == r['animal_id']?.toString()) ||
          (c['owner_uid'] != null && c['owner_uid'].toString() == r['client_uid']?.toString())) { return c; }
    }
    return null;
  }

  String _nomClient(Map<String, dynamic> r) {
    final n = _clients[r['client_profile_id']?.toString() ?? ''];
    if (n != null && n.isNotEmpty) return n;
    final m = r['client_nom_manuel']?.toString() ?? '';
    return m.isNotEmpty ? m : 'Client';
  }

  String _nomAnimal(Map<String, dynamic> r) {
    final n = _animaux[r['animal_id']?.toString()]?['nom']?.toString() ?? '';
    if (n.isNotEmpty) return n;
    final m = r['animal_nom_manuel']?.toString() ?? '';
    return m.isNotEmpty ? m : 'Animal';
  }

  String _prestation(Map<String, dynamic> r) =>
      gardeMotifLabel(gardePrestationKey(r['motif']?.toString()) == 'autre'
          ? (r['motif']?.toString().trim().isNotEmpty == true ? r['motif'].toString().trim() : 'Prestation')
          : gardePrestationKey(r['motif']?.toString()),
          _animaux[r['animal_id']?.toString()]?['espece']?.toString());

  String _lieu(Map<String, dynamic> r) {
    if (estGardeJournee(r)) return 'Chez moi (garde)';
    final a = r['lieu']?.toString().trim() ?? '';
    return a.isNotEmpty ? a : 'Adresse non renseignée';
  }

  String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  String _jm(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  ({String label, Color fg, Color bg}) _statut(Map<String, dynamic> r, DateTime now) {
    if (r['statut'] == 'termine') return (label: 'Terminé', fg: const Color(0xFF4B5563), bg: const Color(0xFFF1F2F4));
    if (_reel(r, 'arrivee_validee_le') != null && _reel(r, 'depart_valide_le') == null && !estGardeJournee(r)) {
      return (label: 'En cours', fg: _teal, bg: const Color(0xFFE6F2F3));
    }
    if (_fin(r).isBefore(now) && !estGardeJournee(r)) return (label: 'À clôturer', fg: _ambre, bg: const Color(0xFFFFF4DC));
    return (label: 'À venir', fg: const Color(0xFF1D4ED8), bg: const Color(0xFFE8F0FE));
  }

  // ── Actions (modules existants) ─────────────────────────────────────────

  Future<void> _go(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) _charger();
  }

  Future<void> _maj(Map<String, dynamic> r, Map<String, dynamic> champs) async {
    try {
      await _supa.from('rdv').update(champs).eq('id', r['id']);
      r.addAll(champs);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  /// Début effectif (l'heure prévue du RDV ne change pas).
  Future<void> _commencer(Map<String, dynamic> r) =>
      _maj(r, {'arrivee_validee_le': DateTime.now().toUtc().toIso8601String()});

  /// Fin effective + RDV terminé, puis compte rendu express proposé.
  Future<void> _terminer(Map<String, dynamic> r) async {
    final maintenant = DateTime.now().toUtc().toIso8601String();
    // termine_at : heure réelle de fin déjà utilisée par l'agenda (retards).
    await _maj(r, {'depart_valide_le': maintenant, 'termine_at': maintenant, 'statut': 'termine'});
    if (!mounted || r['animal_id'] == null) return;
    final ok = await showVisiteRapportSheet(context, r);
    if (ok && mounted) setState(() => _avecCompteRendu.add(r['id'].toString()));
  }

  /// Fiche de la prestation : infos, consignes, clé, itinéraire, actions.
  Future<void> _fiche(Map<String, dynamic> r) async {
    final now = DateTime.now();
    final cle = _cle(r);
    final consignes = (r['notes_client']?.toString() ?? '').trim();
    final debutReel = _reel(r, 'arrivee_validee_le');
    final finReelle = _reel(r, 'depart_valide_le') ?? _reel(r, 'termine_at');
    final garde = estGardeJournee(r);
    final cleARestituer = cle != null && _clesARestituer(DateTime(now.year, now.month, now.day)).contains(cle);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              DashPhotoAnimal(url: _animaux[r['animal_id']?.toString()]?['photo_url']?.toString(), taille: 44),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_nomAnimal(r), style: const TextStyle(fontFamily: 'Galey', fontSize: 17, fontWeight: FontWeight.w700, color: _ink)),
                Text('${_prestation(r)} · ${_nomClient(r)}', style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted)),
              ])),
              DashBadge(_statut(r, now).label, fg: _statut(r, now).fg, bg: _statut(r, now).bg),
            ]),
            const SizedBox(height: 14),
            _ligneInfo(Icons.schedule, 'Prévu ${_jm(_debut(r))} à ${_hm(_debut(r))} · ${(r['duree_minutes'] as num?)?.toInt() ?? 30} min'),
            if (debutReel != null || finReelle != null)
              _ligneInfo(Icons.timer_outlined, [
                if (debutReel != null) 'Début réel ${_hm(debutReel)}',
                if (finReelle != null) 'fin réelle ${_hm(finReelle)}',
              ].join(' · ')),
            _ligneInfo(Icons.place_outlined, _lieu(r)),
            if (_intervenants[r['instructeur_profile_id']?.toString()] != null)
              _ligneInfo(Icons.person_outline, 'Intervenant : ${_intervenants[r['instructeur_profile_id'].toString()]}'),
            const SizedBox(height: 8),
            const Text('Consignes du propriétaire', style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700, color: _ink)),
            const SizedBox(height: 4),
            Text(consignes.isEmpty ? 'Aucune consigne saisie pour ce rendez-vous.' : consignes,
                style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: consignes.isEmpty ? _muted : _ink, height: 1.4)),
            if (!garde) ...[
              const SizedBox(height: 12),
              // Clé : statuts existants (en ma possession / à restituer) ; jamais de code ici.
              InkWell(
                onTap: () { Navigator.pop(ctx); _go(const ClesClientsPage()); },
                child: Row(children: [
                  Icon(Icons.vpn_key_outlined, size: 18, color: cle == null ? _muted : (cleARestituer ? _ambre : _or)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    cle == null ? 'Aucune clé enregistrée pour ce client'
                        : cleARestituer ? 'Clé à restituer — ${cle['description'] ?? ''}' : 'Clé en ma possession — ${cle['description'] ?? ''}',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: cle == null ? _muted : _ink))),
                  const Text('Gestion des clés', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: _teal)),
                ]),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (_exterieur(r))
                OutlinedButton.icon(
                  onPressed: () => ouvrirItineraire(context, lat: (r['lieu_lat'] as num?)?.toDouble(),
                      lng: (r['lieu_lng'] as num?)?.toDouble(), adresse: r['lieu']?.toString()),
                  icon: const Icon(Icons.directions_outlined, size: 18),
                  label: const Text('Itinéraire', style: TextStyle(fontFamily: 'Galey')),
                ),
              if (garde)
                OutlinedButton.icon(
                  onPressed: () { Navigator.pop(ctx); _go(const RegistreVisitesPage()); },
                  icon: const Icon(Icons.checklist_outlined, size: 18),
                  label: const Text('Arrivée / départ (registre)', style: TextStyle(fontFamily: 'Galey')),
                )
              else if (r['statut'] == 'confirme' && debutReel == null)
                ElevatedButton.icon(
                  onPressed: () { Navigator.pop(ctx); _commencer(r); },
                  style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Commencer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                ),
              if (!garde && r['statut'] == 'confirme')
                ElevatedButton.icon(
                  onPressed: () { Navigator.pop(ctx); _terminer(r); },
                  style: ElevatedButton.styleFrom(backgroundColor: _vert, foregroundColor: Colors.white),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Terminer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                ),
              if (r['animal_id'] != null && (r['statut'] == 'termine' || garde || debutReel != null))
                OutlinedButton.icon(
                  onPressed: () { Navigator.pop(ctx); sendGardeNews(context, r).then((_) => _charger()); },
                  icon: const Icon(Icons.chat_outlined, size: 18),
                  label: Text(garde ? 'Journal de garde' : 'Compte rendu', style: const TextStyle(fontFamily: 'Galey')),
                ),
              TextButton(
                onPressed: () { Navigator.pop(ctx); _go(ProAgendaPage(initialTabIndex: 1, focusRdvId: r['id']?.toString())); },
                child: const Text("Voir dans l'agenda", style: TextStyle(fontFamily: 'Galey', color: _teal)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _ligneInfo(IconData ic, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(ic, size: 16, color: _muted),
          const SizedBox(width: 8),
          Expanded(child: Text(t, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _ink))),
        ]),
      );

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator(color: _teal)));
    }
    final now = DateTime.now();
    final jour = DateTime(now.year, now.month, now.day);
    final duJour = _duJour(jour);
    final enGarde = _enGarde(jour);
    final entrees = _entrees(jour), sorties = _sorties(jour);
    final cles = _clesARestituer(jour);
    final aCloturer = _aCloturer(now);
    return LayoutBuilder(builder: (context, c) {
      final large = c.maxWidth >= 860;
      final planning = DashCarte(key: _planningKey, child: _planningSection(duJour, now));
      final colonne = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _demandesSection(),
        const SizedBox(height: 16),
        _tourneeSection(duJour, now),
        const SizedBox(height: 16),
        _quotidienSection(enGarde, entrees, sorties, cles, aCloturer),
      ]);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GridView.count(
          crossAxisCount: large ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12, mainAxisSpacing: 12,
          childAspectRatio: large ? 2.1 : 1.65,
          children: [
            DashKpi(valeur: duJour.length, label: 'Prestations du jour', icon: Icons.today_outlined,
                onTap: () {
                  final ctx = _planningKey.currentContext;
                  if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300));
                }),
            DashKpi(valeur: enGarde.length, label: 'Animaux en garde', icon: Icons.pets_outlined, teinte: _vert,
                onTap: () => _go(const ProClientsPage())),
            DashKpi(valeur: entrees.length + sorties.length, label: 'Entrées / sorties', icon: Icons.swap_horiz_rounded,
                teinte: const Color(0xFF7B5EA7), onTap: () => _go(const RegistreVisitesPage())),
            DashKpi(valeur: cles.length, label: 'Clés à gérer', icon: Icons.vpn_key_outlined, teinte: _or,
                onTap: () => _go(const ClesClientsPage())),
          ],
        ),
        const SizedBox(height: 16),
        if (large)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 2, child: planning),
            const SizedBox(width: 16),
            Expanded(child: colonne),
          ])
        else ...[
          planning,
          const SizedBox(height: 16),
          colonne,
        ],
        const SizedBox(height: 16),
        _accesRapides(),
      ]);
    });
  }

  Widget _choix(String t, bool actif, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(t, style: TextStyle(fontFamily: 'Galey', fontSize: 12.5,
              color: actif ? Colors.white : _ink, fontWeight: FontWeight.w600)),
          selected: actif, onSelected: (_) => onTap(),
          selectedColor: _teal, backgroundColor: const Color(0xFFF1F4F3),
          showCheckmark: false, side: BorderSide.none, visualDensity: VisualDensity.compact,
        ),
      );

  // Planning du jour ------------------------------------------------------

  Widget _planningSection(List<Map<String, dynamic>> duJour, DateTime now) {
    // Filtres : familles réellement présentes (prestations configurées).
    final presentes = [for (final f in kFamillesGarde) if (duJour.any((r) => familleGarde(r) == f.$1)) f];
    final liste = _famille == 'tous' ? duJour : duJour.where((r) => familleGarde(r) == _famille).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DashTitre('Planning du jour', icone: Icons.calendar_today_outlined,
          trailing: DashLien("Voir l'agenda complet", onTap: () => _go(const ProAgendaPage(initialTabIndex: 1)))),
      const SizedBox(height: 8),
      if (presentes.length > 1)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _choix('Toutes (${duJour.length})', _famille == 'tous', () => setState(() => _famille = 'tous')),
            for (final f in presentes)
              _choix('${f.$2} (${duJour.where((r) => familleGarde(r) == f.$1).length})', _famille == f.$1,
                  () => setState(() => _famille = f.$1)),
          ]),
        ),
      const SizedBox(height: 6),
      if (liste.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text("Aucune prestation aujourd'hui.", textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Galey', color: _muted)),
        )
      else
        for (final r in liste) _ligne(r, now),
    ]);
  }

  Widget _ligne(Map<String, dynamic> r, DateTime now) {
    final st = _statut(r, now);
    final duree = (r['duree_minutes'] as num?)?.toInt() ?? 30;
    final cle = estGardeJournee(r) ? null : _cle(r);
    final intervenant = _intervenants[r['instructeur_profile_id']?.toString()];
    final cr = _avecCompteRendu.contains(r['id'].toString());
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _fiche(r),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F1EF)))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 50,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_hm(_debut(r)), style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _ink)),
              Text(duree >= 24 * 60 ? 'journée' : '$duree min', style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: _muted)),
            ]),
          ),
          DashPhotoAnimal(url: _animaux[r['animal_id']?.toString()]?['photo_url']?.toString()),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_nomAnimal(r), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _ink)),
              Text('${_nomClient(r)} · ${_prestation(r)}', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _muted)),
              const SizedBox(height: 2),
              Row(children: [
                Icon(estGardeJournee(r) ? Icons.home_work_outlined : Icons.place_outlined, size: 13, color: _muted),
                const SizedBox(width: 3),
                Flexible(child: Text(_lieu(r), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: _muted))),
                if (cle != null) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.vpn_key_outlined, size: 13, color: _or),
                ],
              ]),
              if (intervenant != null)
                Text('Intervenant : $intervenant', style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: _muted)),
            ]),
          ),
          const SizedBox(width: 6),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            DashBadge(st.label, fg: st.fg, bg: st.bg),
            if (cr) ...[
              const SizedBox(height: 3),
              const Text('Compte rendu envoyé', style: TextStyle(fontFamily: 'Galey', fontSize: 10.5, color: _vert, fontWeight: FontWeight.w600)),
            ],
          ]),
        ]),
      ),
    );
  }

  // Demandes en attente (comme les tableaux véto / ostéo) -----------------

  Widget _demandesSection() {
    final d = _demandes;
    String quand(Map<String, dynamic> r) {
      final c = DateTime.tryParse(r['created_at']?.toString() ?? '')?.toLocal();
      if (c == null) return '';
      final now = DateTime.now();
      final j = DateTime(now.year, now.month, now.day).difference(DateTime(c.year, c.month, c.day)).inDays;
      return j == 0 ? "Aujourd'hui" : j == 1 ? 'Hier' : _jm(c);
    }
    return DashCarte(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DashTitre('Demandes en attente', icone: Icons.notifications_none, compteur: d.length,
          trailing: d.isEmpty ? null : DashLien('Voir toutes', onTap: () => _go(const ProAgendaPage(initialTabIndex: 0)))),
      const SizedBox(height: 6),
      if (d.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Aucune demande à traiter.', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted)))
      else
        for (final r in d.take(3))
          InkWell(
            onTap: () => _go(ProAgendaPage(initialTabIndex: 0, focusRdvId: r['id']?.toString())),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                DashPhotoAnimal(url: _animaux[r['animal_id']?.toString()]?['photo_url']?.toString(), taille: 32),
                const SizedBox(width: 9),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${_nomAnimal(r)} · ${_nomClient(r)}', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: _ink)),
                  Text('${_prestation(r)}${((r['_nb_passages'] as int?) ?? 1) > 1 ? ' · ${r['_nb_passages']} passages dès le' : ' · pour le'} ${_jm(_debut(r))} ${_hm(_debut(r))}${_exterieur(r) ? ' · ${_lieu(r)}' : ''}',
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: _muted)),
                ])),
                const SizedBox(width: 6),
                Text(quand(r), style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Color(0xFFDC2626), fontWeight: FontWeight.w600)),
                const Icon(Icons.chevron_right, size: 18, color: _muted),
              ]),
            ),
          ),
    ]));
  }

  // Ma tournée ------------------------------------------------------------

  Widget _tourneeSection(List<Map<String, dynamic>> duJour, DateTime now) {
    final ext = duJour.where((r) => _exterieur(r) && !estGardeJournee(r)).toList();
    final faites = ext.where((r) => r['statut'] == 'termine').length;
    final prochaine = ext.where((r) => r['statut'] == 'confirme').firstOrNull;
    return DashCarte(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const DashTitre('Ma tournée', icone: Icons.route_outlined),
      const SizedBox(height: 8),
      Text(ext.isEmpty
              ? "Aucune intervention à l'extérieur aujourd'hui."
              : '${ext.length} intervention${ext.length > 1 ? 's' : ''} · $faites terminée${faites > 1 ? 's' : ''} · ${ext.length - faites} restante${ext.length - faites > 1 ? 's' : ''}',
          style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _ink)),
      if (prochaine != null) ...[
        const SizedBox(height: 4),
        Text('Prochaine : ${_hm(_debut(prochaine))} · ${_nomAnimal(prochaine)} · ${_lieu(prochaine)}',
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: _muted)),
      ],
      const SizedBox(height: 10),
      // Ouvre la tournée existante — ne marque rien comme commencé.
      ElevatedButton.icon(
        onPressed: () => _go(const TourneePage()),
        icon: const Icon(Icons.play_arrow_rounded, size: 20),
        label: const Text('Démarrer ma tournée', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    ]));
  }

  // Gestion quotidienne ---------------------------------------------------

  Widget _quotidienSection(List<GardeSejour> enGarde, List<GardeSejour> entrees, List<GardeSejour> sorties,
      List<Map<String, dynamic>> cles, List<Map<String, dynamic>> aCloturer) {
    Widget sousTitre(String t, int n, VoidCallback onVoir) => Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Row(children: [
            Expanded(child: Text('$t ($n)', style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700, color: _ink))),
            DashLien('Voir', onTap: onVoir),
          ]),
        );
    Widget item(String t, {Color couleur = _muted, VoidCallback? onTap}) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: couleur)),
          ),
        );
    final rien = enGarde.isEmpty && entrees.isEmpty && sorties.isEmpty && cles.isEmpty && aCloturer.isEmpty;
    return DashCarte(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const DashTitre('Gestion quotidienne', icone: Icons.fact_check_outlined),
      if (rien)
        const Padding(padding: EdgeInsets.only(top: 10),
            child: Text('Rien à signaler aujourd\'hui.', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted))),
      if (aCloturer.isNotEmpty) ...[
        sousTitre('Prestations à clôturer', aCloturer.length, () => _go(const ProAgendaPage(initialTabIndex: 1))),
        for (final r in aCloturer.take(4))
          item('${_jm(_debut(r))} ${_hm(_debut(r))} · ${_nomAnimal(r)} · ${_prestation(r)}', couleur: _ambre, onTap: () => _fiche(r)),
      ],
      if (entrees.isNotEmpty || sorties.isNotEmpty) ...[
        sousTitre('Entrées / sorties du jour', entrees.length + sorties.length, () => _go(const RegistreVisitesPage())),
        for (final s in entrees) item('Arrivée · ${s.animalNom} (${s.clientNom})${s.arriveeValideeLe != null ? ' — validée' : ''}'),
        for (final s in sorties) item('Départ · ${s.animalNom} (${s.clientNom})'),
      ],
      if (enGarde.isNotEmpty) ...[
        sousTitre('Animaux en garde', enGarde.length, () => _go(const ProClientsPage())),
        item(enGarde.map((s) => s.animalNom).join(', '), couleur: _ink),
      ],
      if (cles.isNotEmpty) ...[
        sousTitre('Clés à restituer', cles.length, () => _go(const ClesClientsPage())),
        for (final c in cles.take(4))
          item('${c['description'] ?? 'Clé'}${_animaux[c['animal_id']?.toString()] != null ? ' · ${_animaux[c['animal_id'].toString()]!['nom']}' : ''}',
              couleur: _ink),
      ],
    ]));
  }

  // Accès rapides -----------------------------------------------------------

  Widget _accesRapides() {
    Widget tuile(IconData ic, String t, VoidCallback onTap) => Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: kDashBorder)),
              child: Row(children: [
                Icon(ic, size: 19, color: _teal),
                const SizedBox(width: 8),
                Expanded(child: Text(t, maxLines: 2, style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5,
                    fontWeight: FontWeight.w600, color: _ink))),
              ]),
            ),
          ),
        );
    return DashCarte(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const DashTitre('Accès rapides', icone: Icons.bolt_outlined),
      const SizedBox(height: 10),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 560 ? 4 : 2;
        return GridView.count(
          crossAxisCount: cols, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: cols == 4 ? 3.0 : 2.9,
          children: [
            tuile(Icons.add_circle_outline, 'Nouveau RDV', () => _go(const ProAgendaPage(initialTabIndex: 1, nouveauRdv: true))),
            tuile(Icons.route_outlined, 'Ma tournée', () => _go(const TourneePage())),
            tuile(Icons.checklist_outlined, 'Registre', () => _go(const RegistreVisitesPage())),
            tuile(Icons.vpn_key_outlined, 'Gestion des clés', () => _go(const ClesClientsPage())),
          ],
        );
      }),
    ]));
  }
}
