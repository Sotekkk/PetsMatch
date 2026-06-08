import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  final _crDocUrlCtrl  = TextEditingController();
  bool _crSaving = false;

  // Ordonnance
  final _ordoDocUrlCtrl = TextEditingController();
  final _ordoNotesCtrl  = TextEditingController();
  bool _ordoSaving = false;

  // Existing docs
  List<Map<String, dynamic>> _crs    = [];
  List<Map<String, dynamic>> _ordos  = [];
  bool _loadingDocs = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: widget.isPension ? 1 : 2, vsync: this);
    _loadExisting();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _crContenuCtrl.dispose();
    _crDocUrlCtrl.dispose();
    _ordoDocUrlCtrl.dispose();
    _ordoNotesCtrl.dispose();
    super.dispose();
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
      if (rdvId != null) {
        crs   = await _supa.from('comptes_rendus').select().eq('rdv_id', rdvId).order('created_at');
        ordos = await _supa.from('ordonnances').select().eq('rdv_id', rdvId).order('created_at');
      } else {
        final vetUid = FirebaseAuth.instance.currentUser?.uid ?? '';
        final aid = animalId ?? '';
        crs   = await _supa.from('comptes_rendus').select()
            .eq('animal_id', aid).eq('pro_uid', vetUid).order('created_at');
        ordos = await _supa.from('ordonnances').select()
            .eq('animal_id', aid).eq('pro_uid', vetUid).order('created_at');
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
    final proUid  = FirebaseAuth.instance.currentUser?.uid;
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
    final ownerUid = widget.ownerUid ?? widget.rdv?['client_uid'];
    try {
      await _supa.from('comptes_rendus').insert({
        'pro_uid'   : proUid,
        'animal_id' : animalId,
        'owner_uid' : ownerUid,
        if (rdvId != null) 'rdv_id': rdvId,
        'contenu'   : contenu,
        if (_crDocUrlCtrl.text.trim().isNotEmpty) 'doc_url': _crDocUrlCtrl.text.trim(),
      });
      _crContenuCtrl.clear();
      _crDocUrlCtrl.clear();
      await _loadExisting();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Compte rendu enregistré.', style: TextStyle(fontFamily: 'Galey')),
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

  Future<void> _saveOrdonnance() async {
    final proUid = FirebaseAuth.instance.currentUser?.uid;
    final docUrl = _ordoDocUrlCtrl.text.trim();
    if (proUid == null || docUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('L\'URL du document est obligatoire.',
            style: TextStyle(fontFamily: 'Galey')),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _ordoSaving = true);
    final rdvId    = widget.rdv?['id'];
    final animalId = widget.animalId ?? widget.rdv?['animal_id'];
    final ownerUid = widget.ownerUid ?? widget.rdv?['client_uid'];
    try {
      final today = DateTime.now();
      await _supa.from('ordonnances').insert({
        'pro_uid'  : proUid,
        'animal_id': animalId,
        'owner_uid': ownerUid,
        if (rdvId != null) 'rdv_id': rdvId,
        'doc_url'  : docUrl,
        'date_emit': '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}',
        if (_ordoNotesCtrl.text.trim().isNotEmpty) 'notes': _ordoNotesCtrl.text.trim(),
      });
      _ordoDocUrlCtrl.clear();
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
            ..._crs.map((cr) => _CrCard(cr: cr, color: widget.categoryColor)),
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

          // URL document (optionnel)
          _inputLabel('Document joint (URL, optionnel)'),
          const SizedBox(height: 6),
          TextFormField(
            controller: _crDocUrlCtrl,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            decoration: _inputDeco('https://…'),
            keyboardType: TextInputType.url,
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
            ..._ordos.map((o) => _OrdoCard(ordo: o, color: widget.categoryColor)),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 8),
          ],

          _sectionTitle('Nouvelle ordonnance'),
          const SizedBox(height: 12),

          // URL document
          _inputLabel('URL du document *'),
          const SizedBox(height: 6),
          TextFormField(
            controller: _ordoDocUrlCtrl,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            decoration: _inputDeco('Lien vers l\'ordonnance (Firebase Storage, Drive…)'),
            keyboardType: TextInputType.url,
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
  const _CrCard({required this.cr, required this.color});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(cr['created_at']?.toString() ?? '');
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
        if (date != null)
          Text('${date.day}/${date.month}/${date.year}',
              style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
        const SizedBox(height: 6),
        Text(contenu,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 13, height: 1.4)),
        if (docUrl.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.attach_file, size: 13, color: color),
            const SizedBox(width: 4),
            Expanded(child: Text(docUrl, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: color))),
          ]),
        ],
      ]),
    );
  }
}

class _OrdoCard extends StatelessWidget {
  final Map<String, dynamic> ordo;
  final Color color;
  const _OrdoCard({required this.ordo, required this.color});

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
          Text('Ordonnance du $dateEmit',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13, color: color)),
        ]),
        if (docUrl.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(docUrl, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey)),
        ],
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(notes, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, height: 1.4)),
        ],
      ]),
    );
  }
}
