import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _kBaseUrl = 'https://www.petsmatchapp.com/partage/';

Future<void> showPartageAnimalSheet(BuildContext context, String animalId, String animalNom) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _PartageAnimalSheet(animalId: animalId, animalNom: animalNom),
  );
}

class _PartageAnimalSheet extends StatefulWidget {
  final String animalId;
  final String animalNom;
  const _PartageAnimalSheet({required this.animalId, required this.animalNom});

  @override
  State<_PartageAnimalSheet> createState() => _PartageAnimalSheetState();
}

class _PartageAnimalSheetState extends State<_PartageAnimalSheet> {
  final _supa = Supabase.instance.client;

  static const _durees = [
    ('24 heures', 1),
    ('3 jours', 3),
    ('7 jours', 7),
    ('30 jours', 30),
  ];

  int _dureeJours = 7;
  bool _creating = false;
  bool _loading = true;
  List<Map<String, dynamic>> _liens = [];
  String? _newToken;

  @override
  void initState() {
    super.initState();
    _loadLiens();
  }

  Future<void> _loadLiens() async {
    setState(() => _loading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final data = await _supa
          .from('partage_animal')
          .select()
          .eq('animal_id', widget.animalId)
          .eq('uid_partageur', uid)
          .eq('actif', true)
          .gt('expire_at', DateTime.now().toIso8601String())
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _liens = List<Map<String, dynamic>>.from(data);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createLien() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _creating = true);
    try {
      final expireAt = DateTime.now().add(Duration(days: _dureeJours)).toUtc();
      final data = await _supa
          .from('partage_animal')
          .insert({
            'animal_id': widget.animalId,
            'uid_partageur': uid,
            'expire_at': expireAt.toIso8601String(),
            'actif': true,
          })
          .select('token')
          .single();
      setState(() {
        _newToken = data['token'] as String;
        _creating = false;
      });
      _loadLiens();
    } catch (e) {
      if (mounted) {
        setState(() => _creating = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _desactiverLien(String id) async {
    await _supa.from('partage_animal').update({'actif': false}).eq('id', id);
    _loadLiens();
    setState(() { if (_newToken != null) _newToken = null; });
  }

  String _formatExpiry(String expireAt) {
    final dt = DateTime.tryParse(expireAt)?.toLocal();
    if (dt == null) return '';
    final diff = dt.difference(DateTime.now());
    if (diff.inDays > 0) return 'Expire dans ${diff.inDays}j';
    if (diff.inHours > 0) return 'Expire dans ${diff.inHours}h';
    return 'Expire bientôt';
  }

  @override
  Widget build(BuildContext context) {
    final token = _newToken ?? (_liens.isNotEmpty ? _liens.first['token'] as String : null);
    final link = token != null ? '$_kBaseUrl$token' : null;

    return Padding(
      padding: EdgeInsets.only(
          left: 20, right: 20, top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.link, color: Color(0xFF6E9E57), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Partager la fiche',
                          style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17)),
                      Text(widget.animalNom,
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Color(0xFF6E9E57))),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text('Lien lecture seule — la personne voit la fiche complète sans pouvoir modifier.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 20),

            // Durée
            const Text('Durée du lien',
                style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: _durees.map((d) {
                final selected = _dureeJours == d.$2;
                return ChoiceChip(
                  label: Text(d.$1, style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                      color: selected ? Colors.white : Colors.black87,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.normal)),
                  selected: selected,
                  selectedColor: const Color(0xFF6E9E57),
                  backgroundColor: Colors.grey.shade100,
                  onSelected: (_) => setState(() => _dureeJours = d.$2),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Bouton créer
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _creating ? null : _createLien,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6E9E57),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: _creating
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.add_link, size: 18),
                label: Text(_creating ? 'Génération...' : 'Créer un nouveau lien',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ),

            // QR + lien si token disponible
            if (link != null) ...[
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              Center(
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE4E7E2)),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: QrImageView(data: link, size: 180, backgroundColor: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F4F8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(link,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontFamily: 'Galey', fontSize: 11, color: Color(0xFF1E2025))),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: link));
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Lien copié !',
                                      style: TextStyle(fontFamily: 'Galey')),
                                    behavior: SnackBarBehavior.floating));
                            },
                            icon: const Icon(Icons.copy_outlined, size: 14),
                            label: const Text('Copier', style: TextStyle(fontFamily: 'Galey')),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => Share.share(link,
                                subject: 'Fiche de ${widget.animalNom}'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0C5C6C),
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.ios_share_rounded, size: 14),
                            label: const Text('Partager', style: TextStyle(fontFamily: 'Galey')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            // Liens actifs existants
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator(color: Color(0xFF6E9E57))),
              )
            else if (_liens.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text('Liens actifs',
                  style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              ..._liens.map((lien) {
                final t = lien['token'] as String;
                final expiry = lien['expire_at'] as String? ?? '';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.link, size: 16, color: Color(0xFF6E9E57)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('.../${t.substring(0, 8)}...',
                                style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                            Text(_formatExpiry(expiry),
                                style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                                    color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => _desactiverLien(lien['id'] as String),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Désactiver',
                            style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
                      ),
                    ],
                  ),
                );
              }),
            ],

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
