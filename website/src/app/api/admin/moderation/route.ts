import { NextRequest, NextResponse } from 'next/server';
import { supabaseAdmin, requireAdmin } from '../_lib/guard';

// Modération admin (ex-onglets de l'appli) : influenceurs, pubs des stories,
// lieux pet-friendly. Jeton Firebase vérifié + statut admin, puis clé
// service : is_influencer est une colonne réservée (trigger), story_ads n'a
// aucune policy d'écriture, petfriendly_places n'est modifiable que par son
// pro.

// GET /api/admin/moderation?type=influenceurs&statut=pending|approved|refused
//                          ?type=pubs
//                          ?type=lieux
export async function GET(req: NextRequest) {
  const auth = await requireAdmin(req);
  if (auth instanceof NextResponse) return auth;
  const { searchParams } = new URL(req.url);
  const type = searchParams.get('type');

  if (type === 'influenceurs') {
    const statut = searchParams.get('statut') ?? 'pending';
    const { data, error } = await supabaseAdmin.from('influencer_requests')
      .select('*').eq('statut', statut).order('created_at', { ascending: false });
    if (error) return NextResponse.json({ error: error.message }, { status: 500 });
    return NextResponse.json({ items: data ?? [] });
  }
  if (type === 'pubs') {
    const { data, error } = await supabaseAdmin.from('story_ads')
      .select('*').order('created_at', { ascending: false });
    if (error) return NextResponse.json({ error: error.message }, { status: 500 });
    return NextResponse.json({ items: data ?? [] });
  }
  if (type === 'lieux') {
    const [enAttente, publies] = await Promise.all([
      supabaseAdmin.from('petfriendly_places').select('*')
        .eq('statut', 'en_attente_validation').order('created_at', { ascending: true }),
      supabaseAdmin.from('petfriendly_places').select('*')
        .in('statut', ['actif', 'suspendu']).order('created_at', { ascending: false }).limit(100),
    ]);
    const err = enAttente.error ?? publies.error;
    if (err) return NextResponse.json({ error: err.message }, { status: 500 });
    return NextResponse.json({ enAttente: enAttente.data ?? [], publies: publies.data ?? [] });
  }
  return NextResponse.json({ error: 'type inconnu' }, { status: 400 });
}

const CHAMPS_PUB = ['annonceur_nom', 'annonceur_logo_url', 'media_url', 'media_type', 'duree_secondes',
  'cta_label', 'lien_url', 'actif', 'date_debut', 'date_fin', 'poids'] as const;

// POST /api/admin/moderation  { action, ... }
export async function POST(req: NextRequest) {
  const auth = await requireAdmin(req);
  if (auth instanceof NextResponse) return auth;
  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch { /* corps invalide */ }
  const action = String(body.action ?? '');
  const id = body.id ? String(body.id) : '';

  try {
    switch (action) {
      // ── Influenceurs ──────────────────────────────────────────────────
      case 'influenceur_valider':
      case 'influenceur_refuser':
      case 'influenceur_revoquer': {
        const { data: demande } = await supabaseAdmin.from('influencer_requests')
          .select('uid').eq('id', id).maybeSingle();
        if (!demande) return NextResponse.json({ error: 'Demande introuvable' }, { status: 404 });
        const statut = action === 'influenceur_valider' ? 'approved' : 'refused';
        await supabaseAdmin.from('influencer_requests').update({ statut }).eq('id', id);
        if (action !== 'influenceur_refuser') {
          await supabaseAdmin.from('user_profiles')
            .update({ is_influencer: action === 'influenceur_valider' }).eq('uid', demande.uid);
        }
        // Prévenir le demandeur (cloche appli + site), sur son profil
        // particulier — le badge vit sur Pets Social. Best-effort.
        try {
          const { data: part } = await supabaseAdmin.from('user_profiles')
            .select('id').eq('uid', demande.uid).eq('profile_type', 'particulier').limit(1).maybeSingle();
          const msg = {
            influenceur_valider:  { type: 'influenceur_approuve', title: '⭐ Badge Influenceur accordé',
              body: 'Félicitations ! Votre badge apparaît désormais sur votre profil Pets Social.' },
            influenceur_refuser:  { type: 'influenceur_refuse', title: 'Demande de badge Influenceur refusée',
              body: "Votre demande n'a pas été retenue pour le moment. Vous pourrez en refaire une plus tard." },
            influenceur_revoquer: { type: 'influenceur_revoque', title: 'Badge Influenceur retiré',
              body: 'Votre badge Influenceur a été retiré de votre profil.' },
          }[action];
          await supabaseAdmin.from('notifications').insert({
            uid: demande.uid, type: msg.type, title: msg.title, body: msg.body,
            ...(part?.id ? { profile_id: part.id } : {}),
            data: { demandeId: id }, read: false,
          });
        } catch { /* notif best-effort */ }
        return NextResponse.json({ ok: true });
      }

      // ── Pubs des stories ──────────────────────────────────────────────
      case 'pub_enregistrer': {
        const src = (body.data ?? {}) as Record<string, unknown>;
        const data = Object.fromEntries(CHAMPS_PUB.filter((k) => k in src).map((k) => [k, src[k]]));
        if (!data.annonceur_nom || !data.media_url) {
          return NextResponse.json({ error: 'Nom de l\'annonceur et média requis' }, { status: 400 });
        }
        const r = id
          ? await supabaseAdmin.from('story_ads').update(data).eq('id', id)
          : await supabaseAdmin.from('story_ads').insert(data);
        if (r.error) throw r.error;
        return NextResponse.json({ ok: true });
      }
      case 'pub_activer': {
        const r = await supabaseAdmin.from('story_ads').update({ actif: body.actif === true }).eq('id', id);
        if (r.error) throw r.error;
        return NextResponse.json({ ok: true });
      }
      case 'pub_supprimer': {
        const r = await supabaseAdmin.from('story_ads').delete().eq('id', id);
        if (r.error) throw r.error;
        return NextResponse.json({ ok: true });
      }

      // ── Lieux pet-friendly ────────────────────────────────────────────
      case 'lieu_valider': {
        const r = await supabaseAdmin.from('petfriendly_places').update({
          statut: 'actif', valide_par: auth.uid, valide_at: new Date().toISOString(),
        }).eq('id', id);
        if (r.error) throw r.error;
        return NextResponse.json({ ok: true });
      }
      case 'lieu_suspendre':
      case 'lieu_reactiver': {
        const r = await supabaseAdmin.from('petfriendly_places')
          .update({ statut: action === 'lieu_suspendre' ? 'suspendu' : 'actif' }).eq('id', id);
        if (r.error) throw r.error;
        return NextResponse.json({ ok: true });
      }
    }
    return NextResponse.json({ error: 'action inconnue' }, { status: 400 });
  } catch (e) {
    return NextResponse.json({ error: (e as Error).message }, { status: 500 });
  }
}
