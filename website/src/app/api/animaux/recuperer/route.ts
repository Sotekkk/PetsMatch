import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { requireUser } from '@/lib/server-auth';

// « Récupérer mon animal » — un animal cédé à un particulier SANS compte
// (fiche d'élevage : statut « sorti », aucun compte acquéreur) peut être
// rattaché au compte que l'acquéreur crée ensuite :
//  • verifier  { puce }               → état de la puce pour l'appelant ;
//  • rattacher { animalId, profileId } → direct si l'e-mail / le téléphone
//    du compte correspond à l'acquéreur enregistré par l'éleveur ;
//  • demander  { animalId, profileId, message } → demande à l'éleveur ;
//  • decider   { demandeId, accepter } → l'éleveur (cédant) accepte / refuse ;
//  • inviter   { animalId }           → lien de récupération (e-mail) ;
//  • reclamer  { token, profileId }    → rattachement via ce lien.
// Une simple saisie de puce ne suffit jamais : correspondance de contact,
// invitation de l'éleveur ou validation de sa part.
const admin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? '',
  { auth: { persistSession: false } },
);
const chiffres = (s: unknown) => String(s ?? '').replace(/\D/g, '');
const estUuid = (s: string) => /^[0-9a-f-]{36}$/i.test(s);
const today = () => new Date().toISOString().slice(0, 10);

interface Animal {
  id: string; nom: string | null; espece: string | null; race: string | null; photo_url: string | null; date_naissance: string | null;
  statut: string | null; uid_eleveur: string | null; uid_acquereur: string | null; date_sortie: string | null;
  acquereur_contact_manuel?: { email?: string; tel?: string; prenom?: string; nom?: string } | null;
}
const COLS = 'id, nom, espece, race, photo_url, date_naissance, statut, uid_eleveur, uid_acquereur, date_sortie, acquereur_contact_manuel';

async function chargerAnimal(id: string): Promise<Animal | null> {
  let { data, error } = await admin.from('animaux').select(COLS).eq('id', id).maybeSingle();
  if (error && error.message.includes('acquereur_contact_manuel')) {
    ({ data, error } = await admin.from('animaux').select(COLS.replace(', acquereur_contact_manuel', '')).eq('id', id).maybeSingle());
  }
  return (data as Animal | null) ?? null;
}

/** Cédé à un particulier sans compte : récupérable. */
const recuperable = (a: Animal) => a.statut === 'sorti' && !a.uid_acquereur;

async function nomProfil(uid: string | null): Promise<string> {
  if (!uid) return '';
  const { data } = await admin.from('user_profiles_complet').select('nom, firstname, lastname, profile_type, is_main').eq('uid', uid);
  const l = (data ?? []) as { nom?: string | null; firstname?: string | null; lastname?: string | null; profile_type?: string | null; is_main?: boolean }[];
  const pro = l.find(p => p.profile_type && p.profile_type !== 'particulier' && p.nom) ?? l.find(p => p.is_main) ?? l[0];
  return ((pro?.profile_type !== 'particulier' ? pro?.nom : '') || `${pro?.firstname ?? ''} ${pro?.lastname ?? ''}`.trim() || pro?.nom || '').trim();
}

/** Nom de l'élevage cédant : le profil qui détenait l'animal
 *  (animaux_proprietes.profile_id_proprio), jamais le premier profil pro
 *  du compte — un même compte peut avoir élevage + taxi, pension… */
async function nomElevage(a: Animal): Promise<string> {
  if (!a.uid_eleveur) return '';
  const { data: props } = await admin.from('animaux_proprietes').select('profile_id_proprio, date_debut')
    .eq('animal_id', a.id).eq('uid_proprio', a.uid_eleveur).order('date_debut', { ascending: false }).limit(1);
  let profilId = (props?.[0] as { profile_id_proprio?: string | null } | undefined)?.profile_id_proprio ?? null;
  if (!profilId) {
    const { data: reg } = await admin.from('registre_mouvements').select('eleveur_profile_id')
      .eq('animal_id', a.id).eq('uid_eleveur', a.uid_eleveur).not('eleveur_profile_id', 'is', null).limit(1);
    profilId = (reg?.[0] as { eleveur_profile_id?: string | null } | undefined)?.eleveur_profile_id ?? null;
  }
  const { data } = profilId
    ? await admin.from('user_profiles_complet').select('nom, firstname, lastname, profile_type').eq('id', profilId).eq('uid', a.uid_eleveur)
    : await admin.from('user_profiles_complet').select('nom, firstname, lastname, profile_type').eq('uid', a.uid_eleveur).eq('profile_type', 'eleveur');
  const p = (data?.[0] ?? null) as { nom?: string | null; firstname?: string | null; lastname?: string | null } | null;
  if (!p) return nomProfil(a.uid_eleveur);
  return (p.nom || `${p.firstname ?? ''} ${p.lastname ?? ''}`.trim()).trim();
}

/** Le compte correspond-il à l'acquéreur enregistré (e-mail ou téléphone) ? */
async function correspond(uid: string, a: Animal): Promise<boolean> {
  const c = a.acquereur_contact_manuel;
  if (!c || (!c.email && !c.tel)) return false;
  const { data: u } = await admin.from('users').select('email, phone_number').eq('uid', uid).maybeSingle();
  const { data: profs } = await admin.from('user_profiles_complet').select('email_contact, phone_number').eq('uid', uid);
  const emails = new Set([(u as { email?: string } | null)?.email, ...((profs ?? []) as { email_contact?: string }[]).map(p => p.email_contact)]
    .filter(Boolean).map(e => String(e).trim().toLowerCase()));
  const tels = new Set([(u as { phone_number?: string } | null)?.phone_number, ...((profs ?? []) as { phone_number?: string }[]).map(p => p.phone_number)]
    .map(t => chiffres(t).slice(-9)).filter(t => t.length === 9));
  if (c.email && emails.has(c.email.trim().toLowerCase())) return true;
  if (c.tel && chiffres(c.tel).slice(-9).length === 9 && tels.has(chiffres(c.tel).slice(-9))) return true;
  return false;
}

async function estCedant(uid: string, a: Animal): Promise<boolean> {
  if (a.uid_eleveur === uid) return true;
  const { data } = await admin.from('animaux_proprietes').select('id').eq('animal_id', a.id).eq('uid_proprio', uid).limit(1);
  return (data ?? []).length > 0;
}

/** Transfert de propriété vers le compte de l'acquéreur (même logique que
 *  ceder_propriete_animal), entrée dans son registre, éleveur prévenu. */
async function transferer(a: Animal, uid: string, profileId: string | null) {
  let profil = profileId;
  if (profil) {
    const { data } = await admin.from('user_profiles').select('id').eq('id', profil).eq('uid', uid).maybeSingle();
    if (!data) profil = null;
  }
  if (!profil) {
    const { data } = await admin.from('user_profiles').select('id').eq('uid', uid).eq('profile_type', 'particulier')
      .order('is_main', { ascending: false }).limit(1).maybeSingle();
    profil = (data as { id: string } | null)?.id ?? null;
  }
  const date = (a.date_sortie ?? '').slice(0, 10) || today();
  await admin.from('animaux_proprietes').update({ date_fin: date })
    .eq('animal_id', a.id).is('date_fin', null).eq('statut', 'actif').neq('uid_proprio', uid);
  const { error } = await admin.from('animaux_proprietes').upsert({
    animal_id: a.id, uid_proprio: uid, profile_id_proprio: profil, date_debut: date, date_fin: null,
    role_proprio: 'principal', statut: 'actif',
  }, { onConflict: 'animal_id,uid_proprio' });
  if (error) throw new Error(error.message);
  let maj = await admin.from('animaux').update({ uid_acquereur: uid, profile_id_acquereur: profil, updated_at: new Date().toISOString() }).eq('id', a.id);
  if (maj.error?.message.includes('profile_id_acquereur')) maj = await admin.from('animaux').update({ uid_acquereur: uid }).eq('id', a.id);
  if (maj.error) throw new Error(maj.error.message);
  if (estUuid(a.id)) {
    const eleveur = await nomElevage(a);
    await admin.from('registre_mouvements').insert({
      animal_id: a.id, uid_eleveur: uid, ...(profil ? { eleveur_profile_id: profil } : {}), type: 'entree', date_mouvement: date,
      motif: 'acquisition', provenance_qualite: 'eleveur', provenance_nom: eleveur || null,
    });
  }
  await admin.from('animal_claims').update({ statut: 'reclame', claimed_by_uid: uid, claimed_at: new Date().toISOString() })
    .eq('animal_id', a.id).eq('statut', 'en_attente');
  if (a.uid_eleveur && a.uid_eleveur !== uid) {
    const nom = await nomProfil(uid);
    await admin.from('notifications').insert({
      uid: a.uid_eleveur, type: 'animal_recupere', title: 'Fiche récupérée',
      body: `${nom || 'Son propriétaire'} a rattaché ${a.nom ?? "l'animal"} à son compte PetsMatch.`,
      data: { animalId: a.id }, read: false,
    });
  }
}

export async function POST(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  const uid = auth.uid;
  const b = await req.json().catch(() => ({})) as {
    action?: string; puce?: string; animalId?: string; profileId?: string | null; message?: string;
    demandeId?: string; accepter?: boolean; token?: string;
  };

  try {
    if (b.action === 'verifier') {
      const puce = chiffres(b.puce);
      if (puce.length < 8) return NextResponse.json({ etat: 'aucun' });
      const { data } = await admin.from('animaux').select('id').eq('identification', puce).limit(5);
      let ids = ((data ?? []) as { id: string }[]).map(x => x.id);
      if (!ids.length) {
        // Puce saisie avec espaces / tirets sur la fiche.
        const { data: d2 } = await admin.from('animaux').select('id, identification').ilike('identification', `%${puce.slice(-6)}%`).limit(20);
        ids = ((d2 ?? []) as { id: string; identification: string }[]).filter(x => chiffres(x.identification) === puce).map(x => x.id);
      }
      if (!ids.length) return NextResponse.json({ etat: 'aucun' });
      const a = await chargerAnimal(ids[0]);
      if (!a) return NextResponse.json({ etat: 'aucun' });
      const { data: moi } = await admin.from('animaux_proprietes').select('id').eq('animal_id', a.id).eq('uid_proprio', uid).is('date_fin', null).limit(1);
      if ((moi ?? []).length || a.uid_acquereur === uid) return NextResponse.json({ etat: 'deja_a_vous', animal: { id: a.id, nom: a.nom } });
      const animal = { id: a.id, nom: a.nom, espece: a.espece, race: a.race, photo_url: a.photo_url, date_naissance: a.date_naissance };
      // Fiche créée par un pro (vétérinaire, ostéo, pension…) pour un client
      // sans appli : récupérée par le client via le rattachement de ses
      // coordonnées (/api/clients/rattachement), pas par la puce seule.
      const { data: fp } = await admin.from('animaux').select('cree_par_pro_profile_id, uid_proprietaire').eq('id', a.id).maybeSingle();
      const ficheProProfil = (fp as { cree_par_pro_profile_id?: string | null; uid_proprietaire?: string | null } | null);
      if (ficheProProfil?.cree_par_pro_profile_id && !ficheProProfil.uid_proprietaire) {
        const { data: pro } = await admin.from('user_profiles_complet').select('nom, firstname, lastname').eq('id', ficheProProfil.cree_par_pro_profile_id).maybeSingle();
        const p = pro as { nom?: string | null; firstname?: string | null; lastname?: string | null } | null;
        const proNom = (p?.nom ?? '').trim() || `${p?.firstname ?? ''} ${p?.lastname ?? ''}`.trim() || 'un professionnel';
        return NextResponse.json({ etat: 'fiche_pro', pro: proNom, animal: { nom: a.nom, espece: a.espece } });
      }
      if (!recuperable(a)) return NextResponse.json({ etat: 'detenu', animal: { nom: a.nom, espece: a.espece } });
      const { data: dem } = await admin.from('animal_recuperations').select('id').eq('animal_id', a.id).eq('demandeur_uid', uid).eq('statut', 'en_attente').limit(1);
      return NextResponse.json({
        etat: 'recuperable', animal, elevage: await nomElevage(a),
        correspondance: await correspond(uid, a), demandeEnCours: (dem ?? []).length > 0,
      });
    }

    if (b.action === 'rattacher' || b.action === 'demander') {
      const a = b.animalId ? await chargerAnimal(b.animalId) : null;
      if (!a || !recuperable(a)) return NextResponse.json({ error: 'Cet animal ne peut pas être récupéré.' }, { status: 409 });
      if (b.action === 'rattacher') {
        if (!(await correspond(uid, a))) return NextResponse.json({ error: "Vos coordonnées ne correspondent pas à celles de l'acquéreur : envoyez une demande à l'élevage." }, { status: 403 });
        await transferer(a, uid, b.profileId ?? null);
        return NextResponse.json({ ok: true, animalId: a.id });
      }
      if (!a.uid_eleveur) return NextResponse.json({ error: 'Élevage introuvable' }, { status: 409 });
      const { data, error } = await admin.from('animal_recuperations').insert({
        animal_id: a.id, demandeur_uid: uid, demandeur_profile_id: b.profileId ?? null, eleveur_uid: a.uid_eleveur,
        message: (b.message ?? '').trim().slice(0, 500) || null,
      }).select('id').single();
      if (error) {
        if (error.code === '23505') return NextResponse.json({ ok: true, deja: true });
        throw new Error(error.message);
      }
      const nom = await nomProfil(uid);
      await admin.from('notifications').insert({
        uid: a.uid_eleveur, type: 'animal_recuperation', title: 'Demande de récupération',
        body: `${nom || 'Un utilisateur'} demande à rattacher ${a.nom ?? 'un animal'} à son compte (acquéreur ?).`,
        data: { demandeId: (data as { id: string }).id, animalId: a.id }, read: false,
      });
      return NextResponse.json({ ok: true });
    }

    if (b.action === 'decider') {
      const { data: d } = await admin.from('animal_recuperations').select('*').eq('id', b.demandeId ?? '').maybeSingle();
      const dem = d as { id: string; animal_id: string; demandeur_uid: string; demandeur_profile_id: string | null; statut: string } | null;
      if (!dem || dem.statut !== 'en_attente') return NextResponse.json({ error: 'Demande introuvable ou déjà traitée' }, { status: 404 });
      const a = await chargerAnimal(dem.animal_id);
      if (!a || !(await estCedant(uid, a))) return NextResponse.json({ error: "Réservé à l'élevage cédant" }, { status: 403 });
      if (b.accepter) {
        if (!recuperable(a)) return NextResponse.json({ error: "L'animal est déjà rattaché à un compte." }, { status: 409 });
        await transferer(a, dem.demandeur_uid, dem.demandeur_profile_id);
      }
      await admin.from('animal_recuperations').update({ statut: b.accepter ? 'acceptee' : 'refusee', decided_at: new Date().toISOString() }).eq('id', dem.id);
      if (b.accepter) {
        // Les autres demandes pour cet animal deviennent sans objet.
        await admin.from('animal_recuperations').update({ statut: 'refusee', decided_at: new Date().toISOString() })
          .eq('animal_id', dem.animal_id).eq('statut', 'en_attente');
      }
      await admin.from('notifications').insert({
        uid: dem.demandeur_uid, type: 'animal_recuperation_reponse',
        title: b.accepter ? `${a.nom ?? 'Votre animal'} est rattaché à votre compte` : 'Demande de récupération refusée',
        body: b.accepter ? `L'élevage a validé votre demande : retrouvez ${a.nom ?? 'votre animal'} dans Mes animaux.` : `L'élevage n'a pas validé votre demande pour ${a.nom ?? 'cet animal'}.`,
        ...(dem.demandeur_profile_id ? { profile_id: dem.demandeur_profile_id } : {}),
        data: { animalId: a.id }, read: false,
      });
      return NextResponse.json({ ok: true });
    }

    if (b.action === 'inviter') {
      const a = b.animalId ? await chargerAnimal(b.animalId) : null;
      if (!a || !(await estCedant(uid, a))) return NextResponse.json({ error: "Réservé à l'élevage cédant" }, { status: 403 });
      if (!recuperable(a)) return NextResponse.json({ error: "L'animal est déjà rattaché à un compte." }, { status: 409 });
      const c = a.acquereur_contact_manuel ?? {};
      const { data, error } = await admin.from('animal_claims').insert({
        animal_id: a.id, created_by_uid: uid, email_destinataire: c.email ?? null,
        nom_destinataire: `${c.prenom ?? ''} ${c.nom ?? ''}`.trim() || null, tel_destinataire: c.tel ?? null,
      }).select('token').single();
      if (error) throw new Error(error.message);
      return NextResponse.json({
        ok: true, token: (data as { token: string }).token, email: c.email ?? null, tel: c.tel ?? null, prenom: c.prenom ?? '',
        nom: `${c.prenom ?? ''} ${c.nom ?? ''}`.trim(), animalNom: a.nom ?? 'votre animal', proNom: await nomElevage(a),
      });
    }

    if (b.action === 'reclamer') {
      const { data: cl } = await admin.from('animal_claims').select('id, animal_id, statut').eq('token', b.token ?? '').maybeSingle();
      const claim = cl as { id: string; animal_id: string; statut: string } | null;
      if (!claim || claim.statut !== 'en_attente') return NextResponse.json({ error: 'Lien invalide ou déjà utilisé' }, { status: 404 });
      const a = await chargerAnimal(claim.animal_id);
      if (!a) return NextResponse.json({ error: 'Animal introuvable' }, { status: 404 });
      if (recuperable(a)) {
        await transferer(a, uid, b.profileId ?? null);
      } else {
        // Fiche créée par un pro (pension) sans compte propriétaire : ancien
        // fonctionnement, le propriétaire réel est noté sur la fiche.
        await admin.from('animaux').update({ owner_uid: uid }).eq('id', a.id);
      }
      await admin.from('animal_claims').update({ statut: 'reclame', claimed_by_uid: uid, claimed_at: new Date().toISOString() }).eq('id', claim.id);
      return NextResponse.json({ ok: true, animalId: a.id });
    }

    return NextResponse.json({ error: 'Action inconnue' }, { status: 400 });
  } catch (e) {
    return NextResponse.json({ error: (e as Error).message }, { status: 500 });
  }
}
