import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:PetsMatch/services/planning_service.dart';
import 'package:PetsMatch/pages/eleveur/planning/plan_template_form_page.dart';
import 'package:PetsMatch/pages/eleveur/planning/apply_plan_sheet.dart';

class PlanTemplateListPage extends StatefulWidget {
  const PlanTemplateListPage({super.key});
  @override
  State<PlanTemplateListPage> createState() => _PlanTemplateListPageState();
}

class _PlanTemplateListPageState extends State<PlanTemplateListPage> {
  static const _green = Color(0xFF6E9E57);
  static const _dark  = Color(0xFF1F2A2E);

  List<Map<String, dynamic>> _templates = [];
  bool _loading = true;
  String? _uid;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _load();
  }

  Future<void> _load() async {
    if (_uid == null) return;
    setState(() => _loading = true);
    final rows = await PlanningService.loadTemplates(_uid!);
    if (mounted) setState(() { _templates = rows; _loading = false; });
  }

  Future<void> _delete(String id, String nom) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer ce protocole ?', style: TextStyle(fontFamily: 'Galey')),
        content: Text('Le protocole "$nom" sera supprimé définitivement.',
            style: const TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await PlanningService.deleteTemplate(id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _dark,
        foregroundColor: Colors.white,
        title: const Text('Mes protocoles', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _green,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Nouveau', style: TextStyle(fontFamily: 'Galey', color: Colors.white, fontWeight: FontWeight.w600)),
        onPressed: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => const PlanTemplateFormPage(),
        )).then((_) => _load()),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _green))
          : _templates.isEmpty
              ? _emptyState()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                  itemCount: _templates.length,
                  itemBuilder: (_, i) => _TemplateCard(
                    template: _templates[i],
                    onEdit: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => PlanTemplateFormPage(existing: _templates[i]),
                    )).then((_) => _load()),
                    onDelete: () => _delete(_templates[i]['id'] as String, _templates[i]['nom'] as String),
                    onApply: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                      builder: (_) => ApplyPlanSheet(
                        template: _templates[i],
                        uid: _uid!,
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _emptyState() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.playlist_add_outlined, size: 72, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        Text('Aucun protocole créé',
            style: TextStyle(fontFamily: 'Galey', fontSize: 16, color: Colors.grey.shade500)),
        const SizedBox(height: 8),
        Text(
          'Créez des protocoles réutilisables\npour vos soins, nettoyages et rondes',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade400),
        ),
      ],
    ),
  );
}

// ─── Carte template ───────────────────────────────────────────────────────────

class _TemplateCard extends StatelessWidget {
  final Map<String, dynamic> template;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onApply;

  const _TemplateCard({required this.template, required this.onEdit, required this.onDelete, required this.onApply});

  static const _green = Color(0xFF6E9E57);

  String get _typeLabel => switch (template['type'] as String? ?? '') {
    'sanitaire'    => 'Sanitaire',
    'nettoyage'    => 'Nettoyage',
    'promenade'    => 'Promenade',
    'socialisation'=> 'Socialisation',
    _              => 'Autre',
  };

  Color get _typeColor => switch (template['type'] as String? ?? '') {
    'sanitaire'    => const Color(0xFF6E9E57),
    'nettoyage'    => const Color(0xFF0C5C6C),
    'promenade'    => const Color(0xFF9B59B6),
    'socialisation'=> const Color(0xFFE67E22),
    _              => Colors.grey,
  };

  String get _typeEmoji => switch (template['type'] as String? ?? '') {
    'sanitaire'    => '💊',
    'nettoyage'    => '🧹',
    'promenade'    => '🦮',
    'socialisation'=> '🐾',
    _              => '📋',
  };

  int get _etapeCount {
    final etapes = template['plan_template_etapes'];
    if (etapes is List) return etapes.length;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final espece = template['espece']?.toString();
    final desc   = template['description']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(_typeEmoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        template['nom'] as String? ?? '',
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1F2A2E)),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          _Badge(label: _typeLabel, color: _typeColor),
                          if (espece != null && espece.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            _Badge(label: espece, color: Colors.grey.shade400),
                          ],
                          const SizedBox(width: 6),
                          _Badge(label: '$_etapeCount étape${_etapeCount > 1 ? 's' : ''}', color: Colors.grey.shade300),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') onEdit();
                    if (v == 'delete') onDelete();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Modifier', style: TextStyle(fontFamily: 'Galey'))),
                    const PopupMenuItem(value: 'delete', child: Text('Supprimer', style: TextStyle(fontFamily: 'Galey', color: Colors.red))),
                  ],
                  child: const Icon(Icons.more_vert, color: Color(0xFF9CA3AF)),
                ),
              ],
            ),
            if (desc != null && desc.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(desc, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onApply,
                icon: const Icon(Icons.play_arrow_rounded, size: 18, color: Colors.white),
                label: const Text('Appliquer ce protocole', style: TextStyle(fontFamily: 'Galey', color: Colors.white, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
