// « Documents de la consultation » (lot 5 des documents vétérinaires) : depuis
// la saisie du compte rendu, ouvrir l'ordonnance, les comptes rendus pré /
// opératoire et les consignes (pages par-dessus : la saisie du CR est
// conservée) ; liste des documents déjà faits, actualisée au retour ;
// imprimer / envoyer au propriétaire, y compris sans compte PetsMatch.
// Miroir site : website/src/components/pro/DocumentsConsultation.tsx.

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/pages/pro/transmission_document.dart';
import 'package:PetsMatch/utils/client_document.dart';
import 'package:PetsMatch/utils/contexte_pro.dart';
import 'package:PetsMatch/utils/document_prive.dart';
import 'package:PetsMatch/utils/ordonnance.dart' show libelleStatutOrdo;
import 'package:PetsMatch/widgets/pro/chirurgie_cr_page.dart';
import 'package:PetsMatch/widgets/pro/ordonnance_editeur_page.dart';

const _teal = Color(0xFF0C5C6C);
const _amber = Color(0xFF8A5A00);
const _libelles = {'preop': 'CR préopératoire', 'operatoire': 'CR opératoire', 'consignes': 'Consignes postopératoires'};

/// Document d'intervention validé : imprimer / partager / envoyer au
/// propriétaire (adresse de son compte, ou saisie pour un client sans compte).
Future<void> transmettreDocIntervention(BuildContext context, {required String animalId, required String doc,
    required String url, String? rdvId}) async {
  ClientDocument? cli;
  try { cli = await clientDocument(animalId, rdvId: rdvId); } catch (_) {}
  final a = await Supabase.instance.client.from('animaux').select('nom').eq('id', animalId).maybeSingle();
  final cl = AgendaContexte.profileId.isEmpty ? null : await Supabase.instance.client.from('user_profiles_complet')
      .select('nom').eq('id', AgendaContexte.profileId).maybeSingle();
  if (!context.mounted) return;
  final nomA = (a?['nom'] ?? 'animal').toString();
  final nomF = doc == 'consignes' ? 'Consignes' : doc == 'preop' ? 'Compte-rendu-preoperatoire' : 'Compte-rendu-operatoire';
  await transmettreDocument(context,
    pdf: () async => (await http.get(Uri.parse(await lienDocument(url)))).bodyBytes,
    nomFichier: '$nomF-$nomA.pdf',
    type: doc == 'consignes' ? 'consignes' : 'compte_rendu',
    animalNom: nomA, expediteur: (cl?['nom'] ?? '').toString(),
    emailParDefaut: cli?.email, destinataireNom: cli?.nom, animalId: animalId,
  );
}

class DocumentsConsultation extends StatefulWidget {
  final String animalId;
  final String? rdvId, ownerUid;
  const DocumentsConsultation({super.key, required this.animalId, this.rdvId, this.ownerUid});
  @override
  State<DocumentsConsultation> createState() => DocumentsConsultationState();
}

class DocumentsConsultationState extends State<DocumentsConsultation> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _ordos = [], _chirs = [];
  bool _peut = false, _ouvert = true;

  /// Ordonnances déjà faites pendant cette consultation (hors versions remplacées).
  bool get ordonnanceDejaFaite => _ordos.any((o) => o['statut'] != 'remplacee');

  @override
  void initState() {
    super.initState();
    peutPreparerOrdonnance().then((v) { if (mounted) setState(() => _peut = v); });
    charger();
  }

  Future<void> charger() async {
    final jour = DateTime.now();
    final j = '${jour.year}-${jour.month.toString().padLeft(2, '0')}-${jour.day.toString().padLeft(2, '0')}';
    try {
      var q = _supa.from('ordonnances').select().eq('animal_id', widget.animalId).neq('statut', 'remplacee');
      q = (widget.rdvId ?? '').isNotEmpty ? q.eq('rdv_id', widget.rdvId!) : q.eq('date_emit', j);
      final o = await q.order('created_at');
      final c = await _supa.from('chirurgies').select().eq('animal_id', widget.animalId).order('date', ascending: false);
      final limite = jour.subtract(const Duration(days: 30));
      final chirs = [
        for (final x in List<Map<String, dynamic>>.from(c as List))
          if ((DateTime.tryParse((x['date'] ?? '').toString()) ?? DateTime(2000)).isAfter(limite)
              || ['preop', 'operatoire', 'consignes'].any((d) => x[d] is Map && x[d]['statut'] != 'valide')) x,
      ].take(6).toList();
      if (mounted) setState(() { _ordos = List<Map<String, dynamic>>.from(o as List); _chirs = chirs; });
    } catch (_) {}
  }

  Future<void> _ordonnance([Map<String, dynamic>? o]) async {
    await ouvrirEditeurOrdonnance(context, ordo: o, animalId: widget.animalId, ownerUid: widget.ownerUid, rdvId: widget.rdvId);
    await charger();
  }

  Future<void> _docIntervention(String doc) async {
    final ctrl = TextEditingController();
    final choix = await showModalBottomSheet<Object>(
      context: context,
      builder: (ctx) => SafeArea(child: ListView(shrinkWrap: true, children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text('${_libelles[doc]} — pour quelle intervention ?',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15))),
        for (final c in _chirs)
          ListTile(title: Text((c['intitule'] ?? 'Intervention').toString(), style: const TextStyle(fontFamily: 'Galey')),
              subtitle: Text((c['date'] ?? '').toString(), style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
              onTap: () => Navigator.pop(ctx, c)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Row(children: [
            Expanded(child: TextField(controller: ctrl, decoration: const InputDecoration(
                hintText: 'Nouvelle intervention (ex. stérilisation)', isDense: true))),
            TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text('Créer', style: TextStyle(fontFamily: 'Galey', color: _teal, fontWeight: FontWeight.w700))),
          ]),
        ),
      ])),
    );
    if (choix == null || !mounted) return;
    Map<String, dynamic>? c;
    if (choix is Map<String, dynamic>) {
      c = choix;
    } else if (choix is String && choix.isNotEmpty) {
      final j = DateTime.now();
      try {
        c = Map<String, dynamic>.from(await _supa.from('chirurgies').insert({
          'id': '${DateTime.now().microsecondsSinceEpoch}', 'animal_id': widget.animalId, 'type': 'chirurgie', 'intitule': choix,
          'date': '${j.year}-${j.month.toString().padLeft(2, '0')}-${j.day.toString().padLeft(2, '0')}', 'statut': 'prevu',
          'source': 'veterinaire', 'vet_id': AgendaContexte.moi ?? AgendaContexte.uid, 'pro_uid': AgendaContexte.uid,
          if (AgendaContexte.profileId.isNotEmpty) 'pro_profile_id': AgendaContexte.profileId,
        }).select().single());
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Intervention non créée : $e')));
        return;
      }
    }
    if (c == null || !mounted) return;
    await ouvrirCrChirurgie(context, c, type: doc);
    await charger();
  }

  @override
  Widget build(BuildContext context) {
    const lien = TextStyle(fontFamily: 'Galey', color: _teal, fontWeight: FontWeight.w700, fontSize: 12.5);
    final docs = [
      for (final c in _chirs)
        for (final d in ['preop', 'operatoire', 'consignes'])
          if (c[d] is Map) (c: c, d: d, url: (c['${d}_doc_url'] ?? '').toString()),
    ];
    final nb = _ordos.length + docs.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: _teal.withValues(alpha: 0.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => setState(() => _ouvert = !_ouvert),
          child: Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 10), child: Row(children: [
            Expanded(child: Text('Documents de la consultation${nb > 0 ? ' ($nb)' : ''}',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13.5, color: _teal))),
            Icon(_ouvert ? Icons.expand_less : Icons.expand_more, color: _teal),
          ])),
        ),
        if (_ouvert) Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_peut) Wrap(spacing: 6, runSpacing: 6, children: [
              OutlinedButton(onPressed: () => _ordonnance(), child: const Text('Ordonnance', style: lien)),
              for (final d in ['preop', 'operatoire', 'consignes'])
                OutlinedButton(onPressed: () => _docIntervention(d), child: Text(_libelles[d]!, style: lien)),
            ]),
            const SizedBox(height: 6),
            if (nb == 0)
              Text('Aucun document pour cette consultation.', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
            for (final o in _ordos)
              Row(children: [
                Expanded(child: Text(
                  'Ordonnance${(o['numero'] ?? '').toString().isNotEmpty ? ' n° ${o['numero']}' : ''} · ${libelleStatutOrdo[(o['statut'] ?? 'signee').toString()] ?? ''}',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: o['statut'] == 'brouillon' ? _amber : null))),
                if (o['statut'] == 'brouillon' && _peut) TextButton(onPressed: () => _ordonnance(o), child: const Text('Compléter', style: lien)),
                if ((o['doc_url'] ?? '').toString().isNotEmpty)
                  TextButton(onPressed: () => ouvrirDocument(context, o['doc_url'].toString()), child: const Text('PDF', style: lien)),
              ]),
            for (final x in docs)
              Row(children: [
                Expanded(child: Text('${_libelles[x.d]} — ${x.c['intitule'] ?? ''} · ${x.c[x.d]['statut'] == 'valide' ? 'Validé' : 'Brouillon'}',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: x.c[x.d]['statut'] == 'valide' ? null : _amber))),
                if (_peut) TextButton(onPressed: () async { await ouvrirCrChirurgie(context, x.c, type: x.d); await charger(); },
                    child: const Text('Ouvrir', style: lien)),
                if (x.url.isNotEmpty) TextButton(
                  onPressed: () => transmettreDocIntervention(context, animalId: widget.animalId, doc: x.d, url: x.url, rdvId: widget.rdvId),
                  child: const Text('Envoyer', style: lien)),
              ]),
          ]),
        ),
      ]),
    );
  }
}
