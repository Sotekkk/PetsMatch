import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:http/http.dart' as http;
import 'dart:convert';

const _teal  = Color(0xFF0C5C6C);
const _dark  = Color(0xFF1F2A2E);
const _green  = Color(0xFF6E9E57);
const _tealD  = Color(0xFF0C5C6C);

class InfluencerRequestPage extends StatefulWidget {
  const InfluencerRequestPage({super.key});

  @override
  State<InfluencerRequestPage> createState() => _InfluencerRequestPageState();
}

class _InfluencerRequestPageState extends State<InfluencerRequestPage> {
  final _supa = Supabase.instance.client;
  final _instagram = TextEditingController();
  final _tiktok    = TextEditingController();
  final _autre     = TextEditingController();
  final _message   = TextEditingController();
  final List<File> _images = [];
  bool _loading = false;
  String? _existingStatut;

  @override
  void initState() {
    super.initState();
    _checkExisting();
  }

  @override
  void dispose() {
    _instagram.dispose();
    _tiktok.dispose();
    _autre.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _checkExisting() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final row = await _supa.from('influencer_requests')
          .select('statut, lien_instagram, lien_tiktok, lien_autre, message')
          .eq('uid', uid)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row != null && mounted) {
        setState(() {
          _existingStatut = row['statut'] as String?;
          _instagram.text = row['lien_instagram'] as String? ?? '';
          _tiktok.text    = row['lien_tiktok']    as String? ?? '';
          _autre.text     = row['lien_autre']     as String? ?? '';
          _message.text   = row['message']        as String? ?? '';
        });
      }
    } catch (_) {}
  }

  Future<void> _pickImage() async {
    if (_images.length >= 3) return;
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (xfile != null && mounted) {
      setState(() => _images.add(File(xfile.path)));
    }
  }

  Future<List<String>> _uploadImages(String uid) async {
    final urls = <String>[];
    for (int i = 0; i < _images.length; i++) {
      final bytes = await _images[i].readAsBytes();
      final ext   = _images[i].path.split('.').last;
      final path  = '$uid/${DateTime.now().millisecondsSinceEpoch}_$i.$ext';
      await _supa.storage.from('influencer-proofs').uploadBinary(path, bytes,
          fileOptions: const FileOptions(upsert: true));
      final url = _supa.storage.from('influencer-proofs').getPublicUrl(path);
      urls.add(url);
    }
    return urls;
  }

  Future<void> _submit() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    if (_instagram.text.trim().isEmpty && _tiktok.text.trim().isEmpty && _autre.text.trim().isEmpty) {
      _snack('Ajoute au moins un lien (Instagram, TikTok ou autre).');
      return;
    }
    if (_message.text.trim().isEmpty) {
      _snack('Le message de motivation est requis.');
      return;
    }

    setState(() => _loading = true);
    try {
      final profs = await _supa.from('user_profiles')
          .select('firstname, lastname')
          .eq('uid', uid)
          .eq('profile_type', 'particulier')
          .maybeSingle();
      final pseudo = '${profs?['firstname'] ?? ''} ${profs?['lastname'] ?? ''}'.trim();

      final preuves = await _uploadImages(uid);

      await _supa.from('influencer_requests').insert({
        'uid': uid,
        'pseudo': pseudo,
        'lien_instagram': _instagram.text.trim().isEmpty ? null : _instagram.text.trim(),
        'lien_tiktok':    _tiktok.text.trim().isEmpty    ? null : _tiktok.text.trim(),
        'lien_autre':     _autre.text.trim().isEmpty     ? null : _autre.text.trim(),
        'message':        _message.text.trim(),
        'preuves_urls':   preuves,
        'statut':         'pending',
      });

      // Notif email admin
      try {
        await http.post(
          Uri.parse('https://petsmatchapp.com/api/influencer-request/notify-email'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'pseudo':    pseudo,
            'instagram': _instagram.text.trim(),
            'tiktok':    _tiktok.text.trim(),
            'autre':     _autre.text.trim(),
            'message':   _message.text.trim(),
            'preuves':   preuves,
          }),
        );
      } catch (_) {}

      if (mounted) {
        setState(() => _existingStatut = 'pending');
        _snack('Demande envoyée ! Nous la traitons sous 48 h.');
      }
    } catch (e) {
      if (mounted) _snack('Erreur : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Galey')),
      backgroundColor: _dark,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Badge Influenceur',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header badge
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_green, _tealD], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.auto_awesome, color: Colors.white, size: 22),
                SizedBox(width: 10),
                Text('Badge Influenceur', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18, color: Colors.white)),
              ]),
              const SizedBox(height: 8),
              const Text('Accès à Pets Social + PetsMatch avec badge visible sur ton profil, tes posts et tes commentaires.',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.white70)),
            ]),
          ),
          const SizedBox(height: 24),

          if (_existingStatut != null) ...[
            _statusBanner(_existingStatut!),
            const SizedBox(height: 20),
          ],

          if (_existingStatut == 'approved') ...[
            Center(child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_green, _tealD]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Column(children: [
                Icon(Icons.auto_awesome, color: Colors.white, size: 40),
                SizedBox(height: 12),
                Text('Badge activé !', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 20, color: Colors.white)),
                SizedBox(height: 6),
                Text('Ton badge Influenceur est visible sur ton profil.', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.white70), textAlign: TextAlign.center),
              ]),
            )),
          ] else if (_existingStatut != 'pending') ...[
            // Formulaire
            _label('Tes liens'),
            const SizedBox(height: 8),
            _field(_instagram, 'Instagram', 'https://instagram.com/ton_compte', Icons.camera_alt_outlined),
            const SizedBox(height: 10),
            _field(_tiktok, 'TikTok', 'https://tiktok.com/@ton_compte', Icons.music_note_outlined),
            const SizedBox(height: 10),
            _field(_autre, 'Autre lien (YouTube, etc.)', 'https://...', Icons.link),
            const SizedBox(height: 20),

            _label('Message de motivation'),
            const SizedBox(height: 8),
            TextField(
              controller: _message,
              maxLines: 5,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: _dark),
              decoration: InputDecoration(
                hintText: 'Parle-nous de ton contenu, ta communauté, tes stats…',
                hintStyle: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade400),
                filled: true, fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade200)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade200)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _teal)),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 20),

            _label('Captures d\'écran (max 3)'),
            const SizedBox(height: 8),
            Text('Stats de ton compte, nombre d\'abonnés, engagements…',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
            const SizedBox(height: 10),
            Row(children: [
              ..._images.asMap().entries.map((e) => _imageTile(e.value, e.key)),
              if (_images.length < 3)
                GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300, width: 1.5),
                    ),
                    child: Icon(Icons.add_photo_alternate_outlined, color: Colors.grey.shade400, size: 28),
                  ),
                ),
            ]),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: _loading ? null : _submit,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: _loading ? null : const LinearGradient(colors: [_green, _tealD]),
                    color: _loading ? Colors.grey.shade300 : null,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: _loading
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text('Envoyer ma demande', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
                          ]),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _dark));

  Widget _field(TextEditingController ctrl, String label, String hint, IconData icon) => TextField(
    controller: ctrl,
    style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: _dark),
    decoration: InputDecoration(
      prefixIcon: Icon(icon, color: _teal, size: 20),
      labelText: label,
      labelStyle: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade500),
      hintText: hint,
      hintStyle: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade400),
      filled: true, fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade200)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade200)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _teal)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
  );

  Widget _imageTile(File file, int index) => Stack(
    children: [
      Container(
        width: 80, height: 80,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          image: DecorationImage(image: FileImage(file), fit: BoxFit.cover),
        ),
      ),
      Positioned(top: 2, right: 10,
        child: GestureDetector(
          onTap: () => setState(() => _images.removeAt(index)),
          child: Container(
            width: 20, height: 20,
            decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
            child: const Icon(Icons.close, color: Colors.white, size: 12),
          ),
        ),
      ),
    ],
  );

  Widget _statusBanner(String statut) {
    final isApproved = statut == 'approved';
    final isPending  = statut == 'pending';
    final color = isApproved ? Colors.green.shade600 : isPending ? Colors.orange.shade600 : Colors.red.shade600;
    final icon  = isApproved ? Icons.check_circle_outline : isPending ? Icons.hourglass_top : Icons.cancel_outlined;
    final label = isApproved ? 'Badge activé !' : isPending ? 'Demande en cours d\'examen (48 h)' : 'Demande refusée — tu peux renvoyer une demande';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: color, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}
