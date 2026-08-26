import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
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
  Set<String> _authorizedTemplateIds = {};
  bool _loading = true;
  String? _uid;

  bool get _isEmployeeMode => widget.employerUid != null;
  bool get _canWrite => !_isEmployeeMode || widget.employePerms.contains('write_protocoles');
  // Profil de l'utilisateur CONNECTÉ (pas widget.employerProfileId, qui est
  // celui de l'employeur) — sert à distinguer "mes protocoles" de ceux de
  // l'élevage quand on agit pour un employeur.
  String get _myProfileId => User_Info.activeProfileId;

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
      await _loadAuthorizations();
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

  // Protocoles de l'élevage que CET employé est spécifiquement autorisé à
  // appliquer (par défaut, un employé ne peut appliquer que ses propres
  // protocoles — voir migration_plan_template_autorisations.sql).
  Future<void> _loadAuthorizations() async {
    if (!_isEmployeeMode || _myProfileId.isEmpty) { _authorizedTemplateIds = {}; return; }
    try {
      final rows = await Supabase.instance.client
          .from('plan_template_autorisations')
          .select('template_id')
          .eq('employe_profile_id', _myProfileId);
      _authorizedTemplateIds = (rows as List).map((r) => r['template_id'] as String).toSet();
    } catch (_) {
      _authorizedTemplateIds = {};
    }
  }

  Future<void> _manageAuthorizations(Map<String, dynamic> template) async {
    final ownerProfileId = widget.employerProfileId ??
        (User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null);
    if (ownerProfileId == null) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ProtocolAuthSheet(
        templateId: template['id'] as String,
        templateNom: template['nom'] as String? ?? '',
        eleveurProfileId: ownerProfileId,
      ),
    );
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
                    final isOwnerProtocol = creatorProfileId == null || creatorProfileId == widget.employerProfileId;
                    final isMine = _isEmployeeMode && _myProfileId.isNotEmpty && creatorProfileId == _myProfileId;
                    final creatorName = isOwnerProtocol
                        ? null
                        : (isMine ? 'Vous' : _creatorNames[creatorProfileId]);
                    final canEditThis = _isEmployeeMode ? (_canWrite && isMine) : _canWrite;
                    final canApply = !_isEmployeeMode || isMine || _authorizedTemplateIds.contains(t['id']);
                    return _TemplateCard(
                      template: t,
                      creatorName: creatorName,
                      isOwnerProtocol: isOwnerProtocol,
                      isEmployeeMode: _isEmployeeMode,
                      canWrite: canEditThis,
                      canApply: canApply,
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
                      onManageAuth: _isEmployeeMode ? null : () => _manageAuthorizations(t),
                      onApply: !canApply ? null : () => showModalBottomSheet(
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
  final bool isOwnerProtocol;
  final bool isEmployeeMode;
  final bool canWrite;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool canApply;
  final VoidCallback? onApply;
  final VoidCallback onPrint;
  final VoidCallback? onManageAuth;

  const _TemplateCard({
    required this.template, this.creatorName, this.isOwnerProtocol = false, this.isEmployeeMode = false,
    required this.canWrite, this.canApply = true,
    required this.onEdit, required this.onDelete, required this.onApply, required this.onPrint,
    this.onManageAuth,
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
                          if (isEmployeeMode && isOwnerProtocol) ...[
                            const SizedBox(width: 6),
                            _Badge(label: '🏠 Élevage', color: Colors.grey.shade500),
                          ],
                          if (creatorName != null && creatorName!.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            _Badge(label: '👤 $creatorName', color: const Color(0xFFC2740B)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (isEmployeeMode && !canWrite)
                  const Padding(
                    padding: EdgeInsets.only(right: 2),
                    child: Tooltip(
                      message: 'Protocole de l\'élevage — non modifiable',
                      child: Icon(Icons.lock_outline, size: 16, color: Color(0xFFBFC5C9)),
                    ),
                  ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit' && onEdit != null)   onEdit!();
                    if (v == 'delete' && onDelete != null) onDelete!();
                    if (v == 'print')  onPrint();
                    if (v == 'auth' && onManageAuth != null) onManageAuth!();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'print', child: Row(children: [
                      Icon(Icons.print_outlined, size: 16, color: Color(0xFF0C5C6C)),
                      SizedBox(width: 8),
                      Text('Imprimer', style: TextStyle(fontFamily: 'Galey')),
                    ])),
                    if (onManageAuth != null)
                      const PopupMenuItem(value: 'auth', child: Row(children: [
                        Icon(Icons.lock_open_outlined, size: 16, color: Color(0xFF0C5C6C)),
                        SizedBox(width: 8),
                        Text('Autorisations', style: TextStyle(fontFamily: 'Galey')),
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
              child: canApply
                  ? ElevatedButton.icon(
                      onPressed: onApply,
                      icon: const Icon(Icons.play_arrow_rounded, size: 18, color: Colors.white),
                      label: const Text('Appliquer ce protocole', style: TextStyle(fontFamily: 'Galey', color: Colors.white, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    )
                  : Tooltip(
                      message: 'Non autorisé par l\'élevage à appliquer ce protocole',
                      child: ElevatedButton.icon(
                        onPressed: null,
                        icon: Icon(Icons.lock_outline, size: 18, color: Colors.grey.shade500),
                        label: Text('Non autorisé', style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade200,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
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

// ─── Sheet : gérer quels employés peuvent APPLIQUER ce protocole ──────────────

class _ProtocolAuthSheet extends StatefulWidget {
  final String templateId;
  final String templateNom;
  final String eleveurProfileId;
  const _ProtocolAuthSheet({required this.templateId, required this.templateNom, required this.eleveurProfileId});

  @override
  State<_ProtocolAuthSheet> createState() => _ProtocolAuthSheetState();
}

class _ProtocolAuthSheetState extends State<_ProtocolAuthSheet> {
  static const _green = Color(0xFF0C5C6C);
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _employes = [];
  Set<String> _authorized = {};
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final empRows = await _supa.from('employes').select()
          .eq('eleveur_profile_id', widget.eleveurProfileId).eq('actif', true);
      final result = <Map<String, dynamic>>[];
      for (final e in (empRows as List)) {
        final employeProfileId = e['employe_profile_id'] as String?;
        if (employeProfileId == null) continue;
        final u = await _supa.from('user_profiles')
            .select('firstname, lastname').eq('id', employeProfileId).maybeSingle();
        final nom = u != null ? '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim() : 'Employé';
        result.add({'employe_profile_id': employeProfileId, 'nom': nom.isEmpty ? 'Employé' : nom});
      }
      final authRows = await _supa.from('plan_template_autorisations')
          .select('employe_profile_id').eq('template_id', widget.templateId);
      if (mounted) setState(() {
        _employes = result;
        _authorized = (authRows as List).map((r) => r['employe_profile_id'] as String).toSet();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(String employeProfileId, bool value) async {
    setState(() => value ? _authorized.add(employeProfileId) : _authorized.remove(employeProfileId));
    if (value) {
      await _supa.from('plan_template_autorisations').insert({
        'template_id': widget.templateId,
        'employe_profile_id': employeProfileId,
      });
    } else {
      await _supa.from('plan_template_autorisations').delete()
          .eq('template_id', widget.templateId).eq('employe_profile_id', employeProfileId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        Text('Qui peut appliquer "${widget.templateNom}" ?',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 4),
        Text('Par défaut, un employé ne peut appliquer que ses propres protocoles.',
            style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: _green)))
        else if (_employes.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Aucun employé actif.', style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade400)),
          )
        else
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _employes.length,
              itemBuilder: (_, i) {
                final e = _employes[i];
                final id = e['employe_profile_id'] as String;
                final checked = _authorized.contains(id);
                return SwitchListTile(
                  value: checked,
                  onChanged: (v) => _toggle(id, v),
                  activeThumbColor: _green,
                  title: Text(e['nom'] as String, style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
                  contentPadding: EdgeInsets.zero,
                );
              },
            ),
          ),
      ]),
    );
  }
}
