import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SignalementsAdmin extends StatefulWidget {
  const SignalementsAdmin({super.key});

  @override
  State<SignalementsAdmin> createState() => _SignalementsAdminState();
}

class _SignalementsAdminState extends State<SignalementsAdmin>
    with SingleTickerProviderStateMixin {
  final _supa = Supabase.instance.client;
  late TabController _tabs;

  static const _statuts = ['en_attente', 'traite', 'rejete'];
  final _data = <String, List<Map<String, dynamic>>>{
    'en_attente': [],
    'traite': [],
    'rejete': [],
  };
  final _loading = <String, bool>{
    'en_attente': false,
    'traite': false,
    'rejete': false,
  };
  int _pendingCount = 0;

  static const _raisonLabels = <String, String>{
    'contenu_inapproprie': 'Contenu inapproprié',
    'spam': 'Spam / Arnaque',
    'faux_profil': 'Faux profil',
    'maltraitance': 'Maltraitance animale',
    'autre': 'Autre',
  };

  static const _targetLabels = <String, String>{
    'user': 'Utilisateur',
    'annonce': 'Annonce',
    'profil_pro': 'Profil pro',
    'balade_ludique': 'Balade ludique',
  };

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() {
      if (_tabs.indexIsChanging) return;
      final statut = _statuts[_tabs.index];
      if (_data[statut]!.isEmpty) _load(statut);
    });
    _load('en_attente');
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load(String statut) async {
    if (_loading[statut]!) return;
    setState(() => _loading[statut] = true);
    try {
      final res = await _supa
          .from('signalements')
          .select()
          .eq('statut', statut)
          .order('created_at', ascending: statut != 'en_attente');
      if (mounted) {
        setState(() {
          _data[statut] = List<Map<String, dynamic>>.from(res as List);
          _loading[statut] = false;
          if (statut == 'en_attente') _pendingCount = _data[statut]!.length;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading[statut] = false);
    }
  }

  Future<void> _handleAction(Map<String, dynamic> sig, String newStatut, String note) async {
    try {
      await _supa.from('signalements').update({
        'statut': newStatut,
        'admin_note': note.trim().isEmpty ? null : note.trim(),
        'handled_at': DateTime.now().toIso8601String(),
        'handled_by': FirebaseAuth.instance.currentUser?.uid,
      }).eq('id', sig['id'] as String);

      setState(() {
        _data['en_attente']!.remove(sig);
        _pendingCount = _data['en_attente']!.length;
        // Force reload de la tab destination
        _data[newStatut] = [];
      });
      if (mounted) _showSnack('Signalement ${newStatut == 'traite' ? 'traité' : 'rejeté'} ✓');
    } catch (e) {
      if (mounted) _showSnack('Erreur : $e', error: true);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Galey')),
      backgroundColor: error ? Colors.red : const Color(0xFF6E9E57),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _openDetail(Map<String, dynamic> sig) {
    final noteCtrl = TextEditingController(text: sig['admin_note'] ?? '');
    final isPending = sig['statut'] == 'en_attente';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          left: 20, right: 20, top: 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.flag_rounded, color: Colors.red, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Signalement — ${_targetLabels[sig['target_type']] ?? sig['target_type']}',
                        style: const TextStyle(
                          fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16,
                        ),
                      ),
                      Text(
                        (sig['target_id'] as String).length > 16
                            ? '${(sig['target_id'] as String).substring(0, 16)}…'
                            : sig['target_id'] as String,
                        style: const TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _InfoRow(label: 'Raison', value: _raisonLabels[sig['raison']] ?? (sig['raison'] as String)),
            if ((sig['description'] as String?) != null && (sig['description'] as String).isNotEmpty)
              _InfoRow(label: 'Description', value: sig['description'] as String),
            _InfoRow(label: 'Signalé par', value: (sig['reporter_uid'] as String).substring(0, 16) + '…'),
            _InfoRow(
              label: 'Date',
              value: _formatDate(sig['created_at'] as String),
            ),
            if (sig['handled_at'] != null)
              _InfoRow(label: 'Traité le', value: _formatDate(sig['handled_at'] as String)),
            const SizedBox(height: 16),
            if (isPending) ...[
              TextField(
                controller: noteCtrl,
                maxLines: 2,
                style: const TextStyle(fontFamily: 'Galey', fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Note admin (optionnel)',
                  labelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF6E9E57)),
                  ),
                  filled: true, fillColor: Colors.grey.shade50,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Rejeter', style: TextStyle(fontFamily: 'Galey')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _handleAction(sig, 'rejete', noteCtrl.text);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Traité', style: TextStyle(fontFamily: 'Galey')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6E9E57),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _handleAction(sig, 'traite', noteCtrl.text);
                      },
                    ),
                  ),
                ],
              ),
            ] else if ((sig['admin_note'] as String?) != null && (sig['admin_note'] as String).isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.sticky_note_2_outlined, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        sig['admin_note'] as String,
                        style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tabs
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabs,
            labelColor: const Color(0xFF0C5C6C),
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFF0C5C6C),
            labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13),
            unselectedLabelStyle: const TextStyle(fontFamily: 'Galey', fontSize: 13),
            tabs: [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('En attente'),
                    if (_pendingCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$_pendingCount',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontFamily: 'Galey', fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Tab(text: 'Traités'),
              const Tab(text: 'Rejetés'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: _statuts.map((statut) => _SignalementList(
              items: _data[statut]!,
              loading: _loading[statut]!,
              onRefresh: () => _load(statut),
              onTap: _openDetail,
              raisonLabels: _raisonLabels,
              targetLabels: _targetLabels,
            )).toList(),
          ),
        ),
      ],
    );
  }
}

// ── Liste ─────────────────────────────────────────────────────────────────────

class _SignalementList extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final bool loading;
  final VoidCallback onRefresh;
  final void Function(Map<String, dynamic>) onTap;
  final Map<String, String> raisonLabels;
  final Map<String, String> targetLabels;

  const _SignalementList({
    required this.items, required this.loading, required this.onRefresh,
    required this.onTap, required this.raisonLabels, required this.targetLabels,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF6E9E57)));
    }
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Aucun signalement',
              style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade400, fontSize: 15),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Rafraîchir', style: TextStyle(fontFamily: 'Galey')),
              onPressed: onRefresh,
              style: TextButton.styleFrom(foregroundColor: const Color(0xFF6E9E57)),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: const Color(0xFF6E9E57),
      onRefresh: () async => onRefresh(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final sig = items[i];
          final raison = raisonLabels[sig['raison']] ?? (sig['raison'] as String);
          final target = targetLabels[sig['target_type']] ?? (sig['target_type'] as String);
          final date = sig['created_at'] as String?;

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onTap(sig),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            sig['target_type'] == 'annonce' ? '📋'
                                : sig['target_type'] == 'user' ? '👤'
                                : sig['target_type'] == 'balade_ludique' ? '🧭'
                                : '💼',
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    target,
                                    style: TextStyle(
                                      fontFamily: 'Galey', fontSize: 11,
                                      fontWeight: FontWeight.w600, color: Colors.red.shade700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    raison,
                                    style: const TextStyle(
                                      fontFamily: 'Galey', fontSize: 12, color: Colors.black87,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            if ((sig['description'] as String?) != null && (sig['description'] as String).isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                sig['description'] as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade600),
                              ),
                            ],
                            if (date != null) ...[
                              const SizedBox(height: 3),
                              Text(
                                _fmtDate(date),
                                style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _fmtDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }
}

// ── InfoRow ───────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'Galey')),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 14, fontFamily: 'Galey', color: Colors.black87)),
        ],
      ),
    );
  }
}
