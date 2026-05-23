import 'dart:io';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/eleveur/desc_entreprise.dart';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

class RegisterDocumentElevage extends StatefulWidget {
  const RegisterDocumentElevage({super.key});
  @override
  State<RegisterDocumentElevage> createState() => _RegisterDocumentElevageState();
}

class _RegisterDocumentElevageState extends State<RegisterDocumentElevage> {
  static const _green = Color(0xFF6E9E57);
  static const _teal = Color(0xFF0C5C6C);
  static const _bg = Color(0xFFF8F8F6);

  final _siretCtrl = TextEditingController();
  final _tvaCtrl = TextEditingController();
  final _acacedCtrl = TextEditingController();

  DateTime? _acacedDate;
  bool _uploading = false;
  bool _siretUploaded = false;
  bool _acacedUploaded = false;
  String? _siretDocUrl;
  String? _acacedDocUrl;
  String? _siretDocName;
  String? _acacedDocName;
  String? _selectedCategory;
  String? _selectedProfession;

  static const Map<String, List<String>> _professions = {
    'Prestataire': [
      'Educateurs comportementalistes', 'Handleurs', 'Mushers',
      'Promeneurs de chiens', 'Petsitter', 'Toiletteur',
    ],
    'Santé animal': ['Vétérinaire', 'Auxiliaire de santé', 'Spécialistes de santé'],
  };

  @override
  void dispose() {
    _siretCtrl.dispose();
    _tvaCtrl.dispose();
    _acacedCtrl.dispose();
    super.dispose();
  }

  DateTime? get _acacedExpiration {
    if (_acacedDate == null) return null;
    return DateTime(_acacedDate!.year + 10, _acacedDate!.month, _acacedDate!.day);
  }

  Color get _acacedColor {
    final exp = _acacedExpiration;
    if (exp == null) return Colors.grey;
    final now = DateTime.now();
    if (exp.isBefore(now)) return Colors.red;
    if (exp.difference(now).inDays < 180) return const Color(0xFFE8A500);
    return _green;
  }

  String get _acacedStatusLabel {
    final exp = _acacedExpiration;
    if (exp == null) return '';
    final now = DateTime.now();
    if (exp.isBefore(now)) return 'Expiré';
    if (exp.difference(now).inDays < 180) return 'Expire bientôt';
    return 'Valide';
  }

  Future<String> _uploadToFirebase(File file, String path) async {
    final ref = FirebaseStorage.instance.ref().child(path);
    final snap = await ref.putFile(file);
    return snap.ref.getDownloadURL();
  }

  Future<void> _pickSiret() async {
    final result = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'png', 'jpeg']);
    if (result?.files.single.path == null) return;
    setState(() => _uploading = true);
    try {
      final file = File(result!.files.single.path!);
      final url = await _uploadToFirebase(file, 'documentElevage/Siret/${file.path.split('/').last}');
      setState(() {
        _siretDocUrl = url;
        _siretDocName = result.files.single.name;
        _siretUploaded = true;
        User_Info.kbisUrl = url;
        User_Info.documentElevage.removeWhere((d) => d['category'] == 'Siret');
        User_Info.documentElevage.add({'name': _siretDocName, 'category': 'Siret', 'url': url, 'uploaded': true});
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur upload: $e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickAcaced() async {
    final result = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'png', 'jpeg']);
    if (result?.files.single.path == null) return;
    setState(() => _uploading = true);
    try {
      final file = File(result!.files.single.path!);
      final url = await _uploadToFirebase(file, 'documentElevage/Acaced/${file.path.split('/').last}');
      setState(() {
        _acacedDocUrl = url;
        _acacedDocName = result.files.single.name;
        _acacedUploaded = true;
        User_Info.documentElevage.removeWhere((d) => d['category'] == 'Acaced_ou_autre');
        User_Info.documentElevage.add({'name': _acacedDocName, 'category': 'Acaced_ou_autre', 'url': url, 'uploaded': true});
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur upload: $e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _acacedDate ?? DateTime.now(),
      firstDate: DateTime(1990),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: ThemeData.light().copyWith(colorScheme: const ColorScheme.light(primary: _green)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _acacedDate = picked);
  }

  void _validateAndContinue() {
    User_Info.siret = _siretCtrl.text.trim();
    User_Info.numeroTVA = _tvaCtrl.text.trim();

    if (User_Info.isPro) {
      if (!_siretUploaded || _siretCtrl.text.trim().isEmpty ||
          _selectedCategory == null || _selectedProfession == null) {
        _showError('SIRET (numéro + document), catégorie et profession sont obligatoires.');
        return;
      }
      User_Info.catPro = _selectedCategory!;
      User_Info.professionPro = _selectedProfession!;
    } else {
      if (!_siretUploaded || _siretCtrl.text.trim().isEmpty) {
        _showError('Le numéro SIRET et son justificatif sont obligatoires.');
        return;
      }
      if (User_Info.isElevage) {
        final acacedRequired = User_Info.isDog || User_Info.isCat;
        if (acacedRequired && (_acacedCtrl.text.trim().isEmpty || _acacedDate == null || !_acacedUploaded)) {
          _showError('L\'ACACED est obligatoire pour les éleveurs de chiens et de chats.');
          return;
        }
        User_Info.acacedNumero = _acacedCtrl.text.trim();
        User_Info.acacedDateObtention = _acacedDate!.toIso8601String();
        User_Info.acacedDocUrl = _acacedDocUrl ?? '';
      }
    }

    Navigator.push(context, MaterialPageRoute(builder: (_) => const DescProEntreprise()));
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Galey'))));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Documents', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(24),
          child: _StepBar(current: 3, total: 4),
        ),
      ),
      body: Stack(children: [
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── SIRET ───────────────────────────────────────────────────────────
            _sectionTitle('SIRET *'),
            const SizedBox(height: 8),
            _card([
              _textField('Numéro SIRET', _siretCtrl, inputType: TextInputType.number),
              _uploadTile(
                label: 'Joindre le justificatif SIRET',
                uploaded: _siretUploaded,
                fileName: _siretDocName,
                onTap: _pickSiret,
                onRemove: () => setState(() {
                  _siretUploaded = false; _siretDocName = null; _siretDocUrl = null;
                  User_Info.documentElevage.removeWhere((d) => d['category'] == 'Siret');
                  User_Info.kbisUrl = '';
                }),
              ),
            ]),
            const SizedBox(height: 20),

            // ── TVA ─────────────────────────────────────────────────────────────
            _sectionTitle('Numéro TVA (optionnel)'),
            const SizedBox(height: 8),
            _card([_textField('Numéro TVA', _tvaCtrl, inputType: TextInputType.number)]),
            const SizedBox(height: 20),

            // ── ACACED (éleveur seulement) ───────────────────────────────────────
            if (User_Info.isElevage) ...[
              _sectionTitle(User_Info.isDog || User_Info.isCat ? 'ACACED ou équivalent *' : 'ACACED ou équivalent (optionnel)'),
              const SizedBox(height: 4),
              const Text(
                'Certificat de capacité animaux domestiques — valable 10 ans',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
              ),
              const SizedBox(height: 10),
              _card([
                _textField('Numéro ACACED', _acacedCtrl),
                const SizedBox(height: 4),
                _datePicker(),
                if (_acacedDate != null) ...[
                  const SizedBox(height: 12),
                  _validityBadge(),
                ],
                const SizedBox(height: 10),
                _uploadTile(
                  label: 'Joindre le document ACACED',
                  uploaded: _acacedUploaded,
                  fileName: _acacedDocName,
                  onTap: _pickAcaced,
                  onRemove: () => setState(() {
                    _acacedUploaded = false; _acacedDocName = null; _acacedDocUrl = null;
                    User_Info.documentElevage.removeWhere((d) => d['category'] == 'Acaced_ou_autre');
                  }),
                ),
              ]),
              const SizedBox(height: 20),
            ],

            // ── Catégorie PRO ────────────────────────────────────────────────────
            if (User_Info.isPro) ...[
              _sectionTitle('Catégorie professionnelle *'),
              const SizedBox(height: 8),
              _card([
                _dropdownField(
                  label: 'Catégorie',
                  value: _selectedCategory,
                  items: _professions.keys.toList(),
                  onChanged: (v) => setState(() { _selectedCategory = v; _selectedProfession = null; }),
                ),
                if (_selectedCategory != null)
                  _dropdownField(
                    label: 'Profession',
                    value: _selectedProfession,
                    items: _professions[_selectedCategory]!,
                    onChanged: (v) => setState(() => _selectedProfession = v),
                  ),
              ]),
              const SizedBox(height: 20),
            ],

            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _uploading ? null : _validateAndContinue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  disabledBackgroundColor: Colors.grey.shade300,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('CONTINUER',
                    style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
              ),
            ),
          ]),
        ),
        if (_uploading)
          const ColoredBox(color: Colors.black26,
              child: Center(child: CircularProgressIndicator(color: _green))),
      ]),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Text(title,
        style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
            fontSize: 16, color: Color(0xFF1F2A2E))),
  );

  Widget _card(List<Widget> children) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );

  Widget _textField(String label, TextEditingController ctrl, {TextInputType? inputType}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: ctrl,
          keyboardType: inputType,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _green, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
        ),
      );

  Widget _uploadTile({
    required String label, required bool uploaded, String? fileName,
    required VoidCallback onTap, required VoidCallback onRemove,
  }) =>
      GestureDetector(
        onTap: uploaded ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            border: Border.all(color: uploaded ? _green : const Color(0xFFE4E7E2)),
            borderRadius: BorderRadius.circular(10),
            color: uploaded ? _green.withOpacity(0.06) : Colors.transparent,
          ),
          child: Row(children: [
            Icon(uploaded ? Icons.check_circle_outline : Icons.upload_file_outlined,
                size: 18, color: uploaded ? _green : _teal),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                uploaded ? (fileName ?? 'Document chargé ✓') : label,
                style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                    color: uploaded ? _green : const Color(0xFF6F767B)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (uploaded)
              GestureDetector(
                onTap: onRemove,
                child: const Icon(Icons.close, size: 16, color: Colors.redAccent),
              ),
          ]),
        ),
      );

  Widget _datePicker() => GestureDetector(
    onTap: _pickDate,
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: 'Date d\'obtention',
        labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
        suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18, color: _green),
      ),
      child: Text(
        _acacedDate != null ? DateFormat('dd/MM/yyyy').format(_acacedDate!) : 'Sélectionner',
        style: TextStyle(fontFamily: 'Galey', fontSize: 14,
            color: _acacedDate != null ? const Color(0xFF1F2A2E) : Colors.grey),
      ),
    ),
  );

  Widget _validityBadge() {
    final exp = _acacedExpiration!;
    final color = _acacedColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.shield_outlined, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          '$_acacedStatusLabel — expire le ${DateFormat('dd/MM/yyyy').format(exp)}',
          style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: color, fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }

  Widget _dropdownField({
    required String label, required String? value,
    required List<String> items, required ValueChanged<String?> onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: DropdownButtonFormField<String>(
          value: value,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF1F2A2E)),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _green, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
          items: items.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: onChanged,
        ),
      );
}

class _StepBar extends StatelessWidget {
  final int current;
  final int total;
  const _StepBar({required this.current, required this.total});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
    child: Row(
      children: List.generate(total, (i) => Expanded(
        child: Container(
          height: 3,
          margin: EdgeInsets.only(right: i < total - 1 ? 4 : 0),
          decoration: BoxDecoration(
            color: i < current ? Colors.white : Colors.white38,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      )),
    ),
  );
}
