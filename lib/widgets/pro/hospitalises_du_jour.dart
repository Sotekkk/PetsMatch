// Hospitalisés du jour (vétérinaire) : interventions du jour et animaux encore
// présents à la clinique — état (attendu, déposé, au bloc, en réveil, prêt à
// partir, rentré), récupération prévue, actions rapides (déposé, prévenir
// réveillé / prêt, récupéré). Vétérinaire ou ASV. Masqué s'il n'y a rien.
// Miroir site : components/rdv/HospitalisesDuJour.tsx.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:PetsMatch/utils/intervention.dart';

const _teal = Color(0xFF0C5C6C);
const _ink = Color(0xFF1E2025);

/// État : rentré > prêt à partir > en réveil > au bloc > déposé > attendu.
String etatHospit(Map<String, dynamic> h, [DateTime? maintenant]) {
  DateTime? d(String k) => DateTime.tryParse(h[k]?.toString() ?? '');
  if (h['sortie_le'] != null) return 'rentre';
  if (h['pret_le'] != null) return 'pret';
  if (h['reveil_le'] != null) return 'reveil';
  if (h['admis_le'] != null) {
    final now = maintenant ?? DateTime.now();
    final bd = d('bloc_debut'), bf = d('bloc_fin');
    if (bd != null && !now.isBefore(bd) && (bf == null || !now.isAfter(bf))) return 'bloc';
    return 'depose';
  }
  return 'attendu';
}

const kEtatsHospit = <String, (String, Color, Color)>{
  'attendu': ('Attendu', Color(0xFF6B7280), Color(0xFFF1F4F3)),
  'depose': ('Déposé', Color(0xFF0C5C6C), Color(0xFFE6F2F3)),
  'bloc': ('Au bloc', Color(0xFF8A5A00), Color(0xFFFFF4DC)),
  'reveil': ('En réveil', Color(0xFF6D28D9), Color(0xFFF1EAFE)),
  'pret': ('Prêt à partir', Color(0xFF2E7D32), Color(0xFFE8F5E9)),
  'rentre': ('Rentré', Color(0xFF6B7280), Color(0xFFF1F4F3)),
};

class HospitalisesDuJour extends StatefulWidget {
  final String profileId;
  /// Ouvre le RDV (agenda) — optionnel.
  final void Function(String rdvId)? onOuvrir;
  const HospitalisesDuJour({super.key, required this.profileId, this.onOuvrir});
  @override
  State<HospitalisesDuJour> createState() => _HospitalisesDuJourState();
}

class _HospitalisesDuJourState extends State<HospitalisesDuJour> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _liste = [];
  String _enCours = '';
  Timer? _tick;

  static const _cols = 'id, date_heure, motif, statut, intervention_type, animal_id, animal_nom_manuel, client_uid, '
      'client_profile_id, client_nom_manuel, client_telephone_manuel, heure_recuperation, bloc_debut, bloc_fin, '
      'admis_le, reveil_le, pret_le, sortie_le';

  @override
  void initState() {
    super.initState();
    _charger();
    // L'état « au bloc » dépend de l'heure.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) { if (mounted) setState(() {}); });
  }

  @override
  void dispose() { _tick?.cancel(); super.dispose(); }

  Future<void> _charger() async {
    try {
      final n = DateTime.now();
      final debut = DateTime(n.year, n.month, n.day), fin = debut.add(const Duration(days: 1));
      final jour = await _supa.from('rdv').select(_cols).eq('pro_profile_id', widget.profileId)
          .not('intervention_type', 'is', null).gte('date_heure', debut.toUtc().toIso8601String())
          .lt('date_heure', fin.toUtc().toIso8601String()).not('statut', 'in', '(annule,refuse)');
      final restants = await _supa.from('rdv').select(_cols).eq('pro_profile_id', widget.profileId)
          .not('intervention_type', 'is', null).not('admis_le', 'is', null).isFilter('sortie_le', null)
          .lt('date_heure', debut.toUtc().toIso8601String());
      final lignes = [...List<Map<String, dynamic>>.from(restants as List), ...List<Map<String, dynamic>>.from(jour as List)];
      final ids = {for (final l in lignes) if (l['animal_id'] != null) l['animal_id'].toString()}.toList();
      final pids = {for (final l in lignes) if (l['client_profile_id'] != null) l['client_profile_id'].toString()}.toList();
      final animaux = <String, String>{}, clients = <String, String>{};
      if (ids.isNotEmpty) {
        for (final a in await _supa.from('animaux').select('id, nom').inFilter('id', ids) as List) {
          animaux[a['id'].toString()] = a['nom']?.toString() ?? '';
        }
      }
      if (pids.isNotEmpty) {
        for (final c in await _supa.from('user_profiles_complet').select('id, firstname, lastname, nom').inFilter('id', pids) as List) {
          final n2 = '${c['firstname'] ?? ''} ${c['lastname'] ?? ''}'.trim();
          clients[c['id'].toString()] = n2.isNotEmpty ? n2 : (c['nom']?.toString() ?? '');
        }
      }
      for (final l in lignes) {
        final an = animaux[l['animal_id']?.toString()] ?? '';
        l['_animal'] = an.isNotEmpty ? an : (l['animal_nom_manuel']?.toString() ?? 'Animal');
        final cl = clients[l['client_profile_id']?.toString()] ?? '';
        l['_client'] = cl.isNotEmpty ? cl : (l['client_nom_manuel']?.toString() ?? 'Client');
      }
      const ordre = ['bloc', 'reveil', 'depose', 'pret', 'attendu', 'rentre'];
      lignes.sort((a, b) {
        final c = ordre.indexOf(etatHospit(a)).compareTo(ordre.indexOf(etatHospit(b)));
        return c != 0 ? c : (a['date_heure']?.toString() ?? '').compareTo(b['date_heure']?.toString() ?? '');
      });
      if (mounted) setState(() => _liste = lignes);
    } catch (_) {}
  }

  String _hm(dynamic iso) {
    final d = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
    return d == null ? '' : '${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _agir(String cle, Future<String?> Function() f) async {
    setState(() => _enCours = cle);
    try {
      final m = await f();
      if (m != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m, style: const TextStyle(fontFamily: 'Galey'))));
      }
      await _charger();
    } finally {
      if (mounted) setState(() => _enCours = '');
    }
  }

  Future<String?> _maj(String id, Map<String, dynamic> champs) async {
    try {
      await _supa.from('rdv').update(champs).eq('id', id);
      return null;
    } catch (e) {
      return 'Non enregistré : $e';
    }
  }

  Widget _btn(String cle, String label, Future<String?> Function() f, {bool plein = false}) => Padding(
        padding: const EdgeInsets.only(right: 6, top: 6),
        child: plein
            ? ElevatedButton(
                onPressed: _enCours.isNotEmpty ? null : () => _agir(cle, f),
                style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white, visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10)),
                child: Text(_enCours == cle ? '…' : label, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700)))
            : OutlinedButton(
                onPressed: _enCours.isNotEmpty ? null : () => _agir(cle, f),
                style: OutlinedButton.styleFrom(foregroundColor: _teal, side: const BorderSide(color: _teal), visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10)),
                child: Text(_enCours == cle ? '…' : label, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600))),
      );

  @override
  Widget build(BuildContext context) {
    if (_liste.isEmpty) return const SizedBox.shrink();
    final presents = _liste.where((h) => !const {'attendu', 'rentre'}.contains(etatHospit(h))).length;
    final aujourdhui = DateTime.now();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE5E8E6))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Expanded(child: Text('Hospitalisés du jour', style: TextStyle(fontFamily: 'Galey', fontSize: 16, fontWeight: FontWeight.w700, color: _ink))),
          Text('$presents présent${presents > 1 ? 's' : ''} · ${_liste.length} intervention${_liste.length > 1 ? 's' : ''}',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
        ]),
        for (final h in _liste) ...[
          const Divider(height: 18),
          Builder(builder: (_) {
            final id = h['id'].toString();
            final e = etatHospit(h);
            final (label, fg, bg) = kEtatsHospit[e]!;
            final depot = DateTime.tryParse(h['date_heure']?.toString() ?? '')?.toLocal();
            final avant = depot != null && (depot.year != aujourdhui.year || depot.month != aujourdhui.month || depot.day != aujourdhui.day);
            final tel = (h['client_telephone_manuel']?.toString() ?? '').trim();
            return InkWell(
              onTap: widget.onOuvrir == null ? null : () => widget.onOuvrir!(id),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${h['_animal']} · ${h['motif'] ?? libelleIntervention(h['intervention_type']?.toString())}',
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
                    Text([
                      h['_client'],
                      avant ? 'depuis le ${depot.day}/${depot.month}' : 'dépôt ${_hm(h['date_heure'])}',
                      if (h['bloc_debut'] != null) 'bloc ${_hm(h['bloc_debut'])}',
                      if (h['heure_recuperation'] != null) 'récup. ${_hm(h['heure_recuperation'])}',
                    ].join(' · '), style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                  ])),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
                    child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
                  ),
                ]),
                Wrap(children: [
                  if (e == 'attendu') _btn('$id:admis', 'Animal déposé', () => _maj(id, {'admis_le': DateTime.now().toUtc().toIso8601String()}), plein: true),
                  if (e == 'depose' || e == 'bloc') _btn('$id:reveille', 'Réveillé — prévenir', () => messageIntervention(id, 'reveille')),
                  if (e == 'depose' || e == 'bloc' || e == 'reveil') _btn('$id:pret', 'Prêt — prévenir', () => messageIntervention(id, 'pret'), plein: e == 'reveil'),
                  if (e == 'pret' || e == 'reveil') _btn('$id:sortie', 'Récupéré', () => _maj(id, {'sortie_le': DateTime.now().toUtc().toIso8601String()}), plein: e == 'pret'),
                  if (tel.isNotEmpty && h['client_uid'] == null)
                    _btn('$id:tel', 'Appeler', () async { await launchUrl(Uri.parse('tel:$tel')); return null; }),
                ]),
              ]),
            );
          }),
        ],
      ]),
    );
  }
}
