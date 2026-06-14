import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/pages/eleveur/admin/registre_sanitaire.dart';

// Types d'actes (mirror de registre_sanitaire.dart)
const _kActes = [
  (value: 'vermifuge',       label: 'Vermifuge',           icon: Icons.bug_report_outlined,        color: Color(0xFFFFF8E1)),
  (value: 'vaccination',     label: 'Vaccination',          icon: Icons.vaccines_outlined,          color: Color(0xFFE8F5E9)),
  (value: 'antiparasitaire', label: 'Antiparasitaire',      icon: Icons.pest_control_outlined,      color: Color(0xFFFFF3E0)),
  (value: 'traitement',      label: 'Traitement',           icon: Icons.medication_outlined,        color: Color(0xFFE0F2F1)),
  (value: 'visite',          label: 'Visite vétérinaire',   icon: Icons.medical_services_outlined,  color: Color(0xFFE3F2FD)),
  (value: 'osteopathie',     label: 'Ostéopathie',          icon: Icons.self_improvement_outlined,  color: Color(0xFFF3E5F5)),
  (value: 'chirurgie',       label: 'Chirurgie',            icon: Icons.healing_outlined,           color: Color(0xFFFFEBEE)),
  (value: 'autre',           label: 'Autre',                icon: Icons.more_horiz,                 color: Color(0xFFF5F5F5)),
];

typedef _Acte = ({String value, String label, IconData icon, Color color});

class PorteeSoinSheet extends StatefulWidget {
  final List<Map<String, dynamic>> animals;

  const PorteeSoinSheet({super.key, required this.animals});

  /// Ouvre le bottom sheet et retourne true si des soins ont été enregistrés.
  static Future<bool> show(BuildContext context, List<Map<String, dynamic>> animals) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PorteeSoinSheet(animals: animals),
    );
    return result ?? false;
  }

  @override
  State<PorteeSoinSheet> createState() => _PorteeSoinSheetState();
}

class _PorteeSoinSheetState extends State<PorteeSoinSheet> {
  static const _teal  = Color(0xFF0C5C6C);
  static const _green = Color(0xFF6E9E57);

  _Acte _selectedActe = _kActes.first; // vermifuge par défaut
  DateTime _date = DateTime.now();
  final _intervenantCtrl  = TextEditingController();
  final _descriptionCtrl  = TextEditingController();
  final _dosageCtrl       = TextEditingController();
  final _notesCtrl        = TextEditingController();
  final _ordonnanceCtrl   = TextEditingController();
  bool _saving = false;
  String? _error;
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.animals.map((a) => a['id']?.toString() ?? '').toSet()..remove('');
  }

  @override
  void dispose() {
    _intervenantCtrl.dispose();
    _descriptionCtrl.dispose();
    _dosageCtrl.dispose();
    _notesCtrl.dispose();
    _ordonnanceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      locale: const Locale('fr'),
      builder: (ctx, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(primary: _teal),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (_descriptionCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Veuillez renseigner le produit / la description.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    final supa        = Supabase.instance.client;
    final type        = _selectedActe.value;
    final desc        = _descriptionCtrl.text.trim();
    final dosage      = _dosageCtrl.text.trim();
    final interv      = _intervenantCtrl.text.trim();
    final notes       = _notesCtrl.text.trim();
    final dateIso     = _date.toIso8601String();
    int success = 0;
    for (final animal in widget.animals) {
      final id = animal['id']?.toString() ?? '';
      if (id.isEmpty || !_selectedIds.contains(id)) continue;
      try {
        final entryId = DateTime.now().microsecondsSinceEpoch.toString();
        // Écriture dans la table spécifique (lue par le carnet de santé de la fiche)
        switch (type) {
          case 'vermifuge':
            await supa.from('vermifuges').insert({
              'id': entryId, 'animal_id': id,
              'produit': desc, 'date': dateIso, 'source': 'owner',
              if (dosage.isNotEmpty) 'dosage': dosage,
              if (notes.isNotEmpty) 'notes': notes,
            });
          case 'vaccination':
            await supa.from('vaccinations').insert({
              'id': entryId, 'animal_id': id,
              'vaccin': desc, 'veterinaire': interv, 'date': dateIso, 'source': 'owner',
            });
          case 'antiparasitaire':
            await supa.from('antiparasitaires').insert({
              'id': entryId, 'animal_id': id,
              'produit': desc, 'type': 'autre', 'date': dateIso, 'source': 'owner',
              if (dosage.isNotEmpty) 'frequence': dosage,
              if (notes.isNotEmpty) 'notes': notes,
            });
          case 'visite':
          case 'osteopathie':
            await supa.from('visites').insert({
              'id': entryId, 'animal_id': id,
              'motif': type == 'osteopathie' ? 'Autre' : 'Consultation',
              'veterinaire': interv, 'date': dateIso,
              'diagnostic': type == 'osteopathie' ? 'Ostéopathie — $desc' : desc,
              if (notes.isNotEmpty) 'notes': notes,
              'source': 'owner',
            });
          default: // traitement, chirurgie, autre
            await supa.from('traitements').insert({
              'id': entryId, 'animal_id': id,
              'nom': desc, 'type': type == 'chirurgie' ? 'autre' : 'medicament',
              'date': dateIso, 'source': 'owner',
            });
        }
        // Log consolidé dans registre_sanitaire
        await RegistreHelper.writeActe(
          animalId:     id,
          typeActe:     type,
          dateActe:     _date,
          intervenant:  interv,
          description:  desc,
          ordonnanceNum: _ordonnanceCtrl.text.trim(),
        );
        success++;
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _saving = false);
      Navigator.pop(context, success > 0);
      if (success > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$success soin${success > 1 ? 's' : ''} enregistré${success > 1 ? 's' : ''} dans le registre.',
              style: const TextStyle(fontFamily: 'Galey')),
          backgroundColor: _green,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy');
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Titre
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: _teal.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.medical_services_outlined, color: _teal, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Soin pour la portée', style: TextStyle(fontFamily: 'Galey',
                    fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF1F2A2E))),
                Text('${_selectedIds.length}/${widget.animals.length} animal${widget.animals.length > 1 ? 'aux' : ''} sélectionné${_selectedIds.length > 1 ? 's' : ''}',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6E9E57))),
              ]),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.pop(context, false),
              padding: EdgeInsets.zero,
            ),
          ]),

          const SizedBox(height: 4),

          // Noms des animaux — tap pour désélectionner
          Wrap(spacing: 6, runSpacing: 4, children: widget.animals.map((a) {
            final id  = a['id']?.toString() ?? '';
            final nom = (a['nom'] as String?) ?? '?';
            final sel = _selectedIds.contains(id);
            return GestureDetector(
              onTap: () {
                if (id.isEmpty) return;
                setState(() {
                  if (sel) _selectedIds.remove(id);
                  else _selectedIds.add(id);
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: sel ? _teal.withOpacity(0.12) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: sel ? _teal.withOpacity(0.35) : Colors.grey.shade300),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(nom, style: TextStyle(
                    fontFamily: 'Galey', fontSize: 12,
                    color: sel ? _teal : Colors.grey,
                    decoration: sel ? TextDecoration.none : TextDecoration.lineThrough,
                  )),
                  if (!sel) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.close, size: 10, color: Colors.grey.shade400),
                  ],
                ]),
              ),
            );
          }).toList()),

          const SizedBox(height: 20),

          // Sélecteur type d'acte
          const Text('Type de soin', style: TextStyle(fontFamily: 'Galey',
              fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0C5C6C))),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: _kActes.map((a) {
            final sel = _selectedActe.value == a.value;
            return GestureDetector(
              onTap: () => setState(() { _selectedActe = a; _dosageCtrl.clear(); }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: sel ? _teal : a.color,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: sel ? _teal : Colors.transparent, width: 1.5),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(a.icon, size: 14, color: sel ? Colors.white : _teal),
                  const SizedBox(width: 5),
                  Text(a.label, style: TextStyle(
                    fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600,
                    color: sel ? Colors.white : const Color(0xFF1F2A2E),
                  )),
                ]),
              ),
            );
          }).toList()),

          const SizedBox(height: 18),

          // Date
          const Text('Date du soin', style: TextStyle(fontFamily: 'Galey',
              fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0C5C6C))),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: _pickDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F8F6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _teal.withOpacity(0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.calendar_today_outlined, size: 16, color: _teal),
                const SizedBox(width: 8),
                Text(fmt.format(_date), style: const TextStyle(
                    fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1F2A2E))),
                const Spacer(),
                const Icon(Icons.chevron_right, size: 18, color: Color(0xFF9E9E9E)),
              ]),
            ),
          ),

          const SizedBox(height: 14),

          // Produit / description
          const Text('Produit / description *', style: TextStyle(fontFamily: 'Galey',
              fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0C5C6C))),
          const SizedBox(height: 6),
          TextField(
            controller: _descriptionCtrl,
            maxLines: 2,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Ex : Milbemax®, 1 comprimé par chiot',
              hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFFBDBDBD)),
              filled: true, fillColor: const Color(0xFFF8F8F6),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _teal.withOpacity(0.2))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _teal.withOpacity(0.2))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _teal, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),

          // Dosage (visible pour vermifuge et antiparasitaire)
          if (_selectedActe.value == 'vermifuge' || _selectedActe.value == 'antiparasitaire') ...[
            const SizedBox(height: 14),
            Text(
              _selectedActe.value == 'antiparasitaire' ? 'Fréquence (optionnel)' : 'Dosage (optionnel)',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0C5C6C)),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _dosageCtrl,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: InputDecoration(
                hintText: _selectedActe.value == 'antiparasitaire' ? 'Ex : 1 mois' : 'Ex : 1 cp / 5 kg',
                hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFFBDBDBD)),
                filled: true, fillColor: const Color(0xFFF8F8F6),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _teal.withOpacity(0.2))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _teal.withOpacity(0.2))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _teal, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Administré par (optionnel)
          const Text('Administré par (optionnel)', style: TextStyle(fontFamily: 'Galey',
              fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0C5C6C))),
          const SizedBox(height: 6),
          TextField(
            controller: _intervenantCtrl,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Éleveur, Dr. Dupont, …',
              hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFFBDBDBD)),
              filled: true, fillColor: const Color(0xFFF8F8F6),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _teal.withOpacity(0.2))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _teal.withOpacity(0.2))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _teal, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),

          const SizedBox(height: 14),

          // Notes (optionnel)
          const Text('Notes (optionnel)', style: TextStyle(fontFamily: 'Galey',
              fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0C5C6C))),
          const SizedBox(height: 6),
          TextField(
            controller: _notesCtrl,
            maxLines: 2,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Observations, réactions, …',
              hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFFBDBDBD)),
              filled: true, fillColor: const Color(0xFFF8F8F6),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _teal.withOpacity(0.2))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _teal.withOpacity(0.2))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _teal, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),

          const SizedBox(height: 14),

          // N° ordonnance (optionnel)
          const Text('N° ordonnance (optionnel)', style: TextStyle(fontFamily: 'Galey',
              fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0C5C6C))),
          const SizedBox(height: 6),
          TextField(
            controller: _ordonnanceCtrl,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            decoration: InputDecoration(
              hintText: 'ORD-2024-XXXXX',
              hintStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFFBDBDBD)),
              filled: true, fillColor: const Color(0xFFF8F8F6),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _teal.withOpacity(0.2))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _teal.withOpacity(0.2))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _teal, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_error!, style: const TextStyle(fontFamily: 'Galey',
                  fontSize: 13, color: Color(0xFFB71C1C))),
            ),
          ],

          const SizedBox(height: 20),

          // Bouton enregistrer
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_saving || _selectedIds.isEmpty) ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.check_circle_outline, size: 18),
              label: Text(
                _saving ? 'Enregistrement…' : 'Enregistrer pour ${_selectedIds.length} animal${_selectedIds.length > 1 ? 'aux' : ''}',
                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                disabledBackgroundColor: Colors.grey.shade300,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
