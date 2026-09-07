import { NextRequest, NextResponse } from 'next/server';
import { supabaseAdmin, checkAdmin } from '../_lib/guard';

// POST /api/admin/abonnement
// { uid: <admin>, targetUid, profileId?, profil_type, plan_code,
//   statut?='actif', periodicite?='mensuel', date_fin?=null }
//
// Reproduit la logique de api/stripe/activate SANS Stripe : annule les
// abonnements actifs du couple (targetUid, profil_type[, profileId]), insère la
// nouvelle ligne (stripe_subscription_id = null → abonnement manuel admin),
// puis resynchronise user_profiles + users.
export async function POST(req: NextRequest) {
  try {
    const body = await req.json() as {
      uid?: string; targetUid?: string; profileId?: string | null;
      profil_type?: string; plan_code?: string;
      statut?: string; periodicite?: string; date_fin?: string | null;
    };
    if (!(await checkAdmin(body.uid))) {
      return NextResponse.json({ error: 'Non autorisé' }, { status: 403 });
    }
    const { targetUid, profil_type: profilType, plan_code: planCode } = body;
    const profileId = body.profileId ?? null;
    const statut = body.statut ?? 'actif';
    const periodicite = body.periodicite ?? 'mensuel';
    const dateFin = body.date_fin ?? null;
    if (!targetUid || !profilType || !planCode) {
      return NextResponse.json({ error: 'targetUid, profil_type et plan_code requis' }, { status: 400 });
    }

    const nowIso = new Date().toISOString();

    // 1. Annuler les abonnements actifs de ce couple.
    let cancelQ = supabaseAdmin.from('abonnements')
      .update({ statut: 'annule', updated_at: nowIso })
      .eq('uid', targetUid).eq('statut', 'actif').eq('profil_type', profilType);
    if (profileId) cancelQ = cancelQ.eq('profile_id', profileId);
    await cancelQ;

    // 2. Insérer la nouvelle ligne (manuelle → pas de stripe_subscription_id).
    const { data: inserted, error: insErr } = await supabaseAdmin.from('abonnements').insert({
      uid: targetUid,
      profile_id: profileId,
      profil_type: profilType,
      plan_code: planCode,
      periodicite,
      statut,
      stripe_subscription_id: null,
      stripe_customer_id: null,
      date_debut: nowIso,
      date_fin: dateFin,
      created_at: nowIso,
      updated_at: nowIso,
    }).select('id, plan_code, statut, date_fin, profil_type, profile_id').single();
    if (insErr) return NextResponse.json({ error: insErr.message }, { status: 500 });

    // 3. Resync user_profiles.
    const isActive = statut === 'actif';
    const profilePatch = {
      plan_code: isActive ? planCode : 'free',
      is_premium: isActive && planCode === 'premium',
      plan_until: isActive ? dateFin : null,
    };
    if (profileId) {
      await supabaseAdmin.from('user_profiles').update(profilePatch).eq('id', profileId);
    } else {
      await supabaseAdmin.from('user_profiles').update(profilePatch)
        .eq('uid', targetUid).eq('profile_type', profilType);
    }

    // 4. Sync users (levier legacy encore lu à certains endroits).
    await supabaseAdmin.from('users').update({
      plan_code: profilePatch.plan_code,
      is_premium: profilePatch.is_premium,
    }).eq('uid', targetUid);

    // État courant renvoyé pour rafraîchir l'UI.
    const { data: abonnements } = await supabaseAdmin.from('abonnements')
      .select('id, profil_type, profile_id, plan_code, statut, periodicite, date_debut, date_fin, stripe_subscription_id, created_at')
      .eq('uid', targetUid).order('created_at', { ascending: false });

    return NextResponse.json({ ok: true, inserted, abonnements: abonnements ?? [] });
  } catch (err) {
    console.error('[admin/abonnement]', err);
    return NextResponse.json({ error: 'Erreur serveur' }, { status: 500 });
  }
}
