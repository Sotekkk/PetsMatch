import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/utils/geocoding_helper.dart';
import 'package:PetsMatch/utils/prestations_education.dart';
import 'package:PetsMatch/utils/forfait_education.dart' show kTypesSeances, libelleTypeSeances;

// ── Prestations & tarifs (éducateur / comportementaliste) : seul endroit où se
// règlent les cours, les bilans, la règle du bilan préalable, les forfaits et
// les options tarifaires (supplément à domicile, autres lignes). La
// réservation (education_reservation_page.dart), la fiche publique
// (service_detail_page.dart) et le devis lisent ces mêmes données
// (utils/prestations_education.dart). Miroir site : app/education/prestations.

class EducationPrestationsPage extends StatefulWidget {
  const EducationPrestationsPage({super.key});

  @override
  State<EducationPrestationsPage> createState() => _EducationPrestationsPageState();
}

class _EducationPrestationsPageState extends State<EducationPrestationsPage> {
  static const _purple = Color(0xFF7B5EA7);
  static const _teal = Color(0xFF0C5C6C);
  static const _bg = Color(0xFFF8F8F6);
  final _supa = Supabase.instance.client;

  bool _loading = true;
  bool _saving = false;
  String _pid = '';
  List<Map<String, dynamic>> _prestations = [];
  List<Map<String, dynamic>> _forfaits = [];
  // Réglages du profil (user_profiles)
  bool _bilanRequis = true;
  bool _tarifsVisibles = false;
  Map<String, dynamic> _tarifs = {};
  final _bilanDescCtrl = TextEditingController();
  final _supplementCtrl = TextEditingController();
  final List<({TextEditingController label, TextEditingController prix, TextEditingController desc})> _extra = [];
  bool _reglagesModifies = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bilanDescCtrl.dispose();
    _supplementCtrl.dispose();
    for (final e in _extra) { e.label.dispose(); e.prix.dispose(); e.desc.dispose(); }
    super.dispose();
  }

  void _modifie() { if (!_reglagesModifies) setState(() => _reglagesModifies = true); }

  ({TextEditingController label, TextEditingController prix, TextEditingController desc}) _ligneExtra(
      {String label = '', String prix = '', String desc = ''}) {
    final l = (label: TextEditingController(text: label), prix: TextEditingController(text: prix), desc: TextEditingController(text: desc));
    for (final c in [l.label, l.prix, l.desc]) { c.addListener(_modifie); }
    return l;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    final pid = profilEducationId();
    try {
      var fq = _supa.from('forfaits_education').select('id, nom, nb_seances, prix, description, affiche_public, type_seances, nb_seances_indiv, nb_seances_coll')
          .eq('pro_uid', uid).eq('actif', true);
      if (pid.isNotEmpty) fq = fq.or('pro_profile_id.eq.$pid,pro_profile_id.is.null');
      final results = await Future.wait<dynamic>([
        chargerPrestationsEducation(uid, profileId: pid),
        fq.order('created_at'),
        pid.isEmpty ? Future.value(null) : _supa.from('user_profiles')
            .select('tarifs_education, tarifs_education_extra, tarifs_education_visibles, education_bilan_requis, education_bilan_description')
            .eq('id', pid).maybeSingle(),
      ]);
      final prof = results[2] as Map<String, dynamic>?;
      for (final e in _extra) { e.label.dispose(); e.prix.dispose(); e.desc.dispose(); }
      _extra.clear();
      if (prof != null) {
        _bilanRequis = prof['education_bilan_requis'] as bool? ?? true;
        _tarifsVisibles = prof['tarifs_education_visibles'] as bool? ?? false;
        _tarifs = prof['tarifs_education'] is Map ? Map<String, dynamic>.from(prof['tarifs_education'] as Map) : {};
        _bilanDescCtrl.text = prof['education_bilan_description']?.toString() ?? '';
        final sup = supplementDomicile(_tarifs);
        _supplementCtrl.text = sup > 0 ? sup.toStringAsFixed(sup == sup.roundToDouble() ? 0 : 2) : '';
        for (final e in (prof['tarifs_education_extra'] as List? ?? [])) {
          if (e is! Map) continue;
          _extra.add(_ligneExtra(label: e['label']?.toString() ?? '',
              prix: (e['prix'] as num?)?.toString() ?? '', desc: e['description']?.toString() ?? ''));
        }
      }
      if (!mounted) return;
      setState(() {
        _pid = pid;
        _prestations = results[0] as List<Map<String, dynamic>>;
        _forfaits = List<Map<String, dynamic>>.from(results[1] as List);
        _reglagesModifies = false;
        _loading = false;
      });
      _bilanDescCtrl.addListener(_modifie);
      _supplementCtrl.addListener(_modifie);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String t, {Color? couleur}) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(t, style: const TextStyle(fontFamily: 'Galey')), backgroundColor: couleur, behavior: SnackBarBehavior.floating));

  Future<void> _enregistrerReglages() async {
    if (_pid.isEmpty) return;
    setState(() => _saving = true);
    // Seules les colonnes de cette page : la grille de prix par type n'est plus
    // éditée (reprise en cours par la migration), domicile_supplement y reste.
    final tarifs = Map<String, dynamic>.from(_tarifs)
      ..['domicile_supplement'] = double.tryParse(_supplementCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    try {
      await _supa.from('user_profiles').update({
        'education_bilan_requis': _bilanRequis,
        'education_bilan_description': _bilanDescCtrl.text.trim(),
        'tarifs_education_visibles': _tarifsVisibles,
        'tarifs_education': tarifs,
        'tarifs_education_extra': [
          for (final e in _extra)
            if (e.label.text.trim().isNotEmpty) {
              'label': e.label.text.trim(),
              'prix': double.tryParse(e.prix.text.trim().replaceAll(',', '.')) ?? 0,
              if (e.desc.text.trim().isNotEmpty) 'description': e.desc.text.trim(),
            },
        ],
      }).eq('id', _pid);
      _tarifs = tarifs;
      if (mounted) { setState(() { _saving = false; _reglagesModifies = false; }); _snack('Enregistré'); }
    } catch (_) {
      if (mounted) { setState(() => _saving = false); _snack('Enregistrement impossible, réessayez.', couleur: Colors.red); }
    }
  }

  Future<void> _rechargerCours() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final l = await chargerPrestationsEducation(uid, profileId: _pid);
    if (mounted) setState(() => _prestations = l);
  }

  Future<void> _basculer(Map<String, dynamic> p, String champ) async {
    final v = p[champ] == false;
    setState(() => p[champ] = v);
    await _supa.from('prestations_education').update({champ: v}).eq('id', p['id']);
  }

  Future<bool> _confirmer(String titre, String texte) async => await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(titre, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          content: Text(texte, style: const TextStyle(fontFamily: 'Galey')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            TextButton(onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
          ],
        ),
      ) ?? false;

  Future<void> _supprimer(Map<String, dynamic> p) async {
    if (!await _confirmer('Supprimer ce cours ?', '« ${p['nom']} » ne sera plus proposé. Les RDV déjà pris ne sont pas modifiés.')) return;
    await _supa.from('prestations_education').update({'actif': false}).eq('id', p['id']);
    if (mounted) setState(() => _prestations.removeWhere((x) => x['id'] == p['id']));
  }

  Future<void> _openForm({Map<String, dynamic>? existing}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PrestationForm(existing: existing, profileId: _pid),
    );
    if (result == true) await _rechargerCours();
  }

  Future<void> _ajouterForfait() async {
    final nom = TextEditingController(), nb = TextEditingController(text: '5'), prix = TextEditingController(), desc = TextEditingController();
    var typeSeances = 'mixte';
    // Forfait mixte : tant de séances individuelles + tant de collectives.
    final indivCtrl = TextEditingController(), collCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        title: const Text('Nouveau forfait', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nom, decoration: const InputDecoration(labelText: 'Nom (ex : Pack 5 séances)')),
          TextField(controller: nb, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Nombre de séances')),
          TextField(controller: prix, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Prix total (€)')),
          DropdownButtonFormField<String>(
            initialValue: typeSeances,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Séances couvertes'),
            items: [for (final t in kTypesSeances) DropdownMenuItem(value: t.$1, child: Text(t.$2))],
            onChanged: (v) => setD(() => typeSeances = v ?? 'mixte'),
          ),
          if (typeSeances == 'mixte') Row(children: [
            Expanded(child: TextField(controller: indivCtrl, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Séances individuelles'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: collCtrl, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Séances collectives'))),
          ]),
          TextField(controller: desc, decoration: const InputDecoration(labelText: 'Description (optionnel)')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Valider')),
        ],
      )),
    );
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (ok == true && nom.text.trim().isNotEmpty && uid != null) {
      final reparti = typeSeances == 'mixte' && (indivCtrl.text.trim().isNotEmpty || collCtrl.text.trim().isNotEmpty);
      final indiv = int.tryParse(indivCtrl.text.trim()) ?? 0, coll = int.tryParse(collCtrl.text.trim()) ?? 0;
      final row = await _supa.from('forfaits_education').insert({
        'pro_uid': uid, if (_pid.isNotEmpty) 'pro_profile_id': _pid, 'nom': nom.text.trim(),
        'nb_seances': reparti ? (indiv + coll > 0 ? indiv + coll : 1) : (int.tryParse(nb.text.trim()) ?? 1),
        if (reparti) 'nb_seances_indiv': indiv,
        if (reparti) 'nb_seances_coll': coll,
        'prix': double.tryParse(prix.text.trim().replaceAll(',', '.')) ?? 0,
        if (desc.text.trim().isNotEmpty) 'description': desc.text.trim(),
        'affiche_public': true,
        'type_seances': typeSeances,
      }).select('id, nom, nb_seances, prix, description, affiche_public, type_seances, nb_seances_indiv, nb_seances_coll').maybeSingle();
      if (row != null && mounted) setState(() => _forfaits.add(Map<String, dynamic>.from(row)));
    }
    for (final c in [nom, nb, prix, desc, indivCtrl, collCtrl]) { c.dispose(); }
  }

  Future<void> _supprimerForfait(Map<String, dynamic> f) async {
    if (!await _confirmer('Supprimer ce forfait ?', '« ${f['nom']} » ne sera plus proposé. Les forfaits déjà souscrits continuent.')) return;
    await _supa.from('forfaits_education').update({'actif': false}).eq('id', f['id']);
    if (mounted) setState(() => _forfaits.removeWhere((x) => x['id'] == f['id']));
  }

  Future<void> _basculerForfait(Map<String, dynamic> f) async {
    final v = f['affiche_public'] != true;
    setState(() => f['affiche_public'] = v);
    await _supa.from('forfaits_education').update({'affiche_public': v}).eq('id', f['id']);
  }

  Widget _bloc(String titre, {String? sousTitre, Widget? action, required List<Widget> children}) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titre, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
              if (sousTitre != null) Padding(padding: const EdgeInsets.only(top: 2),
                  child: Text(sousTitre, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade600))),
            ])),
            if (action != null) action,
          ]),
          const SizedBox(height: 10),
          ...children,
        ]),
      );

  Widget _pastille(String t, {bool actif = true, bool ambre = false, VoidCallback? onTap}) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: ambre ? const Color(0xFFFEF3C7) : actif ? _purple.withValues(alpha: 0.1) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(t, style: TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w600,
              color: ambre ? const Color(0xFF92400E) : actif ? _purple : Colors.grey.shade600)),
        ),
      );

  Widget _interrupteur(String label, String hint, bool v, ValueChanged<bool> onChanged) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: v, activeThumbColor: _purple, onChanged: onChanged,
        title: Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text(hint, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade600)),
      );

  String _eur(num v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  Widget _carteCours(Map<String, dynamic> p) {
    final prix = p['prix'] as num?;
    final actif = p['reservable'] != false;
    final public = p['affiche_public'] != false;
    final collectif = p['type'] == 'collectif';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Opacity(
        opacity: actif ? 1 : 0.75,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: () => _openForm(existing: p),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p['nom']?.toString() ?? '', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
                Text('${typeAffiche(p)}${collectif ? ' (max ${p['capacite_max'] ?? 6})' : ''} · ${p['duree_minutes']} min'
                    '${prix != null ? ' · ${_eur(prix)} € ${uniteTarif(p)}' : ' · prix non renseigné'}',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
              ])),
              const Text('Modifier', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: _teal)),
            ]),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _pastille(actif ? 'Actif' : 'En pause', ambre: !actif, onTap: () => _basculer(p, 'reservable')),
            _pastille(public ? 'Prix sur la fiche' : 'Prix masqué', actif: public, onTap: () => _basculer(p, 'affiche_public')),
            if (p['domicile_ok'] != false) _pastille('À domicile possible', actif: false),
            if (p['bilan_requis'] != true && p['sans_bilan_prealable'] == true) _pastille('Sans bilan préalable', actif: false),
            GestureDetector(onTap: () => _supprimer(p),
                child: Text('Supprimer', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500))),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final aVerifier = _prestations.where((p) => p['reservable'] == false
        && (p['description']?.toString() ?? '').startsWith('Repris de votre ancienne grille')).length;
    final bilansActifs = _prestations.where((p) => p['bilan_requis'] == true && p['reservable'] != false).length;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _purple,
        foregroundColor: Colors.white,
        title: const Text('Prestations & tarifs', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
      ),
      bottomNavigationBar: _loading || !_reglagesModifies ? null : SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: ElevatedButton(
            onPressed: _saving ? null : _enregistrerReglages,
            style: ElevatedButton.styleFrom(backgroundColor: _teal, padding: const EdgeInsets.symmetric(vertical: 14)),
            child: const Text('Enregistrer le bilan, les options et l\'affichage',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _purple))
          : RefreshIndicator(
              onRefresh: _load,
              color: _purple,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Text('Vos cours, bilans, forfaits et options : ce sont ces prix qui s\'affichent sur votre fiche, dans les réservations et dans vos devis.',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade700)),
                const SizedBox(height: 12),
                if (aVerifier > 0)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFF3D9A4))),
                    child: Text('$aVerifier cours ${aVerifier > 1 ? 'ont été repris' : 'a été repris'} de votre ancienne grille de tarifs. '
                        'Ils sont en pause : vérifiez-les, puis activez ceux que vous proposez.',
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF92400E))),
                  ),
                _bloc('Cours et bilans',
                    sousTitre: 'La famille les choisit dans le calendrier de réservation de votre fiche.',
                    action: TextButton(onPressed: () => _openForm(),
                        child: const Text('Ajouter', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: _purple))),
                    children: [
                      if (_prestations.isEmpty)
                        Text('Aucun cours configuré.', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500))
                      else
                        for (final p in _prestations) _carteCours(p),
                    ]),
                _bloc('Bilan préalable',
                    sousTitre: 'Vérifié à chaque réservation : un client sans séance confirmée ou terminée avec vous est un nouveau client.',
                    children: [
                      _interrupteur('Bilan obligatoire avant les autres cours',
                          'Un nouveau client ne peut réserver qu\'un bilan, ou un cours marqué « Réservable sans bilan préalable »',
                          _bilanRequis, (v) { setState(() => _bilanRequis = v); _modifie(); }),
                      if (_bilanRequis && bilansActifs == 0)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text('Aucun bilan actif dans vos cours : les nouveaux clients verront tous vos cours. Ajoutez un cours de type « Bilan ».',
                              style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.orange)),
                        ),
                      TextField(controller: _bilanDescCtrl, maxLines: 3, style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                          decoration: const InputDecoration(labelText: 'Présentation du bilan (déroulé, ce qu\'il faut prévoir)', border: OutlineInputBorder())),
                    ]),
                _bloc('Forfaits',
                    sousTitre: 'Plusieurs séances à un prix global. Appliqué au client depuis le dossier de la séance ; les séances utilisées sont décomptées.',
                    action: TextButton(onPressed: _ajouterForfait,
                        child: const Text('Ajouter', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: _purple))),
                    children: [
                      if (_forfaits.isEmpty)
                        Text('Aucun forfait.', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500))
                      else
                        for (final f in _forfaits)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(children: [
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(f['nom']?.toString() ?? '', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13)),
                                Text('${f['nb_seances_indiv'] != null || f['nb_seances_coll'] != null
                                    ? '${f['nb_seances_indiv'] ?? 0} individuelle(s) + ${f['nb_seances_coll'] ?? 0} collective(s)'
                                    : '${f['nb_seances']} séance${((f['nb_seances'] as num?) ?? 1) > 1 ? 's' : ''} · ${libelleTypeSeances(f['type_seances']?.toString())}'} · ${_eur((f['prix'] as num?) ?? 0)} €',
                                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                              ])),
                              _pastille(f['affiche_public'] == true ? 'Sur la fiche' : 'Masqué', actif: f['affiche_public'] == true,
                                  onTap: () => _basculerForfait(f)),
                              IconButton(icon: Icon(Icons.delete_outline, size: 20, color: Colors.grey.shade500),
                                  tooltip: 'Supprimer', onPressed: () => _supprimerForfait(f)),
                            ]),
                          ),
                    ]),
                _bloc('Options tarifaires',
                    sousTitre: 'S\'ajoutent au prix d\'un cours. Le supplément à domicile est ajouté automatiquement aux réservations à domicile.',
                    children: [
                      SizedBox(width: 200, child: TextField(controller: _supplementCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                          decoration: const InputDecoration(labelText: 'Supplément à domicile (€)', border: OutlineInputBorder()))),
                      const SizedBox(height: 12),
                      for (var i = 0; i < _extra.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Column(children: [
                            Row(children: [
                              Expanded(child: TextField(controller: _extra[i].label, style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                                  decoration: const InputDecoration(labelText: 'Option', isDense: true, border: OutlineInputBorder()))),
                              const SizedBox(width: 8),
                              SizedBox(width: 80, child: TextField(controller: _extra[i].prix,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                                  decoration: const InputDecoration(labelText: '€', isDense: true, border: OutlineInputBorder()))),
                              IconButton(icon: Icon(Icons.close, size: 18, color: Colors.grey.shade500), tooltip: 'Retirer',
                                  onPressed: () { final l = _extra.removeAt(i); setState(() {}); _modifie();
                                    WidgetsBinding.instance.addPostFrameCallback((_) { l.label.dispose(); l.prix.dispose(); l.desc.dispose(); }); }),
                            ]),
                            const SizedBox(height: 6),
                            TextField(controller: _extra[i].desc, style: const TextStyle(fontFamily: 'Galey', fontSize: 12),
                                decoration: const InputDecoration(labelText: 'Description (facultatif)', isDense: true, border: OutlineInputBorder())),
                          ]),
                        ),
                      TextButton(onPressed: () { setState(() => _extra.add(_ligneExtra())); _modifie(); },
                          child: const Text('Ajouter une option', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: _purple))),
                    ]),
                _bloc('Affichage sur ma fiche publique', children: [
                  _interrupteur('Afficher mes tarifs', 'Cours dont le prix est affiché, options et forfaits affichés',
                      _tarifsVisibles, (v) { setState(() => _tarifsVisibles = v); _modifie(); }),
                ]),
                const SizedBox(height: 60),
              ]),
            ),
    );
  }
}

class _PrestationForm extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final String profileId;
  const _PrestationForm({this.existing, required this.profileId});

  @override
  State<_PrestationForm> createState() => _PrestationFormState();
}

class _PrestationFormState extends State<_PrestationForm> {
  static const _purple = Color(0xFF7B5EA7);
  final _supa = Supabase.instance.client;

  late final TextEditingController _nomCtrl;
  late final TextEditingController _dureeCtrl;
  late final TextEditingController _prixCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _capaciteCtrl;
  late final TextEditingController _lieuCtrl;
  late final TextEditingController _conditionsCtrl;
  double? _lieuLat, _lieuLng;
  bool _lieuGeocoding = false;
  // true tant que _lieuCtrl n'a pas changé depuis le dernier géocodage
  // réussi (bouton "Localiser" ou soumission précédente) — sert à afficher
  // la confirmation "coordonnées GPS enregistrées" de façon fiable.
  bool _lieuGeocoded = false;
  late bool _domicileOk;
  late bool _reservable;
  late bool _affichePublic;
  late bool _sansBilan;
  /// 'individuel' | 'collectif' | 'bilan' (bilan = individuel + bilan_requis).
  late String _type;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nomCtrl = TextEditingController(text: e?['nom']?.toString() ?? '');
    _dureeCtrl = TextEditingController(text: (e?['duree_minutes'] as num?)?.toString() ?? '60');
    _prixCtrl = TextEditingController(text: (e?['prix'] as num?)?.toString() ?? '');
    _descCtrl = TextEditingController(text: e?['description']?.toString() ?? '');
    _capaciteCtrl = TextEditingController(text: (e?['capacite_max'] as num?)?.toString() ?? '6');
    _lieuCtrl = TextEditingController(text: e?['lieu_adresse']?.toString() ?? '');
    _lieuLat = (e?['lieu_lat'] as num?)?.toDouble();
    _lieuLng = (e?['lieu_lng'] as num?)?.toDouble();
    _lieuGeocoded = _lieuLat != null && _lieuLng != null;
    _lieuCtrl.addListener(() { if (_lieuGeocoded) setState(() => _lieuGeocoded = false); });
    _conditionsCtrl = TextEditingController(text: e?['conditions']?.toString() ?? '');
    _domicileOk = e?['domicile_ok'] != false;
    _reservable = e?['reservable'] != false;
    _affichePublic = e?['affiche_public'] != false;
    _sansBilan = e?['sans_bilan_prealable'] == true;
    _type = e?['bilan_requis'] == true ? 'bilan' : e?['type']?.toString() ?? 'individuel';
  }

  @override
  void dispose() {
    for (final c in [_nomCtrl, _dureeCtrl, _prixCtrl, _descCtrl, _capaciteCtrl, _lieuCtrl, _conditionsCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  // Géocode explicitement l'adresse saisie (bouton « Localiser ») — donne
  // une confirmation visible (✓ coordonnées GPS) au lieu du géocodage
  // silencieux à la soumission, qui ne montrait jamais si ça avait marché.
  // Même pattern que _geocoderDomicile (education_reservation_page.dart).
  Future<void> _geocoderLieu() async {
    final adresse = _lieuCtrl.text.trim();
    if (adresse.isEmpty) return;
    setState(() => _lieuGeocoding = true);
    final geo = await GeocodingHelper.geocode(adresse);
    if (!mounted) return;
    setState(() {
      _lieuLat = geo?.lat;
      _lieuLng = geo?.lng;
      _lieuGeocoding = false;
      _lieuGeocoded = geo != null;
    });
    if (geo == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Adresse introuvable — vérifiez l\'orthographe ou précisez la ville.', style: TextStyle(fontFamily: 'Galey')),
        backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _submit() async {
    if (_nomCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Donnez un nom à ce cours.', style: TextStyle(fontFamily: 'Galey')),
        backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _saving = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _saving = false); return; }
    try {
      // Géocode l'adresse du cours si elle a changé.
      final lieu = _lieuCtrl.text.trim();
      if (lieu.isEmpty) {
        _lieuLat = null; _lieuLng = null;
      } else if (lieu != (widget.existing?['lieu_adresse']?.toString() ?? '') || _lieuLat == null) {
        final geo = await GeocodingHelper.geocode(lieu);
        _lieuLat = geo?.lat;
        _lieuLng = geo?.lng;
      }
      final collectif = _type == 'collectif', bilan = _type == 'bilan';
      // Les RDV déjà pris gardent leur prix (rdv.prix_calcule) : changer un
      // tarif ici ne touche que les prochaines réservations.
      final data = {
        'pro_uid': uid,
        if (widget.existing == null && widget.profileId.isNotEmpty) 'pro_profile_id': widget.profileId,
        'nom': _nomCtrl.text.trim(),
        'type': collectif ? 'collectif' : 'individuel',
        'duree_minutes': int.tryParse(_dureeCtrl.text.trim()) ?? 60,
        'prix': double.tryParse(_prixCtrl.text.trim().replaceAll(',', '.')),
        'bilan_requis': bilan,
        'domicile_ok': _domicileOk,
        'capacite_max': collectif ? (int.tryParse(_capaciteCtrl.text.trim()) ?? 6) : null,
        'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'reservable': _reservable,
        'affiche_public': _affichePublic,
        'sans_bilan_prealable': bilan ? false : _sansBilan,
        'conditions': _conditionsCtrl.text.trim().isEmpty ? null : _conditionsCtrl.text.trim(),
        'lieu_adresse': lieu.isEmpty ? null : lieu,
        'lieu_lat': _lieuLat,
        'lieu_lng': _lieuLng,
      };
      if (widget.existing != null) {
        await _supa.from('prestations_education').update(data).eq('id', widget.existing!['id']);
      } else {
        await _supa.from('prestations_education').insert(data);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey'))));
      }
    }
  }

  // Interrupteur toujours visible (fond + bordure colorés à l'état actif) —
  // un Switch seul se voit mal sur fond blanc quand il est désactivé.
  Widget _toggleCard({required bool value, required ValueChanged<bool> onChanged, required String label, required String hint}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: value ? _purple.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: value ? _purple : Colors.grey.shade300),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600,
              color: value ? _purple : Colors.black87)),
          const SizedBox(height: 2),
          Text(hint, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade600)),
        ])),
        const SizedBox(width: 8),
        Switch(value: value, activeThumbColor: _purple, onChanged: onChanged),
      ]),
    );
  }

  Widget _field(TextEditingController ctrl, String label, {TextInputType? type}) => TextField(
    controller: ctrl,
    keyboardType: type,
    style: const TextStyle(fontFamily: 'Galey'),
    decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.existing != null ? 'Modifier le cours' : 'Nouveau cours',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 16),
          Row(children: [
            for (final t in [('individuel', 'Individuel'), ('collectif', 'Collectif'), ('bilan', 'Bilan')])
              Expanded(child: Padding(
                padding: EdgeInsets.only(right: t.$1 == 'bilan' ? 0 : 8),
                child: GestureDetector(
                  onTap: () => setState(() => _type = t.$1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: _type == t.$1 ? _purple.withValues(alpha: 0.1) : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _type == t.$1 ? _purple : Colors.grey.shade300, width: _type == t.$1 ? 2 : 1),
                    ),
                    child: Center(child: Text(t.$2, style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                        color: _type == t.$1 ? _purple : Colors.grey.shade600))),
                  ),
                ),
              )),
          ]),
          if (_type == 'bilan')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Un bilan est le seul cours proposé à un nouveau client quand le bilan préalable est obligatoire.',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade600)),
            ),
          const SizedBox(height: 12),
          _field(_nomCtrl, _type == 'bilan' ? 'Nom du bilan' : 'Nom du cours'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _field(_dureeCtrl, 'Durée (min)', type: TextInputType.number)),
            const SizedBox(width: 8),
            Expanded(child: _field(_prixCtrl, _type == 'collectif' ? 'Prix (€ par participant)' : 'Prix (€ par séance)',
                type: const TextInputType.numberWithOptions(decimal: true))),
          ]),
          if (_type == 'collectif') ...[
            const SizedBox(height: 12),
            _field(_capaciteCtrl, 'Capacité maximale (participants)', type: TextInputType.number),
          ],
          const SizedBox(height: 12),
          TextField(controller: _descCtrl, maxLines: 2, style: const TextStyle(fontFamily: 'Galey'),
              decoration: const InputDecoration(labelText: 'Description (optionnel)', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _lieuCtrl, style: const TextStyle(fontFamily: 'Galey'),
              decoration: const InputDecoration(
                labelText: 'Lieu du cours (adresse, optionnel)',
                helperText: 'Ex. « Parc de la Tête d\'Or, Lyon ». Laissez vide = à votre cabinet.',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              )),
          const SizedBox(height: 6),
          // Géocodage explicite + confirmation visible — sans ça, impossible
          // de savoir si l'adresse tapée a bien donné des coordonnées GPS
          // (nécessaires côté client pour le lien « Itinéraire »).
          Row(children: [
            TextButton.icon(
              onPressed: (_lieuGeocoding || _lieuCtrl.text.trim().isEmpty) ? null : _geocoderLieu,
              icon: _lieuGeocoding
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _purple))
                  : const Icon(Icons.my_location, size: 16, color: _purple),
              label: const Text('Localiser', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, color: _purple)),
            ),
            if (_lieuGeocoded) ...[
              const SizedBox(width: 4),
              const Icon(Icons.check_circle, size: 14, color: Colors.green),
              const SizedBox(width: 4),
              const Text('Coordonnées GPS enregistrées', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.green)),
            ],
          ]),
          const SizedBox(height: 10),
          _toggleCard(
            value: _domicileOk,
            onChanged: (v) => setState(() => _domicileOk = v),
            label: 'Peut être proposé à domicile',
            hint: 'La famille pourra le demander à domicile sur les créneaux que vous autorisez (supplément à domicile ajouté s\'il est défini)',
          ),
          if (_type != 'bilan') ...[
            const SizedBox(height: 8),
            _toggleCard(
              value: _sansBilan,
              onChanged: (v) => setState(() => _sansBilan = v),
              label: 'Réservable sans bilan préalable',
              hint: 'Exception : un nouveau client peut le réserver même si le bilan préalable est obligatoire',
            ),
          ],
          const SizedBox(height: 12),
          TextField(controller: _conditionsCtrl, maxLines: 2, style: const TextStyle(fontFamily: 'Galey'),
              decoration: const InputDecoration(labelText: 'Conditions de réservation (optionnel)',
                  hintText: 'Ex : chiot de moins de 6 mois, vaccins à jour', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          _toggleCard(
            value: _reservable,
            onChanged: (v) => setState(() => _reservable = v),
            label: 'Actif',
            hint: 'Désactivé = en pause : ni réservable, ni affiché sur votre fiche',
          ),
          const SizedBox(height: 8),
          _toggleCard(
            value: _affichePublic,
            onChanged: (v) => setState(() => _affichePublic = v),
            label: 'Prix affiché sur ma fiche publique',
            hint: 'Dans la liste des tarifs, si l\'affichage des tarifs est activé',
          ),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _saving ? null : _submit,
            style: ElevatedButton.styleFrom(backgroundColor: _purple, padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(widget.existing != null ? 'Enregistrer' : 'Créer le cours',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
          )),
        ]),
      ),
    );
  }
}
