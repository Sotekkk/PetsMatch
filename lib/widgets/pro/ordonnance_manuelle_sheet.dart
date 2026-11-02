// Ordonnance saisie par le vétérinaire hors compte rendu : lignes (médicament,
// posologie, remarques) → aperçu du PDF → « Modifier » ou « Valider ». Sert à
// produire le PDF d'une ordonnance ajoutée à la main sans document
// (« Générer le PDF »). Rien n'est déduit ni complété automatiquement : la
// saisie d'origine est seulement affichée pour que le vétérinaire la reprenne.
// Le prescripteur (nom + signature) est le vétérinaire connecté.
// Miroir site : website/src/components/pro/OrdonnanceManuelleModal.tsx.

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/pro/ordonnance_pdf.dart';
import 'package:PetsMatch/utils/contexte_pro.dart';
import 'package:PetsMatch/utils/signature_pro.dart';
import 'package:PetsMatch/utils/storage_helper.dart';

const _teal = Color(0xFF0C5C6C);
const _muted = Color(0xFF6B7280);
const _amber = Color(0xFF8A5A00);

/// Un vétérinaire (titulaire, ou praticien de l'espace clinique) — jamais une
/// ASV : l'ordonnance porte le nom et la signature de qui la produit.
Future<bool> peutPrescrireOrdonnance() async =>
    AgendaContexte.catPro == 'veterinaire' &&
    (!AgendaContexte.pourEmployeur || await AgendaContexte.praticienEmploye()) &&
    await AgendaContexte.peut('vet_ordonnances');

/// Produit le PDF d'une ordonnance sans document ([ordo] = ligne `ordonnances`).
/// Renvoie true si le PDF a été enregistré.
Future<bool> genererPdfOrdonnance(BuildContext context, Map<String, dynamic> ordo) async {
  final ok = await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => _OrdonnanceManuellePage(ordo: ordo)));
  return ok == true;
}

String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class _Ligne {
  final medicament = TextEditingController();
  final posologie = TextEditingController();
  final notes = TextEditingController();
  bool get vide => medicament.text.trim().isEmpty && posologie.text.trim().isEmpty && notes.text.trim().isEmpty;
  void dispose() { medicament.dispose(); posologie.dispose(); notes.dispose(); }
}

class _OrdonnanceManuellePage extends StatefulWidget {
  final Map<String, dynamic> ordo;
  const _OrdonnanceManuellePage({required this.ordo});
  @override
  State<_OrdonnanceManuellePage> createState() => _OrdonnanceManuellePageState();
}

class _OrdonnanceManuellePageState extends State<_OrdonnanceManuellePage> {
  final _supa = Supabase.instance.client;
  late DateTime _date;
  final _poids = TextEditingController();
  final List<_Ligne> _lignes = [_Ligne()];
  List<String> _manques = [];
  Uint8List? _pdf;
  bool _occupe = false;

  String get _prescripteur {
    final n = '${User_Info.firstname} ${User_Info.lastname}'.replaceAll('none', '').trim();
    return n.isEmpty ? 'Vétérinaire' : n;
  }

  @override
  void initState() {
    super.initState();
    _date = DateTime.tryParse((widget.ordo['date_emit'] ?? '').toString()) ?? DateTime.now();
  }

  @override
  void dispose() {
    _poids.dispose();
    for (final l in _lignes) { l.dispose(); }
    super.dispose();
  }

  List<LigneOrdonnance> get _saisie => [
        for (final l in _lignes.where((l) => !l.vide))
          LigneOrdonnance(medicament: l.medicament.text.trim(), posologie: l.posologie.text.trim(),
              notes: l.notes.text.trim().isEmpty ? null : l.notes.text.trim()),
      ];

  Future<Uint8List> _construire(List<LigneOrdonnance> lignes) async {
    final pro = (widget.ordo['pro_profile_id'] ?? AgendaContexte.profileId).toString();
    final clinique = pro.isEmpty ? null : await _supa.from('user_profiles_complet')
        .select('nom, rue_pro, code_postal_pro, ville_pro, phone_number, certifications').eq('id', pro).maybeSingle();
    final animal = await _supa.from('animaux')
        .select('nom, espece, race, sexe, date_naissance, age_estime, identification').eq('id', widget.ordo['animal_id']).maybeSingle();
    var proprio = '';
    final ownerProfil = (widget.ordo['owner_profile_id'] ?? '').toString();
    final o = ownerProfil.isNotEmpty
        ? await _supa.from('user_profiles_complet').select('firstname, lastname').eq('id', ownerProfil).maybeSingle()
        : (widget.ordo['owner_uid'] ?? '').toString().isNotEmpty
            ? await _supa.from('user_profiles_complet').select('firstname, lastname')
                .eq('uid', widget.ordo['owner_uid']).eq('profile_type', 'particulier').limit(1).maybeSingle()
            : null;
    if (o != null) proprio = '${o['firstname'] ?? ''} ${o['lastname'] ?? ''}'.trim();
    var ordre = '';
    if (clinique?['certifications'] is List) {
      for (final c in clinique!['certifications'] as List) {
        if (c is Map && (c['nom'] ?? '').toString().toLowerCase().contains('ordre')) { ordre = (c['numero'] ?? '').toString(); break; }
      }
    }
    final adresse = [clinique?['rue_pro'], '${clinique?['code_postal_pro'] ?? ''} ${clinique?['ville_pro'] ?? ''}'.trim()]
        .where((x) => (x?.toString() ?? '').trim().isNotEmpty).join(', ');
    final poids = _poids.text.trim().replaceAll('.', ',');
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
      signature: octetsSignature(await maSignaturePro()),
      animalIdentification: (animal?['identification'] ?? '').toString(),
      animalPoids: poids.isEmpty ? '' : '$poids kg',
      proprietaire: proprio,
      lignes: lignes,
      date: DateTime(_date.year, _date.month, _date.day, 12),
    );
  }

  Future<void> _apercu() async {
    final lignes = _saisie;
    final m = <String>[
      if (lignes.isEmpty) 'Au moins un médicament',
      for (var i = 0; i < lignes.length; i++) ...[
        if (lignes[i].medicament.isEmpty) 'Ligne ${i + 1} : médicament',
        if (lignes[i].posologie.isEmpty) 'Ligne ${i + 1} : posologie (dose, fréquence, durée)',
      ],
    ];
    setState(() => _manques = m);
    if (m.isNotEmpty) return;
    setState(() => _occupe = true);
    try {
      final b = await _construire(lignes);
      if (mounted) setState(() => _pdf = b);
    } catch (e) {
      _message('Aperçu impossible : $e');
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<void> _valider() async {
    final pdf = _pdf;
    if (pdf == null) return;
    setState(() => _occupe = true);
    try {
      final moi = AgendaContexte.moi ?? AgendaContexte.uid;
      final url = await uploadDocumentBytes(pdf, 'ordonnances/$moi/${DateTime.now().millisecondsSinceEpoch}.pdf');
      final monProfil = await AgendaContexte.monProfil();
      final r = await _supa.from('ordonnances').update({
        'doc_url': url,
        'date_emit': _ymd(_date),
        if (AgendaContexte.moi != null) 'praticien_uid': AgendaContexte.moi,
        if (monProfil != null) 'praticien_profile_id': monProfil,
      }).eq('id', widget.ordo['id']).or('doc_url.is.null,doc_url.eq.').select('id');
      if ((r as List).isEmpty) throw 'ordonnance introuvable, déjà pourvue d’un PDF ou non modifiable avec vos droits';
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _message('Non enregistré : $e');
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  void _message(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t, style: const TextStyle(fontFamily: 'Galey')), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
  }

  InputDecoration _deco(String label) => InputDecoration(
        labelText: label, isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );

  @override
  Widget build(BuildContext context) {
    final pdf = _pdf;
    final origine = (widget.ordo['notes'] ?? '').toString().trim();
    const bouton = TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Générer le PDF de l’ordonnance', style: TextStyle(fontFamily: 'Galey', fontSize: 16)),
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
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(children: [
                  Expanded(child: OutlinedButton(
                    onPressed: _occupe ? null : () => setState(() => _pdf = null),
                    style: OutlinedButton.styleFrom(foregroundColor: _teal, side: const BorderSide(color: _teal)),
                    child: const Text('Modifier', style: bouton),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: FilledButton(
                    onPressed: _occupe ? null : _valider,
                    style: FilledButton.styleFrom(backgroundColor: _teal),
                    child: Text(_occupe ? 'Enregistrement…' : 'Valider', style: bouton),
                  )),
                ]),
              )),
            ])
          : ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 32), children: [
              Text('Prescripteur : $_prescripteur (votre nom et votre signature figurent sur l’ordonnance).',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: _muted)),
              if (origine.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFF4F7F8), borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE4E7E2))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Saisie d’origine (à reprendre dans les lignes ci-dessous)',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: _muted)),
                    const SizedBox(height: 4),
                    Text(origine, style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5)),
                  ]),
                ),
              ],
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: InkWell(
                  onTap: () async {
                    final p = await showDatePicker(context: context, initialDate: _date,
                        firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 365)));
                    if (p != null) setState(() => _date = p);
                  },
                  child: InputDecorator(decoration: _deco('Date de l’ordonnance'),
                      child: Text('${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}',
                          style: const TextStyle(fontFamily: 'Galey'))),
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
                      Expanded(child: Text('Ligne ${i + 1}', style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: _muted))),
                      if (_lignes.length > 1)
                        TextButton(
                          onPressed: () => setState(() => _lignes.removeAt(i).dispose()),
                          child: const Text('Retirer', style: TextStyle(fontFamily: 'Galey', color: Colors.red)),
                        ),
                    ]),
                    TextField(controller: _lignes[i].medicament, decoration: _deco('Médicament')),
                    const SizedBox(height: 8),
                    TextField(controller: _lignes[i].posologie, maxLines: 2,
                        decoration: _deco('Posologie : dose, nombre de prises, fréquence, durée')),
                    const SizedBox(height: 8),
                    TextField(controller: _lignes[i].notes, decoration: _deco('Remarques (facultatif)')),
                  ]),
                ),
              Align(alignment: Alignment.centerLeft, child: TextButton(
                onPressed: () => setState(() => _lignes.add(_Ligne())),
                child: const Text('Ajouter un médicament', style: TextStyle(fontFamily: 'Galey', color: _teal, fontWeight: FontWeight.w700)),
              )),
              if (_manques.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFFFF8EA), borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFF3E2BD))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('À compléter avant l’aperçu :',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w700, color: _amber)),
                    for (final m in _manques)
                      Text('• $m', style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: _amber)),
                  ]),
                ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _occupe ? null : _apercu,
                style: FilledButton.styleFrom(backgroundColor: _teal, minimumSize: const Size.fromHeight(44)),
                child: Text(_occupe ? 'Préparation…' : 'Aperçu', style: bouton),
              ),
            ]),
    );
  }
}
