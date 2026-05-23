import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// ─────────────────────────────────────────────────────────────
// CONSTANTS
// ─────────────────────────────────────────────────────────────
const _green = Color(0xFF6E9E57);
const _teal = Color(0xFF0C5C6C);
const _bg = Color(0xFFF8F8F6);
const _dark = Color(0xFF1F2A2E);

// ─────────────────────────────────────────────────────────────
// 1. LIST PAGE
// ─────────────────────────────────────────────────────────────
class FacturationPage extends StatelessWidget {
  const FacturationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Mes Factures',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _green,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Nouvelle facture',
            style: TextStyle(fontFamily: 'Galey', color: Colors.white, fontWeight: FontWeight.w600)),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreerFacturePage())),
      ),
      body: uid == null
          ? const Center(child: Text('Non connecté'))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection('factures')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: _green));
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('Aucune facture', style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade400, fontSize: 16)),
                    ]),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final d = docs[i].data() as Map<String, dynamic>;
                    final statut = d['statut'] ?? 'emise';
                    return _FactureCard(
                      data: d,
                      docId: docs[i].id,
                      statut: statut,
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => FactureDetailPage(data: d, docId: docs[i].id),
                      )),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _FactureCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  final String statut;
  final VoidCallback onTap;

  const _FactureCard({required this.data, required this.docId, required this.statut, required this.onTap});

  Color get _statutColor => statut == 'payee' ? _green : statut == 'annulee' ? Colors.red : const Color(0xFFE9A825);
  String get _statutLabel => statut == 'payee' ? 'Payée' : statut == 'annulee' ? 'Annulée' : 'Émise';

  @override
  Widget build(BuildContext context) {
    final total = (data['totalTTC'] ?? 0.0).toStringAsFixed(2);
    final client = data['nomClient'] ?? '';
    final num = data['numeroFacture']?.toString() ?? '';
    final date = data['dateFacture'] ?? '';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: const Color(0xFFEEF5EA), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.receipt_outlined, color: _green, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Facture n° $num', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _dark)),
            const SizedBox(height: 2),
            Text(client, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
            Text(date, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade400)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('$total €', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: _dark)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: _statutColor.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
              child: Text(_statutLabel, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: _statutColor, fontWeight: FontWeight.w600)),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 2. DETAIL / REPRINT PAGE
// ─────────────────────────────────────────────────────────────
class FactureDetailPage extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;

  const FactureDetailPage({super.key, required this.data, required this.docId});

  @override
  Widget build(BuildContext context) {
    final lignes = List<Map<String, dynamic>>.from(data['lignes'] ?? []);
    final totalHT = (data['totalHT'] ?? 0.0) as num;
    final totalTVA = (data['totalTVA'] ?? 0.0) as num;
    final totalTTC = (data['totalTTC'] ?? 0.0) as num;
    final franchise = data['regimeTVA'] == 'franchise';

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: Text('Facture n° ${data['numeroFacture']}',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Imprimer / PDF',
            onPressed: () async {
              final bytes = await _buildPdf(data);
              await Printing.layoutPdf(onLayout: (_) async => bytes);
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid == null) return;
              await FirebaseFirestore.instance
                  .collection('users').doc(uid).collection('factures').doc(docId)
                  .update({'statut': v});
              if (context.mounted) Navigator.pop(context);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'emise', child: Text('Marquer Émise')),
              const PopupMenuItem(value: 'payee', child: Text('Marquer Payée')),
              const PopupMenuItem(value: 'annulee', child: Text('Annuler')),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Émetteur / Client
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _InfoBlock(title: 'Émetteur', lines: [
              data['nomEmetteur'] ?? '',
              '${data['rueEmetteur'] ?? ''}',
              '${data['cpEmetteur'] ?? ''} ${data['villeEmetteur'] ?? ''}',
              data['paysEmetteur'] ?? '',
              if ((data['siretEmetteur'] ?? '').isNotEmpty) 'SIRET: ${data['siretEmetteur']}',
              if ((data['tvaEmetteur'] ?? '').isNotEmpty) 'TVA: ${data['tvaEmetteur']}',
            ])),
            const SizedBox(width: 12),
            Expanded(child: _InfoBlock(title: 'Client', lines: [
              '${data['prenomClient'] ?? ''} ${data['nomClient'] ?? ''}'.trim(),
              '${data['rueClient'] ?? ''}',
              '${data['cpClient'] ?? ''} ${data['villeClient'] ?? ''}',
              data['paysClient'] ?? '',
              if ((data['emailClient'] ?? '').isNotEmpty) data['emailClient'],
              if ((data['telephoneClient'] ?? '').isNotEmpty) data['telephoneClient'],
            ])),
          ]),
          const SizedBox(height: 16),
          // Dates
          _Card(child: Wrap(spacing: 24, runSpacing: 8, children: [
            _DateChip(label: 'Facture', value: data['dateFacture'] ?? ''),
            _DateChip(label: 'Prestation', value: data['datePrestation'] ?? ''),
            if ((data['dateEcheance'] ?? '').isNotEmpty)
              _DateChip(label: 'Échéance', value: data['dateEcheance'] ?? ''),
          ])),
          const SizedBox(height: 16),
          // Lignes
          _Card(child: Column(children: [
            _TableHeader(franchise: franchise),
            ...lignes.map((l) => _TableRow(ligne: l, franchise: franchise)),
          ])),
          const SizedBox(height: 16),
          // Totaux
          Align(
            alignment: Alignment.centerRight,
            child: _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (!franchise) ...[
                _TotalRow(label: 'Total HT', value: '${totalHT.toStringAsFixed(2)} €'),
                _TotalRow(label: 'TVA', value: '${totalTVA.toStringAsFixed(2)} €'),
              ],
              _TotalRow(label: 'Total TTC', value: '${totalTTC.toStringAsFixed(2)} €', bold: true),
            ])),
          ),
          const SizedBox(height: 16),
          // Paiement
          _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _DetailRow(label: 'Mode de paiement', value: data['modePaiement'] ?? ''),
            if ((data['delaiPaiement'] ?? '').isNotEmpty)
              _DetailRow(label: 'Délai', value: '${data['delaiPaiement']} jours'),
          ])),
          if ((data['noteComplementaire'] ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            _Card(child: Text(data['noteComplementaire'], style: const TextStyle(fontFamily: 'Galey', fontSize: 13))),
          ],
          const SizedBox(height: 16),
          _MentionsLegales(franchise: franchise),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.print_outlined, color: Colors.white),
              label: const Text('Imprimer / Enregistrer en PDF',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final bytes = await _buildPdf(data);
                await Printing.layoutPdf(onLayout: (_) async => bytes);
              },
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 3. CREATE PAGE
// ─────────────────────────────────────────────────────────────
class CreerFacturePage extends StatefulWidget {
  const CreerFacturePage({super.key});
  @override
  State<CreerFacturePage> createState() => _CreerFacturePageState();
}

class _CreerFacturePageState extends State<CreerFacturePage> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  // Émetteur
  final _nomEmetteur = TextEditingController();
  final _rueEmetteur = TextEditingController();
  final _cpEmetteur = TextEditingController();
  final _villeEmetteur = TextEditingController();
  final _paysEmetteur = TextEditingController(text: 'France');
  final _telEmetteur = TextEditingController();
  final _siretEmetteur = TextEditingController();
  final _tvaEmetteur = TextEditingController();
  final _emailEmetteur = TextEditingController();

  // Client
  final _prenomClient = TextEditingController();
  final _nomClient = TextEditingController();
  final _rueClient = TextEditingController();
  final _cpClient = TextEditingController();
  final _villeClient = TextEditingController();
  final _paysClient = TextEditingController(text: 'France');
  final _emailClient = TextEditingController();
  final _telClient = TextEditingController();
  final _siretClient = TextEditingController();
  final _tvaClient = TextEditingController();

  // Facture
  final _numeroFacture = TextEditingController();
  String _dateFacture = DateFormat('dd/MM/yyyy').format(DateTime.now());
  String _datePrestation = DateFormat('dd/MM/yyyy').format(DateTime.now());
  String _dateEcheance = DateFormat('dd/MM/yyyy').format(DateTime.now().add(const Duration(days: 30)));
  String _modePaiement = 'Virement bancaire';
  final _delaiPaiement = TextEditingController(text: '30');
  final _noteComplementaire = TextEditingController();
  bool _franchise = false; // TVA franchise en base

  // Lignes
  List<_Ligne> _lignes = [];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final d = doc.data() ?? {};
    final factures = await FirebaseFirestore.instance
        .collection('users').doc(uid).collection('factures')
        .orderBy('numeroFacture', descending: true).limit(1).get();
    final last = factures.docs.isEmpty ? 0 : (factures.docs.first['numeroFacture'] ?? 0) as int;

    if (!mounted) return;
    setState(() {
      _nomEmetteur.text = d['nameElevage'] ?? d['firstname'] ?? '';
      _rueEmetteur.text = d['rueElevage'] ?? '';
      _cpEmetteur.text = d['codePostalElevage'] ?? '';
      _villeEmetteur.text = d['villeElevage'] ?? '';
      _paysEmetteur.text = d['paysElevage'] ?? 'France';
      _telEmetteur.text = d['numeroElevage'] ?? d['phone_number'] ?? '';
      _siretEmetteur.text = d['siret'] ?? '';
      _tvaEmetteur.text = d['numeroTVA'] ?? '';
      _emailEmetteur.text = d['email'] ?? '';
      _numeroFacture.text = (last + 1).toString();
    });
  }

  Future<void> _pickDate(String field) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('fr'),
    );
    if (picked == null) return;
    final formatted = DateFormat('dd/MM/yyyy').format(picked);
    setState(() {
      if (field == 'facture') _dateFacture = formatted;
      if (field == 'prestation') _datePrestation = formatted;
      if (field == 'echeance') _dateEcheance = formatted;
    });
  }

  double get _totalHT => _lignes.fold(0, (s, l) => s + l.totalHT);
  double get _totalTVA => _lignes.fold(0, (s, l) => s + l.montantTVA);
  double get _totalTTC => _franchise ? _totalHT : _totalHT + _totalTVA;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_lignes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajoutez au moins une ligne')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final data = _buildData();
      await FirebaseFirestore.instance
          .collection('users').doc(uid).collection('factures')
          .add(data);
      if (!mounted) return;
      final bytes = await _buildPdf(data);
      await Printing.layoutPdf(onLayout: (_) async => bytes);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, dynamic> _buildData() => {
    'numeroFacture': int.tryParse(_numeroFacture.text) ?? 0,
    'dateFacture': _dateFacture,
    'datePrestation': _datePrestation,
    'dateEcheance': _dateEcheance,
    'nomEmetteur': _nomEmetteur.text,
    'rueEmetteur': _rueEmetteur.text,
    'cpEmetteur': _cpEmetteur.text,
    'villeEmetteur': _villeEmetteur.text,
    'paysEmetteur': _paysEmetteur.text,
    'telEmetteur': _telEmetteur.text,
    'siretEmetteur': _siretEmetteur.text,
    'tvaEmetteur': _tvaEmetteur.text,
    'emailEmetteur': _emailEmetteur.text,
    'prenomClient': _prenomClient.text,
    'nomClient': _nomClient.text,
    'rueClient': _rueClient.text,
    'cpClient': _cpClient.text,
    'villeClient': _villeClient.text,
    'paysClient': _paysClient.text,
    'emailClient': _emailClient.text,
    'telephoneClient': _telClient.text,
    'siretClient': _siretClient.text,
    'tvaClient': _tvaClient.text,
    'lignes': _lignes.map((l) => l.toMap()).toList(),
    'totalHT': _totalHT,
    'totalTVA': _franchise ? 0.0 : _totalTVA,
    'totalTTC': _totalTTC,
    'modePaiement': _modePaiement,
    'delaiPaiement': _delaiPaiement.text,
    'regimeTVA': _franchise ? 'franchise' : 'normal',
    'noteComplementaire': _noteComplementaire.text,
    'statut': 'emise',
    'createdAt': FieldValue.serverTimestamp(),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Nouvelle facture',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── ÉMETTEUR ──
            _SectionTitle('Votre entreprise'),
            _Card(child: Column(children: [
              _Field(ctrl: _nomEmetteur, label: 'Nom / raison sociale', required: true),
              _Field(ctrl: _rueEmetteur, label: 'Rue', required: true),
              Row(children: [
                Expanded(child: _Field(ctrl: _cpEmetteur, label: 'Code postal', keyboard: TextInputType.number)),
                const SizedBox(width: 12),
                Expanded(child: _Field(ctrl: _villeEmetteur, label: 'Ville', required: true)),
              ]),
              _Field(ctrl: _paysEmetteur, label: 'Pays'),
              _Field(ctrl: _telEmetteur, label: 'Téléphone'),
              _Field(ctrl: _emailEmetteur, label: 'Email', keyboard: TextInputType.emailAddress),
              _Field(ctrl: _siretEmetteur, label: 'SIRET', required: true),
              _Field(ctrl: _tvaEmetteur, label: 'N° TVA intracommunautaire'),
            ])),
            const SizedBox(height: 16),

            // ── CLIENT ──
            _SectionTitle('Client'),
            _Card(child: Column(children: [
              Row(children: [
                Expanded(child: _Field(ctrl: _prenomClient, label: 'Prénom')),
                const SizedBox(width: 12),
                Expanded(child: _Field(ctrl: _nomClient, label: 'Nom / société', required: true)),
              ]),
              _Field(ctrl: _rueClient, label: 'Rue', required: true),
              Row(children: [
                Expanded(child: _Field(ctrl: _cpClient, label: 'Code postal', keyboard: TextInputType.number)),
                const SizedBox(width: 12),
                Expanded(child: _Field(ctrl: _villeClient, label: 'Ville', required: true)),
              ]),
              _Field(ctrl: _paysClient, label: 'Pays'),
              _Field(ctrl: _emailClient, label: 'Email', keyboard: TextInputType.emailAddress),
              _Field(ctrl: _telClient, label: 'Téléphone'),
              _Field(ctrl: _siretClient, label: 'SIRET (si pro, facultatif)'),
              _Field(ctrl: _tvaClient, label: 'N° TVA client (facultatif)'),
            ])),
            const SizedBox(height: 16),

            // ── DÉTAILS FACTURE ──
            _SectionTitle('Détails de la facture'),
            _Card(child: Column(children: [
              _Field(ctrl: _numeroFacture, label: 'Numéro de facture', required: true, keyboard: TextInputType.number),
              const SizedBox(height: 4),
              _DateRow(label: 'Date de facture', value: _dateFacture, onTap: () => _pickDate('facture')),
              _DateRow(label: 'Date de prestation / livraison', value: _datePrestation, onTap: () => _pickDate('prestation')),
              _DateRow(label: 'Date d\'échéance', value: _dateEcheance, onTap: () => _pickDate('echeance')),
              const SizedBox(height: 8),
              _DropdownField(
                label: 'Mode de paiement',
                value: _modePaiement,
                items: const ['Virement bancaire', 'Chèque', 'Espèces', 'Carte bancaire', 'PayPal'],
                onChanged: (v) => setState(() => _modePaiement = v!),
              ),
              _Field(ctrl: _delaiPaiement, label: 'Délai de paiement (jours)', keyboard: TextInputType.number),
            ])),
            const SizedBox(height: 16),

            // ── TVA ──
            _SectionTitle('TVA'),
            _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(_franchise
                    ? 'Franchise en base de TVA'
                    : 'TVA applicable',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600, color: _dark))),
                Switch(
                  value: !_franchise,
                  activeColor: _green,
                  onChanged: (v) => setState(() { _franchise = !v; }),
                ),
              ]),
              if (_franchise)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3CD),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Mention ajoutée sur la facture : "TVA non applicable, art. 293 B du CGI"',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF856404)),
                  ),
                ),
            ])),
            const SizedBox(height: 16),

            // ── LIGNES ──
            _SectionTitle('Lignes de facturation'),
            ..._lignes.asMap().entries.map((e) => _LigneCard(
              index: e.key,
              ligne: e.value,
              franchise: _franchise,
              onChanged: () => setState(() {}),
              onDelete: () => setState(() => _lignes.removeAt(e.key)),
            )),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.add, color: _green),
              label: const Text('Ajouter une ligne', style: TextStyle(fontFamily: 'Galey', color: _green, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _green),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                minimumSize: const Size(double.infinity, 0),
              ),
              onPressed: () => setState(() => _lignes.add(_Ligne())),
            ),
            const SizedBox(height: 16),

            // ── TOTAUX ──
            if (_lignes.isNotEmpty) ...[
              _Card(child: Column(children: [
                if (!_franchise) ...[
                  _TotalRow(label: 'Total HT', value: '${_totalHT.toStringAsFixed(2)} €'),
                  _TotalRow(label: 'TVA', value: '${_totalTVA.toStringAsFixed(2)} €'),
                ],
                _TotalRow(label: 'Total TTC', value: '${_totalTTC.toStringAsFixed(2)} €', bold: true),
              ])),
              const SizedBox(height: 16),
            ],

            // ── NOTE ──
            _SectionTitle('Note / informations complémentaires'),
            _Card(child: TextFormField(
              controller: _noteComplementaire,
              maxLines: 4,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Conditions particulières, coordonnées bancaires (IBAN/BIC), références commande…',
                hintStyle: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade400),
                border: InputBorder.none,
              ),
            )),
            const SizedBox(height: 16),
            _MentionsLegales(franchise: _franchise),
            const SizedBox(height: 24),

            // ── BOUTON ──
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check, color: Colors.white),
                label: const Text('Enregistrer et imprimer',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _saving ? null : _save,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// LIGNE MODEL
// ─────────────────────────────────────────────────────────────
class _Ligne {
  final designation = TextEditingController();
  final description = TextEditingController();
  final quantite = TextEditingController(text: '1');
  final prixHT = TextEditingController(text: '0.00');
  double tauxTVA = 20.0;

  double get _qty => double.tryParse(quantite.text) ?? 1;
  double get _pu => double.tryParse(prixHT.text) ?? 0;
  double get totalHT => _qty * _pu;
  double get montantTVA => totalHT * tauxTVA / 100;
  double get totalTTC => totalHT + montantTVA;

  Map<String, dynamic> toMap() => {
    'designation': designation.text,
    'description': description.text,
    'quantite': double.tryParse(quantite.text) ?? 1,
    'prixUnitaireHT': double.tryParse(prixHT.text) ?? 0,
    'tauxTVA': tauxTVA,
    'totalHT': totalHT,
    'montantTVA': montantTVA,
    'totalTTC': totalTTC,
  };
}

class _LigneCard extends StatefulWidget {
  final int index;
  final _Ligne ligne;
  final bool franchise;
  final VoidCallback onChanged;
  final VoidCallback onDelete;
  const _LigneCard({required this.index, required this.ligne, required this.franchise, required this.onChanged, required this.onDelete});

  @override
  State<_LigneCard> createState() => _LigneCardState();
}

class _LigneCardState extends State<_LigneCard> {
  @override
  Widget build(BuildContext context) {
    final l = widget.ligne;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: const Color(0xFFEEF5EA), borderRadius: BorderRadius.circular(6)),
            child: Text('Ligne ${widget.index + 1}',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: _green, fontWeight: FontWeight.w600)),
          ),
          const Spacer(),
          IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20), onPressed: widget.onDelete, padding: EdgeInsets.zero),
        ]),
        const SizedBox(height: 8),
        _Field(ctrl: l.designation, label: 'Désignation (objet de la vente/prestation)', required: true, onChanged: (_) => widget.onChanged()),
        _Field(ctrl: l.description, label: 'Description détaillée (facultatif)', onChanged: (_) => widget.onChanged()),
        Row(children: [
          Expanded(child: _Field(ctrl: l.quantite, label: 'Quantité', keyboard: TextInputType.number, onChanged: (_) { setState(() {}); widget.onChanged(); })),
          const SizedBox(width: 12),
          Expanded(child: _Field(ctrl: l.prixHT, label: 'Prix unitaire HT (€)', keyboard: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) { setState(() {}); widget.onChanged(); })),
        ]),
        if (!widget.franchise) ...[
          const SizedBox(height: 8),
          Text('Taux TVA : ${l.tauxTVA.toStringAsFixed(0)} %',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _dark)),
          Wrap(spacing: 6, children: [5.5, 10.0, 20.0].map((t) {
            final active = l.tauxTVA == t;
            return ChoiceChip(
              label: Text('${t.toStringAsFixed(t == 5.5 ? 1 : 0)} %'),
              selected: active,
              selectedColor: _green,
              labelStyle: TextStyle(fontFamily: 'Galey', fontSize: 11, color: active ? Colors.white : _dark),
              onSelected: (_) => setState(() { l.tauxTVA = t; widget.onChanged(); }),
            );
          }).toList()),
        ],
        if (l.totalHT > 0) ...[
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Text(
              widget.franchise
                  ? 'Total : ${l.totalHT.toStringAsFixed(2)} €'
                  : 'HT: ${l.totalHT.toStringAsFixed(2)} €  |  TTC: ${l.totalTTC.toStringAsFixed(2)} €',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: _dark),
            ),
          ]),
        ],
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// PDF GENERATION
// ─────────────────────────────────────────────────────────────
Future<Uint8List> _buildPdf(Map<String, dynamic> d) async {
  final pdf = pw.Document();
  final font = await PdfGoogleFonts.robotoRegular();
  final bold = await PdfGoogleFonts.robotoBold();
  final lignes = List<Map<String, dynamic>>.from(d['lignes'] ?? []);
  final franchise = d['regimeTVA'] == 'franchise';
  final totalHT = (d['totalHT'] ?? 0.0) as num;
  final totalTVA = (d['totalTVA'] ?? 0.0) as num;
  final totalTTC = (d['totalTTC'] ?? 0.0) as num;
  final tealPdf = PdfColor.fromHex('#0C5C6C');
  final greenPdf = PdfColor.fromHex('#6E9E57');
  final greyLight = PdfColor.fromHex('#F8F8F6');

  pdf.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    build: (ctx) => [
      // Header
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(d['nomEmetteur'] ?? '', style: pw.TextStyle(font: bold, fontSize: 14, color: tealPdf)),
            pw.Text('${d['rueEmetteur'] ?? ''}', style: pw.TextStyle(font: font, fontSize: 10)),
            pw.Text('${d['cpEmetteur'] ?? ''} ${d['villeEmetteur'] ?? ''}', style: pw.TextStyle(font: font, fontSize: 10)),
            pw.Text(d['paysEmetteur'] ?? '', style: pw.TextStyle(font: font, fontSize: 10)),
            if ((d['siretEmetteur'] ?? '').isNotEmpty)
              pw.Text('SIRET : ${d['siretEmetteur']}', style: pw.TextStyle(font: font, fontSize: 9)),
            if ((d['tvaEmetteur'] ?? '').isNotEmpty)
              pw.Text('N° TVA : ${d['tvaEmetteur']}', style: pw.TextStyle(font: font, fontSize: 9)),
            if ((d['emailEmetteur'] ?? '').isNotEmpty)
              pw.Text(d['emailEmetteur'], style: pw.TextStyle(font: font, fontSize: 9)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('FACTURE', style: pw.TextStyle(font: bold, fontSize: 22, color: tealPdf)),
            pw.Text('N° ${d['numeroFacture']}', style: pw.TextStyle(font: bold, fontSize: 14)),
            pw.SizedBox(height: 6),
            pw.Text('Date : ${d['dateFacture'] ?? ''}', style: pw.TextStyle(font: font, fontSize: 10)),
            pw.Text('Prestation : ${d['datePrestation'] ?? ''}', style: pw.TextStyle(font: font, fontSize: 10)),
            if ((d['dateEcheance'] ?? '').isNotEmpty)
              pw.Text('Échéance : ${d['dateEcheance']}', style: pw.TextStyle(font: bold, fontSize: 10)),
          ]),
        ],
      ),
      pw.SizedBox(height: 20),
      // Client block
      pw.Container(
        alignment: pw.Alignment.centerRight,
        child: pw.Container(
          width: 220,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: greyLight,
            border: pw.Border.all(color: PdfColor.fromHex('#E0E0E0')),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('DESTINATAIRE', style: pw.TextStyle(font: bold, fontSize: 8, color: PdfColor.fromHex('#888888'))),
            pw.SizedBox(height: 4),
            pw.Text('${d['prenomClient'] ?? ''} ${d['nomClient'] ?? ''}'.trim(), style: pw.TextStyle(font: bold, fontSize: 11)),
            pw.Text('${d['rueClient'] ?? ''}', style: pw.TextStyle(font: font, fontSize: 10)),
            pw.Text('${d['cpClient'] ?? ''} ${d['villeClient'] ?? ''}', style: pw.TextStyle(font: font, fontSize: 10)),
            pw.Text(d['paysClient'] ?? '', style: pw.TextStyle(font: font, fontSize: 10)),
            if ((d['emailClient'] ?? '').isNotEmpty)
              pw.Text(d['emailClient'], style: pw.TextStyle(font: font, fontSize: 9)),
          ]),
        ),
      ),
      pw.SizedBox(height: 20),
      // Table
      pw.Table(
        border: pw.TableBorder(bottom: pw.BorderSide(color: PdfColor.fromHex('#E0E0E0'))),
        columnWidths: franchise
            ? {0: const pw.FlexColumnWidth(4), 1: const pw.FlexColumnWidth(1), 2: const pw.FlexColumnWidth(2), 3: const pw.FlexColumnWidth(2)}
            : {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(1), 2: const pw.FlexColumnWidth(1.5), 3: const pw.FlexColumnWidth(1), 4: const pw.FlexColumnWidth(1.5)},
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: tealPdf),
            children: [
              _pdfCell('Désignation', bold, white: true),
              _pdfCell('Qté', bold, white: true, center: true),
              _pdfCell('Prix HT', bold, white: true, center: true),
              if (!franchise) _pdfCell('TVA', bold, white: true, center: true),
              _pdfCell('Total TTC', bold, white: true, center: true),
            ],
          ),
          ...lignes.map((l) => pw.TableRow(
            decoration: pw.BoxDecoration(color: lignes.indexOf(l).isEven ? PdfColors.white : greyLight),
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(l['designation'] ?? '', style: pw.TextStyle(font: bold, fontSize: 10)),
                  if ((l['description'] ?? '').isNotEmpty)
                    pw.Text(l['description'], style: pw.TextStyle(font: font, fontSize: 9, color: PdfColor.fromHex('#666666'))),
                ]),
              ),
              _pdfCell(l['quantite']?.toStringAsFixed(0) ?? '1', font, center: true),
              _pdfCell('${(l['prixUnitaireHT'] ?? 0.0).toStringAsFixed(2)} €', font, center: true),
              if (!franchise) _pdfCell('${(l['tauxTVA'] ?? 20.0).toStringAsFixed(0)} %', font, center: true),
              _pdfCell('${(l['totalTTC'] ?? l['totalHT'] ?? 0.0).toStringAsFixed(2)} €', bold, center: true),
            ],
          )),
        ],
      ),
      pw.SizedBox(height: 16),
      // Totaux
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Container(
          width: 200,
          child: pw.Column(children: [
            if (!franchise) ...[
              _pdfTotalRow('Total HT', '${totalHT.toStringAsFixed(2)} €', font),
              _pdfTotalRow('TVA', '${totalTVA.toStringAsFixed(2)} €', font),
            ],
            pw.Container(
              color: tealPdf,
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('TOTAL TTC', style: pw.TextStyle(font: bold, fontSize: 11, color: PdfColors.white)),
                pw.Text('${totalTTC.toStringAsFixed(2)} €', style: pw.TextStyle(font: bold, fontSize: 11, color: PdfColors.white)),
              ]),
            ),
          ]),
        ),
      ),
      pw.SizedBox(height: 16),
      // Paiement
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: greyLight,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('Mode de paiement : ${d['modePaiement'] ?? ''}', style: pw.TextStyle(font: font, fontSize: 10)),
          if ((d['delaiPaiement'] ?? '').isNotEmpty)
            pw.Text('Délai de règlement : ${d['delaiPaiement']} jours', style: pw.TextStyle(font: font, fontSize: 10)),
          if ((d['noteComplementaire'] ?? '').isNotEmpty)
            pw.Text(d['noteComplementaire'], style: pw.TextStyle(font: font, fontSize: 9)),
        ]),
      ),
      pw.SizedBox(height: 16),
      // Mentions légales
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColor.fromHex('#CCCCCC'))),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          if (franchise)
            pw.Text('TVA non applicable, art. 293 B du CGI.', style: pw.TextStyle(font: bold, fontSize: 9)),
          pw.Text(
            'En cas de retard de paiement, des pénalités de retard au taux de 3 fois le taux d\'intérêt légal en vigueur seront appliquées, ainsi qu\'une indemnité forfaitaire de recouvrement de 40 €.',
            style: pw.TextStyle(font: font, fontSize: 8, color: PdfColor.fromHex('#555555')),
          ),
        ]),
      ),
    ],
  ));

  return pdf.save();
}

pw.Widget _pdfCell(String text, pw.Font font, {bool white = false, bool center = false}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
  child: pw.Text(text,
    textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
    style: pw.TextStyle(font: font, fontSize: 10, color: white ? PdfColors.white : PdfColors.black)),
);

pw.Widget _pdfTotalRow(String label, String value, pw.Font font) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
  child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
    pw.Text(label, style: pw.TextStyle(font: font, fontSize: 10)),
    pw.Text(value, style: pw.TextStyle(font: font, fontSize: 10)),
  ]),
);

// ─────────────────────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: _teal)),
  );
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
    ),
    child: child,
  );
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final bool required;
  final TextInputType keyboard;
  final void Function(String)? onChanged;

  const _Field({
    required this.ctrl,
    required this.label,
    this.required = false,
    this.keyboard = TextInputType.text,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: ctrl,
      keyboardType: keyboard,
      style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
      onChanged: onChanged,
      validator: required ? (v) => (v == null || v.isEmpty) ? 'Champ requis' : null : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500),
        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: _green)),
        isDense: true,
      ),
    ),
  );
}

class _DropdownField extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final void Function(String?) onChanged;
  const _DropdownField({required this.label, required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500),
        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: _green)),
        isDense: true,
      ),
      items: items.map((i) => DropdownMenuItem(value: i, child: Text(i, style: const TextStyle(fontFamily: 'Galey', fontSize: 14)))).toList(),
      onChanged: onChanged,
    ),
  );
}

class _DateRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  const _DateRow({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: GestureDetector(
      onTap: onTap,
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
          Text(value, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: _dark)),
        ])),
        const Icon(Icons.calendar_today_outlined, color: _green, size: 18),
      ]),
    ),
  );
}

class _DateChip extends StatelessWidget {
  final String label;
  final String value;
  const _DateChip({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
    Text(value, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600, color: _dark)),
  ]);
}

class _InfoBlock extends StatelessWidget {
  final String title;
  final List<String> lines;
  const _InfoBlock({required this.title, required this.lines});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4)],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w700, color: _teal)),
      const SizedBox(height: 6),
      ...lines.where((l) => l.trim().isNotEmpty).map((l) =>
          Text(l, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _dark))),
    ]),
  );
}

class _TableHeader extends StatelessWidget {
  final bool franchise;
  const _TableHeader({required this.franchise});
  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFFEEF5EA),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: Row(children: [
      const Expanded(flex: 3, child: Text('Désignation', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: _teal))),
      const _Th('Qté'),
      const _Th('HT'),
      if (!franchise) const _Th('TVA'),
      const _Th('TTC'),
    ]),
  );
}

class _Th extends StatelessWidget {
  final String text;
  const _Th(this.text);
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 52,
    child: Text(text, textAlign: TextAlign.right, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: _teal)),
  );
}

class _TableRow extends StatelessWidget {
  final Map<String, dynamic> ligne;
  final bool franchise;
  const _TableRow({required this.ligne, required this.franchise});
  @override
  Widget build(BuildContext context) {
    final totalTTC = (ligne['totalTTC'] ?? ligne['totalHT'] ?? 0.0) as num;
    final totalHT = (ligne['totalHT'] ?? 0.0) as num;
    final montantTVA = (ligne['montantTVA'] ?? 0.0) as num;
    final qty = (ligne['quantite'] ?? 1.0) as num;
    final tva = (ligne['tauxTVA'] ?? 20.0) as num;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ligne['designation'] ?? '', style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600, color: _dark)),
          if ((ligne['description'] ?? '').isNotEmpty)
            Text(ligne['description'], style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
        ])),
        SizedBox(width: 52, child: Text(qty.toStringAsFixed(0), textAlign: TextAlign.right, style: const TextStyle(fontFamily: 'Galey', fontSize: 12))),
        SizedBox(width: 52, child: Text('${totalHT.toStringAsFixed(2)}', textAlign: TextAlign.right, style: const TextStyle(fontFamily: 'Galey', fontSize: 12))),
        if (!franchise) SizedBox(width: 52, child: Text('${tva.toStringAsFixed(0)}%', textAlign: TextAlign.right, style: const TextStyle(fontFamily: 'Galey', fontSize: 12))),
        SizedBox(width: 52, child: Text('${totalTTC.toStringAsFixed(2)} €', textAlign: TextAlign.right, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: _dark))),
      ]),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _TotalRow({required this.label, required this.value, this.bold = false});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: bold ? FontWeight.w700 : FontWeight.normal, color: bold ? _dark : Colors.grey.shade600)),
      Text(value, style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: bold ? FontWeight.w700 : FontWeight.normal, color: bold ? _dark : Colors.grey.shade700)),
    ]),
  );
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      Text('$label : ', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500)),
      Text(value, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600, color: _dark)),
    ]),
  );
}

class _MentionsLegales extends StatelessWidget {
  final bool franchise;
  const _MentionsLegales({required this.franchise});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF0F4F8),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Mentions légales obligatoires',
          style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: _teal)),
      const SizedBox(height: 6),
      if (franchise) ...[
        const Text('• TVA non applicable, art. 293 B du CGI',
            style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: _dark)),
        const SizedBox(height: 2),
      ],
      Text(
        '• Pénalités de retard : 3× le taux d\'intérêt légal en vigueur (${DateTime.now().year}), exigibles le lendemain de la date d\'échéance.',
        style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: _dark),
      ),
      const SizedBox(height: 2),
      const Text('• Indemnité forfaitaire de recouvrement en cas de retard : 40 €.',
          style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: _dark)),
    ]),
  );
}
