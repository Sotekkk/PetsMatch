// Fiches vétérinaire / ostéopathe — onglets Synthèse et Documents (étape 5
// de l'harmonisation des fiches pro). Données EXISTANTES uniquement :
// comptes_rendus, ordonnances (vétérinaire), suivis_morpho (séances ostéo),
// carnet (poids, allergies, traitements, vaccinations, chirurgies), rdv.
// Miroir site : mes-patients/[id] (onglets Synthèse / Documents).
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/animaux/morpho/morpho_constants.dart' show titreCompteRendu;
import 'package:PetsMatch/pages/animaux/morpho/morpho_detail_page.dart';
import 'package:PetsMatch/pages/pro/pro_agenda.dart' show ProAgendaPage;

const _teal = Color(0xFF0C5C6C);
const _ink = Color(0xFF1F2A2E);
const _rouge = Color(0xFFB3261E);
const _ambre = Color(0xFFD97706);

List<Map<String, dynamic>> _l(dynamic r) =>
    List<Map<String, dynamic>>.from((r as List).map((e) => Map<String, dynamic>.from(e as Map)));
String _date(dynamic v) {
  final d = DateTime.tryParse(v?.toString() ?? '')?.toLocal();
  return d == null ? '' : DateFormat('dd/MM/yyyy').format(d);
}
DateTime? _d(dynamic v) => DateTime.tryParse(v?.toString() ?? '');

Widget _carte(String titre, IconData ic, Widget child, {Widget? action}) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE6E8E6))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(ic, size: 17, color: _teal),
          const SizedBox(width: 8),
          Expanded(child: Text(titre, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _ink))),
          if (action != null) action,
        ]),
        const SizedBox(height: 8),
        child,
      ]),
    );
Widget _discret(String t) => Text(t, style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600));
Widget _txt(String t, {Color? c, FontWeight? w, double taille = 13.5}) => Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Text(t, style: TextStyle(fontFamily: 'Galey', fontSize: taille, color: c ?? _ink, fontWeight: w, height: 1.35)),
    );

Future<Map<String, dynamic>?> _prochainRdv(String animalId) async {
  final pid = User_Info.activeProfileId;
  if (pid.isEmpty) return null;
  try {
    return await Supabase.instance.client.from('rdv').select()
        .eq('pro_profile_id', pid).eq('animal_id', animalId).eq('statut', 'confirme')
        .gte('date_heure', DateTime.now().toUtc().toIso8601String()).order('date_heure').limit(1).maybeSingle();
  } catch (_) { return null; }
}

String _rdvTexte(Map<String, dynamic> r) {
  final d = DateTime.parse(r['date_heure'].toString()).toLocal();
  return '${DateFormat('dd/MM/yyyy à HH:mm').format(d)}'
      '${(r['motif']?.toString() ?? '').isNotEmpty ? ' · ${r['motif']}' : ''}'
      '${(r['lieu']?.toString() ?? '').isNotEmpty ? '\n${r['lieu']}' : ''}';
}

// ── Synthèse vétérinaire ─────────────────────────────────────────────────────

class SyntheseVetTab extends StatefulWidget {
  final String animalId;
  final VoidCallback onIdentite;
  /// Rappel de vaccin fait aujourd'hui (formulaire du carnet pré-rempli) —
  /// null en lecture seule.
  final Future<void> Function(Map<String, dynamic> vaccin)? onFaireRappel;
  /// Écriture au carnet autorisée (pesée depuis la Synthèse).
  final bool peutEcrire;
  const SyntheseVetTab({super.key, required this.animalId, required this.onIdentite, this.onFaireRappel,
      this.peutEcrire = false});
  @override
  State<SyntheseVetTab> createState() => _SyntheseVetTabState();
}

class _SyntheseVetTabState extends State<SyntheseVetTab> {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  Map<String, dynamic>? _derniereCr, _poids, _rdv;
  List<Map<String, dynamic>> _allergies = [], _traitements = [], _vaccins = [], _chirurgies = [];

  @override
  void initState() { super.initState(); _charger(); }

  Future<void> _charger() async {
    final id = widget.animalId;
    try { _derniereCr = await _supa.from('comptes_rendus').select().eq('animal_id', id).order('created_at', ascending: false).limit(1).maybeSingle(); } catch (_) {}
    try { _poids = await _supa.from('poids').select().eq('animal_id', id).order('date', ascending: false).limit(1).maybeSingle(); } catch (_) {}
    try { _allergies = _l(await _supa.from('allergies').select().eq('animal_id', id)); } catch (_) {}
    try { _traitements = _l(await _supa.from('traitements').select().eq('animal_id', id).order('date', ascending: false)); } catch (_) {}
    try { _vaccins = _l(await _supa.from('vaccinations').select().eq('animal_id', id).order('date', ascending: false)); } catch (_) {}
    try { _chirurgies = _l(await _supa.from('chirurgies').select().eq('animal_id', id).order('date', ascending: false)); } catch (_) {}
    _rdv = await _prochainRdv(id);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _ouvrirAgenda(ProAgendaPage page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) _charger();
  }

  /// Nouveau RDV pour cet animal : propriétaire pré-rempli, le RDV arrive dans
  /// son agenda et celui de ses co-propriétaires (rappels 48 h / veille).
  void _planifier([String? motif]) => _ouvrirAgenda(
      ProAgendaPage(nouveauRdv: true, nouveauRdvAnimalId: widget.animalId, nouveauRdvMotif: motif));

  Future<void> _actionsRappel(Map<String, dynamic> v) async {
    final nom = (v['vaccin'] ?? v['categorie'] ?? 'vaccin').toString();
    Widget tuile(String val, IconData ic, String t, String st) => ListTile(
          leading: Icon(ic, color: _teal),
          title: Text(t, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
          subtitle: Text(st, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
          onTap: () => Navigator.pop(context, val),
        );
    final choix = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text('Rappel : $nom', style: const TextStyle(fontFamily: 'Galey', fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          if (widget.onFaireRappel != null)
            tuile('faire', Icons.vaccines_outlined, 'Enregistrer le rappel',
                'Fait aujourd’hui, prochain rappel au même intervalle'),
          tuile('rdv', Icons.event_available_outlined, 'Planifier un RDV de rappel',
              'Dans l’agenda du propriétaire et des co-propriétaires'),
        ]),
      )),
    );
    if (choix == 'faire') {
      await widget.onFaireRappel!(v);
      if (mounted) _charger();
    } else if (choix == 'rdv') {
      _planifier('Rappel vaccin — $nom');
    }
  }

  /// Pesée du jour (souvent le premier geste de la consultation) : courbe de
  /// poids + poids de la fiche ; reprise ensuite dans le compte rendu.
  Future<void> _nouvellePesee() async {
    final ctrl = TextEditingController();
    final kg = await showDialog<double>(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Nouvelle pesée', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      content: TextField(
        controller: ctrl, autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Poids (kg)', border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey'))),
        TextButton(
          onPressed: () {
            final v = double.tryParse(ctrl.text.trim().replaceAll(',', '.').replaceAll(' ', ''));
            if (v != null && v > 0) Navigator.pop(ctx, v);
          },
          child: const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        ),
      ],
    ));
    if (kg == null) return;
    try {
      await _supa.from('poids').insert({
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'animal_id': widget.animalId, 'valeur': kg,
        'date': DateTime.now().toIso8601String(), 'notes': 'Consultation',
      });
      await _supa.from('animaux').update({'poids': kg}).eq('id', widget.animalId);
      if (mounted) _charger();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')), backgroundColor: Colors.red));
      }
    }
  }

  /// Ligne cliquable (rappel) : texte + chevron.
  Widget _ligneRappel(Map<String, dynamic> v, String t, {Color? c, FontWeight? w}) => InkWell(
        onTap: () => _actionsRappel(v),
        borderRadius: BorderRadius.circular(6),
        child: Row(children: [
          Expanded(child: _txt(t, c: c, w: w)),
          Icon(Icons.chevron_right, size: 18, color: c ?? Colors.grey.shade500),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: _teal));
    final now = DateTime.now();
    final actifs = _traitements.where((t) => _d(t['date_fin']) == null || !_d(t['date_fin'])!.isBefore(now)).toList();
    // Un rappel n'est dépassé que si la DERNIÈRE injection de sa catégorie
    // (rage, CHPPi, leptospirose…, sinon nom du vaccin normalisé) a un rappel
    // passé : une injection plus récente couvre le rappel précédent.
    String groupe(Map<String, dynamic> v) {
      final c = (v['categorie']?.toString() ?? '').trim().toLowerCase();
      return c.isNotEmpty ? c : (v['vaccin']?.toString() ?? '').toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    }
    final derniers = <String, Map<String, dynamic>>{};
    for (final v in _vaccins) {
      final k = groupe(v);
      final cur = derniers[k];
      if (cur == null || (_d(v['date']) ?? DateTime(1900)).isAfter(_d(cur['date']) ?? DateTime(1900))) derniers[k] = v;
    }
    final rappelsDepasses = derniers.values.where((v) => _d(v['date_rappel']) != null && _d(v['date_rappel'])!.isBefore(now)).toList();
    final prochainsRappels = derniers.values.where((v) => _d(v['date_rappel']) != null && !_d(v['date_rappel'])!.isBefore(now)).toList()
      ..sort((a, b) => _d(a['date_rappel'])!.compareTo(_d(b['date_rappel'])!));
    final alertes = <Widget>[
      for (final a in _allergies) _txt('Allergie : ${a['description'] ?? a['nom'] ?? ''}', c: _rouge),
      for (final v in rappelsDepasses.take(3))
        _ligneRappel(v, 'Rappel dépassé : ${v['vaccin'] ?? 'vaccin'} (${_date(v['date_rappel'])})', c: _rouge),
    ];
    final poids = _poids?['valeur'] ?? _poids?['poids'];
    return RefreshIndicator(
      onRefresh: _charger, color: _teal,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 40), children: [
        if (alertes.isNotEmpty)
          _carte('Alertes cliniques', Icons.warning_amber_rounded,
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: alertes)),
        _carte('Dernière consultation', Icons.medical_services_outlined, _derniereCr == null
            ? _discret('Aucun compte rendu.')
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _txt(_date(_derniereCr!['created_at']), w: FontWeight.w700, taille: 12.5),
                _txt((_derniereCr!['contenu']?.toString() ?? '').replaceAll(RegExp(r'<[^>]*>'), ' ').trim(), taille: 13),
              ])),
        _carte('Prochain rendez-vous', Icons.event_outlined,
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _rdv == null ? _discret('Aucun rendez-vous planifié.') : _txt(_rdvTexte(_rdv!)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 6, children: [
                if (_rdv != null)
                  OutlinedButton.icon(
                    onPressed: () => _ouvrirAgenda(ProAgendaPage(focusRdvId: _rdv!['id']?.toString(), modifierFocus: true)),
                    icon: const Icon(Icons.edit_calendar_outlined, size: 17),
                    label: const Text('Modifier', style: TextStyle(fontFamily: 'Galey')),
                    style: OutlinedButton.styleFrom(foregroundColor: _teal, visualDensity: VisualDensity.compact),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _planifier(),
                  icon: const Icon(Icons.event_available_outlined, size: 17),
                  label: Text(_rdv == null ? 'Planifier un RDV' : 'Autre RDV', style: const TextStyle(fontFamily: 'Galey')),
                  style: OutlinedButton.styleFrom(foregroundColor: _teal, visualDensity: VisualDensity.compact),
                ),
              ]),
            ])),
        _carte('Dernier poids connu', Icons.monitor_weight_outlined,
            poids == null ? _discret('Non renseigné.') : _txt('$poids kg · ${_date(_poids!['date'])}'),
            action: widget.peutEcrire
                ? TextButton.icon(
                    onPressed: _nouvellePesee,
                    icon: const Icon(Icons.add, size: 17),
                    label: const Text('Nouvelle pesée', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5)),
                    style: TextButton.styleFrom(foregroundColor: _teal, visualDensity: VisualDensity.compact),
                  )
                : null),
        _carte('Allergies', Icons.no_food_outlined, _allergies.isEmpty
            ? _discret('Non renseigné.')
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final a in _allergies) _txt('${a['description'] ?? a['nom'] ?? ''}${(a['severite']?.toString() ?? '').isNotEmpty ? ' (${a['severite']})' : ''}'),
              ])),
        _carte('Traitements actifs', Icons.medication_outlined, actifs.isEmpty
            ? _discret('Aucun traitement en cours.')
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final t in actifs) _txt('${t['nom'] ?? ''}${(t['posologie']?.toString() ?? '').isNotEmpty ? ' — ${t['posologie']}' : ''}'),
              ])),
        _carte('Vaccinations', Icons.vaccines_outlined, _vaccins.isEmpty
            ? _discret('Aucune vaccination enregistrée.')
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Une ligne par catégorie : dernière injection + prochain rappel.
                // Une ligne cliquable par vaccin à rappeler (rappel fait / RDV).
                for (final v in (derniers.values.toList()..sort((a, b) => (_d(b['date']) ?? DateTime(1900)).compareTo(_d(a['date']) ?? DateTime(1900)))))
                  if (_d(v['date_rappel']) != null)
                    _ligneRappel(v, '${v['vaccin'] ?? ''} — ${_date(v['date'])} · rappel ${_date(v['date_rappel'])}',
                        c: _d(v['date_rappel'])!.isBefore(now) ? _rouge : null)
                  else
                    _txt('${v['vaccin'] ?? ''} — ${_date(v['date'])}'),
                if (prochainsRappels.isNotEmpty)
                  _ligneRappel(prochainsRappels.first,
                      'Prochain rappel : ${prochainsRappels.first['vaccin'] ?? ''} le ${_date(prochainsRappels.first['date_rappel'])}', w: FontWeight.w700),
              ])),
        _carte('Antécédents', Icons.history_edu_outlined, _chirurgies.isEmpty
            ? _discret('Aucun antécédent chirurgical enregistré.')
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final c in _chirurgies.take(5)) _txt('${_date(c['date'])} — ${c['intitule'] ?? c['nom'] ?? c['type'] ?? 'Chirurgie'}'),
              ])),
        OutlinedButton.icon(
          onPressed: widget.onIdentite,
          icon: const Icon(Icons.badge_outlined, size: 18),
          label: const Text('Identité complète', style: TextStyle(fontFamily: 'Galey')),
        ),
      ]),
    );
  }
}

// ── Synthèse ostéopathe ──────────────────────────────────────────────────────

class SyntheseOsteoTab extends StatefulWidget {
  final String animalId;
  final VoidCallback onIdentite;
  final VoidCallback onSeances;
  const SyntheseOsteoTab({super.key, required this.animalId, required this.onIdentite, required this.onSeances});
  @override
  State<SyntheseOsteoTab> createState() => _SyntheseOsteoTabState();
}

class _SyntheseOsteoTabState extends State<SyntheseOsteoTab> {
  bool _loading = true;
  List<Map<String, dynamic>> _seances = [];
  Map<String, dynamic>? _rdv;

  @override
  void initState() { super.initState(); _charger(); }

  Future<void> _charger() async {
    final pid = User_Info.activeProfileId;
    try {
      final rows = _l(await Supabase.instance.client.from('suivis_morpho').select()
          .eq('animal_id', widget.animalId).eq('source', 'professionnel').order('date', ascending: false));
      _seances = pid.isEmpty ? rows : rows.where((s) => s['pro_profile_id']?.toString() == pid).toList();
    } catch (_) {}
    _rdv = await _prochainRdv(widget.animalId);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: _teal));
    final derniere = _seances.firstOrNull;
    final motif = _seances.map((s) => s['motif']?.toString() ?? '').firstWhere((m) => m.trim().isNotEmpty, orElse: () => '');
    final aFinaliser = _seances.where((s) => s['statut'] == 'brouillon').length;
    String champ(String k) => (derniere?[k]?.toString() ?? '').trim();
    return RefreshIndicator(
      onRefresh: _charger, color: _teal,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 40), children: [
        if (aFinaliser > 0)
          InkWell(
            onTap: widget.onSeances,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFFF4DC), borderRadius: BorderRadius.circular(12)),
              child: Text('$aFinaliser séance${aFinaliser > 1 ? 's' : ''} à finaliser',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF8A5A00))),
            ),
          ),
        _carte('Motif du suivi', Icons.flag_outlined, motif.isEmpty ? _discret('Non renseigné.') : _txt(motif)),
        _carte('Séances', Icons.self_improvement_outlined, derniere == null
            ? _discret('Aucune séance enregistrée.')
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _txt('${_seances.length} séance${_seances.length > 1 ? 's' : ''} réalisée${_seances.length > 1 ? 's' : ''}', w: FontWeight.w700),
                _txt('Dernière : ${_date(derniere['date'])} — ${titreCompteRendu(derniere['type_suivi']?.toString())}'),
                if ((derniere['lieu']?.toString() ?? '').isNotEmpty) _txt('Lieu : ${derniere['lieu']}'),
              ]), action: TextButton(onPressed: widget.onSeances, child: const Text('Voir', style: TextStyle(fontFamily: 'Galey')))),
        _carte('Principales observations', Icons.visibility_outlined,
            champ('observations_bilan').isEmpty && champ('intervention').isEmpty
                ? _discret('Aucune observation.')
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (champ('observations_bilan').isNotEmpty) _txt(champ('observations_bilan')),
                    if (champ('intervention').isNotEmpty) _txt('Intervention : ${champ('intervention')}'),
                  ])),
        _carte('Recommandations en cours', Icons.tips_and_updates_outlined,
            champ('suivi_recommande').isEmpty && champ('commentaires').isEmpty
                ? _discret('Aucune recommandation.')
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (champ('suivi_recommande').isNotEmpty) _txt(champ('suivi_recommande')),
                    if (champ('commentaires').isNotEmpty) _txt(champ('commentaires')),
                    if (champ('prochain_controle').isNotEmpty) _txt('Prochain contrôle : ${_date(champ('prochain_controle'))}', c: _ambre),
                  ])),
        _carte('Prochain rendez-vous', Icons.event_outlined, _rdv == null ? _discret('Aucun rendez-vous planifié.') : _txt(_rdvTexte(_rdv!))),
        OutlinedButton.icon(
          onPressed: widget.onIdentite,
          icon: const Icon(Icons.badge_outlined, size: 18),
          label: const Text('Identité complète', style: TextStyle(fontFamily: 'Galey')),
        ),
      ]),
    );
  }
}

// ── Documents (vétérinaire / ostéopathe) ─────────────────────────────────────

class DocumentsSanteProTab extends StatefulWidget {
  final String animalId;
  final String espece;
  final bool osteo;
  const DocumentsSanteProTab({super.key, required this.animalId, required this.espece, this.osteo = false});
  @override
  State<DocumentsSanteProTab> createState() => _DocumentsSanteProTabState();
}

class _DocumentsSanteProTabState extends State<DocumentsSanteProTab> {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _crs = [], _ordos = [], _seances = [];

  @override
  void initState() { super.initState(); _charger(); }

  Future<void> _charger() async {
    final id = widget.animalId;
    final pid = User_Info.activeProfileId;
    if (widget.osteo) {
      try {
        _seances = _l(await _supa.from('suivis_morpho').select().eq('animal_id', id).eq('source', 'professionnel')
            .neq('statut', 'brouillon').order('date', ascending: false))
            .where((s) => pid.isEmpty || s['pro_profile_id']?.toString() == pid).toList();
      } catch (_) {}
    } else {
      try { _crs = _l(await _supa.from('comptes_rendus').select().eq('animal_id', id).order('created_at', ascending: false)); } catch (_) {}
      try { _ordos = _l(await _supa.from('ordonnances').select().eq('animal_id', id).order('created_at', ascending: false)); } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  Widget _doc(String titre, String sous, {String? url, VoidCallback? onTap}) => ListTile(
        contentPadding: EdgeInsets.zero, dense: true,
        leading: Icon(url != null ? Icons.picture_as_pdf_outlined : Icons.description_outlined, color: _teal),
        title: Text(titre, style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, fontWeight: FontWeight.w600)),
        subtitle: sous.isEmpty ? null : Text(sous, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
        trailing: (url != null || onTap != null) ? const Icon(Icons.chevron_right) : null,
        onTap: onTap ?? (url == null ? null : () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: _teal));
    String extrait(dynamic v) => (v?.toString() ?? '').replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    String? url(Map<String, dynamic> m) => (m['doc_url']?.toString() ?? '').isEmpty ? null : m['doc_url'].toString();
    return RefreshIndicator(
      onRefresh: _charger, color: _teal,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 40), children: widget.osteo
          ? [
              _carte('Comptes rendus de séance (PDF)', Icons.article_outlined, _seances.isEmpty
                  ? _discret('Aucun compte rendu finalisé.')
                  : Column(children: [
                      for (final s in _seances)
                        _doc('${titreCompteRendu(s['type_suivi']?.toString())} — ${_date(s['date'])}', extrait(s['motif']),
                            onTap: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => MorphoDetailPage(suivi: s, espece: widget.espece)))),
                    ])),
              _discret('Chaque compte rendu s\'exporte en PDF depuis son détail ; il reste rattaché à sa séance et à l\'animal.'),
            ]
          : [
              _carte('Comptes rendus', Icons.article_outlined, _crs.isEmpty
                  ? _discret('Aucun compte rendu.')
                  : Column(children: [
                      for (final c in _crs) _doc('Compte rendu — ${_date(c['created_at'])}', extrait(c['contenu']), url: url(c)),
                    ])),
              _carte('Ordonnances', Icons.medication_outlined, _ordos.isEmpty
                  ? _discret('Aucune ordonnance.')
                  : Column(children: [
                      for (final o in _ordos) _doc('Ordonnance — ${_date(o['date_emit'] ?? o['created_at'])}', extrait(o['notes']), url: url(o)),
                    ])),
              _discret('Résultats et pièces jointes : rattachés à leur consultation (onglet Consultations).'),
            ]),
    );
  }
}
