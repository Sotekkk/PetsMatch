import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// @mentions et #hashtags — Pets Social, Forums, Groupes.
///
/// Une mention est stockée directement dans le texte sous la forme
/// `@[Nom affiché](profileId)` (comme un lien markdown) : pas de migration,
/// pas d'ambiguïté à la lecture (le profil visé est explicite), fonctionne
/// immédiatement partout où le texte est déjà stocké (contenu/texte).
/// Un hashtag est simplement `#mot` dans le texte brut.

const mentionHashtagColor = Color(0xFF1565C0);

/// Cherche des profils "mentionnables" (nom/pseudo) — même colonnes que
/// l'identité Pets Social (kSocialAuthorCols) pour un rendu cohérent.
Future<List<Map<String, dynamic>>> searchMentionableProfiles(String query, {String? excludeUid}) async {
  final q = query.trim();
  if (q.isEmpty) return [];
  final supa = Supabase.instance.client;
  try {
    var builder = supa.from('user_profiles')
        .select('id, uid, firstname, lastname, nom, profile_type, avatar_url, profile_picture_url_pro, social_pseudo')
        .or('firstname.ilike.%$q%,lastname.ilike.%$q%,nom.ilike.%$q%,social_pseudo.ilike.%$q%');
    if (excludeUid != null && excludeUid.isNotEmpty) builder = builder.neq('uid', excludeUid);
    final rows = await builder.limit(6);
    return List<Map<String, dynamic>>.from(rows as List);
  } catch (_) {
    return [];
  }
}

final RegExp _mentionHashtagRegExp = RegExp(r'@\[([^\]]+)\]\(([^)]+)\)|#([\p{L}0-9_]+)', unicode: true);
final RegExp _mentionOnlyRegExp = RegExp(r'@\[([^\]]+)\]\(([^)]+)\)');

/// Notifie chaque profil @mentionné dans [text] (jamais soi-même) —
/// fire-and-forget, n'échoue jamais la publication elle-même. Réutilise la
/// table `notifications` déjà utilisée pour le reste de l'appli (bulle du
/// menu du bas, pas le cœur Pets Social qui lui est calculé dynamiquement).
Future<void> notifyMentions({
  required String text,
  required String actorUid,
  required String notifType,
  required String title,
  required String body,
  required Map<String, dynamic> data,
}) async {
  final profileIds = <String>{
    for (final m in _mentionOnlyRegExp.allMatches(text)) m.group(2)!,
  };
  if (profileIds.isEmpty) return;
  try {
    final supa = Supabase.instance.client;
    final rows = await supa.from('user_profiles').select('id, uid').inFilter('id', profileIds.toList());
    for (final r in rows as List) {
      final targetUid = r['uid'] as String?;
      final targetPid = r['id'] as String?;
      if (targetUid == null || targetUid == actorUid) continue;
      await supa.from('notifications').insert({
        'uid': targetUid,
        'type': notifType,
        'title': title,
        'body': body,
        if (targetPid != null) 'profile_id': targetPid,
        'data': data,
        'read': false,
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  } catch (_) {}
}

/// Texte enrichi : @mentions (tappables vers le profil) et #hashtags
/// (tappables vers une recherche). Gère le cycle de vie des
/// TapGestureRecognizer (StatefulWidget, pas de fuite mémoire).
class MentionHashtagText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final int? maxLines;
  final TextOverflow? overflow;
  final void Function(String profileId)? onMentionTap;
  final void Function(String hashtag)? onHashtagTap;
  /// Les #hashtags sont une fonctionnalité Pets Social uniquement (demande
  /// explicite) — mettre à false dans les forums/groupes pour les laisser en
  /// texte brut sans mise en forme spéciale.
  final bool enableHashtags;

  const MentionHashtagText({
    super.key,
    required this.text,
    required this.style,
    this.maxLines,
    this.overflow,
    this.onMentionTap,
    this.onHashtagTap,
    this.enableHashtags = true,
  });

  @override
  State<MentionHashtagText> createState() => _MentionHashtagTextState();
}

class _MentionHashtagTextState extends State<MentionHashtagText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void didUpdateWidget(covariant MentionHashtagText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _disposeRecognizers();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final spans = <InlineSpan>[];
    int last = 0;
    for (final m in _mentionHashtagRegExp.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      if (m.group(1) != null) {
        final name = m.group(1)!;
        final pid = m.group(2)!;
        final recognizer = TapGestureRecognizer()..onTap = () => widget.onMentionTap?.call(pid);
        _recognizers.add(recognizer);
        spans.add(TextSpan(
          text: '@$name',
          style: widget.style.copyWith(color: mentionHashtagColor, fontWeight: FontWeight.w700),
          recognizer: recognizer,
        ));
      } else if (m.group(3) != null) {
        final tag = m.group(3)!;
        if (!widget.enableHashtags) {
          spans.add(TextSpan(text: '#$tag'));
          last = m.end;
          continue;
        }
        final recognizer = TapGestureRecognizer()..onTap = () => widget.onHashtagTap?.call(tag);
        _recognizers.add(recognizer);
        spans.add(TextSpan(
          text: '#$tag',
          style: widget.style.copyWith(color: mentionHashtagColor, fontWeight: FontWeight.w700),
          recognizer: recognizer,
        ));
      }
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(
      TextSpan(style: widget.style, children: spans),
      maxLines: widget.maxLines,
      overflow: widget.overflow ?? TextOverflow.clip,
    );
  }
}

/// Suggestion affichée pendant la frappe d'une mention.
class MentionSuggestion {
  final String profileId;
  final String displayName;
  final String? photoUrl;
  final String? typeLabel;
  const MentionSuggestion({required this.profileId, required this.displayName, this.photoUrl, this.typeLabel});
}

/// Détecte une « @requête » active autour du curseur d'un [TextEditingController]
/// et propose de l'insérer sous la forme `@[Nom](profileId) `. S'attache/se
/// détache elle-même du controller — pas de listener à gérer côté appelant
/// au-delà de `dispose()`.
class MentionController {
  final TextEditingController textController;
  final void Function(List<MentionSuggestion>? suggestions) onSuggestionsChanged;
  final String? excludeUid;

  String? _activeQuery;
  int? _pendingAtIndex;
  int _searchToken = 0;

  MentionController({required this.textController, required this.onSuggestionsChanged, this.excludeUid}) {
    textController.addListener(_onChanged);
  }

  void dispose() => textController.removeListener(_onChanged);

  void _onChanged() {
    final text = textController.text;
    final sel = textController.selection;
    if (!sel.isValid || sel.baseOffset != sel.extentOffset) {
      _clear();
      return;
    }
    final cursor = sel.baseOffset;
    if (cursor <= 0) {
      _clear();
      return;
    }
    var i = cursor - 1;
    while (i >= 0 && text[i] != '@' && text[i] != '\n' && text[i] != ' ') {
      i--;
    }
    if (i < 0 || text[i] != '@') {
      _clear();
      return;
    }
    if (i > 0 && text[i - 1] != ' ' && text[i - 1] != '\n') {
      _clear();
      return;
    }
    final query = text.substring(i + 1, cursor);
    if (query.contains('[') || query.contains(']') || query.contains('(')) {
      _clear();
      return;
    }
    _activeQuery = query;
    _pendingAtIndex = i;
    if (query.isEmpty) {
      onSuggestionsChanged(const []);
      return;
    }
    _search(query);
  }

  void _clear() {
    if (_activeQuery == null) return;
    _activeQuery = null;
    _pendingAtIndex = null;
    onSuggestionsChanged(null);
  }

  Future<void> _search(String query) async {
    final token = ++_searchToken;
    final results = await searchMentionableProfiles(query, excludeUid: excludeUid);
    if (token != _searchToken || _activeQuery != query) return; // frappe plus récente entre-temps
    onSuggestionsChanged(results.map((p) {
      final isPro = (p['profile_type'] as String?)?.isNotEmpty == true && p['profile_type'] != 'particulier';
      final pseudo = (p['social_pseudo'] as String? ?? '').trim();
      final struct = (p['nom'] as String? ?? '').trim();
      final person = '${p['firstname'] ?? ''} ${p['lastname'] ?? ''}'.trim();
      final name = pseudo.isNotEmpty ? pseudo : (isPro && struct.isNotEmpty ? struct : (person.isNotEmpty ? person : (struct.isNotEmpty ? struct : 'Membre')));
      final photo = isPro ? ((p['profile_picture_url_pro'] as String?) ?? (p['avatar_url'] as String?)) : (p['avatar_url'] as String?);
      return MentionSuggestion(profileId: p['id'] as String, displayName: name, photoUrl: photo);
    }).toList());
  }

  /// Insère `@[Nom](profileId) ` à la place de la « @requête » en cours.
  void select(MentionSuggestion s) {
    final atIndex = _pendingAtIndex;
    if (atIndex == null) return;
    final text = textController.text;
    final cursor = textController.selection.baseOffset;
    final before = text.substring(0, atIndex);
    final after = cursor >= 0 && cursor <= text.length ? text.substring(cursor) : '';
    final insert = '@[${s.displayName}](${s.profileId}) ';
    textController.value = TextEditingValue(
      text: '$before$insert$after',
      selection: TextSelection.collapsed(offset: before.length + insert.length),
    );
    _clear();
  }
}

/// Liste horizontale de suggestions affichée sous/au-dessus du champ de texte
/// pendant la frappe d'une mention.
class MentionSuggestionsBar extends StatelessWidget {
  final List<MentionSuggestion> suggestions;
  final void Function(MentionSuggestion) onSelect;
  const MentionSuggestionsBar({super.key, required this.suggestions, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text('Tapez un nom pour mentionner quelqu\'un…',
            style: TextStyle(fontFamily: 'Galey', fontSize: 12, color: Colors.grey)),
      );
    }
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final s = suggestions[i];
          return GestureDetector(
            onTap: () => onSelect(s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: mentionHashtagColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: mentionHashtagColor.withValues(alpha: 0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                CircleAvatar(
                  radius: 11,
                  backgroundColor: mentionHashtagColor.withValues(alpha: 0.15),
                  backgroundImage: (s.photoUrl?.isNotEmpty ?? false) ? NetworkImage(s.photoUrl!) : null,
                  child: (s.photoUrl?.isNotEmpty ?? false) ? null : const Icon(Icons.person, size: 12, color: mentionHashtagColor),
                ),
                const SizedBox(width: 6),
                Text(s.displayName,
                    style: const TextStyle(fontFamily: 'Galey', fontSize: 12, fontWeight: FontWeight.w600, color: mentionHashtagColor)),
              ]),
            ),
          );
        },
      ),
    );
  }
}
