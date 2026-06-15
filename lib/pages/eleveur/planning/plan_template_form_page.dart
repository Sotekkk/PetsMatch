import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:PetsMatch/services/planning_service.dart';

class PlanTemplateFormPage extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const PlanTemplateFormPage({super.key, this.existing});
  @override
  State<PlanTemplateFormPage> createState() => _PlanTemplateFormPageState();
}

class _PlanTemplateFormPageState extends State<PlanTemplateFormPage> {
  static const _green = Color(0xFF6E9E57);
  static const _dark  = Color(0xFF1F2A2E);

  final _nomCtrl  = TextEditingController();
  final _descCtrl = TextEditingController();

  String _type   = 'sanitaire';
  String _espece = '';
  bool _saving   = false;

  final List<_EtapeController> _etapes = [];

  static const _types = [
    ('sanitaire',    '💊', 'Sanitaire'),
    ('nettoyage',    '🧹', 'Nettoyage'),
    ('promenade',    '🦮', 'Promenade'),
    ('socialisation','🐾', 'Socialisation'),
  ];

  static const _especes = ['', 'chien', 'chat', 'cheval', 'lapin', 'oiseau', 'nac', 'ovin', 'caprin', 'porcin'];

  static const _typesActes = [
    ('vermifuge',       '💊 Vermifuge'),
    ('vaccination',     '💉 Vaccination'),
    ('antiparasitaire', '🛡️ Antiparasitaire'),
    ('traitement',      '🩺 Traitement'),
    ('visite',          '🏥 Visite vétérinaire'),
    ('nettoyage',       '🧹 Nettoyage'),
    ('promenade',       '🦮 Promenade'),
    ('socialisation',   '🐾 Socialisation'),
    ('autre',           '📋 Autre'),
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nomCtrl.text  = e['nom'] ?? '';
      _descCtrl.text = e['description'] ?? '';
      _type   = e['type'] ?? 'sanitaire';
      _espece = e['espece'] ?? '';
      final etapesData = e['plan_template_etapes'];
      if (etapesData is List) {
        for (final et in etapesData) {
          _etapes.add(_EtapeController.fromData(Map<String, dynamic>.from(et)));
        }
      }
    }
    if (_etapes.isEmpty) _addEtape();
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _descCtrl.dispose();
    for (final e in _etapes) { e.dispose(); }
    super.dispose();
  }

  void _addEtape() {
    setState(() => _etapes.add(_EtapeController()));
  }

  void _removeEtape(int i) {
    setState(() {
      _etapes[i].dispose();
      _etapes.removeAt(i);
    });
  }

  Future<void> _save() async {
    if (_nomCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Le nom est requis')));
      return;
    }
    if (_etapes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ajoutez au moins une étape')));
      return;
    }
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final etapesData = _etapes.map((e) => e.toMap()).toList();
      if (widget.existing != null) {
        await PlanningService.updateTemplate(
          templateId: widget.existing!['id'] as String,
          nom: _nomCtrl.text.trim(),
          espece: _espece.isEmpty ? null : _espece,
          description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          etapes: etapesData,
        );
      } else {
        await PlanningService.createTemplate(
          uid: uid,
          nom: _nomCtrl.text.trim(),
          type: _type,
          espece: _espece.isEmpty ? null : _espece,
          description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          etapes: etapesData,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _dark,
        foregroundColor: Colors.white,
        title: Text(
          isEdit ? 'Modifier le protocole' : 'Nouveau protocole',
          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_saving)
            const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
          else
            TextButton(
              onPressed: _save,
              child: const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey', color: Color(0xFF6E9E57), fontWeight: FontWeight.w700, fontSize: 15)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Infos générales ──
          _Section(
            title: 'Informations',
            child: Column(
              children: [
                _Field(controller: _nomCtrl, label: 'Nom du protocole *', hint: 'ex: Vermifuge portée standard chien'),
                const SizedBox(height: 12),
                // Type
                if (!isEdit) ...[
                  const _Label('Type de protocole'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: _types.map((t) {
                      final active = _type == t.$1;
                      return GestureDetector(
                        onTap: () => setState(() => _type = t.$1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: active ? _green : Colors.white,
                            border: Border.all(color: active ? _green : Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${t.$2} ${t.$3}',
                            style: TextStyle(
                              fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600,
                              color: active ? Colors.white : const Color(0xFF1F2A2E),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                ],
                // Espèce
                const _Label('Espèce cible'),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _espece,
                  decoration: _inputDeco('Toutes espèces'),
                  items: _especes.map((e) => DropdownMenuItem(
                    value: e,
                    child: Text(e.isEmpty ? 'Toutes espèces' : e, style: const TextStyle(fontFamily: 'Galey')),
                  )).toList(),
                  onChanged: (v) => setState(() => _espece = v ?? ''),
                ),
                const SizedBox(height: 12),
                _Field(controller: _descCtrl, label: 'Description (optionnel)', hint: 'Notes sur ce protocole', maxLines: 3),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // ── Étapes ──
          _Section(
            title: 'Étapes du protocole',
            trailing: Text('${_etapes.length} étape${_etapes.length > 1 ? 's' : ''}',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
            child: Column(
              children: [
                ..._etapes.asMap().entries.map((entry) => _EtapeCard(
                  index: entry.key,
                  ctrl: entry.value,
                  typesActes: _typesActes,
                  onRemove: _etapes.length > 1 ? () => _removeEtape(entry.key) : null,
                  onChanged: () => setState(() {}),
                )),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _addEtape,
                  icon: const Icon(Icons.add, size: 18, color: _green),
                  label: const Text('Ajouter une étape', style: TextStyle(fontFamily: 'Galey', color: _green)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: _green)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  static InputDecoration _inputDeco(String label, {String? hint}) => InputDecoration(
    labelText: label,
    hintText: hint,
    labelStyle: const TextStyle(fontFamily: 'Galey'),
    hintStyle: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade400),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6E9E57))),
    filled: true,
    fillColor: Colors.white,
  );
}

// ─── Carte d'étape ────────────────────────────────────────────────────────────

class _EtapeCard extends StatelessWidget {
  final int index;
  final _EtapeController ctrl;
  final List<(String, String)> typesActes;
  final VoidCallback? onRemove;
  final VoidCallback onChanged;

  const _EtapeCard({
    required this.index, required this.ctrl, required this.typesActes,
    required this.onRemove, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF6E9E57).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26, height: 26,
                decoration: BoxDecoration(color: const Color(0xFF6E9E57), borderRadius: BorderRadius.circular(8)),
                child: Center(child: Text('${index + 1}', style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.white, fontWeight: FontWeight.w700))),
              ),
              const Spacer(),
              if (onRemove != null)
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                  onPressed: onRemove,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Type d'acte
          DropdownButtonFormField<String>(
            initialValue: ctrl.typeActe,
            decoration: _inputDeco('Type d\'acte'),
            items: typesActes.map((t) => DropdownMenuItem(
              value: t.$1,
              child: Text(t.$2, style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
            )).toList(),
            onChanged: (v) { ctrl.typeActe = v ?? 'vermifuge'; onChanged(); },
          ),
          const SizedBox(height: 8),
          // Produit + dosage
          Row(
            children: [
              Expanded(child: TextFormField(
                controller: ctrl.produitCtrl,
                decoration: _inputDeco('Produit', hint: 'ex: Milbemax®'),
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
              )),
              const SizedBox(width: 8),
              Expanded(child: TextFormField(
                controller: ctrl.dosageCtrl,
                decoration: _inputDeco('Dosage', hint: 'ex: 1 cp/5kg'),
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
              )),
            ],
          ),
          const SizedBox(height: 8),
          // Jour offset + durée
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: ctrl.offsetCtrl,
                  keyboardType: const TextInputType.numberWithOptions(signed: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))],
                  decoration: _inputDeco('Jour relatif', hint: '0 = J0, -15 = J-15'),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: ctrl.dureeCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _inputDeco('Durée (jours)', hint: '1 = ponctuel'),
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: ctrl.descCtrl,
            decoration: _inputDeco('Description / notes', hint: 'Instructions spécifiques'),
            style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  static InputDecoration _inputDeco(String label, {String? hint}) => InputDecoration(
    labelText: label,
    hintText: hint,
    labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12),
    hintStyle: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade400),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF6E9E57))),
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    filled: true,
    fillColor: Colors.white,
  );
}

// ─── Contrôleur d'étape ───────────────────────────────────────────────────────

class _EtapeController {
  String typeActe = 'vermifuge';
  final TextEditingController produitCtrl;
  final TextEditingController dosageCtrl;
  final TextEditingController offsetCtrl;
  final TextEditingController dureeCtrl;
  final TextEditingController descCtrl;
  String? existingId;

  _EtapeController()
      : produitCtrl = TextEditingController(),
        dosageCtrl  = TextEditingController(),
        offsetCtrl  = TextEditingController(text: '0'),
        dureeCtrl   = TextEditingController(text: '1'),
        descCtrl    = TextEditingController();

  _EtapeController.fromData(Map<String, dynamic> d)
      : typeActe   = d['type_acte'] ?? 'vermifuge',
        existingId = d['id'] as String?,
        produitCtrl = TextEditingController(text: d['produit'] ?? ''),
        dosageCtrl  = TextEditingController(text: d['dosage'] ?? ''),
        offsetCtrl  = TextEditingController(text: '${d['jour_offset'] ?? 0}'),
        dureeCtrl   = TextEditingController(text: '${d['duree_jours'] ?? 1}'),
        descCtrl    = TextEditingController(text: d['description'] ?? '');

  Map<String, dynamic> toMap() => {
    if (existingId != null) 'id': existingId,
    'type_acte':   typeActe,
    'produit':     produitCtrl.text.trim().isEmpty ? null : produitCtrl.text.trim(),
    'dosage':      dosageCtrl.text.trim().isEmpty  ? null : dosageCtrl.text.trim(),
    'jour_offset': int.tryParse(offsetCtrl.text) ?? 0,
    'duree_jours': int.tryParse(dureeCtrl.text) ?? 1,
    'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
  };

  void dispose() {
    produitCtrl.dispose();
    dosageCtrl.dispose();
    offsetCtrl.dispose();
    dureeCtrl.dispose();
    descCtrl.dispose();
  }
}

// ─── Widgets utilitaires ──────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget child;

  const _Section({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                Text(title, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0C5C6C))),
                const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          const Divider(height: 16),
          Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 14), child: child),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;

  const _Field({required this.controller, required this.label, this.hint, this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(fontFamily: 'Galey'),
        hintStyle: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade400),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF6E9E57))),
        filled: true,
        fillColor: const Color(0xFFF8F8F6),
      ),
      style: const TextStyle(fontFamily: 'Galey'),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF374151), fontWeight: FontWeight.w500),
  );
}

