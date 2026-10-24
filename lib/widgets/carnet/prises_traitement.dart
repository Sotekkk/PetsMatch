import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Une prise d'un traitement : heure + quantité (« 08:00 · 1 cp »).
class PriseTraitement {
  final String heure;
  final String quantite;
  const PriseTraitement(this.heure, [this.quantite = '']);
}

/// Prises d'une ligne `traitements` : rappel_heures + rappel_quantites (même
/// ordre). Miroir site : ChampPrises (mes-animaux/[id]).
List<PriseTraitement> prisesDepuis(Map data) {
  final h = data['rappel_heures'] is List ? (data['rappel_heures'] as List).map((e) => e.toString()).toList() : <String>[];
  final q = data['rappel_quantites'] is List ? (data['rappel_quantites'] as List).map((e) => e?.toString() ?? '').toList() : <String>[];
  return [for (var i = 0; i < h.length; i++) if (h[i].isNotEmpty) PriseTraitement(h[i], i < q.length ? q[i] : '')];
}

/// Colonnes à enregistrer : rappel_heures et rappel_quantites (null si aucune
/// quantité : la posologie générale s'applique).
Map<String, dynamic> colonnesPrises(List<PriseTraitement> prises) => {
      'rappel_heures': prises.map((p) => p.heure).toList(),
      'rappel_quantites': prises.any((p) => p.quantite.trim().isNotEmpty)
          ? prises.map((p) => p.quantite.trim()).toList()
          : null,
    };

/// « 08:00 (1 cp), 20:00 (1/2 cp) » — ou les heures seules.
String prisesTexte(Map data) =>
    prisesDepuis(data).map((p) => p.quantite.isEmpty ? p.heure : '${p.heure} (${p.quantite})').join(', ');

/// Saisie des prises : chaque prise a son heure et, si elle change, sa
/// quantité (1 cp le matin, ½ cp le soir…). La notification dit alors
/// « ½ cp de [produit] à 20:00 ».
class PrisesTraitementEditor extends StatelessWidget {
  final List<PriseTraitement> prises;
  final ValueChanged<List<PriseTraitement>> onChanged;
  final Color couleur;
  const PrisesTraitementEditor({super.key, required this.prises, required this.onChanged,
      this.couleur = const Color(0xFF6E9E57)});

  Future<void> _ajouter(BuildContext context) async {
    final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 8, minute: 0));
    if (t == null || !context.mounted) return;
    final heure = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final ctrl = TextEditingController();
    final quantite = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Prise de $heure', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Quantité (facultatif)', hintText: 'ex. 1 cp, 1/2 cp, 5 ml'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Ajouter')),
        ],
      ),
    );
    ctrl.dispose();
    if (quantite == null) return;
    final liste = [...prises.where((p) => p.heure != heure), PriseTraitement(heure, quantite)]
      ..sort((a, b) => a.heure.compareTo(b.heure));
    onChanged(liste);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Prises (heure et quantité)', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final p in prises)
          Chip(
            label: Text(p.quantite.isEmpty ? p.heure : '${p.heure} · ${p.quantite}',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
            onDeleted: () => onChanged(prises.where((x) => x.heure != p.heure).toList()),
            backgroundColor: couleur.withValues(alpha: 0.12),
          ),
        ActionChip(
          avatar: const Icon(Icons.add, size: 16),
          label: const Text('Ajouter une prise', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
          onPressed: () => _ajouter(context),
        ),
      ]),
      const SizedBox(height: 4),
      Text('Indiquez la quantité si elle change selon l\'heure (1 cp le matin, ½ cp le soir…).',
          style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade600)),
    ]);
  }
}

// ── Étapes d'une posologie progressive ─────────────────────────────────────
// « 1 cp 3×/jour pendant 4 jours, puis ½ cp 3×/jour pendant 3 jours » :
// chaque étape est une ligne `traitements` du même groupe (groupe_id), notes
// préfixées « Phase i/n » (format du compte rendu vétérinaire, lu par
// resume_traitement.dart). Miroir site : saveTraitement(…, etapeDe).

/// Début de l'étape suivante : le lendemain de la fin de [etape] (date de fin,
/// sinon date de début + durée des rappels), à défaut aujourd'hui.
DateTime debutEtapeSuivante(Map etape) {
  final debut = DateTime.tryParse(etape['date']?.toString() ?? '');
  var fin = DateTime.tryParse(etape['date_fin']?.toString() ?? '');
  final duree = int.tryParse('${etape['rappel_duree_jours'] ?? ''}') ?? 0;
  if (fin == null && debut != null && duree > 0) fin = debut.add(Duration(days: duree - 1));
  if (fin == null) return DateTime.now();
  return DateTime(fin.year, fin.month, fin.day).add(const Duration(days: 1));
}

/// Renumérote les étapes existantes du groupe de [etape] (« Phase i/n », n
/// comptant les [nouvelles] étapes ajoutées) et renvoie l'identifiant du
/// groupe, le nombre d'étapes existantes et le préfixe de la 1re nouvelle.
Future<({String id, String prefixe, int existantes, int total})> preparerEtapeSuivante(
    String animalId, Map etape, {int nouvelles = 1}) async {
  final supa = Supabase.instance.client;
  final gid = (etape['groupe_id'] ?? etape['id']).toString();
  final rows = await supa.from('traitements').select('id, notes, date')
      .eq('animal_id', animalId).or('groupe_id.eq.$gid,id.eq.${etape['id']}');
  final liste = List<Map<String, dynamic>>.from(rows as List)
    ..sort((a, b) => (a['date'] ?? '').toString().compareTo((b['date'] ?? '').toString()));
  final n = liste.length + nouvelles;
  for (var i = 0; i < liste.length; i++) {
    final sans = (liste[i]['notes'] ?? '').toString().replaceFirst(RegExp(r'^Phase \d+/\d+( — )?'), '').trim();
    await supa.from('traitements').update({
      'groupe_id': gid,
      'notes': ['Phase ${i + 1}/$n', if (sans.isNotEmpty) sans].join(' — '),
    }).eq('id', liste[i]['id']);
  }
  return (id: gid, prefixe: 'Phase ${liste.length + 1}/$n', existantes: liste.length, total: n);
}

// ── Saisie d'une posologie en étapes (propriétaire) ────────────────────────
// Une étape = durée (jours) + rythme (tous les N jours) + prises (heure et
// quantité). Ex. étape 1 : 4 jours, 08:00 · 1 cp et 20:00 · ½ cp ; étape 2 :
// 3 jours, 08:00 · ½ cp. La date de fin découle de la date de début et du
// total des jours. Enregistrée en une ligne `traitements` par étape (même
// groupe_id, notes « Phase i/n »). Miroir site : EtapesTraitement.tsx.

class EtapeTraitement {
  int dureeJours;
  int frequenceJours;
  List<PriseTraitement> prises;
  EtapeTraitement({this.dureeJours = 7, this.frequenceJours = 1, List<PriseTraitement>? prises})
      : prises = prises ?? [];

  /// « 1 cp à 08:00, ½ cp à 20:00 pendant 4 jours » (posologie de l'étape).
  String libelle() {
    final p = prises.map((x) => x.quantite.isEmpty ? x.heure : '${x.quantite} à ${x.heure}').join(', ');
    return [
      if (p.isNotEmpty) p,
      if (frequenceJours > 1) 'tous les $frequenceJours jours',
      'pendant $dureeJours jour${dureeJours > 1 ? 's' : ''}',
    ].join(', ');
  }
}

int totalJours(List<EtapeTraitement> etapes) => etapes.fold(0, (s, e) => s + e.dureeJours);

/// Dernier jour du traitement (inclus) : début + total des jours − 1.
DateTime? finTraitement(DateTime? debut, List<EtapeTraitement> etapes) {
  if (debut == null || etapes.isEmpty) return null;
  final d = DateTime(debut.year, debut.month, debut.day);
  return d.add(Duration(days: totalJours(etapes) - 1));
}

/// Lignes `traitements` à insérer (une par étape, dates enchaînées).
/// [base] : colonnes communes (animal_id, nom, type, source…).
List<Map<String, dynamic>> lignesEtapes({
  required Map<String, dynamic> base,
  required DateTime debut,
  required List<EtapeTraitement> etapes,
  required bool rappels,
  String notes = '',
}) {
  String ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  final groupe = etapes.length > 1 ? '${DateTime.now().microsecondsSinceEpoch}g' : null;
  var jour = DateTime(debut.year, debut.month, debut.day);
  final lignes = <Map<String, dynamic>>[];
  for (var i = 0; i < etapes.length; i++) {
    final e = etapes[i];
    final fin = jour.add(Duration(days: e.dureeJours - 1));
    final rappel = rappels && e.prises.isNotEmpty;
    lignes.add({
      ...base,
      'id': '${DateTime.now().microsecondsSinceEpoch}$i',
      if (etapes.length > 1 || (base['posologie'] ?? '').toString().trim().isEmpty) 'posologie': e.libelle(),
      'date': ymd(jour),
      'date_fin': ymd(fin),
      'notes': [if (etapes.length > 1) 'Phase ${i + 1}/${etapes.length}', if (notes.trim().isNotEmpty) notes.trim()]
          .join(' — '),
      if (groupe != null) 'groupe_id': groupe,
      'rappel_actif': rappel,
      if (rappel) ...{
        'rappel_frequence_jours': e.frequenceJours,
        'rappel_duree_jours': e.dureeJours,
        'rappel_fin': ymd(fin),
        ...colonnesPrises(e.prises),
      },
    });
    jour = fin.add(const Duration(days: 1));
  }
  for (final l in lignes) {
    if ((l['notes'] as String).isEmpty) l['notes'] = null;
  }
  return lignes;
}

/// Éditeur des étapes : durée, rythme et prises de chacune, total des jours
/// et date de fin calculée.
class EtapesTraitementEditor extends StatelessWidget {
  final List<EtapeTraitement> etapes;
  final DateTime? debut;
  final VoidCallback onChanged;
  final Color couleur;
  const EtapesTraitementEditor({super.key, required this.etapes, required this.debut, required this.onChanged,
      this.couleur = const Color(0xFF6E9E57)});

  Widget _nombre(String avant, int valeur, String apres, ValueChanged<int> maj) => Row(children: [
        Text(avant, style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
        const SizedBox(width: 8),
        SizedBox(
          width: 56,
          child: TextFormField(
            initialValue: '$valeur',
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder()),
            onChanged: (v) { final n = int.tryParse(v); if (n != null && n > 0) maj(n); },
          ),
        ),
        const SizedBox(width: 8),
        Text(apres, style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
      ]);

  @override
  Widget build(BuildContext context) {
    final fin = finTraitement(debut, etapes);
    String jj(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < etapes.length; i++)
        Container(
          key: ObjectKey(etapes[i]),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFF8F8F6), borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4E7E2))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(etapes.length > 1 ? 'Étape ${i + 1}' : 'Posologie',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13))),
              if (etapes.length > 1)
                IconButton(
                  icon: const Icon(Icons.close, size: 18), tooltip: 'Retirer cette étape',
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                  onPressed: () { etapes.removeAt(i); onChanged(); },
                ),
            ]),
            const SizedBox(height: 8),
            _nombre('Pendant', etapes[i].dureeJours, 'jour(s)', (n) { etapes[i].dureeJours = n; onChanged(); }),
            const SizedBox(height: 8),
            _nombre('Tous les', etapes[i].frequenceJours, 'jour(s)', (n) { etapes[i].frequenceJours = n; onChanged(); }),
            const SizedBox(height: 10),
            PrisesTraitementEditor(prises: etapes[i].prises, couleur: couleur,
                onChanged: (l) { etapes[i].prises = l; onChanged(); }),
          ]),
        ),
      OutlinedButton.icon(
        icon: const Icon(Icons.add, size: 16),
        label: const Text('Ajouter une étape (la posologie change ensuite)', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
        onPressed: () {
          final d = etapes.isNotEmpty ? etapes.last : null;
          etapes.add(EtapeTraitement(dureeJours: 3, frequenceJours: d?.frequenceJours ?? 1,
              prises: [for (final p in d?.prises ?? const <PriseTraitement>[]) PriseTraitement(p.heure, p.quantite)]));
          onChanged();
        },
      ),
      const SizedBox(height: 6),
      Text(
        'Total : ${totalJours(etapes)} jour${totalJours(etapes) > 1 ? 's' : ''}'
        '${fin != null ? ' · fin le ${jj(fin)}' : ' · choisissez la date de début'}',
        style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
      ),
    ]);
  }
}
