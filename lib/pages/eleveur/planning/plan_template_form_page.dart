import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/services/planning_service.dart';
import 'package:PetsMatch/utils/protocoles.dart';
import 'package:PetsMatch/widgets/animal_picker_sheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ════════════════════════════════════════════════════════════════════════════════
// PAGE FORMULAIRE PROTOCOLE — 3 blocs : informations générales, périmètre
// concerné, étapes. Miroir site : TemplateFormModal (elevage/planning).
// ════════════════════════════════════════════════════════════════════════════════

class PlanTemplateFormPage extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final String? profilSource;
  // Contexte "employé agissant pour un employeur" : quand renseigné, le
  // protocole créé appartient à cet employeur (uid_eleveur/eleveur_profile_id)
  // mais garde la trace du créateur réel (created_by_uid/profile_id).
  final String? employerUid;
  final String? employerProfileId;
  const PlanTemplateFormPage({
    super.key, this.existing, this.profilSource,
    this.employerUid, this.employerProfileId,
  });
  @override
  State<PlanTemplateFormPage> createState() => _PlanTemplateFormPageState();
}

const _teal = Color(0xFF0C5C6C);
const _dark = Color(0xFF1F2A2E);

class _PlanTemplateFormPageState extends State<PlanTemplateFormPage> {
  final _nomCtrl  = TextEditingController();
  final _descCtrl = TextEditingController();
  final _lieuCtrl = TextEditingController();

  String _type            = 'sanitaire';
  String _espece          = '';
  String _perimetre       = 'animal';
  String _categorie       = 'femelles';
  String _refEvent        = 'manuel';
  String _declencheurAuto = '';
  bool   _saving          = false;
  List<Map<String, dynamic>> _selectedAnimaux = [];

  static const _lieuxBase = ['Cuisine', 'Salle de soins', 'Salle de quarantaine', 'Jardin', 'Couloir', 'Nurserie'];
  List<String> _lieux = const ['Chatterie', 'Chenil', 'Box', ..._lieuxBase];

  final List<_EtapeCtrl> _etapes = [];

  static const _types = [
    ('sanitaire', 'Sanitaire'), ('alimentaire', 'Alimentaire'), ('nettoyage', 'Désinfection'),
    ('materiel', 'Matériel'), ('promenade', 'Promenade / Socialisation'), ('toilettage', 'Toilettage'),
  ];
  // Pet-sitter : pas d'alimentation (onglet dédié) ni de toilettage.
  static const _typesGarde = [
    ('sanitaire', 'Sanitaire'), ('nettoyage', 'Nettoyage'), ('materiel', 'Matériel'), ('promenade', 'Promenade'),
  ];
  static const _especes = ['', 'chien', 'chat', 'cheval', 'lapin', 'oiseau', 'nac', 'ovin', 'caprin', 'porcin'];

  String get _profilSource => widget.profilSource ?? User_Info.activeType;
  // Association / pension : pas d'élevage contrôlé (saillie, mise bas).
  bool get _isAssociation => _profilSource != 'eleveur';
  // Pet-sitter : pas de cheptel ni de reproduction.
  bool get _isGarde => _profilSource == 'garde';
  bool get _isPension => _profilSource == 'pension';

  String get _cible => cibleTypePour(_perimetre, _categorie);
  bool get _usesAge => _refEvent == 'age_semaines' || _cible == 'bebes';

  List<(String, String, String)> get _perimetresDispo => kPerimetres.where((p) =>
      _isGarde ? (p.$1 == 'animal' || p.$1 == 'locaux') : _isPension ? p.$1 != 'portee' : true).toList();

  List<(String, String)> get _categoriesDispo => kCategoriesProtocole.where((c) =>
      !(_isAssociation && c.$1 == 'gestantes') && !(_isPension && c.$1 == 'bebes')).toList();

  List<(String, String, String)> get _refEventsDispo => kRefEvents.where((r) {
    if ((_isAssociation || _isGarde) && (r.$1 == 'saillie' || r.$1 == 'mise_bas')) return false;
    if ((_isPension || _isGarde) && r.$1 == 'naissance') return false;
    if (_cible == 'gestantes') return ['mise_bas', 'saillie', 'manuel'].contains(r.$1);
    if (_cible == 'bebes') return ['naissance', 'age_semaines'].contains(r.$1);
    if (_perimetre == 'portee') return ['naissance', 'age_semaines', 'manuel'].contains(r.$1);
    return r.$1 != 'age_semaines';
  }).toList();

  void _ajusterRefEvent() {
    if (_perimetre == 'locaux') { _refEvent = 'manuel'; return; }
    final dispo = _refEventsDispo;
    if (!dispo.any((r) => r.$1 == _refEvent)) _refEvent = dispo.isNotEmpty ? dispo.first.$1 : 'manuel';
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nomCtrl.text    = e['nom'] ?? '';
      _descCtrl.text   = e['description'] ?? '';
      _lieuCtrl.text   = e['lieu'] ?? '';
      _type            = e['type'] ?? 'sanitaire';
      _espece          = e['espece'] ?? '';
      _perimetre       = perimetreDe(e, profilSource: _profilSource);
      final c = (e['cible_type'] ?? '').toString();
      if (kCategoriesProtocole.any((k) => k.$1 == c)) _categorie = c;
      _refEvent        = e['reference_event'] ?? 'manuel';
      _declencheurAuto = e['declencheur_auto'] ?? '';
      final etapesData = e['plan_template_etapes'];
      if (etapesData is List) {
        final tri = etapesData.map((x) => Map<String, dynamic>.from(x as Map)).toList()
          ..sort((a, b) => ((a['ordre'] as num?) ?? 0).compareTo((b['ordre'] as num?) ?? 0));
        for (final et in tri) {
          _etapes.add(_EtapeCtrl.fromData(et));
        }
      }
      final defaultIds = e['default_animal_ids'];
      if (defaultIds is List && defaultIds.isNotEmpty) {
        _loadDefaultAnimaux(defaultIds.map((id) => id.toString()).toList());
      }
    }
    if (_etapes.isEmpty) _etapes.add(_EtapeCtrl());
    _loadBoxes();
  }

  Future<void> _loadDefaultAnimaux(List<String> ids) async {
    try {
      final rows = await Supabase.instance.client.from('animaux')
          .select('id, nom, espece, photo_url').inFilter('id', ids);
      if (mounted) setState(() => _selectedAnimaux = List<Map<String, dynamic>>.from(rows));
    } catch (_) {}
  }

  Future<void> _pickAnimaux() async {
    final uid = widget.employerUid ?? FirebaseAuth.instance.currentUser?.uid;
    final pid = widget.employerProfileId ?? User_Info.activeProfileId;
    final result = await AnimalPickerSheet.pickMany(
      context, uid: uid, profileId: pid.isNotEmpty ? pid : null,
      current: _selectedAnimaux, accentColor: _teal, showPortees: false,
    );
    if (result != null && mounted) setState(() => _selectedAnimaux = result);
  }

  Future<void> _loadBoxes() async {
    final uid = widget.employerUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final supa = Supabase.instance.client;
      final profileData = await supa.from('user_profiles_complet').select('id')
          .eq('uid', uid).eq('is_main', true).maybeSingle();
      final profileId = profileData?['id'] as String?;
      final qBase = supa.from('chenil_boxes').select('nom');
      final rows = await (profileId != null
          ? qBase.eq('profile_id', profileId).order('nom')
          : qBase.eq('association_uid', uid).order('nom'));
      final boxNames = (rows as List).map((r) => r['nom']?.toString() ?? '').where((n) => n.isNotEmpty).toList();
      if (mounted && boxNames.isNotEmpty) setState(() => _lieux = [...boxNames, ..._lieuxBase]);
    } catch (_) {}
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _descCtrl.dispose();
    _lieuCtrl.dispose();
    for (final e in _etapes) { e.dispose(); }
    super.dispose();
  }

  void _deplacer(int i, int d) {
    final j = i + d;
    if (j < 0 || j >= _etapes.length) return;
    setState(() { final x = _etapes[i]; _etapes[i] = _etapes[j]; _etapes[j] = x; });
  }

  Future<void> _save() async {
    if (_nomCtrl.text.trim().isEmpty) { _snack('Le nom du protocole est requis'); return; }
    if (_etapes.any((e) => e.actionCtrl.text.trim().isEmpty)) { _snack('Indiquez l’action de chaque étape'); return; }
    setState(() => _saving = true);
    final locaux = _perimetre == 'locaux';
    final etapesData = [
      for (var i = 0; i < _etapes.length; i++) _etapes[i].toMap(ordre: i, usesAge: _usesAge),
    ];
    final lieu = locaux && _lieuCtrl.text.trim().isNotEmpty ? _lieuCtrl.text.trim() : null;
    final auto = (locaux || _declencheurAuto.isEmpty) ? null : _declencheurAuto;
    final defaultIds = (_perimetre == 'animal' && _selectedAnimaux.isNotEmpty)
        ? _selectedAnimaux.map((a) => a['id'].toString()).toList() : null;
    final espece = (locaux || _espece.isEmpty) ? null : _espece;
    final desc = _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim();
    final refEvent = locaux ? 'manuel' : _refEvent;

    Future<void> enregistrer(String cible) async {
      if (widget.existing != null) {
        await PlanningService.updateTemplate(
          templateId: widget.existing!['id'] as String, nom: _nomCtrl.text.trim(),
          espece: espece, description: desc, lieu: lieu, cibleType: cible, referenceEvent: refEvent,
          declencheurAuto: auto, defaultAnimalIds: defaultIds, etapes: etapesData,
        );
      } else {
        final currentUid = FirebaseAuth.instance.currentUser!.uid;
        await PlanningService.createTemplate(
          uid: widget.employerUid ?? currentUid, nom: _nomCtrl.text.trim(), type: _type,
          espece: espece, description: desc, lieu: lieu, cibleType: cible, referenceEvent: refEvent,
          declencheurAuto: auto, defaultAnimalIds: defaultIds, etapes: etapesData,
          profilSourceOverride: widget.profilSource,
          eleveurProfileIdOverride: widget.employerProfileId,
          createdByUid: currentUid,
          createdByProfileId: User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null,
        );
      }
    }

    try {
      try {
        await enregistrer(_cible);
      } on PostgrestException catch (e) {
        // Base pas encore migrée (portée / locaux absents de la contrainte
        // cible_type, migration_plan_templates_perimetre.sql) : « locaux »
        // s'enregistre à l'ancienne (cheptel, relu comme locaux pour un
        // nettoyage / matériel) ; « portée » est refusée.
        if (e.code != '23514' || (_cible != 'locaux' && _cible != 'portee')) rethrow;
        if (_cible == 'portee') throw 'Le périmètre « Portée » sera disponible après la mise à jour de la base.';
        if (_type != 'nettoyage' && _type != 'materiel') {
          throw 'Pour l’instant, « Locaux / matériel » n’est possible qu’avec un protocole Désinfection ou Matériel.';
        }
        await enregistrer('cheptel');
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      _snack(e is String ? e : 'Erreur : $e');
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ── Champs ──────────────────────────────────────────────────────────────────

  static InputDecoration _dec(String label, {String? hint}) => InputDecoration(
        labelText: label.isEmpty ? null : label,
        hintText: hint,
        labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13),
        hintStyle: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade400),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _teal, width: 1.6)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );

  Widget _select<T>(String label, T value, List<(T, String)> items, ValueChanged<T> onChanged) =>
      DropdownButtonFormField<T>(
        initialValue: items.any((i) => i.$1 == value) ? value : items.first.$1,
        isExpanded: true,
        decoration: _dec(label),
        items: items.map((i) => DropdownMenuItem<T>(value: i.$1,
            child: Text(i.$2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Galey', fontSize: 14)))).toList(),
        onChanged: (v) { if (v != null) onChanged(v); },
      );

  Widget _bloc(int n, String titre, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(color: _teal.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Center(child: Text('$n', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, color: _teal))),
            ),
            const SizedBox(width: 10),
            Text(titre, style: const TextStyle(fontFamily: 'Galey', fontSize: 15, fontWeight: FontWeight.w800, color: _dark)),
          ]),
          const SizedBox(height: 12),
          ...children,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final locaux = _perimetre == 'locaux';
    final aidePerimetre = kPerimetres.firstWhere((p) => p.$1 == _perimetre).$3;
    final declencheurs = <(String, String)>[
      ('', 'Manuel uniquement'),
      if (!_isPension && !_isGarde) ('naissance', 'À la naissance'),
      if (!_isAssociation) ('chaleurs', 'Aux chaleurs'),
      if (!_isAssociation) ('gestation', 'Gestation confirmée'),
      if (!_isGarde) ('entree', 'À l’entrée d’un animal'),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: Text(isEdit ? 'Modifier le protocole' : 'Créer un protocole',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          _bloc(1, 'Informations générales', [
            TextFormField(controller: _nomCtrl, style: const TextStyle(fontFamily: 'Galey'),
                decoration: _dec('Nom du protocole *', hint: _isGarde ? 'Ex : Nettoyage du parc après le départ' : 'Ex : Entretien des locaux')),
            const SizedBox(height: 10),
            _select<String>('Type', _type, _isGarde ? _typesGarde : _types, (v) => setState(() => _type = v)),
            const SizedBox(height: 10),
            TextFormField(controller: _descCtrl, minLines: 2, maxLines: 4, style: const TextStyle(fontFamily: 'Galey'),
                decoration: _dec('Description (facultative)', hint: 'Ex : objectifs, contexte, précisions…')),
          ]),

          _bloc(2, 'Périmètre concerné', [
            _select<String>('Concerne', _perimetre, _perimetresDispo.map((p) => (p.$1, p.$2)).toList(),
                (v) => setState(() { _perimetre = v; _ajusterRefEvent(); })),
            const SizedBox(height: 10),
            if (locaux)
              Autocomplete<String>(
                initialValue: TextEditingValue(text: _lieuCtrl.text),
                optionsBuilder: (v) => _lieux.where((l) => l.toLowerCase().contains(v.text.toLowerCase())),
                onSelected: (v) => _lieuCtrl.text = v,
                fieldViewBuilder: (ctx, ctrl, focus, onSubmit) => TextFormField(
                  controller: ctrl, focusNode: focus, style: const TextStyle(fontFamily: 'Galey'),
                  onChanged: (v) => _lieuCtrl.text = v,
                  decoration: _dec('Zone / lieu', hint: 'Ex : Nurserie, chenil n°1…'),
                ),
              )
            else ...[
              if (_perimetre == 'categorie') ...[
                _select<String>('Catégorie d’animaux', _categorie, _categoriesDispo,
                    (v) => setState(() { _categorie = v; _ajusterRefEvent(); })),
                const SizedBox(height: 10),
              ],
              if (!_isGarde)
                _select<String>('Espèce', _espece,
                    _especes.map((e) => (e, e.isEmpty ? 'Toutes espèces' : '${e[0].toUpperCase()}${e.substring(1)}')).toList(),
                    (v) => setState(() => _espece = v)),
            ],
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Icon(Icons.info_outline, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Expanded(child: Text(aidePerimetre, style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade500))),
              ]),
            ),
            if (_perimetre == 'animal' && !_isGarde) ...[
              const SizedBox(height: 10),
              AnimalPickerField(
                selected: _selectedAnimaux,
                onTap: _pickAnimaux,
                label: 'Animaux par défaut (facultatif)…',
                accentColor: _teal,
              ),
            ],
            if (!locaux && !_isGarde) ...[
              const SizedBox(height: 12),
              _select<String>('Calcul des dates à partir de', _refEvent,
                  _refEventsDispo.map((r) => (r.$1, r.$2)).toList(), (v) => setState(() => _refEvent = v)),
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(kRefEvents.firstWhere((r) => r.$1 == _refEvent, orElse: () => kRefEvents.first).$3,
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
              ),
              const SizedBox(height: 10),
              _select<String>('Application automatique', _declencheurAuto, declencheurs,
                  (v) => setState(() => _declencheurAuto = v)),
            ],
          ]),

          _bloc(3, 'Étapes du protocole', [
            for (var i = 0; i < _etapes.length; i++)
              _EtapeCard(
                key: ObjectKey(_etapes[i]),
                index: i,
                total: _etapes.length,
                ctrl: _etapes[i],
                refEvent: locaux ? 'manuel' : _refEvent,
                usesAge: _usesAge,
                onChanged: () => setState(() {}),
                onMove: (d) => _deplacer(i, d),
                onDuplicate: () => setState(() => _etapes.insert(i + 1, _EtapeCtrl.copie(_etapes[i]))),
                onRemove: _etapes.length > 1 ? () => setState(() { _etapes[i].dispose(); _etapes.removeAt(i); }) : null,
              ),
            TextButton.icon(
              onPressed: () => setState(() => _etapes.add(_EtapeCtrl())),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Ajouter une étape', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              style: TextButton.styleFrom(foregroundColor: _teal),
            ),
          ]),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey.shade200))),
          child: Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Annuler', style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade700)),
            )),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800)),
            )),
          ]),
        ),
      ),
    );
  }
}

// ─── Carte d'étape ────────────────────────────────────────────────────────────

class _EtapeCard extends StatefulWidget {
  final int index, total;
  final _EtapeCtrl ctrl;
  final String refEvent;
  final bool usesAge;
  final VoidCallback onChanged;
  final ValueChanged<int> onMove;
  final VoidCallback onDuplicate;
  final VoidCallback? onRemove;

  const _EtapeCard({
    super.key, required this.index, required this.total, required this.ctrl, required this.refEvent,
    required this.usesAge, required this.onChanged, required this.onMove, required this.onDuplicate, this.onRemove,
  });

  @override
  State<_EtapeCard> createState() => _EtapeCardState();
}

class _EtapeCardState extends State<_EtapeCard> {
  late bool _details = widget.ctrl.produitCtrl.text.isNotEmpty || widget.ctrl.dosageCtrl.text.isNotEmpty || widget.ctrl.lieuCtrl.text.isNotEmpty;

  static const _ts = TextStyle(fontFamily: 'Galey', fontSize: 14);
  InputDecoration _dec(String l, {String? hint}) => _PlanTemplateFormPageState._dec(l, hint: hint);

  @override
  Widget build(BuildContext context) {
    final c = widget.ctrl;
    final refLabel = switch (widget.refEvent) {
      'saillie' => 'la saillie', 'mise_bas' => 'la mise bas', 'naissance' => 'la naissance', _ => 'la date de début',
    };
    final sanitaire = ['vermifuge', 'vaccination', 'antiparasitaire', 'traitement'].contains(acteDepuisSaisie(c.actionCtrl.text));
    final freqValeur = c.isRecurrent ? '${c.frequence}_an' : c.frequence;
    void maj(VoidCallback f) { setState(f); widget.onChanged(); }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Étape ${widget.index + 1}', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, color: _dark)),
          const Spacer(),
          IconButton(visualDensity: VisualDensity.compact, tooltip: 'Monter',
              onPressed: widget.index == 0 ? null : () => widget.onMove(-1), icon: const Icon(Icons.keyboard_arrow_up_rounded)),
          IconButton(visualDensity: VisualDensity.compact, tooltip: 'Descendre',
              onPressed: widget.index == widget.total - 1 ? null : () => widget.onMove(1), icon: const Icon(Icons.keyboard_arrow_down_rounded)),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz, color: Colors.grey.shade500),
            onSelected: (v) {
              if (v == 'dup') widget.onDuplicate();
              if (v == 'del') widget.onRemove?.call();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'dup', child: Text('Dupliquer', style: TextStyle(fontFamily: 'Galey'))),
              if (widget.onRemove != null)
                const PopupMenuItem(value: 'del', child: Text('Supprimer', style: TextStyle(fontFamily: 'Galey', color: Colors.red))),
            ],
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Autocomplete<String>(
              initialValue: TextEditingValue(text: c.actionCtrl.text),
              optionsBuilder: (v) => kActesSuggeres.map((a) => a.$2)
                  .where((l) => v.text.isEmpty || l.toLowerCase().contains(v.text.toLowerCase())),
              onSelected: (v) => maj(() => c.actionCtrl.text = v),
              fieldViewBuilder: (ctx, ctrl, focus, _) => TextFormField(
                controller: ctrl, focusNode: focus, style: _ts,
                onChanged: (v) => maj(() => c.actionCtrl.text = v),
                decoration: _dec('Action *', hint: 'Ex : Nettoyer les surfaces'),
              ),
            ),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: widget.usesAge
                  ? TextFormField(
                      controller: c.ageSemainesCtrl, style: _ts, keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => widget.onChanged(),
                      decoration: _dec('À (semaines d’âge)'))
                  : Row(children: [
                      SizedBox(width: 62, child: TextFormField(
                        controller: c.offsetCtrl, style: _ts, textAlign: TextAlign.center, keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (_) => widget.onChanged(),
                        decoration: _dec('Jours'))),
                      const SizedBox(width: 6),
                      Expanded(child: DropdownButtonFormField<String>(
                        initialValue: c.direction, isExpanded: true,
                        decoration: _dec('Déclenchement'),
                        items: [
                          DropdownMenuItem(value: 'apres', child: Text('après $refLabel', overflow: TextOverflow.ellipsis, style: _ts)),
                          DropdownMenuItem(value: 'avant', child: Text('avant $refLabel', overflow: TextOverflow.ellipsis, style: _ts)),
                        ],
                        onChanged: (v) => maj(() => c.direction = v ?? 'apres'),
                      )),
                    ])),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(flex: 3, child: DropdownButtonFormField<String>(
                initialValue: freqValeur, isExpanded: true,
                decoration: _dec('Fréquence'),
                items: const [
                  ('ponctuel', 'Une fois / jours de suite'), ('quotidien', 'Chaque jour'),
                  ('hebdomadaire', 'Chaque semaine'), ('mensuel', 'Chaque mois'),
                  ('quotidien_an', 'Chaque jour (1 an)'), ('hebdomadaire_an', 'Chaque semaine (1 an)'),
                  ('mensuel_an', 'Chaque mois (1 an)'),
                ].map((f) => DropdownMenuItem(value: f.$1, child: Text(f.$2, overflow: TextOverflow.ellipsis, style: _ts))).toList(),
                onChanged: (v) => maj(() {
                  final x = v ?? 'ponctuel';
                  c.isRecurrent = x.endsWith('_an');
                  c.frequence = c.isRecurrent ? x.substring(0, x.length - 3) : x;
                }),
              )),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: DropdownButtonFormField<String?>(
                initialValue: c.trancheHoraire, isExpanded: true,
                decoration: _dec('Créneau'),
                items: [
                  DropdownMenuItem<String?>(value: null, child: Text('Non défini', style: _ts)),
                  ...kTranches.entries.map((t) => DropdownMenuItem<String?>(value: t.key, child: Text(t.value, style: _ts))),
                ],
                onChanged: (v) => maj(() => c.trancheHoraire = v),
              )),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (c.frequence == 'ponctuel') ...[
                const Text('Durée', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
                SizedBox(width: 56, child: TextFormField(controller: c.dureeJoursCtrl, style: _ts, textAlign: TextAlign.center,
                    keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => widget.onChanged(), decoration: _dec(''))),
                const Text('jour(s) de suite', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
              ],
              if (c.frequence == 'hebdomadaire') ...[
                SizedBox(width: 64, child: DropdownButtonFormField<int>(
                  initialValue: c.nbFoisSemaine, decoration: _dec(''),
                  items: [1, 2, 3].map((n) => DropdownMenuItem(value: n, child: Text('$n', style: _ts))).toList(),
                  onChanged: (v) => maj(() => c.nbFoisSemaine = v ?? 1),
                )),
                const Text('fois / semaine', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
              ],
              if (c.frequence != 'ponctuel' && !c.isRecurrent) ...[
                const Text('pendant', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
                SizedBox(width: 56, child: TextFormField(controller: c.dureeSemainesCtrl, style: _ts, textAlign: TextAlign.center,
                    keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => widget.onChanged(), decoration: _dec(''))),
                Text(c.frequence == 'mensuel' ? 'mois' : 'semaines', style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
              ],
            ]),
            const SizedBox(height: 10),
            if (_details || sanitaire) ...[
              Row(children: [
                Expanded(child: TextFormField(controller: c.produitCtrl, style: _ts, onChanged: (_) => widget.onChanged(),
                    decoration: _dec('Produit', hint: 'Ex : Milbemax®'))),
                const SizedBox(width: 8),
                Expanded(child: TextFormField(controller: c.dosageCtrl, style: _ts, onChanged: (_) => widget.onChanged(),
                    decoration: _dec('Dosage', hint: 'Ex : 1 cp / 5 kg'))),
              ]),
              const SizedBox(height: 10),
              TextFormField(controller: c.lieuCtrl, style: _ts, onChanged: (_) => widget.onChanged(),
                  decoration: _dec('Lieu', hint: 'Ex : parc, salle de soins')),
              const SizedBox(height: 10),
            ] else
              TextButton(
                onPressed: () => setState(() => _details = true),
                style: TextButton.styleFrom(foregroundColor: _teal, padding: EdgeInsets.zero, minimumSize: const Size(0, 30)),
                child: const Text('+ Produit, dosage, lieu', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
            TextFormField(controller: c.descCtrl, style: _ts, minLines: 2, maxLines: 5, onChanged: (_) => widget.onChanged(),
                decoration: _dec('Consignes', hint: 'Ex : suivre les consignes du responsable, précautions…')),
          ]),
        ),
      ]),
    );
  }
}

// ─── Contrôleur d'étape ───────────────────────────────────────────────────────

class _EtapeCtrl {
  String  direction      = 'apres';
  String  frequence      = 'ponctuel';
  int     nbFoisSemaine  = 1;
  bool    isRecurrent    = false;
  String? trancheHoraire;
  String? existingId;

  /// Action saisie librement (ou suggestion) — enregistrée dans type_acte
  final TextEditingController actionCtrl;
  final TextEditingController produitCtrl;
  final TextEditingController dosageCtrl;
  final TextEditingController offsetCtrl;
  final TextEditingController ageSemainesCtrl;
  final TextEditingController dureeJoursCtrl;
  final TextEditingController dureeSemainesCtrl;
  final TextEditingController lieuCtrl;
  final TextEditingController descCtrl;

  _EtapeCtrl()
      : actionCtrl       = TextEditingController(),
        produitCtrl      = TextEditingController(),
        dosageCtrl       = TextEditingController(),
        offsetCtrl       = TextEditingController(text: '0'),
        ageSemainesCtrl  = TextEditingController(text: '3'),
        dureeJoursCtrl   = TextEditingController(text: '1'),
        dureeSemainesCtrl= TextEditingController(text: '1'),
        lieuCtrl         = TextEditingController(),
        descCtrl         = TextEditingController();

  _EtapeCtrl.fromData(Map<String, dynamic> d)
      : direction         = d['offset_direction'] ?? 'apres',
        frequence         = d['frequence']   ?? 'ponctuel',
        nbFoisSemaine     = (d['nb_fois_semaine'] as num? ?? 1).toInt(),
        isRecurrent       = d['is_recurrent'] == true,
        trancheHoraire    = d['tranche_horaire'] as String?,
        existingId        = d['id'] as String?,
        actionCtrl        = TextEditingController(text: acteLabel(d['type_acte'] as String?)),
        produitCtrl       = TextEditingController(text: d['produit'] ?? ''),
        dosageCtrl        = TextEditingController(text: d['dosage'] ?? ''),
        offsetCtrl        = TextEditingController(text: '${d['jour_offset'] ?? 0}'),
        ageSemainesCtrl   = TextEditingController(text: '${d['age_min_semaines'] ?? 3}'),
        dureeJoursCtrl    = TextEditingController(text: '${d['duree_jours'] ?? 1}'),
        dureeSemainesCtrl = TextEditingController(text: '${d['duree_semaines'] ?? 1}'),
        lieuCtrl          = TextEditingController(text: d['lieu'] ?? ''),
        descCtrl          = TextEditingController(text: d['description'] ?? '');

  /// Copie d'une étape (nouvelle étape, sans id).
  factory _EtapeCtrl.copie(_EtapeCtrl o) {
    final c = _EtapeCtrl.fromData(o.toMap(ordre: 0, usesAge: true));
    c.existingId = null;
    return c;
  }

  Map<String, dynamic> toMap({required int ordre, bool usesAge = false}) => {
    if (existingId != null) 'id': existingId,
    'type_acte':        acteDepuisSaisie(actionCtrl.text),
    'offset_direction': direction,
    'jour_offset':      int.tryParse(offsetCtrl.text) ?? 0,
    'age_min_semaines': usesAge ? int.tryParse(ageSemainesCtrl.text) : null,
    'produit':          produitCtrl.text.trim().isEmpty  ? null : produitCtrl.text.trim(),
    'dosage':           dosageCtrl.text.trim().isEmpty   ? null : dosageCtrl.text.trim(),
    'frequence':        frequence,
    'nb_fois_semaine':  nbFoisSemaine,
    'is_recurrent':     isRecurrent,
    'duree_semaines':   isRecurrent ? 52 : (int.tryParse(dureeSemainesCtrl.text) ?? 1),
    'duree_jours':      int.tryParse(dureeJoursCtrl.text) ?? 1,
    'lieu':             lieuCtrl.text.trim().isEmpty ? null : lieuCtrl.text.trim(),
    'description':      descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
    'tranche_horaire':  trancheHoraire,
    'ordre':            ordre,
  };

  void dispose() {
    actionCtrl.dispose(); produitCtrl.dispose(); dosageCtrl.dispose(); offsetCtrl.dispose();
    ageSemainesCtrl.dispose(); dureeJoursCtrl.dispose(); dureeSemainesCtrl.dispose();
    lieuCtrl.dispose(); descCtrl.dispose();
  }
}
