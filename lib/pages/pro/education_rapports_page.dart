import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Vue lecture seule côté propriétaire des rapports de séance envoyés par
/// l'éducateur/comportementaliste (table education_progression, déjà
/// alimentée par pro_clients_page.dart → _addProgression()).
class EducationRapportsPage extends StatefulWidget {
  final String? animalId;
  final String animalNom;
  const EducationRapportsPage({super.key, required this.animalId, required this.animalNom});

  @override
  State<EducationRapportsPage> createState() => _EducationRapportsPageState();
}

class _EducationRapportsPageState extends State<EducationRapportsPage> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _rapports = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.animalId == null) return;
    setState(() => _loading = true);
    try {
      final rows = await _supa.from('education_progression').select()
          .eq('animal_id', widget.animalId!).order('date_seance', ascending: false);
      if (mounted) setState(() { _rapports = List<Map<String, dynamic>>.from(rows as List); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFF7B5EA7),
        foregroundColor: Colors.white,
        title: Text('Suivi — ${widget.animalNom}',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF7B5EA7)))
          : _rapports.isEmpty
              ? Center(child: Text('Aucun rapport de séance pour l\'instant.',
                  style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade400)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _rapports.length,
                  itemBuilder: (_, i) {
                    final r = _rapports[i];
                    final date = r['date_seance']?.toString() ?? '';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(date, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
                        const SizedBox(height: 6),
                        Text(r['contenu']?.toString() ?? '',
                            style: const TextStyle(fontFamily: 'Galey', fontSize: 13, height: 1.4)),
                      ]),
                    );
                  },
                ),
    );
  }
}
