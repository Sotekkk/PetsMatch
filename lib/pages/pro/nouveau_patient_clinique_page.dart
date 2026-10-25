// Clinique — nouveau patient dont le propriétaire n'a pas (forcément)
// PetsMatch : client du fichier de la clinique (clients_clinique) + fiche
// animal, via pm_creer_patient_clinique (migration_patients_clinique.sql).
// Anti-doublon : n° de puce (pm_puce_existante : une puce = une fiche ;
// propriétaire → demande d'accès au carnet ; fiche créée par un autre pro →
// rattachement « identité seule », pm_rattacher_fiche_pro) et compte
// PetsMatch (e-mail / téléphone). Miroir site :
// website/src/components/pro/NouveauPatientModal.tsx.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/pages/pro/animal_acces_page.dart';
import 'package:PetsMatch/utils/user_lookup.dart';

const _teal = Color(0xFF0C5C6C);

const kEspecesPatient = [
  ('chien', 'Chien'), ('chat', 'Chat'), ('cheval', 'Cheval / équidé'), ('lapin', 'Lapin'),
  ('nac', 'NAC'), ('oiseau', 'Oiseau'), ('bovin', 'Bovin'), ('ovin', 'Ovin'), ('caprin', 'Caprin'),
  ('porcin', 'Porcin'), ('autre', 'Autre'),
];

class NouveauPatientCliniquePage extends StatefulWidget {
  /// Profil de la clinique.
  final String cliniqueProfileId;
  /// Vocabulaire : « patient » (vétérinaire) ou « client » (toiletteur,
  /// maréchal-ferrant, ostéopathe, éducateur — même fichier clients).
  final bool estClinique;
  /// Titre selon le métier (« Nouvel animal suivi », « Nouvel équidé »…).
  final String? titre;
  const NouveauPatientCliniquePage({super.key, required this.cliniqueProfileId, this.estClinique = true, this.titre});

  @override
  State<NouveauPatientCliniquePage> createState() => _NouveauPatientCliniquePageState();
}

class _NouveauPatientCliniquePageState extends State<NouveauPatientCliniquePage> {
  final _supa = Supabase.instance.client;
  // Propriétaire
  List<Map<String, dynamic>> _clients = [];
  Map<String, dynamic>? _clientExistant;
  final _nom = TextEditingController(), _prenom = TextEditingController(), _tel = TextEditingController(),
      _email = TextEditingController(), _adresse = TextEditingController(), _cp = TextEditingController(),
      _ville = TextEditingController();
  // Animal
  final _animalNom = TextEditingController(), _race = TextEditingController(), _ident = TextEditingController(),
      _poids = TextEditingController(), _couleur = TextEditingController();
  String _espece = 'chien';
  String? _sexe;
  DateTime? _naissance;
  bool _saving = false;
  /// Étape 1 franchie : puce vérifiée (aucune fiche) ou animal sans puce.
  bool _puceVerifiee = false;
  bool _verification = false;
  /// Fiche d'un autre pro à rattacher : on ne saisit que le client.
  String? _rattacherA;

  @override
  void initState() {
    super.initState();
    _chargerClients();
  }

  Future<void> _chargerClients() async {
    try {
      final rows = await _supa.from('clients_clinique').select()
          .eq('clinique_profile_id', widget.cliniqueProfileId).order('nom');
      if (mounted) setState(() => _clients = List<Map<String, dynamic>>.from(rows as List));
    } catch (_) {}
  }

  void _snack(String t, {Color? c}) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t, style: const TextStyle(fontFamily: 'Galey')), backgroundColor: c, behavior: SnackBarBehavior.floating));

  /// Une puce = une fiche : false si l'animal est déjà sur PetsMatch (le
  /// pro est alors orienté : déjà suivi, rattachement ou demande d'accès).
  Future<bool> _controlerPuce() async {
    if (_ident.text.trim().length >= 6) {
      try {
        final rows = await _supa.rpc('pm_puce_existante',
            params: {'p_identification': _ident.text.trim(), 'p_profile': widget.cliniqueProfileId});
        final liste = List<Map<String, dynamic>>.from(rows as List);
        if (liste.isNotEmpty && mounted) {
          final a = liste.first;
          final mot = widget.estClinique ? 'patients' : 'clients';
          if (a['deja_lie'] == true) {
            _snack('${a['nom'] ?? 'Cet animal'} est déjà dans vos $mot.', c: Colors.orange);
            return false;
          }
          if (a['detenteur'] == 'pro') {
            final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
              title: const Text('Fiche déjà créée', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              content: Text('${a['nom'] ?? 'Cet animal'} a déjà une fiche, créée par un autre professionnel pour son client. Rattachez-la à vos $mot : vous verrez son identité et ajouterez vos propres documents. Son carnet de santé et les documents de l’autre professionnel restent privés tant que le propriétaire ne les a pas partagés.',
                  style: const TextStyle(fontFamily: 'Galey')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
                ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Rattacher à mes $mot')),
              ],
            ));
            if (ok == true && mounted) setState(() => _rattacherA = a['animal_id'].toString());
            return false;
          }
          final demander = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
            title: const Text('Animal déjà sur PetsMatch', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            content: Text('Le n° ${_ident.text.trim()} correspond à ${a['nom'] ?? 'un animal'} déjà enregistré par son '
                '${a['detenteur'] == 'eleveur' ? 'éleveur' : 'propriétaire'}. '
                'Demandez plutôt l\'accès à son carnet de santé (le propriétaire valide).'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Demander l'accès")),
            ],
          ));
          if (demander == true && mounted) {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => AnimalAccesPage(
              animalId: a['animal_id'].toString(), ownerUid: a['owner_uid']?.toString() ?? '',
              categoryColor: _teal)));
          }
          return false;
        }
      } catch (_) {}
    }
    return true;
  }

  /// Anti-doublon. Renvoie false si l'utilisateur part sur une demande d'accès.
  Future<bool> _verifierDoublons() async {
    if (!await _controlerPuce()) return false;
    // 2. Propriétaire ayant un compte PetsMatch (nouveau client seulement)
    if (_clientExistant == null) {
      Map<String, dynamic>? u;
      try {
        if (_email.text.trim().isNotEmpty) u = await trouverUtilisateurParEmail(_email.text.trim());
        if (u == null && _tel.text.replaceAll(RegExp(r'[^0-9]'), '').length >= 9) {
          u = await trouverUtilisateurParTelephone(_tel.text.trim());
        }
      } catch (_) {}
      if (u != null && mounted) {
        final continuer = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
          title: const Text('Ce propriétaire a PetsMatch', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          content: Text('${u!['firstname'] ?? ''} ${u['lastname'] ?? ''} a un compte. Si son animal y est déjà, '
              'demandez l\'accès à son carnet (scan de la puce ou depuis un RDV) pour éviter un doublon. '
              'Sinon, créez la fiche : il pourra la rattacher à son compte.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Créer quand même')),
          ],
        ));
        if (continuer != true) return false;
      }
    }
    return true;
  }

  /// Fiche créée par un autre pro : rattachement « identité seule ».
  Future<void> _rattacher(String animalId) async {
    try {
      final id = await _supa.rpc('pm_rattacher_fiche_pro', params: {
        'p_profile': widget.cliniqueProfileId,
        'p_animal': animalId,
        'p_client_id': _clientExistant?['id'],
        'p_client': _clientExistant != null ? null : {
          'nom': _nom.text, 'prenom': _prenom.text, 'telephone': _tel.text, 'email': _email.text,
          'adresse': _adresse.text, 'code_postal': _cp.text, 'ville': _ville.text,
        },
      });
      if (mounted) Navigator.pop(context, id?.toString());
    } on PostgrestException catch (e) {
      _snack(e.code == 'P0001' ? e.message : 'Rattachement impossible : ${e.message}', c: Colors.red);
    }
  }

  Future<void> _enregistrer() async {
    if (_rattacherA != null) {
      if (_clientExistant == null && _nom.text.trim().isEmpty) {
        _snack('Nom du propriétaire obligatoire.', c: Colors.orange);
        return;
      }
      setState(() => _saving = true);
      await _rattacher(_rattacherA!);
      if (mounted) setState(() => _saving = false);
      return;
    }
    if (_animalNom.text.trim().isEmpty || (_clientExistant == null && _nom.text.trim().isEmpty)) {
      _snack('Nom du propriétaire et nom de l\'animal obligatoires.', c: Colors.orange);
      return;
    }
    setState(() => _saving = true);
    try {
      if (!await _verifierDoublons()) { setState(() => _saving = false); return; }
      final id = await _supa.rpc('pm_creer_patient_clinique', params: {
        'p_clinique': widget.cliniqueProfileId,
        'p_client_id': _clientExistant?['id'],
        'p_client': {
          'nom': _nom.text, 'prenom': _prenom.text, 'telephone': _tel.text, 'email': _email.text,
          'adresse': _adresse.text, 'code_postal': _cp.text, 'ville': _ville.text,
        },
        'p_animal': {
          'nom': _animalNom.text, 'espece': _espece, 'race': _race.text, 'sexe': _sexe ?? '',
          'date_naissance': _naissance == null ? '' : _naissance!.toIso8601String().substring(0, 10),
          'identification': _ident.text, 'poids': _poids.text, 'couleur': _couleur.text,
        },
      });
      if (mounted) Navigator.pop(context, id?.toString());
    } on PostgrestException catch (e) {
      _snack(e.code == 'P0001' || e.code == '23505' ? e.message : 'Création impossible : ${e.message}', c: Colors.red);
    } catch (e) {
      _snack('Création impossible : $e', c: Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _deco(String l) => InputDecoration(
    labelText: l, isDense: true, filled: true, fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
  );

  Widget _titre(String t) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Text(t, style: const TextStyle(fontFamily: 'Galey', fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E2025))),
  );

  /// Étape 1 : la puce d'abord — on vérifie que la fiche n'existe pas déjà.
  Future<void> _verifierPuceDabord() async {
    if (_ident.text.replaceAll(RegExp(r'[^0-9A-Za-z]'), '').length < 6) {
      _snack('Saisissez le n° de puce ou de tatouage (6 caractères au moins), ou indiquez que l’animal n’en a pas.', c: Colors.orange);
      return;
    }
    setState(() => _verification = true);
    final libre = await _controlerPuce();
    if (!mounted) return;
    setState(() { _verification = false; _puceVerifiee = libre || _rattacherA != null; });
    if (libre) _snack('Aucune fiche avec cette puce sur PetsMatch : complétez la fiche.');
  }

  Widget _etapePuce() => ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
        const Text('1. Puce ou tatouage', style: TextStyle(fontFamily: 'Galey', fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1F2A2E))),
        const SizedBox(height: 6),
        const Text('On vérifie d’abord que l’animal n’a pas déjà une fiche sur PetsMatch (une puce = un animal).',
            style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B))),
        const SizedBox(height: 14),
        TextField(controller: _ident, autofocus: true, decoration: _deco('N° de puce / tatouage'),
            onSubmitted: (_) => _verifierPuceDabord()),
        const SizedBox(height: 14),
        SizedBox(width: double.infinity, height: 50, child: ElevatedButton(
          onPressed: _verification ? null : _verifierPuceDabord,
          style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          child: _verification
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Vérifier la puce', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
        )),
        const SizedBox(height: 6),
        TextButton(
          onPressed: () => setState(() { _ident.clear(); _puceVerifiee = true; }),
          child: const Text('L’animal n’a pas de puce', style: TextStyle(fontFamily: 'Galey', color: _teal)),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
        title: Text(widget.titre ?? (widget.estClinique ? 'Nouveau patient' : 'Nouveau client'),
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: !_puceVerifiee ? _etapePuce() : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        Text(widget.estClinique
            ? 'Pour un animal dont le propriétaire n\'a pas PetsMatch. Il pourra rattacher la fiche à son compte plus tard.'
            : 'Pour un client qui n\'a pas PetsMatch : contrat, facture et demandes lui sont envoyés par e-mail, avec une invitation '
              'à créer son compte. Il pourra ensuite rattacher la fiche de son animal à son compte.',
            style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Color(0xFF6F767B))),
        _titre('Propriétaire'),
        if (_clients.isNotEmpty) ...[
          Autocomplete<Map<String, dynamic>>(
            displayStringForOption: (c) => '${c['prenom'] ?? ''} ${c['nom'] ?? ''}'.trim(),
            optionsBuilder: (v) {
              final q = v.text.trim().toLowerCase();
              return _clients.where((c) => q.isEmpty ||
                  '${c['prenom'] ?? ''} ${c['nom'] ?? ''} ${c['telephone'] ?? ''} ${c['email'] ?? ''}'.toLowerCase().contains(q)).take(20);
            },
            onSelected: (c) => setState(() => _clientExistant = c),
            fieldViewBuilder: (ctx, ctrl, focus, _) => TextField(controller: ctrl, focusNode: focus,
                decoration: _deco('Client déjà dans votre fichier (rechercher)').copyWith(prefixIcon: const Icon(Icons.search, size: 18))),
          ),
          const SizedBox(height: 8),
        ],
        if (_clientExistant != null)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            decoration: BoxDecoration(color: _teal.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _teal.withValues(alpha: 0.25))),
            child: Row(children: [
              const Icon(Icons.person_outline, color: _teal),
              const SizedBox(width: 10),
              Expanded(child: Text('${_clientExistant!['prenom'] ?? ''} ${_clientExistant!['nom'] ?? ''}\n'
                  '${[_clientExistant!['telephone'], _clientExistant!['email']].where((x) => (x ?? '').toString().isNotEmpty).join(' · ')}',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13))),
              TextButton(onPressed: () => setState(() => _clientExistant = null), child: const Text('Changer')),
            ]),
          )
        else ...[
          Row(children: [
            Expanded(child: TextField(controller: _nom, textCapitalization: TextCapitalization.words, decoration: _deco('Nom *'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _prenom, textCapitalization: TextCapitalization.words, decoration: _deco('Prénom'))),
          ]),
          const SizedBox(height: 8),
          TextField(controller: _tel, keyboardType: TextInputType.phone, decoration: _deco('Téléphone')),
          const SizedBox(height: 8),
          TextField(controller: _email, keyboardType: TextInputType.emailAddress,
              decoration: _deco('E-mail (envoi des ordonnances, rappels)')),
          const SizedBox(height: 8),
          TextField(controller: _adresse, decoration: _deco('Adresse')),
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(width: 110, child: TextField(controller: _cp, keyboardType: TextInputType.number, decoration: _deco('Code postal'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _ville, decoration: _deco('Ville'))),
          ]),
        ],
        if (_rattacherA != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _teal.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
            child: const Text('Fiche existante : l\u2019animal sera rattaché à votre fichier avec ce client. Son carnet de santé '
                'et les documents de l\u2019autre professionnel restent privés.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
          ),
        ] else ...[
        _titre('Animal'),
        TextField(controller: _animalNom, textCapitalization: TextCapitalization.words, decoration: _deco('Nom *')),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: DropdownButtonFormField<String>(
            initialValue: _espece, isExpanded: true, decoration: _deco('Espèce'),
            items: [for (final e in kEspecesPatient) DropdownMenuItem(value: e.$1, child: Text(e.$2))],
            onChanged: (v) => setState(() => _espece = v ?? _espece),
          )),
          const SizedBox(width: 8),
          Expanded(child: DropdownButtonFormField<String?>(
            initialValue: _sexe, isExpanded: true, decoration: _deco('Sexe'),
            items: const [
              DropdownMenuItem(value: null, child: Text('—')),
              DropdownMenuItem(value: 'male', child: Text('Mâle')),
              DropdownMenuItem(value: 'femelle', child: Text('Femelle')),
            ],
            onChanged: (v) => setState(() => _sexe = v),
          )),
        ]),
        const SizedBox(height: 8),
        TextField(controller: _race, decoration: _deco('Race')),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: () async {
              final d = await showDatePicker(context: context, initialDate: _naissance ?? DateTime.now(),
                  firstDate: DateTime(1990), lastDate: DateTime.now());
              if (d != null) setState(() => _naissance = d);
            },
            icon: const Icon(Icons.cake_outlined, size: 18),
            label: Text(_naissance == null ? 'Date de naissance'
                : '${_naissance!.day.toString().padLeft(2, '0')}/${_naissance!.month.toString().padLeft(2, '0')}/${_naissance!.year}'),
            style: OutlinedButton.styleFrom(foregroundColor: _teal, padding: const EdgeInsets.symmetric(vertical: 14)),
          )),
          const SizedBox(width: 8),
          SizedBox(width: 110, child: TextField(controller: _poids, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _deco('Poids (kg)'))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text(_ident.text.trim().isEmpty ? 'Sans puce ni tatouage' : 'Puce / tatouage : ${_ident.text.trim()} (vérifié)',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, color: Color(0xFF1F2A2E)))),
          TextButton(onPressed: () => setState(() { _puceVerifiee = false; _rattacherA = null; }), child: const Text('Modifier')),
        ]),
        const SizedBox(height: 8),
        TextField(controller: _couleur, decoration: _deco('Robe / couleur')),
        ],
        const SizedBox(height: 22),
        SizedBox(width: double.infinity, height: 50, child: ElevatedButton(
          onPressed: _saving ? null : _enregistrer,
          style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          child: _saving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text(_rattacherA != null
                  ? (widget.estClinique ? 'Rattacher à mes patients' : 'Rattacher à mes clients')
                  : (widget.estClinique ? 'Créer le patient' : 'Créer le client'),
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
        )),
      ]),
    );
  }
}
