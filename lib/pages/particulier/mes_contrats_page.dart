import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/config.dart';

const _teal  = Color(0xFF0C5C6C);
const _green = Color(0xFF6E9E57);
const _dark  = Color(0xFF1F2A2E);

class MesContratsParticulierPage extends StatefulWidget {
  const MesContratsParticulierPage({super.key});

  @override
  State<MesContratsParticulierPage> createState() => _MesContratsParticulierPageState();
}

class _MesContratsParticulierPageState extends State<MesContratsParticulierPage> {
  static final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _docs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null) { setState(() => _loading = false); return; }
    try {
      final rows = await _supa
          .from('documents_animaux')
          .select('id, type, titre, statut, token, signe_le, created_at, metadata, animaux(nom, espece)')
          .filter('metadata->>acquereur_email', 'eq', email)
          .order('created_at', ascending: false);
      if (mounted) setState(() { _docs = List<Map<String, dynamic>>.from(rows); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F5),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Mes Contrats', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : RefreshIndicator(
              onRefresh: _load,
              color: _teal,
              child: _docs.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 80),
                      Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.folder_open_outlined, size: 64, color: Colors.grey[300]),
                          const SizedBox(height: 16),
                          Text('Aucun contrat pour le moment',
                              style: TextStyle(fontFamily: 'Galey', fontSize: 15, color: Colors.grey[500])),
                          const SizedBox(height: 6),
                          Text('Les contrats transmis par un éleveur\napparaîtront ici',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey[400])),
                        ]),
                      ),
                    ])
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      itemCount: _docs.length,
                      itemBuilder: (context, i) => _DocCard(doc: _docs[i], onRefresh: _load),
                    ),
            ),
    );
  }
}

class _DocCard extends StatelessWidget {
  final Map<String, dynamic> doc;
  final VoidCallback onRefresh;
  const _DocCard({required this.doc, required this.onRefresh});

  static const _typeLabel = {
    'contrat_vente':       '🤝 Contrat de vente',
    'contrat_reservation': '🐾 Contrat de réservation',
    'certificat_cession':  '📋 Certificat de cession',
  };

  @override
  Widget build(BuildContext context) {
    final type   = doc['type'] as String? ?? '';
    final statut = doc['statut'] as String? ?? 'brouillon';
    final token  = doc['token'] as String?;
    final animal = doc['animaux'] as Map?;
    final date   = doc['created_at'] != null
        ? _fmt(DateTime.parse(doc['created_at']).toLocal())
        : '';
    final signeLe = doc['signe_le'] != null
        ? _fmt(DateTime.parse(doc['signe_le']).toLocal())
        : null;
    final signingUrl = token != null ? '$kSiteBaseUrl/signer-contrat/$token' : null;

    final isSigned = statut == 'signe';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSigned ? const Color(0xFF6EE7B7) : const Color(0xFFE5E7EB),
          width: isSigned ? 1.5 : 1,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Titre + badge
          Row(children: [
            Expanded(
              child: Text(_typeLabel[type] ?? '📄 Document',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _dark)),
            ),
            _StatutBadge(statut: statut),
          ]),

          // Animal
          if (animal != null) ...[
            const SizedBox(height: 4),
            Text('${animal['nom'] ?? ''} · ${animal['espece'] ?? ''}',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey[600])),
          ],

          // Date
          const SizedBox(height: 4),
          Row(children: [
            Text(date, style: TextStyle(fontSize: 11, color: Colors.grey[400], fontFamily: 'Galey')),
            if (signeLe != null) ...[
              const SizedBox(width: 8),
              Text('· signé le $signeLe',
                  style: const TextStyle(fontSize: 11, color: _green, fontFamily: 'Galey', fontWeight: FontWeight.w600)),
            ],
          ]),

          // Boutons
          if (signingUrl != null) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => launchUrl(Uri.parse(signingUrl), mode: LaunchMode.externalApplication),
                  icon: Icon(isSigned ? Icons.visibility_outlined : Icons.edit_outlined, size: 16),
                  label: Text(isSigned ? 'Voir le contrat' : 'Consulter & signer',
                      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isSigned ? Colors.white : _teal,
                    foregroundColor: isSigned ? _teal : Colors.white,
                    elevation: 0,
                    side: isSigned ? const BorderSide(color: _teal) : BorderSide.none,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                child: const Icon(Icons.link, size: 18),
              ),
            ]),
          ],
        ]),
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _StatutBadge extends StatelessWidget {
  final String statut;
  const _StatutBadge({required this.statut});

  @override
  Widget build(BuildContext context) {
    final cfg = switch (statut) {
      'signe'      => (bg: const Color(0xFFDCFCE7), fg: const Color(0xFF166534), label: '✅ Signé'),
      'en_attente' => (bg: const Color(0xFFFEF3C7), fg: const Color(0xFF92400E), label: '⏳ En attente'),
      'archive'    => (bg: const Color(0xFFF3F4F6), fg: const Color(0xFF6B7280), label: 'Archivé'),
      _            => (bg: const Color(0xFFF3F4F6), fg: const Color(0xFF6B7280), label: 'Brouillon'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: cfg.bg, borderRadius: BorderRadius.circular(20)),
      child: Text(cfg.label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cfg.fg, fontFamily: 'Galey')),
    );
  }
}
