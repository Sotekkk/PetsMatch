import 'package:flutter/material.dart';
import 'balades_ludiques_shared.dart';

class BaladesLudiquesFiltresSheet extends StatefulWidget {
  final String espece;
  final bool famille;
  final bool sportif;
  final bool pmr;
  final bool gratuit;
  final String? difficulte;
  final int? dureeMax;

  const BaladesLudiquesFiltresSheet({
    super.key,
    required this.espece,
    required this.famille,
    required this.sportif,
    required this.pmr,
    required this.gratuit,
    required this.difficulte,
    required this.dureeMax,
  });

  @override
  State<BaladesLudiquesFiltresSheet> createState() => _BaladesLudiquesFiltresSheetState();
}

class _BaladesLudiquesFiltresSheetState extends State<BaladesLudiquesFiltresSheet> {
  late String _espece = widget.espece;
  late bool _famille = widget.famille;
  late bool _sportif = widget.sportif;
  late bool _pmr = widget.pmr;
  late bool _gratuit = widget.gratuit;
  late String? _difficulte = widget.difficulte;
  late int? _dureeMax = widget.dureeMax;

  static const _dureeOptions = [(30, '< 30 min'), (60, '< 1h'), (120, '< 2h')];

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: value ? kBlTeal : Colors.white,
          border: Border.all(color: value ? kBlTeal : Colors.grey.shade300),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
            color: value ? Colors.white : kBlDark)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Filtres', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
          TextButton(
            onPressed: () => setState(() {
              _espece = 'tous'; _famille = false; _sportif = false; _pmr = false; _gratuit = false; _difficulte = null; _dureeMax = null;
            }),
            child: const Text('Réinitialiser', style: TextStyle(fontFamily: 'Galey', color: kBlTeal)),
          ),
        ]),
        const SizedBox(height: 12),
        const Text('Espèce', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: kBlEspeces.map((e) =>
          GestureDetector(
            onTap: () => setState(() => _espece = e.$1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: _espece == e.$1 ? kBlTeal : Colors.white,
                border: Border.all(color: _espece == e.$1 ? kBlTeal : Colors.grey.shade300),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${e.$3} ${e.$2}', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                  color: _espece == e.$1 ? Colors.white : kBlDark)),
            ),
          ),
        ).toList()),
        const SizedBox(height: 16),
        const Text('Difficulté', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          GestureDetector(
            onTap: () => setState(() => _difficulte = null),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: _difficulte == null ? kBlTeal : Colors.white,
                border: Border.all(color: _difficulte == null ? kBlTeal : Colors.grey.shade300),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('Toutes', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                  color: _difficulte == null ? Colors.white : kBlDark)),
            ),
          ),
          ...kBlDifficultes.map((d) => GestureDetector(
            onTap: () => setState(() => _difficulte = d.$1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: _difficulte == d.$1 ? d.$3 : Colors.white,
                border: Border.all(color: _difficulte == d.$1 ? d.$3 : Colors.grey.shade300),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(d.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                  color: _difficulte == d.$1 ? Colors.white : kBlDark)),
            ),
          )),
        ]),
        const SizedBox(height: 16),
        const Text('Durée', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          GestureDetector(
            onTap: () => setState(() => _dureeMax = null),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: _dureeMax == null ? kBlTeal : Colors.white,
                border: Border.all(color: _dureeMax == null ? kBlTeal : Colors.grey.shade300),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('Toutes', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                  color: _dureeMax == null ? Colors.white : kBlDark)),
            ),
          ),
          ..._dureeOptions.map((d) => GestureDetector(
            onTap: () => setState(() => _dureeMax = d.$1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: _dureeMax == d.$1 ? kBlTeal : Colors.white,
                border: Border.all(color: _dureeMax == d.$1 ? kBlTeal : Colors.grey.shade300),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(d.$2, style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                  color: _dureeMax == d.$1 ? Colors.white : kBlDark)),
            ),
          )),
        ]),
        const SizedBox(height: 16),
        const Text('Autres critères', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _toggle('👨‍👩‍👧 Famille', _famille, (v) => setState(() => _famille = v)),
          _toggle('🏃 Sportif', _sportif, (v) => setState(() => _sportif = v)),
          _toggle('♿ Accessible PMR', _pmr, (v) => setState(() => _pmr = v)),
          _toggle('🆓 Gratuit', _gratuit, (v) => setState(() => _gratuit = v)),
        ]),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context, {
              'espece': _espece, 'famille': _famille, 'sportif': _sportif,
              'pmr': _pmr, 'gratuit': _gratuit, 'difficulte': _difficulte, 'dureeMax': _dureeMax,
            }),
            style: ElevatedButton.styleFrom(
              backgroundColor: kBlTeal, padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Appliquer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ),
      ]),
    );
  }
}
