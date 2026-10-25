import 'package:flutter/material.dart';

import '../../utils/plan_alimentation.dart';

const _teal = Color(0xFF0C5C6C);
const _texte = Color(0xFF1F2A2E);
const _gris = Color(0xFF5A6469);
const _bord = Color(0xFFDCE3E6);

TextStyle _st(double taille, {FontWeight w = FontWeight.w400, Color c = _texte}) =>
    TextStyle(fontFamily: 'Galey', fontSize: taille, fontWeight: w, color: c);

/// Synthèse d'un plan d'alimentation : type, repas, quantités, aliments
/// (marque + gamme), consignes. Lecture seule — utilisée telle quelle par la
/// pension, le pet-sitter, le vétérinaire et la page de partage, et en tête de
/// l'onglet du propriétaire. Miroir de PlanAlimentationLecture.tsx (site).
class PlanAlimentationLecture extends StatelessWidget {
  final PlanAlimentation plan;
  final CalculRation calcul;
  final String espece;
  final String consignes;
  /// Bandeau « lecture seule » pour un professionnel.
  final bool vuePro;
  final String nomAnimal;

  const PlanAlimentationLecture({
    super.key, required this.plan, required this.calcul, required this.espece,
    this.consignes = '', this.vuePro = false, this.nomAnimal = '',
  });

  /// Plan enregistré d'une ligne `alimentations`, sans recalcul (pros).
  static Widget depuisLigne(Map<String, dynamic>? row, String espece,
      {bool vuePro = true, String nomAnimal = '', String vide = 'Plan d’alimentation non renseigné par le propriétaire.'}) {
    final plan = planDepuisLigne(row, espece);
    if (plan == null) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(vide, style: _st(14, c: _gris)));
    }
    return PlanAlimentationLecture(plan: plan, calcul: calculEnregistre(plan), espece: espece,
        consignes: (row?['consignes'] ?? '').toString(), vuePro: vuePro, nomAnimal: nomAnimal);
  }

  @override
  Widget build(BuildContext context) {
    final profil = profilEspece(espece);
    final kg = profil.uniteKg;
    final labels = libellesRepas(plan.repas.length);
    final types = <String>[];
    for (final a in plan.aliments) {
      final t = kLibellesTypeAliment[a.type] ?? a.type;
      if (!types.contains(t)) types.add(t);
    }
    final typeTxt = '${plan.aliments.length > 1 ? 'Mixte : ' : ''}${types.join(' + ')}';
    String? energie;
    if (profil.methode == 'energie') {
      energie = calcul.kcalServies != null
          ? calcul.kcalEstimees.isEmpty
              ? '${calcul.kcalServies!.round()} kcal/jour'
              : '≈ ${calcul.kcalServies!.round()} kcal/jour (estimation pour ${calcul.kcalEstimees.join(', ')})'
          : calcul.sansKcal.isNotEmpty
              ? 'Non calculable (${calcul.sansKcal.join(', ')} sans valeur énergétique)'
              : null;
    }
    final aVolonte = [
      for (var i = 0; i < plan.aliments.length; i++) if (calcul.alimentLibre[i]) plan.aliments[i].nom,
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (vuePro)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFE8F0F2), borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFB9CDD3))),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: 'Lecture seule. ', style: _st(13.5, w: FontWeight.w700)),
            TextSpan(text: 'Consignes renseignées par le propriétaire${nomAnimal.isNotEmpty ? ' de $nomAnimal' : ''}.', style: _st(13.5)),
          ])),
        ),
      _carte([
        _ligne('Type', typeTxt),
        _ligne('Repas', '${plan.repas.length} repas par jour'),
        _ligne('Quantité totale', calcul.totalG > 0
            ? '${formatQuantite(calcul.totalG, kg: kg)}/jour${aVolonte.isNotEmpty ? ' + ${aVolonte.join(', ')} à volonté' : ''}'
            : aVolonte.isNotEmpty ? '${aVolonte.join(', ')} à volonté' : 'non renseignée'),
        if (energie != null) _ligne('Énergie servie', energie),
      ]),
      _titre('Aliments'),
      _carte([
        for (final a in plan.aliments)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: 'Marque : ', style: _st(14.5, c: _gris)),
                TextSpan(text: a.marque, style: _st(14.5, w: FontWeight.w700)),
              ])),
              if (a.gamme.trim().isNotEmpty)
                Text.rich(TextSpan(children: [
                  TextSpan(text: 'Gamme : ', style: _st(14.5, c: _gris)),
                  TextSpan(text: a.gamme, style: _st(14.5, w: FontWeight.w700)),
                ])),
              Text(kLibellesTypeAliment[a.type] ?? a.type, style: _st(13, c: _gris)),
              if (a.repartition != null)
                Text('Composition : ${a.repartition!.entries.map((e) => '${kLibellesRepartition[e.key] ?? e.key} ${e.value.round()} %').join(' · ')}',
                    style: _st(13, c: _gris)),
            ]),
          ),
      ]),
      _titre('Détail par repas'),
      for (var i = 0; i < plan.repas.length; i++)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _bord)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(labels[i], style: _st(15.5, w: FontWeight.w700))),
              if (plan.repas[i].heure != null) Text(plan.repas[i].heure!.replaceFirst(':', ' h '), style: _st(13.5, c: _gris)),
            ]),
            const SizedBox(height: 6),
            for (final x in calcul.lignes[i]) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Text(plan.aliments[x.a].nom, style: _st(14.5))),
                  const SizedBox(width: 10),
                  Text(x.libre ? 'à volonté' : x.eff != null ? formatQuantite(x.eff!, kg: kg) : 'non précisée',
                      style: _st(14.5, w: FontWeight.w700, c: _teal)),
                ]),
              ),
              if (plan.aliments[x.a].repartition != null && x.eff != null)
                Text(plan.aliments[x.a].repartition!.entries
                        .map((e) => '${kLibellesRepartition[e.key] ?? e.key} ${formatQuantite(x.eff! * e.value / 100)}')
                        .join(' · '),
                    style: _st(12.5, c: _gris)),
            ],
          ]),
        ),
      if (plan.aliments.length > 1) ...[
        _titre('Total par aliment'),
        _carte([
          for (var i = 0; i < plan.aliments.length; i++)
            _ligne(plan.aliments[i].nom, calcul.alimentLibre[i]
                ? 'à volonté'
                : '${formatQuantite(calcul.totalParAliment[i], kg: kg)}/jour'),
        ]),
      ],
      _titre('Consignes alimentaires'),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _bord)),
        child: Text(consignes.trim().isEmpty ? 'Aucune consigne particulière.' : consignes.trim(), style: _st(14.5)),
      ),
    ]);
  }

  static Widget _titre(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
        child: Text(t, style: _st(16, w: FontWeight.w800)),
      );

  static Widget _carte(List<Widget> lignes) => Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _bord)),
        child: Column(children: [
          for (var i = 0; i < lignes.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Color(0xFFEEF2F3)),
            lignes[i],
          ],
        ]),
      );

  static Widget _ligne(String l, String v) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(l, style: _st(14.5, c: _gris))),
          const SizedBox(width: 12),
          Flexible(child: Text(v, textAlign: TextAlign.right, style: _st(14.5, w: FontWeight.w700))),
        ]),
      );
}
