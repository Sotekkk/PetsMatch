import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

// Race d'un animal : liste déroulante des races de l'espèce quand elle existe
// (assets/*_breeds.json), « Autre race » pour saisir librement ; champ libre
// pour les espèces sans liste. Miroir site : components/animaux/ChampRace.tsx.
const _fichiersRaces = {
  'chien': 'assets/dog_breeds.json', 'chat': 'assets/cat_breeds.json', 'cheval': 'assets/horse_breeds.json',
  'lapin': 'assets/rabbit_breeds.json', 'nac': 'assets/nac_breeds.json', 'oiseau': 'assets/bird_breeds.json',
  'ovin': 'assets/sheep_breeds.json', 'caprin': 'assets/goat_breeds.json', 'porcin': 'assets/pig_breeds.json',
};

class ChampRace extends StatefulWidget {
  final String espece;
  final TextEditingController controller;
  final InputDecoration decoration;
  const ChampRace({super.key, required this.espece, required this.controller, required this.decoration});

  @override
  State<ChampRace> createState() => _ChampRaceState();
}

class _ChampRaceState extends State<ChampRace> {
  List<String> _races = [];
  bool _libre = false;
  String? _pour;

  Future<void> _charger() async {
    final e = widget.espece;
    if (_pour == e) return;
    _pour = e;
    final f = _fichiersRaces[e];
    if (f == null) { if (mounted) setState(() => _races = []); return; }
    try {
      final l = (jsonDecode(await rootBundle.loadString(f)) as List).map((x) => x.toString()).toList();
      if (mounted) setState(() => _races = l);
    } catch (_) {
      if (mounted) setState(() => _races = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    _charger();
    final v = widget.controller.text;
    if (_races.isEmpty || _libre || (v.isNotEmpty && !_races.contains(v))) {
      return TextField(
        controller: widget.controller,
        decoration: widget.decoration.copyWith(
          suffixIcon: _races.isEmpty ? null : TextButton(
            onPressed: () => setState(() { _libre = false; widget.controller.clear(); }),
            child: const Text('Liste', style: TextStyle(fontFamily: 'Galey')),
          ),
        ),
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: v.isEmpty ? null : v,
      isExpanded: true,
      decoration: widget.decoration,
      items: [
        for (final r in _races) DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis)),
        const DropdownMenuItem(value: '__autre__', child: Text('Autre race (saisir)')),
      ],
      onChanged: (r) => setState(() {
        if (r == '__autre__') { _libre = true; widget.controller.clear(); } else { widget.controller.text = r ?? ''; }
      }),
    );
  }
}
