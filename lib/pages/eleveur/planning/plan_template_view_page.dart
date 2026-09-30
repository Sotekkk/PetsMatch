import 'package:flutter/material.dart';
import 'package:PetsMatch/services/planning_pdf_service.dart';
import 'package:PetsMatch/utils/plan_template_labels.dart';
import 'package:PetsMatch/pages/eleveur/planning/plan_template_form_page.dart';

/// Fiche de synthèse d'un protocole — lecture seule, sans les champs de
/// formulaire (dropdowns, contrôles d'édition…), pensée pour être consultée
/// rapidement ou imprimée (contrôle sanitaire, affichage au chenil).
class PlanTemplateViewPage extends StatelessWidget {
  final Map<String, dynamic> template;
  final bool canWrite;
  final String? profilSource;
  final String? employerUid;
  final String? employerProfileId;

  const PlanTemplateViewPage({
    super.key,
    required this.template,
    this.canWrite = true,
    this.profilSource,
    this.employerUid,
    this.employerProfileId,
  });

  static const _teal = Color(0xFF0C5C6C);
  static const _bg   = Color(0xFFF8F8F6);

  @override
  Widget build(BuildContext context) {
    final nom    = template['nom'] as String? ?? '';
    final type   = template['type'] as String?;
    final espece = template['espece']?.toString() ?? '';
    final desc   = template['description']?.toString() ?? '';
    final etapes = (template['plan_template_etapes'] as List?)
        ?.map((e) => e as Map<String, dynamic>)
        .toList() ?? [];

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Fiche protocole',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Imprimer',
            onPressed: () => PlanningPdfService.printProtocole(template),
          ),
        ],
      ),
      floatingActionButton: !canWrite ? null : FloatingActionButton.extended(
        backgroundColor: _teal,
        icon: const Icon(Icons.edit_outlined, color: Colors.white),
        label: const Text('Modifier', style: TextStyle(fontFamily: 'Galey', color: Colors.white, fontWeight: FontWeight.w600)),
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(
            builder: (_) => PlanTemplateFormPage(
              existing: template,
              profilSource: profilSource,
              employerUid: employerUid,
              employerProfileId: employerProfileId,
            ),
          ));
          if (context.mounted) Navigator.pop(context);
        },
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          // ── En-tête ────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _teal,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nom, style: const TextStyle(
                  fontFamily: 'Galey', fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, children: [
                _HeaderBadge(planTemplateActeLabel(type)),
                if (espece.isNotEmpty) _HeaderBadge(espece),
                _HeaderBadge('${etapes.length} étape${etapes.length > 1 ? 's' : ''}'),
              ]),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(desc, style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.white.withValues(alpha: 0.85))),
              ],
            ]),
          ),
          const SizedBox(height: 20),

          // ── Étapes ─────────────────────────────────────────────────────
          if (etapes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('Aucune étape définie.',
                    style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade400)),
              ),
            )
          else
            ...etapes.asMap().entries.map((entry) => _EtapeSummaryCard(
                  index: entry.key + 1,
                  etape: entry.value,
                )),
        ],
      ),
    );
  }
}

class _HeaderBadge extends StatelessWidget {
  final String label;
  const _HeaderBadge(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
    );
  }
}

class _EtapeSummaryCard extends StatelessWidget {
  final int index;
  final Map<String, dynamic> etape;
  const _EtapeSummaryCard({required this.index, required this.etape});

  static const _teal = Color(0xFF0C5C6C);
  static const _dark = Color(0xFF1F2A2E);

  @override
  Widget build(BuildContext context) {
    final produit = etape['produit'] as String? ?? '';
    final dosage  = etape['dosage'] as String? ?? '';
    final prodDos = [if (produit.isNotEmpty) produit, if (dosage.isNotEmpty) '($dosage)'].join(' ');
    final notes   = etape['description'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 26, height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: _teal.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Text('$index', style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: _teal)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(planTemplateActeLabel(etape['type_acte'] as String?),
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700, color: _dark)),
              ),
              Text(planTemplateTimingLabel(etape), style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
            ]),
            if (prodDos.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(prodDos, style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade700)),
            ],
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              _Chip(planTemplateFreqLabel(etape)),
              _Chip(planTemplateTrancheLabel(etape['tranche_horaire'] as String?)),
            ]),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(notes, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
    );
  }
}
