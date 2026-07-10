import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:PetsMatch/utils/image_pick.dart';
import 'package:PetsMatch/utils/storage_helper.dart';
import '../balades_ludiques_shared.dart';

class DefiPhotoWidget extends StatefulWidget {
  final String consigne;
  final String storagePath;
  final Future<void> Function(String photoUrl) onValidated;

  const DefiPhotoWidget({super.key, required this.consigne, required this.storagePath, required this.onValidated});

  @override
  State<DefiPhotoWidget> createState() => _DefiPhotoWidgetState();
}

class _DefiPhotoWidgetState extends State<DefiPhotoWidget> {
  File? _photo;
  bool _uploading = false;

  Future<void> _pick() async {
    final f = await pickAndCropSquare(source: ImageSource.camera);
    if (f != null) setState(() => _photo = f);
  }

  Future<void> _validate() async {
    if (_photo == null) return;
    setState(() => _uploading = true);
    try {
      final url = await uploadPhoto(_photo!, widget.storagePath);
      await widget.onValidated(url);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.consigne, style: const TextStyle(fontFamily: 'Galey', fontSize: 14, height: 1.4)),
      const SizedBox(height: 14),
      GestureDetector(
        onTap: _pick,
        child: Container(
          height: 180,
          decoration: BoxDecoration(
            color: const Color(0xFFEEF5EA),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kBlGreen.withOpacity(0.4), style: BorderStyle.solid),
          ),
          child: _photo != null
              ? ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.file(_photo!, fit: BoxFit.cover, width: double.infinity))
              : const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.camera_alt_outlined, size: 36, color: kBlGreen),
                  SizedBox(height: 8),
                  Text('Prendre une photo', style: TextStyle(fontFamily: 'Galey', color: kBlGreen)),
                ])),
        ),
      ),
      const SizedBox(height: 14),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: (_photo == null || _uploading) ? null : _validate,
          style: ElevatedButton.styleFrom(backgroundColor: kBlOrange, padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: _uploading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Valider l\'étape', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
        ),
      ),
    ]);
  }
}
