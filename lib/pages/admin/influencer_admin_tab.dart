import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _teal  = Color(0xFF0C5C6C);
const _green  = Color(0xFF6E9E57);
const _tealD  = Color(0xFF0C5C6C);

class InfluenceurAdminTab extends StatefulWidget {
  const InfluenceurAdminTab({super.key});

  @override
  State<InfluenceurAdminTab> createState() => _InfluenceurAdminTabState();
}

class _InfluenceurAdminTabState extends State<InfluenceurAdminTab> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  String _filter = 'pending';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _supa.from('influencer_requests')
          .select('*')
          .eq('statut', _filter)
          .order('created_at', ascending: false);
      if (mounted) setState(() => _requests = List<Map<String, dynamic>>.from(rows as List));
    } catch (e) {
      if (mounted) _snack('Erreur : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(Map<String, dynamic> req) async {
    try {
      await _supa.from('influencer_requests').update({'statut': 'approved'}).eq('id', req['id']);
      await _supa.from('user_profiles').update({'is_influencer': true}).eq('uid', req['uid'] as String);
      _snack('Badge accordé à ${req['pseudo'] ?? req['uid']}');
      _load();
    } catch (e) {
      _snack('Erreur : $e');
    }
  }

  Future<void> _refuse(Map<String, dynamic> req) async {
    try {
      await _supa.from('influencer_requests').update({'statut': 'refused'}).eq('id', req['id']);
      _snack('Demande refusée.');
      _load();
    } catch (e) {
      _snack('Erreur : $e');
    }
  }

  Future<void> _revoke(Map<String, dynamic> req) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Révoquer le badge', style: TextStyle(fontFamily: 'Galey')),
        content: Text('Retirer le badge influenceur de ${req['pseudo']} ?', style: const TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Révoquer', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _supa.from('user_profiles').update({'is_influencer': false}).eq('uid', req['uid'] as String);
      await _supa.from('influencer_requests').update({'statut': 'refused'}).eq('id', req['id']);
      _snack('Badge révoqué.');
      _load();
    } catch (e) {
      _snack('Erreur : $e');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Galey')),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Filtres
      Container(
        color: const Color(0xFFF8F8F6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          _filterChip('En attente', 'pending'),
          const SizedBox(width: 8),
          _filterChip('Approuvés', 'approved'),
          const SizedBox(width: 8),
          _filterChip('Refusés', 'refused'),
        ]),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _requests.isEmpty
                ? Center(child: Text('Aucune demande ${_filter == 'pending' ? 'en attente' : _filter == 'approved' ? 'approuvée' : 'refusée'}.',
                    style: const TextStyle(fontFamily: 'Galey', color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _requests.length,
                    itemBuilder: (_, i) => _RequestCard(
                      req: _requests[i],
                      onApprove: _filter == 'pending' ? () => _approve(_requests[i]) : null,
                      onRefuse: _filter == 'pending' ? () => _refuse(_requests[i]) : null,
                      onRevoke: _filter == 'approved' ? () => _revoke(_requests[i]) : null,
                    ),
                  ),
      ),
    ]);
  }

  Widget _filterChip(String label, String value) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () { setState(() => _filter = value); _load(); },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? _teal : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? _teal : Colors.grey.shade300),
        ),
        child: Text(label, style: TextStyle(fontFamily: 'Galey', fontSize: 13,
            color: selected ? Colors.white : Colors.grey.shade700, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _RequestCard extends StatefulWidget {
  final Map<String, dynamic> req;
  final VoidCallback? onApprove;
  final VoidCallback? onRefuse;
  final VoidCallback? onRevoke;
  const _RequestCard({required this.req, this.onApprove, this.onRefuse, this.onRevoke});

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final req = widget.req;
    final preuves = (req['preuves_urls'] as List?)?.cast<String>() ?? [];
    final date = req['created_at'] != null
        ? DateTime.tryParse(req['created_at'] as String)?.toLocal()
        : null;
    final dateStr = date != null ? '${date.day.toString().padLeft(2,'0')}/${date.month.toString().padLeft(2,'0')}/${date.year}' : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_green, _tealD]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(req['pseudo'] as String? ?? req['uid'] as String? ?? '?',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15)),
                if (dateStr.isNotEmpty)
                  Text(dateStr, style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
              ])),
              Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.grey),
            ]),

            if (_expanded) ...[
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 14),

              if ((req['lien_instagram'] as String?)?.isNotEmpty == true)
                _linkRow(Icons.camera_alt_outlined, 'Instagram', req['lien_instagram'] as String),
              if ((req['lien_tiktok'] as String?)?.isNotEmpty == true)
                _linkRow(Icons.music_note_outlined, 'TikTok', req['lien_tiktok'] as String),
              if ((req['lien_autre'] as String?)?.isNotEmpty == true)
                _linkRow(Icons.link, 'Autre', req['lien_autre'] as String),

              if ((req['message'] as String?)?.isNotEmpty == true) ...[
                const SizedBox(height: 10),
                const Text('Motivation', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(10)),
                  child: Text(req['message'] as String, style: const TextStyle(fontFamily: 'Galey', fontSize: 13)),
                ),
              ],

              if (preuves.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Captures d\'écran', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 100,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: preuves.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => _showImage(context, preuves[i]),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(preuves[i], width: 100, height: 100, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(width: 100, height: 100,
                                color: Colors.grey.shade200, child: const Icon(Icons.broken_image))),
                      ),
                    ),
                  ),
                ),
              ],

              if (widget.onApprove != null || widget.onRefuse != null || widget.onRevoke != null) ...[
                const SizedBox(height: 16),
                Row(children: [
                  if (widget.onApprove != null) Expanded(child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade600, foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Approuver', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                    onPressed: widget.onApprove,
                  )),
                  if (widget.onApprove != null && widget.onRefuse != null) const SizedBox(width: 10),
                  if (widget.onRefuse != null) Expanded(child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Refuser', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                    onPressed: widget.onRefuse,
                  )),
                  if (widget.onRevoke != null) Expanded(child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    icon: const Icon(Icons.remove_circle_outline, size: 16),
                    label: const Text('Révoquer badge', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
                    onPressed: widget.onRevoke,
                  )),
                ]),
              ],
            ],
          ]),
        ),
      ),
    );
  }

  Widget _linkRow(IconData icon, String label, String url) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      Icon(icon, size: 16, color: Colors.grey),
      const SizedBox(width: 6),
      Text('$label : ', style: const TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w600)),
      Expanded(child: Text(url, style: const TextStyle(fontFamily: 'Galey', fontSize: 13, color: _teal),
          overflow: TextOverflow.ellipsis)),
    ]),
  );

  void _showImage(BuildContext context, String url) {
    showDialog(context: context, builder: (_) => Dialog(
      child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
    ));
  }
}
