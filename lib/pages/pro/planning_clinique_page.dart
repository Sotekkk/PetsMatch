// Planning de la clinique vétérinaire : journée en colonnes, par praticien ou
// par salle — RDV confirmés, demandes (dont « vétérinaire au choix »),
// indisponibilités et disponibilités. Ouvert depuis l'agenda (pro_agenda.dart)
// par le titulaire, le cogérant ou un employé ayant l'accès « Agenda » (même
// contexte AgendaContexte, scopé au profil clinique). Les actions (accepter,
// attribuer, modifier, nouveau RDV) restent celles de l'agenda (callbacks).
// Miroir site : website/src/components/rdv/PlanningClinique.tsx.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/utils/contexte_pro.dart';

const _teal = Color(0xFF0C5C6C);
const _ink = Color(0xFF1E2025);
const _muted = Color(0xFF6F767B);
const _line = Color(0xFFE4E7E2);
const _font = 'Galey';

/// Couleurs des praticiens (repérage en vue « Salles »).
const _kCouleurs = [
  Color(0xFF0C5C6C), Color(0xFF6E9E57), Color(0xFFE08A3C), Color(0xFF8E5BB5),
  Color(0xFFC2185B), Color(0xFF1E88E5), Color(0xFF6D4C41),
];

class PlanningCliniquePage extends StatefulWidget {
  /// Ouvre les actions de l'agenda sur un RDV (accepter, attribuer…).
  final Future<void> Function(Map<String, dynamic> rdv) onOuvrirRdv;
  /// Nouveau RDV pré-rempli (praticien '' = titulaire, null = non précisé).
  final Future<void> Function(DateTime debut, String? praticien, String? salle) onNouveauRdv;

  const PlanningCliniquePage({super.key, required this.onOuvrirRdv, required this.onNouveauRdv});

  @override
  State<PlanningCliniquePage> createState() => _PlanningCliniquePageState();
}

class _Colonne {
  final String id;       // praticien ('' = titulaire) ou salle ('' = sans salle)
  final String titre;
  final String? sousTitre;
  final Color couleur;
  const _Colonne(this.id, this.titre, this.couleur, {this.sousTitre});
}

class _PlanningCliniquePageState extends State<PlanningCliniquePage> {
  static const _hPx = 64.0;      // hauteur d'une heure
  static const _colW = 148.0;
  static const _timeW = 48.0;

  DateTime _jour = DateTime.now();
  bool _parSalle = false;
  bool _loading = true;

  List<({String id, String nom})> _praticiens = [];
  List<({String id, String nom, String type})> _salles = [];
  List<Map<String, dynamic>> _rdvs = [];
  List<Map<String, dynamic>> _indispos = [];
  List<Map<String, dynamic>> _creneaux = [];
  Map<String, String> _nomsClients = {}, _nomsAnimaux = {};

  final _hHeader = ScrollController(), _hBody = ScrollController();
  bool _sync = false;

  @override
  void initState() {
    super.initState();
    _hBody.addListener(() => _suivre(_hBody, _hHeader));
    _hHeader.addListener(() => _suivre(_hHeader, _hBody));
    _charger();
  }

  void _suivre(ScrollController de, ScrollController vers) {
    if (_sync || !vers.hasClients) return;
    _sync = true;
    vers.jumpTo(de.offset.clamp(0.0, vers.position.maxScrollExtent));
    _sync = false;
  }

  @override
  void dispose() {
    _hHeader.dispose();
    _hBody.dispose();
    super.dispose();
  }

  String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _charger() async {
    setState(() => _loading = true);
    final supa = Supabase.instance.client;
    final pid = AgendaContexte.profileId;
    final debut = DateTime(_jour.year, _jour.month, _jour.day);
    final fin = debut.add(const Duration(days: 1));
    try {
      final res = await Future.wait<dynamic>([
        supa.rpc('pm_praticiens_clinique', params: {'p_pro_profile_id': pid}),
        supa.from('salles_clinique').select('id, nom, type_salle')
            .eq('clinique_profile_id', pid).eq('actif', true).order('ordre'),
        supa.from('rdv').select()
            .eq('pro_profile_id', pid)
            .inFilter('statut', ['demande', 'confirme', 'termine'])
            .gte('date_heure', debut.toUtc().toIso8601String())
            .lt('date_heure', fin.toUtc().toIso8601String()),
        supa.from('agenda_events').select('id, titre, date_debut, date_fin, duree_minutes, praticien_profile_id')
            .eq('type', 'indisponible').eq('pro_profile_id', pid)
            .lt('date_debut', fin.toUtc().toIso8601String())
            .gte('date_debut', debut.subtract(const Duration(days: 1)).toUtc().toIso8601String()),
        supa.from('creneaux_pro').select('praticien_profile_id, salle_id, heure_debut, heure_fin')
            .eq('pro_profile_id', pid).eq('date', _ymd(_jour)),
      ]);
      _praticiens = [
        for (final p in res[0] as List)
          (id: p['praticien_profile_id']?.toString() ?? '',
           nom: (p['nom'] as String?)?.trim().isNotEmpty == true ? p['nom'] as String : 'Vétérinaire'),
      ];
      _salles = [
        for (final s in res[1] as List)
          (id: s['id'] as String, nom: (s['nom'] as String?) ?? 'Salle', type: (s['type_salle'] as String?) ?? 'consultation'),
      ];
      _rdvs = List<Map<String, dynamic>>.from((res[2] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      _indispos = List<Map<String, dynamic>>.from((res[3] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      _creneaux = List<Map<String, dynamic>>.from((res[4] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      await _chargerNoms();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _chargerNoms() async {
    final supa = Supabase.instance.client;
    final profils = {for (final r in _rdvs) if (r['client_profile_id'] != null) r['client_profile_id'].toString()};
    final animaux = {for (final r in _rdvs) if (r['animal_id'] != null) r['animal_id'].toString()};
    final clients = <String, String>{}, bestioles = <String, String>{};
    try {
      if (profils.isNotEmpty) {
        final rows = await supa.from('user_profiles_complet')
            .select('id, firstname, lastname, nom').inFilter('id', profils.toList());
        for (final p in rows as List) {
          final n = '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
          clients[p['id'].toString()] = n.isNotEmpty ? n : (p['nom']?.toString() ?? '');
        }
      }
    } catch (_) {}
    try {
      if (animaux.isNotEmpty) {
        final rows = await supa.from('animaux').select('id, nom').inFilter('id', animaux.toList());
        for (final a in rows as List) {
          bestioles[a['id'].toString()] = a['nom']?.toString() ?? '';
        }
      }
    } catch (_) {}
    _nomsClients = clients;
    _nomsAnimaux = bestioles;
  }

  // ── Colonnes ──────────────────────────────────────────────────────────────

  Color _couleurPraticien(String id) {
    final i = _praticiens.indexWhere((p) => p.id == id);
    return _kCouleurs[(i < 0 ? 0 : i) % _kCouleurs.length];
  }

  String _nomPraticien(String? id) =>
      _praticiens.where((p) => p.id == (id ?? '')).map((p) => p.nom).firstOrNull ?? 'Vétérinaire';

  List<_Colonne> get _colonnes {
    if (_parSalle) {
      final cols = [
        for (final s in _salles) _Colonne(s.id, s.nom, _teal, sousTitre: _libelleType(s.type)),
      ];
      if (_rdvs.any((r) => r['salle_id'] == null || !_salles.any((s) => s.id == r['salle_id']))) {
        cols.add(const _Colonne('', 'Sans salle', _muted));
      }
      return cols;
    }
    return [for (final p in _praticiens) _Colonne(p.id, p.nom, _couleurPraticien(p.id))];
  }

  String _libelleType(String t) => switch (t) {
    'consultation' => 'Consultation',
    'chirurgie' => 'Chirurgie',
    'imagerie' => 'Imagerie',
    'hospitalisation' => 'Hospitalisation',
    _ => t.isEmpty ? '' : '${t[0].toUpperCase()}${t.substring(1)}',
  };

  bool _rdvDansColonne(Map<String, dynamic> r, _Colonne c) {
    if (_parSalle) {
      final s = r['salle_id']?.toString();
      if (c.id.isEmpty) return s == null || !_salles.any((x) => x.id == s);
      return s == c.id;
    }
    return (r['instructeur_profile_id']?.toString() ?? '') == c.id;
  }

  // ── Plage horaire affichée ────────────────────────────────────────────────

  (int, int) get _plage {
    var deb = 8 * 60, fin = 19 * 60;
    int m(String hhmm) {
      final p = hhmm.split(':');
      return int.parse(p[0]) * 60 + int.parse(p[1]);
    }
    for (final c in _creneaux) {
      final a = m(c['heure_debut'] as String), b = m(c['heure_fin'] as String);
      if (a < deb) deb = a;
      if (b > fin) fin = b;
    }
    for (final r in _rdvs) {
      final dh = DateTime.tryParse(r['date_heure']?.toString() ?? '')?.toLocal();
      if (dh == null) continue;
      final a = dh.hour * 60 + dh.minute;
      final b = a + ((r['duree_minutes'] as num?)?.toInt() ?? 30);
      if (a < deb) deb = a;
      if (b > fin) fin = b;
    }
    return ((deb ~/ 60) * 60, ((fin + 59) ~/ 60) * 60);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  static const _jours = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
  static const _mois = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août',
      'septembre', 'octobre', 'novembre', 'décembre'];

  void _changerJour(int delta) {
    setState(() => _jour = _jour.add(Duration(days: delta)));
    _charger();
  }

  @override
  Widget build(BuildContext context) {
    final cols = _colonnes;
    final aujourdhui = _ymd(_jour) == _ymd(DateTime.now());
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Planning de la clinique', style: TextStyle(fontFamily: _font, fontWeight: FontWeight.w700)),
        actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: 'Actualiser', onPressed: _charger)],
      ),
      body: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
          child: Column(children: [
            Row(children: [
              IconButton(icon: const Icon(Icons.chevron_left_rounded), onPressed: () => _changerJour(-1)),
              Expanded(child: GestureDetector(
                onTap: () async {
                  final d = await showDatePicker(context: context, initialDate: _jour,
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365)));
                  if (d != null) { setState(() => _jour = d); _charger(); }
                },
                child: Column(children: [
                  Text('${_jours[_jour.weekday - 1]} ${_jour.day} ${_mois[_jour.month - 1]}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontFamily: _font, fontSize: 15.5, fontWeight: FontWeight.w700, color: _ink)),
                  if (!aujourdhui)
                    GestureDetector(
                      onTap: () { setState(() => _jour = DateTime.now()); _charger(); },
                      child: const Text("Revenir à aujourd'hui",
                          style: TextStyle(fontFamily: _font, fontSize: 11.5, color: _teal, decoration: TextDecoration.underline)),
                    ),
                ]),
              )),
              IconButton(icon: const Icon(Icons.chevron_right_rounded), onPressed: () => _changerJour(1)),
            ]),
            const SizedBox(height: 6),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, icon: Icon(Icons.person_outline, size: 18), label: Text('Praticiens')),
                ButtonSegment(value: true, icon: Icon(Icons.meeting_room_outlined, size: 18), label: Text('Salles')),
              ],
              selected: {_parSalle},
              onSelectionChanged: (s) => setState(() => _parSalle = s.first),
              style: ButtonStyle(textStyle: WidgetStateProperty.all(const TextStyle(fontFamily: _font, fontSize: 13))),
            ),
          ]),
        ),
        const Divider(height: 1, color: _line),
        Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(color: _teal))
            : cols.isEmpty
                ? Center(child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_parSalle ? 'Aucune salle déclarée pour la clinique.' : 'Aucun praticien.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontFamily: _font, fontSize: 13, color: _muted)),
                  ))
                : _grille(cols)),
        _legende(),
      ]),
    );
  }

  Widget _legende() {
    Widget item(Color fond, Color bord, String t, {bool pointille = false}) => Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 14, height: 14, decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(4),
          border: Border.all(color: bord, width: pointille ? 1.5 : 1))),
      const SizedBox(width: 5),
      Text(t, style: const TextStyle(fontFamily: _font, fontSize: 11, color: _muted)),
    ]);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: SafeArea(top: false, child: Wrap(spacing: 14, runSpacing: 6, children: [
        item(_teal.withValues(alpha: 0.85), _teal, 'Confirmé'),
        item(Colors.white, _teal, 'Demande', pointille: true),
        item(const Color(0xFFEFF6F1), const Color(0xFFCFE3D6), 'Disponible'),
        item(const Color(0xFFE9EAE8), const Color(0xFFD0D3CF), 'Indisponible'),
      ])),
    );
  }

  Widget _grille(List<_Colonne> cols) {
    final (deb, fin) = _plage;
    final hauteur = (fin - deb) / 60 * _hPx;
    return LayoutBuilder(builder: (context, c) {
      final dispo = c.maxWidth - _timeW;
      final w = cols.length * _colW < dispo ? dispo / cols.length : _colW;
      return Column(children: [
        // En-têtes de colonnes (défilement horizontal synchronisé)
        Container(
          color: Colors.white,
          child: Row(children: [
            const SizedBox(width: _timeW),
            Expanded(child: SingleChildScrollView(
              controller: _hHeader,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: Row(children: [
                for (final col in cols) Container(
                  width: w,
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  decoration: const BoxDecoration(border: Border(left: BorderSide(color: _line))),
                  child: Row(children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: col.couleur, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(col.titre, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: _font, fontSize: 12.5, fontWeight: FontWeight.w700, color: _ink)),
                      if (col.sousTitre != null && col.sousTitre!.isNotEmpty)
                        Text(col.sousTitre!, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontFamily: _font, fontSize: 10.5, color: _muted)),
                    ])),
                  ]),
                ),
              ]),
            )),
          ]),
        ),
        const Divider(height: 1, color: _line),
        Expanded(child: SingleChildScrollView(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: _timeW, height: hauteur, child: Stack(children: [
              for (var h = deb; h < fin; h += 60) Positioned(
                top: (h - deb) / 60 * _hPx - 6, left: 0, right: 6,
                child: Text('${(h ~/ 60).toString().padLeft(2, '0')}:00', textAlign: TextAlign.right,
                    style: const TextStyle(fontFamily: _font, fontSize: 10.5, color: _muted)),
              ),
            ])),
            Expanded(child: SingleChildScrollView(
              controller: _hBody,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final col in cols) _colonne(col, w, hauteur, deb),
              ]),
            )),
          ]),
        )),
      ]);
    });
  }

  double _y(int minutes, int deb) => (minutes - deb) / 60 * _hPx;

  int _minutesDe(String hhmm) {
    final p = hhmm.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  Widget _colonne(_Colonne col, double w, double hauteur, int deb) {
    final debJour = DateTime(_jour.year, _jour.month, _jour.day);
    // Disponibilités (vue praticien) ; indisponibilités (titulaire = sans praticien).
    final dispos = _parSalle
        ? _creneaux.where((c) => c['salle_id']?.toString() == col.id && col.id.isNotEmpty)
        : _creneaux.where((c) => (c['praticien_profile_id']?.toString() ?? '') == col.id);
    final indispos = _parSalle ? const <Map<String, dynamic>>[]
        : _indispos.where((e) => (e['praticien_profile_id']?.toString() ?? '') == col.id);
    final rdvs = _rdvs.where((r) => _rdvDansColonne(r, col)).toList();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        final m = deb + (d.localPosition.dy / _hPx * 60).floor();
        final arrondi = (m ~/ 15) * 15;
        final dt = debJour.add(Duration(minutes: arrondi));
        _nouveau(dt, col);
      },
      child: Container(
        width: w, height: hauteur,
        decoration: const BoxDecoration(color: Colors.white, border: Border(left: BorderSide(color: _line))),
        child: Stack(clipBehavior: Clip.hardEdge, children: [
          for (final c in dispos) Positioned(
            top: _y(_minutesDe(c['heure_debut'] as String), deb), left: 0, right: 0,
            height: (_minutesDe(c['heure_fin'] as String) - _minutesDe(c['heure_debut'] as String)) / 60 * _hPx,
            child: Container(color: const Color(0xFFEFF6F1)),
          ),
          for (var h = 1; h * _hPx < hauteur; h++) Positioned(
            top: h * _hPx, left: 0, right: 0,
            child: Container(height: 1, color: const Color(0xFFF0F1EF)),
          ),
          for (final e in indispos) _blocIndispo(e, debJour, deb),
          for (final r in rdvs) _blocRdv(r, deb),
        ]),
      ),
    );
  }

  Widget _blocIndispo(Map<String, dynamic> e, DateTime debJour, int deb) {
    final d0 = DateTime.tryParse(e['date_debut']?.toString() ?? '')?.toLocal();
    if (d0 == null) return const SizedBox.shrink();
    final d1 = DateTime.tryParse(e['date_fin']?.toString() ?? '')?.toLocal()
        ?? d0.add(Duration(minutes: (e['duree_minutes'] as num?)?.toInt() ?? 60));
    final finJour = debJour.add(const Duration(days: 1));
    final a = d0.isBefore(debJour) ? debJour : d0;
    final b = d1.isAfter(finJour) ? finJour : d1;
    if (!b.isAfter(a)) return const SizedBox.shrink();
    final ma = a.difference(debJour).inMinutes, mb = b.difference(debJour).inMinutes;
    return Positioned(
      top: _y(ma, deb).clamp(0, double.infinity), left: 2, right: 2,
      height: (mb - ma) / 60 * _hPx,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: const Color(0xFFE9EAE8), borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFD0D3CF))),
        child: Text(e['titre']?.toString() ?? 'Indisponible', maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: _font, fontSize: 10.5, color: _muted)),
      ),
    );
  }

  Widget _blocRdv(Map<String, dynamic> r, int deb) {
    final dh = DateTime.tryParse(r['date_heure']?.toString() ?? '')?.toLocal();
    if (dh == null) return const SizedBox.shrink();
    final duree = (r['duree_minutes'] as num?)?.toInt() ?? 30;
    final m = dh.hour * 60 + dh.minute;
    final demande = r['statut'] == 'demande';
    final auChoix = demande && r['praticien_indifferent'] == true;
    final couleur = _couleurPraticien(r['instructeur_profile_id']?.toString() ?? '');
    final animal = (r['animal_id'] != null ? _nomsAnimaux[r['animal_id'].toString()] : null)
        ?? r['animal_nom_manuel']?.toString() ?? '';
    final client = (r['client_profile_id'] != null ? _nomsClients[r['client_profile_id'].toString()] : null)
        ?? r['client_nom_manuel']?.toString() ?? '';
    final heure = '${dh.hour.toString().padLeft(2, '0')}:${dh.minute.toString().padLeft(2, '0')}';
    final h = duree / 60 * _hPx;
    final texte = demande ? _ink : Colors.white;
    return Positioned(
      top: _y(m, deb), left: 3, right: 3, height: h < 22 ? 22 : h,
      child: GestureDetector(
        onTap: () async { await widget.onOuvrirRdv(r); if (mounted) _charger(); },
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 3, 6, 3),
          decoration: BoxDecoration(
            color: demande ? Colors.white : couleur.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: couleur, width: demande ? 1.5 : 1),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 3, offset: const Offset(0, 1))],
          ),
          child: ClipRect(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$heure · ${r['motif'] ?? 'RDV'}', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: _font, fontSize: 11, fontWeight: FontWeight.w700, color: texte)),
            if (h >= 34 && (animal.isNotEmpty || client.isNotEmpty))
              Text([animal, client].where((s) => s.isNotEmpty).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: _font, fontSize: 10.5, color: texte.withValues(alpha: 0.85))),
            if (h >= 48)
              Text(auChoix ? 'Demande · vétérinaire au choix'
                      : demande ? 'Demande à valider'
                      : _parSalle ? _nomPraticien(r['instructeur_profile_id']?.toString()) : '',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: _font, fontSize: 10, fontStyle: demande ? FontStyle.italic : FontStyle.normal,
                      color: demande ? couleur : Colors.white.withValues(alpha: 0.85))),
          ])),
        ),
      ),
    );
  }

  Future<void> _nouveau(DateTime dt, _Colonne col) async {
    final hh = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final ok = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$hh — ${col.titre}', style: const TextStyle(fontFamily: _font, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.add_circle_outline, color: _teal),
            title: const Text('Nouveau rendez-vous ici', style: TextStyle(fontFamily: _font, fontWeight: FontWeight.w600)),
            onTap: () => Navigator.pop(ctx, true),
          ),
        ]),
      )),
    );
    if (ok != true) return;
    await widget.onNouveauRdv(dt, _parSalle ? null : col.id, _parSalle && col.id.isNotEmpty ? col.id : null);
    if (mounted) _charger();
  }
}
