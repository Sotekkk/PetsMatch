// Accueil maréchal-ferrant : tournée du jour, demandes, interventions à
// clôturer et ferrures à renouveler (dernière intervention terminée + délai
// du profil, user_profiles.marechal_cycle_semaines, 7 semaines par défaut —
// migration_marechal_cycle_ferrure.sql). Miroir site :
// website/src/components/dashboard/MarechalDashboard.tsx. Scopé au profil actif.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/itineraire.dart';
import 'package:PetsMatch/pages/message.dart';
import 'package:PetsMatch/pages/agenda/agenda_page.dart';
import 'package:PetsMatch/pages/pro/pro_agenda.dart';
import 'package:PetsMatch/pages/pro/pro_clients_page.dart';
import 'package:PetsMatch/pages/pro/education_devis_page.dart';
import 'package:PetsMatch/pages/pro/marechal_contrats_page.dart';
import 'package:PetsMatch/pages/pro/sante_abonnement_page.dart';
import 'package:PetsMatch/pages/eleveur/admin/facturation.dart' show FacturationPage;
import 'package:PetsMatch/widgets/dashboard/dashboard_kit.dart';

const _teal = kDashTeal;
const _ink = kDashInk;
const _muted = kDashMuted;
const _ambre = Color(0xFFD97706);
const _rouge = Color(0xFFB3261E);
const _vert = Color(0xFF2E7D5E);
const _brun = Color(0xFF8D6E63);
const kCycleFerrureDefaut = 7;
const _actifs = ['demande', 'contre_proposition', 'confirme'];

class MarechalDashboard extends StatefulWidget {
  const MarechalDashboard({super.key});
  @override
  State<MarechalDashboard> createState() => _MarechalDashboardState();
}

class _MarechalDashboardState extends State<MarechalDashboard> {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _rdvs = [];
  final Map<String, String> _clients = {};
  final Map<String, Map<String, dynamic>> _animaux = {};
  int _cycle = kCycleFerrureDefaut;

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
    // Un an d'historique : de quoi retrouver la dernière ferrure de chaque cheval.
    final depuis = DateTime(now.year - 1, now.month, 1);
    try {
      final rows = await _supa.from('rdv')
          .select('id, date_heure, duree_minutes, statut, motif, animal_id, client_profile_id, '
              'client_nom_manuel, animal_nom_manuel, lieu, lieu_lat, lieu_lng, notes_client, created_at')
          .eq('pro_profile_id', pid)
          .inFilter('statut', [..._actifs, 'termine'])
          .gte('date_heure', depuis.toUtc().toIso8601String())
          .order('date_heure')
          .limit(3000);
      _rdvs = List<Map<String, dynamic>>.from((rows as List).map((e) => Map<String, dynamic>.from(e as Map)));
    } catch (_) {}
    try {
      final p = await _supa.from('user_profiles').select('marechal_cycle_semaines').eq('id', pid).maybeSingle();
      final c = (p?['marechal_cycle_semaines'] as num?)?.toInt();
      _cycle = c != null && c >= 2 && c <= 26 ? c : kCycleFerrureDefaut;
    } catch (_) {
      // Migration migration_marechal_cycle_ferrure.sql pas encore passée.
      _cycle = kCycleFerrureDefaut;
    }
    await _chargerNoms();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _chargerNoms() async {
    final profils = {for (final r in _rdvs) if (r['client_profile_id'] != null) r['client_profile_id'].toString()};
    final animaux = {for (final r in _rdvs) if (r['animal_id'] != null) r['animal_id'].toString()};
    try {
      if (profils.isNotEmpty) {
        final rows = await _supa.from('user_profiles_complet')
            .select('id, firstname, lastname, nom, profile_type').inFilter('id', profils.toList());
        for (final p in rows as List) {
          final perso = '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
          final st = (p['nom'] ?? '').toString().trim();
          _clients[p['id'].toString()] = p['profile_type'] != 'particulier' && st.isNotEmpty ? st : (perso.isNotEmpty ? perso : st);
        }
      }
      if (animaux.isNotEmpty) {
        final rows = await _supa.from('animaux').select('id, nom, photo_url').inFilter('id', animaux.toList());
        for (final a in rows as List) {
          _animaux[a['id'].toString()] = Map<String, dynamic>.from(a as Map);
        }
      }
    } catch (_) {}
  }

  Future<void> _changerCycle(int n) async {
    final avant = _cycle;
    setState(() => _cycle = n);
    try {
      await _supa.from('user_profiles').update({'marechal_cycle_semaines': n}).eq('id', _pid);
    } catch (e) {
      if (!mounted) return;
      setState(() => _cycle = avant);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          e.toString().contains('marechal_cycle_semaines')
              ? 'Réglage indisponible : migration migration_marechal_cycle_ferrure.sql à passer.'
              : 'Enregistrement impossible : $e',
          style: const TextStyle(fontFamily: 'Galey'))));
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  DateTime _debut(Map<String, dynamic> r) => DateTime.parse(r['date_heure'].toString()).toLocal();
  DateTime _fin(Map<String, dynamic> r) => _debut(r).add(Duration(minutes: (r['duree_minutes'] as num?)?.toInt() ?? 60));
  bool _memeJour(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  String _jm(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  String _nomAnimal(Map<String, dynamic> r) {
    final a = _animaux[r['animal_id']?.toString()]?['nom']?.toString() ?? '';
    if (a.isNotEmpty) return a;
    final m = r['animal_nom_manuel']?.toString().trim() ?? '';
    return m.isNotEmpty ? m : 'Cheval';
  }
  String _nomClient(Map<String, dynamic> r) {
    final c = _clients[r['client_profile_id']?.toString()] ?? '';
    if (c.isNotEmpty) return c;
    final m = r['client_nom_manuel']?.toString().trim() ?? '';
    return m.isNotEmpty ? m : 'Client';
  }
  String? _photo(Map<String, dynamic> r) => _animaux[r['animal_id']?.toString()]?['photo_url']?.toString();
  String _motif(Map<String, dynamic> r, [String defaut = 'Intervention']) {
    final m = r['motif']?.toString().trim() ?? '';
    return m.isEmpty ? defaut : m;
  }
  String? _adresse(Map<String, dynamic> r) {
    final l = r['lieu']?.toString().trim() ?? '';
    return l.isEmpty || l.toLowerCase() == 'à domicile' ? null : l;
  }
  bool _localise(Map<String, dynamic> r) => _adresse(r) != null || r['lieu_lat'] != null;
  /// Même cheval : fiche PetsMatch, sinon nom saisi + client (fiche hors appli).
  String? _cleCheval(Map<String, dynamic> r) {
    final id = r['animal_id']?.toString();
    if (id != null && id.isNotEmpty) return 'a:$id';
    final m = r['animal_nom_manuel']?.toString().trim() ?? '';
    if (m.isEmpty) return null;
    return 'm:${r['client_profile_id'] ?? r['client_nom_manuel'] ?? ''}:${m.toLowerCase()}';
  }

  Future<void> _go(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) _charger();
  }

  void _ouvrirRdv(Map<String, dynamic> r) {
    final s = r['statut'];
    // Un RDV confirmé reste dans « À venir » jusqu'à « Terminé », même une fois passé.
    final onglet = (s == 'demande' || s == 'contre_proposition') ? 0 : (s == 'confirme' ? 1 : 2);
    _go(ProAgendaPage(initialTabIndex: onglet, focusRdvId: r['id']?.toString()));
  }

  Future<void> _itineraire(Map<String, dynamic> r) => ouvrirItineraire(context,
      lat: (r['lieu_lat'] as num?)?.toDouble(), lng: (r['lieu_lng'] as num?)?.toDouble(),
      adresse: r['lieu']?.toString());

  void _programmer(Map<String, dynamic> r) => _go(ProAgendaPage(
      initialTabIndex: 1, nouveauRdv: true,
      nouveauRdvAnimalId: r['animal_id']?.toString(),
      nouveauRdvMotif: (r['motif']?.toString().trim() ?? '').isEmpty ? null : r['motif'].toString().trim()));

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 60),
          child: Center(child: CircularProgressIndicator(color: _teal)));
    }
    final now = DateTime.now();
    final tournee = _rdvs.where((r) => (r['statut'] == 'confirme' || r['statut'] == 'termine') && _memeJour(_debut(r), now)).toList();
    final debutMois = DateTime(now.year, now.month, 1);
    final finMois = DateTime(now.year, now.month + 1, 1);
    final duMois = _rdvs.where((r) => !_debut(r).isBefore(debutMois) && _debut(r).isBefore(finMois)).length;
    final demandes = _rdvs.where((r) => (r['statut'] == 'demande' || r['statut'] == 'contre_proposition') && _fin(r).isAfter(now)).toList();
    final aCloturer = _rdvs.where((r) => r['statut'] == 'confirme' && !_fin(r).isAfter(now)).toList()
      ..sort((a, b) => b['date_heure'].toString().compareTo(a['date_heure'].toString()));

    return LayoutBuilder(builder: (context, c) {
      final large = c.maxWidth >= 860;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GridView.count(
          crossAxisCount: large ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12, mainAxisSpacing: 12,
          childAspectRatio: large ? 2.4 : 1.65,
          children: [
            DashKpi(valeur: tournee.length, label: "RDV aujourd'hui", icon: Icons.today_outlined,
                onTap: () => _go(const ProAgendaPage(initialTabIndex: 1))),
            DashKpi(valeur: duMois, label: 'RDV ce mois', icon: Icons.calendar_month_outlined, teinte: _brun,
                onTap: () => _go(AgendaPage(initialViewMode: 0, onBack: () => Navigator.pop(context)))),
            DashKpi(valeur: demandes.length, label: 'Demandes en attente', icon: Icons.schedule_outlined,
                teinte: _ambre, actif: demandes.isNotEmpty, onTap: () => _go(const ProAgendaPage(initialTabIndex: 0))),
            DashKpi(valeur: aCloturer.length, label: 'Interventions à clôturer', icon: Icons.assignment_late_outlined,
                teinte: _rouge, actif: aCloturer.isNotEmpty, onTap: () => _go(const ProAgendaPage(initialTabIndex: 1))),
          ],
        ),
        const SizedBox(height: 16),
        _tourneeSection(tournee, now),
        const SizedBox(height: 16),
        _renouvelerSection(now),
        const SizedBox(height: 16),
        _listeSection('Demandes en attente', Icons.notifications_none, demandes, 'Aucune demande à traiter.',
            'Répondre', 0, (r) => [_motif(r, 'Rendez-vous'), 'le ${_jm(_debut(r))} à ${_hm(_debut(r))}'].join(' · ')),
        const SizedBox(height: 16),
        _listeSection('Interventions à clôturer', Icons.assignment_late_outlined, aCloturer,
            'Toutes les interventions passées sont clôturées.', 'Clôturer', 1,
            (r) => [_motif(r), 'le ${_jm(_debut(r))} à ${_hm(_debut(r))}'].join(' · ')),
        const SizedBox(height: 16),
        _accesRapides(),
      ]);
    });
  }

  // Tournée du jour -------------------------------------------------------

  Widget _tourneeSection(List<Map<String, dynamic>> tournee, DateTime now) {
    Map<String, dynamic>? prochain;
    for (final r in tournee) {
      if (r['statut'] == 'confirme' && _fin(r).isAfter(now) && _localise(r)) { prochain = r; break; }
    }
    return DashCarte(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DashTitre('Tournée du jour', icone: Icons.place_outlined, compteur: tournee.length,
          trailing: prochain != null
              ? DashLien('Itinéraire du prochain', onTap: () => _itineraire(prochain!))
              : DashLien("Voir l'agenda", onTap: () => _go(const ProAgendaPage(initialTabIndex: 1)))),
      const SizedBox(height: 8),
      if (tournee.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 16),
            child: Text("Aucune intervention aujourd'hui.", textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted)))
      else
        for (final r in tournee) _ligneTournee(r, now),
    ]));
  }

  Widget _ligneTournee(Map<String, dynamic> r, DateTime now) {
    final fait = r['statut'] == 'termine';
    final passe = !fait && !_fin(r).isAfter(now);
    final st = fait
        ? (t: 'Terminé', fg: const Color(0xFF4B5563), bg: const Color(0xFFF1F2F4))
        : passe
            ? (t: 'À clôturer', fg: _ambre, bg: const Color(0xFFFFF4DC))
            : !_debut(r).isAfter(now)
                ? (t: 'En cours', fg: _teal, bg: const Color(0xFFE6F2F3))
                : (t: 'À venir', fg: const Color(0xFF1D4ED8), bg: const Color(0xFFE8F0FE));
    final a = _adresse(r);
    final lieu = a ?? (r['lieu_lat'] != null ? 'Position enregistrée' : 'Adresse non renseignée');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _ouvrirRdv(r),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFEEF0EE))),
            child: Row(children: [
              SizedBox(width: 46, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_hm(_debut(r)), style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, fontWeight: FontWeight.w700, color: _ink)),
                Text('${(r['duree_minutes'] as num?)?.toInt() ?? 60} min',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: _muted)),
              ])),
              DashPhotoAnimal(url: _photo(r), taille: 34),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_nomAnimal(r)} · ${_nomClient(r)}', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, fontWeight: FontWeight.w700, color: _ink)),
                Text(_motif(r), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _muted)),
                Text(lieu, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: _localise(r) ? _muted : _ambre)),
              ])),
              const SizedBox(width: 6),
              DashBadge(st.t, fg: st.fg, bg: st.bg),
            ]),
          ),
        )),
        if (!fait && _localise(r))
          IconButton(
            tooltip: 'Itinéraire',
            icon: const Icon(Icons.directions_outlined, color: _teal),
            onPressed: () => _itineraire(r),
          ),
      ]),
    );
  }

  // Ferrures à renouveler -------------------------------------------------

  Widget _renouvelerSection(DateTime now) {
    // Dernière intervention terminée + délai, sans RDV déjà prévu pour ce
    // cheval ; affichées dès 7 jours avant l'échéance.
    final derniere = <String, Map<String, dynamic>>{};
    final prevus = <String>{};
    for (final r in _rdvs) {
      final k = _cleCheval(r);
      if (k == null) continue;
      if (r['statut'] == 'termine') {
        final d = derniere[k];
        if (d == null || d['date_heure'].toString().compareTo(r['date_heure'].toString()) < 0) derniere[k] = r;
      } else if (_actifs.contains(r['statut']) && _fin(r).isAfter(now)) {
        prevus.add(k);
      }
    }
    final jour = DateTime(now.year, now.month, now.day);
    final liste = [
      for (final e in derniere.entries)
        if (!prevus.contains(e.key))
          () {
            final d = _debut(e.value);
            final ech = DateTime(d.year, d.month, d.day + _cycle * 7);
            return (r: e.value, ech: ech, ecart: ech.difference(jour).inDays);
          }(),
    ].where((x) => x.ecart <= 7).toList()
      ..sort((a, b) => a.ecart.compareTo(b.ecart));

    return DashCarte(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DashTitre('Ferrures à renouveler', icone: Icons.autorenew, compteur: liste.length),
      const SizedBox(height: 4),
      InkWell(
        onTap: _choisirCycle,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Text('Toutes les $_cycle semaines', style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: _muted)),
            const SizedBox(width: 6),
            const Text('Modifier', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w700, color: _teal)),
          ]),
        ),
      ),
      const SizedBox(height: 4),
      if (liste.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Aucun cheval à revoir dans les 7 prochains jours.', textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted)))
      else ...[
        for (final x in liste.take(8))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              DashPhotoAnimal(url: _photo(x.r), taille: 32),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_nomAnimal(x.r)} · ${_nomClient(x.r)}', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700, color: _ink)),
                Text('${_motif(x.r)} le ${_jm(_debut(x.r))} · à revoir le ${_jm(x.ech)}', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: _muted)),
                Text(x.ecart < 0 ? 'En retard de ${-x.ecart} j' : x.ecart == 0 ? "Aujourd'hui" : 'Dans ${x.ecart} j',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, fontWeight: FontWeight.w600,
                        color: x.ecart < 0 ? const Color(0xFFDC2626) : _muted)),
              ])),
              const SizedBox(width: 6),
              FilledButton(
                onPressed: () => _programmer(x.r),
                style: FilledButton.styleFrom(backgroundColor: _teal, padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 34), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('Programmer', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        if (liste.length > 8)
          Text('et ${liste.length - 8} autre${liste.length - 8 > 1 ? 's' : ''}',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _muted)),
      ],
    ]));
  }

  Future<void> _choisirCycle() async {
    final choix = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Délai entre deux ferrures', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 4),
          const Text('Les chevaux apparaissent dans « Ferrures à renouveler » 7 jours avant l\'échéance.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: _muted)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var n = 2; n <= 26; n++)
              ChoiceChip(
                label: Text('$n sem.', style: const TextStyle(fontFamily: 'Galey')),
                selected: n == _cycle,
                onSelected: (_) => Navigator.pop(ctx, n),
              ),
          ]),
          const SizedBox(height: 8),
        ]),
      )),
    );
    if (choix != null && choix != _cycle) await _changerCycle(choix);
  }

  // Demandes / à clôturer --------------------------------------------------

  Widget _listeSection(String titre, IconData icone, List<Map<String, dynamic>> l, String vide,
      String action, int onglet, String Function(Map<String, dynamic>) detail) {
    return DashCarte(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DashTitre(titre, icone: icone, compteur: l.length,
          trailing: l.length > 4 ? DashLien('Voir toutes', onTap: () => _go(ProAgendaPage(initialTabIndex: onglet))) : null),
      const SizedBox(height: 6),
      if (l.isEmpty)
        Padding(padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(vide, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted)))
      else
        for (final r in l.take(4))
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _ouvrirRdv(r),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                DashPhotoAnimal(url: _photo(r), taille: 32),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${_nomAnimal(r)} · ${_nomClient(r)}', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700, color: _ink)),
                  Text(detail(r), maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: _muted)),
                ])),
                const SizedBox(width: 6),
                Text(action, style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5, fontWeight: FontWeight.w700, color: _teal)),
                const Icon(Icons.chevron_right, size: 18, color: _muted),
              ]),
            ),
          ),
    ]));
  }

  // Accès rapides -----------------------------------------------------------

  Widget _accesRapides() {
    Widget tuile(IconData ic, String t, Color c, VoidCallback onTap) => Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: kDashBorder)),
              child: Row(children: [
                Icon(ic, size: 19, color: c),
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
        final cols = c.maxWidth >= 560 ? 3 : 2;
        return GridView.count(
          crossAxisCount: cols, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: cols == 3 ? 3.4 : 2.9,
          children: [
            tuile(Icons.add_circle_outline, 'Nouveau RDV', _teal,
                () => _go(const ProAgendaPage(initialTabIndex: 1, nouveauRdv: true))),
            tuile(Icons.pets_outlined, 'Mes équidés suivis', _vert, () => _go(const ProClientsPage())),
            tuile(Icons.request_quote_outlined, 'Devis', _brun, () => _go(const DevisPage())),
            tuile(Icons.description_outlined, 'Mes contrats', _ambre, () => _go(const MarechalContratsPage())),
            tuile(Icons.receipt_long_outlined, 'Facturation', _vert, () => _go(const FacturationPage())),
            tuile(Icons.chat_bubble_outline, 'Messages', _teal, () => _go(const MessagePage())),
            tuile(Icons.workspace_premium_outlined, 'Mon abonnement', _ambre,
                () => _go(const SanteAbonnementPage(profilType: 'marechal_ferrant'))),
          ],
        );
      }),
    ]));
  }
}
