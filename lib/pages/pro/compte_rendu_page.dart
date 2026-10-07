import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/utils/document_prive.dart';
import 'package:PetsMatch/utils/storage_helper.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/utils/contexte_pro.dart';

/// S06 — Pro : écrire un compte rendu et/ou créer une ordonnance après un RDV.
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
    final contenu = _crContenuCtrl.text.trim();
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
      });
      if (statut == 'valide') {
        await _notifyOwner(isOrdo: false);
      } else {
        await _notifyValideurs();
      }
      _crContenuCtrl.clear();
      setState(() => _crFile = null);
      await _loadExisting();
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
                onDelete: (cr['statut'] != 'brouillon' && !_peutValider)
                    ? null : () => _deleteDoc('comptes_rendus', cr['id'].toString()),
                onValider: (cr['statut'] == 'brouillon' && _peutValider) ? () => _validerCr(cr) : null)),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 8),
          ],

          _sectionTitle('Nouveau compte rendu'),
          const SizedBox(height: 12),

          // Contenu
          _inputLabel('Contenu *'),
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
            ..._ordos.map((o) => _OrdoCard(ordo: o, color: widget.categoryColor, onDelete: () => _deleteDoc('ordonnances', o['id'].toString()))),
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

// ── Cards existants ──────────────────────────────────────────────────────────

class _CrCard extends StatelessWidget {
  final Map<String, dynamic> cr;
  final Color color;
  final VoidCallback? onDelete;
  final VoidCallback? onValider;
  const _CrCard({required this.cr, required this.color, this.onDelete, this.onValider});

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
  const _OrdoCard({required this.ordo, required this.color, this.onDelete});

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
