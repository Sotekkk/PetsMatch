import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/particulier/numberadressregistration.dart';
import 'package:PetsMatch/utils/storage_helper.dart';
import 'package:flutter/material.dart';
import 'package:PetsMatch/utils/image_pick.dart';
import 'dart:io';

class RegisterParticulierInformationPage extends StatefulWidget {
  const RegisterParticulierInformationPage({super.key});
  @override
  State<RegisterParticulierInformationPage> createState() =>
      _RegisterParticulierInformationPageState();
}

class _RegisterParticulierInformationPageState
    extends State<RegisterParticulierInformationPage> {
  final _nomCtrl = TextEditingController();
  final _prenomCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();

  File? _imageFile;
  String? _imageUrl;
  bool _isImagePickerActive = false;

  bool _nomOk = true;
  bool _prenomOk = true;

  static const _green = Color(0xFF6E9E57);
  static const _teal = Color(0xFF0C5C6C);
  static const _bg = Color(0xFFF8F8F6);

  @override
  void dispose() {
    _nomCtrl.dispose();
    _prenomCtrl.dispose();
    _dobCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_isImagePickerActive) return;
    setState(() => _isImagePickerActive = true);
    try {
      final f = await pickAndCropSquare();
      setState(() {
        if (f != null) _imageFile = f;
        _isImagePickerActive = false;
      });
    } catch (_) {
      setState(() => _isImagePickerActive = false);
    }
  }

  Future<void> _uploadImage() async {
    if (_imageFile == null) return;
    try {
      final name = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      _imageUrl = await uploadPhoto(_imageFile!, 'profiles/$name');
    } catch (_) {}
  }

  void _continue() {
    setState(() {
      _nomOk = _nomCtrl.text.trim().isNotEmpty;
      _prenomOk = _prenomCtrl.text.trim().isNotEmpty;
    });
    if (!_nomOk || !_prenomOk) return;

    User_Info.firstname = _prenomCtrl.text.trim();
    User_Info.lastname = _nomCtrl.text.trim();
    User_Info.dateofbirth = _dobCtrl.text.isNotEmpty ? _dobCtrl.text : '01/01/1900';
    _uploadImage().catchError((_) {});

    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const RegisterPhoneAdressInformationPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: const Text('Inscription',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: const _StepBar(current: 1, total: 3),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Vos informations',
              style: TextStyle(
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                  color: Color(0xFF1F2A2E))),
          const SizedBox(height: 6),
          Text('Renseignez votre nom, prénom et date de naissance.',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500)),
          const SizedBox(height: 24),

          // ── Photo de profil ───────────────────────────────────────────────────
          Center(
            child: GestureDetector(
              onTap: _pickImage,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: const Color(0xFFE8F0E4),
                    backgroundImage: _imageFile != null ? FileImage(_imageFile!) : null,
                    child: _imageFile == null
                        ? const Icon(Icons.person, size: 44, color: _green)
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: _imageFile != null
                          ? () => setState(() => _imageFile = null)
                          : _pickImage,
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: _green,
                        child: Icon(
                          _imageFile == null ? Icons.camera_alt : Icons.close,
                          size: 15,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text('Photo de profil (optionnel)',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B))),
          ),
          const SizedBox(height: 20),

          // ── Nom / Prénom ──────────────────────────────────────────────────────
          _card([
            _field(ctrl: _nomCtrl, label: 'Nom', icon: Icons.person_outline, valid: _nomOk, error: 'Nom requis'),
            const SizedBox(height: 12),
            _field(ctrl: _prenomCtrl, label: 'Prénom', icon: Icons.badge_outlined, valid: _prenomOk, error: 'Prénom requis'),
          ]),
          const SizedBox(height: 16),

          // ── Date de naissance ─────────────────────────────────────────────────
          _card([_dobField()]),
          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _continue,
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('CONTINUER',
                  style: TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Colors.white)),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  Widget _card(List<Widget> children) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _field({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    bool valid = true,
    String error = '',
  }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextFormField(
          controller: ctrl,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
            labelStyle:
                const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
            prefixIcon: Icon(icon, size: 18, color: const Color(0xFF6F767B)),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: valid ? const Color(0xFFE4E7E2) : Colors.red)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _green, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            isDense: true,
          ),
        ),
        if (!valid)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(error,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.red)),
          ),
      ]);

  Widget _dobField() => TextFormField(
        controller: _dobCtrl,
        readOnly: true,
        style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
        decoration: InputDecoration(
          labelText: 'Date de naissance',
          labelStyle:
              const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6F767B)),
          prefixIcon: const Icon(Icons.cake_outlined, size: 18, color: Color(0xFF6F767B)),
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18, color: Color(0xFF6F767B)),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE4E7E2))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _green, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          isDense: true,
        ),
        onTap: () async {
          FocusScope.of(context).requestFocus(FocusNode());
          final picked = await showDatePicker(
            context: context,
            initialDate: DateTime(2000),
            firstDate: DateTime(1900),
            lastDate: DateTime.now(),
            builder: (ctx, child) => Theme(
              data: ThemeData.light().copyWith(
                colorScheme: const ColorScheme.light(primary: _teal),
              ),
              child: child!,
            ),
          );
          if (picked != null) {
            setState(() {
              _dobCtrl.text =
                  '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
            });
          }
        },
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
          children: List.generate(
            total,
            (i) => Expanded(
              child: Container(
                height: 3,
                margin: EdgeInsets.only(right: i < total - 1 ? 4 : 0),
                decoration: BoxDecoration(
                  color: i < current ? Colors.white : Colors.white38,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      );
}
