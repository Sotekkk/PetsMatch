import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/config.dart';

const _kStatutLabels = {
  'brouillon': 'Brouillon', 'envoye': 'Envoyé',
  'accepte': 'Accepté', 'refuse': 'Refusé', 'expire': 'Expiré',
};
const _kStatutColors = {
  'brouillon': Colors.grey, 'envoye': Colors.blue,
  'accepte': Color(0xFF6E9E57), 'refuse': Colors.red, 'expire': Colors.orange,
};

/// Vue lecture seule côté propriétaire des devis reçus d'un éducateur/
/// comportementaliste pour cet animal (table devis, déjà alimentée par
/// education_devis_page.dart côté pro).
class AnimalDevisPage extends StatefulWidget {
  final String? animalId;
  final String animalNom;
  const AnimalDevisPage({super.key, required this.animalId, required this.animalNom});

  @override
  State<AnimalDevisPage> createState() => _AnimalDevisPageState();
}

class _AnimalDevisPageState extends State<AnimalDevisPage> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _devis = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.animalId == null) { setState(() => _loading = false); return; }
    try {
      final rows = await _supa.from('devis').select()
          .eq('animal_id', widget.animalId!).order('created_at', ascending: false);
      if (mounted) setState(() { _devis = List<Map<String, dynamic>>.from(rows as List); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C5C6C),
        foregroundColor: Colors.white,
        title: Text('Devis — ${widget.animalNom}',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0C5C6C)))
          : _devis.isEmpty
              ? Center(child: Text('Aucun devis pour l\'instant.',
                  style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade400)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _devis.length,
                  itemBuilder: (_, i) {
                    final d = _devis[i];
                    final statut = d['statut']?.toString() ?? 'brouillon';
                    final lignes = (d['lignes'] as List?) ?? [];
                    final total = (d['total_ttc'] as num?)?.toDouble() ?? 0;
                    final token = d['token_acceptation']?.toString();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text('${total.toStringAsFixed(2)} €',
                              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15))),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: (_kStatutColors[statut] ?? Colors.grey).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(_kStatutLabels[statut] ?? statut,
                                style: TextStyle(fontFamily: 'Galey', fontSize: 11, fontWeight: FontWeight.w600,
                                    color: _kStatutColors[statut] ?? Colors.grey)),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        for (final l in lignes)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                                '${(l as Map)['description'] ?? ''} — ${l['quantite']} × ${(l['prix_unitaire'] as num?)?.toStringAsFixed(2) ?? ''} €',
                                style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                          ),
                        if (statut != 'brouillon' && token != null) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () => launchUrl(Uri.parse('$kSiteBaseUrl/devis/$token'),
                                  mode: LaunchMode.externalApplication),
                              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF0C5C6C),
                                  side: const BorderSide(color: Color(0xFF0C5C6C))),
                              child: Text(statut == 'envoye' ? 'Voir et répondre' : 'Voir le devis',
                                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ]),
                    );
                  },
                ),
    );
  }
}
