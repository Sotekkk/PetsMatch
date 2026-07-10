import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CertificatsEngagementPage extends StatefulWidget {
  final bool isAssociation;
  const CertificatsEngagementPage({super.key, this.isAssociation = false});
  @override
  State<CertificatsEngagementPage> createState() => _CertificatsEngagementPageState();
}

class _CertificatsEngagementPageState extends State<CertificatsEngagementPage> {
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);
  static const _dark  = Color(0xFF1F2A2E);

  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _certs   = [];
  List<Map<String, dynamic>> _animaux = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ps = widget.isAssociation ? 'association' : 'eleveur';
    final certsQ = _supa.from('certificats_engagement')
        .select('id, nom_animal, espece, acquereur_prenom, acquereur_nom, acquereur_email, statut, token_signature, date_remise, date_signature_acquereur')
        .eq('cedant_uid', uid);
    final animauxQ = _supa.from('animaux')
        .select('id, nom, espece, race, identification, date_naissance')
        .eq('uid_eleveur', uid)
        .eq('is_association', widget.isAssociation);
    final [certs, animaux] = await Future.wait([
      (ps == 'association'
          ? certsQ.eq('profil_source', 'association')
          : certsQ.or('profil_source.is.null,profil_source.eq.eleveur'))
          .order('created_at', ascending: false),
      animauxQ.order('nom'),
    ]);
    if (mounted) setState(() {
      _certs   = List<Map<String, dynamic>>.from(certs as List);
      _animaux = List<Map<String, dynamic>>.from(animaux as List);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        title: const Text('Certificats d\'engagement',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18, color: Colors.white)),
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _animaux.isEmpty ? null : () => _showCreateSheet(context),
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nouveau', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _certs.isEmpty
              ? _emptyState(context)
              : RefreshIndicator(
                  color: _teal,
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: _certs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _CertCard(cert: _certs[i], onCopyLink: _copyLink, onEdit: (c) => _showCreateSheet(context, editCert: c), onDelete: _deleteCert),
                  ),
                ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.edit_document, size: 64, color: Color(0xFFD1D5DB)),
        const SizedBox(height: 16),
        const Text('Aucun certificat',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18, color: _dark)),
        const SizedBox(height: 8),
        Text(
          _animaux.isEmpty
              ? 'Ajoutez d\'abord des animaux dans votre élevage'
              : 'Créez un certificat pour une vente ou adoption',
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF6F767B)),
        ),
        if (_animaux.isNotEmpty) ...[
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => _showCreateSheet(context),
            icon: const Icon(Icons.add),
            label: const Text('Créer un certificat', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ],
      ]),
    );
  }

  void _copyLink(String token) {
    Clipboard.setData(ClipboardData(text: 'https://www.petsmatchapp.com/certificat/$token'));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lien copié !')));
  }

  Future<void> _deleteCert(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer le certificat ?', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: const Text('Cette action est irréversible. Le lien partagé ne fonctionnera plus.', style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler', style: TextStyle(fontFamily: 'Galey', color: Color(0xFF6F767B)))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer', style: TextStyle(fontFamily: 'Galey', color: Color(0xFFEF4444), fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (confirm != true) return;
    await _supa.from('certificats_engagement').delete().eq('id', id).neq('statut', 'signe');
    setState(() => _certs.removeWhere((c) => c['id'] == id));
  }

  void _showCreateSheet(BuildContext context, {Map<String, dynamic>? editCert}) {
    final isEdit = editCert != null;
    Map<String, dynamic>? selectedAnimal = isEdit
        ? _animaux.firstWhere((a) => a['id'] == editCert!['animal_id'], orElse: () => {})
        : null;
    final prenomCtrl  = TextEditingController(text: editCert?['acquereur_prenom'] ?? '');
    final nomCtrl     = TextEditingController(text: editCert?['acquereur_nom'] ?? '');
    final emailCtrl   = TextEditingController(text: editCert?['acquereur_email'] ?? '');
    final telCtrl     = TextEditingController(text: editCert?['acquereur_telephone'] ?? '');
    final adresseCtrl = TextEditingController(text: editCert?['acquereur_adresse'] ?? '');
    final prixCtrl    = TextEditingController(text: editCert?['prix']?.toString() ?? '');
    final searchCtrl  = TextEditingController();
    String modalite   = editCert?['modalite_cession'] ?? 'vente';
    bool saving       = false;
    String? tokenResult;
    List<Map<String, dynamic>> userResults = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        Future<void> searchUsers(String q) async {
          final query = q.trim();
          if (query.length < 2) { setS(() => userResults = []); return; }
          final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
          List<Map<String, dynamic>> results;
          if (query.contains('@')) {
            final users = await _supa.from('users').select('uid,email')
                .ilike('email', '%$query%').neq('uid', currentUid).limit(5);
            final emailByUid = { for (final u in (users as List)) u['uid'] as String: u['email'] as String? };
            final uids = emailByUid.keys.toList();
            final List cps = uids.isEmpty ? [] : await _supa.from('user_profiles')
                .select('uid,firstname,lastname,phone_number,rue,ville,code_postal')
                .inFilter('uid', uids).eq('is_main', true);
            results = List<Map<String, dynamic>>.from(cps).map((cp) => {
              'uid': cp['uid'], 'firstname': cp['firstname'], 'lastname': cp['lastname'],
              'email': emailByUid[cp['uid']] ?? '', 'phone_number': cp['phone_number'],
              'rue': cp['rue'], 'ville': cp['ville'], 'code_postal': cp['code_postal'],
            }).toList();
          } else {
            final cps = await _supa.from('user_profiles')
                .select('uid,firstname,lastname,email_contact,phone_number,rue,ville,code_postal')
                .or('firstname.ilike.%$query%,lastname.ilike.%$query%')
                .neq('uid', currentUid).eq('is_main', true).limit(5);
            results = List<Map<String, dynamic>>.from(cps as List).map((cp) => {
              'uid': cp['uid'], 'firstname': cp['firstname'], 'lastname': cp['lastname'],
              'email': cp['email_contact'] ?? '', 'phone_number': cp['phone_number'],
              'rue': cp['rue'], 'ville': cp['ville'], 'code_postal': cp['code_postal'],
            }).toList();
          }
          setS(() => userResults = results);
        }

        void prefillUser(Map<String, dynamic> u) {
          final addr = [u['rue'], u['code_postal'], u['ville']].where((e) => e != null && (e as String).isNotEmpty).join(', ');
          prenomCtrl.text  = u['firstname'] ?? '';
          nomCtrl.text     = u['lastname'] ?? '';
          emailCtrl.text   = u['email'] ?? '';
          telCtrl.text     = u['phone_number'] ?? '';
          adresseCtrl.text = addr;
          searchCtrl.text  = '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
          setS(() => userResults = []);
        }

        Future<void> submit() async {
          if (!isEdit && selectedAnimal == null) return;
          if (emailCtrl.text.trim().isEmpty || nomCtrl.text.trim().isEmpty) return;
          setS(() => saving = true);
          try {
            final uid = FirebaseAuth.instance.currentUser?.uid;
            if (uid == null) return;
            if (isEdit) {
              // Mise à jour acquéreur uniquement
              await _supa.from('certificats_engagement').update({
                'acquereur_nom':       nomCtrl.text.trim(),
                'acquereur_prenom':    prenomCtrl.text.trim(),
                'acquereur_email':     emailCtrl.text.trim(),
                'acquereur_telephone': telCtrl.text.trim(),
                'acquereur_adresse':   adresseCtrl.text.trim(),
                'modalite_cession':    modalite,
                'prix':                modalite == 'vente' && prixCtrl.text.isNotEmpty ? double.tryParse(prixCtrl.text.replaceAll(',', '.')) : null,
              }).eq('id', editCert!['id'] as String).neq('statut', 'signe');
              setS(() => saving = false);
              if (ctx.mounted) Navigator.pop(ctx);
              _load();
            } else {
              final now = DateTime.now();
              final esp = selectedAnimal!['espece'] as String? ?? '';
              final estDelai = esp == 'chien' || esp == 'chat';
              final payload = <String, dynamic>{
                'cedant_uid':            uid,
                'animal_id':             selectedAnimal!['id'] as String,
                'espece':                esp,
                'race':                  selectedAnimal!['race'] ?? '',
                'nom_animal':            selectedAnimal!['nom'] ?? '',
                'date_naissance_animal': selectedAnimal!['date_naissance'],
                'num_identification':    selectedAnimal!['identification'] ?? '',
                'acquereur_nom':         nomCtrl.text.trim(),
                'acquereur_prenom':      prenomCtrl.text.trim(),
                'acquereur_email':       emailCtrl.text.trim(),
                'acquereur_telephone':   telCtrl.text.trim(),
                'acquereur_adresse':     adresseCtrl.text.trim(),
                'modalite_cession':      modalite,
                'prix':                  modalite == 'vente' && prixCtrl.text.isNotEmpty ? double.tryParse(prixCtrl.text.replaceAll(',', '.')) : null,
                'date_remise':           now.toIso8601String(),
                'date_limite_signature': estDelai ? now.add(const Duration(days: 7)).toIso8601String() : null,
                'profil_source':         widget.isAssociation ? 'association' : 'eleveur',
              };
              final res = await _supa.from('certificats_engagement').insert(payload).select('token_signature').single();
              setS(() { saving = false; tokenResult = res['token_signature'] as String?; });
              _load();
            }
          } catch (e) {
            setS(() => saving = false);
            if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Erreur : $e')));
          }
        }

        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              Text(isEdit ? 'Modifier — ${editCert!['nom_animal']}' : 'Nouveau certificat',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 17, fontWeight: FontWeight.w700, color: _dark)),
              const SizedBox(height: 4),
              const Text('Loi 2021-1539 — Chien/Chat : délai légal 7 jours',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
              const SizedBox(height: 16),

              if (tokenResult != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: _green.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _green.withValues(alpha: 0.3))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('✅ Certificat créé !',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF3D6B33))),
                    const SizedBox(height: 6),
                    const Text('Partagez ce lien à l\'acquéreur :',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF3D6B33))),
                    const SizedBox(height: 6),
                    Text('petsmatchapp.com/certificat/$tokenResult',
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _teal)),
                    const SizedBox(height: 12),
                    SizedBox(width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('Copier le lien', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: 'https://www.petsmatchapp.com/certificat/$tokenResult'));
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Lien copié !')));
                        },
                      ),
                    ),
                    TextButton(onPressed: () => Navigator.pop(ctx),
                        child: const Text('Fermer', style: TextStyle(fontFamily: 'Galey', color: Color(0xFF6F767B)))),
                  ]),
                ),
              ] else ...[

                // ── Sélection animal ──────────────────────────────────────────
                const Text('Animal concerné *',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B))),
                const SizedBox(height: 6),
                if (isEdit)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F0),
                      border: Border.all(color: const Color(0xFFE4E7E2)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${editCert!['nom_animal']} (${editCert['espece']})',
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: _dark)),
                      const Text('L\'animal ne peut pas être modifié après création',
                          style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF9CA3AF))),
                    ]),
                  )
                else
                  DropdownButtonFormField<Map<String, dynamic>>(
                    value: selectedAnimal,
                    hint: const Text('Choisir un animal', style: TextStyle(fontFamily: 'Galey', fontSize: 14)),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _teal, width: 1.5)),
                      filled: true, fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: _animaux.map((a) => DropdownMenuItem(
                      value: a,
                      child: Text('${a['nom'] ?? '?'} (${a['espece'] ?? '?'})',
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
                    )).toList(),
                    onChanged: (v) => setS(() => selectedAnimal = v),
                  ),
                const SizedBox(height: 14),

                // ── Recherche utilisateur PetsMatch ───────────────────────────
                const Text('Rechercher un utilisateur PetsMatch',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B))),
                const SizedBox(height: 6),
                TextFormField(
                  controller: searchCtrl,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Nom, prénom ou email…',
                    hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF9CA3AF)),
                    prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF9CA3AF)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _teal, width: 1.5)),
                    filled: true, fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onChanged: searchUsers,
                ),
                if (userResults.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFE4E7E2)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: userResults.map((u) {
                        final name = '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
                        final ville = u['ville'] as String? ?? '';
                        return InkWell(
                          onTap: () => prefillUser(u),
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Row(children: [
                              const Icon(Icons.person_outline, size: 16, color: Color(0xFF0C5C6C)),
                              const SizedBox(width: 8),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(name, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1F2A2E))),
                                Text('${u['email'] ?? ''}${ville.isNotEmpty ? ' · $ville' : ''}',
                                    style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF6F767B))),
                              ])),
                              const Icon(Icons.arrow_forward_ios, size: 12, color: Color(0xFF9CA3AF)),
                            ]),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0xFFF0F0EC)),
                const SizedBox(height: 12),

                // ── Acquéreur ─────────────────────────────────────────────────
                _field('Prénom *', prenomCtrl),
                _field('Nom *', nomCtrl),
                _field('Email *', emailCtrl, keyboard: TextInputType.emailAddress),
                _field('Téléphone', telCtrl, keyboard: TextInputType.phone),
                _field('Adresse', adresseCtrl),
                const SizedBox(height: 8),

                // ── Modalité ──────────────────────────────────────────────────
                const Text('Modalité', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B))),
                const SizedBox(height: 6),
                Row(children: [
                  for (final opt in [('vente', 'Vente'), ('gratuit', 'Don'), ('adoption', 'Adoption')])
                    Expanded(child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: GestureDetector(
                        onTap: () => setS(() => modalite = opt.$1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: modalite == opt.$1 ? _teal : Colors.transparent,
                            border: Border.all(color: modalite == opt.$1 ? _teal : Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(child: Text(opt.$2, style: TextStyle(
                              fontFamily: 'Galey', fontSize: 13,
                              color: modalite == opt.$1 ? Colors.white : _dark,
                              fontWeight: modalite == opt.$1 ? FontWeight.w600 : FontWeight.normal))),
                        ),
                      ),
                    )),
                ]),
                if (modalite == 'vente') ...[
                  const SizedBox(height: 12),
                  _field('Prix (€)', prixCtrl, keyboard: TextInputType.number),
                ],
                const SizedBox(height: 20),
                SizedBox(width: double.infinity,
                  child: ElevatedButton(
                    onPressed: saving ? null : submit,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _teal, foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14), elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(isEdit ? 'Enregistrer les modifications' : 'Générer le certificat',
                              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 15)),
                  ),
                ),
              ],
            ]),
          ),
        );
      }),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: ctrl,
        keyboardType: keyboard,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _teal, width: 1.5)),
          filled: true, fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }
}

// ─── Carte certificat ─────────────────────────────────────────────────────────

class _CertCard extends StatelessWidget {
  final Map<String, dynamic> cert;
  final void Function(String token) onCopyLink;
  final void Function(Map<String, dynamic> cert) onEdit;
  final void Function(String id) onDelete;
  const _CertCard({required this.cert, required this.onCopyLink, required this.onEdit, required this.onDelete});

  static const _statusColor = {
    'envoye': Color(0xFF0C5C6C),
    'lu':     Color(0xFF7B5EA7),
    'signe':  Color(0xFF6E9E57),
    'refuse': Color(0xFFEF4444),
  };
  static const _statusLabel = {
    'envoye': 'Envoyé',
    'lu':     'Lu',
    'signe':  'Signé',
    'refuse': 'Refusé',
  };

  @override
  Widget build(BuildContext context) {
    final statut  = cert['statut'] as String? ?? 'envoye';
    final token   = cert['token_signature'] as String? ?? '';
    final dateR   = cert['date_remise'] != null ? DateTime.tryParse(cert['date_remise'] as String) : null;
    final dateS   = cert['date_signature_acquereur'] != null ? DateTime.tryParse(cert['date_signature_acquereur'] as String) : null;
    final color   = _statusColor[statut] ?? const Color(0xFF0C5C6C);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4E7E2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(
            '${cert['nom_animal'] ?? '?'} (${cert['espece'] ?? '?'})',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1F2A2E)),
          )),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
            child: Text(_statusLabel[statut] ?? statut,
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          '${cert['acquereur_prenom'] ?? ''} ${cert['acquereur_nom'] ?? ''} · ${cert['acquereur_email'] ?? ''}',
          style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
        ),
        if (dateR != null)
          Text('Remis le ${dateR.day.toString().padLeft(2, '0')}/${dateR.month.toString().padLeft(2, '0')}/${dateR.year}',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF9CA3AF))),
        if (dateS != null)
          Text('Signé le ${dateS.day.toString().padLeft(2, '0')}/${dateS.month.toString().padLeft(2, '0')}/${dateS.year}',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6E9E57))),
        if (token.isNotEmpty) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => onCopyLink(token),
            child: Row(children: [
              const Icon(Icons.link, size: 14, color: Color(0xFF0C5C6C)),
              const SizedBox(width: 4),
              Expanded(child: Text('petsmatchapp.com/certificat/$token',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF0C5C6C)))),
              const Icon(Icons.copy, size: 14, color: Color(0xFF9CA3AF)),
            ]),
          ),
        ],
        if (statut != 'signe') ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => onEdit(cert),
                icon: const Icon(Icons.edit_outlined, size: 14),
                label: const Text('Modifier', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0C5C6C),
                  side: const BorderSide(color: Color(0xFF0C5C6C), width: 1),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => onDelete(cert['id'] as String),
                icon: const Icon(Icons.delete_outline, size: 14),
                label: const Text('Supprimer', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444),
                  side: const BorderSide(color: Color(0xFFEF4444), width: 1),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}
