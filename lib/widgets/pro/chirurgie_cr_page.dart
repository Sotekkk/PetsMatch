// Comptes rendus préopératoire et opératoire d'une intervention : saisie
// structurée, contrôles, aperçu PDF, « Enregistrer le brouillon » ou
// « Valider et signer » (vétérinaire ; l'ASV prépare). Un compte rendu validé
// ne se modifie qu'en « Nouvelle version » : la version précédente est
// archivée par le serveur (migration_chirurgies_cr.sql).
// Miroir site : website/src/components/pro/ChirurgieCrModal.tsx.

import 'dart:typed_data';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/pro/ordonnance_pdf.dart';
import 'package:PetsMatch/utils/chirurgie_cr.dart';
import 'package:PetsMatch/utils/contexte_pro.dart';
import 'package:PetsMatch/utils/document_prive.dart';
import 'package:PetsMatch/utils/signature_pro.dart';
import 'package:PetsMatch/utils/storage_helper.dart';
import 'package:PetsMatch/widgets/pro/ordonnance_editeur_page.dart' show peutPrescrireOrdonnance, peutPreparerOrdonnance;

const _teal = Color(0xFF0C5C6C);
const _muted = Color(0xFF6B7280);
const _amber = Color(0xFF8A5A00);

/// Préparer les comptes rendus d'intervention (vétérinaire ou ASV).
Future<bool> peutPreparerCrChirurgie() => peutPreparerOrdonnance();

/// Ouvre la saisie ; renvoie true si quelque chose a été enregistré.
Future<bool> ouvrirCrChirurgie(BuildContext context, Map<String, dynamic> chirurgie, {String type = 'preop'}) async {
  final ok = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(builder: (_) => _ChirurgieCrPage(chirurgie: chirurgie, typeInitial: type)));
  return ok == true;
}

String get _praticien {
  final n = '${User_Info.firstname} ${User_Info.lastname}'.replaceAll('none', '').trim();
  return n.isEmpty ? 'Vétérinaire' : n;
}

class _ChirurgieCrPage extends StatefulWidget {
  final Map<String, dynamic> chirurgie;
  final String typeInitial;
  const _ChirurgieCrPage({required this.chirurgie, required this.typeInitial});
  @override
  State<_ChirurgieCrPage> createState() => _ChirurgieCrPageState();
}

class _ChirurgieCrPageState extends State<_ChirurgieCrPage> {
  final _supa = Supabase.instance.client;
  late String _type = widget.typeInitial;
  final Map<String, Map<String, TextEditingController>> _ctrl = {};
  final Map<String, bool> _nouvelleVersion = {'preop': false, 'operatoire': false};
  bool _peutValider = false;
  bool _verifie = false;
  Uint8List? _pdf;
  String? _occupe;

  @override
  void initState() {
    super.initState();
    for (final t in ['preop', 'operatoire']) {
      final p = prerempliCrChir(t, widget.chirurgie);
      _ctrl[t] = {for (final e in p.entries) e.key: TextEditingController(text: e.value)..addListener(_change)};
    }
    peutPrescrireOrdonnance().then((v) { if (mounted) setState(() => _peutValider = v); });
    // Poids de la fiche (pré-op), si rien n'est saisi.
    _supa.from('animaux').select('poids').eq('id', widget.chirurgie['animal_id']).maybeSingle().then((a) {
      final c = _ctrl['preop']!['poids']!;
      if (mounted && c.text.isEmpty && (a?['poids']?.toString() ?? '').isNotEmpty) c.text = a!['poids'].toString();
    }).catchError((_) {});
  }

  void _change() { if (mounted) setState(() => _verifie = false); }

  @override
  void dispose() {
    for (final m in _ctrl.values) { for (final c in m.values) { c.dispose(); } }
    super.dispose();
  }

  Map<String, String> get _champs => {for (final e in _ctrl[_type]!.entries) e.key: e.value.text.trim()};
  Map? get _doc => widget.chirurgie[_type] is Map ? widget.chirurgie[_type] as Map : null;
  bool get _valide => _doc?['statut'] == 'valide';
  bool get _verrouille => _valide && !_nouvelleVersion[_type]!;
  String get _docUrl => (widget.chirurgie['${_type}_doc_url'] ?? '').toString();

  Future<Uint8List> _construirePdf(Map<String, dynamic> c, Map<String, String> champs, {required bool apercu}) async {
    final pro = AgendaContexte.profileId;
    final clinique = pro.isEmpty ? null : await _supa.from('user_profiles_complet')
        .select('nom, rue_pro, code_postal_pro, ville_pro, phone_number, email_contact').eq('id', pro).maybeSingle();
    final animal = await _supa.from('animaux')
        .select('nom, espece, race, sexe, date_naissance, age_estime, identification, uid_proprietaire, uid_eleveur, client_clinique_id')
        .eq('id', c['animal_id']).maybeSingle();
    var proprio = '';
    final ownerUid = (animal?['uid_proprietaire'] ?? animal?['uid_eleveur'] ?? '').toString();
    if (ownerUid.isNotEmpty) {
      final o = await _supa.from('user_profiles_complet').select('firstname, lastname')
          .eq('uid', ownerUid).eq('profile_type', 'particulier').limit(1).maybeSingle();
      if (o != null) proprio = '${o['firstname'] ?? ''} ${o['lastname'] ?? ''}'.trim();
    }
    final clientId = (animal?['client_clinique_id'] ?? '').toString();
    if (proprio.isEmpty && clientId.isNotEmpty) {
      try {
        final cc = await _supa.from('clients_clinique').select('prenom, nom').eq('id', clientId).maybeSingle();
        if (cc != null) proprio = '${cc['prenom'] ?? ''} ${cc['nom'] ?? ''}'.trim();
      } catch (_) {}
    }
    final adresse = [clinique?['rue_pro'], '${clinique?['code_postal_pro'] ?? ''} ${clinique?['ville_pro'] ?? ''}'.trim()]
        .where((x) => (x?.toString() ?? '').trim().isNotEmpty).join(', ');
    return compteRenduPdfBytes(
      cliniqueNom: (clinique?['nom'] as String?)?.trim().isNotEmpty == true ? clinique!['nom'] as String : 'Cabinet vétérinaire',
      cliniqueAdresse: adresse,
      cliniqueTel: (clinique?['phone_number'] ?? '').toString(),
      cliniqueEmail: (clinique?['email_contact'] ?? '').toString(),
      praticien: _praticien,
      animalNom: (animal?['nom'] ?? 'Animal').toString(),
      animalEspeceRace: [animal?['espece'], animal?['race']].where((x) => (x?.toString() ?? '').isNotEmpty).join(' · '),
      animalSexe: sexeAnimal(animal?['sexe']),
      animalAge: ageAnimal(animal?['date_naissance'], animal?['age_estime']),
      animalIdentification: (animal?['identification'] ?? '').toString(),
      proprietaire: proprio,
      contenu: texteCrChir(_type, champs, c['date']?.toString()),
      date: DateTime.tryParse((c['date'] ?? '').toString()),
      signature: apercu ? null : octetsSignature(await maSignaturePro()),
      titre: '${titreCrChir[_type]!.toUpperCase()}${apercu ? ' (APERÇU)' : ''}',
    );
  }

  Future<void> _action(String a) async {
    setState(() => _occupe = a);
    try {
      final champs = _champs;
      if (a == 'apercu') {
        final b = await _construirePdf(widget.chirurgie, champs, apercu: true);
        if (mounted) setState(() => _pdf = b);
        return;
      }
      final valider = a == 'valider';
      final contenu = {for (final e in champs.entries) if (e.value.isNotEmpty) e.key: e.value};
      final sansPro = (widget.chirurgie['pro_uid'] ?? '').toString().isEmpty;
      final row = await _supa.from('chirurgies').update({
        _type: {...contenu, 'statut': valider ? 'valide' : 'brouillon'},
        if (sansPro) 'pro_uid': AgendaContexte.uid,
        if (sansPro && AgendaContexte.profileId.isNotEmpty) 'pro_profile_id': AgendaContexte.profileId,
      }).eq('id', widget.chirurgie['id']).select().single();
      if (valider) {
        try {
          final bytes = await _construirePdf(Map<String, dynamic>.from(row), champs, apercu: false);
          final moi = FirebaseAuth.instance.currentUser?.uid ?? AgendaContexte.uid;
          final url = await uploadDocumentBytes(bytes, 'chirurgies/$moi/${DateTime.now().millisecondsSinceEpoch}.pdf');
          await _supa.from('chirurgies').update({'${_type}_doc_url': url}).eq('id', widget.chirurgie['id']);
        } catch (e) {
          _message('Compte rendu validé, mais PDF non enregistré : $e');
        }
        try {
          await FirebaseFunctions.instanceFor(region: 'europe-west1').httpsCallable('notifyOwnerVetEntry')
              .call({'animalId': widget.chirurgie['animal_id'], 'vetName': _praticien, 'typeActe': 'chirurgie'});
        } catch (_) {}
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _message('${a == 'apercu' ? 'Aperçu impossible' : 'Non enregistré'} : $e');
    } finally {
      if (mounted) setState(() => _occupe = null);
    }
  }

  void _message(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t, style: const TextStyle(fontFamily: 'Galey')), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
  }

  Widget _alertes(({List<String> bloquants, List<String> avertissements}) ctrl) {
    if (_verrouille) return const SizedBox.shrink();
    Widget boite(Color fond, Color bord, Color texte, String titre, List<String> l, {Widget? fin}) => Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(10), border: Border.all(color: bord)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titre, style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w700, color: texte)),
            for (final m in l) Text('• $m', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: texte)),
            if (fin != null) fin,
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (ctrl.bloquants.isNotEmpty)
        boite(const Color(0xFFFEF2F2), const Color(0xFFFECACA), const Color(0xFFB91C1C), 'À compléter avant la validation :', ctrl.bloquants),
      if (ctrl.avertissements.isNotEmpty)
        boite(const Color(0xFFFFF8EA), const Color(0xFFF3E2BD), _amber, 'À vérifier :', ctrl.avertissements,
            fin: _peutValider
                ? CheckboxListTile(
                    contentPadding: EdgeInsets.zero, dense: true, value: _verifie, activeColor: _amber,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (v) => setState(() => _verifie = v == true),
                    title: const Text("J'ai vérifié ces points", style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w700, color: _amber)),
                  )
                : null),
      if (!_peutValider)
        const Padding(padding: EdgeInsets.only(top: 8),
          child: Text('Vous préparez ce compte rendu : un vétérinaire le complète, le valide et le signe.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: _muted))),
    ]);
  }

  Widget _boutons(({List<String> bloquants, List<String> avertissements}) ctrl) {
    if (_verrouille) return const SizedBox.shrink();
    const style = TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700);
    final peutConfirmer = _peutValider && ctrl.bloquants.isEmpty && (ctrl.avertissements.isEmpty || _verifie);
    return Row(children: [
      Expanded(child: OutlinedButton(
        onPressed: _occupe != null ? null : () => _action('brouillon'),
        style: OutlinedButton.styleFrom(foregroundColor: _teal, side: const BorderSide(color: _teal)),
        child: Text(_occupe == 'brouillon' ? 'Enregistrement…' : 'Enregistrer le brouillon', style: style, textAlign: TextAlign.center),
      )),
      if (_peutValider) ...[
        const SizedBox(width: 10),
        Expanded(child: FilledButton(
          onPressed: _occupe != null || !peutConfirmer ? null : () => _action('valider'),
          style: FilledButton.styleFrom(backgroundColor: _teal),
          child: Text(_occupe == 'valider' ? 'Validation…' : 'Valider et signer', style: style, textAlign: TextAlign.center),
        )),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = controlerCrChir(_type, _champs);
    final pdf = _pdf;
    final d = _doc;
    final version = (d?['version'] as num?)?.toInt() ?? 1;
    final valideLe = DateTime.tryParse((d?['valide_le'] ?? '').toString())?.toLocal();
    final statut = d == null ? 'Non rédigé' : _valide
        ? 'Validé${valideLe != null ? ' le ${valideLe.day.toString().padLeft(2, '0')}/${valideLe.month.toString().padLeft(2, '0')}/${valideLe.year}' : ''}${version > 1 ? ' · version $version' : ''}'
        : 'Brouillon';
    const lien = TextStyle(fontFamily: 'Galey', color: _teal, fontWeight: FontWeight.w700);
    return Scaffold(
      appBar: AppBar(
        title: Text((widget.chirurgie['intitule'] ?? 'Intervention').toString(), style: const TextStyle(fontFamily: 'Galey', fontSize: 16)),
        backgroundColor: Colors.white, foregroundColor: const Color(0xFF1E2025), elevation: 0.5,
      ),
      backgroundColor: Colors.white,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(children: [
            for (final t in ['preop', 'operatoire']) ...[
              Expanded(child: ChoiceChip(
                label: Text(titreCrChir[t]!.replaceFirst('Compte rendu ', 'CR '), style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5)),
                selected: _type == t, selectedColor: _teal.withValues(alpha: 0.15),
                onSelected: (_) => setState(() { _type = t; _pdf = null; _verifie = false; }),
              )),
              if (t == 'preop') const SizedBox(width: 8),
            ],
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: Row(children: [
            Expanded(child: Text(statut, style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w700,
                color: _valide ? _teal : d != null ? _amber : _muted))),
            if (_valide && _docUrl.isNotEmpty)
              TextButton(onPressed: () => ouvrirDocument(context, _docUrl), child: const Text('Ouvrir le PDF', style: lien)),
            if (_verrouille && _peutValider)
              TextButton(onPressed: () => setState(() => _nouvelleVersion[_type] = true), child: const Text('Nouvelle version', style: lien)),
          ]),
        ),
        Expanded(child: pdf != null
            ? Column(children: [
                Expanded(child: PdfPreview(
                  build: (_) async => pdf,
                  allowPrinting: false, allowSharing: false, canChangePageFormat: false,
                  canChangeOrientation: false, canDebug: false,
                )),
                SafeArea(top: false, child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    _alertes(ctrl),
                    Align(alignment: Alignment.centerLeft, child: TextButton(
                      onPressed: _occupe != null ? null : () => setState(() => _pdf = null),
                      child: const Text('Modifier', style: lien),
                    )),
                    _boutons(ctrl),
                  ]),
                )),
              ])
            : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
                if (_nouvelleVersion[_type]! && _valide)
                  const Padding(padding: EdgeInsets.only(bottom: 8),
                    child: Text("Nouvelle version : la version validée actuelle (et son PDF) est conservée dans l'historique de l'intervention.",
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: _muted))),
                if (_type == 'preop')
                  const Padding(padding: EdgeInsets.only(bottom: 8),
                    child: Text("L'évaluation préopératoire ne vaut pas consentement du propriétaire : le PDF le précise.",
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: _muted))),
                for (final f in champsCrChir[_type]!) ...[
                  TextField(
                    controller: _ctrl[_type]![f.$1],
                    enabled: !_verrouille,
                    maxLines: f.$3 ? null : 1, minLines: f.$3 ? 2 : 1,
                    keyboardType: f.$1 == 'poids' ? const TextInputType.numberWithOptions(decimal: true) : (f.$3 ? TextInputType.multiline : null),
                    decoration: InputDecoration(labelText: f.$2, isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                  ),
                  const SizedBox(height: 10),
                ],
                _alertes(ctrl),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _occupe != null ? null : () => _action('apercu'),
                  style: OutlinedButton.styleFrom(foregroundColor: _teal, side: const BorderSide(color: _teal), minimumSize: const Size.fromHeight(44)),
                  child: Text(_occupe == 'apercu' ? 'Préparation…' : 'Aperçu', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 10),
                _boutons(ctrl),
              ])),
      ]),
    );
  }
}
