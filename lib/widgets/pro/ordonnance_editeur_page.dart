// Éditeur d'ordonnance (contenu structuré, migration_ordonnances_v2.sql) :
// lignes complètes (médicament, présentation, principe actif, posologie, voie,
// durée, quantité, renouvellement, instructions, mentions réglementaires),
// contrôles (bloquants / à vérifier), aperçu du PDF, puis « Modifier »,
// « Enregistrer le brouillon » ou « Valider et signer » (vétérinaire
// seulement — l'ASV prépare). Statut, numéro et validateur sont posés par le
// serveur (pm_ordonnance_controle). Rien n'est complété automatiquement.
// Miroir site : website/src/components/pro/OrdonnanceEditeur.tsx (+ fonctions
// de mes-patients/[id]/page.tsx).

import 'dart:typed_data';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/pro/ordonnance_pdf.dart';
import 'package:PetsMatch/utils/contexte_pro.dart';
import 'package:PetsMatch/utils/ordonnance.dart';
import 'package:PetsMatch/utils/signature_pro.dart';
import 'package:PetsMatch/utils/storage_helper.dart';

const _teal = Color(0xFF0C5C6C);
const _muted = Color(0xFF6B7280);
const _amber = Color(0xFF8A5A00);
final _supa = Supabase.instance.client;

String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _jj(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Un vétérinaire (titulaire, ou praticien de l'espace clinique) — jamais une
/// ASV : l'ordonnance porte le nom et la signature de qui la valide.
Future<bool> peutPrescrireOrdonnance() async =>
    AgendaContexte.catPro == 'veterinaire' &&
    (!AgendaContexte.pourEmployeur || await AgendaContexte.praticienEmploye()) &&
    await AgendaContexte.peut('vet_ordonnances');

/// Préparer un brouillon : aussi l'ASV (rédaction de CR ou droit ordonnances).
Future<bool> peutPreparerOrdonnance() async =>
    AgendaContexte.catPro == 'veterinaire' &&
    (await AgendaContexte.peut('vet_ordonnances') || await AgendaContexte.peut('vet_cr_rediger') ||
        await AgendaContexte.peut('vet_cr_valider'));

String get _prescripteur {
  final n = '${User_Info.firstname} ${User_Info.lastname}'.replaceAll('none', '').trim();
  return n.isEmpty ? 'Vétérinaire' : n;
}

/// Nouvelle ordonnance en brouillon. Version rectificative : rattachée à
/// l'ordonnance corrigée (même propriétaire, même RDV).
Future<Map<String, dynamic>> creerBrouillonOrdonnance({
  required String animalId,
  required ContenuOrdo contenu,
  required DateTime date,
  String? rdvId,
  String? ownerUid,
  String? ownerProfileId,
  Map<String, dynamic>? remplace,
}) async {
  String? oUid = remplace != null ? remplace['owner_uid']?.toString() : ownerUid;
  String? oProfil = remplace != null ? remplace['owner_profile_id']?.toString() : ownerProfileId;
  if (remplace == null && oProfil == null && oUid != null && oUid.isNotEmpty) {
    final p = await _supa.from('user_profiles_complet').select('id')
        .eq('uid', oUid).eq('profile_type', 'particulier').limit(1).maybeSingle();
    oProfil = p?['id']?.toString();
  }
  final rdv = remplace != null ? remplace['rdv_id']?.toString() : rdvId;
  final pro = AgendaContexte.profileId;
  final monProfil = await AgendaContexte.monProfil();
  final row = await _supa.from('ordonnances').insert({
    'animal_id': animalId,
    'pro_uid': AgendaContexte.uid,
    if (pro.isNotEmpty) 'pro_profile_id': pro,
    if (monProfil != null) 'redige_par_profile_id': monProfil,
    if (oUid != null && oUid.isNotEmpty) 'owner_uid': oUid,
    if (oProfil != null && oProfil.isNotEmpty) 'owner_profile_id': oProfil,
    if (rdv != null && rdv.isNotEmpty) 'rdv_id': rdv,
    if (remplace != null) 'remplace_id': remplace['id'],
    'statut': 'brouillon',
    'contenu': contenu.toJson(),
    'date_emit': _ymd(date),
    'notes': contenu.resume.isEmpty ? null : contenu.resume,
    'source': 'veterinaire',
  }).select().single();
  return Map<String, dynamic>.from(row);
}

/// PDF d'une ordonnance (aperçu, ou version validée avec son numéro).
Future<Uint8List> _construirePdf(Map<String, dynamic> base, ContenuOrdo c, DateTime date,
    {String? numero, Map<String, dynamic>? remplace, bool apercu = false}) async {
  final pro = (base['pro_profile_id'] ?? AgendaContexte.profileId).toString();
  final clinique = pro.isEmpty ? null : await _supa.from('user_profiles_complet')
      .select('nom, rue_pro, code_postal_pro, ville_pro, phone_number, certifications').eq('id', pro).maybeSingle();
  final animal = await _supa.from('animaux')
      .select('nom, espece, race, sexe, date_naissance, age_estime, identification, client_clinique_id').eq('id', base['animal_id']).maybeSingle();
  var proprio = '';
  final ownerProfil = (base['owner_profile_id'] ?? '').toString();
  final ownerUid = (base['owner_uid'] ?? '').toString();
  final o = ownerProfil.isNotEmpty
      ? await _supa.from('user_profiles_complet').select('firstname, lastname').eq('id', ownerProfil).maybeSingle()
      : ownerUid.isNotEmpty
          ? await _supa.from('user_profiles_complet').select('firstname, lastname')
              .eq('uid', ownerUid).eq('profile_type', 'particulier').limit(1).maybeSingle()
          : null;
  if (o != null) proprio = '${o['firstname'] ?? ''} ${o['lastname'] ?? ''}'.trim();
  // Patient créé par la clinique : client du fichier clients.
  final clientId = (animal?['client_clinique_id'] ?? '').toString();
  if (proprio.isEmpty && clientId.isNotEmpty) {
    try {
      final cc = await _supa.from('clients_clinique').select('prenom, nom').eq('id', clientId).maybeSingle();
      if (cc != null) proprio = '${cc['prenom'] ?? ''} ${cc['nom'] ?? ''}'.trim();
    } catch (_) {}
  }
  var ordre = '';
  if (clinique?['certifications'] is List) {
    for (final x in clinique!['certifications'] as List) {
      if (x is Map && (x['nom'] ?? '').toString().toLowerCase().contains('ordre')) { ordre = (x['numero'] ?? '').toString(); break; }
    }
  }
  final adresse = [clinique?['rue_pro'], '${clinique?['code_postal_pro'] ?? ''} ${clinique?['ville_pro'] ?? ''}'.trim()]
      .where((x) => (x?.toString() ?? '').trim().isNotEmpty).join(', ');
  final poids = c.poids.trim().replaceAll('.', ',');
  return ordonnancePdfBytes(
    cliniqueNom: (clinique?['nom'] as String?)?.trim().isNotEmpty == true ? clinique!['nom'] as String : 'Cabinet vétérinaire',
    cliniqueAdresse: adresse,
    cliniqueTel: (clinique?['phone_number'] ?? '').toString(),
    numeroOrdre: ordre,
    prescripteur: _prescripteur,
    animalNom: (animal?['nom'] ?? 'Animal').toString(),
    animalEspeceRace: [animal?['espece'], animal?['race']].where((x) => (x?.toString() ?? '').isNotEmpty).join(' · '),
    animalSexe: sexeAnimal(animal?['sexe']),
    animalAge: ageAnimal(animal?['date_naissance'], animal?['age_estime']),
    signature: apercu ? null : octetsSignature(await maSignaturePro()),
    animalIdentification: (animal?['identification'] ?? '').toString(),
    animalPoids: poids.isEmpty ? '' : '$poids kg',
    proprietaire: proprio,
    lignes: [
      for (final l in c.lignes.where((l) => !l.vide))
        LigneOrdonnance(medicament: l.medicament.trim(), posologie: l.posologie.trim(), notes: l.instructions.trim(),
            principeActif: l.principeActif, presentation: l.presentation, voie: l.voie, duree: l.duree,
            quantite: l.quantite, renouvellement: l.renouvellement, mentions: l.mentions),
    ],
    remarques: c.remarques,
    date: DateTime(date.year, date.month, date.day, 12),
    numero: numero,
    rectificative: remplace != null,
    remplaceNumero: remplace?['numero']?.toString(),
    remplaceDate: DateTime.tryParse((remplace?['date_emit'] ?? '').toString()),
    apercu: apercu,
  );
}

/// PDF de l'ordonnance validée (numéro posé par le serveur), déposé une seule fois.
Future<void> deposerPdfOrdonnance(Map<String, dynamic> ordo) async {
  Map<String, dynamic>? remplace;
  if (ordo['remplace_id'] != null) {
    final r = await _supa.from('ordonnances').select().eq('id', ordo['remplace_id']).maybeSingle();
    if (r != null) remplace = Map<String, dynamic>.from(r);
  }
  final date = DateTime.tryParse((ordo['date_emit'] ?? '').toString()) ?? DateTime.now();
  final bytes = await _construirePdf(ordo, ContenuOrdo.fromJson(ordo['contenu']), date,
      numero: ordo['numero']?.toString(), remplace: remplace);
  final moi = AgendaContexte.moi ?? AgendaContexte.uid;
  final url = await uploadDocumentBytes(bytes, 'ordonnances/$moi/${DateTime.now().millisecondsSinceEpoch}.pdf');
  final r = await _supa.from('ordonnances').update({'doc_url': url})
      .eq('id', ordo['id']).or('doc_url.is.null,doc_url.eq.').select('id');
  if ((r as List).isEmpty) throw 'PDF déjà déposé ou ordonnance non modifiable avec vos droits';
}

/// Ouvre l'éditeur : brouillon existant ([ordo]), nouvelle ordonnance
/// ([prefill] éventuel), ou version rectificative ([remplace]). Renvoie true
/// si quelque chose a été enregistré.
Future<bool> ouvrirEditeurOrdonnance(BuildContext context, {
  Map<String, dynamic>? ordo,
  Map<String, dynamic>? remplace,
  required String animalId,
  String? ownerUid,
  String? rdvId,
  ContenuOrdo? prefill,
}) async {
  final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => _OrdonnanceEditeurPage(
      ordo: ordo, remplace: remplace, animalId: animalId, ownerUid: ownerUid, rdvId: rdvId, prefill: prefill)));
  return ok == true;
}

class _Ligne {
  final medicament = TextEditingController(), principeActif = TextEditingController(),
      presentation = TextEditingController(), posologie = TextEditingController(), voie = TextEditingController(),
      duree = TextEditingController(), quantite = TextEditingController(), renouvellement = TextEditingController(),
      instructions = TextEditingController(), mentions = TextEditingController();
  _Ligne([LigneOrdo? l]) {
    if (l == null) return;
    medicament.text = l.medicament; principeActif.text = l.principeActif; presentation.text = l.presentation;
    posologie.text = l.posologie; voie.text = l.voie; duree.text = l.duree; quantite.text = l.quantite;
    renouvellement.text = l.renouvellement; instructions.text = l.instructions; mentions.text = l.mentions;
  }
  LigneOrdo get valeur => LigneOrdo(medicament: medicament.text, principeActif: principeActif.text,
      presentation: presentation.text, posologie: posologie.text, voie: voie.text, duree: duree.text,
      quantite: quantite.text, renouvellement: renouvellement.text, instructions: instructions.text, mentions: mentions.text);
  List<TextEditingController> get tous => [medicament, principeActif, presentation, posologie, voie, duree, quantite,
      renouvellement, instructions, mentions];
  void dispose() { for (final c in tous) { c.dispose(); } }
}

class _OrdonnanceEditeurPage extends StatefulWidget {
  final Map<String, dynamic>? ordo, remplace;
  final String animalId;
  final String? ownerUid, rdvId;
  final ContenuOrdo? prefill;
  const _OrdonnanceEditeurPage({this.ordo, this.remplace, required this.animalId, this.ownerUid, this.rdvId, this.prefill});
  @override
  State<_OrdonnanceEditeurPage> createState() => _OrdonnanceEditeurPageState();
}

String _texteRectificative(Map<String, dynamic> r) {
  final n = (r['numero'] ?? '').toString();
  final d = DateTime.tryParse((r['date_emit'] ?? '').toString());
  return "Version rectificative de l'ordonnance${n.isNotEmpty ? ' n° $n' : ''}${d != null ? ' du ${_jj(d)}' : ''} : "
      'à la validation, celle-ci est marquée « Remplacée » et reste consultable.';
}

class _OrdonnanceEditeurPageState extends State<_OrdonnanceEditeurPage> {
  late DateTime _date;
  final _poids = TextEditingController();
  final _remarques = TextEditingController();
  final List<_Ligne> _lignes = [];
  bool _peutValider = false;
  String? _espece;
  bool _verifie = false;
  Uint8List? _pdf;
  String? _occupe;

  @override
  void initState() {
    super.initState();
    final base = widget.remplace ?? widget.ordo;
    final c = base != null ? ContenuOrdo.fromJson(base['contenu']) : widget.prefill ?? ContenuOrdo(lignes: []);
    _date = DateTime.tryParse((widget.ordo?['date_emit'] ?? '').toString()) ?? DateTime.now();
    _poids.text = c.poids;
    _remarques.text = c.remarques;
    _lignes.addAll(c.lignes.isEmpty ? [_Ligne()] : c.lignes.map(_Ligne.new));
    for (final l in _lignes) { _ecouter(l); }
    _poids.addListener(_change);
    peutPrescrireOrdonnance().then((v) { if (mounted) setState(() => _peutValider = v); });
    _supa.from('animaux').select('espece').eq('id', widget.animalId).maybeSingle().then((a) {
      if (mounted) setState(() => _espece = a?['espece']?.toString());
    }).catchError((_) {});
  }

  void _ecouter(_Ligne l) { for (final c in l.tous) { c.addListener(_change); } }
  void _change() { if (mounted) setState(() => _verifie = false); }

  @override
  void dispose() {
    _poids.dispose(); _remarques.dispose();
    for (final l in _lignes) { l.dispose(); }
    super.dispose();
  }

  ContenuOrdo get _contenu => ContenuOrdo(lignes: [for (final l in _lignes) l.valeur], poids: _poids.text, remarques: _remarques.text);
  /// Contenu nettoyé tel qu'il est enregistré.
  ContenuOrdo get _propre => ContenuOrdo.fromJson(_contenu.toJson());

  Future<void> _action(String type) async {
    final ctrl = controlerOrdo(_contenu, _espece);
    if (type == 'valider' && ctrl.bloquants.isNotEmpty) return;
    setState(() => _occupe = type);
    try {
      final c = _propre;
      if (type == 'apercu') {
        final base = widget.ordo ?? {'animal_id': widget.animalId, 'owner_uid': widget.remplace?['owner_uid'] ?? widget.ownerUid,
          'owner_profile_id': widget.remplace?['owner_profile_id']};
        final b = await _construirePdf(base, c, _date, remplace: widget.remplace, apercu: true);
        if (mounted) setState(() => _pdf = b);
        return;
      }
      var ordo = widget.ordo;
      if (type == 'brouillon') {
        if (ordo == null) {
          await creerBrouillonOrdonnance(animalId: widget.animalId, contenu: c, date: _date,
              rdvId: widget.rdvId, ownerUid: widget.ownerUid, remplace: widget.remplace);
        } else {
          final r = await _supa.from('ordonnances').update({
            'contenu': c.toJson(), 'date_emit': _ymd(_date), 'notes': c.resume.isEmpty ? null : c.resume,
          }).eq('id', ordo['id']).eq('statut', 'brouillon').select('id');
          if ((r as List).isEmpty) throw 'brouillon introuvable ou déjà validé';
        }
        if (mounted) Navigator.pop(context, true);
        return;
      }
      // Validation par le vétérinaire.
      ordo ??= await creerBrouillonOrdonnance(animalId: widget.animalId, contenu: c, date: _date,
          rdvId: widget.rdvId, ownerUid: widget.ownerUid, remplace: widget.remplace);
      final moi = await AgendaContexte.monProfil();
      final signee = (await maSignaturePro()) != null;
      final v = await _supa.from('ordonnances').update({
        'contenu': c.toJson(), 'date_emit': _ymd(_date), 'notes': c.resume.isEmpty ? null : c.resume,
        'statut': signee ? 'signee' : 'validee',
        if (moi != null) 'praticien_profile_id': moi,
        if (moi != null) 'valide_par_profile_id': moi,
      }).eq('id', ordo['id']).eq('statut', 'brouillon').select().single();
      try {
        await deposerPdfOrdonnance(Map<String, dynamic>.from(v));
      } catch (e) {
        _message('Ordonnance validée, mais PDF non enregistré ($e) : utilisez « Générer le PDF ».');
      }
      try {
        await FirebaseFunctions.instanceFor(region: 'europe-west1').httpsCallable('notifyOwnerVetEntry')
            .call({'animalId': widget.animalId, 'vetName': _prescripteur, 'typeActe': 'ordonnance'});
      } catch (_) {}
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _message('${type == 'apercu' ? 'Aperçu impossible' : 'Non enregistré'} : $e');
    } finally {
      if (mounted) setState(() => _occupe = null);
    }
  }

  void _message(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t, style: const TextStyle(fontFamily: 'Galey')), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
  }

  InputDecoration _deco(String label, {String? aide}) => InputDecoration(
        labelText: label, hintText: aide, isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );

  Widget _alertes(({List<String> bloquants, List<String> avertissements}) ctrl) {
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
          child: Text('Vous préparez cette ordonnance : un vétérinaire la complète, la valide et la signe.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: _muted))),
    ]);
  }

  Widget _boutonsFin(({List<String> bloquants, List<String> avertissements}) ctrl) {
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
    final pdf = _pdf;
    final ctrl = controlerOrdo(_contenu, _espece);
    final titre = widget.remplace != null ? 'Version rectificative'
        : widget.ordo != null ? (_peutValider ? 'Compléter et valider' : 'Brouillon d’ordonnance') : 'Nouvelle ordonnance';
    const bouton = TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700);
    return Scaffold(
      appBar: AppBar(
        title: Text(titre, style: const TextStyle(fontFamily: 'Galey', fontSize: 16)),
        backgroundColor: Colors.white, foregroundColor: const Color(0xFF1E2025), elevation: 0.5,
      ),
      backgroundColor: Colors.white,
      body: pdf != null
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
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerLeft, child: TextButton(
                    onPressed: _occupe != null ? null : () => setState(() => _pdf = null),
                    child: const Text('Modifier', style: TextStyle(fontFamily: 'Galey', color: _teal, fontWeight: FontWeight.w700)),
                  )),
                  _boutonsFin(ctrl),
                ]),
              )),
            ])
          : ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 32), children: [
              if (widget.remplace != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFF4F7F8), borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE4E7E2))),
                  child: Text(_texteRectificative(widget.remplace!),
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5)),
                ),
              if (_peutValider)
                Text('Prescripteur : $_prescripteur (votre nom et votre signature figurent sur l’ordonnance validée).',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: _muted)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: InkWell(
                  onTap: () async {
                    final p = await showDatePicker(context: context, initialDate: _date,
                        firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 365)));
                    if (p != null) setState(() => _date = p);
                  },
                  child: InputDecorator(decoration: _deco('Date de l’ordonnance'),
                      child: Text(_jj(_date), style: const TextStyle(fontFamily: 'Galey'))),
                )),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _poids,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: _deco('Poids (kg, facultatif)'))),
              ]),
              const SizedBox(height: 14),
              for (var i = 0; i < _lignes.length; i++)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE4E7E2))),
                  child: Column(children: [
                    Row(children: [
                      Expanded(child: Text('Médicament ${i + 1}', style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: _muted))),
                      if (_lignes.length > 1)
                        TextButton(
                          onPressed: () => setState(() => _lignes.removeAt(i).dispose()),
                          child: const Text('Retirer', style: TextStyle(fontFamily: 'Galey', color: Colors.red)),
                        ),
                    ]),
                    for (final (c, label, aide, lignes) in [
                      (_lignes[i].medicament, 'Médicament *', null, 1),
                      (_lignes[i].presentation, 'Présentation et concentration', 'ex. comprimé 50 mg', 1),
                      (_lignes[i].principeActif, 'Principe actif', null, 1),
                      (_lignes[i].posologie, 'Posologie * (dose, prises, fréquence)', null, 2),
                      (_lignes[i].duree, 'Durée *', 'ex. 7 jours, au long cours', 1),
                      (_lignes[i].quantite, 'Quantité à délivrer', 'ex. 1 boîte de 14', 1),
                      (_lignes[i].renouvellement, 'Renouvellement', 'Vide = non renouvelable', 1),
                      (_lignes[i].instructions, 'Instructions particulières', 'à jeun, avec le repas…', 1),
                      (_lignes[i].mentions, 'Mentions réglementaires', "temps d'attente, catégorie du médicament…", 1),
                    ]) ...[
                      const SizedBox(height: 8),
                      TextField(controller: c, maxLines: lignes, decoration: _deco(label, aide: aide)),
                      if (c == _lignes[i].posologie) ...[
                        const SizedBox(height: 8),
                        TextField(controller: _lignes[i].voie, decoration: _deco("Voie d'administration").copyWith(
                          suffixIcon: PopupMenuButton<String>(
                            icon: const Icon(Icons.arrow_drop_down),
                            onSelected: (v) => _lignes[i].voie.text = v,
                            itemBuilder: (_) => [for (final v in voiesOrdonnance) PopupMenuItem(value: v, child: Text(v, style: const TextStyle(fontFamily: 'Galey')))],
                          ),
                        )),
                      ],
                    ],
                  ]),
                ),
              Align(alignment: Alignment.centerLeft, child: TextButton(
                onPressed: () => setState(() { final l = _Ligne(); _ecouter(l); _lignes.add(l); }),
                child: const Text('Ajouter un médicament', style: TextStyle(fontFamily: 'Galey', color: _teal, fontWeight: FontWeight.w700)),
              )),
              TextField(controller: _remarques, maxLines: 2, decoration: _deco('Remarques (facultatif)')),
              _alertes(ctrl),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: _occupe != null ? null : () => _action('apercu'),
                style: OutlinedButton.styleFrom(foregroundColor: _teal, side: const BorderSide(color: _teal), minimumSize: const Size.fromHeight(44)),
                child: Text(_occupe == 'apercu' ? 'Préparation…' : 'Aperçu', style: bouton),
              ),
              const SizedBox(height: 10),
              _boutonsFin(ctrl),
            ]),
    );
  }
}
