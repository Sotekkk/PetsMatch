import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

Future<File?> pickAndCropBanner({ImageSource source = ImageSource.gallery}) async {
  final picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
  if (picked == null) return null;
  final cropped = await ImageCropper().cropImage(
    sourcePath: picked.path,
    aspectRatio: const CropAspectRatio(ratioX: 16, ratioY: 9),
    uiSettings: [
      AndroidUiSettings(
        toolbarTitle: 'Recadrer la bannière',
        toolbarColor: const Color(0xFF0C5C6C),
        toolbarWidgetColor: Colors.white,
        activeControlsWidgetColor: const Color(0xFF6E9E57),
        lockAspectRatio: true,
      ),
      IOSUiSettings(
        title: 'Recadrer la bannière',
        aspectRatioLockEnabled: true,
        resetAspectRatioEnabled: false,
        aspectRatioPickerButtonHidden: true,
      ),
    ],
  );
  return cropped != null ? File(cropped.path) : null;
}

Future<File?> pickAndCropSquare({ImageSource source = ImageSource.gallery}) async {
  final picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
  if (picked == null) return null;
  final cropped = await ImageCropper().cropImage(
    sourcePath: picked.path,
    aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
    uiSettings: [
      AndroidUiSettings(
        toolbarTitle: 'Recadrer',
        toolbarColor: const Color(0xFF0C5C6C),
        toolbarWidgetColor: Colors.white,
        activeControlsWidgetColor: const Color(0xFF6E9E57),
        lockAspectRatio: true,
      ),
      IOSUiSettings(
        title: 'Recadrer',
        aspectRatioLockEnabled: true,
        minimumAspectRatio: 1.0,
        resetAspectRatioEnabled: false,
        aspectRatioPickerButtonHidden: true,
      ),
    ],
  );
  return cropped != null ? File(cropped.path) : null;
}

/// Galerie : plusieurs photos en une sélection, chacune recadrée au carré
/// (une photo dont le recadrage est annulé est ignorée). [limite] : nombre
/// maximum de photos encore acceptées.
Future<List<File>> pickAndCropSquareMultiple({required int limite}) async {
  if (limite <= 0) return [];
  final choix = await ImagePicker().pickMultiImage(imageQuality: 85, limit: limite > 1 ? limite : null);
  final out = <File>[];
  for (final x in choix.take(limite)) {
    final cropped = await ImageCropper().cropImage(
      sourcePath: x.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Recadrer',
          toolbarColor: const Color(0xFF0C5C6C),
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: const Color(0xFF6E9E57),
          lockAspectRatio: true,
        ),
        IOSUiSettings(
          title: 'Recadrer',
          aspectRatioLockEnabled: true,
          minimumAspectRatio: 1.0,
          resetAspectRatioEnabled: false,
          aspectRatioPickerButtonHidden: true,
        ),
      ],
    );
    if (cropped != null) out.add(File(cropped.path));
  }
  return out;
}
