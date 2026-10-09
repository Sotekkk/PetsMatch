// Accueil vétérinaire : tableau de bord de gestion de la clinique.
// Uniquement des données réelles (rdv, comptes_rendus, praticiens) ; chaque
// indicateur / ligne ouvre le module existant (agenda, Mes patients, compte
// rendu) — aucun module médical parallèle. Miroir site :
// website/src/components/dashboard/VetDashboard.tsx.

import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/pro/compte_rendu_page.dart';
import 'package:PetsMatch/pages/pro/pro_agenda.dart';
import 'package:PetsMatch/pages/pro/vet_patients_page.dart';
import 'package:PetsMatch/utils/retards_rdv.dart';
import 'package:PetsMatch/widgets/dashboard/dashboard_kit.dart';

const _teal = Color(0xFF0C5C6C);
const _ink = Color(0xFF1E2025);
const _muted = Color(0xFF6B7280);
const _border = Color(0xFFE4E7E2);

/// Motifs de réservation (≠ actes réalisés, qui vivent dans les comptes
/// rendus). Couleurs : palette catégorielle validée daltonisme, ordre fixe.
const vetMotifs = <({String key, String label, Color color})>[
  (key: 'consultation', label: 'Consultation', color: Color(0xFF2A78D6)),
  (key: 'vaccination', label: 'Vaccination', color: Color(0xFFEB6834)),
  (key: 'bilan', label: 'Bilan annuel', color: Color(0xFF1BAF7A)),
  (key: 'urgence', label: 'Urgence', color: Color(0xFFEDA100)),
  (key: 'chirurgie', label: 'Chirurgie', color: Color(0xFFE87BA4)),
  (key: 'autre', label: 'Autre', color: Color(0xFF008300)),
];

/// Classe le motif saisi à la réservation (texte libre ou prestation).
String categorieMotif(String? motif) {
  final m = (motif ?? '').toLowerCase();
  if (m.contains('urgen')) return 'urgence';
  if (m.contains('vaccin') || m.contains('rappel')) return 'vaccination';
  if (m.contains('bilan') || m.contains('annuel') || m.contains('check')) return 'bilan';
  if (m.contains('chirurg') || m.contains('opérat') || m.contains('operat') ||
      m.contains('stérilis') || m.contains('sterilis') || m.contains('castra')) { return 'chirurgie'; }
  if (m.contains('consult') || m.isEmpty) return 'consultation';
  return 'autre';
}

/// Statut affiché d'un RDV (« en cours » / « à clôturer » sont calculés).
({String label, Color fg, Color bg}) statutRdvVet(Map<String, dynamic> r, DateTime now) {
  final s = r['statut']?.toString() ?? '';
  final debut = DateTime.tryParse(r['date_heure']?.toString() ?? '')?.toLocal() ?? now;
  final fin = debut.add(Duration(minutes: (r['duree_minutes'] as num?)?.toInt() ?? 30));
  switch (s) {
    case 'demande':
    case 'contre_proposition':
      return (label: 'En attente', fg: const Color(0xFF8A5A00), bg: const Color(0xFFFFF4DC));
    case 'termine':
      return (label: 'Terminé', fg: const Color(0xFF4B5563), bg: const Color(0xFFF1F2F4));
    case 'annule':
    case 'refuse':
      return (label: 'Annulé', fg: const Color(0xFF9CA3AF), bg: const Color(0xFFF7F7F8));
    case 'confirme':
      if (!now.isBefore(debut) && now.isBefore(fin)) {
        return (label: 'En cours', fg: const Color(0xFF1D4ED8), bg: const Color(0xFFE8F0FE));
      }
      if (!now.isBefore(fin)) {
        return (label: 'À clôturer', fg: const Color(0xFFB45309), bg: const Color(0xFFFFEDD5));
      }
      return (label: 'Confirmé', fg: _teal, bg: const Color(0xFFE6F2F3));
  }
  return (label: s, fg: _muted, bg: const Color(0xFFF1F2F4));
}

class VetDashboard extends StatefulWidget {
  /// Même règle que la liste « Mes patients » (calculée par l'accueil).
  final int patientsCount;
  /// Accès rapides existants (ordonnance, vaccin, puce…), affichés en bas.
  final Widget raccourcis;
  const VetDashboard({super.key, required this.patientsCount, required this.raccourcis});

  @override
  State<VetDashboard> createState() => _VetDashboardState();
}

class _VetDashboardState extends State<VetDashboard> {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _rdvs = [];
  List<Map<String, dynamic>> _crBrouillons = [];
  List<({String id, String nom})> _praticiens = [];
  final Map<String, String> _clients = {};
  final Map<String, Map<String, dynamic>> _animaux = {};
  String _filtrePlanning = '*'; // '*' = toute la clinique, '' = titulaire
  String _periode = 'mois';     // semaine | mois | annee
  String _filtreStats = '*';

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
  }

  Future<void> _charger() async {
    final pid = _pid;
    if (pid.isEmpty) { setState(() => _loading = false); return; }
    final now = DateTime.now();
    final debutAnnee = DateTime(now.year, 1, 1);
    // Début de semaine (lundi) si l'année vient de commencer.
    final lundi = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final depuis = lundi.isBefore(debutAnnee) ? lundi : debutAnnee;
    try {
      final res = await Future.wait<dynamic>([
        _supa.from('rdv')
            .select('id, date_heure, duree_minutes, statut, motif, animal_id, client_uid, client_profile_id, '
                'client_nom_manuel, animal_nom_manuel, instructeur_profile_id, praticien_indifferent, termine_at')
            .eq('pro_profile_id', pid)
            .or('date_heure.gte.${depuis.toUtc().toIso8601String()},statut.in.(demande,contre_proposition,confirme)')
            .order('date_heure'),
        _supa.from('comptes_rendus').select('id, animal_id, created_at, motif')
            .eq('pro_profile_id', pid).eq('statut', 'brouillon')
            .order('created_at', ascending: false).limit(20),
        _supa.rpc('pm_praticiens_clinique', params: {'p_pro_profile_id': pid}),
      ].map((f) => (f as Future).catchError((_) => <dynamic>[])));
      _rdvs = List<Map<String, dynamic>>.from((res[0] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      _crBrouillons = List<Map<String, dynamic>>.from((res[1] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      _praticiens = [
        for (final p in res[2] as List)
          (id: p['praticien_profile_id']?.toString() ?? '',
           nom: (p['nom'] as String?)?.trim().isNotEmpty == true ? p['nom'] as String : 'Vétérinaire'),
      ];
      await _chargerNoms();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _chargerNoms() async {
    final now = DateTime.now();
    // Noms utiles : planning du jour + actions (pas toute l'année).
    final utiles = [..._planningJour(now, '*'), ..._demandes, ..._aCloturer(now)];
    final profils = {for (final r in utiles) if (r['client_profile_id'] != null) r['client_profile_id'].toString()};
    final animaux = {
      for (final r in utiles) if (r['animal_id'] != null) r['animal_id'].toString(),
      for (final c in _crBrouillons) if (c['animal_id'] != null) c['animal_id'].toString(),
    };
    try {
      if (profils.isNotEmpty) {
        final rows = await _supa.from('user_profiles_complet')
            .select('id, firstname, lastname, nom').inFilter('id', profils.toList());
        for (final p in rows as List) {
          final n = '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
          _clients[p['id'].toString()] = n.isNotEmpty ? n : (p['nom']?.toString() ?? '');
        }
      }
    } catch (_) {}
    try {
      if (animaux.isNotEmpty) {
        final rows = await _supa.from('animaux').select('id, nom, espece, photo_url').inFilter('id', animaux.toList());
        for (final a in rows as List) {
          _animaux[a['id'].toString()] = Map<String, dynamic>.from(a as Map);
        }
      }
    } catch (_) {}
  }

  // ── Sélections ──────────────────────────────────────────────────────────

  DateTime _debut(Map<String, dynamic> r) =>
      DateTime.tryParse(r['date_heure']?.toString() ?? '')?.toLocal() ?? DateTime(2000);
  DateTime _fin(Map<String, dynamic> r) =>
      _debut(r).add(Duration(minutes: (r['duree_minutes'] as num?)?.toInt() ?? 30));
  String _praticienDe(Map<String, dynamic> r) => r['instructeur_profile_id']?.toString() ?? '';

  bool _memeJour(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  List<Map<String, dynamic>> _planningJour(DateTime now, String filtre) => _rdvs.where((r) {
        if (!_memeJour(_debut(r), now)) return false;
        // « Peu importe » encore en demande : visible chez tous les praticiens.
        if (filtre != '*' && _praticienDe(r) != filtre &&
            !(r['praticien_indifferent'] == true && r['statut'] == 'demande')) { return false; }
        return true;
      }).toList();

  List<Map<String, dynamic>> get _demandes =>
      _rdvs.where((r) => r['statut'] == 'demande' || r['statut'] == 'contre_proposition').toList();

  List<Map<String, dynamic>> _aCloturer(DateTime now) =>
      _rdvs.where((r) => r['statut'] == 'confirme' && !_fin(r).isAfter(now)).toList()
        ..sort((a, b) => _debut(b).compareTo(_debut(a)));

  int _rdvAujourdhui(DateTime now) => _planningJour(now, '*')
      .where((r) => ['confirme', 'termine', 'demande', 'contre_proposition'].contains(r['statut'])).length;

  String _nomClient(Map<String, dynamic> r) {
    final p = r['client_profile_id']?.toString();
    final n = p != null ? _clients[p] : null;
    if (n != null && n.isNotEmpty) return n;
    final m = r['client_nom_manuel']?.toString() ?? '';
    return m.isNotEmpty ? m : 'Client';
  }

  String _nomAnimal(Map<String, dynamic> r) {
    final a = _animaux[r['animal_id']?.toString()];
    final n = a?['nom']?.toString() ?? '';
    if (n.isNotEmpty) return n;
    final m = r['animal_nom_manuel']?.toString() ?? '';
    return m.isNotEmpty ? m : 'Animal non précisé';
  }

  String _nomPraticien(String id) =>
      _praticiens.where((p) => p.id == id).map((p) => p.nom).firstOrNull ?? 'Vétérinaire';

  String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  String _jm(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  // ── Navigation vers les modules existants ───────────────────────────────

  Future<void> _go(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) _charger();
  }

  void _ouvrirRdv(Map<String, dynamic> r) {
    final s = r['statut'];
    final onglet = (s == 'demande' || s == 'contre_proposition') ? 0 : (s == 'confirme' ? 1 : 2);
    _go(ProAgendaPage(initialTabIndex: onglet, focusRdvId: r['id']?.toString()));
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator(color: _teal)));
    }
    final now = DateTime.now();
    final retards = retardsEnCascade(_rdvs, maintenant: now);
    final enRetard = retards.values.where((m) => m > 0).fold<int>(0, math.max);
    final aCloturer = _aCloturer(now);
    return LayoutBuilder(builder: (context, c) {
      final large = c.maxWidth >= 860;
      final planning = _carte(_planningSection(now, retards));
      final actions = _actionsSection(now, aCloturer);
      final stats = _statsSection(now);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (enRetard > 0 || _demandes.isNotEmpty) ...[
          _alertes(enRetard),
          const SizedBox(height: 12),
        ],
        _kpis(now, aCloturer.length, large),
        const SizedBox(height: 16),
        if (large)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 2, child: planning),
            if (actions != null) ...[const SizedBox(width: 16), Expanded(child: actions)],
          ])
        else ...[
          planning,
          if (actions != null) ...[const SizedBox(height: 16), actions],
        ],
        const SizedBox(height: 16),
        stats,
        const SizedBox(height: 20),
        _titre('Accès rapides'),
        const SizedBox(height: 10),
        widget.raccourcis,
      ]);
    });
  }

  Widget _carte(Widget child, {EdgeInsets padding = const EdgeInsets.all(16)}) => Container(
        padding: padding,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border)),
        child: child,
      );

  Widget _titre(String t, {Widget? trailing}) => Row(children: [
        Expanded(child: Text(t, style: const TextStyle(fontFamily: 'Galey', fontSize: 16,
            fontWeight: FontWeight.w700, color: _ink))),
        if (trailing != null) trailing,
      ]);

  Widget _alertes(int retardMax) => Wrap(spacing: 8, runSpacing: 8, children: [
        if (retardMax > 0)
          _pastille(Icons.schedule, 'Retard estimé : +$retardMax min', const Color(0xFFB45309),
              const Color(0xFFFFEDD5), () => _go(const ProAgendaPage(initialTabIndex: 1))),
        if (_demandes.isNotEmpty)
          _pastille(Icons.notifications_active_outlined,
              '${_demandes.length} demande${_demandes.length > 1 ? 's' : ''} à confirmer',
              const Color(0xFF8A5A00), const Color(0xFFFFF4DC), () => _go(const ProAgendaPage(initialTabIndex: 0))),
      ]);

  Widget _pastille(IconData ic, String t, Color fg, Color bg, VoidCallback onTap) => Material(
        color: bg, borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20), onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(ic, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(t, style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
            ]),
          ),
        ),
      );

  Widget _kpis(DateTime now, int nbACloturer, bool large) {
    final cartes = [
      DashKpi(valeur: _rdvAujourdhui(now), label: "RDV aujourd'hui", icon: Icons.today_outlined,
          onTap: () => _go(const ProAgendaPage(initialTabIndex: 1))),
      DashKpi(valeur: _demandes.length, label: 'Demandes à confirmer', icon: Icons.mark_email_unread_outlined,
          onTap: () => _go(const ProAgendaPage(initialTabIndex: 0))),
      DashKpi(valeur: nbACloturer, label: 'Consultations à clôturer', icon: Icons.assignment_late_outlined,
          onTap: () => _go(const ProAgendaPage(initialTabIndex: 1))),
      DashKpi(valeur: widget.patientsCount, label: 'Patients suivis', icon: Icons.favorite_outline,
          onTap: () => _go(const VetPatientsPage())),
    ];
    return GridView.count(
      crossAxisCount: large ? 4 : 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12, mainAxisSpacing: 12,
      childAspectRatio: large ? 2.1 : 1.65,
      children: cartes,
    );
  }

  // Planning du jour ------------------------------------------------------

  Widget _planningSection(DateTime now, Map<String, int> retards) {
    final rdvs = _planningJour(now, _filtrePlanning)..sort((a, b) => _debut(a).compareTo(_debut(b)));
    final plusieurs = _praticiens.length > 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titre('Planning du jour', trailing: TextButton(
        onPressed: () => _go(const ProAgendaPage(initialTabIndex: 1)),
        child: const Text("Voir l'agenda complet", style: TextStyle(fontFamily: 'Galey', color: _teal,
            fontWeight: FontWeight.w700, fontSize: 13)),
      )),
      if (plusieurs) ...[
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _choix('Toute la clinique', _filtrePlanning == '*', () => setState(() => _filtrePlanning = '*')),
            for (final p in _praticiens)
              _choix(p.nom, _filtrePlanning == p.id, () => setState(() => _filtrePlanning = p.id)),
          ]),
        ),
      ],
      const SizedBox(height: 8),
      if (rdvs.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text("Aucun rendez-vous aujourd'hui.", textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Galey', color: _muted)),
        )
      else
        for (final r in rdvs) _ligneRdv(r, now, retards[r['id']?.toString()], plusieurs),
    ]);
  }

  Widget _choix(String t, bool actif, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(t, style: TextStyle(fontFamily: 'Galey', fontSize: 12.5,
              color: actif ? Colors.white : _ink, fontWeight: FontWeight.w600)),
          selected: actif, onSelected: (_) => onTap(),
          selectedColor: _teal, backgroundColor: const Color(0xFFF1F4F3),
          showCheckmark: false, side: BorderSide.none,
          visualDensity: VisualDensity.compact,
        ),
      );

  Widget _photo(Map<String, dynamic> r, {double taille = 38}) {
    final url = _animaux[r['animal_id']?.toString()]?['photo_url']?.toString() ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(taille / 2),
      child: Container(
        width: taille, height: taille, color: const Color(0xFFE6F2F3),
        child: url.isNotEmpty
            ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const Icon(Icons.pets, size: 18, color: _teal))
            : const Icon(Icons.pets, size: 18, color: _teal),
      ),
    );
  }

  Widget _ligneRdv(Map<String, dynamic> r, DateTime now, int? retard, bool afficherPraticien) {
    final st = statutRdvVet(r, now);
    final annule = st.label == 'Annulé';
    final duree = (r['duree_minutes'] as num?)?.toInt() ?? 30;
    final motif = (r['motif']?.toString() ?? '').trim();
    final sousTitre = [
      _nomClient(r),
      if (motif.isNotEmpty) motif,
      if (afficherPraticien)
        r['praticien_indifferent'] == true && r['statut'] == 'demande' ? 'Peu importe' : _nomPraticien(_praticienDe(r)),
    ].join(' · ');
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _ouvrirRdv(r),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F1EF)))),
        child: Row(children: [
          SizedBox(
            width: 50,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_hm(_debut(r)), style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14,
                  color: annule ? _muted : _ink, decoration: annule ? TextDecoration.lineThrough : null)),
              Text('$duree min', style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: _muted)),
            ]),
          ),
          _photo(r),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_nomAnimal(r), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14,
                      color: annule ? _muted : _ink)),
              Text(sousTitre, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _muted)),
            ]),
          ),
          const SizedBox(width: 6),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            _badge(st.label, st.fg, st.bg),
            if (retard != null && retard > 0) ...[
              const SizedBox(height: 3),
              Text('+$retard min', style: const TextStyle(fontFamily: 'Galey', fontSize: 11,
                  fontWeight: FontWeight.w700, color: Color(0xFFB45309))),
            ],
          ]),
        ]),
      ),
    );
  }

  Widget _badge(String t, Color fg, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(t, style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
      );

  // Actions ---------------------------------------------------------------

  /// null si rien à faire (aucune section vide).
  Widget? _actionsSection(DateTime now, List<Map<String, dynamic>> aCloturer) {
    final demandes = _demandes..sort((a, b) => _debut(a).compareTo(_debut(b)));
    if (demandes.isEmpty && aCloturer.isEmpty && _crBrouillons.isEmpty) return null;
    Widget groupe(String titre, int total, List<Widget> lignes, VoidCallback voirTout) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(child: Text('$titre ($total)', style: const TextStyle(fontFamily: 'Galey',
                  fontWeight: FontWeight.w700, fontSize: 13.5, color: _ink))),
              if (total > lignes.length)
                GestureDetector(onTap: voirTout, child: const Text('Tout voir', style: TextStyle(
                    fontFamily: 'Galey', fontSize: 12, color: _teal, fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 4),
            ...lignes,
            const SizedBox(height: 12),
          ],
        );
    Widget ligne(Map<String, dynamic> r, String detail, VoidCallback onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              _photo(r, taille: 30),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_nomAnimal(r), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: _ink)),
                Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: _muted)),
              ])),
              const Icon(Icons.chevron_right, size: 18, color: _muted),
            ]),
          ),
        );
    return _carte(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titre('Actions'),
      const SizedBox(height: 10),
      if (demandes.isNotEmpty)
        groupe('Demandes en attente', demandes.length, [
          for (final r in demandes.take(4))
            ligne(r, '${_jm(_debut(r))} ${_hm(_debut(r))} · ${_nomClient(r)}', () => _ouvrirRdv(r)),
        ], () => _go(const ProAgendaPage(initialTabIndex: 0))),
      if (aCloturer.isNotEmpty)
        groupe('Consultations à clôturer', aCloturer.length, [
          for (final r in aCloturer.take(4))
            ligne(r, '${_jm(_debut(r))} ${_hm(_debut(r))} · ${(r['motif'] ?? 'Consultation')}', () => _ouvrirRdv(r)),
        ], () => _go(const ProAgendaPage(initialTabIndex: 1))),
      if (_crBrouillons.isNotEmpty)
        groupe('Comptes rendus à valider', _crBrouillons.length, [
          for (final c in _crBrouillons.take(4))
            ligne(c, 'Brouillon du ${_jm(DateTime.tryParse(c['created_at']?.toString() ?? '')?.toLocal() ?? now)}'
                '${(c['motif']?.toString() ?? '').isNotEmpty ? ' · ${c['motif']}' : ''}',
                () => _go(CompteRenduPage(animalId: c['animal_id']?.toString(), categoryColor: _teal))),
        ], () => _go(const VetPatientsPage())),
    ]));
  }

  // Statistiques ------------------------------------------------------------

  ({DateTime debut, DateTime fin}) _bornes(DateTime now) {
    final jour = DateTime(now.year, now.month, now.day);
    switch (_periode) {
      case 'semaine':
        final lundi = jour.subtract(Duration(days: now.weekday - 1));
        return (debut: lundi, fin: lundi.add(const Duration(days: 7)));
      case 'annee':
        return (debut: DateTime(now.year, 1, 1), fin: DateTime(now.year + 1, 1, 1));
      default:
        return (debut: DateTime(now.year, now.month, 1), fin: DateTime(now.year, now.month + 1, 1));
    }
  }

  /// RDV réels : confirmés ou terminés (ni demandes, ni annulés).
  bool _compte(Map<String, dynamic> r) =>
      (r['statut'] == 'confirme' || r['statut'] == 'termine') &&
      (_filtreStats == '*' || _praticienDe(r) == _filtreStats);

  Widget _statsSection(DateTime now) {
    final b = _bornes(now);
    final periode = _rdvs.where((r) => _compte(r) && !_debut(r).isBefore(b.debut) && _debut(r).isBefore(b.fin));
    final parMotif = <String, int>{for (final m in vetMotifs) m.key: 0};
    for (final r in periode) {
      final k = categorieMotif(r['motif']?.toString());
      parMotif[k] = (parMotif[k] ?? 0) + 1;
    }
    final total = parMotif.values.fold<int>(0, (a, v) => a + v);

    final lundi = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final parJour = List<int>.filled(7, 0);
    for (final r in _rdvs.where(_compte)) {
      final d = _debut(r);
      final i = DateTime(d.year, d.month, d.day).difference(lundi).inDays;
      if (i >= 0 && i < 7) parJour[i]++;
    }

    final filtres = Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'semaine', label: Text('Semaine')),
          ButtonSegment(value: 'mois', label: Text('Mois')),
          ButtonSegment(value: 'annee', label: Text('Année')),
        ],
        selected: {_periode},
        showSelectedIcon: false,
        onSelectionChanged: (s) => setState(() => _periode = s.first),
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w600)),
          backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? _teal : Colors.white),
          foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : _ink),
        ),
      ),
      if (_praticiens.length > 1)
        DropdownButton<String>(
          value: _filtreStats,
          underline: const SizedBox.shrink(),
          style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _ink),
          items: [
            const DropdownMenuItem(value: '*', child: Text('Toute la clinique')),
            for (final p in _praticiens) DropdownMenuItem(value: p.id, child: Text(p.nom)),
          ],
          onChanged: (v) => setState(() => _filtreStats = v ?? '*'),
        ),
    ]);

    return _carte(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titre('Répartition des rendez-vous'),
      const SizedBox(height: 2),
      const Text('Par motif de réservation · RDV confirmés et terminés',
          style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: _muted)),
      const SizedBox(height: 10),
      filtres,
      const SizedBox(height: 14),
      if (total == 0)
        const Padding(padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('Aucun rendez-vous sur la période.', textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Galey', color: _muted)))
      else
        DashDonut(segments: [for (final m in vetMotifs) (key: m.key, label: m.label, color: m.color, n: parMotif[m.key] ?? 0)]),
      const SizedBox(height: 18),
      const Divider(height: 1, color: Color(0xFFF0F1EF)),
      const SizedBox(height: 14),
      const Text('Activité de la semaine', style: TextStyle(fontFamily: 'Galey', fontSize: 14,
          fontWeight: FontWeight.w700, color: _ink)),
      const Text('RDV par jour', style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: _muted)),
      const SizedBox(height: 10),
      DashBarresSemaine(series: [parJour], couleurs: const [_teal], aujourdhui: now.weekday - 1),
    ]));
  }
}
