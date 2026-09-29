import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Colonnes lues par les sélecteurs d'aliment (fiche animal particulier /
/// éleveur) — l'ajout renvoie la même forme pour être sélectionné aussitôt.
const kMarqueAlimentCols =
    'id, marque, gamme, densite_kcal_100g, doses, age_categorie, taille_race, type_aliment, ajoute_par_uid, kcal_estime';

/// Estimation de la densité énergétique (kcal/100 g) quand l'utilisateur ne
/// la connaît pas — moyennes du catalogue marques_aliments (sept. 2026) par
/// espèce / type / âge, formule stérilisé/light un peu moins énergétique.
/// null = pas d'estimation fiable (espèce peu représentée).
double? estimationKcal100g({
  required String espece,
  required String type,
  required String age,
  required bool sterilise,
}) {
  final e = espece.toLowerCase();
  final patee = type == 'pâtée';
  final jr = age == 'junior';
  final sr = age == 'senior';
  final st = sterilise && !jr;
  if (e == 'chien') {
    if (patee) return jr ? 90 : st ? 75 : sr ? 80 : 85;
    return jr ? 390 : st ? 330 : sr ? 350 : 370;
  }
  if (e == 'chat') {
    if (patee) return jr ? 80 : (st || sr) ? 70 : 75;
    return jr ? 390 : st ? 340 : sr ? 345 : 360;
  }
  if (patee) return null;
  if (e == 'lapin') return 280;
  if (e == 'cheval') return 300;
  if (e == 'oiseau') return 365;
  return null;
}

/// Ouvre le formulaire « Ajouter mon aliment » ; renvoie la ligne créée
/// (colonnes [kMarqueAlimentCols]) ou null si annulé.
Future<Map<String, dynamic>?> showAjoutAlimentSheet(
  BuildContext context, {
  required String espece,
  String marqueInitiale = '',
  String ageInitial = 'adulte',
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AjoutAlimentSheet(
      espece: espece, marqueInitiale: marqueInitiale, ageInitial: ageInitial),
  );
}

class _AjoutAlimentSheet extends StatefulWidget {
  final String espece;
  final String marqueInitiale;
  final String ageInitial;
  const _AjoutAlimentSheet({required this.espece, required this.marqueInitiale, required this.ageInitial});
  @override
  State<_AjoutAlimentSheet> createState() => _AjoutAlimentSheetState();
}

class _AjoutAlimentSheetState extends State<_AjoutAlimentSheet> {
  static const _teal = Color(0xFF0C5C6C);
  late final _marqueCtrl = TextEditingController(text: widget.marqueInitiale);
  final _gammeCtrl = TextEditingController();
  final _kcalCtrl = TextEditingController();
  final List<(TextEditingController, TextEditingController)> _doses = [];
  String _type = 'croquettes';
  late String _age = const ['junior', 'adulte', 'senior'].contains(widget.ageInitial) ? widget.ageInitial : 'adulte';
  bool _sterilise = false;
  String? _taille;
  bool _saving = false;
  String? _error;

  double? get _estimation => estimationKcal100g(
      espece: widget.espece, type: _type, age: _age, sterilise: _sterilise);

  double? get _kcalSaisi => double.tryParse(_kcalCtrl.text.trim().replaceAll(',', '.'));

  @override
  void dispose() {
    _marqueCtrl.dispose();
    _gammeCtrl.dispose();
    _kcalCtrl.dispose();
    for (final d in _doses) { d.$1.dispose(); d.$2.dispose(); }
    super.dispose();
  }

  Future<void> _enregistrer() async {
    final marque = _marqueCtrl.text.trim();
    final gamme = _gammeCtrl.text.trim();
    if (marque.isEmpty || gamme.isEmpty) {
      setState(() => _error = 'Indiquez la marque et le nom du produit.');
      return;
    }
    final saisi = _kcalSaisi;
    if (_kcalCtrl.text.trim().isNotEmpty && (saisi == null || saisi < 20 || saisi > 700)) {
      setState(() => _error = 'Valeur énergétique invalide (en kcal pour 100 g, ex. 370).');
      return;
    }
    final doses = <Map<String, num>>[];
    for (final d in _doses) {
      final p = double.tryParse(d.$1.text.trim().replaceAll(',', '.'));
      final g = double.tryParse(d.$2.text.trim().replaceAll(',', '.'));
      if (p != null && g != null && p > 0 && g > 0) doses.add({'poids_kg': p, 'grammes': g});
    }
    doses.sort((a, b) => a['poids_kg']!.compareTo(b['poids_kg']!));
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() { _saving = true; _error = null; });
    try {
      final densite = saisi ?? _estimation;
      final row = await Supabase.instance.client.from('marques_aliments').insert({
        'marque': marque,
        'gamme': gamme,
        'espece': widget.espece.toLowerCase(),
        'type_aliment': _type,
        'age_categorie': _age,
        'formule_sterilise': _sterilise && _age != 'junior',
        if (_taille != null) 'taille_race': _taille,
        'densite_kcal_100g': densite,
        'kcal_estime': saisi == null,
        'doses': doses,
        'notes': 'Ajouté par un membre',
        'ajoute_par_uid': uid,
      }).select(kMarqueAlimentCols).single();
      if (mounted) Navigator.pop(context, Map<String, dynamic>.from(row));
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = 'Enregistrement impossible, réessayez.'; });
    }
  }

  Widget _chips<T>(List<(T, String)> options, T? value, ValueChanged<T> onPick) => Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final o in options)
            ChoiceChip(
              label: Text(o.$2, style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
              selected: value == o.$1,
              selectedColor: _teal.withValues(alpha: 0.15),
              onSelected: (_) => onPick(o.$1),
            ),
        ],
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(t, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13.5)),
      );

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade400),
        isDense: true,
        filled: true,
        fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      );

  @override
  Widget build(BuildContext context) {
    final est = _estimation;
    final estTxt = est != null ? '${est.round()} kcal/100 g' : null;
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(children: [
        Center(child: Container(margin: const EdgeInsets.symmetric(vertical: 12), width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
        const Text('Ajouter mon aliment',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17, color: Color(0xFF1F2A2E))),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
            children: [
              _label('Marque *'),
              TextField(controller: _marqueCtrl, style: const TextStyle(fontFamily: 'Galey'), decoration: _deco('Ex : Josera, Carnilove…')),
              _label('Nom du produit / gamme *'),
              TextField(controller: _gammeCtrl, style: const TextStyle(fontFamily: 'Galey'), decoration: _deco('Ex : Adult Medium Agneau')),
              _label('Type'),
              _chips<String>(const [('croquettes', 'Croquettes'), ('pâtée', 'Pâtée')], _type, (v) => setState(() => _type = v)),
              _label('Âge'),
              _chips<String>(const [('junior', 'Junior / chiot, chaton'), ('adulte', 'Adulte'), ('senior', 'Senior')], _age,
                  (v) => setState(() => _age = v)),
              if (_age != 'junior')
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _sterilise,
                  activeThumbColor: _teal,
                  onChanged: (v) => setState(() => _sterilise = v),
                  title: const Text('Formule stérilisé / light', style: TextStyle(fontFamily: 'Galey', fontSize: 14)),
                ),
              if (widget.espece.toLowerCase() == 'chien') ...[
                _label('Taille de race (facultatif)'),
                _chips<String?>(const [(null, 'Toutes'), ('petite', 'Petite'), ('moyenne', 'Moyenne'), ('grande', 'Grande')],
                    _taille, (v) => setState(() => _taille = v)),
              ],
              _label('Valeur énergétique (kcal pour 100 g)'),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFFFF7E6), borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF5C77E))),
                child: Text(
                  '⚠️ Information essentielle pour calculer la bonne ration. Elle figure sur le paquet '
                  '(« valeur énergétique » ou « énergie métabolisable », en kcal/100 g ou kcal/kg ÷ 10).\n'
                  '${estTxt != null ? 'Si vous ne l\'avez pas, nous utiliserons une estimation ($estTxt) : la ration sera moins précise.' : 'Sans elle, la ration ne pourra pas être calculée pour cette espèce.'}',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Color(0xFF7A4B00), height: 1.35),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _kcalCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontFamily: 'Galey'),
                decoration: _deco(estTxt != null ? 'Ex : ${est!.round()}' : 'Ex : 370').copyWith(suffixText: 'kcal/100 g'),
              ),
              _label('Tableau de rationnement du paquet (recommandé)'),
              Text('Au dos du paquet : la quantité par jour selon le poids de l\'animal. Si vous la renseignez, '
                  'la ration conseillée s\'appuie dessus.',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              for (var i = 0; i < _doses.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Expanded(child: TextField(controller: _doses[i].$1, style: const TextStyle(fontFamily: 'Galey'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _deco('Poids').copyWith(suffixText: 'kg'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: _doses[i].$2, style: const TextStyle(fontFamily: 'Galey'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _deco('Quantité').copyWith(suffixText: 'g/jour'))),
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.grey.shade500),
                      onPressed: () => setState(() { final d = _doses.removeAt(i); d.$1.dispose(); d.$2.dispose(); }),
                    ),
                  ]),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _doses.add((TextEditingController(), TextEditingController()))),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Ajouter une ligne poids → quantité', style: TextStyle(fontFamily: 'Galey')),
                  style: TextButton.styleFrom(foregroundColor: _teal),
                ),
              ),
              if (_error != null)
                Padding(padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!, style: const TextStyle(fontFamily: 'Galey', color: Colors.red, fontSize: 13))),
              const SizedBox(height: 12),
              Text('L\'aliment sera visible des autres membres pour cette espèce (« ajouté par un membre »).',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade500)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _enregistrer,
                  style: ElevatedButton.styleFrom(backgroundColor: _teal, padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  child: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Ajouter et sélectionner',
                          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}
