// Signature manuscrite du professionnel (table signatures_pro, migration
// migration_signatures_pro.sql) : dessinée une fois au doigt, comme pour les
// contrats (SignatureFullScreen), puis apposée sur ses comptes rendus et
// ordonnances. Lisible par son seul propriétaire. Miroir site : lib/signature-pro.ts.

import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:PetsMatch/widgets/signature_pad.dart';

/// Signature enregistrée (data-URL PNG), ou null.
Future<String?> maSignaturePro() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  try {
    final r = await Supabase.instance.client.from('signatures_pro').select('signature').eq('uid', uid).maybeSingle();
    final s = r?['signature']?.toString() ?? '';
    return s.isEmpty ? null : s;
  } catch (_) {
    return null;
  }
}

/// Octets PNG d'une data-URL (pour les PDF).
Uint8List? octetsSignature(String? dataUrl) {
  if (dataUrl == null) return null;
  final i = dataUrl.indexOf('base64,');
  if (i < 0) return null;
  try {
    return base64Decode(dataUrl.substring(i + 7));
  } catch (_) {
    return null;
  }
}

/// Fait dessiner la signature (plein écran) et l'enregistre. Renvoie la
/// data-URL enregistrée, ou null si annulé / échec.
Future<String?> signerEtEnregistrer(BuildContext context) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  final dataUrl = await Navigator.push<String?>(context, MaterialPageRoute(
      builder: (_) => const SignatureFullScreen(titre: 'Ma signature')));
  if (dataUrl == null) return null;
  try {
    await Supabase.instance.client.from('signatures_pro').upsert({
      'uid': uid, 'signature': dataUrl, 'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'uid');
    return dataUrl;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Signature non enregistrée : $e')));
    }
    return null;
  }
}
