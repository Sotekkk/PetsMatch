import 'package:PetsMatch/main.dart';
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

// Pharmacie vétérinaire (migration_inventaire_veto.sql).
const _categoriesVeto = [
  ('medicament',      '💊', 'Médicaments',          Color(0xFFE53E3E)),
  ('vaccin',          '💉', 'Vaccins',              Color(0xFF2B6CB0)),
  ('antiparasitaire', '🛡️', 'Antiparasitaires',     Color(0xFF805AD5)),
  ('alimentation',    '🥣', 'Alimentation',         Color(0xFF6E9E57)),
  ('consommable',     '🩹', 'Consommables médicaux', _teal),
  ('hygiene',         '🧴', 'Hygiène & soins',      Color(0xFF8E24AA)),
  ('autre',           '📦', 'Autre',                Color(0xFF718096)),
];

const _unites = ['kg', 'g', 'L', 'mL', 'sac', 'paquet', 'boite', 'unité'];
const _unitesVeto = ['boite', 'flacon', 'dose', 'comprimé', 'pipette', 'seringue', 'ampoule', 'sac', 'kg', 'mL', 'unité'];

(String, String, String, Color) _catDef(String cat) =>
    _categories.where((c) => c.$1 == cat).firstOrNull
    ?? _categoriesVeto.where((c) => c.$1 == cat).firstOrNull
    ?? _categories.last;

String _catLabel(String cat) => _catDef(cat).$3;

/// État du stock : 'rupture' (≤ 0), 'alerte' (seuil atteint) ou 'normal'.
String _etatStock(Map<String, dynamic> i) {
  final q = (i['quantite'] as num?)?.toDouble() ?? 0;
  if (q <= 0) return 'rupture';
  final s = (i['quantite_alerte'] as num?)?.toDouble();
  if (i['alerte_active'] == true && s != null && q <= s) return 'alerte';
  return 'normal';
}

const _ambre = Color(0xFFB45309);
const _rouge = Color(0xFFC53030);

/// Péremption : null = sans date ; < 0 = périmé ; sinon jours restants.
int? _joursAvantPeremption(Map<String, dynamic> item) {
  final d = DateTime.tryParse(item['date_peremption']?.toString() ?? '');
  if (d == null) return null;
  final now = DateTime.now();
  return DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
}

String _fmtQte(double q) =>
    q == q.truncateToDouble() ? q.toInt().toString() : q.toStringAsFixed(1);

// Pluriel français : kg/g/L/mL invariables, sinon +s si qté > 1
String _plural(String unite, double qty) {
  if (qty <= 1) return unite;
  const invariable = {'kg', 'g', 'L', 'l', 'mL', 'ml', 'cl', 'dl', '%'};
  if (invariable.contains(unite)) return unite;
  if (unite.endsWith('s') || unite.endsWith('x')) return unite;
  return '${unite}s';
}

// ── Page principale ─────────────────────────────────────────────────────────────

class InventairePage extends StatefulWidget {
  final String? eleveurProfileIdOverride;
  final String? eleveurUidOverride;
  final bool readOnly;
  /// Ouvre directement la fiche de cet article au chargement (ex. depuis une
  /// notification « Stock bas »).
  final String? focusItemId;
  /// Pharmacie vétérinaire (lots, péremptions, froid, stupéfiants). Par
  /// défaut : profil actif vétérinaire.
  final bool? veto;
  const InventairePage({
    super.key,
    this.eleveurProfileIdOverride,
    this.eleveurUidOverride,
    this.readOnly = false,
    this.focusItemId,
    this.veto,
  });
  @override
  State<InventairePage> createState() => _InventairePageState();
}

class _InventairePageState extends State<InventairePage> {
  final _supa = Supabase.instance.client;
  final _uid  = FirebaseAuth.instance.currentUser!.uid;
  String? _profileId;

  bool get _veto => widget.veto ?? User_Info.catPro == 'veterinaire';
  bool _loading = true;
  bool _focusHandled = false;
  List<Map<String, dynamic>> _items = [];
  String _catFilter = 'tous';
  String _etatFilter = 'tous'; // tous | normal | alerte | rupture
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      if (widget.eleveurProfileIdOverride != null) {
        _profileId = widget.eleveurProfileIdOverride;
      } else {
        // Profil actuellement actif (peut différer du profil "is_main" —
        // sinon un utilisateur multi-profil basculé sur son profil
        // association/refuge voit l'inventaire de son profil éleveur).
        _profileId = User_Info.activeProfileId.isNotEmpty ? User_Info.activeProfileId : null;
      }
      final effectiveUid = widget.eleveurUidOverride ?? _uid;
      final rows = _profileId != null
          ? await _supa.from('inventaire_items').select().eq('eleveur_profile_id', _profileId!).order('categorie').order('nom')
          : await _supa.from('inventaire_items').select().eq('uid_eleveur', effectiveUid).order('categorie').order('nom');
      if (mounted) setState(() {
        _items = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
      // Ouvre la fiche de l'article ciblé (notification « Stock bas »)
      if (widget.focusItemId != null && !_focusHandled && mounted) {
        _focusHandled = true;
        final target = _items.where((i) => '${i['id']}' == widget.focusItemId).toList();
        if (target.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            showModalBottomSheet(
              context: context, isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => _ItemDetailSheet(
                item: target.first, uid: widget.eleveurUidOverride ?? _uid, onChanged: _load),
            );
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur chargement : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _createCommandeTask(Map<String, dynamic> item) async {
    final label = 'Commander : ${item['nom']}';
    final today = DateTime.now().toIso8601String().split('T').first;
    // Évite les doublons : une seule tâche en_attente par article
    final existing = await _supa
        .from('plan_taches')
        .select('id')
        .eq('uid_eleveur', _uid)
        .eq('label', label)
        .eq('statut', 'en_attente')
        .maybeSingle();
    if (existing != null) return;

    await _supa.from('plan_taches').insert({
      'uid_eleveur': _uid,
      if (_profileId != null) 'eleveur_profile_id': _profileId,
      if (_profileId != null) 'profile_id': _profileId,
      'profil_source': 'eleveur',
      'label': label,
      'type_acte': 'commande',
      'date_prevue': today,
      'statut': 'en_attente',
      'jour_traitement': 1,
      'total_jours': 1,
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Tâche créée : commande à passer'),
        backgroundColor: _teal,
        action: SnackBarAction(
          label: 'Voir',
          textColor: Colors.white,
          onPressed: () => Navigator.pushNamed(context, '/planning'),
        ),
        duration: const Duration(seconds: 4),
      ));
    }
  }

  List<Map<String, dynamic>> get _displayed {
    final q = _search.trim().toLowerCase();
    return _items.where((i) =>
        (_catFilter == 'tous' || i['categorie'] == _catFilter) &&
        (_etatFilter == 'tous' || _etatStock(i) == _etatFilter) &&
        (q.isEmpty || (i['nom'] ?? '').toString().toLowerCase().contains(q) ||
            (i['notes'] ?? '').toString().toLowerCase().contains(q) ||
            (i['lot'] ?? '').toString().toLowerCase().contains(q))).toList();
  }

  bool get _filtresActifs => _catFilter != 'tous' || _etatFilter != 'tous' || _search.trim().isNotEmpty;

  List<Map<String, dynamic>> get _alertes => _items.where((i) => _etatStock(i) != 'normal').toList();

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
        title: Text(_veto ? 'Inventaire & pharmacie' : 'Inventaire',
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 18, color: _dark)),
        actions: [
          if (_veto)
            IconButton(
              icon: const Icon(Icons.menu_book_outlined, color: _teal),
              tooltip: 'Registre des stupéfiants',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _RegistreStupefiantsPage(
                items: _items.where((i) => i['stupefiant'] == true).toList()))),
            ),
          if (!widget.readOnly)
            IconButton(
              icon: const Icon(Icons.add, color: _teal),
              tooltip: 'Ajouter un article',
              onPressed: () async {
                await showModalBottomSheet(
                  context: context, isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => _ItemFormSheet(uid: widget.eleveurUidOverride ?? _uid, profileId: _profileId, veto: _veto, onSaved: _load),
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
                slivers: [SliverToBoxAdapter(child: _buildContent())],
              ),
            ),
    );
  }

  Widget _buildContent() {
    final perimes = _veto ? _items.where((i) => (_joursAvantPeremption(i) ?? 999) < 0).toList() : const [];
    final bientot = _veto ? _items.where((i) {
      final j = _joursAvantPeremption(i);
      return j != null && j >= 0 && j <= 30;
    }).toList() : const [];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Péremptions (pharmacie vétérinaire)
        if (perimes.isNotEmpty || bientot.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFCA5A5)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Péremptions : ${perimes.length} périmé(s), ${bientot.length} sous 30 jours',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF991B1B))),
              const SizedBox(height: 6),
              for (final a in [...perimes, ...bientot])
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('${a['nom']}'
                      '${(a['lot'] as String?)?.isNotEmpty == true ? ' (lot ${a['lot']})' : ''} — '
                      '${(_joursAvantPeremption(a) ?? 0) < 0 ? 'périmé' : 'expire dans ${_joursAvantPeremption(a)} j'}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF991B1B))),
                ),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        // Stocks à réapprovisionner (sobre, sans pictogramme)
        if (_alertes.isNotEmpty) ...[
          InkWell(
            onTap: () => setState(() => _etatFilter = _etatFilter == 'alerte' ? 'tous' : 'alerte'),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Text(
                '${_alertes.length} article${_alertes.length > 1 ? 's' : ''} à réapprovisionner — '
                '${_alertes.map((a) => a['nom']).join(', ')}',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Color(0xFF92400E)),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Recherche + filtres (menus déroulants, combinables)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(children: [
            TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v),
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
              decoration: _filtreDeco('Rechercher un article…', prefix: const Icon(Icons.search, size: 18, color: Colors.grey)),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(
                initialValue: _catFilter,
                isExpanded: true,
                decoration: _filtreDeco('Catégorie', label: true),
                items: [
                  const DropdownMenuItem(value: 'tous', child: Text('Toutes les catégories', overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Galey', fontSize: 13.5))),
                  for (final c in [
                    ...(_veto ? _categoriesVeto : _categories),
                    ..._items.map((i) => (i['categorie'] ?? 'autre').toString()).toSet()
                        .where((c) => !(_veto ? _categoriesVeto : _categories).any((x) => x.$1 == c))
                        .map(_catDef),
                  ])
                    DropdownMenuItem(value: c.$1, child: Text(c.$3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5))),
                ],
                onChanged: (v) => setState(() => _catFilter = v ?? 'tous'),
              )),
              const SizedBox(width: 8),
              Expanded(child: DropdownButtonFormField<String>(
                initialValue: _etatFilter,
                isExpanded: true,
                decoration: _filtreDeco('État du stock', label: true),
                items: const [
                  ('tous', 'Tous les états'), ('normal', 'Stock normal'),
                  ('alerte', 'Seuil d’alerte atteint'), ('rupture', 'Rupture'),
                ].map((e) => DropdownMenuItem(value: e.$1, child: Text(e.$2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5)))).toList(),
                onChanged: (v) => setState(() => _etatFilter = v ?? 'tous'),
              )),
            ]),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
          child: Row(children: [
            Text('${_displayed.length} article${_displayed.length > 1 ? 's' : ''} affiché${_displayed.length > 1 ? 's' : ''}',
                style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade500)),
            const Spacer(),
            if (_filtresActifs)
              TextButton(
                onPressed: () => setState(() { _searchCtrl.clear(); _search = ''; _catFilter = 'tous'; _etatFilter = 'tous'; }),
                style: TextButton.styleFrom(foregroundColor: _teal, padding: EdgeInsets.zero, minimumSize: const Size(0, 28)),
                child: const Text('Réinitialiser', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
          ]),
        ),

        // Liste
        if (_displayed.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(children: [
                Text(_items.isEmpty ? 'Aucun article' : 'Aucun article ne correspond à ces filtres',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, color: Colors.grey, fontSize: 15)),
                if (_items.isEmpty)
                  const Text('Appuyez sur + pour ajouter votre premier stock',
                      style: TextStyle(color: Colors.grey, fontSize: 12), textAlign: TextAlign.center),
              ]),
            ),
          )
        else
          ...(_displayed.map((item) => _ItemCard(
            item: item,
            profileId: _profileId,
            onTap: () => showModalBottomSheet(
              context: context, isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => _ItemDetailSheet(item: item, uid: widget.eleveurUidOverride ?? _uid, onChanged: _load),
            ),
            onEdit: widget.readOnly ? null : () => showModalBottomSheet(
              context: context, isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => _ItemFormSheet(uid: widget.eleveurUidOverride ?? _uid, profileId: _profileId, item: item, veto: _veto, onSaved: _load),
            ),
            onAjuster: widget.readOnly ? null : () => showModalBottomSheet(
              context: context, isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => _QuickMvtSheet(
                item: item, type: 'restock',
                uid: widget.eleveurUidOverride ?? _uid, profileId: _profileId,
                onSaved: _load,
                onAlerte: () => _createCommandeTask(item),
              ),
            ),
          ))),
      ]),
    );
  }
}

// ── Champs de filtre ───────────────────────────────────────────────────────────

InputDecoration _filtreDeco(String texte, {bool label = false, Widget? prefix}) => InputDecoration(
      labelText: label ? texte : null,
      hintText: label ? null : texte,
      labelStyle: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600),
      hintStyle: TextStyle(fontFamily: 'Galey', fontSize: 13.5, color: Colors.grey.shade400),
      prefixIcon: prefix,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _teal, width: 1.5)),
    );

// ── Carte article (ligne compacte) ─────────────────────────────────────────────

class _ItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final String? profileId;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onAjuster;

  const _ItemCard({
    required this.item,
    this.profileId,
    required this.onTap,
    this.onEdit,
    this.onAjuster,
  });

  @override
  Widget build(BuildContext context) {
    final cat   = item['categorie'] as String? ?? 'autre';
    final qte   = (item['quantite'] as num?)?.toDouble() ?? 0;
    final seuil = item['quantite_alerte'] != null ? (item['quantite_alerte'] as num).toDouble() : null;
    final unite = item['unite'] as String? ?? '';
    final etat  = _etatStock(item);
    final couleurStock = etat == 'rupture' ? _rouge : etat == 'alerte' ? _ambre : _dark;
    final j = _joursAvantPeremption(item);
    final mentions = [
      if ((item['lot'] as String?)?.isNotEmpty == true) 'Lot ${item['lot']}',
      if (j != null) j < 0 ? 'Périmé' : 'Exp. ${DateFormat('dd/MM/yyyy').format(DateTime.parse(item['date_peremption'].toString()))}',
      if (item['froid'] == true) '+2 / +8 °C',
      if (item['stupefiant'] == true) 'Stupéfiant',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item['nom'] as String? ?? '',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _dark),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(_catLabel(cat), style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
                if (mentions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(mentions.join(' · '),
                        style: TextStyle(fontFamily: 'Galey', fontSize: 11,
                            color: j != null && j <= 30 ? _rouge : Colors.grey.shade500)),
                  ),
              ])),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${_fmtQte(qte)} ${_plural(unite, qte)}',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w700, color: couleurStock)),
                Text(item['alerte_active'] == true && seuil != null
                        ? 'Seuil : ${_fmtQte(seuil)} ${_plural(unite, seuil)}' : 'Seuil : —',
                    style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
                if (etat != 'normal')
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: etat == 'rupture' ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(etat == 'rupture' ? 'Rupture' : 'Seuil atteint',
                        style: TextStyle(fontFamily: 'Galey', fontSize: 10.5, fontWeight: FontWeight.w700, color: couleurStock)),
                  ),
              ]),
            ]),
          ),
        ),
        if (onAjuster != null || onEdit != null)
          Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade100))),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (onAjuster != null)
                OutlinedButton(
                  onPressed: onAjuster,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _teal, side: const BorderSide(color: _teal),
                    minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Ajuster le stock', style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              if (onEdit != null) ...[
                const SizedBox(width: 6),
                TextButton(
                  onPressed: onEdit,
                  style: TextButton.styleFrom(foregroundColor: _teal, minimumSize: const Size(0, 34)),
                  child: const Text('Modifier', style: TextStyle(fontFamily: 'Galey', fontSize: 13, fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline)),
                ),
              ],
            ]),
          ),
      ]),
    );
  }
}

// ── Bottom sheet mouvement avec quantité personnalisée ─────────────────────────

class _QuickMvtSheet extends StatefulWidget {
  final Map<String, dynamic> item;
  final String type;
  final String uid;
  final String? profileId;
  final VoidCallback onSaved;
  final VoidCallback? onAlerte;
  const _QuickMvtSheet({required this.item, required this.type, required this.uid, this.profileId, required this.onSaved, this.onAlerte});
  @override
  State<_QuickMvtSheet> createState() => _QuickMvtSheetState();
}

class _QuickMvtSheetState extends State<_QuickMvtSheet> {
  final _supa     = Supabase.instance.client;
  /// Sens choisi dans « Ajuster le stock » : restock (ajouter) ou consommation (retirer)
  late String _type = widget.type;
  final _qteCtrl  = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _saving = false;
  String? _error;
  double? _preview;

  @override
  void initState() {
    super.initState();
    _qteCtrl.addListener(_updatePreview);
  }

  void _updatePreview() {
    final qte = double.tryParse(_qteCtrl.text.replaceAll(',', '.'));
    final current = (widget.item['quantite'] as num).toDouble();
    setState(() {
      if (qte != null && qte > 0) {
        _preview = _type == 'consommation' ? current - qte : current + qte;
      } else {
        _preview = null;
      }
    });
  }

  @override
  void dispose() { _qteCtrl.dispose(); _noteCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    final qte = double.tryParse(_qteCtrl.text.replaceAll(',', '.'));
    if (qte == null || qte <= 0) {
      setState(() => _error = 'Quantité invalide');
      return;
    }
    final stock = (widget.item['quantite'] as num).toDouble();
    if (_type == 'consommation' && qte > stock) {
      setState(() => _error = 'Impossible de retirer plus que le stock actuel '
          '(${_fmtQte(stock)} ${_plural(widget.item['unite'] as String? ?? '', stock)}).');
      return;
    }
    // Registre des stupéfiants : origine / motif obligatoire.
    if (widget.item['stupefiant'] == true && _noteCtrl.text.trim().isEmpty) {
      setState(() => _error = _type == 'consommation'
          ? 'Stupéfiant : indiquez le motif (animal, ordonnance…)'
          : 'Stupéfiant : indiquez l\'origine (fournisseur, bon de livraison…)');
      return;
    }
    setState(() { _saving = true; _error = null; });

    try {
      final isConsomm = _type == 'consommation';
      final currentQte = (widget.item['quantite'] as num).toDouble();
      final newQte = isConsomm
          ? (currentQte - qte).clamp(0.0, double.infinity)
          : currentQte + qte;

      await _supa.from('inventaire_mouvements').insert({
        'item_id': widget.item['id'],
        'uid_eleveur': widget.uid,
        'uid_auteur': widget.uid,
        if (widget.profileId != null) 'eleveur_profile_id': widget.profileId,
        if (widget.profileId != null) 'auteur_profile_id': widget.profileId,
        'type': _type,
        'quantite': qte,
        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        // Registre des stupéfiants : stock après mouvement + auteur réel (pas
        // le compte de la structure). Colonnes de migration_inventaire_veto.sql.
        if (widget.item['stupefiant'] == true) ...{
          'stock_apres': newQte,
          'uid_auteur': FirebaseAuth.instance.currentUser?.uid ?? widget.uid,
        },
      });
      await _supa.from('inventaire_items')
          .update({'quantite': newQte, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', widget.item['id']);

      final seuil = widget.item['quantite_alerte'] != null
          ? (widget.item['quantite_alerte'] as num).toDouble()
          : null;
      if (isConsomm && widget.item['alerte_active'] == true && seuil != null && newQte <= seuil) {
        await _supa.from('notifications').insert({
          'uid': widget.uid,
          'type': 'inventaire_alerte',
          'title': '⚠️ Stock bas : ${widget.item['nom']}',
          'body': 'Il ne reste que ${_fmtQte(newQte)} ${_plural(widget.item['unite'] as String? ?? '', newQte)} de ${widget.item['nom']}.',
          if (widget.profileId != null) 'profile_id': widget.profileId,
          'data': {'itemId': widget.item['id']},
          'read': false,
        });
        widget.onAlerte?.call();
      }

      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() { _saving = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConsomm = _type == 'consommation';
    final unite = widget.item['unite'] as String? ?? '';
    final stock = (widget.item['quantite'] as num).toDouble();
    final qte = double.tryParse(_qteCtrl.text.replaceAll(',', '.'));
    final trop = isConsomm && qte != null && qte > stock;
    final stupefiant = widget.item['stupefiant'] == true;
    InputDecoration deco({String? hint, Widget? suffix}) => InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          suffixIcon: suffix,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: trop ? Colors.red.shade300 : Colors.grey.shade300)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: trop ? Colors.red.shade300 : _teal, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          const Text('Ajuster le stock',
              style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w800, fontSize: 16, color: _dark)),
          const SizedBox(height: 2),
          Text('${widget.item['nom']} — stock actuel : ${_fmtQte(stock)} ${_plural(unite, stock)}',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              for (final s in const [('restock', 'Ajouter'), ('consommation', 'Retirer')])
                Expanded(child: GestureDetector(
                  onTap: () { setState(() { _type = s.$1; _error = null; }); _updatePreview(); },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: _type == s.$1 ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: _type == s.$1 ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4)] : null,
                    ),
                    child: Text(s.$2, textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Galey', fontSize: 13,
                        fontWeight: FontWeight.w700, color: _type == s.$1 ? _teal : Colors.grey.shade600)),
                  ),
                )),
            ]),
          ),
          const SizedBox(height: 14),
          Text('Quantité', style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
          const SizedBox(height: 6),
          TextField(
            controller: _qteCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 15),
            decoration: deco(hint: '0', suffix: Padding(
              padding: const EdgeInsets.only(right: 12, top: 12),
              child: Text(_plural(unite, qte ?? 2), style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade600)),
            )),
          ),
          const SizedBox(height: 6),
          if (trop)
            Text('Impossible de retirer plus que le stock actuel (${_fmtQte(stock)} ${_plural(unite, stock)}).',
                style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.red))
          else if (_preview != null)
            Text.rich(TextSpan(style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade600), children: [
              const TextSpan(text: 'Nouveau stock : '),
              TextSpan(text: '${_fmtQte(_preview!)} ${_plural(unite, _preview!)}',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: _dark)),
            ])),
          const SizedBox(height: 12),
          Text(stupefiant ? (isConsomm ? 'Motif (animal, ordonnance…) *' : 'Origine (fournisseur, bon de livraison…) *') : 'Note (facultative)',
              style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
          const SizedBox(height: 6),
          TextField(
            controller: _noteCtrl,
            style: const TextStyle(fontFamily: 'Galey', fontSize: 14),
            decoration: deco(hint: isConsomm ? 'Ex : sac terminé' : 'Ex : livraison reçue'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: Colors.grey.shade300),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Annuler', style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade700)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: (_saving || trop || qte == null || qte <= 0) ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(_saving ? 'Enregistrement…' : 'Enregistrer',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ]),
      ),
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
    if (mounted) setState(() {
      _mouvements = List<Map<String, dynamic>>.from(rows);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return DraggableScrollableSheet(
      initialChildSize: 0.6, maxChildSize: 0.9, minChildSize: 0.4,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(children: [
              Text('${item['nom'] ?? ''}',
                  style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16, color: _dark)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.grey),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
          ),
          const Divider(height: 1),
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
                          final date = DateTime.tryParse(m['created_at'] as String? ?? '')?.toLocal();
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(children: [
                              SizedBox(width: 72, child: Text(type == 'consommation' ? 'Retrait' : type == 'restock' ? 'Ajout' : 'Correction',
                                  style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600))),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(
                                    '${type == 'consommation' ? '−' : '+'}${_fmtQte(qte)} ${_plural(item['unite'] as String? ?? '', qte)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700, fontSize: 14,
                                      color: type == 'consommation' ? Colors.red.shade600 : Colors.green.shade600,
                                    ),
                                  ),
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

// ── Formulaire article (ajout / édition) ──────────────────────────────────────

class _ItemFormSheet extends StatefulWidget {
  final String uid;
  final String? profileId;
  final Map<String, dynamic>? item;
  final VoidCallback onSaved;
  final bool veto;
  const _ItemFormSheet({required this.uid, this.profileId, this.item, required this.onSaved, this.veto = false});
  @override
  State<_ItemFormSheet> createState() => _ItemFormSheetState();
}

class _ItemFormSheetState extends State<_ItemFormSheet> {
  final _supa      = Supabase.instance.client;
  final _nomCtrl   = TextEditingController();
  final _qteCtrl   = TextEditingController(text: '0');
  final _seuilCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  // Pharmacie vétérinaire
  final _lotCtrl   = TextEditingController();
  final _prixCtrl  = TextEditingController();
  DateTime? _peremption;
  bool _froid = false;
  bool _stupefiant = false;

  String _cat   = 'alimentation';
  String _unite = 'kg';
  bool   _alerte  = true;
  bool   _saving  = false;
  bool   _deleting = false;
  String? _error;

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
      _notesCtrl.text  = item['notes'] as String? ?? '';
      if (item['quantite_alerte'] != null) {
        _seuilCtrl.text = _fmtQte((item['quantite_alerte'] as num).toDouble());
      }
      _lotCtrl.text = item['lot'] as String? ?? '';
      if (item['prix_vente'] != null) _prixCtrl.text = (item['prix_vente'] as num).toString();
      _peremption = DateTime.tryParse(item['date_peremption']?.toString() ?? '');
      _froid = item['froid'] as bool? ?? false;
      _stupefiant = item['stupefiant'] as bool? ?? false;
    } else if (widget.veto) {
      _cat = 'medicament';
      _unite = 'boite';
    }
  }

  @override
  void dispose() {
    _nomCtrl.dispose(); _qteCtrl.dispose();
    _seuilCtrl.dispose(); _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nomCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Le nom est requis');
      return;
    }
    final qte = double.tryParse(_qteCtrl.text.replaceAll(',', '.'));
    if (qte == null) {
      setState(() => _error = 'Quantité invalide');
      return;
    }
    setState(() { _saving = true; _error = null; });

    try {
      final payload = {
        'uid_eleveur': widget.uid,
        if (widget.profileId != null) 'eleveur_profile_id': widget.profileId,
        'nom': _nomCtrl.text.trim(),
        'categorie': _cat,
        'unite': _unite,
        'quantite': qte,
        'quantite_alerte': (_alerte && _seuilCtrl.text.isNotEmpty)
            ? double.tryParse(_seuilCtrl.text.replaceAll(',', '.'))
            : null,
        'alerte_active': _alerte,
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'updated_at': DateTime.now().toIso8601String(),
        if (widget.veto) ...{
          'lot': _lotCtrl.text.trim().isEmpty ? null : _lotCtrl.text.trim(),
          'date_peremption': _peremption?.toIso8601String().substring(0, 10),
          'prix_vente': double.tryParse(_prixCtrl.text.replaceAll(',', '.')),
          'froid': _froid,
          'stupefiant': _stupefiant,
        },
      };
      if (widget.item != null) {
        await _supa.from('inventaire_items').update(payload).eq('id', widget.item!['id']);
      } else {
        await _supa.from('inventaire_items').insert(payload);
      }
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() { _saving = false; _error = e.toString(); });
    }
  }

  Future<void> _delete() async {
    if (widget.item == null) return;
    setState(() => _deleting = true);
    try {
      await _supa.from('inventaire_items').delete().eq('id', widget.item!['id']);
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() { _deleting = false; _error = e.toString(); });
    }
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
    // Container fixe avec scroll interne — le bouton "Enregistrer" est toujours visible
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        // Handle + header
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

        // Formulaire scrollable
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Nom
              TextField(
                controller: _nomCtrl,
                decoration: _dec('Nom de l\'article *', 'ex : Croquettes Royal Canin…'),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 14),

              // Catégorie
              DropdownButtonFormField<String>(
                initialValue: _cat,
                isExpanded: true,
                decoration: _dec('Catégorie'),
                items: [
                  ...(widget.veto ? _categoriesVeto : _categories),
                  if (!(widget.veto ? _categoriesVeto : _categories).any((c) => c.$1 == _cat)) _catDef(_cat),
                ].map((c) => DropdownMenuItem(value: c.$1, child: Text(c.$3, style: const TextStyle(fontFamily: 'Galey', fontSize: 14)))).toList(),
                onChanged: (v) => setState(() {
                  _cat = v ?? _cat;
                  if (widget.veto && _cat == 'vaccin') _froid = true;
                }),
              ),
              const SizedBox(height: 14),

              // Quantité + Unité
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _qteCtrl,
                    decoration: _dec('Quantité actuelle'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _unite,
                    decoration: _dec('Unité'),
                    items: {...(widget.veto ? _unitesVeto : _unites), _unite}
                        .map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
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

              if (widget.veto) ...[
                Row(children: [
                  Expanded(child: TextField(controller: _lotCtrl, decoration: _dec('N° de lot'))),
                  const SizedBox(width: 10),
                  Expanded(child: OutlinedButton.icon(
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(_peremption == null
                        ? 'Péremption'
                        : DateFormat('dd/MM/yyyy').format(_peremption!)),
                    onPressed: () async {
                      final d = await showDatePicker(context: context,
                          initialDate: _peremption ?? DateTime.now().add(const Duration(days: 365)),
                          firstDate: DateTime(2020), lastDate: DateTime(2040));
                      if (d != null) setState(() => _peremption = d);
                    },
                  )),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: _prixCtrl,
                  decoration: _dec('Prix de vente (€)', 'si vendu au comptoir'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('❄️ À conserver au froid (+2 / +8 °C)', style: TextStyle(fontSize: 13)),
                  value: _froid,
                  onChanged: (v) => setState(() => _froid = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('🔒 Stupéfiant', style: TextStyle(fontSize: 13)),
                  subtitle: const Text('Chaque entrée / sortie est inscrite au registre, avec son motif.',
                      style: TextStyle(fontSize: 11)),
                  value: _stupefiant,
                  onChanged: (v) => setState(() => _stupefiant = v),
                ),
                const SizedBox(height: 10),
              ],
              // Notes
              TextField(
                controller: _notesCtrl,
                decoration: _dec('Notes', 'Marque, fournisseur, remarques…'),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
            ]),
          ),
        ),

        // Boutons toujours visibles en bas
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Row(children: [
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
                child: Text(
                  _saving ? 'Enregistrement…' : widget.item == null ? 'Ajouter' : 'Enregistrer',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}


// ── Registre des stupéfiants (pharmacie vétérinaire) ──────────────────────────
// Entrées / sorties de chaque produit classé stupéfiant, avec le motif, le
// stock restant après le mouvement et l'auteur. À conserver 10 ans.
class _RegistreStupefiantsPage extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  const _RegistreStupefiantsPage({required this.items});
  @override
  State<_RegistreStupefiantsPage> createState() => _RegistreStupefiantsPageState();
}

class _RegistreStupefiantsPageState extends State<_RegistreStupefiantsPage> {
  final _supa = Supabase.instance.client;
  List<Map<String, dynamic>> _mvts = [];
  Map<String, String> _auteurs = {};
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final ids = widget.items.map((i) => i['id'].toString()).toList();
    if (ids.isEmpty) { setState(() => _loading = false); return; }
    try {
      final rows = List<Map<String, dynamic>>.from(await _supa.from('inventaire_mouvements')
          .select().inFilter('item_id', ids).order('created_at', ascending: false) as List);
      final uids = rows.map((r) => r['uid_auteur']?.toString()).whereType<String>().toSet().toList();
      final noms = <String, String>{};
      if (uids.isNotEmpty) {
        for (final u in await _supa.from('users_complet').select('uid, firstname, lastname').inFilter('uid', uids) as List) {
          noms[u['uid'].toString()] = '${u['firstname'] ?? ''} ${u['lastname'] ?? ''}'.trim();
        }
      }
      if (mounted) setState(() { _mvts = rows; _auteurs = noms; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nomItem = {for (final i in widget.items) i['id'].toString(): i};
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        iconTheme: const IconThemeData(color: _dark),
        title: const Text('Registre des stupéfiants',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 17, color: _dark)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : widget.items.isEmpty
              ? const Center(child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Aucun produit marqué « Stupéfiant » dans l\'inventaire.',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                ))
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Text('Entrées et sorties au fil de l\'eau, stock après mouvement et motif. '
                      'Registre à conserver 10 ans ; balance mensuelle à faire sur le stock affiché.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 12),
                  for (final it in widget.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('🔒 ${it['nom']} — stock actuel : ${_fmtQte((it['quantite'] as num).toDouble())} '
                          '${_plural(it['unite'] as String? ?? '', (it['quantite'] as num).toDouble())}',
                          style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  const Divider(height: 24),
                  if (_mvts.isEmpty)
                    const Text('Aucun mouvement enregistré.', style: TextStyle(color: Colors.grey)),
                  for (final m in _mvts)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(m['type'] == 'consommation' ? '⬇️ Sortie' : '⬆️ Entrée',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
                                  color: m['type'] == 'consommation' ? Colors.red.shade700 : _green)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(nomItem[m['item_id'].toString()]?['nom']?.toString() ?? '',
                              style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                          Text(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(m['created_at'].toString()).toLocal()),
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        ]),
                        const SizedBox(height: 4),
                        Text('Quantité : ${_fmtQte((m['quantite'] as num).toDouble())}'
                            '${m['stock_apres'] != null ? '  ·  stock après : ${_fmtQte((m['stock_apres'] as num).toDouble())}' : ''}',
                            style: const TextStyle(fontSize: 12)),
                        if ((m['note'] as String?)?.isNotEmpty == true)
                          Text('Motif : ${m['note']}', style: const TextStyle(fontSize: 12)),
                        if (_auteurs[m['uid_auteur']?.toString()]?.isNotEmpty == true)
                          Text('Par ${_auteurs[m['uid_auteur'].toString()]}',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      ]),
                    ),
                ]),
    );
  }
}
