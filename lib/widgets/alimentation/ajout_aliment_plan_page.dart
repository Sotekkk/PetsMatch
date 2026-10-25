import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/plan_alimentation.dart';

const _teal = Color(0xFF0C5C6C);
const _texte = Color(0xFF1F2A2E);
const _gris = Color(0xFF5A6469);
const _rouge = Color(0xFFB3261E);

TextStyle _st(double t, {FontWeight w = FontWeight.w400, Color c = _texte}) =>
    TextStyle(fontFamily: 'Galey', fontSize: t, fontWeight: w, color: c);

/// « Mon aliment n'est pas dans la liste » : saisie progressive (marque et
/// nom, puis type / stade, puis énergie pour le chien et le chat). Un aliment
/// du commerce rejoint le catalogue (visible des autres membres) ; une
/// préparation maison ou un aliment sans marque reste propre à l'animal.
/// Renvoie l'[AlimentPlan] créé, ou null si annulé.
class AjoutAlimentPlanPage extends StatefulWidget {
  final String espece;
  final String? typeInitial;
  final String marqueInitiale;
  const AjoutAlimentPlanPage({super.key, required this.espece, this.typeInitial, this.marqueInitiale = ''});

  static Future<AlimentPlan?> ouvrir(BuildContext context, {required String espece, String? typeInitial, String marqueInitiale = ''}) =>
      Navigator.of(context).push<AlimentPlan>(MaterialPageRoute(
          builder: (_) => AjoutAlimentPlanPage(espece: espece, typeInitial: typeInitial, marqueInitiale: marqueInitiale)));

  @override
  State<AjoutAlimentPlanPage> createState() => _AjoutAlimentPlanPageState();
}

class _AjoutAlimentPlanPageState extends State<AjoutAlimentPlanPage> {
  late final ProfilEspece _profil = profilEspece(widget.espece);
  late final _marque = TextEditingController(text: widget.marqueInitiale);
  final _nom = TextEditingController();
  final _kcal = TextEditingController();
  final _compo = {for (final (k, _) in kChampsComposition) k: TextEditingController()};
  final _repartition = {
    for (final k in {...kRepartitionBarf.keys, ...kRepartitionMenagere.keys}) k: TextEditingController(),
  };
  final List<List<TextEditingController>> _table = [];
  late String _type = widget.typeInitial != null && _profil.types.contains(widget.typeInitial)
      ? widget.typeInitial! : _profil.types.first;
  late String _espece = widget.espece;
  String _stade = 'adulte';
  String _methode = '';
  String _unite = '100g';
  bool _warnOk = false;
  bool _saving = false;
  String? _erreur;

  bool get _energie => _profil.methode == 'energie';
  String get _libSansMarque => _energie ? 'Préparation maison' : 'Sans marque';
  bool get _prive => _marque.text.trim() == _libSansMarque;

  @override
  void initState() {
    super.initState();
    _ajouterLigne();
  }

  @override
  void dispose() {
    for (final c in [_marque, _nom, _kcal, ..._compo.values, ..._repartition.values, ..._table.expand((r) => r)]) {
      c.dispose();
    }
    super.dispose();
  }

  void _ajouterLigne() => _table.add([TextEditingController(), TextEditingController(), TextEditingController()]);

  EvaluationEnergie get _eval => evaluerEnergie(
        methode: _methode, type: _type, kcalTexte: _kcal.text, unite: _unite,
        compo: {for (final e in _compo.entries) e.key: e.value.text},
      );

  /// Repère de composition (BARF / ration ménagère maison) selon le type.
  Map<String, double>? get _repereType =>
      _type == 'barf' ? kRepartitionBarf : _type == 'menagere' ? kRepartitionMenagere : null;

  /// Composition d'une préparation maison : vide ou somme = 100 %.
  (Map<String, double>?, String?) _lireRepartition() {
    final repere = _repereType;
    if (repere == null) return (null, null);
    final vals = <String, double>{};
    for (final k in repere.keys) {
      final l = lireNombre(_repartition[k]!.text, zeroAutorise: true);
      if (l.err != null) return (null, 'Composition : ${l.err}');
      if (l.v != null) vals[k] = l.v!;
    }
    if (vals.isEmpty) return (null, null);
    final s = vals.values.fold<double>(0, (a, b) => a + b);
    if ((s - 100).abs() > 1) return (null, 'Composition : la somme fait ${s.round()} % au lieu de 100 %.');
    return (vals, null);
  }

  void _preremplirRepartition() {
    final repere = _repereType;
    if (repere == null) return;
    for (final e in repere.entries) {
      if (_repartition[e.key]!.text.isEmpty) _repartition[e.key]!.text = e.value.round().toString();
    }
  }

  Future<void> _enregistrer() async {
    final marque = _marque.text.trim(), nom = _nom.text.trim();
    if (marque.isEmpty || nom.isEmpty) return setState(() => _erreur = 'Indiquez la marque et le nom de l’aliment.');
    final ev = _eval;
    if (_energie) {
      if (_methode.isEmpty) return setState(() => _erreur = 'Choisissez comment renseigner la valeur énergétique.');
      if (ev.err != null) return setState(() => _erreur = ev.err);
      if (ev.erreursChamps.isNotEmpty) return setState(() => _erreur = 'Corrigez les valeurs signalées en rouge.');
      if (!ev.ok) {
        return setState(() => _erreur = _methode == 'A'
            ? 'Indiquez la valeur énergétique.' : 'Complétez la composition analytique.');
      }
      if (ev.warn != null && !_warnOk) return setState(() => _erreur = 'Confirmez la valeur énergétique signalée ci-dessus.');
    }
    final (repartition, errRep) = _prive ? _lireRepartition() : (null, null);
    if (errRep != null) return setState(() => _erreur = errRep);
    final tableau = <Map<String, dynamic>>[];
    if (_energie && _stade == 'croissance') {
      for (final r in _table) {
        final age = lireNombre(r[0].text), pa = lireNombre(r[1].text), g = lireNombre(r[2].text);
        if (r.every((c) => c.text.trim().isEmpty)) continue;
        final err = age.err ?? pa.err ?? g.err;
        if (err != null) return setState(() => _erreur = 'Tableau de rationnement : $err');
        if (age.v == null || g.v == null) {
          return setState(() => _erreur = 'Tableau de rationnement : chaque ligne demande au moins l’âge et la quantité.');
        }
        tableau.add({'age_mois': age.v, if (pa.v != null) 'poids_adulte_kg': pa.v, 'g_jour': g.v});
      }
    }
    final aliment = AlimentPlan(
      marque: marque, gamme: nom, type: _type,
      kcal: _energie && _methode != 'C' ? ev.kcal : null,
      source: !_energie || _methode == 'C' ? null : (ev.estime ? 'composition' : 'fabricant'),
      repartition: repartition,
    )..tableauCroissance = tableau;
    if (_prive) {
      if (mounted) Navigator.of(context).pop(aliment);
      return;
    }
    setState(() { _saving = true; _erreur = null; });
    final supa = Supabase.instance.client;
    try {
      final existant = await supa.from('marques_aliments').select('id')
          .eq('espece', _espece).ilike('marque', marque).ilike('gamme', nom)
          .eq('type_aliment', typeVersCatalogue(_type)).limit(1);
      if ((existant as List).isNotEmpty) {
        setState(() { _saving = false; _erreur = 'Cet aliment existe déjà dans le catalogue : sélectionnez-le dans la liste.'; });
        return;
      }
      final row = await supa.from('marques_aliments').insert({
        'marque': marque, 'gamme': nom, 'espece': _espece,
        'type_aliment': typeVersCatalogue(_type),
        'age_categorie': _stade == 'croissance' ? 'junior' : _stade,
        'densite_kcal_100g': aliment.kcal,
        'kcal_estime': aliment.source == 'composition',
        'kcal_source': aliment.source,
        if (_methode == 'B') 'composition': _eval.composition,
        if (tableau.isNotEmpty) 'tableau_croissance': tableau,
        'doses': <dynamic>[],
        'notes': 'Ajouté par un membre',
        'ajoute_par_uid': FirebaseAuth.instance.currentUser?.uid,
      }).select('id').single();
      aliment.id = row['id']?.toString();
      if (mounted) Navigator.of(context).pop(aliment);
    } on PostgrestException catch (e) {
      setState(() {
        _saving = false;
        _erreur = e.code == '23505' || e.code == '23514'
            ? e.message
            : e.code == 'PGRST204'
                ? 'Enregistrement impossible : la base de données doit être mise à jour (migration alimentation).'
                : 'Enregistrement impossible, réessayez.';
      });
    } catch (_) {
      setState(() { _saving = false; _erreur = 'Enregistrement impossible, réessayez.'; });
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  Widget _champ(String label, TextEditingController c, {String? hint, String? suffixe, String? erreur, bool nombre = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          onChanged: (_) => setState(() { _erreur = null; _warnOk = false; }),
          keyboardType: nombre ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          style: _st(15),
          decoration: InputDecoration(
            labelText: label, hintText: hint, suffixText: suffixe, errorText: erreur, errorMaxLines: 3,
            labelStyle: _st(14, c: _gris), filled: true, fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );

  Widget _pastilles(List<(String, String)> options, String valeur, ValueChanged<String> choisir) => Wrap(
        spacing: 8, runSpacing: 8,
        children: [
          for (final (v, l) in options)
            ChoiceChip(
              label: Text(l, style: _st(14, w: FontWeight.w700, c: valeur == v ? Colors.white : _texte)),
              selected: valeur == v,
              selectedColor: _teal,
              backgroundColor: Colors.white,
              showCheckmark: false,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onSelected: (_) => setState(() { choisir(v); _erreur = null; _warnOk = false; }),
            ),
        ],
      );

  Widget _methodeCarte(String code, String titre, String sous) {
    final on = _methode == code;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() { _methode = code; _erreur = null; _warnOk = false; }),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: on ? const Color(0xFFE8F0F2) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? _teal : const Color(0xFFDCE3E6), width: 2),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titre, style: _st(14.5, w: FontWeight.w700)),
            Text(sous, style: _st(12.5, c: _gris)),
          ]),
        ),
      ),
    );
  }

  Widget _encadre(String t, {Color fond = const Color(0xFFE8F0F2), Color c = _texte}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(10)),
        child: Text(t, style: _st(13.5, c: c)),
      );

  @override
  Widget build(BuildContext context) {
    final ev = _eval;
    final identiteOk = _marque.text.trim().isNotEmpty && _nom.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F8),
      appBar: AppBar(
        backgroundColor: _teal, foregroundColor: Colors.white,
        title: Text('Ajouter mon aliment', style: _st(17, w: FontWeight.w800, c: Colors.white)),
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              _champ('Marque', _marque, hint: _energie ? 'Ex. Easy BARF, Josera…' : 'Ex. Cavalor, Versele-Laga…'),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OutlinedButton(
                    onPressed: () => setState(() { _marque.text = _libSansMarque; _preremplirRepartition(); }),
                    child: Text(_libSansMarque, style: _st(13.5, w: FontWeight.w700, c: _teal)),
                  ),
                ),
              ),
              _champ('Nom de l’aliment ou de la recette', _nom,
                  hint: _energie ? 'Ex. Bœuf menu complet' : 'Ex. Foin de prairie, Sport Mix…'),
              Text('Type', style: _st(14.5, w: FontWeight.w700)),
              const SizedBox(height: 8),
              _pastilles([for (final t in _profil.types) (t, kLibellesTypeAliment[t]!)], _type, (v) {
                _type = v;
                if (_prive) _preremplirRepartition();
              }),
              const SizedBox(height: 14),
              if (_energie) ...[
                Text('Espèce', style: _st(14.5, w: FontWeight.w700)),
                const SizedBox(height: 8),
                _pastilles(const [('chien', 'Chien'), ('chat', 'Chat')], _espece, (v) => _espece = v),
                const SizedBox(height: 14),
                Text('Stade de vie', style: _st(14.5, w: FontWeight.w700)),
                const SizedBox(height: 8),
                _pastilles(const [('croissance', 'Croissance'), ('adulte', 'Adulte'), ('senior', 'Senior'), ('tous', 'Tous âges')],
                    _stade, (v) => _stade = v),
                const SizedBox(height: 16),
              ],
              if (_repereType != null && _prive) ...[
                Text('Composition de votre préparation (facultatif)', style: _st(14.5, w: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Détaillée en grammes à chaque repas. Repère proposé, à adapter à votre recette.', style: _st(12.5, c: _gris)),
                const SizedBox(height: 8),
                for (final k in _repereType!.keys)
                  _champ(kLibellesRepartition[k]!, _repartition[k]!, suffixe: '%', nombre: true),
              ],
              if (_energie && identiteOk) ...[
                Text('Valeur énergétique', style: _st(15, w: FontWeight.w800)),
                const SizedBox(height: 8),
                _methodeCarte('A', 'Je connais les kcal', 'Indiquées sur l’emballage, pour 100 g ou pour 1 kg'),
                _methodeCarte('B', 'J’ai la composition analytique', 'Protéines, matières grasses, fibres, cendres, humidité'),
                _methodeCarte('C', 'Je n’ai aucune information', 'Je saisirai les grammes moi-même'),
                if (_methode == 'A') ...[
                  _champ('Valeur énergétique', _kcal, nombre: true, hint: _unite == 'kg' ? 'Ex. 3700' : 'Ex. 370',
                      suffixe: _unite == 'kg' ? 'kcal/kg' : 'kcal/100 g'),
                  _pastilles(const [('100g', 'kcal/100 g'), ('kg', 'kcal/kg')], _unite, (v) => _unite = v),
                  const SizedBox(height: 10),
                ],
                if (_methode == 'B') ...[
                  _encadre('Recopiez la « composition analytique » de l’emballage (pas le tableau des quantités par poids). '
                      'Les glucides sont facultatifs : ils sont estimés par différence.'),
                  for (final (k, l) in kChampsComposition)
                    _champ(l, _compo[k]!, suffixe: '%', nombre: true, erreur: ev.erreursChamps[k]),
                ],
                if (_methode == 'C')
                  _encadre('Valeur énergétique non renseignée — ration personnalisée. Vous indiquerez les grammes vous-même ; '
                      'vous pourrez compléter plus tard.', fond: const Color(0xFFEEF2F3)),
                if (ev.info != null) _encadre(ev.info!),
                if (ev.err != null) _encadre(ev.err!, fond: const Color(0xFFFDECEA), c: const Color(0xFF8C1D16)),
                if (ev.warn != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFFFF4E0), borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE9C27A))),
                    child: Column(children: [
                      Text(ev.warn!, style: _st(13.5)),
                      CheckboxListTile(
                        value: _warnOk, contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading,
                        activeColor: _teal,
                        title: Text('La valeur est bien celle de l’emballage', style: _st(13.5, w: FontWeight.w700)),
                        onChanged: (v) => setState(() { _warnOk = v ?? false; _erreur = null; }),
                      ),
                    ]),
                  ),
                if (_stade == 'croissance' && _methode.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Tableau de rationnement du fabricant (facultatif)', style: _st(14.5, w: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Recopiez seulement les colonnes présentes sur l’emballage. Il sert à afficher la recommandation '
                      'du fabricant ; il n’est pas converti en kcal.', style: _st(12.5, c: _gris)),
                  const SizedBox(height: 8),
                  for (final r in _table)
                    Row(children: [
                      Expanded(child: _champ('Âge (mois)', r[0], nombre: true)),
                      const SizedBox(width: 6),
                      Expanded(child: _champ('Poids adulte', r[1], nombre: true, suffixe: 'kg')),
                      const SizedBox(width: 6),
                      Expanded(child: _champ('Quantité', r[2], nombre: true, suffixe: 'g/j')),
                    ]),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => setState(_ajouterLigne),
                      child: Text('+ Ajouter une ligne', style: _st(14, w: FontWeight.w800, c: _teal)),
                    ),
                  ),
                ],
              ],
              if (!_prive && identiteOk)
                Text('L’aliment rejoindra le catalogue PetsMatch, visible des autres membres (« ajouté par un membre »).',
                    style: _st(12.5, c: _gris)),
              if (_erreur != null) ...[
                const SizedBox(height: 10),
                Text(_erreur!, style: _st(14, w: FontWeight.w700, c: _rouge)),
              ],
            ]),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFDCE3E6)))),
            child: Row(children: [
              Expanded(child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Annuler', style: _st(15, w: FontWeight.w700)),
              )),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50)),
                onPressed: _saving ? null : _enregistrer,
                child: Text(_saving ? 'Enregistrement…' : 'Ajouter et sélectionner', style: _st(15, w: FontWeight.w800, c: Colors.white)),
              )),
            ]),
          ),
        ]),
      ),
    );
  }
}
