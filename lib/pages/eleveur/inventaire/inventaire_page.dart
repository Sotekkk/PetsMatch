import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Constantes ─────────────────────────────────────────────────────────────────

const _teal  = Color(0xFF0C5C6C);
const _green = Color(0xFF6E9E57);
const _dark  = Color(0xFF1F2A2E);
const _bg    = Color(0xFFF8F8F6);

const _categories = [
  ('alimentation', '🍖', 'Alimentation',  Color(0xFF6E9E57)),
  ('litiere',      '🪣', 'Litière',       Color(0xFF8B6914)),
  ('medicament',   '💊', 'Médicaments',   Color(0xFFE53E3E)),
  ('accessoire',   '🎾', 'Accessoires',   _teal),
  ('hygiene',      '🧴', 'Hygiène',       Color(0xFF8E24AA)),
  ('autre',        '📦', 'Autre',         Color(0xFF718096)),
];

const _unites = ['kg', 'g', 'L', 'mL', 'sac', 'paquet', 'boite', 'unité'];

String _catEmoji(String cat) =>
    _categories.firstWhere((c) => c.$1 == cat, orElse: () => _categories.last).$2;

Color _catColor(String cat) =>
    _categories.firstWhere((c) => c.$1 == cat, orElse: () => _categories.last).$4;

// ── Page principale ─────────────────────────────────────────────────────────────

class InventairePage extends StatefulWidget {
  const InventairePage({super.key});
  @override
  State<InventairePage> createState() => _InventairePageState();
}

class _InventairePageState extends State<InventairePage> {
  final _supa = Supabase.instance.client;
  final _uid  = FirebaseAuth.instance.currentUser!.uid;

  bool _loading = true;
  List<Map<String, dynamic>> _items = [];
  String _catFilter = 'tous';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final rows = await _supa
          .from('inventaire_items')
          .select()
          .eq('uid_eleveur', _uid)
          .order('categorie')
          .order('nom');
      if (mounted) setState(() { _items = List<Map<String, dynamic>>.from(rows); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _displayed => _catFilter == 'tous'
      ? _items
      : _items.where((i) => i['categorie'] == _catFilter).toList();

  List<Map<String, dynamic>> get _alertes => _items.where((i) =>
      i['alerte_active'] == true &&
      i['quantite_alerte'] != null &&
      (i['quantite'] as num) <= (i['quantite_alerte'] as num)).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: _dark, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('📦 Inventaire',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18, color: _dark)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: _teal),
            onPressed: () async {
              await showModalBottomSheet(
                context: context, isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => _ItemFormSheet(uid: _uid, onSaved: _load),
              );
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : RefreshIndicator(
              onRefresh: _load, color: _teal,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildContent()),
                ],
              ),
            ),
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Alertes stock bas
        if (_alertes.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFCD34D)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('⚠️ Stock bas (${_alertes.length})',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700,
                      fontSize: 13, color: Color(0xFF92400E))),
              const SizedBox(height: 6),
              ..._alertes.map((a) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${a['nom']} — ${a['quantite']} ${a['unite']} restant(s)',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                ),
              )),
            ]),
          ),
          const SizedBox(height: 12),
        ],

        // Filtres catégorie
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _CatChip(label: 'Tous (${_items.length})', active: _catFilter == 'tous',
                  color: _dark, onTap: () => setState(() => _catFilter = 'tous')),
              ..._categories.map((c) {
                final count = _items.where((i) => i['categorie'] == c.$1).length;
                if (count == 0) return const SizedBox.shrink();
                return _CatChip(
                  label: '${c.$2} ${c.$3} ($count)',
                  active: _catFilter == c.$1,
                  color: c.$4,
                  onTap: () => setState(() => _catFilter = c.$1),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Liste
        if (_displayed.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Column(children: [
                Text('📦', style: TextStyle(fontSize: 48)),
                SizedBox(height: 12),
                Text('Aucun article', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600,
                    color: Colors.grey, fontSize: 15)),
                Text('Appuyez sur + pour ajouter votre premier stock',
                    style: TextStyle(color: Colors.grey, fontSize: 12), textAlign: TextAlign.center),
              ]),
            ),
          )
        else
          ...(_displayed.map((item) => _ItemCard(
            item: item,
            onTap: () => showModalBottomSheet(
              context: context, isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => _ItemDetailSheet(item: item, uid: _uid, onChanged: _load),
            ),
            onEdit: () => showModalBottomSheet(
              context: context, isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => _ItemFormSheet(uid: _uid, item: item, onSaved: _load),
            ),
          ))),
      ]),
    );
  }
}

// ── Chip catégorie ─────────────────────────────────────────────────────────────

class _CatChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  const _CatChip({required this.label, required this.active, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? color : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? color : Colors.grey.shade300),
      ),
      child: Text(label,
          style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600,
            color: active ? Colors.white : Colors.grey.shade700,
          )),
    ),
  );
}

// ── Carte article ──────────────────────────────────────────────────────────────

class _ItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  const _ItemCard({required this.item, required this.onTap, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final cat   = item['categorie'] as String? ?? 'autre';
    final qte   = (item['quantite'] as num).toDouble();
    final seuil = item['quantite_alerte'] != null ? (item['quantite_alerte'] as num).toDouble() : null;
    final isLow = item['alerte_active'] == true && seuil != null && qte <= seuil;
    final color = _catColor(cat);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isLow ? const Color(0xFFFCD34D) : Colors.grey.shade100),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            // Icône catégorie
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(child: Text(_catEmoji(cat), style: const TextStyle(fontSize: 20))),
            ),
            const SizedBox(width: 12),

            // Infos
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(item['nom'] as String? ?? '',
                        style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 14, color: _dark),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  if (isLow)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('⚠️ bas', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF92400E))),
                    ),
                ]),
                const SizedBox(height: 2),
                Text(
                  '${_fmtQte(qte)} ${item['unite'] ?? ''}${seuil != null ? '  ·  seuil ${_fmtQte(seuil)} ${item['unite'] ?? ''}' : ''}',
                  style: TextStyle(fontSize: 12, color: isLow ? const Color(0xFFB45309) : color, fontWeight: FontWeight.w600),
                ),
              ]),
            ),

            const SizedBox(width: 8),
            // Boutons rapides
            _QuickBtn('+', color: _green, onTap: () => _showQuickMvt(context, item, 'restock')),
            const SizedBox(width: 6),
            _QuickBtn('−', color: Colors.red.shade400, onTap: () => _showQuickMvt(context, item, 'consommation')),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onEdit,
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                child: const Center(child: Text('✏️', style: TextStyle(fontSize: 14))),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _showQuickMvt(BuildContext context, Map<String, dynamic> item, String type) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuickMvtSheet(
        item: item,
        type: type,
        uid: FirebaseAuth.instance.currentUser!.uid,
        onSaved: () => Navigator.pop(context),
      ),
    );
  }
}

class _QuickBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickBtn(this.label, {required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(child: Text(label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color))),
    ),
  );
}

String _fmtQte(double q) => q == q.truncateToDouble() ? q.toInt().toString() : q.toStringAsFixed(1);

// ── Bottom sheet mouvement rapide ──────────────────────────────────────────────

class _QuickMvtSheet extends StatefulWidget {
  final Map<String, dynamic> item;
  final String type; // 'consommation' | 'restock'
  final String uid;
  final VoidCallback onSaved;
  const _QuickMvtSheet({required this.item, required this.type, required this.uid, required this.onSaved});
  @override
  State<_QuickMvtSheet> createState() => _QuickMvtSheetState();
}

class _QuickMvtSheetState extends State<_QuickMvtSheet> {
  final _supa = Supabase.instance.client;
  final _qteCtrl  = TextEditingController(text: '1');
  final _noteCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() { _qteCtrl.dispose(); _noteCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    final qte = double.tryParse(_qteCtrl.text);
    if (qte == null || qte <= 0) return;
    setState(() => _saving = true);

    final isConsomm = widget.type == 'consommation';
    final currentQte = (widget.item['quantite'] as num).toDouble();
    final newQte = isConsomm ? (currentQte - qte).clamp(0, double.infinity) : currentQte + qte;

    await _supa.from('inventaire_mouvements').insert({
      'item_id': widget.item['id'],
      'uid_eleveur': widget.uid,
      'uid_auteur': widget.uid,
      'type': widget.type,
      'quantite': qte,
      'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
    });
    await _supa.from('inventaire_items')
        .update({'quantite': newQte, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', widget.item['id']);

    // Notification si seuil atteint
    if (isConsomm &&
        widget.item['alerte_active'] == true &&
        widget.item['quantite_alerte'] != null &&
        newQte <= (widget.item['quantite_alerte'] as num)) {
      await _supa.from('notifications').insert({
        'uid': widget.uid,
        'type': 'inventaire_alerte',
        'title': '⚠️ Stock bas : ${widget.item['nom']}',
        'body': 'Il ne reste que ${_fmtQte(newQte)} ${widget.item['unite']} de ${widget.item['nom']}.',
        'data': {'itemId': widget.item['id']},
        'read': false,
      });
    }

    if (mounted) { widget.onSaved(); Navigator.pop(context); }
  }

  @override
  Widget build(BuildContext context) {
    final isConsomm = widget.type == 'consommation';
    final color     = isConsomm ? Colors.red : _green;

    return Container(
      margin: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          '${isConsomm ? '📉 Consommation' : '📦 Réapprovisionnement'} — ${widget.item['nom']}',
          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: _dark),
        ),
        const SizedBox(height: 16),
        Text('Quantité (${widget.item['unite'] ?? 'unité'})',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
        const SizedBox(height: 6),
        TextField(
          controller: _qteCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: color, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
        const SizedBox(height: 12),
        Text('Note (optionnel)',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
        const SizedBox(height: 6),
        TextField(
          controller: _noteCtrl,
          decoration: InputDecoration(
            hintText: isConsomm ? 'ex : paquet de croquettes terminé' : 'ex : livraison reçue',
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: color, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Annuler'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(_saving ? '…' : 'Enregistrer',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ── Bottom sheet détail / historique ──────────────────────────────────────────

class _ItemDetailSheet extends StatefulWidget {
  final Map<String, dynamic> item;
  final String uid;
  final VoidCallback onChanged;
  const _ItemDetailSheet({required this.item, required this.uid, required this.onChanged});
  @override
  State<_ItemDetailSheet> createState() => _ItemDetailSheetState();
}

class _ItemDetailSheetState extends State<_ItemDetailSheet> {
  final _supa = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _mouvements = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final rows = await _supa
        .from('inventaire_mouvements')
        .select()
        .eq('item_id', widget.item['id'])
        .order('created_at', ascending: false)
        .limit(30);
    if (mounted) setState(() { _mouvements = List<Map<String, dynamic>>.from(rows); _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final cat  = item['categorie'] as String? ?? 'autre';

    return DraggableScrollableSheet(
      initialChildSize: 0.6, maxChildSize: 0.9, minChildSize: 0.4,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          // Handle
          Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(children: [
              Text('${_catEmoji(cat)} ${item['nom'] ?? ''}',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: _dark)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.grey),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
          ),
          const Divider(height: 1),
          // Mouvements
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _teal))
                : _mouvements.isEmpty
                    ? const Center(child: Text('Aucun mouvement', style: TextStyle(color: Colors.grey)))
                    : ListView.separated(
                        controller: ctrl,
                        padding: const EdgeInsets.all(16),
                        itemCount: _mouvements.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final m    = _mouvements[i];
                          final type = m['type'] as String? ?? 'consommation';
                          final qte  = (m['quantite'] as num).toDouble();
                          final date = DateTime.tryParse(m['created_at'] as String? ?? '');
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(children: [
                              Text(type == 'consommation' ? '📉' : type == 'restock' ? '📦' : '🔧',
                                  style: const TextStyle(fontSize: 20)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Text(
                                      '${type == 'consommation' ? '−' : '+'}${_fmtQte(qte)} ${item['unite'] ?? ''}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700, fontSize: 14,
                                        color: type == 'consommation' ? Colors.red.shade600 : Colors.green.shade600,
                                      ),
                                    ),
                                  ]),
                                  if ((m['note'] as String?)?.isNotEmpty == true)
                                    Text(m['note'] as String,
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                  if (date != null)
                                    Text(
                                      DateFormat('dd MMM yyyy HH:mm', 'fr_FR').format(date),
                                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                ]),
                              ),
                            ]),
                          );
                        },
                      ),
          ),
        ]),
      ),
    );
  }
}

// ── Formulaire article ─────────────────────────────────────────────────────────

class _ItemFormSheet extends StatefulWidget {
  final String uid;
  final Map<String, dynamic>? item;
  final VoidCallback onSaved;
  const _ItemFormSheet({required this.uid, this.item, required this.onSaved});
  @override
  State<_ItemFormSheet> createState() => _ItemFormSheetState();
}

class _ItemFormSheetState extends State<_ItemFormSheet> {
  final _supa     = Supabase.instance.client;
  final _nomCtrl  = TextEditingController();
  final _qteCtrl  = TextEditingController(text: '0');
  final _seuilCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String _cat   = 'alimentation';
  String _unite = 'kg';
  bool   _alerte = true;
  bool   _saving  = false;
  bool   _deleting = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    if (item != null) {
      _nomCtrl.text   = item['nom'] as String? ?? '';
      _qteCtrl.text   = _fmtQte((item['quantite'] as num).toDouble());
      _cat             = item['categorie'] as String? ?? 'alimentation';
      _unite           = item['unite'] as String? ?? 'kg';
      _alerte          = item['alerte_active'] as bool? ?? true;
      _notesCtrl.text = item['notes'] as String? ?? '';
      if (item['quantite_alerte'] != null) {
        _seuilCtrl.text = _fmtQte((item['quantite_alerte'] as num).toDouble());
      }
    }
  }

  @override
  void dispose() {
    _nomCtrl.dispose(); _qteCtrl.dispose();
    _seuilCtrl.dispose(); _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nomCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final payload = {
      'uid_eleveur': widget.uid,
      'nom': _nomCtrl.text.trim(),
      'categorie': _cat,
      'unite': _unite,
      'quantite': double.tryParse(_qteCtrl.text) ?? 0,
      'quantite_alerte': _seuilCtrl.text.isNotEmpty ? double.tryParse(_seuilCtrl.text) : null,
      'alerte_active': _alerte,
      'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (widget.item != null) {
      await _supa.from('inventaire_items').update(payload).eq('id', widget.item!['id']);
    } else {
      await _supa.from('inventaire_items').insert(payload);
    }
    if (mounted) { widget.onSaved(); Navigator.pop(context); }
  }

  Future<void> _delete() async {
    if (widget.item == null) return;
    setState(() => _deleting = true);
    await _supa.from('inventaire_items').delete().eq('id', widget.item!['id']);
    if (mounted) { widget.onSaved(); Navigator.pop(context); }
  }

  InputDecoration _dec(String label, [String? hint]) => InputDecoration(
    labelText: label, hintText: hint,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _teal, width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85, maxChildSize: 0.95, minChildSize: 0.5,
        builder: (_, ctrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                Text(widget.item == null ? 'Nouvel article' : 'Modifier l\'article',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17, color: _dark)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => Navigator.pop(context)),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(controller: ctrl, padding: const EdgeInsets.all(16), children: [
                // Nom
                TextField(controller: _nomCtrl, decoration: _dec('Nom de l\'article *', 'ex : Croquettes Royal Canin…'),
                    textCapitalization: TextCapitalization.sentences),
                const SizedBox(height: 14),

                // Catégorie
                const Text('Catégorie', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: _categories.map((c) {
                  final sel = _cat == c.$1;
                  return GestureDetector(
                    onTap: () => setState(() => _cat = c.$1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: sel ? c.$4 : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: sel ? c.$4 : Colors.grey.shade300),
                      ),
                      child: Text('${c.$2} ${c.$3}',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                              color: sel ? Colors.white : Colors.grey.shade700)),
                    ),
                  );
                }).toList()),
                const SizedBox(height: 14),

                // Quantité + Unité
                Row(children: [
                  Expanded(
                    child: TextField(controller: _qteCtrl, decoration: _dec('Quantité actuelle'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _unite,
                      decoration: _dec('Unité'),
                      items: _unites.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                      onChanged: (v) => setState(() => _unite = v!),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),

                // Alerte
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFCD34D)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('⚠️ Alerte stock bas',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF92400E))),
                      Switch(
                        value: _alerte,
                        activeColor: const Color(0xFFF59E0B),
                        onChanged: (v) => setState(() => _alerte = v),
                      ),
                    ]),
                    if (_alerte) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _seuilCtrl,
                        decoration: InputDecoration(
                          labelText: 'Notifier quand il reste moins de… ($_unite)',
                          hintText: 'ex : 2',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFF59E0B), width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ],
                  ]),
                ),
                const SizedBox(height: 14),

                // Notes
                TextField(controller: _notesCtrl, decoration: _dec('Notes', 'Marque, fournisseur, remarques…'),
                    maxLines: 2),
                const SizedBox(height: 24),

                // Boutons
                Row(children: [
                  if (widget.item != null) ...[
                    OutlinedButton(
                      onPressed: _deleting ? null : _delete,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(_deleting ? '…' : 'Supprimer',
                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _teal,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(_saving ? 'Enregistrement…' : widget.item == null ? 'Ajouter' : 'Enregistrer',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
