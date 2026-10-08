import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/utils/document_prive.dart';
import 'package:PetsMatch/utils/storage_helper.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/contexte_pro.dart';
import 'package:PetsMatch/pages/pro/ordonnance_pdf.dart';
import 'package:PetsMatch/pages/eleveur/admin/facturation.dart' show CreerFacturePage, FacturePrefillLigne;
import 'package:PetsMatch/pages/pro/transmission_document.dart';
import 'package:http/http.dart' as http;

/// S06 — Pro : écrire un compte rendu et/ou créer une ordonnance après un RDV.
/// Vétérinaire : le CR saisit aussi les vaccins réalisés et les traitements
/// prescrits → inscrits au carnet de santé (vaccinations / traitements, rappels
/// au propriétaire par les Cloud Functions sante.js) + ordonnance PDF générée
/// et rangée dans les documents de l'animal (ordonnances).
/// Peut être ouvert avec un RDV précis (`rdv`) ou directement depuis la fiche
/// animal (`animalId` + `ownerUid`).
class CompteRenduPage extends StatefulWidget {
  final Map<String, dynamic>? rdv;
  final String? animalId;
  final String? ownerUid;
  final String clientName;
  final Color categoryColor;
  final bool isPension;

  const CompteRenduPage({
    super.key,
    this.rdv,
    this.animalId,
    this.ownerUid,
    this.clientName = '',
    required this.categoryColor,
    this.isPension = false,
  });

  @override
  State<CompteRenduPage> createState() => _CompteRenduPageState();
}

class _CompteRenduPageState extends State<CompteRenduPage>
    with SingleTickerProviderStateMixin {
  final _supa = Supabase.instance.client;
  late TabController _tabCtrl;

  // Compte rendu
  final _crContenuCtrl = TextEditingController();
  File? _crFile;
  bool _crSaving = false;

  // Vétérinaire : actes saisis dans le CR (carnet de santé + ordonnance).
  final List<_VaccinCr> _vaccinsCr = [];
  // Consultation structurée : motif, poids du jour, actes réalisés
  // (historique du patient : date · motif · poids · actes · prescription).
  late final _motifCtrl = TextEditingController(text: widget.rdv?['motif']?.toString() ?? '');
  final _poidsCtrl = TextEditingController();
  final Set<String> _actesRealises = {};
  final _autreActeCtrl = TextEditingController();
  static const _actesCourants = ['Examen clinique', 'Vaccination', 'Prise de sang', 'Analyse sanguine', 'Radiographie',
      'Échographie', "Analyse d'urine", 'Coproscopie', 'Injection', 'Soins de plaie', 'Détartrage', 'Pose de puce',
      'Castration / stérilisation', 'Chirurgie', 'Hospitalisation', 'Euthanasie'];
  double? get _poidsSaisi => double.tryParse(_poidsCtrl.text.trim().replaceAll(',', '.'));
  final List<_TraitementCr> _traitementsCr = [];
  bool get _saisieActes => !widget.isPension && _peutValider;

  // Ordonnance
  final _ordoNotesCtrl = TextEditingController();
  File? _ordoFile;
  bool _ordoSaving = false;

  // Existing docs
  List<Map<String, dynamic>> _crs    = [];
  List<Map<String, dynamic>> _ordos  = [];
  bool _loadingDocs = true;
  String? _proProfileId;

  // Équipe vétérinaire : un ASV rédige des brouillons, un vétérinaire valide
  // (contrôlé aussi en base). Titulaire : tous les droits.
  bool _peutValider = true;
  bool _peutOrdonnances = true;

  /// Profil du compte pro concerné : celui du RDV, sinon le contexte
  /// (profil actif, ou clinique pour un employé) — jamais `is_main`
  /// (multi-profil : un véto peut avoir un profil élevage principal).
  String? get _profilPro {
    final r = widget.rdv?['pro_profile_id']?.toString();
    if (r != null && r.isNotEmpty) return r;
    final c = AgendaContexte.profileId;
    return c.isNotEmpty ? c : null;
  }

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: widget.isPension ? 1 : 2, vsync: this);
    _proProfileId = _profilPro;
    _chargerDroits();
    _loadExisting();
    _chargerPharmacie();
    _prefillDepuisRdv();
  }

  /// Message laissé par le client dans sa demande de RDV (symptômes…).
  String _messageClient = '';
  Map<String, dynamic>? _rdvSource;

  /// Accès au carnet de l'animal pour la clinique (RDV pris avant le partage
  /// à la réservation) — sinon vaccins / traitements du CR sont refusés.
  Future<void> _assurerAcces(String? animalId, String? ownerProfileId) async {
    final pro = _profilPro;
    if (animalId == null || pro == null || ownerProfileId == null || ownerProfileId.isEmpty) return;
    try {
      final ex = await _supa.from('animal_access').select('statut')
          .eq('animal_id', animalId).eq('pro_profile_id', pro).maybeSingle();
      if (ex != null) return;
      await _supa.from('animal_access').insert({
        'animal_id': animalId, 'pro_profile_id': pro, 'granted_by_profile_id': ownerProfileId,
        'permissions': ['read_basic', 'read_health', 'write_health'],
        'statut': 'active', 'granted_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
  }

  /// Motif + message du client : depuis le RDV ouvert, sinon le dernier RDV
  /// de cet animal avec la clinique (CR ouvert depuis la fiche patient).
  Future<void> _prefillDepuisRdv() async {
    Map<String, dynamic>? r = widget.rdv;
    final animalId = (widget.animalId ?? widget.rdv?['animal_id'])?.toString();
    if (r == null && animalId != null && _profilPro != null) {
      try {
        r = await _supa.from('rdv').select('id, motif, notes_client, client_uid, client_profile_id, client_nom_manuel, client_email_manuel, client_telephone_manuel')
            .eq('animal_id', animalId).eq('pro_profile_id', _profilPro!)
            .inFilter('statut', ['confirme', 'termine'])
            .lte('date_heure', DateTime.now().add(const Duration(hours: 12)).toUtc().toIso8601String())
            .order('date_heure', ascending: false).limit(1).maybeSingle();
      } catch (_) {}
    }
    if (r == null || !mounted) return;
    await _assurerAcces(animalId, r['client_profile_id']?.toString());
    if (!mounted) return;
    setState(() {
      _rdvSource = r;
      if (_motifCtrl.text.trim().isEmpty) _motifCtrl.text = (r!['motif'] ?? '').toString();
      _messageClient = (r!['notes_client'] ?? '').toString().trim();
    });
  }

  Future<void> _chargerDroits() async {
    final v = await AgendaContexte.peut('vet_cr_valider');
    final o = await AgendaContexte.peut('vet_ordonnances');
    if (mounted) setState(() { _peutValider = v; _peutOrdonnances = o; });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _crContenuCtrl.dispose();
    _ordoNotesCtrl.dispose();
    super.dispose();
  }

  Future<void> _deleteDoc(String table, String id) async {
    final label = table == 'comptes_rendus' ? 'ce compte rendu' : 'cette ordonnance';
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Supprimer $label ?',
          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      content: const Text('Cette action est irréversible.',
          style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey'))),
        TextButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer',
                style: TextStyle(fontFamily: 'Galey', color: Colors.red, fontWeight: FontWeight.w700))),
      ],
    ));
    if (ok != true) return;
    try {
      await _supa.from(table).delete().eq('id', id);
      await _loadExisting();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
              backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _pickCrFile() async {
    final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
    if (result != null && result.files.single.path != null) {
      setState(() => _crFile = File(result.files.single.path!));
    }
  }

  Future<void> _pickOrdoFile() async {
    final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
    if (result != null && result.files.single.path != null) {
      setState(() => _ordoFile = File(result.files.single.path!));
    }
  }

  Future<void> _loadExisting() async {
    final rdvId    = widget.rdv?['id']?.toString();
    final animalId = widget.animalId ?? widget.rdv?['animal_id']?.toString();
    if (rdvId == null && animalId == null) {
      setState(() => _loadingDocs = false);
      return;
    }
    try {
      List crs, ordos;
      final vetUid = AgendaContexte.uid ?? '';
      final aid = animalId ?? '';
      final proFilter  = _proProfileId != null ? 'pro_profile_id' : 'pro_uid';
      final proValue   = _proProfileId ?? vetUid;
      if (rdvId != null) {
        crs   = await _supa.from('comptes_rendus').select().eq('rdv_id', rdvId).order('created_at');
        ordos = await _supa.from('ordonnances').select()
            .eq('animal_id', aid).eq(proFilter, proValue)
            .order('date_emit', ascending: false);
      } else {
        crs   = await _supa.from('comptes_rendus').select()
            .eq('animal_id', aid).eq(proFilter, proValue).order('created_at');
        ordos = await _supa.from('ordonnances').select()
            .eq('animal_id', aid).eq(proFilter, proValue).order('created_at');
      }
      if (mounted) {
        setState(() {
          _crs       = List<Map<String, dynamic>>.from(crs);
          _ordos     = List<Map<String, dynamic>>.from(ordos);
          _loadingDocs = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingDocs = false);
    }
  }

  Future<void> _saveCompteRendu() async {
    final proUid  = AgendaContexte.uid;
    final moi     = AgendaContexte.moi;
    final actes = _saisieActes && (_vaccinsCr.isNotEmpty || _traitementsCr.isNotEmpty);
    // Instantané pour la facture proposée après l'enregistrement.
    final factVaccins = List<_VaccinCr>.of(_vaccinsCr);
    final factTraitements = List<_TraitementCr>.of(_traitementsCr);
    final factActes = _actesRealises.toList();
    final motif = _saisieActes ? _motifCtrl.text.trim() : '';
    final poids = _saisieActes ? _poidsSaisi : null;
    final actesRealises = _saisieActes ? _actesRealises.toList() : const <String>[];
    final prescription = _saisieActes ? _traitementsCr.map((t) => '${t.nom} — ${t.posologieComplete}').join(' ; ') : '';
    final contenu = [
      if (motif.isNotEmpty) 'Motif : $motif',
      if (poids != null) 'Poids : ${_fmtPoids(poids)} kg',
      if (actesRealises.isNotEmpty) 'Actes réalisés : ${actesRealises.join(', ')}.',
      _crContenuCtrl.text.trim(),
      if (actes && _vaccinsCr.isNotEmpty)
        'Vaccins : ${_vaccinsCr.map((v) => v.nom + (v.lot.isNotEmpty ? ' (lot ${v.lot})' : '')).join(', ')}.',
      if (actes && _traitementsCr.isNotEmpty)
        'Traitement : ${_traitementsCr.map((t) => '${t.nom} — ${t.posologieComplete}').join(' ; ')}.',
    ].where((l) => l.isNotEmpty).join('\n\n');
    if (proUid == null || contenu.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Le contenu du compte rendu est obligatoire.',
            style: TextStyle(fontFamily: 'Galey')),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _crSaving = true);
    final rdvId    = widget.rdv?['id'];
    final animalId = widget.animalId ?? widget.rdv?['animal_id'];
    try {
      final owner = await _resolveOwner();
      final proProfileId = _profilPro;
      final monProfil = await AgendaContexte.monProfil();
      final statut = _peutValider ? 'valide' : 'brouillon';
      String? docUrl;
      if (_crFile != null) {
        final name = '${DateTime.now().millisecondsSinceEpoch}.${_crFile!.path.split('.').last}';
        // Dossier de l'auteur (règles de stockage) ; la lecture passe par
        // la référence du CR (lien-document), pas par le dossier.
        docUrl = await uploadDocument(_crFile!, 'comptes_rendus/${moi ?? proUid}/$name');
      }
      await _insertRecord('comptes_rendus', {
        'pro_uid'   : proUid,
        'animal_id' : animalId,
        if (owner.uid != null) 'owner_uid': owner.uid,
        if (rdvId != null) 'rdv_id': rdvId,
        'contenu'   : contenu,
        if (docUrl != null) 'doc_url': docUrl,
      }, {
        if (proProfileId != null && proProfileId.isNotEmpty) 'pro_profile_id': proProfileId,
        if (owner.profileId != null) 'owner_profile_id': owner.profileId,
        'statut': statut,
        if (moi != null) 'redige_par_uid': moi,
        if (monProfil != null) 'redige_par_profile_id': monProfil,
        if (statut == 'valide' && monProfil != null) 'valide_par_profile_id': monProfil,
        if (motif.isNotEmpty) 'motif': motif,
        if (poids != null) 'poids': poids,
        if (actesRealises.isNotEmpty) 'actes': actesRealises,
        if (prescription.isNotEmpty) 'prescription': prescription,
      });
      // Pesée du jour → courbe de poids + poids de la fiche.
      if (poids != null && animalId != null) {
        try {
          await _supa.from('poids').insert({
            'id': DateTime.now().microsecondsSinceEpoch.toString(),
            'animal_id': animalId, 'valeur': poids,
            'date': DateTime.now().toIso8601String(), 'notes': 'Consultation',
          });
          await _supa.from('animaux').update({'poids': _fmtPoids(poids)}).eq('id', animalId);
        } catch (_) {}
      }
      if (statut == 'valide') {
        await _notifyOwner(isOrdo: false);
      } else {
        await _notifyValideurs();
      }
      if (actes && animalId != null) await _ecrireActes(animalId.toString(), rdvId?.toString(), owner);
      final poidsFacture = _poidsSaisi;
      final motifFacture = _motifCtrl.text.trim();
      _crContenuCtrl.clear();
      _poidsCtrl.clear();
      setState(() { _crFile = null; _vaccinsCr.clear(); _traitementsCr.clear(); _actesRealises.clear(); });
      await _loadExisting();
      // Le vétérinaire choisit de préparer (ou non) la facture de la consultation.
      if (mounted && _saisieActes && statut == 'valide' && animalId != null) {
        await _proposerFacture(animalId: animalId.toString(), rdvId: rdvId?.toString(), owner: owner,
            motif: motifFacture, poids: poidsFacture, actesRealises: factActes,
            vaccins: factVaccins, traitements: factTraitements);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(statut == 'valide'
              ? 'Compte rendu enregistré.'
              : 'Brouillon enregistré — un vétérinaire doit le valider avant envoi au propriétaire.',
              style: const TextStyle(fontFamily: 'Galey')),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _crSaving = false);
    }
  }

  /// Vaccins / traitements du CR → carnet de santé ; traitements →
  /// ordonnance PDF (si droit de prescrire) dans les documents de l'animal.
  Future<void> _ecrireActes(String animalId, String? rdvId, ({String? uid, String? profileId}) owner) async {
    final erreurs = <String>[];
    final vetId = AgendaContexte.moi ?? AgendaContexte.uid;
    final today = DateTime.now();
    String ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final praticien = '${User_Info.firstname} ${User_Info.lastname}'.replaceAll('none', '').trim();

    for (final v in _vaccinsCr) {
      try {
        await _supa.from('vaccinations').insert({
          'id': DateTime.now().microsecondsSinceEpoch.toString(),
          'animal_id': animalId,
          'vaccin': v.nom, 'lot': v.lot,
          'veterinaire': praticien,
          'date': ymd(v.date),
          'date_validite_debut': ymd(v.date),
          if (v.rappel != null) 'date_rappel': ymd(v.rappel!),
          'source': 'veterinaire',
          if (vetId != null) 'vet_id': vetId,
        });
      } catch (e) { erreurs.add('vaccin ${v.nom}'); }
    }
    for (final t in _traitementsCr) {
      var debut = DateTime(today.year, today.month, today.day, today.hour, today.minute);
      for (var i = 0; i < t.phases.length; i++) {
        final ph = t.phases[i];
        final fin = ph.dureeJours != null ? debut.add(Duration(days: ph.dureeJours!)) : null;
        final heures = [for (final k in ph.prises) _kPrises[k]!.$2]..sort();
        final rappel = t.rappels && heures.isNotEmpty;
        try {
          await _supa.from('traitements').insert({
            'id': '${DateTime.now().microsecondsSinceEpoch}$i',
            'animal_id': animalId,
            'type': t.type, 'nom': t.nom, 'posologie': ph.libelle,
            'date': debut.toIso8601String(),
            if (fin != null) 'date_fin': fin.toIso8601String(),
            if (t.notes.isNotEmpty || t.phases.length > 1)
              'notes': [if (t.phases.length > 1) 'Phase ${i + 1}/${t.phases.length}', if (t.notes.isNotEmpty) t.notes].join(' — '),
            'source': 'veterinaire',
            if (vetId != null) 'vet_id': vetId,
            'rappel_actif': rappel,
            if (rappel) ...{
              'rappel_frequence_jours': ph.frequenceJours,
              'rappel_duree_jours': ph.dureeJours ?? 30,
              'rappel_fin': (fin ?? debut.add(const Duration(days: 30))).toIso8601String(),
              'rappel_heures': heures,
            },
          });
        } catch (e) { erreurs.add('traitement ${t.nom}'); }
        if (fin == null) break;
        debut = fin;
      }
    }

    if (_traitementsCr.isNotEmpty && _peutOrdonnances) {
      try {
        final pro = _profilPro;
        final clinique = pro == null ? null : await _supa.from('user_profiles_complet')
            .select('nom, rue_pro, code_postal_pro, ville_pro, phone_number, certifications').eq('id', pro).maybeSingle();
        final animal = await _supa.from('animaux')
            .select('nom, espece, race, identification, poids').eq('id', animalId).maybeSingle();
        String proprio = widget.clientName;
        if (owner.profileId != null) {
          final o = await _supa.from('user_profiles_complet')
              .select('firstname, lastname, nom').eq('id', owner.profileId!).maybeSingle();
          final n = '${o?['firstname'] ?? ''} ${o?['lastname'] ?? ''}'.trim();
          if (n.isNotEmpty) proprio = n;
        }
        var ordre = '';
        if (clinique?['certifications'] is List) {
          for (final c in clinique!['certifications'] as List) {
            if (c is Map && (c['nom'] ?? '').toString().toLowerCase().contains('ordre')) { ordre = (c['numero'] ?? '').toString(); break; }
          }
        }
        final adresse = [clinique?['rue_pro'], '${clinique?['code_postal_pro'] ?? ''} ${clinique?['ville_pro'] ?? ''}'.trim()]
            .where((x) => (x?.toString() ?? '').trim().isNotEmpty).join(', ');
        final bytes = await ordonnancePdfBytes(
          cliniqueNom: (clinique?['nom'] as String?)?.trim().isNotEmpty == true ? clinique!['nom'] as String : 'Cabinet vétérinaire',
          cliniqueAdresse: adresse,
          cliniqueTel: (clinique?['phone_number'] ?? '').toString(),
          numeroOrdre: ordre,
          prescripteur: praticien.isEmpty ? 'Vétérinaire' : praticien,
          animalNom: (animal?['nom'] ?? widget.rdv?['_animal_nom'] ?? 'Animal').toString(),
          animalEspeceRace: [animal?['espece'], animal?['race']].where((x) => (x?.toString() ?? '').isNotEmpty).join(' · '),
          animalIdentification: (animal?['identification'] ?? '').toString(),
          animalPoids: _poidsSaisi != null ? '${_fmtPoids(_poidsSaisi!)} kg'
              : animal?['poids'] != null ? '${animal!['poids']} kg' : '',
          proprietaire: proprio,
          lignes: [for (final t in _traitementsCr)
            LigneOrdonnance(medicament: t.nom, posologie: t.posologieComplete, notes: t.notes)],
        );
        final moi = AgendaContexte.moi ?? AgendaContexte.uid;
        final docUrl = await uploadDocumentBytes(bytes, 'ordonnances/$moi/${DateTime.now().millisecondsSinceEpoch}.pdf');
        final monProfil = await AgendaContexte.monProfil();
        await _insertRecord('ordonnances', {
          'pro_uid': AgendaContexte.uid,
          'animal_id': animalId,
          if (owner.uid != null) 'owner_uid': owner.uid,
          if (rdvId != null) 'rdv_id': rdvId,
          'doc_url': docUrl,
          'date_emit': ymd(today),
          'notes': _traitementsCr.map((t) => t.nom).join(', '),
        }, {
          if (pro != null && pro.isNotEmpty) 'pro_profile_id': pro,
          if (owner.profileId != null) 'owner_profile_id': owner.profileId,
          if (AgendaContexte.moi != null) 'praticien_uid': AgendaContexte.moi,
          if (monProfil != null) 'praticien_profile_id': monProfil,
        });
        await _notifyOwner(isOrdo: true);
      } catch (e) { erreurs.add('ordonnance'); }
    }
    if (erreurs.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Non enregistré : ${erreurs.join(', ')} — vérifiez l'accès au carnet de l'animal.",
            style: const TextStyle(fontFamily: 'Galey')),
        backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating,
      ));
    }
  }

  // ── Saisie des actes (feuilles) ───────────────────────────────────────────

  static const _vaccinsCourants = ['CHPPiL', 'Rage', 'Leptospirose', 'Toux du chenil', 'Leishmaniose',
      'Typhus / coryza (RC P)', 'Leucose (FeLV)', 'Myxomatose', 'VHD (lapin)', 'Grippe équine', 'Rhinopneumonie', 'Tétanos'];

  /// Pharmacie de la clinique (inventaire_items) — autocomplétion des
  /// vaccins / médicaments, n° de lot repris de l'article.
  List<Map<String, dynamic>> _pharmacie = [];

  Future<void> _chargerPharmacie() async {
    final pro = _profilPro;
    if (pro == null || widget.isPension) return;
    try {
      final rows = await _supa.from('inventaire_items')
          .select('id, nom, categorie, lot, unite, quantite, prix_vente').eq('eleveur_profile_id', pro).order('nom');
      if (mounted) setState(() => _pharmacie = List<Map<String, dynamic>>.from(rows as List));
    } catch (_) {}
  }

  /// Champ avec suggestions de la pharmacie dès la 1re lettre ; saisie libre
  /// possible. [onChoix] reçoit l'article choisi (nom, lot…).
  Widget _champPharmacie({
    required TextEditingController ctrl,
    required FocusNode focus,
    required String label,
    required bool Function(Map<String, dynamic>) filtre,
    required void Function(Map<String, dynamic>) onChoix,
    VoidCallback? onChange,
    List<String> courants = const [],
  }) {
    return RawAutocomplete<Map<String, dynamic>>(
      textEditingController: ctrl,
      focusNode: focus,
      displayStringForOption: (o) => o['nom']?.toString() ?? '',
      // Liste déroulante avec recherche : pharmacie d'abord, puis la liste
      // courante (vaccins) — tout s'affiche au focus, filtré à la frappe.
      optionsBuilder: (v) {
        final q = v.text.trim().toLowerCase();
        bool ok(String n) => q.isEmpty || n.toLowerCase().contains(q);
        final stock = _pharmacie.where((o) => filtre(o) && ok(o['nom']?.toString() ?? '')).toList();
        final noms = {for (final o in stock) (o['nom']?.toString() ?? '').toLowerCase()};
        return [
          ...stock,
          for (final c in courants) if (ok(c) && !noms.contains(c.toLowerCase())) {'nom': c, 'categorie': '_courant'},
        ].take(40);
      },
      onSelected: onChoix,
      fieldViewBuilder: (ctx, c, focus, onSubmit) => TextField(
        controller: c, focusNode: focus, onChanged: (_) => onChange?.call(),
        textCapitalization: TextCapitalization.sentences,
        decoration: _inputDeco(label).copyWith(labelText: label,
            suffixIcon: _pharmacie.isEmpty ? null : const Icon(Icons.inventory_2_outlined, size: 18)),
      ),
      optionsViewBuilder: (ctx, onSelect, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4, borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 360),
            child: ListView(padding: EdgeInsets.zero, shrinkWrap: true, children: [
              if (_pharmacie.where(filtre).isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(14, 10, 14, 6),
                  child: Text('Pharmacie vide — ajoutez vos produits dans Inventaire pour les retrouver ici (lot, stock).',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey)),
                ),
              for (final o in options) ListTile(
                dense: true,
                leading: Icon(o['categorie'] == 'vaccin' ? Icons.vaccines_outlined : Icons.medication_outlined,
                    size: 18, color: widget.categoryColor),
                title: Text(o['nom']?.toString() ?? '', style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5)),
                subtitle: o['categorie'] == '_courant' ? null : Text([
                  'Pharmacie',
                  if ((o['lot'] ?? '').toString().isNotEmpty) 'Lot ${o['lot']}',
                  if (o['quantite'] != null) 'Stock ${o['quantite']} ${o['unite'] ?? ''}'.trim(),
                ].join(' · '), style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5)),
                onTap: () => onSelect(o),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// Ajout (ou modification si [existant]) d'un vaccin réalisé.
  Future<void> _ajouterVaccin([_VaccinCr? existant]) async {
    final nomCtrl = TextEditingController(text: existant?.nom ?? '');
    final lotCtrl = TextEditingController(text: existant?.lot ?? '');
    final nomFocus = FocusNode();
    final date = existant?.date ?? DateTime.now();
    DateTime? rappel = existant == null ? DateTime(date.year + 1, date.month, date.day) : existant.rappel;
    final res = await showModalBottomSheet<_VaccinCr>(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setM) {
        Widget chipRappel(String l, DateTime? d) => ChoiceChip(
          label: Text(l, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
          selected: d == null ? rappel == null : (rappel != null && rappel!.difference(d).inDays.abs() < 1),
          selectedColor: widget.categoryColor.withValues(alpha: 0.18), onSelected: (_) => setM(() => rappel = d));
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(existant == null ? '💉 Vaccin réalisé' : '💉 Modifier le vaccin',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            _champPharmacie(
              ctrl: nomCtrl, focus: nomFocus, label: 'Vaccin (nom / marque) *',
              filtre: (o) => o['categorie'] == 'vaccin',
              onChoix: (o) => setM(() { nomCtrl.text = o['nom']?.toString() ?? ''; if ((o['lot'] ?? '').toString().isNotEmpty) lotCtrl.text = o['lot'].toString(); }),
              onChange: () => setM(() {}),
              courants: _vaccinsCourants,
            ),
            const SizedBox(height: 10),
            TextField(controller: lotCtrl, decoration: _inputDeco('N° de lot').copyWith(labelText: 'N° de lot')),
            const SizedBox(height: 12),
            const Text('Prochain rappel (le propriétaire sera prévenu)', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              chipRappel('3 semaines', date.add(const Duration(days: 21))),
              chipRappel('1 mois', DateTime(date.year, date.month + 1, date.day)),
              chipRappel('6 mois', DateTime(date.year, date.month + 6, date.day)),
              chipRappel('1 an', DateTime(date.year + 1, date.month, date.day)),
              chipRappel('3 ans', DateTime(date.year + 3, date.month, date.day)),
              chipRappel('Aucun', null),
            ]),
            const SizedBox(height: 18),
            SizedBox(width: double.infinity, child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: widget.categoryColor, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: nomCtrl.text.trim().isEmpty ? null
                  : () => Navigator.pop(ctx, _VaccinCr(nomCtrl.text.trim(), lotCtrl.text.trim(), date, rappel)),
              child: Text(existant == null ? 'Ajouter' : 'Enregistrer', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            )),
          ])),
        );
      }),
    );
    if (res == null) return;
    setState(() {
      final i = existant == null ? -1 : _vaccinsCr.indexOf(existant);
      if (i >= 0) { _vaccinsCr[i] = res; } else { _vaccinsCr.add(res); }
    });
  }

  /// Ajout (ou modification si [existant]) d'un traitement : une ou plusieurs
  /// phases (traitement dégressif), prises matin / midi / soir, rythme.
  Future<void> _ajouterTraitement([_TraitementCr? existant]) async {
    final nomCtrl = TextEditingController(text: existant?.nom ?? '');
    final notesCtrl = TextEditingController(text: existant?.notes ?? '');
    final nomFocus = FocusNode();
    var type = existant?.type ?? 'medicament';
    var rappels = existant?.rappels ?? true;
    final phases = <_PhaseEdit>[
      for (final p in existant?.phases ?? [const _PhaseCr(dose: '1 cp', prises: {'matin', 'soir'}, frequenceJours: 1, dureeJours: 7)])
        _PhaseEdit.de(p),
    ];
    final res = await showModalBottomSheet<_TraitementCr>(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setM) {
        ChoiceChip chip(String l, bool sel, VoidCallback onTap) => ChoiceChip(
          label: Text(l, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)), selected: sel,
          selectedColor: widget.categoryColor.withValues(alpha: 0.18), onSelected: (_) => onTap());
        Widget phase(int i) {
          final p = phases[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            decoration: BoxDecoration(color: const Color(0xFFF6F8F7), borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE4E7E2))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(phases.length > 1 ? 'Phase ${i + 1}' : 'Posologie',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700))),
                if (phases.length > 1) IconButton(
                  visualDensity: VisualDensity.compact, icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setM(() => phases.removeAt(i))),
              ]),
              TextField(controller: p.dose, decoration: _inputDeco('ex. 1 cp, ½ cp, 2 mL, 1 pipette').copyWith(labelText: 'Dose par prise')),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final pr in _kPrises.entries) FilterChip(
                  label: Text(pr.value.$1, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                  selected: p.prises.contains(pr.key), selectedColor: widget.categoryColor.withValues(alpha: 0.18),
                  onSelected: (v) => setM(() => v ? p.prises.add(pr.key) : p.prises.remove(pr.key))),
              ]),
              const SizedBox(height: 8),
              // Intervalle libre : une prise tous les N jours.
              Row(children: [
                const Text('Tous les', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
                const SizedBox(width: 8),
                SizedBox(width: 70, child: TextField(
                  controller: p.frequenceCtrl, keyboardType: TextInputType.number, textAlign: TextAlign.center,
                  decoration: _inputDeco('1').copyWith(contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8)),
                  onChanged: (_) => setM(() {}),
                )),
                const SizedBox(width: 8),
                Text((int.tryParse(p.frequenceCtrl.text) ?? 1) > 1 ? 'jours' : 'jour (tous les jours)',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                SizedBox(width: 120, child: TextField(
                  controller: p.duree, keyboardType: TextInputType.number,
                  decoration: _inputDeco('jours').copyWith(labelText: 'Durée (jours)'),
                  onChanged: (_) => setM(() {}),
                )),
                const SizedBox(width: 8),
                Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final d in [3, 5, 7, 10, 14]) chip('$d j', p.duree.text == '$d', () => setM(() => p.duree.text = '$d')),
                ])),
              ]),
              if (i == phases.length - 1)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: TextButton(
                    onPressed: () => setM(() => p.duree.text = ''),
                    child: Text(p.duree.text.isEmpty ? '✓ Au long cours' : 'Au long cours (sans fin)',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: widget.categoryColor)),
                  ),
                ),
            ]),
          );
        }
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(existant == null ? '💊 Traitement prescrit' : '💊 Modifier le traitement',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            _champPharmacie(
              ctrl: nomCtrl, focus: nomFocus, label: 'Médicament *',
              filtre: (o) => type == 'antiparasitaire' ? o['categorie'] == 'antiparasitaire'
                  : (o['categorie'] != 'vaccin' && o['categorie'] != 'alimentation'),
              courants: type == 'antiparasitaire' ? _antiparasitairesCourants : _medicamentsCourants,
              onChoix: (o) => setM(() {
                nomCtrl.text = o['nom']?.toString() ?? '';
                if (o['categorie'] == 'antiparasitaire') type = 'antiparasitaire';
              }),
              onChange: () => setM(() {}),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              chip('Médicament', type == 'medicament', () => setM(() => type = 'medicament')),
              chip('Antiparasitaire', type == 'antiparasitaire', () => setM(() => type = 'antiparasitaire')),
              chip('Autre', type == 'autre', () => setM(() => type = 'autre')),
            ]),
            const SizedBox(height: 12),
            for (var i = 0; i < phases.length; i++) phase(i),
            OutlinedButton.icon(
              onPressed: () => setM(() {
                final der = phases.last;
                phases.add(_PhaseEdit.de(_PhaseCr(dose: '', prises: {...der.prises}, frequenceJours: der.frequence,
                    dureeJours: int.tryParse(der.duree.text))));
                if (der.duree.text.isEmpty) der.duree.text = '3';
              }),
              icon: const Icon(Icons.trending_down, size: 18),
              label: const Text('Ajouter une phase (dose dégressive)', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5)),
              style: OutlinedButton.styleFrom(foregroundColor: widget.categoryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero, value: rappels, activeThumbColor: widget.categoryColor,
              onChanged: (v) => setM(() => rappels = v),
              title: const Text('Rappeler chaque prise au propriétaire', style: TextStyle(fontFamily: 'Galey', fontSize: 13.5, fontWeight: FontWeight.w600)),
              subtitle: const Text('Matin 8 h · midi 12 h · soir 19 h, jusqu\'à la fin du traitement.', style: TextStyle(fontFamily: 'Galey', fontSize: 11.5)),
            ),
            TextField(controller: notesCtrl, decoration: _inputDeco('Précautions, à jeun, pendant le repas…').copyWith(labelText: 'Remarque (facultatif)')),
            const SizedBox(height: 18),
            SizedBox(width: double.infinity, child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: widget.categoryColor, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: nomCtrl.text.trim().isEmpty || phases.any((p) => p.prises.isEmpty) ? null : () => Navigator.pop(ctx, _TraitementCr(
                nom: nomCtrl.text.trim(), type: type, rappels: rappels, notes: notesCtrl.text.trim(),
                phases: [for (final p in phases) p.vers()])),
              child: Text(existant == null ? 'Ajouter' : 'Enregistrer', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            )),
          ])),
        );
      }),
    );
    if (res == null) return;
    setState(() {
      final i = existant == null ? -1 : _traitementsCr.indexOf(existant);
      if (i >= 0) { _traitementsCr[i] = res; } else { _traitementsCr.add(res); }
    });
  }

  static const _antiparasitairesCourants = ['Bravecto', 'NexGard', 'NexGard Spectra', 'Simparica', 'Simparica Trio',
      'Credelio', 'Advocate', 'Stronghold', 'Frontline', 'Broadline', 'Milbemax', 'Drontal', 'Milpro', 'Profender',
      'Seresto (collier)', 'Scalibor (collier)'];
  static const _medicamentsCourants = ['Metacam (méloxicam)', 'Previcox', 'Onsior', 'Rimadyl', 'Synulox', 'Clavaseptin',
      'Kesium', 'Marbocyl', 'Convenia', 'Prednisolone', 'Cortavance', 'Apoquel', 'Cytopoint', 'Vetmedin', 'Fortekor',
      'Cerenia', 'Gabapentine', 'Tramadol', 'Forthyron', 'Cardalis'];

  String _fmtPoids(double p) => p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(1).replaceAll('.', ',');

  Widget _blocConsultation() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: TextField(controller: _motifCtrl, textCapitalization: TextCapitalization.sentences,
            decoration: _inputDeco('Consultation, vaccination, boiterie…').copyWith(labelText: 'Motif'))),
        const SizedBox(width: 10),
        SizedBox(width: 120, child: TextField(controller: _poidsCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _inputDeco('kg').copyWith(labelText: 'Poids (kg)'))),
      ]),
      if (_messageClient.isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFF6F8F7), borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE4E7E2))),
          child: Text('💬 Message du client : $_messageClient',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade700)),
        ),
      ],
      const SizedBox(height: 12),
      // Actes réalisés : liste déroulante à cocher (recherche + autre acte).
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _choisirActes,
        child: InputDecorator(
          decoration: _inputDeco('').copyWith(labelText: 'Actes réalisés',
              suffixIcon: const Icon(Icons.arrow_drop_down)),
          child: Text(_actesRealises.isEmpty ? 'Choisir les actes…' : _actesRealises.join(', '),
              maxLines: 3, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Galey', fontSize: 14,
                  color: _actesRealises.isEmpty ? Colors.grey : const Color(0xFF1E2025))),
        ),
      ),
      const SizedBox(height: 16),
    ]);
  }

  Future<void> _choisirActes() async {
    final choix = {..._actesRealises};
    final autres = [for (final a in _actesRealises) if (!_actesCourants.contains(a)) a];
    final autreCtrl = TextEditingController();
    var q = '';
    final res = await showModalBottomSheet<Set<String>>(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setM) {
        final liste = [..._actesCourants, ...autres].where((a) => q.isEmpty || a.toLowerCase().contains(q.toLowerCase())).toList();
        void ajouter() {
          final v = autreCtrl.text.trim();
          if (v.isEmpty) return;
          setM(() { if (!autres.contains(v) && !_actesCourants.contains(v)) autres.add(v); choix.add(v); autreCtrl.clear(); });
        }
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.75,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(onChanged: (v) => setM(() => q = v),
                    decoration: _inputDeco('Rechercher un acte').copyWith(prefixIcon: const Icon(Icons.search, size: 18))),
              ),
              Expanded(child: ListView(children: [
                for (final a in liste) CheckboxListTile(
                  dense: true, value: choix.contains(a), activeColor: widget.categoryColor,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(a, style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
                  onChanged: (v) => setM(() => v == true ? choix.add(a) : choix.remove(a)),
                ),
              ])),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                child: Row(children: [
                  Expanded(child: TextField(controller: autreCtrl, textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => ajouter(), decoration: _inputDeco('Autre acte (biopsie, ECG…)'))),
                  IconButton(onPressed: ajouter, icon: Icon(Icons.add_circle_outline, color: widget.categoryColor)),
                ]),
              ),
              SafeArea(top: false, child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: SizedBox(width: double.infinity, child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: widget.categoryColor, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () => Navigator.pop(ctx, choix),
                  child: Text('Valider (${choix.length})', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                )),
              )),
            ]),
          ),
        );
      }),
    );
    if (res != null) setState(() { _actesRealises..clear()..addAll(res); });
  }

  // ── Facture de la consultation (au choix du vétérinaire) ──────────────────

  /// Prix TTC → HT (TVA 20 % des actes vétérinaires).
  double _ht(double ttc) => (ttc / 1.2 * 100).round() / 100;

  Future<void> _proposerFacture({
    required String animalId, String? rdvId, required ({String? uid, String? profileId}) owner,
    required String motif, double? poids, required List<String> actesRealises,
    required List<_VaccinCr> vaccins, required List<_TraitementCr> traitements,
  }) async {
    // Tarifs du vétérinaire + infos animal pour choisir la bonne ligne.
    Map<String, dynamic> tarifs = {};
    Map<String, dynamic>? an;
    try {
      if (_profilPro != null) {
        final t = await _supa.from('user_profiles_complet').select('tarifs_veto').eq('id', _profilPro!).maybeSingle();
        if (t?['tarifs_veto'] is Map) tarifs = Map<String, dynamic>.from(t!['tarifs_veto'] as Map);
      }
      an = await _supa.from('animaux').select('nom, espece, sexe, poids, client_clinique_id').eq('id', animalId).maybeSingle();
    } catch (_) {}
    double? tarif(String cle) => double.tryParse('${tarifs[cle] ?? ''}'.replaceAll(',', '.'));
    double? prixPharmacie(String nom) {
      for (final o in _pharmacie) {
        if ((o['nom'] ?? '').toString().toLowerCase() == nom.toLowerCase()) {
          return double.tryParse('${o['prix_vente'] ?? ''}'.replaceAll(',', '.'));
        }
      }
      return null;
    }
    final espece = (an?['espece'] ?? '').toString().toLowerCase();
    final femelle = (an?['sexe'] ?? '').toString().toLowerCase().startsWith('f');
    final kg = poids ?? double.tryParse('${an?['poids'] ?? ''}'.replaceAll(',', '.'));
    String tranche() => kg == null ? '25' : kg < 10 ? '10' : kg < 25 ? '25' : kg < 45 ? '45' : '45p';

    final lignes = <FacturePrefillLigne>[];
    void ligne(String designation, double? ttc) =>
        lignes.add(FacturePrefillLigne(designation: designation, prixHT: ttc == null ? 0 : _ht(ttc), quantite: 1, tauxTVA: 20));

    // 1. Le RDV (consultation / urgence / visite à domicile)
    final m = motif.toLowerCase();
    final cleRdv = m.contains('urgen') ? 'consultation_urgence' : m.contains('domicile') ? 'visite_domicile' : 'consultation';
    ligne(motif.isEmpty ? 'Consultation' : motif, tarif(cleRdv));
    // 2. Actes réalisés (tarif connu si dans la grille, sinon à compléter)
    for (final a in actesRealises) {
      if (a == 'Examen clinique') continue; // compris dans la consultation
      if (a == 'Vaccination' && vaccins.isNotEmpty) continue; // facturé avec le vaccin
      double? prix;
      if (a == 'Vaccination') prix = tarif(espece == 'chat' ? 'vaccin_chat' : 'vaccin_chien');
      if (a == 'Pose de puce') prix = tarif('identification');
      if (a == 'Castration / stérilisation') {
        prix = espece == 'chat' ? tarif(femelle ? 'sterilisation_chatte' : 'castration_chat')
            : tarif('${femelle ? 'sterilisation_chienne' : 'castration_chien'}_${tranche()}');
      }
      ligne(a, prix);
    }
    // 3. Produits : vaccins et traitements (prix de vente de la pharmacie)
    for (final v in vaccins) {
      ligne('Vaccin ${v.nom}${v.lot.isNotEmpty ? ' (lot ${v.lot})' : ''}',
          prixPharmacie(v.nom) ?? tarif(espece == 'chat' ? 'vaccin_chat' : 'vaccin_chien'));
    }
    for (final t in traitements) {
      ligne(t.nom, prixPharmacie(t.nom));
    }

    final total = lignes.fold<double>(0, (s, l) => s + l.prixHT * 1.2);
    final aCompleter = lignes.where((l) => l.prixHT == 0).length;
    if (!mounted) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Facturer cette consultation ?', style: TextStyle(fontFamily: 'Galey', fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final l in lignes) Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Expanded(child: Text(l.designation, style: const TextStyle(fontFamily: 'Galey', fontSize: 13))),
              Text(l.prixHT == 0 ? 'à compléter' : '${(l.prixHT * 1.2).toStringAsFixed(2)} €',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600,
                      color: l.prixHT == 0 ? Colors.orange.shade800 : const Color(0xFF1E2025))),
            ]),
          ),
          const Divider(),
          Text('Total estimé : ${total.toStringAsFixed(2)} € TTC'
              '${aCompleter > 0 ? ' — $aCompleter prix à compléter' : ''}',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Tarifs : votre grille (profil) et les prix de vente de la pharmacie. Tout reste modifiable avant l\'émission.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Pas maintenant', style: TextStyle(fontFamily: 'Galey')))),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: widget.categoryColor, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Préparer la facture', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            )),
          ]),
        ]),
      )),
    );
    if (ok != true || !mounted) return;

    // Client : fichier de la clinique, sinon RDV.
    String? nom, email, tel;
    if (an?['client_clinique_id'] != null) {
      try {
        final c = await _supa.from('clients_clinique').select('nom, prenom, email, telephone').eq('id', an!['client_clinique_id']).maybeSingle();
        nom = '${c?['prenom'] ?? ''} ${c?['nom'] ?? ''}'.trim();
        email = c?['email'] as String?;
        tel = c?['telephone'] as String?;
      } catch (_) {}
    }
    final r = widget.rdv ?? _rdvSource;
    nom ??= widget.clientName.isNotEmpty ? widget.clientName : r?['client_nom_manuel']?.toString();
    email ??= r?['client_email_manuel']?.toString();
    tel ??= r?['client_telephone_manuel']?.toString();
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CreerFacturePage(
      clientNom: nom, clientEmail: email, clientTel: tel,
      lignesPrefill: lignes,
      noteInitiale: 'Consultation de ${an?['nom'] ?? 'votre animal'}',
      sourceRdvId: rdvId ?? r?['id']?.toString(),
      sourceAnimalId: animalId,
      clientUid: owner.uid,
      clientProfileId: owner.profileId,
    )));
  }

  Widget _blocActes() {
    String date(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    Widget ligne(IconData ic, String titre, String sous, VoidCallback onEdit, VoidCallback onDelete) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: widget.categoryColor.withValues(alpha: 0.25))),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(children: [
            Icon(ic, size: 18, color: widget.categoryColor),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titre, style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, fontWeight: FontWeight.w700)),
              if (sous.isNotEmpty) Text(sous, style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
            ])),
            Icon(Icons.edit_outlined, size: 16, color: Colors.grey.shade500),
            IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onDelete, color: Colors.grey),
          ]),
        ),
      ),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _inputLabel('Vaccins réalisés'),
      const SizedBox(height: 6),
      for (final v in List.of(_vaccinsCr)) ligne(Icons.vaccines_outlined, v.nom,
          [if (v.lot.isNotEmpty) 'Lot ${v.lot}', if (v.rappel != null) 'Rappel le ${date(v.rappel!)}'].join(' · '),
          () => _ajouterVaccin(v), () => setState(() => _vaccinsCr.remove(v))),
      OutlinedButton.icon(
        onPressed: () => _ajouterVaccin(), icon: const Icon(Icons.add, size: 18),
        label: const Text('Ajouter un vaccin', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
        style: OutlinedButton.styleFrom(foregroundColor: widget.categoryColor, side: BorderSide(color: widget.categoryColor.withValues(alpha: 0.5)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      ),
      const SizedBox(height: 14),
      _inputLabel('Traitements prescrits'),
      const SizedBox(height: 6),
      for (final t in List.of(_traitementsCr)) ligne(Icons.medication_outlined, t.nom,
          [t.posologieComplete, if (t.rappels) 'rappels au propriétaire'].join(' · '),
          () => _ajouterTraitement(t), () => setState(() => _traitementsCr.remove(t))),
      OutlinedButton.icon(
        onPressed: () => _ajouterTraitement(), icon: const Icon(Icons.add, size: 18),
        label: const Text('Ajouter un traitement', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
        style: OutlinedButton.styleFrom(foregroundColor: widget.categoryColor, side: BorderSide(color: widget.categoryColor.withValues(alpha: 0.5)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      ),
      if (_traitementsCr.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(_peutOrdonnances
                ? "📄 L'ordonnance sera générée en PDF et ajoutée aux documents de l'animal."
                : 'Ordonnance : réservée aux vétérinaires — le traitement sera inscrit au carnet.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
      ],
      const SizedBox(height: 4),
      Text('Touchez une ligne pour la modifier. Inscrits au carnet de santé ; le propriétaire reçoit les rappels.',
          style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
      const SizedBox(height: 16),
    ]);
  }

  // ── Imprimer / partager / envoyer (CR et ordonnances) ─────────────────────

  /// En-tête clinique, patient, propriétaire (client de la clinique s'il n'a
  /// pas PetsMatch — e-mail pré-rempli).
  Future<({String clinique, String adresse, String tel, String animal, String especeRace,
      String identification, String proprio, String? email})> _infosDocument() async {
    final animalId = (widget.animalId ?? widget.rdv?['animal_id'])?.toString();
    final pro = _profilPro;
    Map<String, dynamic>? cl, an, client;
    try {
      if (pro != null) {
        cl = await _supa.from('user_profiles_complet')
            .select('nom, rue_pro, code_postal_pro, ville_pro, phone_number').eq('id', pro).maybeSingle();
      }
      if (animalId != null) {
        an = await _supa.from('animaux').select('nom, espece, race, identification, client_clinique_id')
            .eq('id', animalId).maybeSingle();
      }
      if (an?['client_clinique_id'] != null) {
        client = await _supa.from('clients_clinique').select('nom, prenom, email')
            .eq('id', an!['client_clinique_id']).maybeSingle();
      }
    } catch (_) {}
    var proprio = widget.clientName;
    if (client != null) proprio = '${client['prenom'] ?? ''} ${client['nom'] ?? ''}'.trim();
    return (
      clinique: (cl?['nom'] as String?)?.trim().isNotEmpty == true ? cl!['nom'] as String : 'Cabinet vétérinaire',
      adresse: [cl?['rue_pro'], '${cl?['code_postal_pro'] ?? ''} ${cl?['ville_pro'] ?? ''}'.trim()]
          .where((x) => (x?.toString() ?? '').trim().isNotEmpty).join(', '),
      tel: (cl?['phone_number'] ?? '').toString(),
      animal: (an?['nom'] ?? widget.rdv?['_animal_nom'] ?? 'Animal').toString(),
      especeRace: [an?['espece'], an?['race']].where((x) => (x?.toString() ?? '').isNotEmpty).join(' · '),
      identification: (an?['identification'] ?? '').toString(),
      proprio: proprio,
      email: client?['email'] as String?,
    );
  }

  Future<void> _transmettreCr(Map<String, dynamic> cr) async {
    final i = await _infosDocument();
    if (!mounted) return;
    final praticien = '${User_Info.firstname} ${User_Info.lastname}'.replaceAll('none', '').trim();
    await transmettreDocument(context,
      type: 'compte_rendu',
      nomFichier: 'Compte-rendu-${i.animal}.pdf',
      animalNom: i.animal, expediteur: i.clinique,
      emailParDefaut: i.email, destinataireNom: i.proprio,
      pdf: () => compteRenduPdfBytes(
        cliniqueNom: i.clinique, cliniqueAdresse: i.adresse, cliniqueTel: i.tel,
        praticien: praticien.isEmpty ? 'Vétérinaire' : praticien,
        animalNom: i.animal, animalEspeceRace: i.especeRace, animalIdentification: i.identification,
        proprietaire: i.proprio, contenu: cr['contenu']?.toString() ?? '',
        date: DateTime.tryParse(cr['created_at']?.toString() ?? '')?.toLocal(),
      ),
    );
  }

  Future<void> _transmettreOrdo(Map<String, dynamic> o) async {
    final url = o['doc_url']?.toString() ?? '';
    if (url.isEmpty) return;
    final i = await _infosDocument();
    if (!mounted) return;
    await transmettreDocument(context,
      type: 'ordonnance',
      nomFichier: 'Ordonnance-${i.animal}.pdf',
      animalNom: i.animal, expediteur: i.clinique,
      emailParDefaut: i.email, destinataireNom: i.proprio,
      pdf: () async {
        final lien = await lienDocument(url);
        final res = await http.get(Uri.parse(lien));
        if (res.statusCode != 200) throw Exception('document inaccessible');
        return res.bodyBytes;
      },
    );
  }

  ({String? uid, String? profileId})? _owner;

  /// Insert tolérant aux colonnes `*_profile_id` pas encore migrées : réessaie
  /// sans elles si la BDD les rejette.
  Future<void> _insertRecord(String table, Map<String, dynamic> base,
      Map<String, dynamic> profileExtra) async {
    try {
      await _supa.from(table).insert({...base, ...profileExtra});
    } catch (e) {
      if (profileExtra.isEmpty) rethrow;
      final msg = e.toString().toLowerCase();
      if (msg.contains('profile_id') || msg.contains('column') || msg.contains('schema cache')) {
        await _supa.from(table).insert(base);
      } else {
        rethrow;
      }
    }
  }

  /// Résout un propriétaire VALIDE pour l'animal / le RDV : `owner_uid` doit
  /// exister dans `users` (contrainte FK) sinon on le laisse nul ; `profile_id`
  /// = profil particulier du propriétaire.
  Future<({String? uid, String? profileId})> _resolveOwner() async {
    if (_owner != null) return _owner!;
    final animalId = (widget.animalId ?? widget.rdv?['animal_id'])?.toString();
    String? uid = widget.ownerUid?.trim();
    if (uid == null || uid.isEmpty) uid = widget.rdv?['client_uid']?.toString();
    if (uid != null && uid.isEmpty) uid = null;
    String? pid = widget.rdv?['client_profile_id']?.toString();
    if (pid != null && pid.isEmpty) pid = null;

    if ((uid == null || pid == null) && animalId != null && animalId.isNotEmpty) {
      try {
        final row = await _supa.from('animaux_proprietes')
            .select('uid_proprio, profile_id_proprio')
            .eq('animal_id', animalId).filter('date_fin', 'is', null)
            .order('date_debut', ascending: false).limit(1).maybeSingle();
        uid ??= row?['uid_proprio'] as String?;
        pid ??= row?['profile_id_proprio'] as String?;
      } catch (_) {}
    }

    // owner_uid doit être un uid réel (FK vers users).
    if (uid != null) {
      try {
        final u = await _supa.from('users_complet').select('uid').eq('uid', uid).maybeSingle();
        if (u == null) uid = null;
      } catch (_) { uid = null; }
    }
    // Profil particulier du propriétaire si non fourni.
    if (pid == null && uid != null) {
      try {
        final p = await _supa.from('user_profiles_complet')
            .select('id').eq('uid', uid).eq('profile_type', 'particulier')
            .order('is_main', ascending: false).limit(1).maybeSingle();
        pid = p?['id'] as String?;
      } catch (_) {}
    }
    _owner = (uid: uid, profileId: pid);
    return _owner!;
  }

  /// Valide un brouillon (vétérinaire) → visible et notifié au propriétaire.
  Future<void> _validerCr(Map<String, dynamic> cr) async {
    try {
      final monProfil = await AgendaContexte.monProfil();
      await _supa.from('comptes_rendus').update({
        'statut': 'valide',
        if (monProfil != null) 'valide_par_profile_id': monProfil,
      }).eq('id', cr['id']);
      await _notifyOwner(isOrdo: false);
      await _loadExisting();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Compte rendu validé et envoyé au propriétaire.', style: TextStyle(fontFamily: 'Galey')),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red, behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  /// Brouillon d'ASV : prévient le titulaire de la clinique et les
  /// vétérinaires qui peuvent valider (scopé au profil clinique).
  Future<void> _notifyValideurs() async {
    try {
      final cliniqueUid = AgendaContexte.uid;
      final cliniqueProfil = _profilPro;
      var animalNom = (widget.rdv?['_animal_nom'] ?? widget.rdv?['animal_nom'] ?? '').toString();
      final animalId = (widget.animalId ?? widget.rdv?['animal_id'])?.toString();
      if (animalNom.isEmpty && animalId != null) {
        final a = await _supa.from('animaux').select('nom').eq('id', animalId).maybeSingle();
        animalNom = (a?['nom'] as String?) ?? '';
      }
      final auteur = '${User_Info.firstname} ${User_Info.lastname}'.replaceAll('none', '').trim();
      final destinataires = <({String uid, String? profileId})>[
        if (cliniqueUid != null) (uid: cliniqueUid, profileId: cliniqueProfil),
      ];
      if (cliniqueProfil != null) {
        final vetos = await _supa.from('employe_permissions').select('employe_profile_id')
            .eq('eleveur_profile_id', cliniqueProfil).eq('permission', 'vet_cr_valider');
        final ids = [for (final v in vetos as List) v['employe_profile_id'] as String];
        if (ids.isNotEmpty) {
          final emps = await _supa.from('employes').select('uid_employe, employe_profile_id')
              .eq('eleveur_profile_id', cliniqueProfil).eq('actif', true).inFilter('employe_profile_id', ids);
          for (final e in emps as List) {
            final u = e['uid_employe'] as String?;
            if (u != null && u != AgendaContexte.moi) {
              destinataires.add((uid: u, profileId: e['employe_profile_id'] as String?));
            }
          }
        }
      }
      for (final d in destinataires) {
        await _supa.from('notifications').insert({
          'uid': d.uid,
          'type': 'cr_a_valider',
          'title': '📝 Compte rendu à valider${animalNom.isEmpty ? '' : ' — $animalNom'}',
          'body': '${auteur.isEmpty ? 'Un(e) assistant(e)' : auteur} a rédigé un compte rendu à relire et valider.',
          if (d.profileId != null) 'profile_id': d.profileId,
          'data': {'animalId': animalId, 'cliniqueProfileId': cliniqueProfil, 'cliniqueUid': cliniqueUid},
          'read': false,
        });
      }
    } catch (_) {}
  }

  /// Prévient le propriétaire qu'un compte rendu / une ordonnance a été ajouté.
  Future<void> _notifyOwner({required bool isOrdo}) async {
    try {
      final owner = await _resolveOwner();
      final ownerUid = owner.uid;
      final ownerProfileId = owner.profileId;
      final animalId = (widget.animalId ?? widget.rdv?['animal_id'])?.toString();
      if (ownerUid == null || ownerUid.isEmpty) return;

      var animalNom = (widget.rdv?['_animal_nom'] ?? widget.rdv?['animal_nom'] ?? '').toString();
      if (animalNom.isEmpty && animalId != null) {
        final a = await _supa.from('animaux').select('nom').eq('id', animalId).maybeSingle();
        animalNom = (a?['nom'] as String?) ?? '';
      }
      final proNom = User_Info.nameElevage.isNotEmpty
          ? User_Info.nameElevage
          : '${User_Info.firstname} ${User_Info.lastname}'.trim();
      final quoi = isOrdo ? 'une ordonnance' : 'un compte rendu';

      await _supa.from('notifications').insert({
        'uid': ownerUid,
        'type': 'compte_rendu_recu',
        'title': isOrdo
            ? '💊 Ordonnance — ${animalNom.isEmpty ? 'votre animal' : animalNom}'
            : '📄 Compte rendu — ${animalNom.isEmpty ? 'votre animal' : animalNom}',
        'body': '${proNom.isEmpty ? 'Votre professionnel' : proNom} a ajouté $quoi'
            '${animalNom.isEmpty ? '' : ' pour $animalNom'}.',
        if (ownerProfileId != null && ownerProfileId.isNotEmpty) 'profile_id': ownerProfileId,
        'data': {'animalId': animalId, 'animalNom': animalNom},
        'read': false,
      });
    } catch (_) {}
  }

  Future<void> _saveOrdonnance() async {
    final proUid = AgendaContexte.uid;
    final moi = AgendaContexte.moi;
    if (proUid == null || _ordoFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Veuillez sélectionner un fichier PDF.',
            style: TextStyle(fontFamily: 'Galey')),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _ordoSaving = true);
    final rdvId    = widget.rdv?['id'];
    final animalId = widget.animalId ?? widget.rdv?['animal_id'];
    try {
      final owner = await _resolveOwner();
      final proProfileId = _profilPro;
      final monProfil = await AgendaContexte.monProfil();
      final name   = '${DateTime.now().millisecondsSinceEpoch}.${_ordoFile!.path.split('.').last}';
      final docUrl = await uploadDocument(_ordoFile!, 'ordonnances/${moi ?? proUid}/$name');
      final today  = DateTime.now();
      await _insertRecord('ordonnances', {
        'pro_uid'  : proUid,
        'animal_id': animalId,
        if (owner.uid != null) 'owner_uid': owner.uid,
        if (rdvId != null) 'rdv_id': rdvId,
        'doc_url'  : docUrl,
        'date_emit': '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}',
        if (_ordoNotesCtrl.text.trim().isNotEmpty) 'notes': _ordoNotesCtrl.text.trim(),
      }, {
        if (proProfileId != null && proProfileId.isNotEmpty) 'pro_profile_id': proProfileId,
        if (owner.profileId != null) 'owner_profile_id': owner.profileId,
        if (moi != null) 'praticien_uid': moi,
        if (monProfil != null) 'praticien_profile_id': monProfil,
      });
      await _notifyOwner(isOrdo: true);
      setState(() => _ordoFile = null);
      _ordoNotesCtrl.clear();
      await _loadExisting();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ordonnance enregistrée.', style: TextStyle(fontFamily: 'Galey')),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _ordoSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: widget.categoryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.isPension ? 'Compte rendu' : 'CR & Ordonnances',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
            if (widget.clientName.isNotEmpty)
              Text(widget.clientName,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.white70)),
          ],
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13),
          tabs: [
            Tab(text: 'Compte rendu${_crs.isNotEmpty ? " (${_crs.length})" : ""}'),
            if (!widget.isPension)
              Tab(text: 'Ordonnances${_ordos.isNotEmpty ? " (${_ordos.length})" : ""}'),
          ],
        ),
      ),
      body: _loadingDocs
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0C5C6C)))
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildCompteRenduTab(),
                if (!widget.isPension) _buildOrdonnanceTab(),
              ],
            ),
    );
  }

  // ── Onglet Compte rendu ──────────────────────────────────────────────────────

  Widget _buildCompteRenduTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Existing CRs
          if (_crs.isNotEmpty) ...[
            _sectionTitle('Comptes rendus existants'),
            const SizedBox(height: 8),
            ..._crs.map((cr) => _CrCard(cr: cr, color: widget.categoryColor,
                onTransmettre: widget.isPension ? null : () => _transmettreCr(cr),
                onDelete: (cr['statut'] != 'brouillon' && !_peutValider)
                    ? null : () => _deleteDoc('comptes_rendus', cr['id'].toString()),
                onValider: (cr['statut'] == 'brouillon' && _peutValider) ? () => _validerCr(cr) : null)),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 8),
          ],

          _sectionTitle('Nouveau compte rendu'),
          const SizedBox(height: 12),

          if (_saisieActes) _blocConsultation(),
          if (_saisieActes) _blocActes(),

          // Contenu
          _inputLabel(_saisieActes ? 'Observations' : 'Contenu *'),
          const SizedBox(height: 6),
          TextFormField(
            controller: _crContenuCtrl,
            maxLines: 6,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            decoration: _inputDeco('Décrivez la consultation, les observations, les recommandations…'),
          ),
          const SizedBox(height: 14),

          // Document joint (optionnel)
          _inputLabel('Document joint (optionnel)'),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: _pickCrFile,
            icon: const Icon(Icons.upload_file, size: 18),
            label: Text(
              _crFile != null ? _crFile!.path.split('/').last : 'Joindre un PDF / image',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 46),
              side: BorderSide(color: _crFile != null ? widget.categoryColor : Colors.grey.shade300),
              foregroundColor: widget.categoryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _crSaving ? null : _saveCompteRendu,
              icon: _crSaving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: Text(_crSaving ? 'Enregistrement…' : 'Enregistrer le CR',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.categoryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ── Onglet Ordonnances ───────────────────────────────────────────────────────

  Widget _buildOrdonnanceTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Existing ordonnances
          if (_ordos.isNotEmpty) ...[
            _sectionTitle('Ordonnances existantes'),
            const SizedBox(height: 8),
            ..._ordos.map((o) => _OrdoCard(ordo: o, color: widget.categoryColor,
                onTransmettre: () => _transmettreOrdo(o),
                onDelete: () => _deleteDoc('ordonnances', o['id'].toString()))),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 8),
          ],

          if (!_peutOrdonnances)
            Text("La prescription est réservée aux vétérinaires de la clinique.",
                style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600))
          else ...[
          _sectionTitle('Nouvelle ordonnance'),
          const SizedBox(height: 12),

          // Fichier ordonnance
          _inputLabel('Fichier PDF *'),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: _pickOrdoFile,
            icon: const Icon(Icons.upload_file, size: 18),
            label: Text(
              _ordoFile != null ? _ordoFile!.path.split('/').last : 'Sélectionner un PDF *',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 46),
              side: BorderSide(color: _ordoFile != null ? widget.categoryColor : Colors.grey.shade300),
              foregroundColor: widget.categoryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 14),

          // Notes
          _inputLabel('Notes (optionnel)'),
          const SizedBox(height: 6),
          TextFormField(
            controller: _ordoNotesCtrl,
            maxLines: 3,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            decoration: _inputDeco('Posologie, instructions particulières…'),
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _ordoSaving ? null : _saveOrdonnance,
              icon: _ordoSaving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.description_outlined),
              label: Text(_ordoSaving ? 'Enregistrement…' : 'Enregistrer l\'ordonnance',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.categoryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
            ),
          ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1E2025)));

  Widget _inputLabel(String t) => Text(t,
      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF444444)));

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFDDDDDD))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFDDDDDD))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: widget.categoryColor)),
    contentPadding: const EdgeInsets.all(14),
  );
}

class _VaccinCr {
  final String nom, lot;
  final DateTime date;
  final DateTime? rappel;
  _VaccinCr(this.nom, this.lot, this.date, this.rappel);
}

/// Prises de la journée → libellé + heure du rappel au propriétaire.
const _kPrises = <String, (String, String)>{
  'matin': ('Matin', '08:00'),
  'midi': ('Midi', '12:00'),
  'soir': ('Soir', '19:00'),
};

/// Phase d'un traitement (dégressif : plusieurs phases enchaînées).
class _PhaseCr {
  final String dose;
  final Set<String> prises;
  final int frequenceJours;
  final int? dureeJours;
  const _PhaseCr({required this.dose, required this.prises, this.frequenceJours = 1, this.dureeJours});

  /// « 1 cp matin et soir, tous les 2 jours, pendant 3 jours ».
  String get libelle {
    final noms = [for (final k in _kPrises.keys) if (prises.contains(k)) _kPrises[k]!.$1.toLowerCase()];
    final quand = noms.length > 1 ? '${noms.sublist(0, noms.length - 1).join(', ')} et ${noms.last}' : noms.join();
    return [
      [if (dose.trim().isNotEmpty) dose.trim(), quand].where((x) => x.isNotEmpty).join(' '),
      if (frequenceJours > 1) 'tous les $frequenceJours jours',
      dureeJours != null ? 'pendant $dureeJours jour${dureeJours! > 1 ? 's' : ''}' : 'au long cours',
    ].join(', ');
  }
}

class _PhaseEdit {
  final TextEditingController dose, duree, frequenceCtrl;
  final Set<String> prises;
  _PhaseEdit(this.dose, this.duree, this.frequenceCtrl, this.prises);
  int get frequence => (int.tryParse(frequenceCtrl.text.trim()) ?? 1).clamp(1, 365);
  factory _PhaseEdit.de(_PhaseCr p) => _PhaseEdit(TextEditingController(text: p.dose),
      TextEditingController(text: p.dureeJours?.toString() ?? ''),
      TextEditingController(text: '${p.frequenceJours}'), {...p.prises});
  _PhaseCr vers() => _PhaseCr(dose: dose.text.trim(), prises: {...prises}, frequenceJours: frequence,
      dureeJours: int.tryParse(duree.text.trim()));
}

class _TraitementCr {
  final String nom, type, notes;
  final List<_PhaseCr> phases;
  final bool rappels;
  _TraitementCr({required this.nom, required this.type, required this.phases, required this.rappels, this.notes = ''});

  /// Posologie de toutes les phases : « …, puis … ».
  String get posologieComplete => phases.map((p) => p.libelle).join(', puis ');
}

// ── Cards existants ──────────────────────────────────────────────────────────

class _CrCard extends StatelessWidget {
  final Map<String, dynamic> cr;
  final Color color;
  final VoidCallback? onDelete;
  final VoidCallback? onValider;
  /// Imprimer / partager / envoyer au propriétaire (CR validé).
  final VoidCallback? onTransmettre;
  const _CrCard({required this.cr, required this.color, this.onDelete, this.onValider, this.onTransmettre});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(cr['created_at']?.toString() ?? '')?.toLocal();
    final contenu = cr['contenu']?.toString() ?? '';
    final docUrl  = cr['doc_url']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (date != null)
            Text('${date.day}/${date.month}/${date.year}',
                style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
          if (cr['statut'] == 'brouillon') ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFFFFF4E0), borderRadius: BorderRadius.circular(8)),
              child: const Text('Brouillon — à valider',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFB26A00))),
            ),
          ],
          const Spacer(),
          if (onTransmettre != null && cr['statut'] != 'brouillon')
            IconButton(visualDensity: VisualDensity.compact, tooltip: 'Imprimer / envoyer',
                onPressed: onTransmettre, icon: Icon(Icons.ios_share, size: 18, color: color)),
          if (onDelete != null)
            GestureDetector(onTap: onDelete,
              child: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFCCCCCC))),
        ]),
        const SizedBox(height: 6),
        Text(contenu,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 13, height: 1.4)),
        if (docUrl.isNotEmpty) ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () async {
              await ouvrirDocument(context, docUrl);
            },
            child: Row(children: [
              Icon(Icons.attach_file, size: 13, color: color),
              const SizedBox(width: 4),
              Text('Voir le document',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                      color: color, fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline)),
            ]),
          ),
        ],
        if (onValider != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: onValider,
              icon: const Icon(Icons.task_alt, size: 16),
              label: const Text('Valider et envoyer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
            ),
          ),
        ],
      ]),
    );
  }
}

class _OrdoCard extends StatelessWidget {
  final Map<String, dynamic> ordo;
  final Color color;
  final VoidCallback? onDelete;
  final VoidCallback? onTransmettre;
  const _OrdoCard({required this.ordo, required this.color, this.onDelete, this.onTransmettre});

  @override
  Widget build(BuildContext context) {
    final dateEmit = ordo['date_emit']?.toString() ?? '';
    final docUrl   = ordo['doc_url']?.toString() ?? '';
    final notes    = ordo['notes']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.description_outlined, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(child: Text('Ordonnance du $dateEmit',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13, color: color))),
          if (onTransmettre != null && docUrl.isNotEmpty)
            IconButton(visualDensity: VisualDensity.compact, tooltip: 'Imprimer / envoyer',
                onPressed: onTransmettre, icon: Icon(Icons.ios_share, size: 18, color: color)),
          if (onDelete != null)
            GestureDetector(onTap: onDelete,
              child: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFCCCCCC))),
        ]),
        if (docUrl.isNotEmpty) ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () async {
              await ouvrirDocument(context, docUrl);
            },
            child: Row(children: [
              Icon(Icons.description_outlined, size: 14, color: color),
              const SizedBox(width: 4),
              Text('Voir l\'ordonnance',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                      color: color, fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline)),
            ]),
          ),
        ],
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(notes, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, height: 1.4)),
        ],
      ]),
    );
  }
}
