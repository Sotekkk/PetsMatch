import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/widgets/rich_text_view.dart';

/// Vue lecture seule côté propriétaire du suivi éducatif : plan de travail
/// (objectifs, `education_objectifs`) + rapports de séance (`education_progression`,
/// alimentée par `education_suivi_page.dart` / `mes-patients/[id]`).
class EducationRapportsPage extends StatefulWidget {
  final String? animalId;
  final String animalNom;
  const EducationRapportsPage({super.key, required this.animalId, required this.animalNom});

  @override
  State<EducationRapportsPage> createState() => _EducationRapportsPageState();
}

const _kCategories = <String, String>{
  'rappel': 'Rappel', 'laisse': 'Marche en laisse', 'proprete': 'Propreté',
  'aboiements': 'Aboiements', 'destruction': 'Destruction',
  'socialisation_chien': 'Socialisation chiens', 'socialisation_humain': 'Socialisation humains',
  'manipulation': 'Manipulation / soins', 'solitude': 'Solitude',
  'agressivite': 'Agressivité', 'peurs': 'Peurs', 'autre': 'Autre',
};
const _kStatutLabels = {
  'a_travailler': 'À travailler', 'en_cours': 'En cours', 'acquis': 'Acquis',
};
Color _statutColor(String s) => switch (s) {
      'acquis' => const Color(0xFF6E9E57),
      'en_cours' => const Color(0xFFEFA100),
      _ => const Color(0xFFD5573B),
    };

class _EducationRapportsPageState extends State<EducationRapportsPage> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _rapports = [];
  List<Map<String, dynamic>> _objectifs = [];
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
      List objs = const [];
      try {
        objs = await _supa.from('education_objectifs').select()
            .eq('animal_id', widget.animalId!).order('ordre').order('created_at');
      } catch (_) {}
      if (mounted) {
        setState(() {
          _rapports = List<Map<String, dynamic>>.from(rows as List);
          _objectifs = List<Map<String, dynamic>>.from(objs);
          _loading = false;
        });
      }
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
          : (_rapports.isEmpty && _objectifs.isEmpty)
              ? Center(child: Text('Aucun suivi pour l\'instant.',
                  style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade400)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_objectifs.isNotEmpty) ...[
                      _sectionTitle('Plan de travail'),
                      ..._objectifs.map(_objectifCard),
                      const SizedBox(height: 18),
                    ],
                    if (_rapports.isNotEmpty) ...[
                      _sectionTitle('Comptes rendus de séance'),
                      ..._rapports.map(_rapportCard),
                    ],
                  ],
                ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t.toUpperCase(),
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                fontSize: 11, letterSpacing: 0.5, color: Colors.grey.shade500)),
      );

  Widget _objectifCard(Map<String, dynamic> o) {
    final statut = o['statut']?.toString() ?? 'a_travailler';
    final cat = o['categorie']?.toString();
    final color = _statutColor(statut);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(o['libelle']?.toString() ?? '',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13))),
          Text(_kStatutLabels[statut] ?? statut,
              style: TextStyle(fontFamily: 'Galey', fontSize: 10, fontWeight: FontWeight.w600, color: color)),
        ]),
        if (cat != null && _kCategories[cat] != null) ...[
          const SizedBox(height: 4),
          Text(_kCategories[cat]!, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
        ],
        if ((o['note']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 4),
          RichTextView(o['note'].toString(), style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
        ],
      ]),
    );
  }

  Widget _rapportCard(Map<String, dynamic> r) {
    final date = r['date_seance']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(date, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
        const SizedBox(height: 6),
        RichTextView(r['contenu']?.toString() ?? '',
            style: const TextStyle(fontFamily: 'Galey', fontSize: 13, height: 1.4, color: Color(0xFF1F2A2E))),
        if ((r['exercices_conseilles']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFFEEF5EA), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('🏋️ Exercices conseillés',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 11, color: Color(0xFF4A7A32))),
              const SizedBox(height: 2),
              Text(r['exercices_conseilles'].toString(),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF4A7A32))),
            ]),
          ),
        ],
      ]),
    );
  }
}
