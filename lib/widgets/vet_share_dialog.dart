import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/pages/pro/vet_token_view.dart';

const _kVetBaseUrl = 'https://www.petsmatchapp.com/sante/';

Future<void> showVetShareSheet(BuildContext context, String animalId) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final profileRow = await Supabase.instance.client
      .from('user_profiles').select('id').eq('uid', uid).eq('is_main', true).maybeSingle();
  final profileId = profileRow?['id'] as String?;

  final now = DateTime.now().toUtc();
  final filterCol = profileId != null ? 'owner_profile_id' : 'owner_id';
  final filterVal = profileId ?? uid;
  final rows = await Supabase.instance.client
      .from('partage_tokens')
      .select('token')
      .eq('animal_id', animalId)
      .eq(filterCol, filterVal)
      .gt('expires_at', now.toIso8601String())
      .order('created_at', ascending: false)
      .limit(1);

  if (!context.mounted) return;

  final list = rows as List;
  if (list.isNotEmpty) {
    _openDialog(context, list.first['token'] as String, animalId, uid, profileId: profileId, isExisting: true);
  } else {
    await _generateAndOpen(context, animalId, uid, profileId: profileId);
  }
}

Future<void> _generateAndOpen(BuildContext context, String animalId, String uid, {String? profileId}) async {
  try {
    final expiresAt = DateTime.now().toUtc().add(const Duration(hours: 72));
    final data = await Supabase.instance.client
        .from('partage_tokens')
        .insert({
          'animal_id': animalId,
          'owner_id': uid,
          if (profileId != null) 'owner_profile_id': profileId,
          'expires_at': expiresAt.toIso8601String(),
        })
        .select('token')
        .single();
    if (context.mounted) {
      _openDialog(context, data['token'] as String, animalId, uid, profileId: profileId, isExisting: false);
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erreur : $e', style: const TextStyle(fontFamily: 'Galey')),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }
}

void _openDialog(BuildContext context, String token, String animalId, String uid, {String? profileId, required bool isExisting}) {
  showDialog(
    context: context,
    builder: (_) => _VetShareDialog(
      token: token,
      isExisting: isExisting,
      onNewToken: () async {
        Navigator.pop(context);
        await _generateAndOpen(context, animalId, uid, profileId: profileId);
      },
    ),
  );
}

class _VetShareDialog extends StatelessWidget {
  final String token;
  final bool isExisting;
  final VoidCallback onNewToken;

  const _VetShareDialog({
    required this.token,
    required this.isExisting,
    required this.onNewToken,
  });

  @override
  Widget build(BuildContext context) {
    final link = '$_kVetBaseUrl$token';
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      title: const Row(children: [
        Icon(Icons.medical_services_outlined, color: Color(0xFF26A69A), size: 20),
        SizedBox(width: 8),
        Expanded(
          child: Text('Partager avec mon vétérinaire',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
        ),
      ]),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (isExisting)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(children: [
                Icon(Icons.info_outline, size: 13, color: Colors.amber.shade700),
                const SizedBox(width: 6),
                const Expanded(child: Text('Token actif existant réutilisé',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11))),
              ]),
            ),
          const Text('Valable 72h · lecture seule du carnet de santé',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4E7E2)),
            ),
            padding: const EdgeInsets.all(10),
            child: QrImageView(data: link, size: 180, backgroundColor: Colors.white),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4F8),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(link,
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 10, color: Color(0xFF1E2025))),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: link));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Lien copié !', style: TextStyle(fontFamily: 'Galey')),
                    behavior: SnackBarBehavior.floating,
                  ));
                },
                icon: const Icon(Icons.copy_outlined, size: 14),
                label: const Text('Copier', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => Share.share(link, subject: 'Carnet de santé de mon animal'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF26A69A),
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
                icon: const Icon(Icons.ios_share_rounded, size: 14),
                label: const Text('Partager', style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => VetTokenView(token: token),
                ));
              },
              icon: const Icon(Icons.visibility_outlined, size: 14),
              label: const Text('Consulter dans l\'appli',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF26A69A),
                side: const BorderSide(color: Color(0xFF26A69A)),
              ),
            ),
          ),
          if (isExisting) ...[
            const SizedBox(height: 4),
            TextButton(
              onPressed: onNewToken,
              child: const Text('Générer un nouveau token',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey)),
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer', style: TextStyle(fontFamily: 'Galey')),
        ),
      ],
    );
  }
}
