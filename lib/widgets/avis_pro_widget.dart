import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Système d'avis générique pour les profils pro (`avis_pro`), scopé
// pro_profile_id dès la création. Conçu pour taxi_animalier, réutilisable
// tel quel par les futurs modules photographe/toiletteur — pas de module
// dédié par profession, contrairement à petfriendly_reviews (lieux).

class AvisProSection extends StatefulWidget {
  final String proUid;
  final String? proProfileId;
  const AvisProSection({super.key, required this.proUid, required this.proProfileId});

  @override
  State<AvisProSection> createState() => _AvisProSectionState();
}

class _AvisProSectionState extends State<AvisProSection> {
  static const _teal = Color(0xFF0C5C6C);
  final _supa = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _avis = [];
  bool _dejaNote = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      var q = _supa.from('avis_pro').select().eq('pro_uid', widget.proUid);
      if (widget.proProfileId != null && widget.proProfileId!.isNotEmpty) {
        q = q.eq('pro_profile_id', widget.proProfileId!);
      }
      final rows = await q.order('created_at', ascending: false);
      final list = List<Map<String, dynamic>>.from(rows as List);
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (mounted) setState(() {
        _avis = list;
        _dejaNote = uid != null && list.any((a) => a['client_uid'] == uid);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _moyenne {
    if (_avis.isEmpty) return 0;
    return _avis.fold<int>(0, (s, a) => s + ((a['note'] as num?)?.toInt() ?? 0)) / _avis.length;
  }

  Future<void> _openForm() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AvisProForm(
        proUid: widget.proUid,
        proProfileId: widget.proProfileId,
        clientUid: uid,
        onSubmit: () { Navigator.pop(context); _load(); },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Avis', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(width: 8),
        if (_avis.isNotEmpty) ...[
          const Icon(Icons.star_rounded, size: 16, color: Color(0xFFFFA000)),
          const SizedBox(width: 2),
          Text('${_moyenne.toStringAsFixed(1)} (${_avis.length})',
              style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey)),
        ],
        const Spacer(),
        if (!_dejaNote)
          TextButton(onPressed: _openForm, child: const Text('Laisser un avis', style: TextStyle(fontFamily: 'Galey', color: _teal))),
      ]),
      const SizedBox(height: 8),
      if (_avis.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('Aucun avis pour l\'instant.', style: TextStyle(fontFamily: 'Galey', color: Colors.grey)),
        )
      else
        ..._avis.map((a) => _AvisTile(avis: a)),
    ]);
  }
}

class _AvisTile extends StatelessWidget {
  final Map<String, dynamic> avis;
  const _AvisTile({required this.avis});

  @override
  Widget build(BuildContext context) {
    final note = (avis['note'] as num?)?.toInt() ?? 0;
    final dh = DateTime.tryParse(avis['created_at']?.toString() ?? '');
    final dateStr = dh != null ? DateFormat('d MMM yyyy', 'fr_FR').format(dh) : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade100)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Row(children: List.generate(5, (i) =>
              Icon(i < note ? Icons.star_rounded : Icons.star_border_rounded, size: 16, color: const Color(0xFFFFA000)))),
          const Spacer(),
          Text(dateStr, style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade400)),
        ]),
        if ((avis['commentaire'] as String?)?.isNotEmpty == true) ...[
          const SizedBox(height: 6),
          Text(avis['commentaire'].toString(), style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
        ],
      ]),
    );
  }
}

class _AvisProForm extends StatefulWidget {
  final String proUid;
  final String? proProfileId;
  final String clientUid;
  final VoidCallback onSubmit;
  const _AvisProForm({required this.proUid, required this.proProfileId, required this.clientUid, required this.onSubmit});

  @override
  State<_AvisProForm> createState() => _AvisProFormState();
}

class _AvisProFormState extends State<_AvisProForm> {
  static const _teal = Color(0xFF0C5C6C);
  int _note = 0;
  final _commentCtrl = TextEditingController();
  bool _saving = false;

  Future<void> _submit() async {
    if (_note == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Merci de choisir une note', style: TextStyle(fontFamily: 'Galey'))));
      return;
    }
    setState(() => _saving = true);
    try {
      final profileRow = await Supabase.instance.client
          .from('user_profiles').select('id').eq('uid', widget.clientUid).eq('profile_type', 'particulier').maybeSingle();
      final clientProfileId = profileRow?['id'] as String?;
      await Supabase.instance.client.from('avis_pro').insert({
        'pro_uid': widget.proUid,
        if (widget.proProfileId != null && widget.proProfileId!.isNotEmpty) 'pro_profile_id': widget.proProfileId,
        'client_uid': widget.clientUid,
        if (clientProfileId != null) 'client_profile_id': clientProfileId,
        'note': _note,
        'commentaire': _commentCtrl.text.trim().isEmpty ? null : _commentCtrl.text.trim(),
      });
      widget.onSubmit();
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().contains('unique')
                ? 'Vous avez déjà laissé un avis'
                : 'Erreur : $e', style: const TextStyle(fontFamily: 'Galey'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Laisser un avis', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18)),
        const SizedBox(height: 16),
        Row(children: List.generate(5, (i) => GestureDetector(
          onTap: () => setState(() => _note = i + 1),
          child: Icon(i < _note ? Icons.star_rounded : Icons.star_border_rounded, size: 32, color: const Color(0xFFFFA000)),
        ))),
        const SizedBox(height: 12),
        TextField(
          controller: _commentCtrl,
          maxLines: 4,
          maxLength: 500,
          style: const TextStyle(fontFamily: 'Galey'),
          decoration: InputDecoration(
            hintText: 'Votre commentaire (optionnel)…',
            hintStyle: const TextStyle(fontFamily: 'Galey'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _teal)),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: _teal, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: _saving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Publier l\'avis', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }
}
