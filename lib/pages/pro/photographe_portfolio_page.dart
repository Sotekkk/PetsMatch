// Mon portfolio (photographe) — réalisations PUBLIQUES de la fiche
// professionnelle : import, titre, description, catégorie (liste proposée +
// catégories libres), couverture, ordre, masquage, suppression, aperçu de la
// fiche publique. Stocké dans user_profiles.photos_galerie (jsonb, même
// colonne que la galerie des autres pros, champs ajoutés ignorés ailleurs).
// Jamais alimenté automatiquement par une galerie privée client. Une photo
// où une personne est identifiable n'est publiée qu'avec son autorisation.
// Limite du plan Découverte (maxPhotosPortfolio). Miroir site :
// /photographe/portfolio. Scopé au profil actif.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/services/plan_service.dart';
import 'package:PetsMatch/utils/storage_helper.dart' as storage;
import 'package:PetsMatch/pages/services/service_detail_page.dart';
import 'package:PetsMatch/pages/pro/photographe_abonnement_page.dart';

const _teal = Color(0xFF0C5C6C);
const _ink = Color(0xFF1F2A2E);
const _ambre = Color(0xFFD97706);
const _rouge = Color(0xFFB3261E);

/// Catégories proposées (le photographe peut en créer d'autres).
const List<String> kCategoriesPortfolio = [
  'Portraits canins', 'Portraits félins', 'Photographie équine', 'Studio',
  'Extérieur', 'Élevages', 'Concours et événements', 'Autres animaux',
];

/// Éléments du portfolio, normalisés (anciens formats : URL seule ou
/// {url, legende}). `legende` = titre (compatibilité).
List<Map<String, dynamic>> portfolioItems(dynamic raw) {
  if (raw is! List) return [];
  return raw.map<Map<String, dynamic>?>((e) {
    if (e is String && e.isNotEmpty) return {'url': e, 'legende': ''};
    if (e is Map && (e['url']?.toString() ?? '').isNotEmpty) return Map<String, dynamic>.from(e);
    return null;
  }).whereType<Map<String, dynamic>>().toList();
}

/// Publiable : non masquée, et autorisation obtenue si une personne est
/// identifiable. La couverture passe en tête.
List<Map<String, dynamic>> portfolioPublic(dynamic raw) {
  final l = portfolioItems(raw)
      .where((p) => p['masquee'] != true && !(p['personne_identifiable'] == true && p['autorisation'] != true))
      .toList();
  final i = l.indexWhere((p) => p['couverture'] == true);
  if (i > 0) l.insert(0, l.removeAt(i));
  return l;
}

class PhotographePortfolioPage extends StatefulWidget {
  const PhotographePortfolioPage({super.key});

  @override
  State<PhotographePortfolioPage> createState() => _PhotographePortfolioPageState();
}

class _PhotographePortfolioPageState extends State<PhotographePortfolioPage> {
  final _supa = Supabase.instance.client;
  bool _loading = true, _envoi = false;
  List<Map<String, dynamic>> _items = [];
  int _max = -1;

  String get _pid => User_Info.activeProfileId;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _pid.isEmpty) { setState(() => _loading = false); return; }
    try {
      final plan = await PlanService.getPhotographePlanCode(uid);
      _max = PlanService.getPhotographeConfig(plan).maxPhotosPortfolio;
      final row = await _supa.from('user_profiles').select('photos_galerie').eq('id', _pid).maybeSingle();
      _items = portfolioItems(row?['photos_galerie']);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _enregistrer() async {
    try {
      await _supa.from('user_profiles').update({'photos_galerie': _items}).eq('id', _pid);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enregistrement impossible : $e')));
    }
  }

  bool get _limiteAtteinte => _max >= 0 && _items.length >= _max;

  Future<void> _ajouter() async {
    if (_limiteAtteinte) { _proposerPremium(); return; }
    final choix = await ImagePicker().pickMultiImage(requestFullMetadata: false);
    if (choix.isEmpty) return;
    final restant = _max < 0 ? choix.length : (_max - _items.length).clamp(0, choix.length);
    setState(() => _envoi = true);
    for (final x in choix.take(restant)) {
      try {
        final url = await storage.uploadPhoto(File(x.path), 'portfolio/$_pid/${DateTime.now().microsecondsSinceEpoch}.jpg',
            maxDim: 2000, quality: 85);
        _items.add({'url': url, 'legende': '', 'description': '', 'categorie': '', 'masquee': false});
      } catch (_) {}
    }
    await _enregistrer();
    if (mounted) setState(() => _envoi = false);
    if (restant < choix.length) _proposerPremium();
  }

  void _proposerPremium() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Le plan Découverte est limité à $_max photos de portfolio.', style: const TextStyle(fontFamily: 'Galey')),
      action: SnackBarAction(label: 'Abonnements', onPressed: () =>
          Navigator.push(context, MaterialPageRoute(builder: (_) => const PhotographeAbonnementPage()))),
    ));
  }

  Future<void> _editer(int i) async {
    final it = Map<String, dynamic>.from(_items[i]);
    final titre = TextEditingController(text: it['legende']?.toString() ?? '');
    final desc = TextEditingController(text: it['description']?.toString() ?? '');
    final autre = TextEditingController();
    final categories = {...kCategoriesPortfolio, ..._items.map((e) => e['categorie']?.toString() ?? '').where((c) => c.isNotEmpty)}.toList();
    final res = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setM) => SafeArea(child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ClipRRect(borderRadius: BorderRadius.circular(12),
              child: Image.network(it['url'].toString(), height: 180, fit: BoxFit.contain)),
          const SizedBox(height: 12),
          TextField(controller: titre, decoration: const InputDecoration(labelText: 'Titre', border: OutlineInputBorder(), isDense: true)),
          const SizedBox(height: 10),
          TextField(controller: desc, maxLines: 3, minLines: 1,
              decoration: const InputDecoration(labelText: 'Description (facultatif)', border: OutlineInputBorder(), isDense: true)),
          const SizedBox(height: 12),
          const Text('Catégorie', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13, color: _ink)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in categories)
              ChoiceChip(
                label: Text(c, style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: it['categorie'] == c ? Colors.white : _ink)),
                selected: it['categorie'] == c, showCheckmark: false, selectedColor: _teal, backgroundColor: Colors.white,
                side: BorderSide(color: it['categorie'] == c ? _teal : Colors.grey.shade300),
                onSelected: (v) => setM(() => it['categorie'] = v ? c : ''),
              ),
          ]),
          const SizedBox(height: 6),
          TextField(controller: autre, decoration: const InputDecoration(labelText: 'Nouvelle catégorie', isDense: true, border: OutlineInputBorder()),
              onSubmitted: (v) { if (v.trim().isNotEmpty) setM(() => it['categorie'] = v.trim()); }),
          const SizedBox(height: 8),
          SwitchListTile(contentPadding: EdgeInsets.zero, activeThumbColor: _teal, value: it['couverture'] == true,
              onChanged: (v) => setM(() => it['couverture'] = v),
              title: const Text('Photo de couverture', style: TextStyle(fontFamily: 'Galey', fontSize: 14))),
          SwitchListTile(contentPadding: EdgeInsets.zero, activeThumbColor: _teal, value: it['masquee'] == true,
              onChanged: (v) => setM(() => it['masquee'] = v),
              title: const Text('Masquer de la fiche publique', style: TextStyle(fontFamily: 'Galey', fontSize: 14))),
          SwitchListTile(contentPadding: EdgeInsets.zero, activeThumbColor: _teal, value: it['personne_identifiable'] == true,
              onChanged: (v) => setM(() => it['personne_identifiable'] = v),
              title: const Text('Une personne est identifiable', style: TextStyle(fontFamily: 'Galey', fontSize: 14))),
          if (it['personne_identifiable'] == true)
            CheckboxListTile(contentPadding: EdgeInsets.zero, activeColor: _teal, value: it['autorisation'] == true,
                onChanged: (v) => setM(() => it['autorisation'] = v == true),
                title: const Text('J\'ai son autorisation écrite de publier cette photo', style: TextStyle(fontFamily: 'Galey', fontSize: 13.5)),
                subtitle: it['autorisation'] == true ? null
                    : const Text('Sans autorisation, la photo reste masquée.', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: _ambre))),
          const SizedBox(height: 8),
          Row(children: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'supprimer'),
                child: const Text('Supprimer', style: TextStyle(fontFamily: 'Galey', color: _rouge))),
            const Spacer(),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'ok'), style: FilledButton.styleFrom(backgroundColor: _teal),
                child: const Text('Enregistrer', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700))),
          ]),
        ]),
      ))),
    );
    if (res == 'supprimer') {
      setState(() => _items.removeAt(i));
    } else if (res == 'ok') {
      if (autre.text.trim().isNotEmpty && (it['categorie']?.toString() ?? '').isEmpty) it['categorie'] = autre.text.trim();
      it['legende'] = titre.text.trim();
      it['description'] = desc.text.trim();
      if (it['couverture'] == true) {
        for (final e in _items) { e['couverture'] = false; }
      }
      setState(() => _items[i] = it);
    } else {
      return;
    }
    await _enregistrer();
  }

  @override
  Widget build(BuildContext context) {
    final publiees = portfolioPublic(_items).length;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
        title: const Text('Mon portfolio', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Aperçu de ma fiche publique',
            icon: const Icon(Icons.visibility_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ServiceDetailPage(
                proUid: FirebaseAuth.instance.currentUser!.uid, categoryLabel: 'Photographe',
                categoryColor: _teal, profileTableId: _pid))),
          ),
        ],
      ),
      floatingActionButton: _loading ? null : FloatingActionButton.extended(
        onPressed: _envoi ? null : _ajouter, backgroundColor: _teal, foregroundColor: Colors.white,
        icon: _envoi ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.add_photo_alternate_outlined),
        label: Text(_envoi ? 'Envoi…' : 'Ajouter des photos', style: const TextStyle(fontFamily: 'Galey')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : Column(children: [
              Container(
                width: double.infinity, color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Text(
                  '$publiees publiée${publiees > 1 ? 's' : ''} sur ${_items.length}${_max >= 0 ? ' · plan Découverte : $_max max' : ''}'
                  ' · maintenez une photo pour la déplacer',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade700)),
              ),
              Expanded(child: _items.isEmpty
                  ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(
                      'Présentez vos plus belles réalisations sur votre fiche professionnelle. Les photos de vos galeries clients ne sont jamais publiées automatiquement.',
                      textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade600))))
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 100),
                      itemCount: _items.length,
                      onReorderItem: (a, b) async {
                        setState(() => _items.insert(b, _items.removeAt(a)));
                        await _enregistrer();
                      },
                      itemBuilder: (_, i) {
                        final p = _items[i];
                        final bloquee = p['personne_identifiable'] == true && p['autorisation'] != true;
                        return Card(
                          key: ValueKey(p['url']),
                          elevation: 0, margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE6E8E6))),
                          child: ListTile(
                            contentPadding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                            leading: ClipRRect(borderRadius: BorderRadius.circular(8),
                                child: Opacity(opacity: p['masquee'] == true || bloquee ? 0.45 : 1,
                                    child: Image.network(p['url'].toString(), width: 64, height: 64, fit: BoxFit.cover, cacheWidth: 200))),
                            title: Text((p['legende']?.toString() ?? '').isEmpty ? 'Sans titre' : p['legende'].toString(),
                                style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 14, color: _ink)),
                            subtitle: Text([
                              if ((p['categorie']?.toString() ?? '').isNotEmpty) p['categorie'].toString(),
                              if (p['couverture'] == true) 'Couverture',
                              if (p['masquee'] == true) 'Masquée',
                              if (bloquee) 'Autorisation manquante',
                            ].join(' · '), style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: bloquee ? _ambre : Colors.grey.shade700)),
                            trailing: const Icon(Icons.drag_handle),
                            onTap: () => _editer(i),
                          ),
                        );
                      },
                    )),
            ]),
    );
  }
}
