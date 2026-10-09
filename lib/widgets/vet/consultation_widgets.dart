// Onglet « Consultations » de la fiche animal (vue vétérinaire) : une carte
// compacte par consultation (date, motif, intervenant, poids, actes, statut
// du compte rendu, nombre d'ordonnances) ; le détail (CR complet,
// ordonnances, traçabilité) s'ouvre à la demande. Le carnet de santé reste
// dans l'onglet Santé — rien n'est dupliqué ici.
// Miroir site : website/src/components/pro/ConsultationsVet.tsx.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/utils/document_prive.dart';

const _teal = Color(0xFF0C5C6C);
const _ink = Color(0xFF1E2025);
const _muted = Color(0xFF6B7280);
const _border = Color(0xFFE4E7E2);
const _amber = Color(0xFF8A5A00);

/// Une consultation = un compte rendu (lié au RDV) + ses ordonnances.
/// Une ordonnance sans compte rendu forme sa propre consultation.
class ConsultationVet {
  final String cle;
  final DateTime date;
  final Map<String, dynamic>? cr;
  final List<Map<String, dynamic>> ordos;
  ConsultationVet({required this.cle, required this.date, this.cr, required this.ordos});

  String get motif {
    final m = (cr?['motif'] ?? '').toString().trim();
    if (m.isNotEmpty) return m;
    return cr != null ? 'Consultation' : 'Ordonnance';
  }

  List<String> get actes => [for (final a in (cr?['actes'] as List?) ?? const []) a.toString()];
  num? get poids => cr?['poids'] as num?;
  bool get brouillon => cr?['statut'] == 'brouillon';
}

DateTime _date(dynamic iso) => DateTime.tryParse(iso?.toString() ?? '')?.toLocal() ?? DateTime(2000);
String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String fmtJour(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
String fmtJourHeure(DateTime d) =>
    '${fmtJour(d)} à ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

List<ConsultationVet> regrouperConsultations(List<Map<String, dynamic>> crs, List<Map<String, dynamic>> ordos) {
  final restantes = [...ordos];
  final out = <ConsultationVet>[];
  for (final cr in crs) {
    final rdv = cr['rdv_id']?.toString();
    final jour = _ymd(_date(cr['created_at']));
    final liees = restantes.where((o) {
      final ordoRdv = o['rdv_id']?.toString();
      if (rdv != null && ordoRdv != null) return ordoRdv == rdv;
      // Sans RDV : même jour d'émission.
      return ordoRdv == null && rdv == null && (o['date_emit']?.toString() ?? '').startsWith(jour);
    }).toList();
    restantes.removeWhere(liees.contains);
    out.add(ConsultationVet(cle: 'cr:${cr['id']}', date: _date(cr['created_at']), cr: cr, ordos: liees));
  }
  final parGroupe = <String, List<Map<String, dynamic>>>{};
  for (final o in restantes) {
    final k = o['rdv_id']?.toString() ?? 'jour:${o['date_emit'] ?? o['created_at']}';
    parGroupe.putIfAbsent(k, () => []).add(o);
  }
  parGroupe.forEach((k, liste) {
    final d = _date(liste.first['created_at'] ?? liste.first['date_emit']);
    out.add(ConsultationVet(cle: 'ordo:$k', date: d, ordos: liste));
  });
  out.sort((a, b) => b.date.compareTo(a.date));
  return out;
}

/// Noms des intervenants : profils (user_profiles) puis comptes (users).
Future<Map<String, String>> chargerNomsIntervenants({Iterable<String> profils = const [], Iterable<String> uids = const []}) async {
  final supa = Supabase.instance.client;
  final out = <String, String>{};
  String nom(Map p) {
    final n = '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
    return n.isNotEmpty ? n : (p['nom']?.toString() ?? '');
  }
  final ps = profils.where((x) => x.isNotEmpty).toSet().toList();
  final us = uids.where((x) => x.isNotEmpty).toSet().toList();
  try {
    if (ps.isNotEmpty) {
      final rows = await supa.from('user_profiles_complet').select('id, firstname, lastname, nom').inFilter('id', ps);
      for (final p in rows as List) { out[p['id'].toString()] = nom(p as Map); }
    }
  } catch (_) {}
  try {
    if (us.isNotEmpty) {
      final rows = await supa.from('users_complet').select('uid, firstname, lastname').inFilter('uid', us);
      for (final u in rows as List) { out[u['uid'].toString()] = nom(u as Map); }
    }
  } catch (_) {}
  out.removeWhere((_, v) => v.isEmpty);
  return out;
}

/// Profils / uids cités par des CR et ordonnances (pour [chargerNomsIntervenants]).
({Set<String> profils, Set<String> uids}) intervenantsCites(List<Map<String, dynamic>> crs, List<Map<String, dynamic>> ordos) {
  final p = <String>{}, u = <String>{};
  void ajoute(Set<String> s, dynamic v) { final t = v?.toString() ?? ''; if (t.isNotEmpty) s.add(t); }
  for (final c in crs) {
    ajoute(p, c['redige_par_profile_id']); ajoute(p, c['valide_par_profile_id']);
    ajoute(u, c['redige_par_uid']); ajoute(u, c['valide_par_uid']);
  }
  for (final o in ordos) { ajoute(p, o['praticien_profile_id']); ajoute(u, o['praticien_uid']); }
  return (profils: p, uids: u);
}

String? _nomDe(Map<String, String> noms, dynamic profil, dynamic uid) =>
    noms[profil?.toString() ?? ''] ?? noms[uid?.toString() ?? ''];

/// Intervenant affiché : validateur, sinon rédacteur, sinon prescripteur.
String? intervenant(ConsultationVet c, Map<String, String> noms) {
  final cr = c.cr;
  if (cr != null) {
    return _nomDe(noms, cr['valide_par_profile_id'], cr['valide_par_uid'])
        ?? _nomDe(noms, cr['redige_par_profile_id'], cr['redige_par_uid']);
  }
  for (final o in c.ordos) {
    final n = _nomDe(noms, o['praticien_profile_id'], o['praticien_uid']);
    if (n != null) return n;
  }
  return null;
}

String _poids(num p) => '${p % 1 == 0 ? p.toInt() : p} kg';

class ConsultationCard extends StatelessWidget {
  final ConsultationVet c;
  final Map<String, String> noms;
  final VoidCallback onOuvrir;
  const ConsultationCard({super.key, required this.c, required this.noms, required this.onOuvrir});

  @override
  Widget build(BuildContext context) {
    final qui = intervenant(c, noms);
    final actes = c.actes;
    final details = [
      if (qui != null) qui,
      if (c.poids != null) _poids(c.poids!),
    ].join(' · ');
    final actesTxt = actes.isEmpty ? '' : actes.length <= 3
        ? actes.join(', ') : '${actes.take(3).join(', ')} +${actes.length - 3}';
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOuvrir,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 78,
                child: Text(fmtJour(c.date), style: const TextStyle(fontFamily: 'Galey', fontSize: 13,
                    fontWeight: FontWeight.w700, color: _teal)),
              ),
              Expanded(child: Text(c.motif, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700, color: _ink))),
              const Icon(Icons.chevron_right, size: 20, color: _muted),
            ]),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 4),
              Padding(padding: const EdgeInsets.only(left: 78),
                  child: Text(details, style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: _muted))),
            ],
            if (actesTxt.isNotEmpty) ...[
              const SizedBox(height: 2),
              Padding(padding: const EdgeInsets.only(left: 78),
                  child: Text(actesTxt, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: _ink))),
            ],
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 78),
              child: Row(children: [
                Icon(c.cr == null ? Icons.remove_circle_outline
                    : c.brouillon ? Icons.pending_outlined : Icons.check_circle_outline,
                    size: 14, color: c.brouillon ? _amber : _muted),
                const SizedBox(width: 4),
                Text(c.cr == null ? 'Sans compte rendu' : c.brouillon ? 'CR à valider' : 'CR validé',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                        color: c.brouillon ? _amber : _muted, fontWeight: FontWeight.w600)),
                const SizedBox(width: 14),
                if (c.ordos.isNotEmpty) ...[
                  const Icon(Icons.description_outlined, size: 14, color: _muted),
                  const SizedBox(width: 4),
                  Text('Ordonnances (${c.ordos.length})', style: const TextStyle(fontFamily: 'Galey',
                      fontSize: 12, color: _muted, fontWeight: FontWeight.w600)),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Détail d'une consultation : CR complet, ordonnances, traçabilité.
Future<void> showConsultationDetail(BuildContext context, {
  required ConsultationVet c,
  required Map<String, String> noms,
  VoidCallback? onGererCr,
}) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.75, maxChildSize: 0.95, minChildSize: 0.4,
        builder: (ctx, sc) => _ConsultationDetail(c: c, noms: noms, controller: sc, onGererCr: onGererCr),
      ),
    );

class _ConsultationDetail extends StatefulWidget {
  final ConsultationVet c;
  final Map<String, String> noms;
  final ScrollController controller;
  final VoidCallback? onGererCr;
  const _ConsultationDetail({required this.c, required this.noms, required this.controller, this.onGererCr});

  @override
  State<_ConsultationDetail> createState() => _ConsultationDetailState();
}

class _ConsultationDetailState extends State<_ConsultationDetail> {
  List<Map<String, dynamic>> _journal = [];
  Map<String, String> _noms = {};

  @override
  void initState() {
    super.initState();
    _noms = {...widget.noms};
    _chargerJournal();
  }

  /// Journal serveur (migration_journal_medical.sql) : vide tant que la
  /// migration n'est pas passée — la traçabilité des colonnes du CR reste.
  Future<void> _chargerJournal() async {
    final c = widget.c;
    final ids = [if (c.cr != null) c.cr!['id'].toString(), for (final o in c.ordos) o['id'].toString()];
    if (ids.isEmpty) return;
    try {
      final rows = await Supabase.instance.client.from('journal_medical')
          .select('table_source, ligne_id, action, auteur_uid, auteur_profile_id, cree_le')
          .inFilter('table_source', ['comptes_rendus', 'ordonnances']).inFilter('ligne_id', ids)
          .order('cree_le');
      final liste = List<Map<String, dynamic>>.from(rows as List);
      final manquants = await chargerNomsIntervenants(
        profils: liste.map((j) => j['auteur_profile_id']?.toString() ?? '').where((x) => !_noms.containsKey(x)),
        uids: liste.map((j) => j['auteur_uid']?.toString() ?? '').where((x) => !_noms.containsKey(x)),
      );
      if (mounted) setState(() { _journal = liste; _noms.addAll(manquants); });
    } catch (_) {}
  }

  Widget _titre(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(t.toUpperCase(), style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5,
            letterSpacing: 0.6, fontWeight: FontWeight.w700, color: _muted)),
      );

  Widget _ligne(String label, String valeur) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted))),
          Expanded(child: Text(valeur, style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, color: _ink))),
        ]),
      );

  static const _actions = {
    'creation': 'Création', 'modification': 'Modification', 'validation': 'Validation', 'suppression': 'Suppression',
  };

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final cr = c.cr;
    final qui = intervenant(c, _noms);
    final redacteur = cr == null ? null : _nomDe(_noms, cr['redige_par_profile_id'], cr['redige_par_uid']);
    final validateur = cr == null ? null : _nomDe(_noms, cr['valide_par_profile_id'], cr['valide_par_uid']);
    final valideLe = cr?['valide_le'] != null ? _date(cr!['valide_le']) : null;
    final contenu = (cr?['contenu'] ?? '').toString().trim();
    final prescription = (cr?['prescription'] ?? '').toString().trim();
    final docCr = (cr?['doc_url'] ?? '').toString();

    return ListView(controller: widget.controller, padding: const EdgeInsets.fromLTRB(20, 10, 20, 28), children: [
      Center(child: Container(width: 40, height: 4,
          decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
      const SizedBox(height: 14),
      Text(fmtJour(c.date), style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700, color: _teal)),
      const SizedBox(height: 2),
      Text(c.motif, style: const TextStyle(fontFamily: 'Galey', fontSize: 19, fontWeight: FontWeight.w700, color: _ink)),
      const SizedBox(height: 12),
      if (qui != null) _ligne('Intervenant', qui),
      if (c.poids != null) _ligne('Poids', _poids(c.poids!)),
      if (c.actes.isNotEmpty) _ligne('Actes réalisés', c.actes.join(', ')),
      if (cr != null) _ligne('Compte rendu', c.brouillon ? 'Brouillon — à valider' : 'Validé'),

      if (cr != null) ...[
        _titre('Compte rendu'),
        if (contenu.isNotEmpty)
          Text(contenu, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, height: 1.45, color: _ink))
        else
          const Text('Aucun texte saisi.', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: _muted)),
        if (prescription.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('Prescription', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w700, color: _muted)),
          const SizedBox(height: 2),
          Text(prescription, style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, height: 1.4, color: _ink)),
        ],
        if (docCr.isNotEmpty) Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => ouvrirDocument(context, docCr),
            icon: const Icon(Icons.attach_file, size: 16, color: _teal),
            label: const Text('Document joint', style: TextStyle(fontFamily: 'Galey', color: _teal, fontWeight: FontWeight.w600)),
          ),
        ),
      ],

      if (c.ordos.isNotEmpty) ...[
        _titre('Ordonnances (${c.ordos.length})'),
        for (final o in c.ordos)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: _border)),
            child: Row(children: [
              const Icon(Icons.description_outlined, size: 18, color: _teal),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Émise le ${fmtJour(_date(o['date_emit'] ?? o['created_at']))}',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, fontWeight: FontWeight.w600, color: _ink)),
                if ([_nomDe(_noms, o['praticien_profile_id'], o['praticien_uid']), o['notes']]
                    .any((x) => (x?.toString() ?? '').isNotEmpty))
                  Text([_nomDe(_noms, o['praticien_profile_id'], o['praticien_uid']), o['notes']]
                      .where((x) => (x?.toString() ?? '').isNotEmpty).join(' · '),
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _muted)),
              ])),
              if ((o['doc_url'] ?? '').toString().isNotEmpty)
                TextButton(
                  onPressed: () => ouvrirDocument(context, o['doc_url'].toString()),
                  child: const Text('Ouvrir', style: TextStyle(fontFamily: 'Galey', color: _teal, fontWeight: FontWeight.w700)),
                ),
            ]),
          ),
      ],

      _titre('Traçabilité'),
      if (cr != null) ...[
        _ligne('Rédigé', [if (redacteur != null) 'par $redacteur', 'le ${fmtJourHeure(_date(cr['created_at']))}'].join(' ')),
        if (!c.brouillon)
          _ligne('Validé', [if (validateur != null) 'par $validateur', if (valideLe != null) 'le ${fmtJourHeure(valideLe)}']
              .join(' ').ifEmpty('Oui')),
      ],
      for (final o in c.ordos)
        _ligne('Ordonnance', [
          if (_nomDe(_noms, o['praticien_profile_id'], o['praticien_uid']) != null)
            'prescrite par ${_nomDe(_noms, o['praticien_profile_id'], o['praticien_uid'])}',
          if (o['created_at'] != null) 'le ${fmtJourHeure(_date(o['created_at']))}',
        ].join(' ').ifEmpty('—')),
      if (_journal.isNotEmpty) ...[
        const SizedBox(height: 6),
        const Text('Journal des modifications', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5,
            fontWeight: FontWeight.w700, color: _muted)),
        const SizedBox(height: 4),
        for (final j in _journal)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              '${fmtJourHeure(_date(j['cree_le']))} · ${_actions[j['action']] ?? j['action']}'
              '${j['table_source'] == 'ordonnances' ? ' (ordonnance)' : ''}'
              '${_nomDe(_noms, j['auteur_profile_id'], j['auteur_uid']) != null ? ' · ${_nomDe(_noms, j['auteur_profile_id'], j['auteur_uid'])}' : ''}',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: _ink),
            ),
          ),
      ],

      if (widget.onGererCr != null) ...[
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: () { Navigator.pop(context); widget.onGererCr!(); },
          icon: const Icon(Icons.edit_note, size: 18, color: _teal),
          label: Text(cr != null && c.brouillon ? 'Valider, modifier, exporter' : 'Exporter, transmettre',
              style: const TextStyle(fontFamily: 'Galey', color: _teal, fontWeight: FontWeight.w700)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: _teal),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    ]);
  }
}

extension on String {
  String ifEmpty(String autre) => isEmpty ? autre : this;
}
