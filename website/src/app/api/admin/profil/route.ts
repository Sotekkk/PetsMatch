import { NextRequest, NextResponse } from 'next/server';
import { supabaseAdmin, checkAdmin } from '../_lib/guard';

const IDENTITY_COLS = [
  'id', 'uid', 'is_main', 'profile_type', 'cat_pro', 'statut_pro', 'is_validate',
  'nom', 'firstname', 'lastname', 'profession_pro', 'profile_label',
  'avatar_url', 'profile_picture_url_pro', 'banner_url',
  'email_contact', 'phone', 'phone_number', 'telephone', 'site_web', 'instagram', 'facebook',
  'adresse', 'rue', 'ville', 'code_postal', 'pays', 'departement', 'region',
  'siret', 'forme_juridique_pro', 'numero_tva', 'regime_tva_pro', 'rcs_pro', 'rm_pro',
  'capital_social_pro', 'iban_pro', 'bic_pro', 'rna',
  'acaced', 'acaced_numero', 'acaced_date_obtention', 'acaced_date_renewal',
  'kbis_url', 'acaced_doc_url', 'statuts_url', 'diplome_url', 'agrement_prefectoral',
  'numero_ordre', 'numero_etablissement', 'especes_acceptees', 'especes_elevees',
  'certifications', 'rayon_intervention', 'created_at',
  'plan_code', 'plan_until', 'is_premium', 'verification_status', 'rejection_reason',
].join(', ');

// GET /api/admin/profil?uid=<admin>&targetUid=<x>&profileId=<y>
export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url);
  if (!(await checkAdmin(searchParams.get('uid')))) {
    return NextResponse.json({ error: 'Non autorisé' }, { status: 403 });
  }
  const targetUid = searchParams.get('targetUid');
  const profileId = searchParams.get('profileId');
  if (!targetUid && !profileId) {
    return NextResponse.json({ error: 'targetUid ou profileId requis' }, { status: 400 });
  }

  try {
    let uid = targetUid;
    if (!uid && profileId) {
      const { data } = await supabaseAdmin.from('user_profiles').select('uid').eq('id', profileId).maybeSingle();
      uid = (data?.uid as string) ?? null;
    }
    if (!uid) return NextResponse.json({ error: 'Compte introuvable' }, { status: 404 });

    const [profilesRes, aboRes, plansRes, userRes] = await Promise.all([
      supabaseAdmin.from('user_profiles').select(IDENTITY_COLS)
        .eq('uid', uid).order('is_main', { ascending: false }),
      supabaseAdmin.from('abonnements')
        .select('id, profil_type, profile_id, plan_code, statut, periodicite, date_debut, date_fin, stripe_subscription_id, created_at, updated_at')
        .eq('uid', uid).order('created_at', { ascending: false }),
      supabaseAdmin.from('plans_tarifaires')
        .select('profil_type, plan_code, label, prix_mensuel, prix_annuel, max_annonces, duree_annonce_jours, actif'),
      supabaseAdmin.from('users').select('uid, email, is_premium, plan_code, last_active, created_at, is_admin').eq('uid', uid).maybeSingle(),
    ]);

    return NextResponse.json({
      uid,
      user: userRes.data ?? null,
      profiles: profilesRes.data ?? [],
      abonnements: aboRes.data ?? [],
      plans: plansRes.data ?? [],
    });
  } catch (err) {
    console.error('[admin/profil]', err);
    return NextResponse.json({ error: 'Erreur serveur' }, { status: 500 });
  }
}
