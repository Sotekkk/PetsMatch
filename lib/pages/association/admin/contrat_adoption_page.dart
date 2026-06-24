import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/config.dart';

const _teal  = Color(0xFF0C5C6C);
const _green = Color(0xFF6E9E57);
const _dark  = Color(0xFF1F2A2E);
const _bg    = Color(0xFFF8F8F6);

// Participation par défaut selon l'espèce
int _participationDefaut(String? espece) => switch ((espece ?? '').toLowerCase()) {
  'chien'  => 150,
  'chat'   => 100,
  'cheval' => 500,
  'lapin'  => 50,
  'oiseau' => 30,
  'ovin' || 'caprin' || 'porcin' => 80,
  _        => 50,
};

class ContratAdoptionPage extends StatefulWidget {
  const ContratAdoptionPage({super.key});
  @override
  State<ContratAdoptionPage> createState() => _ContratAdoptionPageState();
}

class _ContratAdoptionPageState extends State<ContratAdoptionPage> {
  final _supa = Supabase.instance.client;

  List<Map<String, dynamic>> _animaux     = [];
  List<Map<String, dynamic>> _contrats    = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final [animaux, contrats] = await Future.wait([
      _supa.from('animaux')
          .select('id, nom, espece, race, identification, date_naissance, photo_url, statut')
          .eq('uid_eleveur', uid)
          .eq('is_association', true)
          .order('nom'),
      _supa.from('documents_animaux')
          .select('id, titre, statut, created_at, metadata, token, animal_id')
          .eq('uid_eleveur', uid)
          .eq('type', 'contrat_adoption')
          .order('created_at', ascending: false),
    ]);
    if (mounted) {
      setState(() {
        _animaux  = List<Map<String, dynamic>>.from(animaux as List);
        _contrats = List<Map<String, dynamic>>.from(contrats as List);
        _loading  = false;
      });
    }
  }

  Future<void> _transmettreContrat(Map<String, dynamic> contrat) async {
    final id    = contrat['id'].toString();
    final token = contrat['token'] as String?;
    if (token == null) return;
    await _supa.from('documents_animaux').update({'statut': 'en_attente'}).eq('id', id);
    // Notifier l'adoptant si sur PetsMatch
    final meta     = contrat['metadata'] as Map<String, dynamic>? ?? {};
    final acqEmail = meta['acquereur_email'] as String?;
    if (acqEmail != null && acqEmail.trim().isNotEmpty) {
      final target = await _supa.from('users').select('uid').eq('email', acqEmail.trim()).maybeSingle();
      if (target != null) {
        await _supa.from('notifications').insert({
          'uid':  target['uid'],
          'type': 'contrat_invite',
          'title': '📄 Contrat d\'adoption à signer',
          'body':  '${contrat['titre'] ?? 'Un contrat d\'adoption'} vous a été transmis — vérifiez et signez',
          'data':  {'token': token, 'url': '$kSiteBaseUrl/signer-contrat/$token'},
          'read':  false,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    }
    if (!mounted) return;
    setState(() {
      final idx = _contrats.indexWhere((c) => c['id'] == id);
      if (idx != -1) _contrats[idx] = {..._contrats[idx], 'statut': 'en_attente'};
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Contrat transmis pour signature'), duration: Duration(seconds: 3)),
    );
  }

  void _openCreate() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CreerContratSheet(
        animaux: _animaux,
        onCreated: _load,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Contrats d\'adoption',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _animaux.isEmpty ? null : _openCreate,
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nouveau', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _contrats.isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  color: _teal,
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: _contrats.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _ContratCard(
                      contrat: _contrats[i],
                      animaux: _animaux,
                      onDelete: () async {
                        await _supa.from('documents_animaux').delete().eq('id', _contrats[i]['id']);
                        _load();
                      },
                      onTransmettre: (_contrats[i]['statut'] ?? 'brouillon') == 'brouillon'
                          ? () => _transmettreContrat(_contrats[i])
                          : null,
                    ),
                  ),
                ),
    );
  }

  Widget _emptyState() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.handshake_outlined, size: 64, color: Color(0xFFD1D5DB)),
      const SizedBox(height: 16),
      const Text('Aucun contrat', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18, color: _dark)),
      const SizedBox(height: 8),
      Text(
        _animaux.isEmpty
            ? 'Ajoutez d\'abord des animaux à votre association'
            : 'Créez un contrat pour une adoption',
        textAlign: TextAlign.center,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF6F767B)),
      ),
      if (_animaux.isNotEmpty) ...[
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: _openCreate,
          icon: const Icon(Icons.add),
          label: const Text('Créer un contrat', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
              backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
      ],
    ]),
  );
}

// ── Carte contrat ─────────────────────────────────────────────────────────────

class _ContratCard extends StatelessWidget {
  final Map<String, dynamic> contrat;
  final List<Map<String, dynamic>> animaux;
  final VoidCallback onDelete;
  final VoidCallback? onTransmettre;

  const _ContratCard({required this.contrat, required this.animaux, required this.onDelete, this.onTransmettre});

  bool get _isBrouillon => (contrat['statut'] ?? 'brouillon') == 'brouillon';

  String get _statutLabel => switch (contrat['statut'] ?? 'brouillon') {
    'signe'      => '✅ Signé',
    'en_attente' => '⏳ En attente',
    'partiellement_signe' => '✍️ Partiel',
    'annule'     => '🚫 Annulé',
    'en_cours'   => 'En cours',
    _            => 'Brouillon',
  };

  Color get _statutColor => switch (contrat['statut'] ?? 'brouillon') {
    'signe'    => _green,
    'en_cours' => Colors.orange,
    _          => Colors.grey,
  };

  @override
  Widget build(BuildContext context) {
    final meta      = contrat['metadata'] as Map<String, dynamic>? ?? {};
    final adoptant  = meta['adoptant_nom'] as String? ?? '—';
    final token     = contrat['token'] as String?;
    final titre     = contrat['titre'] as String? ?? 'Contrat d\'adoption';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.05), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(titre,
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _dark))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: _statutColor.withValues(alpha:0.1), borderRadius: BorderRadius.circular(6)),
            child: Text(_statutLabel, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: _statutColor, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 4),
        Text('Adoptant : $adoptant', style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B))),
        if (token != null) ...[
          const SizedBox(height: 10),
          if (_isBrouillon && onTransmettre != null)
            FilledButton.icon(
              onPressed: onTransmettre,
              style: FilledButton.styleFrom(
                  backgroundColor: _teal,
                  minimumSize: const Size(double.infinity, 38),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              icon: const Icon(Icons.send_outlined, size: 15),
              label: const Text('📤 Transmettre pour signature',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600)),
            )
          else
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_browser, size: 15),
                  label: const Text('Ouvrir le contrat', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: _teal, side: const BorderSide(color: _teal),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  onPressed: () async {
                    final url = Uri.parse('$kSiteBaseUrl/signer-contrat/$token');
                    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
                  },
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 15),
                label: const Text('Lien', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                style: OutlinedButton.styleFrom(
                    foregroundColor: _green, side: const BorderSide(color: _green),
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: '$kSiteBaseUrl/signer-contrat/$token'));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lien copié !')));
                },
              ),
            ]),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: onDelete,
            child: const Text('Supprimer', style: TextStyle(fontFamily: 'Galey', color: Colors.redAccent, fontSize: 12)),
          ),
        ),
      ]),
    );
  }
}

// ── Sheet création ────────────────────────────────────────────────────────────

class _CreerContratSheet extends StatefulWidget {
  final List<Map<String, dynamic>> animaux;
  final VoidCallback onCreated;
  const _CreerContratSheet({required this.animaux, required this.onCreated});
  @override
  State<_CreerContratSheet> createState() => _CreerContratSheetState();
}

class _CreerContratSheetState extends State<_CreerContratSheet> {
  final _supa = Supabase.instance.client;

  Map<String, dynamic>? _selectedAnimal;

  // Recherche adoptant PetsMatch
  final _searchCtrl       = TextEditingController();
  List<Map<String, dynamic>> _userResults = [];
  bool _searching = false;

  // Infos adoptant
  final _nomCtrl      = TextEditingController();
  final _prenomCtrl   = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _telCtrl      = TextEditingController();
  final _adresseCtrl  = TextEditingController();
  final _participCtrl = TextEditingController();

  bool _saving    = false;
  String? _token;

  @override
  void dispose() {
    _searchCtrl.dispose(); _nomCtrl.dispose(); _prenomCtrl.dispose();
    _emailCtrl.dispose(); _telCtrl.dispose(); _adresseCtrl.dispose();
    _participCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchUsers(String q) async {
    if (q.trim().length < 2) { setState(() => _userResults = []); return; }
    setState(() => _searching = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final res = await _supa.from('users')
          .select('uid,firstname,lastname,email,phone_number,rue,ville,code_postal,rue_elevage,ville_elevage,code_postal_elevage')
          .or('firstname.ilike.%${q.trim()}%,lastname.ilike.%${q.trim()}%,email.ilike.%${q.trim()}%')
          .neq('uid', uid).limit(5);
      if (mounted) setState(() { _userResults = List<Map<String, dynamic>>.from(res as List); _searching = false; });
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _prefillUser(Map<String, dynamic> u) {
    final personalAddr = [u['rue'], u['code_postal'], u['ville']]
        .where((e) => e != null && (e as String).isNotEmpty).join(', ');
    final elevageAddr = [u['rue_elevage'], u['code_postal_elevage'], u['ville_elevage']]
        .where((e) => e != null && (e as String).isNotEmpty).join(', ');
    _prenomCtrl.text   = u['firstname'] ?? '';
    _nomCtrl.text      = u['lastname'] ?? '';
    _emailCtrl.text    = u['email'] ?? '';
    _telCtrl.text      = u['phone_number'] ?? '';
    _adresseCtrl.text  = personalAddr.isNotEmpty ? personalAddr : elevageAddr;
    _searchCtrl.text   = '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
    setState(() => _userResults = []);
  }

  void _onAnimalSelected(Map<String, dynamic> a) {
    setState(() {
      _selectedAnimal = a;
      final esp = a['espece'] as String? ?? '';
      _participCtrl.text = _participationDefaut(esp).toString();
    });
  }

  Future<void> _submit() async {
    if (_selectedAnimal == null) return;
    if (_emailCtrl.text.trim().isEmpty || _nomCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final uid      = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final animal   = _selectedAnimal!;
      final animalId = animal['id'] as String;
      final nomAnimal = animal['nom'] as String? ?? '';
      final espece   = animal['espece'] as String? ?? '';
      final participation = int.tryParse(_participCtrl.text) ?? _participationDefaut(espece);

      final res = await _supa.from('documents_animaux').insert({
        'animal_id':   animalId,
        'uid_eleveur': uid,
        'type':        'contrat_adoption',
        'titre':       'Contrat d\'adoption — $nomAnimal',
        'statut':      'brouillon',
        'metadata': {
          'adoptant_nom':     _nomCtrl.text.trim(),
          'adoptant_prenom':  _prenomCtrl.text.trim(),
          'adoptant_email':   _emailCtrl.text.trim(),
          'adoptant_tel':     _telCtrl.text.trim(),
          'adoptant_adresse': _adresseCtrl.text.trim(),
          'participation':    participation,
          'espece':           espece,
          'race':             animal['race'] ?? '',
          'identification':   animal['identification'] ?? '',
          'date_naissance':   animal['date_naissance'] ?? '',
          'date_adoption':    DateTime.now().toIso8601String().split('T').first,
        },
      }).select('token').single();
      if (mounted) setState(() { _token = res['token'] as String?; _saving = false; });
      widget.onCreated();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final iCls = BoxDecoration(
      border: Border.all(color: Colors.grey.shade300),
      borderRadius: BorderRadius.circular(10),
      color: Colors.white,
    );

    InputDecoration iDec(String label) => InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      isDense: true,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),

          const Text('Nouveau contrat d\'adoption',
              style: TextStyle(fontFamily: 'Galey', fontSize: 17, fontWeight: FontWeight.w700, color: _dark)),
          const SizedBox(height: 16),

          if (_token != null) ...[
            // ── Succès ──────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: _green.withValues(alpha:0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _green.withValues(alpha:0.3))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('✅ Contrat créé !',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF3D6B33))),
                const SizedBox(height: 6),
                const Text('Partagez ce lien à l\'adoptant pour signature :',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF3D6B33))),
                const SizedBox(height: 6),
                Text('petsmatchapp.com/signer-contrat/$_token',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _teal)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.open_in_browser, size: 16),
                      label: const Text('Ouvrir', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      onPressed: () async {
                        final url = Uri.parse('$kSiteBaseUrl/signer-contrat/$_token');
                        if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copier le lien', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white, elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: '$kSiteBaseUrl/signer-contrat/$_token'));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lien copié !')));
                      },
                    ),
                  ),
                ]),
                TextButton(onPressed: () => Navigator.pop(context),
                    child: const Text('Fermer', style: TextStyle(fontFamily: 'Galey', color: Color(0xFF6F767B)))),
              ]),
            ),
          ] else ...[

            // ── Sélection animal ─────────────────────────────────────────────
            const Text('Animal adopté *',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF6F767B))),
            const SizedBox(height: 8),
            Container(
              decoration: iCls,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<Map<String, dynamic>>(
                  value: _selectedAnimal,
                  isExpanded: true,
                  hint: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('Choisir un animal…', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
                  ),
                  items: widget.animaux.map((a) => DropdownMenuItem(
                    value: a,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('${a['nom'] ?? '?'} — ${a['espece'] ?? ''}',
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                    ),
                  )).toList(),
                  onChanged: (a) { if (a != null) _onAnimalSelected(a); },
                ),
              ),
            ),
            if (_selectedAnimal != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: _teal.withValues(alpha:0.06), borderRadius: BorderRadius.circular(8)),
                child: Text(
                  '${_selectedAnimal!['espece'] ?? ''}'
                  '${_selectedAnimal!['race'] != null ? ' · ${_selectedAnimal!['race']}' : ''}'
                  '${_selectedAnimal!['identification'] != null ? ' · N° ${_selectedAnimal!['identification']}' : ''}',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _teal),
                ),
              ),
            ],
            const SizedBox(height: 16),

            // ── Participation ────────────────────────────────────────────────
            TextField(
              controller: _participCtrl,
              keyboardType: TextInputType.number,
              decoration: iDec('Participation aux frais (€)'),
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
            ),
            const SizedBox(height: 16),

            // ── Recherche adoptant PetsMatch ─────────────────────────────────
            const Text('Adoptant *',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF6F767B))),
            const SizedBox(height: 8),
            TextField(
              controller: _searchCtrl,
              decoration: iDec('Rechercher un membre PetsMatch…'),
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
              onChanged: (v) => _searchUsers(v),
            ),
            if (_searching) const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _teal))),
            ),
            if (_userResults.isNotEmpty) ...[
              const SizedBox(height: 4),
              ...(_userResults.map((u) => ListTile(
                dense: true,
                leading: CircleAvatar(radius: 16, backgroundColor: _teal.withValues(alpha:0.1),
                    child: const Icon(Icons.person, size: 16, color: _teal)),
                title: Text('${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim(),
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                subtitle: Text(u['email'] ?? '', style: const TextStyle(fontFamily: 'Galey', fontSize: 11)),
                onTap: () => _prefillUser(u),
              ))),
            ],
            const SizedBox(height: 12),

            // ── Champs adoptant ──────────────────────────────────────────────
            Row(children: [
              Expanded(child: TextField(controller: _prenomCtrl, decoration: iDec('Prénom'), style: const TextStyle(fontFamily: 'Galey', fontSize: 13))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _nomCtrl, decoration: iDec('Nom *'), style: const TextStyle(fontFamily: 'Galey', fontSize: 13))),
            ]),
            const SizedBox(height: 10),
            TextField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress,
                decoration: iDec('Email *'), style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
            const SizedBox(height: 10),
            TextField(controller: _telCtrl, keyboardType: TextInputType.phone,
                decoration: iDec('Téléphone'), style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
            const SizedBox(height: 10),
            TextField(controller: _adresseCtrl, decoration: iDec('Adresse complète'),
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_saving || _selectedAnimal == null || _emailCtrl.text.trim().isEmpty)
                    ? null
                    : _submit,
                style: ElevatedButton.styleFrom(
                    backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: _saving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Créer le contrat', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
