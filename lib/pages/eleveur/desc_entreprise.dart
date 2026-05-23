import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/condition_general.dart';
import 'package:flutter/material.dart';

class DescProEntreprise extends StatefulWidget {
  const DescProEntreprise({super.key});
  @override
  State<DescProEntreprise> createState() => _DescProEntrepriseState();
}

class _DescProEntrepriseState extends State<DescProEntreprise> {
  static const _green = Color(0xFF6E9E57);
  static const _teal = Color(0xFF0C5C6C);
  static const _bg = Color(0xFFF8F8F6);

  final _descCtrl = TextEditingController();

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isElevage = User_Info.isElevage;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: Text(
          isElevage ? 'Votre élevage' : 'Votre société',
          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(24),
          child: _StepBar(current: 4, total: 4),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            isElevage ? 'Parlez-nous de votre élevage' : 'Parlez-nous de votre société',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20, color: Color(0xFF1F2A2E)),
          ),
          const SizedBox(height: 6),
          Text(
            'Décrivez votre activité, vos valeurs, vos spécialités…',
            style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: TextFormField(
              controller: _descCtrl,
              maxLines: 10,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(
                hintText: isElevage
                    ? 'Ex: Élevage familial spécialisé dans les Labradors depuis 15 ans…'
                    : 'Ex: Cabinet vétérinaire proposant des soins de proximité…',
                hintStyle: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade400),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF5EA),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _green.withOpacity(0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, color: _green, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Votre compte sera actif après validation par notre équipe. Vous recevrez un email de confirmation.',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF1F2A2E)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                User_Info.descEntreprise = _descCtrl.text;
                User_Info.isValidate = false;
                Navigator.push(context, MaterialPageRoute(builder: (_) => ConditionGeneral()));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('FINALISER',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
            ),
          ),
        ]),
      ),
    );
  }
}

class _StepBar extends StatelessWidget {
  final int current;
  final int total;
  const _StepBar({required this.current, required this.total});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
    child: Row(
      children: List.generate(total, (i) => Expanded(
        child: Container(
          height: 3,
          margin: EdgeInsets.only(right: i < total - 1 ? 4 : 0),
          decoration: BoxDecoration(
            color: i < current ? Colors.white : Colors.white38,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      )),
    ),
  );
}
