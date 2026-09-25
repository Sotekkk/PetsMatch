import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

type Role = 'eleveur' | 'acquereur';

async function notify(opts: {
  uid?: string | null; email?: string | null;
  type: string; title: string; body: string;
  data?: Record<string, unknown>; profileType?: string;
}) {
  try {
    let uid = opts.uid ?? undefined;
    if (!uid && opts.email) {
      const { data: u } = await supabase.from('users').select('uid').eq('email', opts.email).maybeSingle();
      uid = u?.uid as string | undefined;
    }
    if (!uid) return;
    const { data: prof } = await supabase.from('user_profiles').select('id')
      .eq('uid', uid).eq('profile_type', opts.profileType || 'particulier').maybeSingle();
    await supabase.from('notifications').insert({
      uid, type: opts.type, title: opts.title, body: opts.body,
      data: opts.data ?? {}, ...(prof?.id ? { profile_id: prof.id } : {}), read: false,
    });
  } catch { /* notif best-effort */ }
}

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params;
    const { role, signature, actorUid, actorNom } = await req.json() as {
      role: Role; signature: string; actorUid?: string; actorNom?: string;
    };
    if (!role || (role !== 'eleveur' && role !== 'acquereur') || !signature) {
      return NextResponse.json({ error: 'role et signature requis' }, { status: 400 });
    }

    const { data: doc } = await supabase
      .from('documents_animaux')
      .select('id, animal_id, uid_eleveur, type, titre, statut, metadata')
      .eq('id', id)
      .maybeSingle();
    if (!doc) return NextResponse.json({ error: 'Contrat introuvable' }, { status: 404 });
    if (['signe', 'annule', 'refuse', 'expire'].includes(doc.statut)) {
      return NextResponse.json({ error: `Ce contrat est déjà ${doc.statut}` }, { status: 400 });
    }

    const meta = (doc.metadata ?? {}) as Record<string, unknown>;
    const notBlank = (v: unknown) => v != null && String(v).trim() !== '';
    const sigField  = role === 'eleveur' ? 'signature_eleveur'  : 'signature_acquereur';
    if (notBlank(meta[sigField])) {
      return NextResponse.json({ error: 'Cette partie a déjà signé' }, { status: 400 });
    }

    // Signer côté éleveur : réservé au gérant lui-même ou un cogérant actif.
    // Signer côté acquéreur : ouvert à quiconque possède le lien (comme le
    // reste du flux token — même modèle que devis/cessions).
    if (role === 'eleveur') {
      const isGerant = actorUid && actorUid === doc.uid_eleveur;
      let isCogerant = false;
      if (!isGerant && actorUid) {
        const { data: cog } = await supabase.from('elevage_cogerants').select('id')
          .eq('uid_gerant', doc.uid_eleveur).eq('uid_cogerant', actorUid)
          .eq('statut', 'actif').is('date_fin', null).maybeSingle();
        isCogerant = !!cog;
      }
      if (!isGerant && !isCogerant) {
        return NextResponse.json({ error: 'Non autorisé à signer pour l\'éleveur' }, { status: 403 });
      }
    }

    const now = new Date().toISOString();
    const mergedMeta: Record<string, unknown> = { ...meta, [sigField]: signature, [role === 'eleveur' ? 'signe_eleveur_le' : 'signe_acquereur_le']: now };
    if (role === 'eleveur' && actorUid) {
      mergedMeta.signataire_eleveur_uid = actorUid;
      mergedMeta.signataire_eleveur_nom = actorNom ?? '';
    }
    const bothSigned = notBlank(mergedMeta.signature_eleveur) && notBlank(mergedMeta.signature_acquereur);
    const newStatut = bothSigned ? 'signe' : (notBlank(mergedMeta.signature_eleveur) || notBlank(mergedMeta.signature_acquereur)) ? 'partiellement_signe' : 'en_attente';

    const { error: updErr } = await supabase.from('documents_animaux').update({
      metadata: mergedMeta,
      statut: newStatut,
      ...(bothSigned ? { signe_le: now } : {}),
    }).eq('id', doc.id);
    if (updErr) return NextResponse.json({ error: updErr.message }, { status: 500 });

    try {
      await supabase.rpc('log_contract_action', {
        p_document_id: doc.id,
        p_action: bothSigned ? 'signed' : 'partially_signed',
        p_actor_uid: role === 'eleveur' ? (actorUid ?? null) : null,
        p_actor_email: role === 'acquereur' ? ((meta.acquereur_email as string | undefined) ?? null) : null,
        p_actor_role: role,
        p_details: { role },
      });
    } catch { /* audit best-effort */ }

    // Une cession/vente n'est plus JAMAIS finalisée automatiquement à la
    // signature, quel que soit l'ordre des signatures — bascule juste
    // l'animal/la cession en attente de confirmation explicite de l'éleveur
    // (bandeau « Confirmer la cession », mes-animaux/[id]/page.tsx
    // confirmerCession() ; côté appli, _confirmerCession). C'est ce bouton,
    // cliqué explicitement, qui déclenche le vrai transfert.
    const isCessionType = doc.type === 'contrat_vente' || doc.type === 'certificat_cession';
    if (bothSigned && isCessionType && doc.animal_id) {
      try {
        await supabase.from('animaux').update({ statut: 'cession_en_cours' })
          .eq('id', doc.animal_id).in('statut', ['present', 'en_attente_cession']);
      } catch { /* pas bloquant */ }
      try {
        await supabase.from('cessions').update({ statut: 'signe_acquereur' })
          .eq('animal_id', doc.animal_id).in('statut', ['en_attente_acquereur']);
      } catch { /* pas bloquant */ }
    }

    if (bothSigned && doc.type === 'contrat_adoption' && doc.animal_id) {
      await supabase.from('animaux').update({ statut: 'adopte' }).eq('id', doc.animal_id);
    }

    // Notifications inter-parties
    const isAdoption = doc.type === 'contrat_adoption';
    const { partieVendeur, partieAcquereurDefaut } = (() => {
      switch (doc.type) {
        case 'contrat_garde':
        case 'contrat_hebergement':
        case 'contrat_prestation_photo':
        case 'contrat_prestation_toilettage':
        case 'contrat_prestation_marechal':
        case 'contrat_education':
        case 'contrat_sante':
          return { partieVendeur: 'Le prestataire', partieAcquereurDefaut: 'Le client' };
        case 'contrat_adoption':
          return { partieVendeur: 'L\'association', partieAcquereurDefaut: 'L\'adoptant(e)' };
        case 'contrat_saillie':
          return { partieVendeur: 'Le propriétaire de l\'étalon', partieAcquereurDefaut: 'Le propriétaire de la femelle' };
        default:
          return { partieVendeur: 'L\'éleveur', partieAcquereurDefaut: 'L\'acquéreur' };
      }
    })();
    const proProfileType = (() => {
      switch (doc.type) {
        case 'contrat_garde': return 'garde';
        case 'contrat_hebergement': return 'pension';
        case 'contrat_prestation_photo': return 'photographe';
        case 'contrat_prestation_toilettage': return 'toilettage';
        case 'contrat_prestation_marechal': return 'marechal_ferrant';
        case 'contrat_education': return 'education';
        case 'contrat_sante': return 'sante';
        case 'contrat_adoption': return 'association';
        default: return 'eleveur';
      }
    })();
    const acqEmail = meta.acquereur_email as string | undefined;
    const acqNom   = (meta.acquereur_nom as string | undefined) || partieAcquereurDefaut;
    const titre    = doc.titre ?? 'le contrat';

    // Une cession n'est jamais « finalized » automatiquement (voir plus
    // haut) — le mail/notif « complet » ne part donc que pour les contrats
    // non-cession (prestation, adoption...) ; pour une cession, les deux
    // signatures présentes déclenchent toujours la notif « à confirmer »,
    // peu importe qui a signé en dernier.
    const finalized = bothSigned && !isCessionType;
    if (finalized) {
      const complet = `${titre} est désormais signé par les deux parties.`;
      await notify({ uid: doc.uid_eleveur, type: 'contrat_signe_complet', title: '✅ Contrat signé !', body: complet, profileType: isAdoption ? 'association' : 'eleveur', data: { token: id } });
      if (acqEmail) await notify({ email: acqEmail, type: 'contrat_signe_complet', title: '✅ Contrat signé !', body: complet, data: { token: id } });
    } else if (bothSigned) {
      await notify({
        uid: doc.uid_eleveur, type: 'contrat_signe_acquereur',
        title: '✍️ Contrat signé — à confirmer',
        body: `${acqNom} a signé ${titre}. Confirmez la cession pour transférer l'animal.`,
        profileType: proProfileType,
        data: { token: id, ...(doc.animal_id ? { animalId: doc.animal_id } : {}) },
      });
    } else if (role === 'acquereur') {
      await notify({
        uid: doc.uid_eleveur, type: 'contrat_signe_acquereur',
        title: '✍️ Signature reçue',
        body: `${acqNom} a signé ${titre} — à vous de signer pour finaliser.`,
        profileType: proProfileType,
        data: { token: id, ...(doc.animal_id ? { animalId: doc.animal_id } : {}) },
      });
    } else if (acqEmail) {
      await notify({ email: acqEmail, type: 'contrat_signe_eleveur', title: `✍️ ${partieVendeur} a signé`, body: `${partieVendeur} a signé ${titre} — à vous de signer pour finaliser.`, data: { token: id } });
    }

    // Devis d'éducation : la signature du client vaut acceptation du devis.
    if (doc.type === 'contrat_education' && role === 'acquereur') {
      const devisId = meta.devis_id as string | undefined;
      if (devisId) {
        await supabase.from('devis').update({ statut: 'accepte', date_reponse: now, updated_at: now })
          .eq('id', devisId).eq('statut', 'envoye');
        try {
          const { data: dv } = await supabase.from('devis')
            .select('pro_uid, pro_profile_id, client_uid, client_profile_id, animal_id, lignes').eq('id', devisId).maybeSingle();
          if (dv?.pro_uid && Array.isArray(dv.lignes)) {
            const { data: forfaits } = await supabase.from('forfaits_education')
              .select('id, nom, nb_seances, prix').eq('pro_uid', dv.pro_uid).eq('actif', true);
            for (const l of dv.lignes as { description?: string }[]) {
              const desc = (l.description ?? '').toLowerCase();
              const match = (forfaits ?? []).find(f => desc.includes((f.nom ?? '').toLowerCase()) && (f.nom ?? '').length > 2);
              if (match) {
                const { data: exists } = await supabase.from('forfaits_souscrits')
                  .select('id').eq('devis_id', devisId).eq('forfait_id', match.id).maybeSingle();
                if (!exists) {
                  await supabase.from('forfaits_souscrits').insert({
                    forfait_id: match.id, pro_uid: dv.pro_uid, pro_profile_id: dv.pro_profile_id,
                    client_uid: dv.client_uid, client_profile_id: dv.client_profile_id, animal_id: dv.animal_id,
                    nom_snapshot: match.nom, nb_seances_total: match.nb_seances ?? 1, prix_snapshot: match.prix,
                    devis_id: devisId,
                  });
                }
              }
            }
          }
        } catch { /* la souscription auto est un bonus */ }
      }
    }

    return NextResponse.json({ ok: true, statut: newStatut, metadata: mergedMeta, signe_le: bothSigned ? now : null });
  } catch (err) {
    console.error('[contracts/sign]', err);
    return NextResponse.json({ error: 'Erreur serveur' }, { status: 500 });
  }
}
