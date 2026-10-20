import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:PetsMatch/utils/document_prive.dart';
import 'package:PetsMatch/main.dart' show User_Info;
import 'package:PetsMatch/pages/contrats/contrat_signature_page.dart';

class PensionDocumentsPage extends StatefulWidget {
  const PensionDocumentsPage({super.key});
  @override
  State<PensionDocumentsPage> createState() => _PensionDocumentsPageState();
}

// Contrats seulement : les factures de la pension sont dans Facturation.
class _PensionDocumentsPageState extends State<PensionDocumentsPage> {
  static const _teal = Color(0xFF0C5C6C);
  static const _bg   = Color(0xFFF8F8F6);

  bool _loading  = false;
  bool _uploading = false;

  // Stockage privé Supabase (bucket `documents`) :
  // pension_documents/<uid>/contrats|factures/<nom>. Chemins complets.
  List<String> _contrats = [];
  // Contrats d'hébergement des séjours (documents_animaux), signés ou non.
  List<Map<String, dynamic>> _contratsSejour = [];

  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    setState(() => _loading = true);
    try {
      final store = Supabase.instance.client.storage.from('documents');
      Future<List<String>> lister(String dossier) async {
        final base = 'pension_documents/$_uid/$dossier';
        final items = await store.list(path: base);
        return items.where((f) => f.id != null).map((f) => '$base/${f.name}').toList();
      }
      final contrats = await lister('contrats');
      try {
        var q = Supabase.instance.client.from('documents_animaux')
            .select('id, titre, statut, token, created_at, signe_le, pro_profile_id, metadata')
            .eq('uid_eleveur', _uid).eq('type', 'contrat_hebergement');
        final pid = User_Info.activeProfileId;
        if (pid.isNotEmpty) q = q.or('pro_profile_id.eq.$pid,pro_profile_id.is.null');
        _contratsSejour = List<Map<String, dynamic>>.from(await q.order('created_at', ascending: false));
      } catch (_) { _contratsSejour = []; }
      if (mounted) setState(() => _contrats = contrats);
    } catch (_) {
      // folders may not exist yet
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _uploadContrat() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
    );
    if (result?.files.single.path == null) return;
    setState(() => _uploading = true);
    try {
      final file = File(result!.files.single.path!);
      final name = result.files.single.name;
      await Supabase.instance.client.storage.from('documents').upload(
          'pension_documents/$_uid/contrats/$name', file,
          fileOptions: const FileOptions(upsert: true));
      await _loadDocuments();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contrat ajouté avec succès')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur upload: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _openDocument(String chemin) async {
    try {
      final url = Supabase.instance.client.storage.from('documents').getPublicUrl(chemin);
      await ouvrirDocument(context, url); // lien temporaire (déposant)
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible d\'ouvrir: $e')));
      }
    }
  }

  Future<void> _deleteContrat(String chemin) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer le contrat',
            style: TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700)),
        content: const Text('Ce document sera supprimé définitivement.',
            style: TextStyle(fontFamily: 'Galey')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler',
                style: TextStyle(fontFamily: 'Galey', color: Color(0xFF6F767B))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('Supprimer', style: TextStyle(fontFamily: 'Galey')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client.storage.from('documents').remove([chemin]);
      await _loadDocuments();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur suppression: $e')));
      }
    }
  }

  Widget _buildDocItem(String chemin, {required bool canDelete}) {
    final name = chemin.split('/').last;
    final lower = name.toLowerCase();
    final isPdf = lower.endsWith('.pdf');
    final isDoc = lower.endsWith('.doc') || lower.endsWith('.docx');
    final displayName = name.replaceAll('_', ' ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      color: Colors.white,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: isPdf
                ? Colors.red.shade50
                : isDoc
                    ? Colors.blue.shade50
                    : _teal.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isPdf
                ? Icons.picture_as_pdf_outlined
                : isDoc
                    ? Icons.description_outlined
                    : Icons.insert_drive_file_outlined,
            color: isPdf
                ? Colors.red.shade600
                : isDoc
                    ? Colors.blue.shade600
                    : _teal,
            size: 22,
          ),
        ),
        title: Text(
          displayName,
          style: const TextStyle(
              fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.open_in_new_rounded, size: 20),
              color: _teal,
              tooltip: 'Ouvrir',
              onPressed: () => _openDocument(chemin),
            ),
            if (canDelete)
              IconButton(
                icon: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade400),
                tooltip: 'Supprimer',
                onPressed: () => _deleteContrat(chemin),
              ),
          ],
        ),
      ),
    );
  }

  Widget _contratSejourItem(Map<String, dynamic> c) {
    final meta = (c['metadata'] as Map?) ?? {};
    final statut = c['statut']?.toString() ?? 'brouillon';
    final (lib, coul) = switch (statut) {
      'signe' => ('Signé', const Color(0xFF2E7D5E)),
      'partiellement_signe' => ('Signé en partie', const Color(0xFF2563EB)),
      'en_attente' => ('À signer', const Color(0xFFD97706)),
      'refuse' => ('Refusé', const Color(0xFFB3261E)),
      _ => ('Brouillon', Colors.grey),
    };
    final client = (meta['client_nom'] ?? meta['acquereur_nom'])?.toString() ?? '';
    final dates = [meta['date_entree'], meta['date_sortie_prevue']].where((x) => (x?.toString() ?? '').isNotEmpty)
        .map((x) { final d = DateTime.tryParse(x.toString()); return d == null ? '' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}'; })
        .join(' → ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: ListTile(
        leading: const Icon(Icons.description_outlined, color: _teal),
        title: Text(c['titre']?.toString() ?? "Contrat d'hébergement",
            style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600, fontSize: 13.5)),
        subtitle: Text([client, dates].where((x) => x.isNotEmpty).join(' · '),
            style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade600)),
        trailing: Text(lib, style: TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w700, color: coul)),
        onTap: () async {
          final token = c['token']?.toString();
          if (token == null) return;
          await Navigator.push(context, MaterialPageRoute(builder: (_) => ContratSignaturePage(token: token)));
          _loadDocuments();
        },
      ),
    );
  }

  Widget _buildContratsTab() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _loadDocuments,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: _uploading ? null : _uploadContrat,
            icon: _uploading
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.upload_file_outlined, size: 20),
            label: Text(
              _uploading ? 'Envoi en cours…' : 'Ajouter un contrat',
              style: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _teal,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 20),
          if (_contratsSejour.isNotEmpty) ...[
            Text('Contrats de séjour', style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            for (final c in _contratsSejour) _contratSejourItem(c),
            const SizedBox(height: 20),
            Text('Documents ajoutés', style: TextStyle(fontFamily: 'Galey', fontSize: 12,
                color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
          ],
          if (_contrats.isEmpty) ...[
            const SizedBox(height: 40),
            Center(child: Icon(Icons.folder_open_outlined, size: 56, color: Colors.grey.shade300)),
            const SizedBox(height: 12),
            Center(
              child: Text('Aucun contrat enregistré',
                  style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500)),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text('Ajoutez vos contrats de pension, CGV, etc.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade400)),
            ),
          ] else ...[
            Text(
              '${_contrats.length} document${_contrats.length > 1 ? 's' : ''}',
              style: TextStyle(
                  fontFamily: 'Galey', fontSize: 12,
                  color: Colors.grey.shade500, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ..._contrats.map((r) => _buildDocItem(r, canDelete: true)),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(),
        title: const Text('Documents',
            style: TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700,
                fontSize: 18, color: Color(0xFF1F2A2E))),
      ),
      body: _buildContratsTab(),
    );
  }
}
