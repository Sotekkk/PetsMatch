// Pension — horaires d'arrivée / de départ (user_profiles.pension_horaires,
// migration_pension_horaires.sql) : lecture, durée d'une arrivée / d'un départ
// et formulaire de réglage (page Tarifs). Les créneaux libres sont calculés par
// le serveur (route /api/pension/sejour). Miroir site : lib/pension-horaires.ts
// et components/pension/HorairesPensionForm.tsx.
import 'package:flutter/material.dart';

const Map<String, dynamic> kHorairesPensionDefaut = {
  'arrivees': [{'debut': '08:00', 'fin': '10:00'}, {'debut': '17:00', 'fin': '19:00'}],
  'departs': [{'debut': '08:00', 'fin': '10:00'}, {'debut': '17:00', 'fin': '19:00'}],
  'duree_arrivee_nouveau': 30, 'duree_arrivee_habitue': 15, 'duree_depart': 15,
  'minutes_par_animal': 5, 'max_par_creneau': 3,
};

final _hm = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');
bool heureValidePension(String? h) => h != null && _hm.hasMatch(h);
int _min(String h) { final m = _hm.firstMatch(h)!; return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!); }

/// Réglages nettoyés ; null = pas d'horaires (le client ne choisit pas d'heure).
Map<String, dynamic>? lireHorairesPension(Object? brut) {
  if (brut is! Map) return null;
  List<Map<String, String>> plages(Object? l) => [
        for (final p in (l is List ? l : const []))
          if (p is Map && heureValidePension(p['debut']?.toString()) && heureValidePension(p['fin']?.toString())
              && _min(p['debut'].toString()) < _min(p['fin'].toString()))
            {'debut': p['debut'].toString(), 'fin': p['fin'].toString()},
      ];
  int n(Object? v, int d, [int min = 0, int max = 600]) {
    final x = num.tryParse(v?.toString() ?? '');
    return x == null ? d : x.round().clamp(min, max);
  }
  final h = <String, dynamic>{
    'arrivees': plages(brut['arrivees']), 'departs': plages(brut['departs']),
    'duree_arrivee_nouveau': n(brut['duree_arrivee_nouveau'], 30, 5), 'duree_arrivee_habitue': n(brut['duree_arrivee_habitue'], 15, 5),
    'duree_depart': n(brut['duree_depart'], 15, 5), 'minutes_par_animal': n(brut['minutes_par_animal'], 5, 0, 120),
    'max_par_creneau': n(brut['max_par_creneau'], 3, 1, 50),
  };
  return (h['arrivees'] as List).isEmpty && (h['departs'] as List).isEmpty ? null : h;
}

/// Durée d'une arrivée / d'un départ, arrondie au quart d'heure.
int dureePassagePension(Map<String, dynamic> h, {required bool depart, required int nbAnimaux, required bool nouveau}) {
  final base = depart ? h['duree_depart'] as int : nouveau ? h['duree_arrivee_nouveau'] as int : h['duree_arrivee_habitue'] as int;
  final total = base + (nbAnimaux - 1).clamp(0, 50) * (h['minutes_par_animal'] as int);
  final arrondi = ((total / 15).ceil()) * 15;
  return arrondi < 15 ? 15 : arrondi;
}

/// Réglage des horaires (page Tarifs). `valeur` null = pas d'horaires.
class HorairesPensionForm extends StatelessWidget {
  final Map<String, dynamic>? valeur;
  final ValueChanged<Map<String, dynamic>?> onChange;
  final Color couleur;
  const HorairesPensionForm({super.key, required this.valeur, required this.onChange, this.couleur = const Color(0xFF6E9E57)});

  Map<String, dynamic> get _h => valeur ?? Map<String, dynamic>.from(kHorairesPensionDefaut);
  void _maj(String cle, Object v) => onChange({..._h, cle: v});

  Future<String?> _choisirHeure(BuildContext context, String actuelle) async {
    final m = heureValidePension(actuelle) ? _min(actuelle) : 9 * 60;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60));
    if (t == null) return null;
    final quart = (t.minute / 15).round() * 15;
    final total = t.hour * 60 + (quart >= 60 ? 45 : quart);
    return '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
  }

  Widget _plages(BuildContext context, String titre, String cle) {
    final liste = [for (final p in (_h[cle] as List)) Map<String, String>.from((p as Map).map((k, v) => MapEntry(k.toString(), v.toString())))];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(titre, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13)),
      for (final (i, p) in liste.indexed)
        Row(children: [
          for (final champ in ['debut', 'fin']) ...[
            if (champ == 'fin') const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('à', style: TextStyle(fontFamily: 'Galey'))),
            OutlinedButton(
              onPressed: () async {
                final h = await _choisirHeure(context, p[champ] ?? '');
                if (h == null) return;
                final l = [...liste]; l[i] = {...p, champ: h};
                _maj(cle, l);
              },
              style: OutlinedButton.styleFrom(foregroundColor: couleur, visualDensity: VisualDensity.compact),
              child: Text((p[champ] ?? '--:--').replaceAll(':', 'h'), style: const TextStyle(fontFamily: 'Galey')),
            ),
          ],
          IconButton(
            tooltip: 'Retirer', icon: Icon(Icons.close, size: 18, color: Colors.grey.shade600),
            onPressed: () => _maj(cle, [...liste]..removeAt(i)),
          ),
          if (!heureValidePension(p['debut']) || !heureValidePension(p['fin']) || _min(p['debut']!) >= _min(p['fin']!))
            const Text('plage invalide', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFFB3261E))),
        ]),
      TextButton.icon(
        onPressed: () => _maj(cle, [...liste, {'debut': '09:00', 'fin': '10:00'}]),
        icon: const Icon(Icons.add, size: 16), label: const Text('Ajouter une plage', style: TextStyle(fontFamily: 'Galey')),
        style: TextButton.styleFrom(foregroundColor: couleur, padding: EdgeInsets.zero),
      ),
    ]);
  }

  Widget _nombre(String lib, String cle, String suffixe, {int min = 0, int max = 240, int pas = 5}) {
    final v = _h[cle] as int;
    return Row(children: [
      Expanded(child: Text(lib, style: const TextStyle(fontFamily: 'Galey', fontSize: 13))),
      IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.remove_circle_outline, size: 20),
          onPressed: v - pas < min ? null : () => _maj(cle, v - pas)),
      SizedBox(width: 64, child: Text('$v $suffixe', textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13))),
      IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.add_circle_outline, size: 20),
          onPressed: v + pas > max ? null : () => _maj(cle, v + pas)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final actif = valeur != null;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: actif ? couleur.withValues(alpha: 0.4) : const Color(0xFFEEEEEE)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SwitchListTile.adaptive(
          value: actif,
          onChanged: (v) => onChange(v ? Map<String, dynamic>.from(kHorairesPensionDefaut) : null),
          activeTrackColor: couleur,
          title: const Text("Horaires d'arrivée et de départ", style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Text("À la réservation, le client choisit son heure d'arrivée et de départ parmi les créneaux encore libres.",
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
        ),
        if (actif)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _plages(context, 'Arrivées possibles', 'arrivees'),
              const SizedBox(height: 8),
              _plages(context, 'Départs possibles', 'departs'),
              const Divider(),
              _nombre("Arrivée — premier séjour", 'duree_arrivee_nouveau', 'min', min: 5),
              _nombre("Arrivée — client habitué", 'duree_arrivee_habitue', 'min', min: 5),
              _nombre('Départ', 'duree_depart', 'min', min: 5),
              _nombre('Par animal en plus', 'minutes_par_animal', 'min', max: 120),
              _nombre('Clients max par 15 min', 'max_par_creneau', '', min: 1, max: 50, pas: 1),
              Text("Arrivées et départs partagent ce maximum. Durées arrondies au quart d'heure ; vous pourrez ajuster l'heure en acceptant chaque séjour.",
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
            ]),
          ),
      ]),
    );
  }
}
