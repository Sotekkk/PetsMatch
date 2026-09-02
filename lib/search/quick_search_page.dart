import 'package:flutter/material.dart';
import 'package:PetsMatch/search/feature_catalog.dart';

const _teal = Color(0xFF0C5C6C);
const _green = Color(0xFF6E9E57);

/// Bouton loupe à placer dans l'AppBar de l'accueil. Ouvre la recherche
/// rapide et exécute l'action choisie depuis le contexte de l'accueil
/// (stable, contrairement à celui de la page de recherche fermée).
class QuickSearchButton extends StatelessWidget {
  final Color? color;
  const QuickSearchButton({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Rechercher une fonctionnalité',
      icon: Icon(Icons.search, color: color ?? Colors.white),
      onPressed: () async {
        final action = await Navigator.push<QuickAction>(
          context,
          MaterialPageRoute(builder: (_) => const QuickSearchPage(), fullscreenDialog: true),
        );
        if (action != null && context.mounted) action.open(context);
      },
    );
  }
}

// ── Normalisation + scoring ──────────────────────────────────────────────────

const _accents = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a',
  'ç': 'c',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'î': 'i', 'ï': 'i', 'í': 'i',
  'ô': 'o', 'ö': 'o', 'ó': 'o', 'õ': 'o',
  'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
  'ñ': 'n', 'œ': 'oe', 'æ': 'ae',
};

String _norm(String s) {
  final buf = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    buf.write(_accents[ch] ?? ch);
  }
  return buf.toString().replaceAll(RegExp(r"[^a-z0-9 ]"), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var cur = List<int>.filled(b.length + 1, 0);
  for (var i = 0; i < a.length; i++) {
    cur[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final cost = a[i] == b[j] ? 0 : 1;
      cur[j + 1] = [cur[j] + 1, prev[j + 1] + 1, prev[j] + cost].reduce((x, y) => x < y ? x : y);
    }
    final tmp = prev; prev = cur; cur = tmp;
  }
  return prev[b.length];
}

/// Score d'une entrée pour une requête normalisée. 0 = non pertinent.
int _score(QuickAction a, String q, List<String> qTokens) {
  final label = _norm(a.label);
  final kws = a.keywords.map(_norm).toList();
  int best = 0;

  if (label == q) {
    best = 1000;
  } else if (label.startsWith(q)) {
    best = 600;
  } else if (label.contains(q)) {
    best = 420;
  }

  for (final k in kws) {
    if (k == q) {
      if (best < 380) best = 380;
    } else if (k.startsWith(q)) {
      if (best < 300) best = 300;
    } else if (k.contains(q)) {
      if (best < 220) best = 220;
    }
  }

  // Tous les mots de la requête présents quelque part (label + mots-clés)
  final hay = '$label ${kws.join(' ')}';
  if (qTokens.length > 1 && qTokens.every(hay.contains)) {
    best = best < 340 ? 340 : best;
  }

  // Tolérance aux fautes de frappe (par mot)
  if (best == 0 && q.length >= 4) {
    for (final word in hay.split(' ')) {
      if (word.length < 3) continue;
      final d = _levenshtein(q, word);
      if (d <= 2) { best = best < (120 - d * 30) ? (120 - d * 30) : best; }
    }
    for (final tok in qTokens) {
      if (tok.length < 4) continue;
      for (final word in hay.split(' ')) {
        if (word.length < 3) continue;
        if (_levenshtein(tok, word) <= 1) { best = best < 90 ? 90 : best; }
      }
    }
  }

  return best;
}

// ── Page ─────────────────────────────────────────────────────────────────────

class QuickSearchPage extends StatefulWidget {
  const QuickSearchPage({super.key});
  @override
  State<QuickSearchPage> createState() => _QuickSearchPageState();
}

class _QuickSearchPageState extends State<QuickSearchPage> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  late final List<QuickAction> _catalog;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _catalog = visibleQuickActions(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final qn = _norm(_q);
    final qTokens = qn.split(' ').where((t) => t.isNotEmpty).toList();

    List<QuickAction> results;
    Map<String, List<QuickAction>>? grouped;

    if (qn.isEmpty) {
      grouped = <String, List<QuickAction>>{};
      for (final a in _catalog) {
        grouped.putIfAbsent(a.group, () => []).add(a);
      }
      results = const [];
    } else {
      final scored = _catalog
          .map((a) => (a, _score(a, qn, qTokens)))
          .where((e) => e.$2 > 0)
          .toList()
        ..sort((x, y) => y.$2.compareTo(x.$2));
      results = scored.map((e) => e.$1).toList();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _teal),
          onPressed: () => Navigator.pop(context),
        ),
        title: TextField(
          controller: _ctrl,
          focusNode: _focus,
          onChanged: (v) => setState(() => _q = v),
          style: const TextStyle(fontFamily: 'Galey', fontSize: 15),
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Rechercher une fonctionnalité…',
            hintStyle: TextStyle(fontFamily: 'Galey', color: Colors.grey),
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_q.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.grey),
              onPressed: () { _ctrl.clear(); setState(() => _q = ''); },
            ),
        ],
      ),
      body: qn.isEmpty
          ? _GroupedList(grouped: grouped!, onTap: (a) => Navigator.pop(context, a))
          : results.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('Aucune fonctionnalité pour « $_q »',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: 'Galey', color: Colors.grey.shade500, fontSize: 15)),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
                  itemCount: results.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 60),
                  itemBuilder: (_, i) => _ResultTile(
                    action: results[i],
                    query: qn,
                    onTap: () => Navigator.pop(context, results[i]),
                  ),
                ),
    );
  }
}

class _GroupedList extends StatelessWidget {
  final Map<String, List<QuickAction>> grouped;
  final void Function(QuickAction) onTap;
  const _GroupedList({required this.grouped, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final groups = grouped.keys.toList();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: groups.length,
      itemBuilder: (_, i) {
        final g = groups[i];
        final items = grouped[g]!;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
            child: Text(g.toUpperCase(),
                style: TextStyle(
                    fontFamily: 'Galey', fontWeight: FontWeight.w700, fontSize: 11,
                    letterSpacing: 0.6, color: Colors.grey.shade500)),
          ),
          ...items.map((a) => _ResultTile(action: a, query: '', onTap: () => onTap(a))),
        ]);
      },
    );
  }
}

class _ResultTile extends StatelessWidget {
  final QuickAction action;
  final String query;
  final VoidCallback onTap;
  const _ResultTile({required this.action, required this.query, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: (action.isAction ? _green : _teal).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(action.icon, size: 20, color: action.isAction ? _green : _teal),
      ),
      title: Text(action.label,
          style: const TextStyle(fontFamily: 'Galey', fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1F2A2E))),
      subtitle: Text(action.group,
          style: TextStyle(fontFamily: 'Galey', fontSize: 11, color: Colors.grey.shade500)),
      trailing: Icon(action.isAction ? Icons.add : Icons.chevron_right, size: 18, color: Colors.grey.shade400),
      dense: true,
    );
  }
}
