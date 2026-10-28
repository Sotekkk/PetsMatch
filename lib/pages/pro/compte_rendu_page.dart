import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/widgets/carnet/prises_traitement.dart' show AideEtapes;
import 'package:PetsMatch/utils/document_prive.dart';
import 'package:PetsMatch/utils/storage_helper.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/contexte_pro.dart';
import 'package:PetsMatch/pages/pro/ordonnance_pdf.dart';
import 'package:PetsMatch/pages/eleveur/admin/facturation.dart' show CreerFacturePage, FacturePrefillLigne;
import 'package:PetsMatch/pages/pro/transmission_document.dart';
import 'package:PetsMatch/pages/pro/pro_profile_edit.dart' show ProProfileEditPage;
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
  /// Produits vendus (non administrés) : facture + stock, pas le carnet.
  final List<_ProduitCr> _produitsCr = [];
  /// Autres soins inscrits au carnet à l'enregistrement (vermifuge,
  /// antiparasitaire, allergie, chirurgie / hospitalisation, radio / examen).
  final List<_SoinCr> _soinsCr = [];
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
    _prefillDepuisRdv().whenComplete(() { _chargerRappelsVaccins(); _chargerCarnetDuJour(); });
  }

  /// Actes inscrits au carnet AUJOURD'HUI par moi (Synthèse, onglet Santé) et
  /// pesée du jour : repris dans le compte rendu sans être réécrits au
  /// carnet. Ceux déjà couverts par un compte rendu de ce jour sont exclus.
  List<({String type, String libelle, Map<String, dynamic> ligne})> _carnetJour = [];
  double? _poidsCarnet;
  static const _libCarnet = {'vaccin': 'Vaccin', 'traitement': 'Traitement', 'vermifuge': 'Vermifuge', 'antiparasitaire': 'Antiparasitaire'};

  Future<void> _chargerCarnetDuJour() async {
    final animalId = (widget.animalId ?? widget.rdv?['animal_id'])?.toString();
    final vetId = AgendaContexte.moi ?? AgendaContexte.uid;
    if (animalId == null || animalId.isEmpty || widget.isPension || vetId == null) return;
    final now = DateTime.now();
    final jour = DateTime(now.year, now.month, now.day);
    final ymd = '${jour.year}-${jour.month.toString().padLeft(2, '0')}-${jour.day.toString().padLeft(2, '0')}';
    try {
      var crQ = _supa.from('comptes_rendus').select('created_at').eq('animal_id', animalId)
          .gte('created_at', jour.toUtc().toIso8601String());
      crQ = _profilPro != null ? crQ.eq('pro_profile_id', _profilPro!) : crQ.eq('pro_uid', AgendaContexte.uid ?? '');
      final crs = await crQ.order('created_at', ascending: false).limit(1);
      final depuis = (crs as List).isEmpty ? null : DateTime.tryParse(crs.first['created_at'].toString());
      bool apres(Map m) {
        final c = DateTime.tryParse(m['created_at']?.toString() ?? '');
        return depuis == null || c == null || c.isAfter(depuis);
      }
      final res = <({String type, String libelle, Map<String, dynamic> ligne})>[];
      for (final (table, type) in const [('vaccinations', 'vaccin'), ('traitements', 'traitement'),
          ('vermifuges', 'vermifuge'), ('antiparasitaires', 'antiparasitaire')]) {
        final rows = await _supa.from(table).select().eq('animal_id', animalId).eq('vet_id', vetId).eq('date', ymd).order('created_at');
        for (final r in rows as List) {
          final m = Map<String, dynamic>.from(r as Map);
          if (!apres(m)) continue;
          String s(String k) => (m[k] ?? '').toString().trim();
          final libelle = switch (type) {
            'vaccin' => '${s('vaccin').isEmpty ? 'Vaccin' : s('vaccin')}${s('lot').isNotEmpty ? ' (lot ${s('lot')})' : ''}',
            'traitement' => '${s('nom').isEmpty ? 'Traitement' : s('nom')}${s('posologie').isNotEmpty ? ' — ${s('posologie')}' : ''}',
            _ => s('produit').isEmpty ? _libCarnet[type]! : s('produit'),
          };
          res.add((type: type, libelle: libelle, ligne: m));
        }
      }
      final p = await _supa.from('poids').select('valeur, created_at').eq('animal_id', animalId).eq('date', ymd)
          .order('created_at', ascending: false).limit(1).maybeSingle();
      if (!mounted) return;
      setState(() {
        _carnetJour = res;
        _poidsCarnet = p != null && apres(p) ? (p['valeur'] as num?)?.toDouble() : null;
        if (_poidsCarnet != null && _poidsCtrl.text.trim().isEmpty) _poidsCtrl.text = _fmtPoids(_poidsCarnet!);
        if (res.any((a) => a.type == 'vaccin')) _actesRealises.add('Vaccination');
      });
    } catch (_) {}
  }

  /// Rappels de vaccins de l'animal à faire : en retard ou dans les 30 jours
  /// (dernière injection de chaque vaccin seulement — un rappel déjà fait
  /// n'apparaît plus).
  List<Map<String, dynamic>> _rappelsVaccins = [];

  Future<void> _chargerRappelsVaccins() async {
    final animalId = (widget.animalId ?? widget.rdv?['animal_id'])?.toString();
    if (animalId == null || animalId.isEmpty || widget.isPension) return;
    try {
      final rows = await _supa.from('vaccinations').select('id, vaccin, categorie, date, date_rappel')
          .eq('animal_id', animalId).order('date', ascending: false, nullsFirst: false).limit(200);
      final limite = DateTime.now().add(const Duration(days: 30));
      final vus = <String>{};
      final res = <Map<String, dynamic>>[];
      for (final r in rows as List) {
        final m = Map<String, dynamic>.from(r as Map);
        final cle = ((m['categorie'] ?? '').toString().isNotEmpty ? m['categorie'] : m['vaccin'] ?? '').toString().toLowerCase();
        if (cle.isEmpty || !vus.add(cle)) continue;
        final dr = DateTime.tryParse((m['date_rappel'] ?? '').toString());
        if (dr == null || dr.isAfter(limite)) continue;
        res.add(m);
      }
      res.sort((a, b) => a['date_rappel'].toString().compareTo(b['date_rappel'].toString()));
      if (mounted) setState(() => _rappelsVaccins = res);
    } catch (_) {}
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

  /// Brouillon repris (ligne comptes_rendus modifiée au lieu d'en créer une).
  String? _brouillonId;

  /// Saisie complète, gardée avec le brouillon (format commun appli / site).
  Map<String, dynamic> _etatBrouillon() => {
        'motif': _motifCtrl.text.trim(),
        'poids': _poidsCtrl.text.trim(),
        'texte': _crContenuCtrl.text.trim(),
        'diag': '',
        'actes': [..._actesRealises],
        'vaccins': [for (final v in _vaccinsCr) v.toJson()],
        'traitements': [for (final t in _traitementsCr) t.toJson()],
        'produits': [for (final p in _produitsCr) p.toJson()],
        'soins': [for (final s in _soinsCr) s.toJson()],
      };

  void _reprendreBrouillon(Map<String, dynamic> cr) {
    final e = cr['brouillon'];
    if (e is! Map) return;
    final diag = (e['diag'] ?? '').toString().trim();
    final texte = (e['texte'] ?? '').toString().trim();
    setState(() {
      _brouillonId = cr['id'].toString();
      _motifCtrl.text = (e['motif'] ?? '').toString();
      _poidsCtrl.text = (e['poids'] ?? '').toString();
      _crContenuCtrl.text = [if (diag.isNotEmpty) 'Diagnostic : $diag', if (texte.isNotEmpty) texte].join('\n\n');
      _actesRealises..clear()..addAll([for (final a in (e['actes'] as List? ?? const [])) a.toString()]);
      _vaccinsCr..clear()..addAll([for (final v in (e['vaccins'] as List? ?? const [])) _VaccinCr.fromJson(Map<String, dynamic>.from(v as Map))]);
      _traitementsCr..clear()..addAll([for (final t in (e['traitements'] as List? ?? const [])) _TraitementCr.fromJson(Map<String, dynamic>.from(t as Map))]);
      _produitsCr..clear()..addAll([for (final p in (e['produits'] as List? ?? const [])) _ProduitCr.fromJson(Map<String, dynamic>.from(p as Map))]);
      _soinsCr..clear()..addAll([for (final x in (e['soins'] as List? ?? const [])) _SoinCr.fromJson(Map<String, dynamic>.from(x as Map))]);
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Brouillon repris : modifiez-le, puis enregistrez.', style: TextStyle(fontFamily: 'Galey')),
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// Facturer après coup un compte rendu validé : motif, poids, actes du CR,
  /// vaccins et traitements inscrits au carnet par moi le jour du CR.
  Future<void> _facturerCr(Map<String, dynamic> cr) async {
    final animalId = (cr['animal_id'] ?? widget.animalId ?? widget.rdv?['animal_id'])?.toString();
    if (animalId == null || animalId.isEmpty) return;
    final d = DateTime.tryParse(cr['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now();
    final ymd = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final vetId = AgendaContexte.moi ?? AgendaContexte.uid;
    var vac = <dynamic>[], trt = <dynamic>[];
    if (vetId != null) {
      try {
        vac = await _supa.from('vaccinations').select('vaccin, lot, date, date_rappel')
            .eq('animal_id', animalId).eq('date', ymd).eq('vet_id', vetId);
        trt = await _supa.from('traitements').select('nom').eq('animal_id', animalId).eq('date', ymd).eq('vet_id', vetId);
      } catch (_) {}
    }
    final owner = await _resolveOwner();
    if (!mounted) return;
    await _proposerFacture(
      animalId: animalId, rdvId: cr['rdv_id']?.toString(), owner: owner,
      motif: (cr['motif'] ?? '').toString(), poids: (cr['poids'] as num?)?.toDouble(),
      actesRealises: [for (final a in (cr['actes'] as List? ?? const [])) a.toString()],
      vaccins: [for (final v in vac) _VaccinCr((v['vaccin'] ?? 'Vaccin').toString(), (v['lot'] ?? '').toString(),
          DateTime.tryParse(v['date']?.toString() ?? '') ?? d, DateTime.tryParse(v['date_rappel']?.toString() ?? ''))],
      traitements: [for (final n in {for (final t in trt) (t['nom'] ?? '').toString()}) if (n.isNotEmpty)
          _TraitementCr(nom: n, type: 'medicament', phases: const [], rappels: false)],
      produits: [for (final p in (cr['produits'] as List? ?? const [])) _ProduitCr.fromJson(Map<String, dynamic>.from(p as Map))],
    );
  }

  void _abandonnerBrouillon() => setState(() {
        _brouillonId = null;
        _crContenuCtrl.clear();
        _poidsCtrl.clear();
        _vaccinsCr.clear();
        _traitementsCr.clear();
        _produitsCr.clear();
        _soinsCr.clear();
        _actesRealises.clear();
      });

  /// [enBrouillon] : enregistré sans être validé — invisible du propriétaire,
  /// sans notification, carnet ni facture ; repris plus tard.
  Future<void> _saveCompteRendu({bool enBrouillon = false}) async {
    final proUid  = AgendaContexte.uid;
    final moi     = AgendaContexte.moi;
    final actes = _saisieActes && (_vaccinsCr.isNotEmpty || _traitementsCr.isNotEmpty || _soinsCr.isNotEmpty);
    // Instantané pour la facture proposée après l'enregistrement.
    final factVaccins = [
      ..._vaccinsCr,
      if (_saisieActes)
        for (final a in _carnetJour)
          if (a.type == 'vaccin')
            _VaccinCr((a.ligne['vaccin'] ?? 'Vaccin').toString(), (a.ligne['lot'] ?? '').toString(),
                DateTime.tryParse(a.ligne['date']?.toString() ?? '') ?? DateTime.now(),
                DateTime.tryParse(a.ligne['date_rappel']?.toString() ?? '')),
    ];
    final factTraitements = List<_TraitementCr>.of(_traitementsCr);
    final factActes = _actesRealises.toList();
    final factProduits = _saisieActes ? List<_ProduitCr>.of(_produitsCr) : const <_ProduitCr>[];
    final motif = _saisieActes ? _motifCtrl.text.trim() : '';
    final poids = _saisieActes ? _poidsSaisi : null;
    final actesRealises = _saisieActes ? _actesRealises.toList() : const <String>[];
    // Actes du CR + actes déjà inscrits au carnet aujourd'hui (Synthèse, Santé).
    final carnet = _saisieActes ? _carnetJour : const <({String type, String libelle, Map<String, dynamic> ligne})>[];
    List<String> duCarnet(String t) => [for (final a in carnet) if (a.type == t) a.libelle];
    List<String> soins(String t) => actes ? [for (final s in _soinsCr) if (s.type == t) s.libelle] : const [];
    final vaccinsTxt = [
      if (actes) for (final v in _vaccinsCr) v.nom + (v.lot.isNotEmpty ? ' (lot ${v.lot})' : ''),
      ...duCarnet('vaccin'),
    ];
    final traitementsTxt = [
      if (actes) for (final t in _traitementsCr) '${t.nom} — ${t.posologieComplete}',
      ...duCarnet('traitement'),
    ];
    final prescription = traitementsTxt.join(' ; ');
    final contenu = [
      if (motif.isNotEmpty) 'Motif : $motif',
      if (poids != null) 'Poids : ${_fmtPoids(poids)} kg',
      if (actesRealises.isNotEmpty) 'Actes réalisés : ${actesRealises.join(', ')}.',
      _crContenuCtrl.text.trim(),
      if (vaccinsTxt.isNotEmpty) 'Vaccins : ${vaccinsTxt.join(', ')}.',
      for (final (type, titre) in const [('vermifuge', 'Vermifuge'), ('antiparasitaire', 'Antiparasitaire'),
          ('allergie', 'Allergie / pathologie'), ('chirurgie', 'Chirurgie'), ('hospitalisation', 'Hospitalisation'), ('radio', 'Examen')])
        if ([...soins(type), ...duCarnet(type)].isNotEmpty) '$titre : ${[...soins(type), ...duCarnet(type)].join(', ')}.',
      if (traitementsTxt.isNotEmpty) 'Traitement : ${traitementsTxt.join(' ; ')}.',
      if (factProduits.isNotEmpty) 'Produits délivrés : ${factProduits.map((p) => p.libelle).join(', ')}.',
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
      final statut = !enBrouillon && _peutValider ? 'valide' : 'brouillon';
      String? docUrl;
      if (_crFile != null) {
        final name = '${DateTime.now().millisecondsSinceEpoch}.${_crFile!.path.split('.').last}';
        // Dossier de l'auteur (règles de stockage) ; la lecture passe par
        // la référence du CR (lien-document), pas par le dossier.
        docUrl = await uploadDocument(_crFile!, 'comptes_rendus/${moi ?? proUid}/$name');
      }
      final ligneCr = <String, dynamic>{
        'pro_uid'   : proUid,
        'animal_id' : animalId,
        if (owner.uid != null) 'owner_uid': owner.uid,
        if (rdvId != null) 'rdv_id': rdvId,
        'contenu'   : contenu,
        if (docUrl != null) 'doc_url': docUrl,
      };
      final champsCr = <String, dynamic>{
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
        if (factProduits.isNotEmpty) 'produits': [for (final p in factProduits) p.toJson()],
      };
      final etat = enBrouillon ? _etatBrouillon() : null;
      if (_brouillonId != null) {
        await _supa.from('comptes_rendus').update({...ligneCr, ...champsCr, 'brouillon': etat}).eq('id', _brouillonId!);
      } else {
        await _insertRecord('comptes_rendus', ligneCr, {...champsCr, if (etat != null) 'brouillon': etat});
      }
      if (enBrouillon) {
        _crContenuCtrl.clear();
        _poidsCtrl.clear();
        setState(() { _crFile = null; _brouillonId = null; _vaccinsCr.clear(); _traitementsCr.clear(); _produitsCr.clear(); _soinsCr.clear(); _actesRealises.clear(); });
        await _loadExisting();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Brouillon enregistré — non visible du propriétaire. Reprenez-le depuis la liste.',
                style: TextStyle(fontFamily: 'Galey')),
            behavior: SnackBarBehavior.floating,
          ));
        }
        return;
      }
      _brouillonId = null;
      // Pesée du jour → courbe de poids + poids de la fiche (sauf si c'est
      // la pesée déjà inscrite aujourd'hui depuis la Synthèse).
      if (poids != null && animalId != null && poids != _poidsCarnet) {
        try {
          await _supa.from('poids').insert({
            'id': DateTime.now().microsecondsSinceEpoch.toString(),
            'animal_id': animalId, 'valeur': poids,
            'date': DateTime.now().toIso8601String(), 'notes': 'Consultation',
          });
          await _supa.from('animaux').update({'poids': poids}).eq('id', animalId);
        } catch (_) {}
      }
      if (statut == 'valide') {
        await _notifyOwner(isOrdo: false, crId: await _dernierCrId());
      } else {
        await _notifyValideurs();
      }
      if (actes && animalId != null) await _ecrireActes(animalId.toString(), rdvId?.toString(), owner);
      if (factProduits.isNotEmpty) await _decompterStock(factProduits);
      final poidsFacture = _poidsSaisi;
      final motifFacture = _motifCtrl.text.trim();
      _crContenuCtrl.clear();
      _poidsCtrl.clear();
      setState(() { _crFile = null; _vaccinsCr.clear(); _traitementsCr.clear(); _produitsCr.clear(); _soinsCr.clear(); _actesRealises.clear(); _carnetJour = []; _poidsCarnet = null; });
      await _loadExisting();
      // Le vétérinaire choisit de préparer (ou non) la facture de la consultation.
      if (mounted && _saisieActes && statut == 'valide' && animalId != null) {
        await _proposerFacture(animalId: animalId.toString(), rdvId: rdvId?.toString(), owner: owner,
            motif: motifFacture, poids: poidsFacture, actesRealises: factActes,
            vaccins: factVaccins, traitements: factTraitements, produits: factProduits);
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
    for (final s in _soinsCr) {
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final rappel = s.rappelMois == null ? null : ymd(DateTime(today.year, today.month + s.rappelMois!, today.day));
      final base = {'id': id, 'animal_id': animalId, 'date': ymd(today), 'source': 'veterinaire', if (vetId != null) 'vet_id': vetId};
      try {
        switch (s.type) {
          case 'vermifuge':
            await _supa.from('vermifuges').insert({...base, 'produit': s.nom,
                if (s.detail.isNotEmpty) 'dosage': s.detail, if (rappel != null) 'date_rappel': rappel});
          case 'antiparasitaire':
            await _supa.from('antiparasitaires').insert({...base, 'produit': s.nom,
                if (s.detail.isNotEmpty) 'frequence': s.detail, if (rappel != null) 'date_rappel': rappel});
          case 'allergie':
            await _supa.from('allergies').insert({...base, 'description': s.nom, if (s.detail.isNotEmpty) 'severite': s.detail});
          case 'chirurgie':
          case 'hospitalisation':
            await _supa.from('chirurgies').insert({...base, 'type': s.type, 'intitule': s.nom, 'statut': 'realise',
                'veterinaire': praticien, if (s.detail.isNotEmpty) 'notes': s.detail});
          case 'radio':
            await _supa.from('radios').insert({...base, 'titre': s.nom, 'veterinaire': praticien,
                if (s.detail.isNotEmpty) 'notes': s.detail});
        }
      } catch (e) { erreurs.add('${_SoinCr.libelles[s.type] ?? s.type} ${s.nom}'.toLowerCase()); }
    }
    for (final t in _traitementsCr) {
      // Antiparasitaire : section « Antiparasitaires » du carnet (pas les
      // traitements), une ligne à la date du jour.
      if (t.type == 'antiparasitaire') {
        try {
          await _supa.from('antiparasitaires').insert({
            'id': DateTime.now().microsecondsSinceEpoch.toString(),
            'animal_id': animalId, 'produit': t.nom,
            'date': ymd(today),
            'frequence': t.posologieComplete,
            if (t.notes.isNotEmpty) 'notes': t.notes,
            'source': 'veterinaire',
            if (vetId != null) 'vet_id': vetId,
          });
        } catch (e) { erreurs.add('antiparasitaire ${t.nom}'); }
        continue;
      }
      var debut = DateTime(today.year, today.month, today.day, today.hour, today.minute);
      for (var i = 0; i < t.phases.length; i++) {
        final ph = t.phases[i];
        final fin = ph.dureeJours != null ? debut.add(Duration(days: ph.dureeJours!)) : null;
        final cles = _prisesTriees(ph.prises);
        final heures = [for (final k in cles) _heurePrise(k)];
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
              // Dose de CHAQUE prise (1 cp le matin, ½ cp le soir) : la
              // notification au propriétaire dit la bonne quantité.
              if (ph.doses.isNotEmpty) 'rappel_quantites': [for (final k in cles) ph.doseDe(k)],
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
  /// [depuisRappel] : rappel à faire (vaccin précédent) — même vaccin, même
  /// intervalle jusqu'au prochain rappel.
  Future<void> _ajouterVaccin([_VaccinCr? existant, Map<String, dynamic>? depuisRappel]) async {
    final nomCtrl = TextEditingController(text: existant?.nom ?? depuisRappel?['vaccin']?.toString() ?? '');
    final lotCtrl = TextEditingController(text: existant?.lot ?? '');
    final nomFocus = FocusNode();
    final date = existant?.date ?? DateTime.now();
    DateTime? rappel = existant == null ? DateTime(date.year + 1, date.month, date.day) : existant.rappel;
    if (depuisRappel != null) {
      final d0 = DateTime.tryParse((depuisRappel['date'] ?? '').toString());
      final r0 = DateTime.tryParse((depuisRappel['date_rappel'] ?? '').toString());
      if (d0 != null && r0 != null && r0.isAfter(d0)) rappel = date.add(r0.difference(d0));
    }
    // Délai libre jusqu'au prochain rappel (en plus des durées proposées).
    final dansCtrl = TextEditingController();
    var dansUnite = 'mois';
    final res = await showModalBottomSheet<_VaccinCr>(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setM) {
        Widget chipRappel(String l, DateTime? d) => ChoiceChip(
          label: Text(l, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
          selected: d == null ? rappel == null : (rappel != null && rappel!.difference(d).inDays.abs() < 1),
          selectedColor: widget.categoryColor.withValues(alpha: 0.18),
          onSelected: (_) => setM(() { rappel = d; dansCtrl.clear(); }));
        void appliquerDelai() {
          final n = int.tryParse(dansCtrl.text.trim());
          if (n != null && n > 0) rappel = _ajouterDelai(date, n, dansUnite);
        }
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
            const SizedBox(height: 10),
            _saisieDelai(
              libelle: 'Ou dans', ctrl: dansCtrl, unite: dansUnite, unites: const ['jours', 'semaines', 'mois', 'ans'],
              onChange: () => setM(appliquerDelai),
              onUnite: (u) => setM(() { dansUnite = u; appliquerDelai(); }),
            ),
            if (rappel != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Rappel le ${_jjmmaaaa(rappel!)}',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w600, color: widget.categoryColor)),
              ),
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
              if (!p.dosesParPrise)
                TextField(controller: p.dose, decoration: _inputDeco('ex. 1 cp, ½ cp, 2 mL, 1 pipette').copyWith(labelText: 'Dose par prise')),
              const SizedBox(height: 8),
              // Moments proposés (avec l'heure du rappel) + heures libres.
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final pr in _kPrises.entries) FilterChip(
                  label: Text('${pr.value.$1} · ${_heureCourte(pr.value.$2)}', style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                  selected: p.prises.contains(pr.key), selectedColor: widget.categoryColor.withValues(alpha: 0.18),
                  onSelected: (v) => setM(() => v ? p.prises.add(pr.key) : p.prises.remove(pr.key))),
                for (final k in _prisesTriees(p.prises)) if (!_kPrises.containsKey(k)) InputChip(
                  label: Text(_nomPrise(k), style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                  selected: true, selectedColor: widget.categoryColor.withValues(alpha: 0.18), showCheckmark: false,
                  onDeleted: () => setM(() => p.prises.remove(k))),
                ActionChip(
                  avatar: Icon(Icons.add, size: 16, color: widget.categoryColor),
                  label: Text('Autre heure', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: widget.categoryColor)),
                  onPressed: () async {
                    final t = await showTimePicker(context: ctx, initialTime: const TimeOfDay(hour: 21, minute: 0),
                        helpText: 'Heure de la prise');
                    if (t == null) return;
                    setM(() => p.prises.add('${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'));
                  },
                ),
              ]),
              // Dose propre à chaque prise (1 cp le matin, ½ cp le soir…).
              if (p.prises.length > 1)
                CheckboxListTile(
                  dense: true, contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading,
                  value: p.dosesParPrise, activeColor: widget.categoryColor,
                  title: const Text('Dose différente selon la prise', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
                  onChanged: (v) => setM(() => p.basculerDoses(v == true)),
                ),
              // Une ligne par prise : moment + heure à gauche, dose à droite.
              if (p.dosesParPrise && p.prises.length > 1)
                for (final k in _prisesTriees(p.prises))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      SizedBox(width: 118, child: Text('${_nomPrise(k)} · ${_heureCourte(_heurePrise(k))}',
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600))),
                      Expanded(child: TextField(controller: p.doseCtrl(k),
                          decoration: _inputDeco('ex. 1 cp, ½ cp').copyWith(labelText: 'Dose'))),
                    ]),
                  ),
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
              // Durée libre (jours / semaines / mois) ou durées courantes.
              _saisieDelai(
                libelle: 'Pendant', ctrl: p.dureeNb, unite: p.unite, unites: const ['jours', 'semaines', 'mois'],
                onChange: () => setM(p.majDuree),
                onUnite: (u) => setM(() { p.unite = u; p.majDuree(); }),
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final d in [3, 5, 7, 10, 14]) chip('$d j', p.duree.text == '$d', () => setM(() => p.jours(d))),
              ]),
              if (i == phases.length - 1)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: TextButton(
                    onPressed: () => setM(() => p.jours(null)),
                    child: Text(p.duree.text.isEmpty ? '✓ Au long cours' : 'Au long cours (sans fin)',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: widget.categoryColor)),
                  ),
                ),
              // Rythme impossible : une prise tous les 100 jours pendant 17 jours.
              if (_rythmeImpossible(p))
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFFFDECEC), borderRadius: BorderRadius.circular(8)),
                  child: Text('Une prise tous les ${p.frequence} jours ne tient pas dans ${p.duree.text} jours de traitement '
                      '— le rythme doit être inférieur ou égal à la durée.',
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFFB71C1C))),
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
            const AideEtapes(phase: true),
            for (var i = 0; i < phases.length; i++) phase(i),
            OutlinedButton.icon(
              onPressed: () => setM(() {
                final der = phases.last;
                phases.add(_PhaseEdit.de(_PhaseCr(dose: '', prises: {...der.prises}, frequenceJours: der.frequence,
                    dureeJours: int.tryParse(der.duree.text))));
                if (der.duree.text.isEmpty) der.jours(3);
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
              subtitle: const Text('À l\'heure de chaque prise choisie, jusqu\'à la fin du traitement.', style: TextStyle(fontFamily: 'Galey', fontSize: 11.5)),
            ),
            TextField(controller: notesCtrl, decoration: _inputDeco('Précautions, à jeun, pendant le repas…').copyWith(labelText: 'Remarque (facultatif)')),
            const SizedBox(height: 18),
            SizedBox(width: double.infinity, child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: widget.categoryColor, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: nomCtrl.text.trim().isEmpty || phases.any((p) => p.prises.isEmpty || _rythmeImpossible(p)) ? null : () => Navigator.pop(ctx, _TraitementCr(
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

  /// Phase dont le rythme dépasse la durée (au long cours : pas de limite).
  static bool _rythmeImpossible(_PhaseEdit p) {
    final duree = int.tryParse(p.duree.text.trim());
    return duree != null && duree > 0 && p.frequence > duree;
  }

  static const _antiparasitairesCourants = ['Bravecto', 'NexGard', 'NexGard Spectra', 'Simparica', 'Simparica Trio',
      'Credelio', 'Advocate', 'Stronghold', 'Frontline', 'Broadline', 'Milbemax', 'Drontal', 'Milpro', 'Profender',
      'Seresto (collier)', 'Scalibor (collier)'];
  static const _medicamentsCourants = ['Metacam (méloxicam)', 'Previcox', 'Onsior', 'Rimadyl', 'Synulox', 'Clavaseptin',
      'Kesium', 'Marbocyl', 'Convenia', 'Prednisolone', 'Cortavance', 'Apoquel', 'Cytopoint', 'Vetmedin', 'Fortekor',
      'Cerenia', 'Gabapentine', 'Tramadol', 'Forthyron', 'Cardalis'];

  /// « Dans / Pendant [N] [unité] » — saisie libre d'un délai.
  Widget _saisieDelai({required String libelle, required TextEditingController ctrl, required String unite,
      required List<String> unites, required VoidCallback onChange, required ValueChanged<String> onUnite}) {
    return Row(children: [
      Text(libelle, style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
      const SizedBox(width: 8),
      SizedBox(width: 70, child: TextField(
        controller: ctrl, keyboardType: TextInputType.number, textAlign: TextAlign.center,
        decoration: _inputDeco('').copyWith(contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8)),
        onChanged: (_) => onChange(),
      )),
      const SizedBox(width: 8),
      DropdownButton<String>(
        value: unite, underline: const SizedBox.shrink(),
        style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF1E2025)),
        items: [for (final u in unites) DropdownMenuItem(value: u, child: Text(u))],
        onChanged: (u) { if (u != null) onUnite(u); },
      ),
    ]);
  }

  static DateTime _ajouterDelai(DateTime d, int n, String unite) => switch (unite) {
        'jours' => d.add(Duration(days: n)),
        'semaines' => d.add(Duration(days: 7 * n)),
        'ans' => DateTime(d.year + n, d.month, d.day),
        _ => DateTime(d.year, d.month + n, d.day),
      };

  static String _jjmmaaaa(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

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
    List<_ProduitCr> produits = const [],
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
    // 4. Produits vendus (non administrés) : quantité + prix saisi, sinon prix de vente du stock.
    for (final p in produits) {
      final ttc = p.prixTTC ?? prixPharmacie(p.nom);
      lignes.add(FacturePrefillLigne(designation: p.nom, prixHT: ttc == null ? 0 : _ht(ttc), quantite: p.quantite, tauxTVA: 20));
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
          // Aucune grille saisie : les prix sont à 0 → lien direct vers « Mes tarifs ».
          if (tarifs.values.every((v) => (double.tryParse('${v ?? ''}'.replaceAll(',', '.')) ?? 0) == 0)) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              decoration: BoxDecoration(color: const Color(0xFFFFF4E0), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Expanded(child: Text('Vos tarifs ne sont pas encore renseignés : les prix sont à compléter.',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Color(0xFF8A5A00)))),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx, false);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => ProProfileEditPage(
                        secondaryProfileId: _profilPro, allerAuxTarifs: true)));
                  },
                  child: Text('Saisir mes tarifs', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: widget.categoryColor)),
                ),
              ]),
            ),
          ],
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

    // Client : propriétaire PetsMatch (coordonnées de facturation selon
    // particulier / élevage / association — pm_client_facturation), sinon
    // fichier de la clinique, sinon RDV.
    String? prenom, nom, email, tel, rue, cp, ville;
    String? vide(dynamic v) => (v?.toString().trim() ?? '').isEmpty ? null : v.toString().trim();
    try {
      // Client du RDV (co-propriétaire qui a amené l'animal) si connu.
      final j = await _supa.rpc('pm_client_facturation', params: {
        'p_animal_id': animalId,
        if ((owner.profileId ?? '').isNotEmpty) 'p_client_profile_id': owner.profileId,
      });
      if (j is Map && (vide(j['nom']) != null || vide(j['prenom']) != null)) {
        prenom = vide(j['prenom']); nom = vide(j['nom']);
        email = vide(j['email']); tel = vide(j['telephone']);
        rue = vide(j['rue']); cp = vide(j['code_postal']); ville = vide(j['ville']);
      }
    } catch (_) {}
    if (nom == null && an?['client_clinique_id'] != null) {
      try {
        final c = await _supa.from('clients_clinique').select('nom, prenom, email, telephone, adresse, code_postal, ville')
            .eq('id', an!['client_clinique_id']).maybeSingle();
        prenom = vide(c?['prenom']); nom = vide(c?['nom']);
        email = vide(c?['email']); tel = vide(c?['telephone']);
        rue = vide(c?['adresse']); cp = vide(c?['code_postal']); ville = vide(c?['ville']);
      } catch (_) {}
    }
    final r = widget.rdv ?? _rdvSource;
    nom ??= widget.clientName.isNotEmpty ? widget.clientName : r?['client_nom_manuel']?.toString();
    email ??= r?['client_email_manuel']?.toString();
    tel ??= r?['client_telephone_manuel']?.toString();
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CreerFacturePage(
      clientPrenom: prenom, clientNom: nom, clientEmail: email, clientTel: tel,
      clientRue: rue, clientCp: cp, clientVille: ville,
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
    final carnetJour = _carnetJour.isEmpty ? <Widget>[] : [
      _inputLabel('Déjà inscrit au carnet aujourd’hui'),
      const SizedBox(height: 6),
      Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(color: widget.categoryColor.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12),
            border: Border.all(color: widget.categoryColor.withValues(alpha: 0.25))),
        child: Column(children: [
          for (final a in List.of(_carnetJour))
            ListTile(
              dense: true,
              leading: Icon(switch (a.type) {
                'vaccin' => Icons.vaccines_outlined,
                'traitement' => Icons.medication_outlined,
                _ => Icons.pest_control_outlined,
              }, color: widget.categoryColor),
              title: Text('${_libCarnet[a.type]} : ${a.libelle}',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, fontWeight: FontWeight.w600)),
              subtitle: Text('Repris dans ce compte rendu', style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade700)),
              trailing: IconButton(
                tooltip: 'Ne pas reprendre',
                icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                onPressed: () => setState(() => _carnetJour.remove(a)),
              ),
            ),
        ]),
      ),
    ];
    final aujourdhui = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final rappelsAFaire = _rappelsVaccins.where((r) =>
        !_vaccinsCr.any((v) => v.nom.toLowerCase() == (r['vaccin'] ?? '').toString().toLowerCase())).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ...carnetJour,
      if (rappelsAFaire.isNotEmpty) ...[
        _inputLabel('Rappels de vaccins à faire'),
        const SizedBox(height: 6),
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(color: const Color(0xFFFFF7EC), borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF0D9B5))),
          child: Column(children: [
            for (final r in rappelsAFaire)
              () {
                final dr = DateTime.parse(r['date_rappel'].toString());
                final j = DateTime(dr.year, dr.month, dr.day).difference(aujourdhui).inDays;
                final enRetard = j < 0;
                return ListTile(
                  dense: true,
                  leading: Icon(Icons.vaccines_outlined, color: enRetard ? Colors.red.shade700 : const Color(0xFFA85A12)),
                  title: Text((r['vaccin'] ?? r['categorie'] ?? 'Vaccin').toString(),
                      style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5, fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      enRetard
                          ? 'En retard depuis le ${date(dr)}'
                          : j == 0 ? 'Rappel aujourd\u2019hui' : 'Rappel le ${date(dr)} (dans $j j)',
                      style: TextStyle(fontFamily: 'Galey', fontSize: 11.5,
                          color: enRetard ? Colors.red.shade700 : Colors.grey.shade700)),
                  trailing: IconButton(
                    tooltip: 'Faire le rappel',
                    icon: Icon(Icons.add_circle_outline, color: widget.categoryColor),
                    onPressed: () => _ajouterVaccin(null, r),
                  ),
                );
              }(),
          ]),
        ),
      ],
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
      const SizedBox(height: 14),
      _inputLabel('Autres soins (inscrits au carnet)'),
      const SizedBox(height: 6),
      for (final s in List.of(_soinsCr)) ligne(_SoinCr.icones[s.type] ?? Icons.healing_outlined,
          '${_SoinCr.libelles[s.type]} : ${s.nom}',
          [if (s.detail.isNotEmpty) s.detail, if (s.rappelMois != null) 'rappel dans ${s.rappelMois} mois'].join(' · '),
          () => _ajouterSoin(s), () => setState(() => _soinsCr.remove(s))),
      OutlinedButton.icon(
        onPressed: () => _ajouterSoin(), icon: const Icon(Icons.add, size: 18),
        label: const Text('Ajouter un soin (vermifuge, allergie, chirurgie, examen…)', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
        style: OutlinedButton.styleFrom(foregroundColor: widget.categoryColor, side: BorderSide(color: widget.categoryColor.withValues(alpha: 0.5)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      ),
      const SizedBox(height: 14),
      _inputLabel('Produits vendus (non administrés)'),
      const SizedBox(height: 6),
      for (final p in List.of(_produitsCr)) ligne(Icons.shopping_bag_outlined, p.libelle,
          p.prixTTC == null ? 'Prix du stock ou à compléter sur la facture' : '${(p.prixTTC! * p.quantite).toStringAsFixed(2)} € TTC',
          () => _ajouterProduit(p), () => setState(() => _produitsCr.remove(p))),
      OutlinedButton.icon(
        onPressed: () => _ajouterProduit(), icon: const Icon(Icons.add, size: 18),
        label: const Text('Ajouter un produit vendu', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
        style: OutlinedButton.styleFrom(foregroundColor: widget.categoryColor, side: BorderSide(color: widget.categoryColor.withValues(alpha: 0.5)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      ),
      const SizedBox(height: 4),
      Text('Ajoutés à la facture et décomptés du stock à l’enregistrement ; pas inscrits au carnet.',
          style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
      const SizedBox(height: 16),
    ]);
  }

  /// Ajout (ou modification si [existant]) d'un soin inscrit au carnet à
  /// l'enregistrement, dans sa rubrique (vermifuge, antiparasitaire, allergie,
  /// chirurgie / hospitalisation, radio / examen).
  Future<void> _ajouterSoin([_SoinCr? existant]) async {
    var type = existant?.type ?? 'vermifuge';
    final nomCtrl = TextEditingController(text: existant?.nom ?? '');
    final nomFocus = FocusNode();
    final detailCtrl = TextEditingController(text: existant?.detail ?? '');
    int? rappelMois = existant?.rappelMois;
    const avecRappel = {'vermifuge', 'antiparasitaire'};
    String labelNom() => switch (type) {
          'allergie' => 'Allergie / pathologie *',
          'chirurgie' || 'hospitalisation' => 'Intervention *',
          'radio' => 'Examen (radio, échographie, prise de sang…) *',
          _ => 'Produit *',
        };
    String labelDetail() => switch (type) {
          'vermifuge' => 'Dosage (facultatif)',
          'antiparasitaire' => 'Fréquence / posologie (facultatif)',
          'allergie' => 'Sévérité (facultatif)',
          'radio' => 'Résultats / observations (facultatif)',
          _ => 'Notes (facultatif)',
        };
    final res = await showModalBottomSheet<_SoinCr>(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setM) {
        ChoiceChip chip(String l, bool sel, VoidCallback onTap) => ChoiceChip(
          label: Text(l, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)), selected: sel,
          selectedColor: widget.categoryColor.withValues(alpha: 0.18), onSelected: (_) => onTap());
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(existant == null ? 'Soin à inscrire au carnet' : 'Modifier le soin',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in _SoinCr.libelles.entries)
                chip(e.value, type == e.key, () => setM(() { type = e.key; if (!avecRappel.contains(type)) rappelMois = null; })),
            ]),
            const SizedBox(height: 12),
            if (type == 'vermifuge' || type == 'antiparasitaire')
              _champPharmacie(
                ctrl: nomCtrl, focus: nomFocus, label: labelNom(),
                filtre: (o) => o['categorie'] != 'vaccin' && o['categorie'] != 'alimentation',
                courants: type == 'antiparasitaire' ? _antiparasitairesCourants : const [],
                onChoix: (o) => setM(() => nomCtrl.text = o['nom']?.toString() ?? ''),
                onChange: () => setM(() {}),
              )
            else
              TextField(controller: nomCtrl, textCapitalization: TextCapitalization.sentences,
                  decoration: _inputDeco('').copyWith(labelText: labelNom()), onChanged: (_) => setM(() {})),
            const SizedBox(height: 10),
            TextField(controller: detailCtrl, textCapitalization: TextCapitalization.sentences, maxLines: type == 'radio' ? 3 : 1,
                decoration: _inputDeco('').copyWith(labelText: labelDetail())),
            if (avecRappel.contains(type)) ...[
              const SizedBox(height: 12),
              const Text('Prochain rappel (le propriétaire sera prévenu)', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final m in const [null, 1, 3, 6, 12])
                  chip(m == null ? 'Aucun' : m == 12 ? '1 an' : '$m mois', rappelMois == m, () => setM(() => rappelMois = m)),
              ]),
            ],
            const SizedBox(height: 18),
            SizedBox(width: double.infinity, child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: widget.categoryColor, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: nomCtrl.text.trim().isEmpty ? null
                  : () => Navigator.pop(ctx, _SoinCr(type, nomCtrl.text.trim(), detailCtrl.text.trim(), rappelMois)),
              child: Text(existant == null ? 'Ajouter' : 'Enregistrer', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
            )),
          ])),
        );
      }),
    );
    if (res == null) return;
    setState(() {
      final i = existant == null ? -1 : _soinsCr.indexOf(existant);
      if (i >= 0) { _soinsCr[i] = res; } else { _soinsCr.add(res); }
    });
  }

  /// Ajout (ou modification si [existant]) d'un produit vendu : depuis le
  /// stock (prix de vente repris) ou saisi librement avec son prix.
  Future<void> _ajouterProduit([_ProduitCr? existant]) async {
    final nomCtrl = TextEditingController(text: existant?.nom ?? '');
    final nomFocus = FocusNode();
    final qteCtrl = TextEditingController(text: existant == null ? '1' : _fmtQ(existant.quantite));
    final prixCtrl = TextEditingController(text: existant?.prixTTC == null ? '' : existant!.prixTTC!.toStringAsFixed(2).replaceAll('.', ','));
    String? itemId = existant?.itemId;
    String? stock;
    double? nombre(String t) => double.tryParse(t.trim().replaceAll(',', '.').replaceAll(' ', ''));
    final res = await showModalBottomSheet<_ProduitCr>(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setM) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(existant == null ? 'Produit vendu' : 'Modifier le produit',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Délivré au client, non administré : facturé et décompté du stock.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          _champPharmacie(
            ctrl: nomCtrl, focus: nomFocus, label: 'Produit (stock ou saisie libre) *',
            filtre: (o) => o['categorie'] != 'vaccin',
            onChoix: (o) => setM(() {
              nomCtrl.text = o['nom']?.toString() ?? '';
              itemId = o['id']?.toString();
              final pv = (o['prix_vente'] as num?)?.toDouble();
              if (pv != null) prixCtrl.text = pv.toStringAsFixed(2).replaceAll('.', ',');
              stock = o['quantite'] == null ? null : 'En stock : ${o['quantite']} ${o['unite'] ?? ''}'.trim();
            }),
            onChange: () => setM(() { itemId = null; stock = null; }),
          ),
          if (stock != null) Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(stock!, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade700)),
          ),
          const SizedBox(height: 10),
          Row(children: [
            SizedBox(width: 110, child: TextField(controller: qteCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _inputDeco('1').copyWith(labelText: 'Quantité'), onChanged: (_) => setM(() {}))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: prixCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _inputDeco('ex. 24,90').copyWith(labelText: 'Prix unitaire TTC (€)'), onChanged: (_) => setM(() {}))),
          ]),
          const SizedBox(height: 18),
          SizedBox(width: double.infinity, child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: widget.categoryColor, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: nomCtrl.text.trim().isEmpty || (nombre(qteCtrl.text) ?? 0) <= 0 ? null
                : () => Navigator.pop(ctx, _ProduitCr(nomCtrl.text.trim(), nombre(qteCtrl.text)!, nombre(prixCtrl.text), itemId)),
            child: Text(existant == null ? 'Ajouter' : 'Enregistrer', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
          )),
        ])),
      )),
    );
    if (res == null) return;
    setState(() {
      final i = existant == null ? -1 : _produitsCr.indexOf(existant);
      if (i >= 0) { _produitsCr[i] = res; } else { _produitsCr.add(res); }
    });
  }

  /// Produits vendus pris dans le stock : sortie enregistrée (mouvement
  /// « consommation ») et quantité mise à jour.
  Future<void> _decompterStock(List<_ProduitCr> produits) async {
    final pro = _profilPro;
    final uid = AgendaContexte.uid;
    if (pro == null || uid == null) return;
    for (final p in produits) {
      if (p.itemId == null) continue;
      try {
        final item = await _supa.from('inventaire_items').select('quantite, stupefiant').eq('id', p.itemId!).maybeSingle();
        if (item == null) continue;
        final avant = (item['quantite'] as num?)?.toDouble() ?? 0;
        final apres = (avant - p.quantite).clamp(0.0, double.infinity);
        await _supa.from('inventaire_mouvements').insert({
          'item_id': p.itemId, 'uid_eleveur': uid, 'uid_auteur': AgendaContexte.moi ?? uid,
          'eleveur_profile_id': pro, 'type': 'consommation', 'quantite': p.quantite,
          'note': 'Vente — consultation',
          if (item['stupefiant'] == true) 'stock_apres': apres,
        });
        await _supa.from('inventaire_items').update({'quantite': apres}).eq('id', p.itemId!);
      } catch (_) {}
    }
    await _chargerPharmacie();
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
      animalId: (cr['animal_id'] ?? widget.animalId ?? widget.rdv?['animal_id'])?.toString(),
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
      animalId: (o['animal_id'] ?? widget.animalId ?? widget.rdv?['animal_id'])?.toString(),
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
      await _notifyOwner(isOrdo: false, crId: cr['id']?.toString());
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
  Future<void> _notifyOwner({required bool isOrdo, String? crId}) async {
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
        'data': {'animalId': animalId, 'animalNom': animalNom, if (!isOrdo && crId != null) 'crId': crId},
        'read': false,
      });
    } catch (_) {}
  }

  /// Dernier compte rendu de cet animal par ce profil (lien direct de la notification).
  Future<String?> _dernierCrId() async {
    final animalId = (widget.animalId ?? widget.rdv?['animal_id'])?.toString();
    if (animalId == null) return null;
    try {
      var q = _supa.from('comptes_rendus').select('id').eq('animal_id', animalId);
      q = _profilPro != null ? q.eq('pro_profile_id', _profilPro!) : q.eq('pro_uid', AgendaContexte.uid ?? '');
      final r = await q.order('created_at', ascending: false).limit(1).maybeSingle();
      return r?['id']?.toString();
    } catch (_) {
      return null;
    }
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
                // Brouillon du vétérinaire (saisie gardée) : repris dans le
                // formulaire ; brouillon d'ASV : validé tel quel.
                onValider: (cr['statut'] == 'brouillon' && _peutValider && cr['brouillon'] == null) ? () => _validerCr(cr) : null,
                onReprendre: (cr['statut'] == 'brouillon' && cr['brouillon'] != null && cr['id']?.toString() != _brouillonId)
                    ? () => _reprendreBrouillon(cr) : null,
                onFacturer: (_saisieActes && cr['statut'] != 'brouillon') ? () => _facturerCr(cr) : null)),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 8),
          ],

          _sectionTitle(_brouillonId != null ? 'Brouillon en cours de modification' : 'Nouveau compte rendu'),
          if (_brouillonId != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _abandonnerBrouillon,
                child: Text('Fermer sans enregistrer', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade700)),
              ),
            ),
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
          if (_saisieActes) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _crSaving ? null : () => _saveCompteRendu(enBrouillon: true),
                icon: const Icon(Icons.edit_note_outlined),
                label: const Text('Enregistrer en brouillon', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: widget.categoryColor,
                  side: BorderSide(color: widget.categoryColor),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text('Non visible du propriétaire ; vous pourrez le reprendre et le modifier.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
          ],
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

/// Soin du compte rendu inscrit au carnet dans sa rubrique.
class _SoinCr {
  /// vermifuge | antiparasitaire | allergie | chirurgie | hospitalisation | radio
  final String type;
  final String nom;
  final String detail;
  /// Vermifuge / antiparasitaire : prochain rappel dans N mois.
  final int? rappelMois;
  _SoinCr(this.type, this.nom, this.detail, [this.rappelMois]);

  static const libelles = {
    'vermifuge': 'Vermifuge', 'antiparasitaire': 'Antiparasitaire', 'allergie': 'Allergie / pathologie',
    'chirurgie': 'Chirurgie', 'hospitalisation': 'Hospitalisation', 'radio': 'Radio / examen',
  };
  static const icones = {
    'vermifuge': Icons.bug_report_outlined, 'antiparasitaire': Icons.pest_control_outlined,
    'allergie': Icons.warning_amber_outlined, 'chirurgie': Icons.local_hospital_outlined,
    'hospitalisation': Icons.local_hospital_outlined, 'radio': Icons.image_search_outlined,
  };
  String get libelle => detail.isEmpty ? nom : '$nom ($detail)';
  Map<String, dynamic> toJson() => {'type': type, 'nom': nom, 'detail': detail, if (rappelMois != null) 'rappel_mois': rappelMois};
  factory _SoinCr.fromJson(Map<String, dynamic> j) => _SoinCr((j['type'] ?? 'vermifuge').toString(),
      (j['nom'] ?? '').toString(), (j['detail'] ?? '').toString(), (j['rappel_mois'] as num?)?.toInt());
}

/// Produit vendu pendant la consultation (non administré : pas au carnet).
class _ProduitCr {
  final String nom;
  final double quantite;
  /// Prix unitaire TTC saisi (null : prix de vente du stock, sinon à compléter).
  final double? prixTTC;
  /// Article de l'inventaire (décompté du stock), null si saisi librement.
  final String? itemId;
  _ProduitCr(this.nom, this.quantite, this.prixTTC, this.itemId);

  String get libelle => quantite == 1 ? nom : '$nom ×${_fmtQ(quantite)}';
  Map<String, dynamic> toJson() => {'nom': nom, 'quantite': quantite, 'prix': prixTTC, if (itemId != null) 'item_id': itemId};
  factory _ProduitCr.fromJson(Map<String, dynamic> j) => _ProduitCr((j['nom'] ?? '').toString(),
      (j['quantite'] as num?)?.toDouble() ?? 1, (j['prix'] as num?)?.toDouble(), j['item_id']?.toString());
}

String _fmtQ(double q) => q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toString().replaceAll('.', ',');

class _VaccinCr {
  final String nom, lot;
  final DateTime date;
  final DateTime? rappel;
  _VaccinCr(this.nom, this.lot, this.date, this.rappel);

  static String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  Map<String, dynamic> toJson() => {'nom': nom, 'lot': lot, 'date': _ymd(date), 'rappel': rappel == null ? null : _ymd(rappel!)};
  factory _VaccinCr.fromJson(Map<String, dynamic> j) => _VaccinCr((j['nom'] ?? '').toString(), (j['lot'] ?? '').toString(),
      DateTime.tryParse(j['date']?.toString() ?? '') ?? DateTime.now(), DateTime.tryParse(j['rappel']?.toString() ?? ''));
}

/// Prises de la journée → libellé + heure du rappel au propriétaire.
/// Une prise libre (plus de 3 par jour, horaire précis) est son heure « HH:MM ».
const _kPrises = <String, (String, String)>{
  'matin': ('Matin', '08:00'),
  'midi': ('Midi', '12:00'),
  'apres_midi': ('Après-midi', '16:00'),
  'soir': ('Soir', '19:00'),
  'coucher': ('Coucher', '22:00'),
};
String _heurePrise(String k) => _kPrises[k]?.$2 ?? k;
String _nomPrise(String k) => _kPrises[k]?.$1 ?? 'À ${_heureCourte(k)}';
/// « le matin » / « à 22 h 30 ».
String _quandPrise(String k) => _kPrises.containsKey(k) ? 'le ${_kPrises[k]!.$1.toLowerCase()}' : 'à ${_heureCourte(k)}';
List<String> _prisesTriees(Iterable<String> p) => p.toList()..sort((a, b) => _heurePrise(a).compareTo(_heurePrise(b)));
/// « 08:00 » → « 8 h », « 22:30 » → « 22 h 30 ».
String _heureCourte(String hhmm) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm);
  if (m == null) return hhmm;
  return '${int.parse(m.group(1)!)} h${m.group(2) == '00' ? '' : ' ${m.group(2)}'}';
}

/// Phase d'un traitement (dégressif : plusieurs phases enchaînées).
class _PhaseCr {
  final String dose;
  final Set<String> prises;
  final int frequenceJours;
  final int? dureeJours;
  /// Dose propre à chaque prise (clé de [_kPrises]) — vide : [dose] partout.
  final Map<String, String> doses;
  const _PhaseCr({required this.dose, required this.prises, this.frequenceJours = 1, this.dureeJours, this.doses = const {}});

  String doseDe(String prise) => (doses[prise] ?? '').trim().isNotEmpty ? doses[prise]!.trim() : dose.trim();

  /// « 1 cp matin et soir, tous les 2 jours, pendant 3 jours » — ou
  /// « 1 cp le matin, ½ cp le soir, … » avec une dose par prise.
  String get libelle {
    final cles = _prisesTriees(prises);
    final noms = [for (final k in cles) _kPrises.containsKey(k) ? _kPrises[k]!.$1.toLowerCase() : 'à ${_heureCourte(k)}'];
    final quand = noms.length > 1 ? '${noms.sublist(0, noms.length - 1).join(', ')} et ${noms.last}' : noms.join();
    return [
      if (doses.isNotEmpty)
        [for (final k in cles) [doseDe(k), _quandPrise(k)].where((x) => x.isNotEmpty).join(' ')].join(', ')
      else
        [if (dose.trim().isNotEmpty) dose.trim(), quand].where((x) => x.isNotEmpty).join(' '),
      if (frequenceJours > 1) 'tous les $frequenceJours jours',
      dureeJours != null ? 'pendant $dureeJours jour${dureeJours! > 1 ? 's' : ''}' : 'au long cours',
    ].join(', ');
  }
}

class _PhaseEdit {
  /// [duree] : durée en jours (stockée) ; [dureeNb] + [unite] : saisie.
  final TextEditingController dose, duree, frequenceCtrl;
  final Set<String> prises;
  late final TextEditingController dureeNb = TextEditingController(text: duree.text);
  String unite = 'jours';
  _PhaseEdit(this.dose, this.duree, this.frequenceCtrl, this.prises);
  int get frequence => (int.tryParse(frequenceCtrl.text.trim()) ?? 1).clamp(1, 365);
  static const _joursParUnite = {'jours': 1, 'semaines': 7, 'mois': 30};
  /// Saisie (nombre + unité) → durée en jours.
  void majDuree() {
    final n = int.tryParse(dureeNb.text.trim());
    duree.text = n == null || n <= 0 ? '' : '${n * _joursParUnite[unite]!}';
  }
  /// Durée courante en jours (null = au long cours).
  void jours(int? j) {
    duree.text = j?.toString() ?? '';
    dureeNb.text = duree.text;
    unite = 'jours';
  }
  /// Dose propre à chaque prise.
  bool dosesParPrise = false;
  final Map<String, TextEditingController> _doses = {};
  TextEditingController doseCtrl(String prise) => _doses.putIfAbsent(prise, () => TextEditingController(text: dose.text));
  void basculerDoses(bool v) {
    dosesParPrise = v;
    // Repli : la dose commune reprend la première dose saisie.
    if (!v && dose.text.trim().isEmpty) {
      dose.text = _doses.values.map((c) => c.text.trim()).firstWhere((t) => t.isNotEmpty, orElse: () => '');
    }
  }
  factory _PhaseEdit.de(_PhaseCr p) {
    final e = _PhaseEdit(TextEditingController(text: p.dose),
        TextEditingController(text: p.dureeJours?.toString() ?? ''),
        TextEditingController(text: '${p.frequenceJours}'), {...p.prises});
    if (p.doses.isNotEmpty) {
      e.dosesParPrise = true;
      p.doses.forEach((k, v) => e._doses[k] = TextEditingController(text: v));
    }
    return e;
  }
  _PhaseCr vers() {
    final doses = dosesParPrise && prises.length > 1
        ? {for (final k in prises) if (doseCtrl(k).text.trim().isNotEmpty) k: doseCtrl(k).text.trim()}
        : const <String, String>{};
    return _PhaseCr(dose: doses.isEmpty ? dose.text.trim() : '', prises: {...prises}, frequenceJours: frequence,
        dureeJours: int.tryParse(duree.text.trim()), doses: doses);
  }
}

class _TraitementCr {
  final String nom, type, notes;
  final List<_PhaseCr> phases;
  final bool rappels;
  _TraitementCr({required this.nom, required this.type, required this.phases, required this.rappels, this.notes = ''});

  Map<String, dynamic> toJson() => {
        'nom': nom, 'type': type, 'rappels': rappels, 'notes': notes,
        'phases': [for (final p in phases) {
          'dose': p.dose, 'prises': p.prises.toList(), 'frequenceJours': p.frequenceJours, 'dureeJours': p.dureeJours,
          if (p.doses.isNotEmpty) 'doses': p.doses,
        }],
      };
  factory _TraitementCr.fromJson(Map<String, dynamic> j) => _TraitementCr(
        nom: (j['nom'] ?? '').toString(), type: (j['type'] ?? 'medicament').toString(),
        rappels: j['rappels'] != false, notes: (j['notes'] ?? '').toString(),
        phases: [
          for (final p in (j['phases'] as List? ?? const []))
            _PhaseCr(
              dose: ((p as Map)['dose'] ?? '').toString(),
              prises: {for (final k in (p['prises'] as List? ?? const [])) k.toString()},
              frequenceJours: (p['frequenceJours'] as num?)?.toInt() ?? 1,
              dureeJours: (p['dureeJours'] as num?)?.toInt(),
              doses: {for (final e in ((p['doses'] as Map?) ?? const {}).entries) e.key.toString(): e.value.toString()},
            ),
        ],
      );

  /// Posologie de toutes les phases : « …, puis … ».
  String get posologieComplete => phases.map((p) => p.libelle).join(', puis ');
}

// ── Cards existants ──────────────────────────────────────────────────────────

class _CrCard extends StatelessWidget {
  final Map<String, dynamic> cr;
  final Color color;
  final VoidCallback? onDelete;
  final VoidCallback? onValider;
  /// Brouillon du vétérinaire : reprendre la saisie.
  final VoidCallback? onReprendre;
  /// CR validé : préparer la facture (si elle n'a pas été faite à l'enregistrement).
  final VoidCallback? onFacturer;
  /// Imprimer / partager / envoyer au propriétaire (CR validé).
  final VoidCallback? onTransmettre;
  const _CrCard({required this.cr, required this.color, this.onDelete, this.onValider, this.onReprendre, this.onFacturer, this.onTransmettre});

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
              child: Text(cr['brouillon'] != null ? 'Brouillon — non visible du propriétaire' : 'Brouillon — à valider',
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
        if (onFacturer != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: onFacturer,
              icon: const Icon(Icons.receipt_long_outlined, size: 16),
              label: const Text('Facturer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color)),
            ),
          ),
        ],
        if (onReprendre != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: onReprendre,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Reprendre le brouillon', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color)),
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
