import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _tealC = Color(0xFF00ACC1);

const _kCategories = [
  _CatInfo('Santé', '🏥', 'sante'),
  _CatInfo('Alimentation', '🍖', 'alimentation'),
  _CatInfo('Éducation', '🎓', 'education'),
  _CatInfo('Élevage', '🐣', 'elevage'),
  _CatInfo('Bien-être', '💆', 'bien_etre'),
  _CatInfo('Général', '💬', 'general'),
];

class _CatInfo {
  final String label;
  final String emoji;
  final String slug;
  const _CatInfo(this.label, this.emoji, this.slug);
}

// ─────────────────────────────────────────────────────────────────────────────
// Page principale — liste des catégories
// ─────────────────────────────────────────────────────────────────────────────

class ForumPage extends StatelessWidget {
  const ForumPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _tealC,
        title: const Text('Forum communauté',
            style: TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        itemCount: _kCategories.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final cat = _kCategories[i];
          return GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => _ForumCategorieePage(cat: cat)),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(children: [
                  Text(cat.emoji, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(cat.label,
                        style: const TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: Color(0xFF1E2025))),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded,
                      size: 14, color: Colors.grey),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page catégorie — liste des sujets
// ─────────────────────────────────────────────────────────────────────────────

class _ForumCategorieePage extends StatefulWidget {
  final _CatInfo cat;
  const _ForumCategorieePage({required this.cat});

  @override
  State<_ForumCategorieePage> createState() => _ForumCategorieePageState();
}

class _ForumCategorieePageState extends State<_ForumCategorieePage> {
  final _supa = Supabase.instance.client;
  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  List<Map<String, dynamic>> _sujets = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _supa
          .from('forum_sujets')
          .select()
          .eq('categorie_slug', widget.cat.slug)
          .order('epingle', ascending: false)
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _sujets = List<Map<String, dynamic>>.from(data);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreation() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreerSujetSheet(categorieSlug: widget.cat.slug),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _tealC,
        title: Text('${widget.cat.emoji} ${widget.cat.label}',
            style: const TextStyle(
                fontFamily: 'Galey', fontWeight: FontWeight.w700, color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      floatingActionButton: _uid.isNotEmpty
          ? FloatingActionButton(
              backgroundColor: _tealC,
              onPressed: _openCreation,
              child: const Icon(Icons.edit_outlined, color: Colors.white),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _tealC))
          : _sujets.isEmpty
              ? _empty()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: _tealC,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: _sujets.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _SujetTile(
                      sujet: _sujets[i],
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => _ForumSujetPage(sujet: _sujets[i])),
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _empty() => const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.forum_outlined, size: 72, color: Color(0xFFCCCCCC)),
          SizedBox(height: 16),
          Text('Aucun sujet pour l\'instant',
              style: TextStyle(
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: Color(0xFFAAAAAA))),
          SizedBox(height: 8),
          Text('Lancez la discussion !',
              style: TextStyle(fontFamily: 'Galey', fontSize: 13, color: Colors.grey)),
        ]),
      );
}

// ─── Tile sujet ───────────────────────────────────────────────────────────────

class _SujetTile extends StatelessWidget {
  final Map<String, dynamic> sujet;
  final VoidCallback onTap;

  const _SujetTile({required this.sujet, required this.onTap});

  static String _fmtDate(String iso) {
    try {
      return DateFormat('dd/MM/yyyy').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final titre = sujet['titre']?.toString() ?? '';
    final contenu = sujet['contenu']?.toString() ?? '';
    final createdAt = sujet['created_at']?.toString() ?? '';
    final epingle = sujet['epingle'] == true;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: epingle ? Border.all(color: _tealC.withValues(alpha: 0.4)) : null,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 1))
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (epingle) ...[
                const Icon(Icons.push_pin, size: 13, color: _tealC),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(titre,
                    style: const TextStyle(
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Color(0xFF1E2025))),
              ),
              Text(_fmtDate(createdAt),
                  style: const TextStyle(
                      fontFamily: 'Galey', fontSize: 11, color: Colors.grey)),
            ]),
            if (contenu.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(contenu,
                  style: const TextStyle(
                      fontFamily: 'Galey', fontSize: 12, color: Color(0xFF6F767B)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page sujet — réponses
// ─────────────────────────────────────────────────────────────────────────────

class _ForumSujetPage extends StatefulWidget {
  final Map<String, dynamic> sujet;
  const _ForumSujetPage({required this.sujet});

  @override
  State<_ForumSujetPage> createState() => _ForumSujetPageState();
}

class _ForumSujetPageState extends State<_ForumSujetPage> {
  final _supa = Supabase.instance.client;
  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  List<Map<String, dynamic>> _reponses = [];
  bool _loading = true;
  String _newReponse = '';
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadReponses();
  }

  Future<void> _loadReponses() async {
    setState(() => _loading = true);
    try {
      final data = await _supa
          .from('forum_reponses')
          .select()
          .eq('sujet_id', widget.sujet['id'])
          .order('created_at');
      if (mounted) {
        setState(() {
          _reponses = List<Map<String, dynamic>>.from(data);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _envoyer() async {
    final texte = _newReponse.trim();
    if (texte.isEmpty || _uid.isEmpty) return;
    setState(() => _sending = true);
    try {
      final inserted = await _supa.from('forum_reponses').insert({
        'sujet_id': widget.sujet['id'],
        'auteur_uid': _uid,
        'contenu': texte,
        'created_at': DateTime.now().toIso8601String(),
      }).select().single();
      if (mounted) {
        setState(() {
          _reponses.add(Map<String, dynamic>.from(inserted));
          _newReponse = '';
          _sending = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titre = widget.sujet['titre']?.toString() ?? '';
    final contenu = widget.sujet['contenu']?.toString() ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: _tealC,
        title: Text(titre,
            style: const TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w700,
                color: Colors.white,
                fontSize: 15),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _tealC))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  itemCount: _reponses.length + 1,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _tealC.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _tealC.withValues(alpha: 0.2)),
                        ),
                        child: Text(contenu,
                            style: const TextStyle(
                                fontFamily: 'Galey',
                                fontSize: 14,
                                color: Color(0xFF1E2025))),
                      );
                    }
                    final r = _reponses[i - 1];
                    return _ReponseCard(reponse: r);
                  },
                ),
        ),
        if (_uid.isNotEmpty)
          Container(
            color: Colors.white,
            padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 10,
                bottom: MediaQuery.of(context).padding.bottom + 10),
            child: Row(children: [
              Expanded(
                child: TextFormField(
                  initialValue: _newReponse,
                  decoration: InputDecoration(
                    hintText: 'Votre réponse…',
                    hintStyle:
                        const TextStyle(fontFamily: 'Galey', color: Colors.grey),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Colors.grey.shade300)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: _tealC, width: 1.5)),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    filled: true,
                    fillColor: const Color(0xFFF8F8F8),
                  ),
                  maxLines: null,
                  onChanged: (v) => _newReponse = v,
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _sending ? null : _envoyer,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                      color: _tealC, shape: BoxShape.circle),
                  child: _sending
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.send_rounded,
                          color: Colors.white, size: 20),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

// ─── Réponse card ─────────────────────────────────────────────────────────────

class _ReponseCard extends StatelessWidget {
  final Map<String, dynamic> reponse;
  const _ReponseCard({required this.reponse});

  static String _fmtDate(String iso) {
    try {
      return DateFormat('dd/MM · HH:mm').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final contenu = reponse['contenu']?.toString() ?? '';
    final auteur = reponse['auteur_uid']?.toString() ?? '';
    final date = reponse['created_at']?.toString() ?? '';
    final isMe = auteur == (FirebaseAuth.instance.currentUser?.uid ?? '');

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFFE0F7FA) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, 1))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(contenu,
              style: const TextStyle(fontFamily: 'Galey', fontSize: 14, color: Color(0xFF1E2025))),
          const SizedBox(height: 4),
          Text(_fmtDate(date),
              style: const TextStyle(fontFamily: 'Galey', fontSize: 10, color: Colors.grey)),
        ]),
      ),
    );
  }
}

// ─── Sheet créer sujet ────────────────────────────────────────────────────────

class _CreerSujetSheet extends StatefulWidget {
  final String categorieSlug;
  const _CreerSujetSheet({required this.categorieSlug});

  @override
  State<_CreerSujetSheet> createState() => _CreerSujetSheetState();
}

class _CreerSujetSheetState extends State<_CreerSujetSheet> {
  final _formKey = GlobalKey<FormState>();
  final _supa = Supabase.instance.client;
  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  String _titre = '';
  String _contenu = '';
  bool _saving = false;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    setState(() => _saving = true);
    try {
      await _supa.from('forum_sujets').insert({
        'categorie_slug': widget.categorieSlug,
        'auteur_uid': _uid,
        'titre': _titre,
        'contenu': _contenu,
        'created_at': DateTime.now().toIso8601String(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 28),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Row(children: [
                  const Expanded(
                      child: Text('Nouveau sujet',
                          style: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w700,
                              fontSize: 18))),
                  IconButton(
                      icon: const Icon(Icons.close, size: 22, color: Colors.grey),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints()),
                ]),
                const SizedBox(height: 20),

                _lbl('Titre *'),
                TextFormField(
                  decoration: _dec('Titre de votre question ou discussion'),
                  validator: (v) => (v?.trim().isEmpty ?? true) ? 'Obligatoire' : null,
                  onSaved: (v) => _titre = v?.trim() ?? '',
                ),
                const SizedBox(height: 12),

                _lbl('Contenu *'),
                TextFormField(
                  decoration: _dec('Décrivez votre sujet en détail…'),
                  maxLines: 5,
                  validator: (v) => (v?.trim().isEmpty ?? true) ? 'Obligatoire' : null,
                  onSaved: (v) => _contenu = v?.trim() ?? '',
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                        backgroundColor: _tealC,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Publier',
                            style: TextStyle(
                                fontFamily: 'Galey',
                                fontWeight: FontWeight.w700,
                                fontSize: 16)),
                  ),
                ),
              ]),
        ),
      ),
    );
  }

  Widget _lbl(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: const TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Color(0xFF6F767B))),
      );

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontFamily: 'Galey', color: Colors.grey),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _tealC, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        filled: true,
        fillColor: const Color(0xFFF8F8F8),
      );
}
