// Chiffre d'affaires du mois et de l'année, en tête de « Mes Factures »
// (tous les pros qui ont la facturation). Calculé depuis les factures déjà
// chargées (profil actif). Miroir site : components/ChiffreAffaires.tsx +
// lib/chiffre-affaires.ts.
//   Facturé : factures non annulées, par date de facture (avoirs déduits).
//   Encaissé : factures payées, par date de paiement (sinon de facture).
//   À encaisser : factures émises non payées (hors avoirs).
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const _teal = Color(0xFF0C5C6C);
const _vert = Color(0xFF6E9E57);
const _dark = Color(0xFF1F2A2E);
const kMoisCourts = ['Janv.', 'Févr.', 'Mars', 'Avr.', 'Mai', 'Juin', 'Juil.', 'Août', 'Sept.', 'Oct.', 'Nov.', 'Déc.'];

class MoisCA {
  double ht = 0, ttc = 0, encaisse = 0;
  int nb = 0;
}

class ResumeCA {
  final List<MoisCA> mois;
  final double aEncaisser, ttcAnneePrec;
  ResumeCA(this.mois, this.aEncaisser, this.ttcAnneePrec);
  double get ht => mois.fold(0, (t, x) => t + x.ht);
  double get ttc => mois.fold(0, (t, x) => t + x.ttc);
  double get encaisse => mois.fold(0, (t, x) => t + x.encaisse);
}

double _n(Object? v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
int? _an(Object? d) => (d?.toString().length ?? 0) >= 4 ? int.tryParse(d.toString().substring(0, 4)) : null;
int _mois(Object? d) => (d?.toString().length ?? 0) >= 7 ? (int.tryParse(d.toString().substring(5, 7)) ?? 0) - 1 : -1;

ResumeCA resumeCA(List<Map<String, dynamic>> factures, int an) {
  final m = List.generate(12, (_) => MoisCA());
  var aEncaisser = 0.0, prec = 0.0;
  for (final f in factures) {
    final statut = f['statut']?.toString() ?? 'emise';
    if (statut == 'annulee' || statut == 'brouillon') continue;
    final avoir = f['type_facture'] == 'avoir';
    final s = avoir && _n(f['total_ttc']) > 0 ? -1 : 1;
    final ttc = s * _n(f['total_ttc']);
    final ht = s * (f['total_ht'] != null ? _n(f['total_ht']) : _n(f['total_ttc']));
    final df = f['date_facture'];
    if (_an(df) == an && _mois(df) >= 0) {
      final x = m[_mois(df)];
      x.ht += ht; x.ttc += ttc; x.nb++;
    }
    if (_an(df) == an - 1) prec += ttc;
    if (statut == 'payee') {
      final d = f['date_paiement'] ?? df;
      if (_an(d) == an && _mois(d) >= 0) m[_mois(d)].encaisse += s * (f['montant_regle'] != null ? _n(f['montant_regle']) : _n(f['total_ttc']));
    } else if (!avoir) {
      aEncaisser += _n(f['total_ttc']);
    }
  }
  return ResumeCA(m, aEncaisser, prec);
}

class ChiffreAffairesCard extends StatefulWidget {
  final List<Map<String, dynamic>> factures;
  const ChiffreAffairesCard({super.key, required this.factures});
  @override
  State<ChiffreAffairesCard> createState() => _ChiffreAffairesCardState();
}

class _ChiffreAffairesCardState extends State<ChiffreAffairesCard> {
  final _maintenant = DateTime.now();
  late int _an = _maintenant.year;
  bool _detail = false;
  final _eur = NumberFormat.currency(locale: 'fr_FR', symbol: '€', decimalDigits: 0);

  Widget _tuile(String titre, String valeur, String? sous) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(color: const Color(0xFFF7FAF8), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titre.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Galey', fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
          Text(valeur, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 17, fontWeight: FontWeight.w800, color: _dark)),
          if (sous != null)
            Text(sous, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade600)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final r = resumeCA(widget.factures, _an);
    final courant = _an == _maintenant.year;
    final mc = courant ? r.mois[_maintenant.month - 1] : null;
    final evo = r.ttcAnneePrec > 0 ? ((r.ttc - r.ttcAnneePrec) / r.ttcAnneePrec * 100).round() : null;
    final max = [1.0, for (final x in r.mois) ...[x.ttc, x.encaisse]].reduce((a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text("Chiffre d'affaires",
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 16, color: _teal))),
          IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.chevron_left), tooltip: 'Année précédente',
              onPressed: () => setState(() => _an--)),
          Text('$_an', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, color: _dark)),
          IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.chevron_right), tooltip: 'Année suivante',
              onPressed: courant ? null : () => setState(() => _an++)),
        ]),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 2.1,
          children: [
            _tuile(mc != null ? '${kMoisCourts[_maintenant.month - 1]} (mois)' : 'Mois en cours',
                mc != null ? _eur.format(mc.ttc) : '—',
                mc != null ? '${_eur.format(mc.ht)} HT · ${mc.nb} facture${mc.nb > 1 ? 's' : ''}' : null),
            _tuile('Année $_an', _eur.format(r.ttc),
                '${_eur.format(r.ht)} HT${evo != null ? ' · ${evo >= 0 ? '+' : ''}$evo % vs ${_an - 1}' : ''}'),
            _tuile('Encaissé', _eur.format(r.encaisse), 'en $_an'),
            _tuile('À encaisser', _eur.format(r.aEncaisser), 'émises non payées'),
          ],
        ),
        TextButton(
          onPressed: () => setState(() => _detail = !_detail),
          style: TextButton.styleFrom(foregroundColor: _teal, padding: EdgeInsets.zero, minimumSize: const Size(0, 34)),
          child: Text(_detail ? 'Masquer le détail par mois' : 'Voir le détail par mois',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        ),
        if (_detail) ...[
          Row(children: [
            Container(width: 12, height: 8, decoration: BoxDecoration(color: _teal, borderRadius: BorderRadius.circular(2))),
            const Text(' Facturé TTC   ', style: TextStyle(fontFamily: 'Galey', fontSize: 11)),
            Container(width: 12, height: 8, decoration: BoxDecoration(color: _vert, borderRadius: BorderRadius.circular(2))),
            const Text(' Encaissé', style: TextStyle(fontFamily: 'Galey', fontSize: 11)),
          ]),
          const SizedBox(height: 6),
          for (var i = 0; i < 12; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(width: 44, child: Text(kMoisCourts[i], style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade700))),
                Expanded(child: LayoutBuilder(builder: (_, c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(height: 7, width: (r.mois[i].ttc / max).clamp(0, 1) * c.maxWidth,
                      decoration: BoxDecoration(color: _teal, borderRadius: BorderRadius.circular(4))),
                  const SizedBox(height: 2),
                  Container(height: 7, width: (r.mois[i].encaisse / max).clamp(0, 1) * c.maxWidth,
                      decoration: BoxDecoration(color: _vert, borderRadius: BorderRadius.circular(4))),
                ]))),
                SizedBox(width: 92, child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(_eur.format(r.mois[i].ttc), style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w700)),
                  Text('${_eur.format(r.mois[i].encaisse)} encaissé',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 10.5, color: Colors.grey.shade600)),
                ])),
              ]),
            ),
        ],
      ]),
    );
  }
}
