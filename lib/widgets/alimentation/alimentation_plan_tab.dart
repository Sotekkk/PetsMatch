import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/plan_alimentation.dart';
import 'ajout_aliment_plan_page.dart';
import 'plan_alimentation_lecture.dart';

const _teal = Color(0xFF0C5C6C);
const _texte = Color(0xFF1F2A2E);
const _gris = Color(0xFF5A6469);
const _bord = Color(0xFFDCE3E6);

TextStyle _st(double t, {FontWeight w = FontWeight.w400, Color c = _texte}) =>
    TextStyle(fontFamily: 'Galey', fontSize: t, fontWeight: w, color: c);

const _etapes = ['Type', 'Besoins', 'Aliments', 'Repas', 'Ration', 'Résumé'];

/// Onglet Alimentation d'une fiche animal (particulier, éleveur,
/// association), toutes espèces. Synthèse une fois configuré, parcours en 6
/// étapes pour le premier paramétrage ou une modification (chaque étape est
/// accessible directement). [lectureSeule] : vue d'un professionnel (pet-sitter…),
/// sans aucune action. Miroir de AlimentationPlanTab.tsx (site).
class AlimentationPlanTab extends StatefulWidget {
  final String? animalId;
  final String espece;
  final String race;
  final String sexe;
  final bool sterilise;
  final DateTime? dateNaissance;
  final String nom;
  /// Poids de la fiche (repli si aucune pesée dans l'historique).
  final double? poidsFiche;
  final bool lectureSeule;

  const AlimentationPlanTab({
    super.key, required this.animalId, required this.espece, this.race = '', this.sexe = '',
    this.sterilise = false, this.dateNaissance, this.nom = '', this.poidsFiche, this.lectureSeule = false,
  });

  @override
  State<AlimentationPlanTab> createState() => _AlimentationPlanTabState();
}

class _AlimentationPlanTabState extends State<AlimentationPlanTab> {
  static final _supa = Supabase.instance.client;
  late final ProfilEspece _profil = profilEspece(widget.espece);

  bool _loading = true;
  bool _saving = false;
  Map<String, dynamic>? _row;
  late PlanAlimentation _plan = _planNeuf();

  bool _parcours = false;
  int _etape = 1;
  String? _erreurEtape;
  bool _ecartOk = false;

  final _qte = <String, TextEditingController>{};
  final _invalides = <String, String>{};
  final _objectif = TextEditingController();
  final _poidsAdulte = TextEditingController();
  final _consignes = TextEditingController();
  final _recherche = TextEditingController();

  List<Map<String, dynamic>> _catalogue = [];
  bool _catalogueCharge = false;
  double? _poids;
  String _etatRepro = 'normal';
  int? _semaineLactation;
  /// Nombre de petits détecté (portée ou gestation), sa source, et la mise bas.
  int? _nbNesPortee;
  String? _sourceNbPetits;
  String? _miseBas;
  final _nbPetits = TextEditingController();

  PlanAlimentation _planNeuf() => PlanAlimentation(
        repas: List.generate(widget.espece == 'chat' || widget.espece == 'cheval' ? 3 : 2, (_) => RepasPlan()),
      );

  ProfilAnimal get _animal => ProfilAnimal(
        espece: widget.espece, nom: widget.nom, sexe: widget.sexe, sterilise: widget.sterilise,
        dateNaissance: widget.dateNaissance, poidsKg: _poids, etatRepro: _etatRepro, semaineLactation: _semaineLactation,
      );

  CalculRation get _calc => calculerRation(_plan, _animal, poidsObjectif: lireNombre(_objectif.text).v);

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    for (final c in [..._qte.values, _objectif, _poidsAdulte, _consignes, _recherche, _nbPetits]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Chargement ───────────────────────────────────────────────────────────

  Future<void> _charger() async {
    final id = widget.animalId;
    if (id == null) { setState(() => _loading = false); return; }
    try {
      _row = await _supa.from('alimentations').select().eq('animal_id', id).maybeSingle();
    } catch (_) {}
    final plan = planDepuisLigne(_row, widget.espece);
    if (plan != null) {
      _plan = plan;
      _consignes.text = (_row?['consignes'] ?? '').toString();
      final obj = (_row?['poids_objectif'] as num?)?.toDouble();
      _objectif.text = obj != null ? _fr(obj) : '';
      _poidsAdulte.text = plan.poidsAdulte != null ? _fr(plan.poidsAdulte!) : '';
      await _detailsCatalogue();
    } else {
      _parcours = !widget.lectureSeule;
    }
    try {
      final p = await _supa.from('poids').select('valeur').eq('animal_id', id)
          .order('date', ascending: false).limit(1).maybeSingle();
      _poids = double.tryParse(p?['valeur']?.toString().replaceAll(',', '.') ?? '');
    } catch (_) {}
    _poids ??= widget.poidsFiche;
    if (widget.sexe == 'femelle' && !widget.sterilise) await _detecterRepro(id);
    if (_etatRepro == 'lactation') {
      // Saisie de l'éleveur conservée pour la même portée ; une nouvelle
      // portée reprend le nombre détecté.
      if (_plan.nbPetits == null || _plan.nbPetitsMiseBas != _miseBas) {
        _plan.nbPetits = _nbNesPortee;
        _plan.nbPetitsMiseBas = _miseBas;
      }
      _nbPetits.text = _plan.nbPetits?.toString() ?? '';
    }
    _syncQuantites();
    if (mounted) setState(() => _loading = false);
  }

  /// Gestation en cours / mise bas récente (< 8 semaines) : besoins augmentés.
  /// Dernière gestation de l'onglet Repro + portées dont la femelle est la
  /// mère (fiches des petits reliées par la puce, sinon le nom de la mère).
  Future<void> _detecterRepro(String id) async {
    Map? gestation;
    try {
      gestation = await _supa.from('gestations').select('date, date_naissance, nb_nes')
          .eq('animal_id', id).order('date', ascending: false).limit(1).maybeSingle();
    } catch (_) {}
    var portees = <dynamic>[];
    try {
      final mere = await _supa.from('animaux').select('identification, nom, nom_pedigree, uid_eleveur')
          .eq('id', id).maybeSingle();
      final puce = (mere?['identification'] ?? '').toString().replaceAll(' ', '');
      const cols = 'portee_id, date_naissance, statut';
      if (puce.isNotEmpty) {
        portees = await _supa.from('animaux').select(cols).eq('puce_mere', puce).not('portee_id', 'is', null);
      }
      final uidEleveur = mere?['uid_eleveur']?.toString();
      for (final nom in [mere?['nom_pedigree'], mere?['nom']]) {
        final n = (nom ?? '').toString().trim();
        if (portees.isNotEmpty || n.isEmpty || uidEleveur == null) continue;
        portees = await _supa.from('animaux').select(cols)
            .ilike('nom_mere', n).eq('uid_eleveur', uidEleveur).not('portee_id', 'is', null);
      }
    } catch (_) {}
    final e = detecterReproduction(espece: widget.espece, gestation: gestation, portees: portees);
    _etatRepro = e.etat;
    _semaineLactation = e.semaine;
    _nbNesPortee = e.nbPetits;
    _sourceNbPetits = e.source;
    _miseBas = e.miseBas;
  }

  /// Tableaux fabricant (doses, croissance) des aliments du catalogue.
  Future<void> _detailsCatalogue() async {
    final ids = _plan.aliments.map((a) => a.id).whereType<String>().toSet().toList();
    if (ids.isEmpty) return;
    List rows;
    try {
      rows = await _supa.from('marques_aliments').select('id, doses, tableau_croissance').inFilter('id', ids);
    } on PostgrestException {
      try {
        rows = await _supa.from('marques_aliments').select('id, doses').inFilter('id', ids);
      } catch (_) { return; }
    } catch (_) { return; }
    for (final r in rows.whereType<Map>()) {
      for (final a in _plan.aliments.where((a) => a.id == r['id']?.toString())) {
        a.doses = (r['doses'] as List?) ?? const [];
        a.tableauCroissance = (r['tableau_croissance'] as List?) ?? const [];
      }
    }
  }

  Future<void> _chargerCatalogue() async {
    if (_catalogueCharge) return;
    _catalogueCharge = true;
    const cols = 'id, marque, gamme, type_aliment, age_categorie, densite_kcal_100g, kcal_estime, ajoute_par_uid, doses';
    try {
      List rows;
      try {
        rows = await _supa.from('marques_aliments').select('$cols, tableau_croissance')
            .eq('espece', widget.espece).order('marque').limit(1000);
      } on PostgrestException {
        rows = await _supa.from('marques_aliments').select(cols).eq('espece', widget.espece).order('marque').limit(1000);
      }
      if (mounted) setState(() => _catalogue = rows.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList());
    } catch (_) {
      _catalogueCharge = false;
    }
  }

  AlimentPlan _depuisCatalogue(Map<String, dynamic> r) {
    final k = (r['densite_kcal_100g'] as num?)?.toDouble();
    return AlimentPlan(
      id: r['id']?.toString(),
      marque: (r['marque'] ?? '').toString(),
      gamme: (r['gamme'] ?? '').toString(),
      type: typeDepuisCatalogue(r['type_aliment']?.toString(), widget.espece),
      kcal: k != null && k > 0 ? k : null,
      source: k == null ? null : (r['kcal_estime'] == true ? 'composition' : 'fabricant'),
    )
      ..doses = (r['doses'] as List?) ?? const []
      ..tableauCroissance = (r['tableau_croissance'] as List?) ?? const [];
  }

  // ── Quantités saisies ────────────────────────────────────────────────────

  String _fr(double v) => (v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), ''))
      .replaceAll('.', ',');

  String _cle(int repas, int a) => '$repas-$a';

  void _syncQuantites() {
    final cles = <String>{};
    for (var i = 0; i < _plan.repas.length; i++) {
      for (final it in _plan.repas[i].items) {
        final k = _cle(i, it.a);
        cles.add(k);
        final txt = it.g == null ? '' : _fr(_profil.uniteKg ? it.g! / 1000 : it.g!);
        final c = _qte.putIfAbsent(k, () => TextEditingController());
        if (!_invalides.containsKey(k) && c.text != txt) c.text = txt;
      }
    }
    for (final k in _qte.keys.where((k) => !cles.contains(k)).toList()) {
      _qte.remove(k)?.dispose();
      _invalides.remove(k);
    }
  }

  void _saisirQuantite(int repas, ItemRepas it, String texte) {
    final k = _cle(repas, it.a);
    final l = lireNombre(texte);
    setState(() {
      _ecartOk = false;
      _erreurEtape = null;
      if (l.err != null) { _invalides[k] = l.err!; return; }
      final g = l.v == null ? null : (_profil.uniteKg ? l.v! * 1000 : l.v!);
      if (g != null && g > 20000) { _invalides[k] = 'Quantité trop élevée pour un repas (20 kg au plus).'; return; }
      _invalides.remove(k);
      it.g = g;
    });
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  void _allerEtape(int n) => setState(() {
        _syncQuantites();
        _etape = n;
        _erreurEtape = null;
      });

  void _suivant() {
    final err = _erreurDe(_etape);
    if (err != null) { setState(() => _erreurEtape = err); return; }
    if (_etape == 2) _plan.poidsAdulte = lireNombre(_poidsAdulte.text).v;
    if (_etape == 3) _chargerCatalogue();
    if (_etape < 6) {
      _allerEtape(_etape + 1);
    } else {
      _enregistrer();
    }
  }

  String? _erreurDe(int etape) => erreurEtape(etape, _plan, _calc,
      objectifTexte: _objectif.text, poidsAdulteTexte: _poidsAdulte.text, ecartConfirme: _ecartOk, saisiesInvalides: _invalides);

  Future<bool> _confirmerRetourReco() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Revenir à la ration recommandée ?', style: _st(17, w: FontWeight.w800)),
        content: Text('Les quantités que vous avez modifiées seront remplacées par la ration recommandée par PetsMatch. '
            'Les aliments, les repas et les horaires sont conservés.', style: _st(14.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Annuler', style: _st(14.5, w: FontWeight.w700))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Remplacer', style: _st(14.5, w: FontWeight.w800, c: Colors.white)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _retourReco({bool enregistrer = false}) async {
    if (!await _confirmerRetourReco()) return;
    setState(() {
      _plan.revenirRecommandation();
      _invalides.clear();
      for (final c in _qte.values) { c.clear(); }
      _ecartOk = false;
    });
    if (enregistrer) await _enregistrer();
  }

  Future<void> _enregistrer() async {
    final id = widget.animalId;
    if (id == null) return;
    for (var e = 1; e <= 5; e++) {
      final err = _erreurDe(e);
      if (err != null) {
        setState(() { _parcours = true; _etape = e; _erreurEtape = err; });
        return;
      }
    }
    _plan.poidsAdulte = lireNombre(_poidsAdulte.text).v;
    final c = _calc;
    setState(() => _saving = true);
    final payload = <String, dynamic>{
      'plan': _plan.toJson(c),
      'consignes': _consignes.text.trim().isEmpty ? null : _consignes.text.trim(),
      'poids_objectif': lireNombre(_objectif.text).v,
      ...colonnesHistoriques(_plan, c),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      final Map<String, dynamic> r;
      if (_row?['id'] != null) {
        r = await _supa.from('alimentations').update(payload).eq('id', _row!['id']).select().single();
      } else {
        r = await _supa.from('alimentations')
            .insert({...payload, 'animal_id': id, 'uid_eleveur': FirebaseAuth.instance.currentUser?.uid})
            .select().single();
      }
      _row = r;
      _plan.repris = false;
      if (!mounted) return;
      setState(() { _parcours = false; _erreurEtape = null; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Alimentation enregistrée'), behavior: SnackBarBehavior.floating));
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _erreurEtape = e.code == '23514'
          ? e.message
          : e.code == 'PGRST204'
              ? 'Enregistrement impossible : la base de données doit être mise à jour (migration alimentation).'
              : 'Enregistrement impossible, réessayez.');
    } catch (_) {
      if (mounted) setState(() => _erreurEtape = 'Enregistrement impossible, réessayez.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _voirCommePro() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF4F7F8),
      builder: (_) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.9, maxChildSize: 0.95,
        builder: (_, ctrl) => ListView(controller: ctrl, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          PlanAlimentationLecture.depuisLigne(_row, widget.espece, nomAnimal: widget.nom),
        ]),
      ),
    );
  }

  Future<void> _ajouterAliment() async {
    final types = _plan.categories.isNotEmpty ? _plan.categories : _profil.types;
    final a = await AjoutAlimentPlanPage.ouvrir(context,
        espece: widget.espece, typeInitial: types.first, marqueInitiale: _recherche.text.trim());
    if (a == null || !mounted) return;
    setState(() {
      _plan.ajouterAliment(a, _profil);
      if (!_plan.categories.contains(a.type)) _plan.categories.add(a.type);
      _recherche.clear();
      _erreurEtape = null;
    });
  }

  int _indexDe(AlimentPlan cand) => _plan.aliments.indexWhere((a) => cand.id != null
      ? a.id == cand.id
      : a.id == null && a.marque == cand.marque && a.gamme == cand.gamme && a.type == cand.type);

  void _basculerAliment(AlimentPlan cand) => setState(() {
        final i = _indexDe(cand);
        if (i >= 0) {
          _plan.retirerAliment(i);
        } else {
          _plan.ajouterAliment(cand, _profil);
        }
        _erreurEtape = null;
        _syncQuantites();
      });

  // ── Composants ───────────────────────────────────────────────────────────

  Widget _carte(Widget child, {EdgeInsets padding = const EdgeInsets.all(14)}) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: padding,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _bord)),
        child: child,
      );

  Widget _encadre(String t, {Color fond = const Color(0xFFE8F0F2), Color bord = const Color(0xFFB9CDD3), Widget? action}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(12), border: Border.all(color: bord)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: _st(14)),
          if (action != null) ...[const SizedBox(height: 8), action],
        ]),
      );

  Widget _avertissement(String t) => _encadre(t, fond: const Color(0xFFFFF4E0), bord: const Color(0xFFE9C27A));

  Widget _pastille(String label, bool on, VoidCallback onTap) => ChoiceChip(
        label: Text(label, style: _st(14.5, w: FontWeight.w700, c: on ? Colors.white : _texte)),
        selected: on,
        selectedColor: _teal,
        backgroundColor: Colors.white,
        showCheckmark: false,
        side: BorderSide(color: on ? _teal : const Color(0xFFC9D1D4)),
        materialTapTargetSize: MaterialTapTargetSize.padded,
        onSelected: (_) => onTap(),
      );

  Widget _caseACocher(String label, bool on, VoidCallback onTap, {String? sous}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: on ? const Color(0xFFE8F0F2) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: on ? _teal : _bord, width: on ? 2 : 1),
            ),
            child: Row(children: [
              Icon(on ? Icons.check_box : Icons.check_box_outline_blank, color: _teal),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: _st(14.5, w: FontWeight.w700)),
                if (sous != null) Text(sous, style: _st(12.5, c: _gris)),
              ])),
            ]),
          ),
        ),
      );

  Widget _titreEtape(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(t, style: _st(19, w: FontWeight.w800)),
      );

  Widget _sousTitre(String t) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 8),
        child: Text(t, style: _st(15, w: FontWeight.w700)),
      );

  // ── Vues ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: _teal));
    if (widget.lectureSeule) {
      return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 40), children: [
        PlanAlimentationLecture.depuisLigne(_row, widget.espece, nomAnimal: widget.nom),
      ]);
    }
    return _parcours ? _vueParcours() : _vueSynthese();
  }

  String get _badge {
    if (_profil.methode == 'aucune') return 'Quantités saisies';
    final c = _calc;
    return _plan.estPersonnalise || !c.recoDisponible ? 'Ration personnalisée' : 'Ration recommandée PetsMatch';
  }

  Widget _vueSynthese() {
    final c = _calc;
    final perso = _badge != 'Ration recommandée PetsMatch';
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 40), children: [
      Row(children: [
        Expanded(child: Text('Alimentation${widget.nom.isNotEmpty ? ' de ${widget.nom}' : ''}', style: _st(19, w: FontWeight.w800))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: perso ? const Color(0xFFFFF4E0) : const Color(0xFFEAF3E5),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(_badge, style: _st(12, w: FontWeight.w800, c: perso ? const Color(0xFF6B4100) : const Color(0xFF2F5A1F))),
        ),
      ]),
      const SizedBox(height: 12),
      if (_plan.repris)
        _encadre('Plan repris de l’ancienne version de l’onglet. Vérifiez-le, puis enregistrez-le.'),
      if (c.besoin.manque != null)
        _avertissement(c.besoin.manque!),
      for (final a in c.avertissements) _avertissement(a),
      PlanAlimentationLecture(plan: _plan, calcul: c, espece: widget.espece, consignes: _consignes.text),
      const SizedBox(height: 16),
      ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        onPressed: () => setState(() { _parcours = true; _etape = 1; _erreurEtape = null; }),
        child: Text('Modifier l’alimentation', style: _st(15.5, w: FontWeight.w800, c: Colors.white)),
      ),
      if (c.recoDisponible && _plan.estPersonnalise) ...[
        const SizedBox(height: 10),
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), side: const BorderSide(color: _teal),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          onPressed: _saving ? null : () => _retourReco(enregistrer: true),
          child: Text('Revenir à la ration recommandée', style: _st(15, w: FontWeight.w800, c: _teal)),
        ),
      ],
      if (_row != null)
        TextButton(
          onPressed: _voirCommePro,
          child: Text('Voir comme un professionnel (pension, pet-sitter)',
              style: _st(14, w: FontWeight.w700, c: _teal).copyWith(decoration: TextDecoration.underline)),
        ),
    ]);
  }

  Widget _vueParcours() {
    return Column(children: [
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Row(children: [
          for (var i = 0; i < _etapes.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                label: 'Étape ${i + 1} : ${_etapes[i]}',
                child: InkWell(
                  onTap: () => _allerEtape(i + 1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                    child: Column(children: [
                      Container(height: 5, decoration: BoxDecoration(
                          color: i < _etape ? _teal : _bord, borderRadius: BorderRadius.circular(3))),
                      const SizedBox(height: 5),
                      Text(_etapes[i], maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: _st(11, w: FontWeight.w700, c: i + 1 == _etape ? _teal : _gris)),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 20), children: [
          switch (_etape) {
            1 => _etape1(),
            2 => _etape2(),
            3 => _etape3(),
            4 => _etape4(),
            5 => _etape5(),
            _ => _etape6(),
          },
          if (_erreurEtape != null)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFDECEA), borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFF1B5AE))),
              child: Text(_erreurEtape!, style: _st(14, c: const Color(0xFF8C1D16))),
            ),
        ]),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: _bord))),
        child: Row(children: [
          Expanded(child: OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () {
              if (_etape > 1) {
                _allerEtape(_etape - 1);
              } else if (_row != null) {
                setState(() => _parcours = false);
              }
            },
            child: Text(_etape > 1 ? 'Retour' : 'Annuler', style: _st(15, w: FontWeight.w700)),
          )),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: _saving ? null : _suivant,
            child: Text(_etape == 6 ? (_saving ? 'Enregistrement…' : 'Enregistrer') : 'Continuer',
                style: _st(15.5, w: FontWeight.w800, c: Colors.white)),
          )),
        ]),
      ),
    ]);
  }

  // Étape 1 — type d'alimentation
  Widget _etape1() {
    Widget mode(String code, String titre, String sous) {
      final on = _plan.mode == code;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() {
            _plan.mode = code;
            if (code == 'unique') {
              if (_plan.categories.length > 1) _plan.categories = _plan.categories.sublist(0, 1);
              while (_plan.aliments.length > 1) { _plan.retirerAliment(_plan.aliments.length - 1); }
            }
            _erreurEtape = null;
          }),
          child: Container(
            constraints: const BoxConstraints(minHeight: 68),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: on ? const Color(0xFFE8F0F2) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: on ? _teal : _bord, width: 2),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titre, style: _st(15, w: FontWeight.w700)),
              Text(sous, style: _st(12.5, c: _gris)),
            ]),
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _titreEtape('1. Type d’alimentation'),
      Row(children: [
        mode('unique', 'Alimentation unique', 'Un seul aliment'),
        const SizedBox(width: 8),
        mode('mixte', 'Alimentation mixte', 'Deux aliments ou plus'),
      ]),
      const SizedBox(height: 14),
      Text(_plan.mode == 'unique'
          ? 'Quel type d’aliment ?'
          : 'Quels types d’aliments ? Plusieurs choix possibles, ou deux fois le même type (deux marques de croquettes par exemple).',
          style: _st(14, c: _gris)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final t in _profil.types)
          _pastille(kLibellesTypeAliment[t]!, _plan.categories.contains(t), () => setState(() {
                if (_plan.mode == 'unique') {
                  _plan.categories = [t];
                } else if (_plan.categories.contains(t)) {
                  _plan.categories.remove(t);
                } else {
                  _plan.categories.add(t);
                }
                _erreurEtape = null;
              })),
      ]),
      if (_profil.methode == 'energie') ...[
        const SizedBox(height: 12),
        Text('BARF et ration ménagère peuvent être des produits du commerce prêts à servir (Easy BARF, Dogfy Diet…) '
            'ou des préparations maison.', style: _st(13, c: _gris)),
      ],
    ]);
  }

  // Étape 2 — besoins
  Widget _etape2() {
    final c = _calc;
    final age = _animal.ageMois;
    final enCroissancePossible = _profil.methode == 'energie' && age != null && age < (widget.espece == 'chien' ? 18 : 12);
    String ageTxt() {
      if (age == null) return 'date de naissance non renseignée';
      if (age < 24) return '${age.floor()} mois';
      return '${(age / 12).floor()} ans';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _titreEtape('2. Besoins${widget.nom.isNotEmpty ? ' de ${widget.nom}' : ''}'),
      _carte(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('REPRIS DE LA FICHE IDENTITÉ', style: _st(12, w: FontWeight.w800, c: _gris)),
        const SizedBox(height: 6),
        Text([
          widget.espece.isEmpty ? '' : '${widget.espece[0].toUpperCase()}${widget.espece.substring(1)}',
          if (widget.race.trim().isNotEmpty) widget.race.trim(),
          if (widget.sexe.isNotEmpty) widget.sexe,
          ageTxt(),
        ].where((s) => s.isNotEmpty).join(' · '), style: _st(14.5)),
        Text('Poids : ${_poids != null ? '${_fr(_poids!)} kg' : 'non renseigné'} · Stérilisé(e) : ${widget.sterilise ? 'oui' : 'non'}',
            style: _st(14.5)),
        if (_etatRepro != 'normal')
          Text(_etatRepro == 'lactation'
              ? 'Lactation en cours (semaine ${_semaineLactation ?? 1} après la mise bas)'
              : _etatRepro == 'gestation_fin' ? 'Gestation en cours (dernières semaines)' : 'Gestation en cours',
              style: _st(14.5)),
      ])),
      _sousTitre('Niveau d’activité'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final a in kActivites)
          _pastille(kLibellesActivite[a]!, _plan.activite == a, () => setState(() => _plan.activite = a)),
      ]),
      _sousTitre('Nombre de repas par jour'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (var n = 1; n <= 4; n++)
          _pastille('$n', _plan.repas.length == n, () => setState(() { _plan.changerNbRepas(n, _profil); _syncQuantites(); })),
      ]),
      _sousTitre('Horaires (facultatif)'),
      for (var i = 0; i < _plan.repas.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Expanded(child: Text(libellesRepas(_plan.repas.length)[i], style: _st(14.5))),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(120, 44)),
              onPressed: () async {
                final h = _plan.repas[i].heure?.split(':');
                final t = await showTimePicker(context: context,
                    initialTime: h != null ? TimeOfDay(hour: int.parse(h[0]), minute: int.parse(h[1])) : const TimeOfDay(hour: 8, minute: 0));
                if (t != null) {
                  setState(() => _plan.repas[i].heure =
                      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
                }
              },
              child: Text(_plan.repas[i].heure?.replaceFirst(':', ' h ') ?? 'Ajouter', style: _st(14.5, w: FontWeight.w700, c: _teal)),
            ),
            if (_plan.repas[i].heure != null)
              IconButton(tooltip: 'Retirer l’horaire', icon: const Icon(Icons.close, color: _gris),
                  onPressed: () => setState(() => _plan.repas[i].heure = null)),
          ]),
        ),
      if (_profil.methode != 'aucune') ...[
        _sousTitre('Objectif de poids (facultatif)'),
        TextField(
          controller: _objectif,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() => _erreurEtape = null),
          style: _st(15),
          decoration: InputDecoration(
            hintText: 'Ex. 17,5', suffixText: 'kg', filled: true, fillColor: Colors.white,
            errorText: lireNombre(_objectif.text).err,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
      if (_etatRepro == 'lactation' && _profil.methode == 'energie') ...[
        _sousTitre('Nombre de petits allaités'),
        TextField(
          controller: _nbPetits,
          keyboardType: TextInputType.number,
          onChanged: (t) => setState(() {
            final l = lireNombre(t);
            _plan.nbPetits = l.v != null && l.v == l.v!.roundToDouble() ? l.v!.round() : null;
            _plan.nbPetitsMiseBas = _miseBas;
            _erreurEtape = null;
          }),
          style: _st(15),
          decoration: InputDecoration(
            hintText: 'Ex. 6', filled: true, fillColor: Colors.white,
            helperText: _sourceNbPetits != null
                ? '$_sourceNbPetits : corrigez si certains petits ne tètent plus.'
                : 'Les besoins de lactation dépendent du nombre de petits.',
            helperMaxLines: 2,
            errorText: lireNombre(_nbPetits.text).err ??
                (_nbPetits.text.trim().isNotEmpty && _plan.nbPetits == null ? 'Nombre entier attendu (ex. 6).' : null),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
      if (enCroissancePossible) ...[
        _sousTitre('Poids adulte estimé'),
        TextField(
          controller: _poidsAdulte,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() { _plan.poidsAdulte = lireNombre(_poidsAdulte.text).v; _erreurEtape = null; }),
          style: _st(15),
          decoration: InputDecoration(
            hintText: 'Ex. 25', suffixText: 'kg', filled: true, fillColor: Colors.white,
            helperText: 'Nécessaire au calcul pendant la croissance (demandez à l’éleveur ou au vétérinaire).',
            helperMaxLines: 2,
            errorText: lireNombre(_poidsAdulte.text).err,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
      const SizedBox(height: 14),
      _besoinEncadre(c),
    ]);
  }

  Widget _besoinEncadre(CalculRation c) {
    final b = c.besoin;
    if (b.manque != null) return _avertissement(b.manque!);
    final valeur = b.kcal != null
        ? '${b.kcal!.round()} kcal/jour'
        : b.totalG != null ? '${formatQuantite(b.totalG!, kg: true)}/jour' : null;
    return _encadre('${valeur != null ? 'Besoin estimé : $valeur\n' : ''}${b.detail}');
  }

  // Étape 3 — aliments
  Widget _etape3() {
    final q = _recherche.text.trim().toLowerCase();
    final filtres = _catalogue.where((r) {
      final t = typeDepuisCatalogue(r['type_aliment']?.toString(), widget.espece);
      if (_plan.categories.isNotEmpty && !_plan.categories.contains(t) && q.isEmpty) return false;
      if (q.isEmpty) return true;
      return '${r['marque']} ${r['gamme']} ${kLibellesTypeAliment[t]}'.toLowerCase().contains(q);
    }).take(60).toList();
    final sansMarque = [
      for (final t in _plan.categories.isNotEmpty ? _plan.categories : _profil.types)
        if (['foin', 'paturage', 'legumes'].contains(t)) t,
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _titreEtape('3. Aliments'),
      Text(_plan.mode == 'unique' ? 'Choisissez l’aliment.' : 'Choisissez au moins deux aliments (même catégorie possible).',
          style: _st(14, c: _gris)),
      const SizedBox(height: 10),
      if (_plan.aliments.isNotEmpty) ...[
        Text('Sélectionnés', style: _st(14, w: FontWeight.w700)),
        const SizedBox(height: 6),
        for (var i = 0; i < _plan.aliments.length; i++)
          _caseACocher(_plan.aliments[i].nom, true, () => setState(() { _plan.retirerAliment(i); _syncQuantites(); }),
              sous: _sousTitreAliment(_plan.aliments[i])),
        const SizedBox(height: 8),
      ],
      TextField(
        controller: _recherche,
        onChanged: (_) => setState(() {}),
        style: _st(15),
        decoration: InputDecoration(
          hintText: 'Marque, produit ou catégorie', prefixIcon: const Icon(Icons.search),
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
      const SizedBox(height: 10),
      if (!_catalogueCharge) const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: _teal))),
      for (final r in filtres)
        () {
          final a = _depuisCatalogue(r);
          if (_indexDe(a) >= 0) return const SizedBox.shrink();
          return _caseACocher(a.nom, false, () => _basculerAliment(a),
              sous: '${_sousTitreAliment(a)}${r['ajoute_par_uid'] != null ? ' · ajouté par un membre' : ''}');
        }(),
      if (_catalogueCharge && filtres.isEmpty)
        Padding(padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(q.isEmpty ? 'Aucun aliment de ce type dans le catalogue.' : 'Aucun résultat pour « ${_recherche.text.trim()} ».',
                style: _st(14, c: _gris))),
      for (final t in sansMarque)
        if (!_plan.aliments.any((a) => a.type == t && a.id == null))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
              onPressed: () => _basculerAliment(AlimentPlan(marque: 'Sans marque', gamme: kLibellesTypeAliment[t]!, type: t)),
              child: Text('Ajouter : ${kLibellesTypeAliment[t]} (sans marque)', style: _st(14.5, w: FontWeight.w700, c: _teal)),
            ),
          ),
      const SizedBox(height: 6),
      OutlinedButton(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), side: const BorderSide(color: _teal, width: 2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        onPressed: _ajouterAliment,
        child: Text('Mon aliment n’est pas dans la liste', style: _st(15, w: FontWeight.w800, c: _teal)),
      ),
    ]);
  }

  String _sousTitreAliment(AlimentPlan a) {
    final t = kLibellesTypeAliment[a.type] ?? a.type;
    if (_profil.methode != 'energie') return t;
    if (a.kcal == null) return '$t · valeur énergétique non renseignée';
    return '$t · ${a.kcal!.round()} kcal/100 g${a.source == 'composition' ? ' (estimation)' : ''}';
  }

  // Étape 4 — répartition
  Widget _etape4() {
    final labels = libellesRepas(_plan.repas.length);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _titreEtape('4. Répartition par repas'),
      Text('Cochez les aliments servis à chaque repas. Un repas peut en contenir un seul ou plusieurs.', style: _st(14, c: _gris)),
      const SizedBox(height: 10),
      for (var i = 0; i < _plan.repas.length; i++)
        _carte(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(labels[i], style: _st(15.5, w: FontWeight.w700))),
            if (_plan.repas[i].heure != null) Text(_plan.repas[i].heure!.replaceFirst(':', ' h '), style: _st(13.5, c: _gris)),
          ]),
          const SizedBox(height: 8),
          for (var a = 0; a < _plan.aliments.length; a++)
            () {
              final it = _plan.repas[i].items.where((x) => x.a == a).firstOrNull;
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _caseACocher(_plan.aliments[a].nom, it != null,
                    () => setState(() { _plan.basculer(i, a, _profil); _syncQuantites(); _erreurEtape = null; })),
                if (it != null && _profil.typesLibres.contains(_plan.aliments[a].type))
                  SwitchListTile(
                    dense: true, contentPadding: const EdgeInsets.only(left: 12), activeThumbColor: _teal,
                    title: Text('À volonté (sans quantité)', style: _st(13.5)),
                    value: it.libre,
                    onChanged: (v) => setState(() { it.libre = v; if (v) it.g = null; _syncQuantites(); }),
                  ),
              ]);
            }(),
        ])),
    ]);
  }

  // Étape 5 — ration
  Widget _etape5() {
    final c = _calc;
    final labels = libellesRepas(_plan.repas.length);
    final kg = _profil.uniteKg;
    final unite = kg ? 'kg/repas' : 'g/repas';
    final fabricant = [
      for (var a = 0; a < _plan.aliments.length; a++)
        if (c.fabricant[a] != null) '${_plan.aliments[a].nom} : ${formatQuantite(c.fabricant[a]!, kg: kg)}/jour',
    ];
    String? ecartMsg;
    if (c.ecartPct != null && (_plan.estPersonnalise || c.ecartPct!.abs() > 1)) {
      final p = c.ecartPct!.round();
      ecartMsg = c.ecartImportant
          ? 'Écart de ${p > 0 ? '+' : ''}$p % avec l’estimation PetsMatch. Cette ration est très différente de l’estimation PetsMatch : vérifiez les quantités avant de confirmer.'
          : 'Écart de ${p > 0 ? '+' : ''}$p % avec l’estimation PetsMatch : la ration correspond aux besoins.';
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _titreEtape('5. Ration'),
      if (_profil.methode != 'aucune') ...[
        Text('RATION RECOMMANDÉE PAR PETSMATCH', style: _st(12, w: FontWeight.w800, c: _gris)),
        const SizedBox(height: 6),
      ],
      _besoinEncadre(c),
      for (final a in c.avertissements) _avertissement(a),
      if (fabricant.isNotEmpty)
        _encadre('Recommandation du fabricant (pour une alimentation 100 % avec cet aliment) :\n${fabricant.join('\n')}',
            fond: Colors.white, bord: _bord),
      for (var i = 0; i < _plan.repas.length; i++)
        _carte(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('${labels[i]}${_plan.repas[i].heure != null ? ' · ${_plan.repas[i].heure!.replaceFirst(':', ' h ')}' : ''}',
                style: _st(15.5, w: FontWeight.w700))),
            Text('Total ${formatQuantite(c.lignes[i].fold<double>(0, (s, x) => s + (x.eff ?? 0)), kg: kg)}', style: _st(13.5, c: _gris)),
          ]),
          const SizedBox(height: 8),
          for (var j = 0; j < _plan.repas[i].items.length; j++)
            () {
              final it = _plan.repas[i].items[j];
              final x = c.lignes[i][j];
              final nom = _plan.aliments[it.a].nom;
              if (it.libre) {
                return Padding(padding: const EdgeInsets.only(bottom: 10),
                    child: Text('$nom : à volonté', style: _st(14.5, w: FontWeight.w700)));
              }
              final k = _cle(i, it.a);
              final ctrl = _qte.putIfAbsent(k, () => TextEditingController());
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: ctrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (t) => _saisirQuantite(i, it, t),
                  style: _st(16, w: FontWeight.w700),
                  decoration: InputDecoration(
                    labelText: nom, labelStyle: _st(14, c: _gris),
                    hintText: x.reco != null ? _fr(kg ? (x.reco! / 100).round() / 10 : x.reco!.roundToDouble()) : 'Quantité',
                    suffixText: unite, filled: true, fillColor: Colors.white,
                    helperText: x.reco != null
                        ? 'Recommandé par PetsMatch : ${formatQuantite(x.reco!, kg: kg)}${it.g != null ? ' · vous avez choisi ${formatQuantite(it.g!, kg: kg)}' : ''}'
                        : _profil.methode == 'energie' && _plan.aliments[it.a].kcal == null
                            ? 'Valeur énergétique non renseignée — ration personnalisée'
                            : 'Quantité à indiquer',
                    helperMaxLines: 2,
                    errorText: _invalides[k], errorMaxLines: 2,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              );
            }(),
        ])),
      _carte(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Total de la journée', style: _st(15, w: FontWeight.w700)),
        const SizedBox(height: 6),
        for (var a = 0; a < _plan.aliments.length; a++)
          Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [
            Expanded(child: Text(_plan.aliments[a].nom, style: _st(14.5))),
            Text(c.alimentLibre[a] ? 'à volonté' : '${formatQuantite(c.totalParAliment[a], kg: kg)}/jour', style: _st(14.5, w: FontWeight.w700)),
          ])),
        if (_profil.methode == 'energie') ...[
          const Divider(),
          Row(children: [
            Expanded(child: Text('Énergie servie', style: _st(14.5))),
            Flexible(child: Text(
                c.kcalServies != null
                    ? '${c.kcalServies!.round()} kcal/jour'
                    : c.sansKcal.isNotEmpty ? 'Non calculable (${c.sansKcal.join(', ')} sans valeur énergétique)' : '—',
                textAlign: TextAlign.right, style: _st(14.5, w: FontWeight.w700))),
          ]),
        ],
      ])),
      if (ecartMsg != null)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.ecartImportant ? const Color(0xFFFFF4E0) : const Color(0xFFEAF3E5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.ecartImportant ? const Color(0xFFE9C27A) : const Color(0xFFB8D3A8)),
          ),
          child: Column(children: [
            Text(ecartMsg, style: _st(14)),
            if (c.ecartImportant)
              CheckboxListTile(
                value: _ecartOk, contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, activeColor: _teal,
                title: Text('J’ai vérifié, cette ration est voulue', style: _st(14, w: FontWeight.w700)),
                onChanged: (v) => setState(() { _ecartOk = v ?? false; _erreurEtape = null; }),
              ),
          ]),
        ),
      if (c.recoDisponible && _plan.estPersonnalise)
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), side: const BorderSide(color: _teal),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          onPressed: _retourReco,
          child: Text('Revenir à la ration recommandée', style: _st(14.5, w: FontWeight.w800, c: _teal)),
        ),
    ]);
  }

  // Étape 6 — résumé
  Widget _etape6() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titreEtape('6. Résumé et enregistrement'),
      TextField(
        controller: _consignes,
        minLines: 3, maxLines: 6,
        onChanged: (_) => setState(() {}),
        style: _st(15),
        decoration: InputDecoration(
          labelText: 'Consignes alimentaires (facultatif)', alignLabelWithHint: true,
          hintText: 'Humidifier les croquettes, servir à température ambiante, pas de friandises…',
          helperText: 'Visibles en lecture seule par les professionnels à qui vous avez ouvert l’accès (pension, pet-sitter).',
          helperMaxLines: 2, filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      const SizedBox(height: 14),
      PlanAlimentationLecture(plan: _plan, calcul: _calc, espece: widget.espece, consignes: _consignes.text),
    ]);
  }
}
