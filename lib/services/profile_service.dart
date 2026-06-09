import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileService {
  static final _supa = Supabase.instance.client;

  static Future<List<Map<String, dynamic>>> loadProfiles(String uid) async {
    final rows = await _supa
        .from('user_profiles')
        .select()
        .eq('uid', uid)
        .order('created_at');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  static Future<void> upsertProfile(Map<String, dynamic> data) async {
    await _supa
        .from('user_profiles')
        .upsert(data, onConflict: 'uid,profile_type');
  }

  static Future<void> deleteProfile(String id) async {
    await _supa.from('user_profiles').delete().eq('id', id);
  }
}
