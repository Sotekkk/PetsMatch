import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/config.dart';
import 'package:PetsMatch/pages/eleveur/admin/certificats_engagement_page.dart';

class ContratReservationPage extends StatefulWidget {
  const ContratReservationPage({super.key});
  @override
  State<ContratReservationPage> createState() => _ContratReservationPageState();
}

class _ContratReservationPageState extends State<ContratReservationPage> {
  static const _teal  = Color(0xFF0C5C6C);
  static const _bg    = Color(0xFFF5F5F0);

  final _supa = Supabase.instance.client;

  List<Map<String, dynamic>> _docs    = [];
  List<Map<String, dynamic>> _animaux = [];
  Map<String, dynamic>?      _profil;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final [docs, animaux, profil] = await Future.wait([
      _supa.from('documents_animaux')
          .select()
          .eq('uid_eleveur', uid)
          .order('created_at', ascending: false),
      _supa.from('animaux')
          .select('id, nom, espece, race, identification, date_naissance, sexe')
          .eq('uid_eleveur', uid)
          .not('statut', 'in', '(sorti,decede)')
          .order('nom'),
      _supa.from('users')
          .select('firstname, lastname, name_elevage, is_elevage, adress_elevage, adress, rue, ville, code_postal, siret, email, numero_elevage, code_iso_elevage, phone_number, code_iso')
          .eq('uid', uid)
          .maybeSingle(),
    ]);
    if (!mounted) return;
    setState(() {
      _docs    = List<Map<String, dynamic>>.from(docs as List);
      _animaux = List<Map<String, dynamic>>.from(animaux as List);
      _profil  = profil as Map<String, dynamic>?;
      _loading = false;
    });
  }

  String get _eleveurNom {
    if (_profil == null) return '';
    final isElv = _profil!['is_elevage'] == true;
    return isElv
        ? (_profil!['name_elevage'] as String? ?? '${_profil!['firstname'] ?? ''} ${_profil!['lastname'] ?? ''}'.trim())
        : '${_profil!['firstname'] ?? ''} ${_profil!['lastname'] ?? ''}'.trim();
  }
  String get _eleveurAdresse {
    if (_profil == null) return '';
    final isElv = _profil!['is_elevage'] == true;
    return isElv
        ? (_profil!['adress_elevage'] as String? ?? [_profil!['rue'], _profil!['code_postal'], _profil!['ville']].whereType<String>().join(', '))
        : (_profil!['adress'] as String? ?? [_profil!['rue'], _profil!['code_postal'], _profil!['ville']].whereType<String>().join(', '));
  }
  String get _eleveurSiret  => _profil?['siret'] as String? ?? '';
  String get _eleveurEmail  => _profil?['email']  as String? ?? '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Contrats', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const CertificatsEngagementPage(),
            )),
            icon: const Icon(Icons.edit_document, color: Colors.white, size: 18),
            label: const Text('Certificats', style: TextStyle(fontFamily: 'Galey', color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nouveau', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
        onPressed: _animaux.isEmpty ? null : () => _showCreateSheet(context),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : RefreshIndicator(
              color: _teal,
              onRefresh: _load,
              child: _docs.isEmpty ? _emptyState(context) : _list(),
            ),
    );
  }

  Widget _emptyState(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.description_outlined, size: 64, color: Color(0xFFCCCCCC)),
      const SizedBox(height: 16),
      const Text('Aucun contrat', style: TextStyle(fontFamily: 'Galey', fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF888888))),
      const SizedBox(height: 6),
      const Text('Créez votre premier contrat\nen sélectionnant un animal',
          textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFFAAAAAA))),
      const SizedBox(height: 24),
      if (_animaux.isNotEmpty)
        ElevatedButton.icon(
          onPressed: () => _showCreateSheet(context),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Créer un contrat', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
    ]),
  );

  Widget _list() => ListView.separated(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
    itemCount: _docs.length,
    separatorBuilder: (_, __) => const SizedBox(height: 10),
    itemBuilder: (_, i) => _DocCard(doc: _docs[i], onDelete: _deleteDoc),
  );

  Future<void> _deleteDoc(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: const Text('Ce contrat sera définitivement supprimé.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    await _supa.from('documents_animaux').delete().eq('id', id);
    await _load();
  }

  Future<void> _showCreateSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateContratSheet(
        animaux: _animaux,
        eleveurNom: _eleveurNom,
        eleveurAdresse: _eleveurAdresse,
        eleveurSiret: _eleveurSiret,
        eleveurEmail: _eleveurEmail,
        supa: _supa,
        onSaved: _load,
      ),
    );
  }
}

// ── Carte document ────────────────────────────────────────────────────────────

class _DocCard extends StatelessWidget {
  final Map<String, dynamic> doc;
  final Future<void> Function(String) onDelete;

  const _DocCard({required this.doc, required this.onDelete});

  static const _teal = Color(0xFF0C5C6C);

  static const _typeLabel = {
    'contrat_vente':       ('🤝', 'Vente'),
    'contrat_reservation': ('🐾', 'Réservation'),
    'certificat_cession':  ('📋', 'Cession'),
    'contrat_saillie':     ('💞', 'Saillie'),
  };
  static const _statutColor = {
    'brouillon':          Color(0xFFEEEEEE),
    'en_attente':         Color(0xFFFEF3C7),
    'partiellement_signe':Color(0xFFDBEAFE),
    'signe':              Color(0xFFDCF5E4),
    'archive':            Color(0xFFFFF3CD),
    'annule':             Color(0xFFFEE2E2),
    'expire':             Color(0xFFFFEDD5),
    'refuse':             Color(0xFFFEE2E2),
  };
  static const _statutLabel = {
    'brouillon':          'Brouillon',
    'en_attente':         '⏳ En attente',
    'partiellement_signe':'✍️ Partiel',
    'signe':              '✅ Signé',
    'archive':            'Archivé',
    'annule':             '🚫 Annulé',
    'expire':             '⏰ Expiré',
    'refuse':             '❌ Refusé',
  };

  @override
  Widget build(BuildContext context) {
    final type        = doc['type'] as String? ?? 'contrat_vente';
    final statut      = doc['statut'] as String? ?? 'brouillon';
    final meta        = _typeLabel[type] ?? ('📄', 'Contrat');
    final metaMap     = (doc['metadata'] as Map<String, dynamic>?) ?? {};
    final acqNom      = (metaMap['acquereur_nom'] as String?) ?? '';
    final titre       = doc['titre'] as String? ?? 'Contrat';
    final token       = doc['token'] as String?;
    final pdfSigneUrl = doc['pdf_signe_url'] as String?;
    final date   = doc['created_at'] != null
        ? DateTime.tryParse(doc['created_at'] as String)?.toLocal()
        : null;
    final signingUrl = token != null ? '$kSiteBaseUrl/signer-contrat/$token' : null;
    final isFinal    = ['signe', 'annule', 'expire', 'refuse'].contains(statut);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(color: const Color(0xFFEEF5EA), borderRadius: BorderRadius.circular(10)),
            child: Center(child: Text(meta.$1, style: const TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titre, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1F2A2E)), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: _statutColor[statut] ?? const Color(0xFFEEEEEE), borderRadius: BorderRadius.circular(20)),
                child: Text(_statutLabel[statut] ?? statut, style: const TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w600)),
              ),
              if (acqNom.isNotEmpty) ...[
                const SizedBox(width: 6),
                Flexible(child: Text('→ $acqNom', style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF888888)), overflow: TextOverflow.ellipsis)),
              ],
              if (date != null) ...[
                const SizedBox(width: 6),
                Text('${date.day.toString().padLeft(2,'0')}/${date.month.toString().padLeft(2,'0')}/${date.year}',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 10, color: Color(0xFFAAAAAA))),
              ],
            ]),
          ])),
        ]),

        if (signingUrl != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse(signingUrl), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new, size: 15),
                label: const Text('Ouvrir sur le web', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _teal,
                  side: const BorderSide(color: _teal),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Copier lien
            if (!isFinal) ...[
              OutlinedButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: signingUrl));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Lien copié'), duration: Duration(seconds: 2)),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: _teal,
                  side: const BorderSide(color: _teal),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: const Icon(Icons.link, size: 16),
              ),
              const SizedBox(width: 8),
            ],
            // PREP07 — Télécharger PDF signé
            if (statut == 'signe' && pdfSigneUrl != null) ...[
              OutlinedButton(
                onPressed: () => launchUrl(Uri.parse(pdfSigneUrl), mode: LaunchMode.externalApplication),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6E9E57),
                  side: const BorderSide(color: Color(0xFF6E9E57)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: const Icon(Icons.download_outlined, size: 16),
              ),
              const SizedBox(width: 8),
            ],
            // PREP08 — Annuler
            if (!isFinal)
              OutlinedButton(
                onPressed: () => onDelete(doc['id'] as String),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.redAccent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: const Icon(Icons.delete_outline, size: 16),
              ),
          ]),
        ],
      ]),
    );
  }
}

// ── Bottom sheet création ─────────────────────────────────────────────────────

class _CreateContratSheet extends StatefulWidget {
  final List<Map<String, dynamic>> animaux;
  final String eleveurNom, eleveurAdresse, eleveurSiret, eleveurEmail;
  final dynamic supa;
  final VoidCallback onSaved;

  const _CreateContratSheet({
    required this.animaux, required this.eleveurNom, required this.eleveurAdresse,
    required this.eleveurSiret, required this.eleveurEmail,
    required this.supa, required this.onSaved,
  });

  @override
  State<_CreateContratSheet> createState() => _CreateContratSheetState();
}

class _CreateContratSheetState extends State<_CreateContratSheet> {
  static const _teal  = Color(0xFF0C5C6C);

  String _type = 'contrat_vente';
  Map<String, dynamic>? _selectedAnimal;
  bool _avecSteril = true;

  final _acqRaisonSocialeCtrl = TextEditingController();
  final _acqNomCtrl      = TextEditingController();
  final _acqPrenomCtrl   = TextEditingController();
  final _acqEmailCtrl    = TextEditingController();
  final _acqTelCtrl      = TextEditingController();
  final _acqAdresseCtrl  = TextEditingController();
  final _prixCtrl        = TextEditingController();
  final _notesCtrl       = TextEditingController();
  final _searchCtrl      = TextEditingController();

  DateTime _date = DateTime.now();
  List<Map<String, dynamic>> _searchResults = [];
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_acqRaisonSocialeCtrl, _acqNomCtrl, _acqPrenomCtrl, _acqEmailCtrl, _acqTelCtrl, _acqAdresseCtrl, _prixCtrl, _notesCtrl, _searchCtrl]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _searchUser(String q) async {
    if (q.length < 2) { setState(() => _searchResults = []); return; }
    final isEmail = q.contains('@');
    final supa = Supabase.instance.client;
    const fields = 'uid, firstname, lastname, name_elevage, is_elevage, email, phone_number, numero_elevage, code_iso_elevage, rue, ville, code_postal, adress_elevage';
    final data = isEmail
        ? await supa.from('users').select(fields).ilike('email', '%$q%').limit(5)
        : await supa.from('users').select(fields).or('firstname.ilike.%$q%,lastname.ilike.%$q%,name_elevage.ilike.%$q%').limit(8);
    setState(() => _searchResults = List<Map<String, dynamic>>.from(data as List));
  }

  void _selectUser(Map<String, dynamic> u) {
    final isElv = u['is_elevage'] == true && (u['name_elevage'] as String? ?? '').isNotEmpty;
    _acqRaisonSocialeCtrl.text = isElv ? (u['name_elevage'] as String? ?? '') : '';
    _acqPrenomCtrl.text = u['firstname'] as String? ?? '';
    _acqNomCtrl.text    = u['lastname'] as String? ?? '';
    _acqEmailCtrl.text  = u['email'] as String? ?? '';
    if (isElv && (u['numero_elevage'] as String? ?? '').isNotEmpty) {
      final iso = u['code_iso_elevage'] as String? ?? '+33';
      _acqTelCtrl.text = '$iso ${u['numero_elevage']}'.trim();
    } else {
      _acqTelCtrl.text = u['phone_number'] as String? ?? '';
    }
    if (isElv && (u['adress_elevage'] as String? ?? '').isNotEmpty) {
      _acqAdresseCtrl.text = u['adress_elevage'] as String? ?? '';
    } else {
      _acqAdresseCtrl.text = [u['rue'], u['code_postal'], u['ville']].whereType<String>().where((s) => s.isNotEmpty).join(', ');
    }
    _searchCtrl.clear();
    setState(() => _searchResults = []);
  }

  Future<void> _creer() async {
    if (_selectedAnimal == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _saving = true);

    try {
      final typeLabel = _type == 'contrat_vente' ? 'Contrat de vente'
          : _type == 'contrat_reservation' ? 'Contrat de réservation'
          : _type == 'contrat_saillie' ? 'Contrat de saillie'
          : 'Certificat de cession';

      final result = await widget.supa
          .from('documents_animaux')
          .insert({
            'animal_id':   _selectedAnimal!['id'],
            'uid_eleveur': uid,
            'type':        _type,
            'titre':       '$typeLabel — ${_selectedAnimal!['nom'] ?? 'Animal'}',
            'statut':      'en_attente',
            'expires_at':  DateTime.now().add(const Duration(days: 30)).toIso8601String(),
            'metadata': {
              if (_acqRaisonSocialeCtrl.text.trim().isNotEmpty)
                'acquereur_raison_sociale': _acqRaisonSocialeCtrl.text.trim(),
              'acquereur_nom':      '${_acqPrenomCtrl.text.trim()} ${_acqNomCtrl.text.trim()}'.trim(),
              'acquereur_email':    _acqEmailCtrl.text.trim(),
              'acquereur_tel':      _acqTelCtrl.text.trim(),
              'acquereur_adresse':  _acqAdresseCtrl.text.trim(),
              'prix':               double.tryParse(_prixCtrl.text.replaceAll(',', '.')) ?? 0,
              'date_doc':           _date.toIso8601String().split('T').first,
              'notes':              _notesCtrl.text.trim(),
              if (_type == 'contrat_vente') 'avec_sterilisation': _avecSteril,
            },
          })
          .select('id, token')
          .single();

      final token = result['token'] as String?;

      widget.onSaved();
      setState(() => _saving = false);

      if (mounted) Navigator.pop(context);

      if (token != null) {
        final url = '$kSiteBaseUrl/signer-contrat/$token';

        // Notifier la contrepartie si c'est un contrat de saillie
        if (_type == 'contrat_saillie') {
          final acqEmail = _acqEmailCtrl.text.trim();
          if (acqEmail.isNotEmpty) {
            try {
              final targetRes = await widget.supa
                  .from('users').select('uid').eq('email', acqEmail).maybeSingle();
              final targetUid = targetRes?['uid'] as String?;
              if (targetUid != null) {
                await widget.supa.from('notifications').insert({
                  'uid': targetUid,
                  'type': 'contrat_saillie_invite',
                  'title': '💞 Contrat de saillie',
                  'body': 'Vous avez reçu un contrat de saillie à compléter et signer',
                  'profile_type': '',
                  'data': {'token': token, 'url': url},
                  'read': false,
                });
              }
            } catch (_) {}
          }
        }

        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.97,
      minChildSize: 0.5,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(children: [
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios, size: 20), color: const Color(0xFF1F2A2E)),
              const Expanded(child: Text('Nouveau contrat', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17, color: Color(0xFF1F2A2E)), textAlign: TextAlign.center)),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 20), color: const Color(0xFF1F2A2E)),
            ]),
          ),
          Expanded(child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [

            // Type de contrat
            const Text('Type de contrat', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Row(children: [
              for (final t in [('contrat_vente', '🤝', 'Vente'), ('contrat_reservation', '🐾', 'Réservation'), ('certificat_cession', '📋', 'Cession'), ('contrat_saillie', '💞', 'Saillie')])
                Expanded(child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _type = t.$1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _type == t.$1 ? _teal : const Color(0xFFF5F5F0),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _type == t.$1 ? _teal : const Color(0xFFE0E0E0)),
                      ),
                      child: Column(children: [
                        Text(t.$2, style: const TextStyle(fontSize: 18)),
                        const SizedBox(height: 2),
                        Text(t.$3, style: TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w600, color: _type == t.$1 ? Colors.white : const Color(0xFF555555))),
                      ]),
                    ),
                  ),
                )),
            ]),
            const SizedBox(height: 20),

            // Sélecteur animal
            const Text('Animal concerné *', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE0E0E0)),
                borderRadius: BorderRadius.circular(12),
                color: Colors.white,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _selectedAnimal?['id'] as String?,
                  hint: const Text('Sélectionner un animal', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey)),
                  onChanged: (v) => setState(() => _selectedAnimal = widget.animaux.firstWhere((a) => a['id'] == v)),
                  items: widget.animaux.map((a) => DropdownMenuItem<String>(
                    value: a['id'] as String,
                    child: Text('${a['nom'] ?? '—'} (${a['espece'] ?? '—'}${a['race'] != null ? ' · ${a['race']}' : ''})',
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                  )).toList(),
                ),
              ),
            ),
            if (_selectedAnimal != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFEEF5EA), borderRadius: BorderRadius.circular(10)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${_selectedAnimal!['nom'] ?? '—'} · ${_selectedAnimal!['espece'] ?? '—'}${_selectedAnimal!['race'] != null ? ' · ${_selectedAnimal!['race']}' : ''}',
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 12)),
                  if (_selectedAnimal!['identification'] != null)
                    Text('Puce : ${_selectedAnimal!['identification']}', style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF555555))),
                ]),
              ),
            const SizedBox(height: 20),

            // Recherche acquéreur
            const Text('Rechercher l\'acquéreur (PetsMatch)', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 6),
            TextField(
              controller: _searchCtrl,
              onChanged: _searchUser,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Nom, prénom ou email…',
                prefixIcon: const Icon(Icons.search, size: 18),
                hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _teal, width: 1.5)),
              ),
            ),
            if (_searchResults.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE0E0E0)), borderRadius: BorderRadius.circular(10)),
                child: Column(children: _searchResults.map((u) {
                  final isElv = u['is_elevage'] == true && (u['name_elevage'] as String? ?? '').isNotEmpty;
                  final displayName = isElv
                      ? u['name_elevage'] as String
                      : '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
                  return ListTile(
                    dense: true,
                    leading: isElv ? const Text('🏠', style: TextStyle(fontSize: 16)) : null,
                    title: Text(displayName, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text(u['email'] as String? ?? '', style: const TextStyle(fontFamily: 'Galey', fontSize: 11)),
                    onTap: () => _selectUser(u),
                  );
                }).toList()),
              ),
            const SizedBox(height: 16),

            // Infos acquéreur
            _field('Raison sociale (entreprise / élevage)', _acqRaisonSocialeCtrl),
            _field('Prénom', _acqPrenomCtrl),
            _field('Nom', _acqNomCtrl),
            _field('Email', _acqEmailCtrl, type: TextInputType.emailAddress),
            _field('Téléphone', _acqTelCtrl, type: TextInputType.phone),
            _field('Adresse', _acqAdresseCtrl),
            _field('Prix (€, 0 = gratuit)', _prixCtrl, type: TextInputType.number),
            const SizedBox(height: 8),

            // Date
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date du contrat', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
              subtitle: Text('${_date.day.toString().padLeft(2,'0')}/${_date.month.toString().padLeft(2,'0')}/${_date.year}',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.calendar_today_outlined, size: 18),
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime(2030));
                if (d != null) setState(() => _date = d);
              },
            ),
            _field('Notes', _notesCtrl, maxLines: 2),
            const SizedBox(height: 8),

            // Clause stérilisation (contrat de vente uniquement)
            if (_type == 'contrat_vente')
              GestureDetector(
                onTap: () => setState(() => _avecSteril = !_avecSteril),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    border: Border.all(color: const Color(0xFFFCD34D)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Checkbox(
                      value: _avecSteril,
                      onChanged: (v) => setState(() => _avecSteril = v ?? true),
                      activeColor: _teal,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Clause de stérilisation (Tranche 2)', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF92400E))),
                      SizedBox(height: 2),
                      Text('Inclure la pénalité si l\'acquéreur ne stérilise pas dans le délai légal.', style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFFB45309))),
                    ])),
                  ]),
                ),
              ),

            const SizedBox(height: 16),

            // Boutons
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed: (_selectedAnimal == null || _saving) ? null : _creer,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Créer & ouvrir sur le web', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
              )),
            ]),
          ])),
        ]),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {TextInputType? type, int maxLines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      TextField(
        controller: ctrl,
        keyboardType: type,
        maxLines: maxLines,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF0C5C6C), width: 1.5)),
        ),
      ),
    ]),
  );
}
