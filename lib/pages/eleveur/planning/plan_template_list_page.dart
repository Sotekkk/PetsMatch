import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/services/planning_service.dart';
import 'package:PetsMatch/services/planning_pdf_service.dart';
import 'package:PetsMatch/pages/eleveur/planning/plan_template_form_page.dart';
import 'package:PetsMatch/pages/eleveur/planning/apply_plan_sheet.dart';

class PlanTemplateListPage extends StatefulWidget {
  final bool isAssociation;
  final String profilSource;
  // Contexte "employé agissant pour un employeur" : quand renseigné, les
  // protocoles sont ceux de cet employeur (pas de l'utilisateur connecté),
  // et la création/édition est soumise à employePerms.
  final String? employerUid;
  final String? employerProfileId;
  final String? employerNom;
  final Set<String> employePerms;

  const PlanTemplateListPage({
    super.key,
    this.isAssociation = false,
    String? profilSource,
    this.employerUid,
    this.employerProfileId,
    this.employerNom,
    this.employePerms = const {},
  }) : profilSource = profilSource ?? (isAssociation ? 'association' : 'eleveur');

  @override
  State<PlanTemplateListPage> createState() => _PlanTemplateListPageState();
}

class _PlanTemplateListPageState extends State<PlanTemplateListPage> {
  static const _green = Color(0xFF0C5C6C);

  List<Map<String, dynamic>> _templates = [];
  Map<String, String> _creatorNames = {};
  bool _loading = true;
  String? _uid;

  bool get _isEmployeeMode => widget.employerUid != null;
  bool get _canWrite => !_isEmployeeMode || widget.employePerms.contains('write_protocoles');

  @override
  void initState() {
    super.initState();
    _uid = widget.employerUid ?? FirebaseAuth.instance.currentUser?.uid;
    _load();
  }

  Future<void> _load() async {
    if (_uid == null) return;
    setState(() => _loading = true);
    try {
      final rows = await PlanningService.loadTemplates(
        _uid!,
        profilSourceOverride: widget.profilSource,
        eleveurProfileIdOverride: widget.employerProfileId,
      );
      await _loadCreatorNames(rows);
      if (mounted) setState(() { _templates = rows; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _templates = []; _loading = false; });
    }
  }

  // Résout le nom des employés créateurs (créé par quelqu'un d'autre que le
  // propriétaire du protocole) pour l'afficher à l'employeur.
  Future<void> _loadCreatorNames(List<Map<String, dynamic>> rows) async {
    final ownerProfileId = widget.employerProfileId;
    final ids = rows
        .map((r) => r['created_by_profile_id'] as String?)
        .whereType<String>()
        .where((id) => id != ownerProfileId)
        .toSet()
        .toList();
    if (ids.isEmpty) {
      _creatorNames = {};
      return;
    }
    try {
      final profRows = await Supabase.instance.client
          .from('user_profiles')
          .select('id, nom, prenom')
          .inFilter('id', ids);
      _creatorNames = {
        for (final p in (profRows as List))
          p['id'] as String: [p['prenom'], p['nom']]
              .where((s) => s != null && (s as String).isNotEmpty)
              .join(' ')
      };
    } catch (_) {
      _creatorNames = {};
    }
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
        backgroundColor: const Color(0xFF0C5C6C),
        foregroundColor: Colors.white,
        title: Text(
          widget.employerNom != null ? 'Protocoles · ${widget.employerNom}' : 'Mes protocoles',
          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButton: !_canWrite ? null : FloatingActionButton.extended(
        backgroundColor: _green,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Nouveau', style: TextStyle(fontFamily: 'Galey', color: Colors.white, fontWeight: FontWeight.w600)),
        onPressed: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => PlanTemplateFormPage(
            profilSource: widget.profilSource,
            employerUid: widget.employerUid,
            employerProfileId: widget.employerProfileId,
          ),
        )).then((_) => _load()),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _green))
          : _templates.isEmpty
              ? _emptyState()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                  itemCount: _templates.length,
                  itemBuilder: (_, i) {
                    final t = _templates[i];
                    final creatorProfileId = t['created_by_profile_id'] as String?;
                    final creatorName = (creatorProfileId != null && creatorProfileId != widget.employerProfileId)
                        ? _creatorNames[creatorProfileId]
                        : null;
                    final canEditThis = _canWrite;
                    return _TemplateCard(
                      template: t,
                      creatorName: creatorName,
                      canWrite: canEditThis,
                      onEdit: !canEditThis ? null : () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => PlanTemplateFormPage(
                          existing: t,
                          profilSource: widget.profilSource,
                          employerUid: widget.employerUid,
                          employerProfileId: widget.employerProfileId,
                        ),
                      )).then((_) => _load()),
                      onDelete: !canEditThis ? null : () => _delete(t['id'] as String, t['nom'] as String),
                      onPrint: () => PlanningPdfService.printProtocole(t),
                      onApply: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.white,
                        shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                        builder: (_) => ApplyPlanSheet(
                          template: t,
                          uid: _uid!,
                          profilSourceOverride: widget.profilSource,
                          eleveurProfileIdOverride: widget.employerProfileId,
                        ),
                      ),
                    );
                  },
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
  final String? creatorName;
  final bool canWrite;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback onApply;
  final VoidCallback onPrint;

  const _TemplateCard({
    required this.template, this.creatorName, required this.canWrite,
    required this.onEdit, required this.onDelete, required this.onApply, required this.onPrint,
  });

  static const _green = Color(0xFF0C5C6C);

  String get _typeLabel => switch (template['type'] as String? ?? '') {
    'sanitaire'    => 'Sanitaire',
    'nettoyage'    => 'Nettoyage',
    'promenade'    => 'Promenade',
    'socialisation'=> 'Socialisation',
    _              => 'Autre',
  };

  Color get _typeColor => switch (template['type'] as String? ?? '') {
    'sanitaire'    => const Color(0xFF0C5C6C),
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
                          if (creatorName != null && creatorName!.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            _Badge(label: '👤 $creatorName', color: const Color(0xFFC2740B)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit' && onEdit != null)   onEdit!();
                    if (v == 'delete' && onDelete != null) onDelete!();
                    if (v == 'print')  onPrint();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'print', child: Row(children: [
                      Icon(Icons.print_outlined, size: 16, color: Color(0xFF0C5C6C)),
                      SizedBox(width: 8),
                      Text('Imprimer', style: TextStyle(fontFamily: 'Galey')),
                    ])),
                    if (canWrite) ...[
                      const PopupMenuItem(value: 'edit',   child: Text('Modifier',  style: TextStyle(fontFamily: 'Galey'))),
                      const PopupMenuItem(value: 'delete', child: Text('Supprimer', style: TextStyle(fontFamily: 'Galey', color: Colors.red))),
                    ],
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
