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
    // Files de modération des lieux pet-friendly (communauté + établissements).
    const [enAttente, aCorriger, publies, corrections, revendications, journal] = await Promise.all([
      supabaseAdmin.from('petfriendly_places').select('*')
        .eq('statut', 'en_attente_validation').order('created_at', { ascending: true }),
      supabaseAdmin.from('petfriendly_places').select('*')
        .in('statut', ['a_corriger', 'brouillon']).order('updated_at', { ascending: false }).limit(100),
      supabaseAdmin.from('petfriendly_places').select('*')
        .in('statut', ['actif', 'suspendu', 'masque', 'refuse']).order('created_at', { ascending: false }).limit(200),
      supabaseAdmin.from('petfriendly_corrections').select('*, place:petfriendly_places(id, nom, ville)')
        .eq('statut', 'en_attente').order('created_at', { ascending: true }),
      supabaseAdmin.from('petfriendly_revendications').select('*, place:petfriendly_places(id, nom, ville, site_web, siret)')
        .eq('statut', 'en_attente').order('created_at', { ascending: true }),
      supabaseAdmin.from('petfriendly_moderation_log').select('*, place:petfriendly_places(nom)')
        .order('created_at', { ascending: false }).limit(60),
    ]);
    const err = enAttente.error ?? aCorriger.error ?? publies.error ?? corrections.error ?? revendications.error ?? journal.error;
    if (err) return NextResponse.json({ error: err.message }, { status: 500 });
    // Doublons probables : lieu déjà présent à moins de 150 m d'une fiche en attente.
    type L = { id: string; nom?: string; lat?: number; lng?: number; ville?: string; statut?: string };
    const tous = [...(publies.data ?? []), ...(enAttente.data ?? []), ...(aCorriger.data ?? [])] as L[];
    const dist = (a: L, b: L) => {
      if (a.lat == null || a.lng == null || b.lat == null || b.lng == null) return Infinity;
      const r = Math.PI / 180, dLat = (b.lat - a.lat) * r, dLng = (b.lng - a.lng) * r;
      const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * r) * Math.cos(b.lat * r) * Math.sin(dLng / 2) ** 2;
      return 6371000 * 2 * Math.asin(Math.sqrt(h));
    };
    const doublons: Record<string, { id: string; nom?: string; ville?: string; statut?: string; metres: number }[]> = {};
    for (const p of (enAttente.data ?? []) as L[]) {
      const proches = tous.filter(o => o.id !== p.id && o.statut !== 'refuse' && dist(p, o) < 150)
        .map(o => ({ id: o.id, nom: o.nom, ville: o.ville, statut: o.statut, metres: Math.round(dist(p, o)) }));
      if (proches.length) doublons[p.id] = proches;
    }
    // Justificatifs de revendication (stockage privé) : lien temporaire d'1 h.
    const revs = (revendications.data ?? []) as { justificatif_url?: string | null }[];
    for (const r of revs) {
      const m = r.justificatif_url?.match(/\/object\/(?:public|sign)\/documents\/([^?]+)/);
      if (m) {
        const { data: sig } = await supabaseAdmin.storage.from('documents').createSignedUrl(decodeURIComponent(m[1]), 3600);
        r.justificatif_url = sig?.signedUrl ?? null;
      }
    }
    return NextResponse.json({
      enAttente: enAttente.data ?? [], aCorriger: aCorriger.data ?? [], publies: publies.data ?? [],
      corrections: corrections.data ?? [], revendications: revendications.data ?? [], journal: journal.data ?? [], doublons,
    });
  }
  if (type === 'signalements_contexte') {
    // Qui signale + ce qui est signalé (extrait), lu avec la clé service : un
    // admin n'est pas forcément membre du groupe privé où est la publication.
    const ids = (searchParams.get('ids') ?? '').split(',').filter(Boolean).slice(0, 200);
    if (ids.length === 0) return NextResponse.json({ items: {} });
    const { data: sigs } = await supabaseAdmin.from('signalements')
      .select('id, reporter_uid, target_type, target_id, groupe_id').in('id', ids);
    const liste = (sigs ?? []) as { id: string; reporter_uid: string; target_type: string; target_id: string; groupe_id: string | null }[];
    const uids = new Set<string>();
    liste.forEach(s => { if (s.reporter_uid) uids.add(s.reporter_uid); if (s.target_type === 'user') uids.add(s.target_id); });
    const postIds = liste.filter(s => s.target_type === 'groupe_post').map(s => s.target_id);
    const { data: posts } = postIds.length
      ? await supabaseAdmin.from('groupe_posts').select('id, groupe_id, auteur_uid, auteur_profile_id, contenu, image_url').in('id', postIds)
      : { data: [] };
    const postsList = (posts ?? []) as { id: string; groupe_id: string; auteur_uid: string; auteur_profile_id: string | null; contenu: string | null; image_url: string | null }[];
    postsList.forEach(p => uids.add(p.auteur_uid));
    const groupeIds = [...new Set(postsList.map(p => p.groupe_id))];
    const [{ data: profils }, { data: groupes }] = await Promise.all([
      supabaseAdmin.from('user_profiles').select('id, uid, profile_type, nom, firstname, lastname, is_main').in('uid', [...uids]),
      groupeIds.length ? supabaseAdmin.from('groupes').select('id, nom').in('id', groupeIds) : Promise.resolve({ data: [] }),
    ]);
    type P = { id: string; uid: string; profile_type: string; nom: string | null; firstname: string | null; lastname: string | null; is_main: boolean };
    const pl = (profils ?? []) as P[];
    const nomP = (p?: P) => p ? ((p.profile_type !== 'particulier' && p.nom?.trim()) || `${p.firstname ?? ''} ${p.lastname ?? ''}`.trim() || p.nom || '') : '';
    // Personne : profil particulier, sinon principal.
    const nomUid = (uid: string) => nomP(pl.find(p => p.uid === uid && p.profile_type === 'particulier') ?? pl.find(p => p.uid === uid && p.is_main) ?? pl.find(p => p.uid === uid)) || uid;
    const items: Record<string, unknown> = {};
    for (const s of liste) {
      const post = postsList.find(p => p.id === s.target_id);
      items[s.id] = {
        reporter: { uid: s.reporter_uid, nom: nomUid(s.reporter_uid) },
        cible: s.target_type === 'groupe_post' && post ? {
          extrait: (post.contenu ?? '').slice(0, 300), image_url: post.image_url,
          auteur: { uid: post.auteur_uid, nom: nomP(pl.find(p => p.id === post.auteur_profile_id)) || nomUid(post.auteur_uid) },
          groupe_id: post.groupe_id,
          groupe_nom: ((groupes ?? []) as { id: string; nom: string }[]).find(g => g.id === post.groupe_id)?.nom ?? '',
        } : s.target_type === 'user' ? { nom: nomUid(s.target_id) } : null,
      };
    }
    return NextResponse.json({ items });
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

      // ── Lieux pet-friendly : décisions de modération ───────────────────
      // Chaque décision est historisée (petfriendly_moderation_log) et, sauf
      // réactivation, la personne concernée est prévenue avec le motif.
      case 'lieu_valider':
      case 'lieu_a_corriger':
      case 'lieu_refuser':
      case 'lieu_masquer':
      case 'lieu_suspendre':
      case 'lieu_reactiver': {
        const motif = String(body.motif ?? '').trim() || null;
        if (['lieu_a_corriger', 'lieu_refuser', 'lieu_masquer'].includes(action) && !motif) {
          return NextResponse.json({ error: 'Indiquez le motif.' }, { status: 400 });
        }
        const lieu = (await supabaseAdmin.from('petfriendly_places').select('id, nom, uid_pro, pro_profile_id, ajoute_par_uid, ajoute_par_profile_id, origine').eq('id', id).maybeSingle()).data;
        if (!lieu) return NextResponse.json({ error: 'Lieu introuvable' }, { status: 404 });
        const statut = { lieu_valider: 'actif', lieu_a_corriger: 'a_corriger', lieu_refuser: 'refuse', lieu_masquer: 'masque', lieu_suspendre: 'suspendu', lieu_reactiver: 'actif' }[action]!;
        const maj: Record<string, unknown> = { statut, motif_moderation: motif };
        if (action === 'lieu_valider') {
          maj.valide_par = auth.uid; maj.valide_at = new Date().toISOString();
          if (lieu.uid_pro) maj.verification = 'verifie';
        }
        const r = await supabaseAdmin.from('petfriendly_places').update(maj).eq('id', id);
        if (r.error) throw r.error;
        await supabaseAdmin.from('petfriendly_moderation_log').insert({ place_id: id, objet: 'fiche', objet_id: id, action: action.replace('lieu_', ''), motif, admin_uid: auth.uid });
        // Destinataire : le gestionnaire s'il existe, sinon le contributeur.
        const dest = lieu.uid_pro ? { uid: lieu.uid_pro, pid: lieu.pro_profile_id } : { uid: lieu.ajoute_par_uid, pid: lieu.ajoute_par_profile_id };
        const textes: Record<string, [string, string]> = {
          lieu_valider: ['Lieu publié', `« ${lieu.nom} » est maintenant visible sur la carte des lieux pet-friendly. Merci pour votre contribution.`],
          lieu_a_corriger: ['Lieu à compléter', `« ${lieu.nom} » doit être complété avant publication : ${motif}`],
          lieu_refuser: ['Lieu non publié', `« ${lieu.nom} » n'a pas été publié : ${motif}`],
          lieu_masquer: ['Lieu masqué', `« ${lieu.nom} » a été masqué de la carte : ${motif}`],
          lieu_suspendre: ['Lieu suspendu', `« ${lieu.nom} » a été suspendu${motif ? ` : ${motif}` : '.'}`],
        };
        if (dest.uid && textes[action]) {
          await supabaseAdmin.from('notifications').insert({
            uid: dest.uid, type: 'lieu_moderation', read: false, ...(dest.pid ? { profile_id: dest.pid } : {}),
            title: textes[action][0], body: textes[action][1], data: { place_id: id },
          });
        }
        return NextResponse.json({ ok: true });
      }

      case 'lieu_fusionner': {
        // Doublon : avis, corrections et revendications rejoignent la fiche
        // conservée ; la fiche en double est refusée (motif : doublon).
        const cible = String(body.cible ?? '');
        if (!cible || cible === id) return NextResponse.json({ error: 'Fiche à conserver manquante' }, { status: 400 });
        const [src, dst] = await Promise.all([
          supabaseAdmin.from('petfriendly_places').select('id, nom, ajoute_par_uid, ajoute_par_profile_id').eq('id', id).maybeSingle(),
          supabaseAdmin.from('petfriendly_places').select('id, nom').eq('id', cible).maybeSingle(),
        ]);
        if (!src.data || !dst.data) return NextResponse.json({ error: 'Lieu introuvable' }, { status: 404 });
        for (const t of ['petfriendly_reviews', 'petfriendly_corrections', 'petfriendly_revendications']) {
          const r = await supabaseAdmin.from(t).update({ place_id: cible }).eq('place_id', id);
          if (r.error) throw r.error;
        }
        const r = await supabaseAdmin.from('petfriendly_places').update({ statut: 'refuse', motif_moderation: `Doublon de « ${dst.data.nom} »` }).eq('id', id);
        if (r.error) throw r.error;
        await supabaseAdmin.from('petfriendly_moderation_log').insert({ place_id: cible, objet: 'fiche', objet_id: id, action: 'fusionner', motif: `« ${src.data.nom} » fusionné dans « ${dst.data.nom} »`, admin_uid: auth.uid });
        if (src.data.ajoute_par_uid) {
          await supabaseAdmin.from('notifications').insert({
            uid: src.data.ajoute_par_uid, type: 'lieu_moderation', read: false,
            ...(src.data.ajoute_par_profile_id ? { profile_id: src.data.ajoute_par_profile_id } : {}),
            title: 'Lieu déjà référencé', body: `« ${src.data.nom} » existait déjà : votre contribution a été rattachée à la fiche « ${dst.data.nom} ».`,
            data: { place_id: cible },
          });
        }
        return NextResponse.json({ ok: true });
      }

      case 'correction_appliquer':
      case 'correction_refuser': {
        const motif = String(body.motif ?? '').trim() || null;
        const c = (await supabaseAdmin.from('petfriendly_corrections').select('*, place:petfriendly_places(id, nom, uid_pro)').eq('id', id).maybeSingle()).data as
          { id: string; uid: string; profile_id: string | null; place_id: string; champs: Record<string, unknown>; place: { nom: string; uid_pro: string | null } | null } | null;
        if (!c) return NextResponse.json({ error: 'Correction introuvable' }, { status: 404 });
        if (action === 'correction_refuser' && !motif) return NextResponse.json({ error: 'Indiquez le motif.' }, { status: 400 });
        if (action === 'correction_appliquer') {
          const AUTORISES = ['nom', 'categorie', 'sous_categorie', 'adresse', 'code_postal', 'ville', 'lat', 'lng', 'site_web', 'telephone',
            'especes_acceptees', 'animaux_en_salle', 'terrasse', 'restriction_taille', 'nb_animaux_max', 'supplement_animal',
            'conditions_particulieres', 'horaires', 'derniere_confirmation_le'];
          const maj = Object.fromEntries(Object.entries(c.champs ?? {}).filter(([k]) => AUTORISES.includes(k)));
          if (Object.keys(maj).length) {
            const r = await supabaseAdmin.from('petfriendly_places').update(maj).eq('id', c.place_id);
            if (r.error) throw r.error;
          }
        }
        const r = await supabaseAdmin.from('petfriendly_corrections').update({
          statut: action === 'correction_appliquer' ? 'appliquee' : 'refusee', motif, traite_par: auth.uid, traite_le: new Date().toISOString(),
        }).eq('id', id);
        if (r.error) throw r.error;
        await supabaseAdmin.from('petfriendly_moderation_log').insert({ place_id: c.place_id, objet: 'correction', objet_id: id, action: action === 'correction_appliquer' ? 'appliquer' : 'refuser', motif, admin_uid: auth.uid, details: c.champs });
        await supabaseAdmin.from('notifications').insert({
          uid: c.uid, type: 'lieu_moderation', read: false, ...(c.profile_id ? { profile_id: c.profile_id } : {}),
          title: action === 'correction_appliquer' ? 'Correction appliquée' : 'Correction non retenue',
          body: action === 'correction_appliquer'
            ? `Merci : votre correction de « ${c.place?.nom ?? 'ce lieu'} » a été appliquée.`
            : `Votre correction de « ${c.place?.nom ?? 'ce lieu'} » n'a pas été retenue : ${motif}`,
          data: { place_id: c.place_id },
        });
        return NextResponse.json({ ok: true });
      }

      case 'revendication_valider':
      case 'revendication_refuser': {
        const motif = String(body.motif ?? '').trim() || null;
        const rv = (await supabaseAdmin.from('petfriendly_revendications').select('*, place:petfriendly_places(id, nom, uid_pro)').eq('id', id).maybeSingle()).data as
          { id: string; uid: string; profile_id: string | null; place_id: string; siret: string | null; place: { nom: string; uid_pro: string | null } | null } | null;
        if (!rv) return NextResponse.json({ error: 'Revendication introuvable' }, { status: 404 });
        if (action === 'revendication_refuser' && !motif) return NextResponse.json({ error: 'Indiquez le motif.' }, { status: 400 });
        if (action === 'revendication_valider') {
          if (rv.place?.uid_pro && rv.place.uid_pro !== rv.uid) {
            return NextResponse.json({ error: 'Cette fiche a déjà un gestionnaire.' }, { status: 409 });
          }
          // Même fiche (identifiant, avis, historique conservés) : seul le gestionnaire change.
          const r = await supabaseAdmin.from('petfriendly_places').update({
            uid_pro: rv.uid, pro_profile_id: rv.profile_id, verification: 'verifie',
            ...(rv.siret ? { siret: rv.siret } : {}),
          }).eq('id', rv.place_id);
          if (r.error) throw r.error;
          await supabaseAdmin.from('petfriendly_revendications').update({
            statut: 'refusee', motif: 'Une autre demande a été validée pour cette fiche.', traite_par: auth.uid, traite_le: new Date().toISOString(),
          }).eq('place_id', rv.place_id).eq('statut', 'en_attente').neq('id', id);
        }
        const r = await supabaseAdmin.from('petfriendly_revendications').update({
          statut: action === 'revendication_valider' ? 'validee' : 'refusee', motif, traite_par: auth.uid, traite_le: new Date().toISOString(),
        }).eq('id', id);
        if (r.error) throw r.error;
        await supabaseAdmin.from('petfriendly_moderation_log').insert({ place_id: rv.place_id, objet: 'revendication', objet_id: id, action: action === 'revendication_valider' ? 'valider' : 'refuser', motif, admin_uid: auth.uid });
        await supabaseAdmin.from('notifications').insert({
          uid: rv.uid, type: 'lieu_moderation', read: false, ...(rv.profile_id ? { profile_id: rv.profile_id } : {}),
          title: action === 'revendication_valider' ? 'Fiche revendiquée' : 'Revendication refusée',
          body: action === 'revendication_valider'
            ? `Vous gérez désormais « ${rv.place?.nom ?? 'votre établissement'} » : vous pouvez corriger les informations et répondre aux avis.`
            : `Votre demande pour « ${rv.place?.nom ?? 'cet établissement'} » a été refusée : ${motif}`,
          data: { place_id: rv.place_id },
        });
        return NextResponse.json({ ok: true });
      }

      // ── Signalements : sanction décidée par l'admin ─────────────────────
      // Contenu retiré et/ou avertissement, suspension (jours) ou blocage
      // (définitif) du compte de l'auteur, avec la règle enfreinte : la
      // personne est prévenue (notification) et la sanction est historisée.
      case 'signalement_sanction': {
        const sig = (await supabaseAdmin.from('signalements').select('*').eq('id', id).maybeSingle()).data as
          { id: string; target_type: string; target_id: string } | null;
        if (!sig) return NextResponse.json({ error: 'Signalement introuvable' }, { status: 404 });
        const regle = String(body.regle ?? '').trim();
        const precisions = String(body.precisions ?? '').trim();
        const supprimer = body.supprimer === true;
        const sanction = String(body.sanction ?? 'aucune'); // aucune | avertissement | suspension | blocage
        const jours = Math.min(365, Math.max(1, Number(body.jours ?? 7)));
        if (!regle) return NextResponse.json({ error: 'Indiquez la règle enfreinte.' }, { status: 400 });

        // Auteur + contenu visé.
        let auteur: string | null = null;
        let contenu: Record<string, unknown> | null = null;
        let libelleContenu = 'votre contenu';
        if (sig.target_type === 'groupe_post') {
          const p = (await supabaseAdmin.from('groupe_posts').select('id, auteur_uid, contenu, groupe_id').eq('id', sig.target_id).maybeSingle()).data;
          auteur = p?.auteur_uid ?? null; libelleContenu = 'votre publication dans un groupe';
          contenu = p ? { type: 'groupe_post', id: p.id, groupe_id: p.groupe_id, extrait: String(p.contenu ?? '').slice(0, 300) } : null;
        } else if (sig.target_type === 'annonce') {
          const a = (await supabaseAdmin.from('annonces').select('id, uid_eleveur, titre').eq('id', sig.target_id).maybeSingle()).data;
          auteur = a?.uid_eleveur ?? null; libelleContenu = 'votre annonce';
          contenu = a ? { type: 'annonce', id: a.id, extrait: a.titre } : null;
        } else if (sig.target_type === 'balade_ludique') {
          const b = (await supabaseAdmin.from('balades_ludiques').select('id, createur_uid, titre').eq('id', sig.target_id).maybeSingle()).data;
          auteur = b?.createur_uid ?? null; libelleContenu = 'votre balade';
          contenu = b ? { type: 'balade_ludique', id: b.id, extrait: b.titre } : null;
        } else if (sig.target_type === 'lieu') {
          const l = (await supabaseAdmin.from('petfriendly_places').select('id, nom, uid_pro, ajoute_par_uid').eq('id', sig.target_id).maybeSingle()).data;
          auteur = l?.uid_pro ?? l?.ajoute_par_uid ?? null; libelleContenu = 'votre fiche de lieu';
          contenu = l ? { type: 'lieu', id: l.id, extrait: l.nom } : null;
        } else if (sig.target_type === 'user') {
          auteur = sig.target_id;
        }
        if (!auteur) return NextResponse.json({ error: 'Auteur introuvable (contenu déjà supprimé ?)' }, { status: 404 });

        const faits: string[] = [];
        if (supprimer && contenu) {
          const r = sig.target_type === 'groupe_post'
            ? await supabaseAdmin.from('groupe_posts').delete().eq('id', sig.target_id)
            : sig.target_type === 'annonce'
              ? await supabaseAdmin.from('annonces').update({ statut: 'supprime' }).eq('id', sig.target_id)
              : sig.target_type === 'lieu'
                ? await supabaseAdmin.from('petfriendly_places').update({ statut: 'masque', motif_moderation: regle }).eq('id', sig.target_id)
                : await supabaseAdmin.from('balades_ludiques').update({ statut: 'supprime' }).eq('id', sig.target_id);
          if (r.error) throw r.error;
          await supabaseAdmin.from('sanctions_moderation').insert({
            uid: auteur, type: 'suppression', regle, precisions: precisions || null,
            signalement_id: sig.id, contenu, created_by: auth.uid,
          });
          faits.push('contenu supprimé');
        }

        let finLe: string | null = null;
        if (sanction === 'avertissement' || sanction === 'suspension' || sanction === 'blocage') {
          if (sanction === 'suspension') finLe = new Date(Date.now() + jours * 864e5).toISOString();
          const r = await supabaseAdmin.from('sanctions_moderation').insert({
            uid: auteur, type: sanction, regle, precisions: precisions || null, fin_le: finLe,
            signalement_id: sig.id, contenu, created_by: auth.uid,
          });
          if (r.error) throw r.error;
          if (sanction !== 'avertissement') {
            // Compte entier (tous les profils), comme le bouton « Suspendre » de l'admin.
            const s = await supabaseAdmin.from('user_profiles').update({ statut_pro: 'suspendu' }).eq('uid', auteur);
            if (s.error) throw s.error;
          }
          faits.push(sanction === 'avertissement' ? 'avertissement' : sanction === 'suspension' ? `suspension ${jours} j` : 'compte bloqué');
        }

        // La personne est prévenue, avec la règle enfreinte.
        const motif = precisions ? `${regle} — ${precisions}` : regle;
        const dateFin = finLe ? new Date(finLe).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' }) : '';
        const titre = sanction === 'blocage' ? 'Votre compte a été bloqué'
          : sanction === 'suspension' ? `Votre compte est suspendu jusqu'au ${dateFin}`
          : supprimer ? `Nous avons retiré ${libelleContenu}`
          : 'Avertissement de la modération';
        const corps = [
          supprimer && contenu ? `${libelleContenu.charAt(0).toUpperCase()}${libelleContenu.slice(1)} a été retiré(e).` : '',
          `Règle enfreinte : ${motif}.`,
          sanction === 'suspension' ? `Votre compte est suspendu jusqu'au ${dateFin}.` : '',
          sanction === 'blocage' ? 'Votre compte est bloqué de façon définitive.' : '',
        ].filter(Boolean).join(' ');
        if (faits.length) {
          await supabaseAdmin.from('notifications').insert({ uid: auteur, type: 'moderation', title: titre, body: corps, read: false });
        }

        await supabaseAdmin.from('signalements').update({
          statut: 'traite', handled_at: new Date().toISOString(), handled_by: auth.uid,
          admin_note: [faits.join(', ') || 'sans suite', motif].filter(Boolean).join(' · '),
        }).eq('id', sig.id);
        return NextResponse.json({ ok: true, faits });
      }
    }
    return NextResponse.json({ error: 'action inconnue' }, { status: 400 });
  } catch (e) {
    return NextResponse.json({ error: (e as Error).message }, { status: 500 });
  }
}
