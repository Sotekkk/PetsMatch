import 'package:supabase_flutter/supabase_flutter.dart';

/// Flamme de discussion façon Snapchat : jours consécutifs où LES DEUX
/// participants d'une conversation 1:1 ont envoyé au moins un message.
/// Ne s'applique pas aux groupes (retourne null pour toute conversation
/// à plus de 2 participants).
class ConversationStreakService {
  ConversationStreakService._();
  static final ConversationStreakService instance = ConversationStreakService._();

  SupabaseClient get _supa => Supabase.instance.client;

  String _dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// À appeler après l'insertion d'un message. Met à jour la flamme de la
  /// conversation et retourne le nouveau compteur (null si non applicable,
  /// c-à-d groupe ou conversation à un seul participant).
  Future<int?> registerMessage({
    required String conversationId,
    required String senderUid,
    required List<String> participants,
  }) async {
    if (participants.toSet().length != 2) return null;
    try {
      final conv = await _supa
          .from('conversations')
          .select('msg_streak_count, msg_streak_last_date, msg_streak_today_date, msg_streak_today_senders')
          .eq('id', conversationId)
          .maybeSingle();
      if (conv == null) return null;

      final today = DateTime.now();
      final todayStr = _dateStr(today);
      var streak = (conv['msg_streak_count'] as num?)?.toInt() ?? 0;
      final lastDate = conv['msg_streak_last_date'] != null
          ? DateTime.tryParse(conv['msg_streak_last_date'].toString())
          : null;
      final todayDateStored = conv['msg_streak_today_date']?.toString();
      var todaySenders = <String>{
        ...((conv['msg_streak_today_senders'] as List?) ?? []).map((e) => e.toString()),
      };

      if (todayDateStored != todayStr) {
        // Nouveau jour : si plus d'un jour s'est écoulé depuis le dernier
        // incrément, la série est rompue (perte sèche, pas de dégradation).
        if (lastDate != null) {
          final lastDay = DateTime(lastDate.year, lastDate.month, lastDate.day);
          final todayDay = DateTime(today.year, today.month, today.day);
          if (todayDay.difference(lastDay).inDays > 1) streak = 0;
        }
        todaySenders = {};
      }

      todaySenders.add(senderUid);

      if (todaySenders.length >= 2 && lastDate != null && _dateStr(lastDate) == todayStr) {
        // Déjà incrémenté aujourd'hui, rien à faire de plus.
      } else if (todaySenders.length >= 2) {
        streak += 1;
      }

      await _supa.from('conversations').update({
        'msg_streak_count': streak,
        'msg_streak_last_date': todaySenders.length >= 2 ? todayStr : (lastDate != null ? _dateStr(lastDate) : null),
        'msg_streak_today_date': todayStr,
        'msg_streak_today_senders': todaySenders.toList(),
      }).eq('id', conversationId);

      return streak;
    } catch (_) {
      return null;
    }
  }
}
