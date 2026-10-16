import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/config.dart' show kSiteBaseUrl;
import 'package:PetsMatch/services/plan_service.dart';
import 'package:PetsMatch/utils/galeries_api.dart';
import 'package:PetsMatch/pages/pro/photographe_abonnement_page.dart';

/// Galerie client privée (photographe) — une galerie, rattachée ou non à une
/// séance (rdv). Aperçus compressés (filigrane facultatif) dans le bucket
/// privé « galeries », affichés par URL signées courtes (/api/galeries) ;
/// import multiple avec progression et doublons écartés ; couverture, ordre,
/// statut, partage (compte client et / ou lien privé avec expiration),
/// archivage, suppression. Premium. Miroir site : /photographe/galeries/[id].
/// Ouverte depuis une séance ([rdvId] : galerie retrouvée ou créée) ou depuis
/// la liste ([albumId]).
class PhotographeAlbumPage extends StatefulWidget {
  final String? rdvId;
  final String? albumId;
  final String clientName;
  /// Ouvre directement sur les photos choisies par le client.
  final bool filtreSelection;
  const PhotographeAlbumPage({super.key, this.rdvId, this.albumId, this.clientName = '', this.filtreSelection = false});

  @override
  State<PhotographeAlbumPage> createState() => _PhotographeAlbumPageState();
}

class _PhotographeAlbumPageState extends State<PhotographeAlbumPage> {
  static const _teal = Color(0xFF0C5C6C);
  static const _ink = Color(0xFF1F2A2E);
  static const _rouge = Color(0xFFB3261E);
  final _supa = Supabase.instance.client;

  bool _loading = true;
  bool _premium = false;
  String? _albumId;
  String? _erreur;
  Map<String, dynamic> _album = {};
  String _studio = '';
  List<Map<String, dynamic>> _photos = [];
  List<Map<String, dynamic>> _liens = [];
  List<Map<String, dynamic>> _livraison = [];
  bool _filtreSel = false;
  String? _livEnCours;
  final Set<String> _sel = {};
  (int, int)? _progres;

  @override
  void initState() {
    super.initState();
    _filtreSel = widget.filtreSelection;
    _initialiser();
  }

  Future<void> _initialiser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    // Galeries clients : formule Premium uniquement.
    _premium = PlanService.getPhotographeConfig(await PlanService.getPhotographePlanCode(uid)).hasGaleriesClients;
    _albumId = widget.albumId;
    if (_albumId == null && widget.rdvId != null) {
      try {
        final a = await _supa.from('albums_photo').select('id').eq('rdv_id', widget.rdvId!).maybeSingle();
        if (a != null) {
          _albumId = a['id'].toString();
        } else if (_premium) {
          final rdv = await _supa.from('rdv').select('client_uid, client_profile_id, date_heure, prestation_id').eq('id', widget.rdvId!).maybeSingle();
          Map<String, dynamic>? presta;
          if (rdv?['prestation_id'] != null) {
            try {
              presta = await _supa.from('prestations_photographe').select('nb_photos, prix_photo_supp').eq('id', rdv!['prestation_id']).maybeSingle();
            } catch (_) {}
          }
          final row = await _supa.from('albums_photo').insert({
            'pro_uid': uid,
            if (User_Info.activeProfileId.isNotEmpty) 'pro_profile_id': User_Info.activeProfileId,
            'rdv_id': widget.rdvId,
            if (rdv?['client_uid'] != null) 'client_uid': rdv!['client_uid'],
            if (rdv?['client_profile_id'] != null) 'client_profile_id': rdv!['client_profile_id'],
            if (rdv?['date_heure'] != null) 'date_seance': rdv!['date_heure'].toString().substring(0, 10),
            'titre': widget.clientName.isNotEmpty ? 'Séance photo — ${widget.clientName}' : 'Séance photo',
            if (presta?['nb_photos'] != null) 'nb_photos_incluses': presta!['nb_photos'],
            if (presta?['prix_photo_supp'] != null) 'prix_photo_supp': presta!['prix_photo_supp'],
          }).select('id').single();
          _albumId = row['id'].toString();
        }
      } catch (e) {
        _erreur = e.toString().contains('column') ? 'Migrations des galeries à passer.' : 'Erreur : $e';
      }
    }
    await _charger();
  }

  Future<void> _charger() async {
    if (_albumId == null) {
      if (mounted) setState(() { _loading = false; _erreur ??= _premium ? null : 'premium'; });
      return;
    }
    try {
      final c = await GaleriesApi.charger(_albumId!);
      _album = Map<String, dynamic>.from(c['album'] as Map);
      _studio = (c['studio'] as Map?)?['nom']?.toString() ?? '';
      _photos = List<Map<String, dynamic>>.from((c['photos'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      _livraison = List<Map<String, dynamic>>.from(((c['livraison'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
      _sel.removeWhere((id) => !_photos.any((p) => p['id'] == id));
      _liens = List<Map<String, dynamic>>.from(await _supa.from('album_partage').select('id, token, expire_at, actif')
          .eq('album_id', _albumId!).order('created_at', ascending: false));
      _erreur = null;
    } catch (e) {
      _erreur = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _snack(String t) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t, style: const TextStyle(fontFamily: 'Galey'))));
  }

  Future<bool> _majAlbum(Map<String, dynamic> champs) async {
    try {
      await _supa.from('albums_photo').update({...champs, 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', _albumId!);
      await _charger();
      return true;
    } catch (e) {
      _snack(e.toString().contains('column') ? 'Migration migration_photographe_galeries_privees.sql à passer.' : 'Erreur : $e');
      return false;
    }
  }

  Future<void> _importer() async {
    final choix = await ImagePicker().pickMultiImage(requestFullMetadata: false);
    if (choix.isEmpty || _albumId == null) return;
    setState(() => _progres = (0, choix.length));
    try {
      final b = await GaleriesApi.importer(_albumId!, choix.map((x) => File(x.path)).toList(),
          _album['filigrane'] == false ? null : '© ${_studio.isNotEmpty ? _studio : 'PetsMatch'}',
          (f, t) { if (mounted) setState(() => _progres = (f, t)); });
      _snack([
        '${b.ajoutees} photo${b.ajoutees > 1 ? 's' : ''} ajoutée${b.ajoutees > 1 ? 's' : ''}',
        if (b.doublons > 0) '${b.doublons} doublon${b.doublons > 1 ? 's' : ''} ignoré${b.doublons > 1 ? 's' : ''}',
        if (b.erreurs.isNotEmpty) '${b.erreurs.length} erreur${b.erreurs.length > 1 ? 's' : ''}',
      ].join(' · '));
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
    if (mounted) setState(() => _progres = null);
    _charger();
  }

  Future<void> _supprimerSelection() async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text('Supprimer ${_sel.length} photo${_sel.length > 1 ? 's' : ''} ?', style: const TextStyle(fontFamily: 'Galey')),
      content: const Text('Cette action est définitive.', style: TextStyle(fontFamily: 'Galey')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer', style: TextStyle(color: _rouge))),
      ],
    ));
    if (ok != true) return;
    try {
      await GaleriesApi.supprimerPhotos(_albumId!, _sel.toList());
      _sel.clear();
      _charger();
    } catch (e) { _snack(e.toString()); }
  }

  Future<void> _deplacer(int sens) async {
    if (_sel.length != 1) return;
    final i = _photos.indexWhere((p) => p['id'] == _sel.first);
    final j = i + sens;
    if (i < 0 || j < 0 || j >= _photos.length) return;
    for (var k = 0; k < _photos.length; k++) {
      final o = k == i ? j : k == j ? i : k;
      if (_photos[k]['ordre'] != o) await _supa.from('album_photos').update({'ordre': o}).eq('id', _photos[k]['id']);
    }
    _charger();
  }

  Future<void> _partageClient(bool actif) async {
    final clientUid = _album['client_uid']?.toString();
    if (clientUid == null) return;
    final premiere = actif && _album['partage_client'] != true;
    final ok = await _majAlbum({
      'partage_client': actif,
      if (actif && _album['statut'] == 'brouillon') ...{'statut': 'partagee', 'partagee_le': DateTime.now().toUtc().toIso8601String()},
    });
    if (ok && premiere) {
      try {
        await _supa.from('notifications').insert({
          'uid': clientUid,
          'type': 'galerie_disponible',
          'title': 'Votre galerie photo est disponible',
          'body': '${_studio.isNotEmpty ? _studio : 'Votre photographe'} a partagé la galerie « ${_album['titre'] ?? 'Séance photo'} ».',
          if (_album['client_profile_id'] != null) 'profile_id': _album['client_profile_id'],
          'data': {'albumId': _albumId},
          'read': false,
        });
      } catch (_) {}
    }
  }

  Future<void> _creerLien(int jours) async {
    try {
      await _supa.from('album_partage').insert({
        'album_id': _albumId,
        'expire_at': DateTime.now().add(Duration(days: jours)).toUtc().toIso8601String(),
        'actif': true,
      });
      if (_album['statut'] == 'brouillon') {
        await _majAlbum({'statut': 'partagee', 'partagee_le': DateTime.now().toUtc().toIso8601String()});
      } else {
        await _charger();
      }
    } catch (e) { _snack('Erreur : $e'); }
  }

  int get _nbSel => _photos.where((p) => p['selectionnee'] == true).length;

  Future<void> _livrer(int jours) async {
    final res = await FilePicker.pickFiles(allowMultiple: true);
    final fichiers = (res?.files ?? []).where((f) => f.path != null).map((f) => File(f.path!)).toList();
    if (fichiers.isEmpty) return;
    setState(() => _livEnCours = 'Préparation…');
    try {
      await GaleriesApi.livrer(_albumId!, fichiers, jours, (t) { if (mounted) setState(() => _livEnCours = t); });
      _snack('Livraison envoyée${_album['partage_client'] == true ? ' : votre client est prévenu' : ''}');
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
    if (mounted) setState(() => _livEnCours = null);
    _charger();
  }

  Future<void> _selectionEtLivraison() async {
    final incluses = TextEditingController(text: _album['nb_photos_incluses']?.toString() ?? '');
    var jours = 30;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setM) {
        final confirmee = DateTime.tryParse(_album['selection_confirmee_le']?.toString() ?? '')?.toLocal();
        final exp = _livraison.isEmpty ? null : DateTime.tryParse(_livraison.first['expire_le'].toString())?.toLocal();
        final nbLivres = _livraison.fold<int>(0, (n, l) => n + ((l['nb'] as num?)?.toInt() ?? 0));
        final telech = _livraison.fold<int>(0, (n, l) => (l['telechargements'] as num? ?? 0).toInt() > n ? (l['telechargements'] as num).toInt() : n);
        return SafeArea(child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Sélection du client', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: _ink)),
            const SizedBox(height: 6),
            if (confirmee != null) ...[
              Text('$_nbSel photo${_nbSel > 1 ? 's' : ''} choisie${_nbSel > 1 ? 's' : ''}, confirmée le ${DateFormat('dd/MM/yyyy').format(confirmee)}.',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5)),
              if ((_album['selection_commentaire']?.toString() ?? '').isNotEmpty)
                Text('« ${_album['selection_commentaire']} »', style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey.shade700)),
              TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () async {
                  await _majAlbum({'selection_confirmee_le': null, 'statut': 'partagee'});
                  setM(() {});
                },
                child: const Text('Rouvrir la sélection', style: TextStyle(fontFamily: 'Galey', color: _teal)),
              ),
            ] else
              Text(_album['statut'] == 'partagee'
                  ? 'Ouverte : le client choisit ses photos ($_nbSel pour l\'instant) puis confirme.'
                  : 'La sélection s\'ouvre quand la galerie est partagée (statut « En attente de sélection »).',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            TextField(
              controller: incluses, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Photos incluses dans la prestation (facultatif)', border: OutlineInputBorder(), isDense: true),
              onSubmitted: (v) => _majAlbum({'nb_photos_incluses': int.tryParse(v.trim())}),
            ),
            const Divider(height: 28),
            const Text('Livraison des fichiers finaux', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: _ink)),
            const SizedBox(height: 6),
            if (_livraison.isNotEmpty) ...[
              Text('$nbLivres fichiers · ${GaleriesApi.taille(_livraison.fold<num>(0, (n, l) => n + ((l['taille'] as num?) ?? 0)))} · ${_livraison.length} ZIP',
                  style: const TextStyle(fontFamily: 'Galey', fontSize: 13.5)),
              if (exp != null)
                Text('Supprimés automatiquement le ${DateFormat('dd/MM/yyyy').format(exp)} (client et vous prévenus 3 jours avant).',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, color: _rouge)),
              Text('Téléchargements par le client : $telech', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade700)),
              Row(children: [
                TextButton(onPressed: () async {
                  try { await GaleriesApi.actionLivraison(_albumId!, 'prolonger'); await _charger(); setM(() {}); } catch (e) { _snack(e.toString()); }
                }, child: const Text('Prolonger de 30 jours', style: TextStyle(fontFamily: 'Galey', color: _teal))),
                TextButton(onPressed: () async {
                  try { await GaleriesApi.actionLivraison(_albumId!, 'supprimer'); await _charger(); setM(() {}); } catch (e) { _snack(e.toString()); }
                }, child: const Text('Supprimer', style: TextStyle(fontFamily: 'Galey', color: _rouge))),
              ]),
            ] else
              Text('Aucune livraison en cours.', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade700)),
            if (_premium) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: [
                for (final j in [15, 30, 60])
                  ChoiceChip(
                    label: Text('$j jours', style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: jours == j ? Colors.white : _ink)),
                    selected: jours == j, showCheckmark: false, selectedColor: _teal,
                    onSelected: (_) => setM(() => jours = j),
                  ),
              ]),
              const SizedBox(height: 6),
              SizedBox(width: double.infinity, child: FilledButton.icon(
                onPressed: _livEnCours != null ? null : () { Navigator.pop(ctx); _livrer(jours); },
                style: FilledButton.styleFrom(backgroundColor: _teal),
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: Text(_livraison.isEmpty ? 'Choisir les fichiers finaux et livrer' : 'Remplacer la livraison',
                    style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
              )),
              const SizedBox(height: 6),
              Text('Fichiers regroupés en ZIP (45 Mo max par archive) dans un stockage temporaire privé : seul le client peut les télécharger, '
                  'puis ils sont supprimés. La galerie passe en « Livrée » (sans la marquer payée).',
                  style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
            ],
          ]),
        ));
      }),
    );
  }

  Future<void> _reglages() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setM) {
        Future<void> apres(Future<void> f) async { await f; setM(() {}); }
        final actifs = _liens.where((l) => l['actif'] == true
            && (DateTime.tryParse(l['expire_at']?.toString() ?? '')?.isAfter(DateTime.now()) ?? false)).toList();
        return SafeArea(child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Statut', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: _ink)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: kStatutsGalerie.any((s) => s.$1 == _album['statut']) ? _album['statut'] as String : 'brouillon',
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              items: [for (final s in kStatutsGalerie) DropdownMenuItem(value: s.$1, child: Text(s.$2, style: const TextStyle(fontFamily: 'Galey')))],
              onChanged: (v) { if (v != null) apres(_majAlbum({'statut': v, if (v == 'livree') 'livree_le': DateTime.now().toUtc().toIso8601String()})); },
            ),
            Text('Une galerie livrée n\'est pas considérée comme payée.', style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
            const Divider(height: 28),
            const Text('Partage', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 15, color: _ink)),
            if (_album['client_uid'] != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero, activeThumbColor: _teal,
                value: _album['partage_client'] == true,
                onChanged: (v) => apres(_partageClient(v)),
                title: Text('Partager sur le compte de ${widget.clientName.isNotEmpty ? widget.clientName : 'mon client'}',
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 14)),
                subtitle: const Text('Il est prévenu et retrouve la galerie dans « Mes galeries photo ».', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
              )
            else
              Padding(padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('Galerie sans client PetsMatch : utilisez un lien privé.', style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade700))),
            const SizedBox(height: 4),
            const Text('Lien privé', style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13, color: _ink)),
            Wrap(spacing: 6, children: [
              for (final j in [7, 30, 90])
                ActionChip(label: Text('Créer · $j jours', style: const TextStyle(fontFamily: 'Galey', fontSize: 12)), onPressed: () => apres(_creerLien(j))),
            ]),
            for (final l in actifs)
              Builder(builder: (_) {
                final url = '$kSiteBaseUrl/album/${l['token']}';
                final exp = DateTime.tryParse(l['expire_at'].toString())?.toLocal();
                return ListTile(
                  contentPadding: EdgeInsets.zero, dense: true,
                  title: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Galey', fontSize: 12)),
                  subtitle: Text(exp != null ? 'Expire le ${DateFormat('dd/MM/yyyy').format(exp)}' : '', style: const TextStyle(fontFamily: 'Galey', fontSize: 11.5)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: const Icon(Icons.copy_outlined, size: 18), onPressed: () {
                      Clipboard.setData(ClipboardData(text: url));
                      _snack('Lien copié');
                    }),
                    IconButton(icon: const Icon(Icons.ios_share_rounded, size: 18), onPressed: () => Share.share(url)),
                    IconButton(icon: const Icon(Icons.link_off, size: 18, color: _rouge), onPressed: () => apres(() async {
                      await _supa.from('album_partage').update({'actif': false}).eq('id', l['id']);
                      await _charger();
                    }())),
                  ]),
                );
              }),
            Text('Le lien n\'ouvre que cette galerie, n\'est jamais indexé et cesse de fonctionner à l\'expiration.',
                style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: Colors.grey.shade600)),
            const Divider(height: 28),
            SwitchListTile(
              contentPadding: EdgeInsets.zero, activeThumbColor: _teal,
              value: _album['filigrane'] != false,
              onChanged: (v) => apres(_majAlbum({'filigrane': v})),
              title: const Text('Filigrane sur les aperçus', style: TextStyle(fontFamily: 'Galey', fontSize: 14)),
              subtitle: const Text('S\'applique aux prochains imports. Dissuasif, pas une protection absolue.', style: TextStyle(fontFamily: 'Galey', fontSize: 12)),
            ),
            const Divider(height: 28),
            if (_album['statut'] == 'archivee')
              OutlinedButton(onPressed: () => apres(_majAlbum({'statut': _album['partage_client'] == true ? 'partagee' : 'brouillon'}).then((_) {})),
                  child: const Text('Rouvrir la galerie', style: TextStyle(fontFamily: 'Galey')))
            else
              OutlinedButton(onPressed: () => apres(() async {
                await _supa.from('album_partage').update({'actif': false}).eq('album_id', _albumId!);
                await _majAlbum({'statut': 'archivee'});
              }()), child: const Text('Archiver (masque la galerie et désactive les liens)', style: TextStyle(fontFamily: 'Galey'))),
            const SizedBox(height: 6),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: _rouge),
              onPressed: () async {
                final ok = await showDialog<bool>(context: ctx, builder: (d) => AlertDialog(
                  title: const Text('Supprimer la galerie ?', style: TextStyle(fontFamily: 'Galey')),
                  content: const Text('La galerie et toutes ses photos seront supprimées définitivement.', style: TextStyle(fontFamily: 'Galey')),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
                    TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Supprimer', style: TextStyle(color: _rouge))),
                  ],
                ));
                if (ok != true) return;
                try {
                  await GaleriesApi.supprimerGalerie(_albumId!);
                  if (!mounted) return;
                  Navigator.of(context)..pop()..pop();
                } catch (e) { _snack(e.toString()); }
              },
              child: const Text('Supprimer la galerie', style: TextStyle(fontFamily: 'Galey')),
            ),
          ]),
        ));
      }),
    );
  }

  Future<void> _renommer() async {
    final ctrl = TextEditingController(text: _album['titre']?.toString() ?? '');
    final desc = TextEditingController(text: _album['description']?.toString() ?? '');
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Galerie', style: TextStyle(fontFamily: 'Galey')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Titre')),
        TextField(controller: desc, maxLines: 3, decoration: const InputDecoration(labelText: 'Message au client (facultatif)')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
      ],
    ));
    if (ok == true) {
      await _majAlbum({'titre': ctrl.text.trim().isEmpty ? 'Séance photo' : ctrl.text.trim(),
          'description': desc.text.trim().isEmpty ? null : desc.text.trim()});
    }
  }

  List<Map<String, dynamic>> get _vues => _filtreSel ? _photos.where((p) => p['selectionnee'] == true).toList() : _photos;

  @override
  Widget build(BuildContext context) {
    final statut = kStatutsGalerie.where((s) => s.$1 == _album['statut']).firstOrNull?.$2 ?? 'Brouillon';
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        title: Text(_album['titre']?.toString() ?? 'Galerie', style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 16)),
        actions: [
          if (_albumId != null && _erreur == null) ...[
            IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Titre et message', onPressed: _renommer),
            IconButton(icon: const Icon(Icons.favorite_border), tooltip: 'Sélection et livraison', onPressed: _selectionEtLivraison),
            IconButton(icon: const Icon(Icons.tune), tooltip: 'Statut et partage', onPressed: _reglages),
          ],
        ],
      ),
      floatingActionButton: _albumId != null && _premium && _erreur == null && _sel.isEmpty
          ? FloatingActionButton.extended(
              backgroundColor: _teal,
              onPressed: _progres != null ? null : _importer,
              icon: const Icon(Icons.add_photo_alternate_outlined, color: Colors.white),
              label: Text(_progres != null ? 'Import ${_progres!.$1}/${_progres!.$2}' : 'Importer des photos',
                  style: const TextStyle(fontFamily: 'Galey', color: Colors.white)),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _erreur == 'premium'
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('Les galeries clients privées sont réservées à la formule Premium.', textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700, color: _ink)),
                    TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PhotographeAbonnementPage())),
                        child: const Text('Voir les abonnements', style: TextStyle(fontFamily: 'Galey', color: _teal))),
                  ]),
                ))
              : _erreur != null
                  ? Center(child: Padding(padding: const EdgeInsets.all(24),
                      child: Text(_erreur!, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Galey', color: Colors.grey))))
                  : Column(children: [
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                        child: Row(children: [
                          Expanded(child: Text([
                            if (widget.clientName.isNotEmpty) widget.clientName,
                            '${_photos.length} photo${_photos.length > 1 ? 's' : ''}',
                            statut,
                            if (_album['partage_client'] == true) 'partagée au client',
                            if (_livEnCours != null) _livEnCours!,
                          ].join(' · '), style: TextStyle(fontFamily: 'Galey', fontSize: 12.5, color: Colors.grey.shade700))),
                          if (_nbSel > 0 && _sel.isEmpty)
                            FilterChip(
                              label: Text('Sélection client ($_nbSel)', style: TextStyle(fontFamily: 'Galey', fontSize: 11.5, color: _filtreSel ? Colors.white : _ink)),
                              selected: _filtreSel, showCheckmark: false, selectedColor: _teal, visualDensity: VisualDensity.compact,
                              onSelected: (v) => setState(() => _filtreSel = v),
                            ),
                          if (_sel.isNotEmpty) ...[
                            if (_sel.length == 1) ...[
                              IconButton(tooltip: 'Couverture', icon: const Icon(Icons.star_outline, size: 20),
                                  onPressed: () => _majAlbum({'couverture_url': _sel.first})),
                              IconButton(tooltip: 'Avancer', icon: const Icon(Icons.arrow_back, size: 20), onPressed: () => _deplacer(-1)),
                              IconButton(tooltip: 'Reculer', icon: const Icon(Icons.arrow_forward, size: 20), onPressed: () => _deplacer(1)),
                            ],
                            IconButton(tooltip: 'Supprimer', icon: const Icon(Icons.delete_outline, size: 20, color: _rouge), onPressed: _supprimerSelection),
                            IconButton(tooltip: 'Désélectionner', icon: const Icon(Icons.close, size: 20), onPressed: () => setState(_sel.clear)),
                          ],
                        ]),
                      ),
                      if (_progres != null)
                        LinearProgressIndicator(value: _progres!.$2 == 0 ? null : _progres!.$1 / _progres!.$2, color: _teal, backgroundColor: const Color(0xFFE6F2F3)),
                      Expanded(child: _photos.isEmpty
                          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(
                              _premium ? 'Aucune photo. Importez vos aperçus : ils sont compressés et stockés dans un espace privé.'
                                  : 'Import réservé à la formule Premium.',
                              textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade600))))
                          : RefreshIndicator(
                              onRefresh: _charger, color: _teal,
                              child: GridView.builder(
                                padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4),
                                itemCount: _vues.length,
                                itemBuilder: (_, i) {
                                  final p = _vues[i];
                                  final id = p['id'].toString();
                                  final actif = _sel.contains(id);
                                  return GestureDetector(
                                    onTap: () => setState(() => actif ? _sel.remove(id) : _sel.add(id)),
                                    child: Stack(children: [
                                      Positioned.fill(child: Container(
                                        decoration: BoxDecoration(color: const Color(0xFFF0F1EF), borderRadius: BorderRadius.circular(6),
                                            border: actif ? Border.all(color: _teal, width: 3) : null),
                                        child: ClipRRect(borderRadius: BorderRadius.circular(4),
                                            child: Image.network(p['url'].toString(), fit: BoxFit.contain, cacheWidth: 400)),
                                      )),
                                      if (_album['couverture_url'] == id)
                                        Positioned(left: 4, top: 4, child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(4)),
                                          child: const Text('Couverture', style: TextStyle(fontFamily: 'Galey', fontSize: 9.5, fontWeight: FontWeight.w700)),
                                        )),
                                      if (actif)
                                        const Positioned(right: 4, top: 4, child: CircleAvatar(radius: 10, backgroundColor: _teal,
                                            child: Icon(Icons.check, size: 13, color: Colors.white))),
                                      if (p['selectionnee'] == true)
                                        const Positioned(left: 4, bottom: 4, child: CircleAvatar(radius: 10, backgroundColor: _teal,
                                            child: Icon(Icons.favorite, size: 11, color: Colors.white))),
                                    ]),
                                  );
                                },
                              ),
                            )),
                    ]),
    );
  }
}
