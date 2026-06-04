import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PensionDocumentsPage extends StatefulWidget {
  const PensionDocumentsPage({super.key});
  @override
  State<PensionDocumentsPage> createState() => _PensionDocumentsPageState();
}

class _PensionDocumentsPageState extends State<PensionDocumentsPage>
    with SingleTickerProviderStateMixin {
  static const _teal = Color(0xFF0C5C6C);
  static const _bg   = Color(0xFFF8F8F6);

  late TabController _tabController;
  bool _loading  = false;
  bool _uploading = false;

  List<Reference> _contrats = [];
  List<Reference> _factures = [];

  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadDocuments();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDocuments() async {
    setState(() => _loading = true);
    try {
      final uid = _uid;
      final results = await Future.wait([
        FirebaseStorage.instance.ref('contrats/$uid').listAll(),
        FirebaseStorage.instance.ref('factures/$uid').listAll(),
      ]).catchError((_) => <ListResult>[]);

      if (mounted && results.length == 2) {
        setState(() {
          _contrats = results[0].items;
          _factures = results[1].items;
        });
      }
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
      await FirebaseStorage.instance.ref('contrats/$_uid/$name').putFile(file);
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

  Future<void> _openDocument(Reference ref) async {
    try {
      final url = await ref.getDownloadURL();
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible d\'ouvrir: $e')));
      }
    }
  }

  Future<void> _deleteContrat(Reference ref) async {
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
      await ref.delete();
      await _loadDocuments();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur suppression: $e')));
      }
    }
  }

  Widget _buildDocItem(Reference ref, {required bool canDelete}) {
    final name = ref.name;
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
              onPressed: () => _openDocument(ref),
            ),
            if (canDelete)
              IconButton(
                icon: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade400),
                tooltip: 'Supprimer',
                onPressed: () => _deleteContrat(ref),
              ),
          ],
        ),
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

  Widget _buildFacturesTab() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _loadDocuments,
      child: _factures.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(32),
              children: [
                const SizedBox(height: 40),
                Center(child: Icon(Icons.receipt_long_outlined, size: 56, color: Colors.grey.shade300)),
                const SizedBox(height: 12),
                Center(
                  child: Text('Aucune facture générée',
                      style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500)),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    'Les factures générées depuis le registre apparaîtront automatiquement ici',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: 'Galey', fontSize: 12, color: Colors.grey.shade400),
                  ),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '${_factures.length} facture${_factures.length > 1 ? 's' : ''}',
                  style: TextStyle(
                      fontFamily: 'Galey', fontSize: 12,
                      color: Colors.grey.shade500, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                ..._factures.map((r) => _buildDocItem(r, canDelete: false)),
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
        bottom: TabBar(
          controller: _tabController,
          labelStyle: const TextStyle(fontFamily: 'Galey', fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontFamily: 'Galey'),
          labelColor: _teal,
          unselectedLabelColor: const Color(0xFF6F767B),
          indicatorColor: _teal,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: const [
            Tab(text: 'Contrats'),
            Tab(text: 'Factures'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildContratsTab(),
          _buildFacturesTab(),
        ],
      ),
    );
  }
}
