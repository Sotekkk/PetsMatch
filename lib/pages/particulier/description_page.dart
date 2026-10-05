import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/condition_general.dart';
import 'package:flutter/material.dart';

/// Inscription particulier — « Vos animaux & votre projet » (nouveau design).
/// Remplace les anciennes pages Description + Projet d'adoption (ancien
/// design, question du projet posée sans savoir si la personne avait déjà un
/// animal). Ordre : a-t-on déjà un animal ? → projet d'adoption (premier /
/// autre animal) → espèces envisagées → quelques mots (optionnel).
/// Miroir site : website/src/app/inscription/page.tsx (étape « animaux »).
class DescriptionRegistrationPage extends StatefulWidget {
  const DescriptionRegistrationPage({super.key});

  @override
  State<DescriptionRegistrationPage> createState() => _DescriptionRegistrationPageState();
}

/// Espèces proposées (même liste que le site).
const kEspecesProjet = [
  ('chien', '🐶 Chien'), ('chat', '🐱 Chat'), ('lapin', '🐰 Lapin'), ('cheval', '🐴 Cheval'),
  ('oiseau', '🐦 Oiseau'), ('nac', '🐹 NAC'), ('reptile', '🦎 Reptile'), ('autre', '🐾 Autre'),
];

/// Texte du projet d'adoption (stocké dans adoptProject, éditable ensuite
/// depuis Mon profil).
String texteProjetAdoption({required bool aDejaAnimal, required bool projet,
    required Set<String> especes, String precisions = ''}) {
  if (!projet) return '';
  final labels = kEspecesProjet.where((e) => especes.contains(e.$1)).map((e) => e.$2.split(' ').last).toList();
  final buf = StringBuffer(aDejaAnimal ? 'Projet : adopter un autre animal' : 'Projet : adopter un premier animal');
  if (labels.isNotEmpty) buf.write(' — ${labels.join(', ').toLowerCase()}');
  if (precisions.trim().isNotEmpty) buf.write('. ${precisions.trim()}');
  return buf.toString();
}

class _DescriptionRegistrationPageState extends State<DescriptionRegistrationPage> {
  static const _teal = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);
  static const _bg = Color(0xFFF8F8F6);

  bool? _aDejaAnimal;
  bool? _projet;
  final Set<String> _especes = {};
  final _precisionsCtrl = TextEditingController();
  final _bioCtrl = TextEditingController(text: User_Info.desc);

  @override
  void dispose() {
    _precisionsCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  bool get _peutContinuer => _aDejaAnimal != null && _projet != null;

  void _continuer() {
    User_Info.desc = _bioCtrl.text.trim();
    User_Info.adoptProject = texteProjetAdoption(
      aDejaAnimal: _aDejaAnimal ?? false, projet: _projet ?? false,
      especes: _especes, precisions: _precisionsCtrl.text,
    );
    User_Info.isValidate = true;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ConditionGeneral()));
  }

  Widget _card(List<Widget> children) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _question(String q) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(q, style: const TextStyle(fontFamily: 'Galey', fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1F2A2E))),
      );

  Widget _ouiNon(bool? valeur, ValueChanged<bool> onChanged, {String oui = 'Oui', String non = 'Non'}) => Row(children: [
        for (final opt in [(true, oui), (false, non)])
          Expanded(child: Padding(
            padding: EdgeInsets.only(right: opt.$1 ? 6 : 0, left: opt.$1 ? 0 : 6),
            child: GestureDetector(
              onTap: () => setState(() => onChanged(opt.$1)),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: valeur == opt.$1 ? _teal : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: valeur == opt.$1 ? _teal : const Color(0xFFE4E7E2)),
                ),
                child: Text(opt.$2, textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                        color: valeur == opt.$1 ? Colors.white : _teal)),
              ),
            ),
          )),
      ]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Inscription', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Vos animaux & votre projet',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20, color: Color(0xFF1F2A2E))),
          const SizedBox(height: 6),
          Text('Pour vous proposer les bons éleveurs, associations et services.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500)),
          const SizedBox(height: 24),

          _card([
            _question('Avez-vous déjà un ou plusieurs animaux ?'),
            _ouiNon(_aDejaAnimal, (v) => _aDejaAnimal = v),
            if (_aDejaAnimal == true)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Vous pourrez créer leur fiche juste après l\'inscription.',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
              ),
          ]),

          if (_aDejaAnimal != null)
            _card([
              _question(_aDejaAnimal == true
                  ? 'Avez-vous un projet d\'adoption pour un autre animal ?'
                  : 'Avez-vous un projet d\'adoption pour un premier animal ?'),
              _ouiNon(_projet, (v) => _projet = v),
              if (_projet == true) ...[
                const SizedBox(height: 14),
                const Text('Quelle(s) espèce(s) ?', style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final e in kEspecesProjet)
                    FilterChip(
                      label: Text(e.$2, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                      selected: _especes.contains(e.$1),
                      selectedColor: _green.withValues(alpha: 0.2),
                      checkmarkColor: _green,
                      onSelected: (v) => setState(() => v ? _especes.add(e.$1) : _especes.remove(e.$1)),
                    ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: _precisionsCtrl,
                  maxLines: 2,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Précisions (race, délai, mode de vie…) — optionnel',
                    hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                  ),
                ),
              ],
            ]),

          _card([
            _question('Quelques mots sur vous (optionnel)'),
            TextField(
              controller: _bioCtrl,
              maxLines: 3,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Votre mode de vie, votre expérience avec les animaux…',
                hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
            ),
          ]),

          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _peutContinuer ? _continuer : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                disabledBackgroundColor: Colors.grey.shade300,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('CONTINUER',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
            ),
          ),
        ]),
      ),
    );
  }
}
