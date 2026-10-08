// Clinique — nouveau patient dont le propriétaire n'a pas (forcément)
// PetsMatch : client du fichier de la clinique (clients_clinique) + fiche
// animal, via pm_creer_patient_clinique (migration_patients_clinique.sql).
// Anti-doublon : n° de puce (pm_patient_existant → demande d'accès au carnet)
// et compte PetsMatch (e-mail / téléphone). Miroir site :
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
  const NouveauPatientCliniquePage({super.key, required this.cliniqueProfileId});

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

  /// Anti-doublon. Renvoie false si l'utilisateur part sur une demande d'accès.
  Future<bool> _verifierDoublons() async {
    // 1. Animal déjà sur PetsMatch (puce / tatouage)
    if (_ident.text.trim().length >= 6) {
      try {
        final rows = await _supa.rpc('pm_patient_existant',
            params: {'p_clinique': widget.cliniqueProfileId, 'p_identification': _ident.text.trim()});
        final liste = List<Map<String, dynamic>>.from(rows as List);
        if (liste.isNotEmpty && mounted) {
          final a = liste.first;
          if (a['deja_patient'] == true) {
            _snack('${a['nom'] ?? 'Cet animal'} est déjà dans vos patients.', c: Colors.orange);
            return false;
          }
          final demander = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
            title: const Text('Animal déjà sur PetsMatch', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            content: Text('Le n° ${_ident.text.trim()} correspond à ${a['nom'] ?? 'un animal'} déjà enregistré par son propriétaire. '
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

  Future<void> _enregistrer() async {
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
      _snack(e.code == 'P0001' ? e.message : 'Création impossible : ${e.message}', c: Colors.red);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
        title: const Text('Nouveau patient', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        const Text('Pour un animal dont le propriétaire n\'a pas PetsMatch. Il pourra rattacher la fiche à son compte plus tard.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Color(0xFF6F767B))),
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
        TextField(controller: _ident, decoration: _deco('N° de puce / tatouage (vérifié sur PetsMatch)')),
        const SizedBox(height: 8),
        TextField(controller: _couleur, decoration: _deco('Robe / couleur')),
        const SizedBox(height: 22),
        SizedBox(width: double.infinity, height: 50, child: ElevatedButton(
          onPressed: _saving ? null : _enregistrer,
          style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          child: _saving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Créer le patient', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
        )),
      ]),
    );
  }
}
