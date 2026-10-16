import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { requireUser } from '@/lib/server-auth';

// Import I-CAD — correction d'une cession enregistrée dans PetsMatch vers un
// mauvais compte (cession test) alors qu'I-CAD indique un acquéreur
// particulier sans compte. Réservé au CÉDANT (éleveur de référence de la
// fiche, ou ancien propriétaire au registre de propriété). Effets :
//  • la fiche n'est plus rattachée au compte de l'acquéreur (uid / profil),
//    ses lignes de propriété et son mouvement d'entrée sont supprimés ;
//  • destinataire + coordonnées = acquéreur I-CAD ;
//  • le mouvement de sortie du cédant (registre) reprend ces informations.
// Les contrats et documents ne sont pas touchés.
const admin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? '',
  { auth: { persistSession: false } },
);
const estUuid = (s: string) => /^[0-9a-f-]{36}$/i.test(s);

export async function POST(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  const uid = auth.uid;
  const body = await req.json().catch(() => ({})) as {
    animalId?: string; dateCession?: string;
    acquereur?: { nom?: string; prenom?: string; adresse?: string; email?: string; tel?: string };
  };
  const animalId = String(body.animalId ?? '');
  const a = body.acquereur;
  if (!animalId || !a) return NextResponse.json({ error: 'Paramètres manquants' }, { status: 400 });

  const { data: animal } = await admin.from('animaux').select('id, uid_eleveur, uid_acquereur').eq('id', animalId).maybeSingle();
  const fiche = animal as { id: string; uid_eleveur: string | null; uid_acquereur: string | null } | null;
  if (!fiche) return NextResponse.json({ error: 'Animal introuvable' }, { status: 404 });
  const { data: mesLignes } = await admin.from('animaux_proprietes').select('id').eq('animal_id', animalId).eq('uid_proprio', uid).limit(1);
  const estCedant = fiche.uid_eleveur === uid || (mesLignes ?? []).length > 0;
  if (!estCedant || fiche.uid_acquereur === uid) return NextResponse.json({ error: 'Réservé au cédant de cet animal' }, { status: 403 });

  const acqUid = fiche.uid_acquereur;
  const nom = `${a.prenom ?? ''} ${a.nom ?? ''}`.trim();
  const contact = { prenom: a.prenom ?? '', nom: a.nom ?? '', tel: a.tel ?? '', email: a.email ?? '', adresse: a.adresse ?? '' };
  const date = /^\d{4}-\d{2}-\d{2}$/.test(body.dateCession ?? '') ? body.dateCession! : null;

  // 1. Compte acquéreur erroné : propriété et mouvement d'entrée retirés.
  if (acqUid) {
    await admin.from('animaux_proprietes').delete().eq('animal_id', animalId).eq('uid_proprio', acqUid);
    if (estUuid(animalId)) {
      await admin.from('registre_mouvements').delete().eq('animal_id', animalId).eq('uid_eleveur', acqUid);
    }
  }
  // 2. Fiche : acquéreur réel (sans compte).
  const maj: Record<string, unknown> = {
    uid_acquereur: null, profile_id_acquereur: null, statut: 'sorti',
    destinataire_nom: nom, destinataire_qualite: 'particulier', destinataire_adresse: contact.adresse,
    acquereur_contact_manuel: contact, updated_at: new Date().toISOString(),
    ...(date ? { date_sortie: date } : {}),
  };
  let { error } = await admin.from('animaux').update(maj).eq('id', animalId);
  if (error && /profile_id_acquereur|acquereur_contact_manuel/.test(error.message)) {
    delete maj.profile_id_acquereur;
    if (/acquereur_contact_manuel/.test(error.message)) delete maj.acquereur_contact_manuel;
    ({ error } = await admin.from('animaux').update(maj).eq('id', animalId));
  }
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  // 3. Cédant : sa propriété se clôt à la cession, son registre suit.
  if (date) {
    await admin.from('animaux_proprietes').update({ date_fin: date })
      .eq('animal_id', animalId).eq('uid_proprio', uid).is('date_fin', null);
  }
  if (estUuid(animalId)) {
    await admin.from('registre_mouvements').update({
      destinataire_nom: nom, destinataire_qualite: 'particulier', destinataire_adresse: contact.adresse,
      ...(date ? { date_mouvement: date } : {}),
    }).eq('animal_id', animalId).eq('uid_eleveur', uid).eq('type', 'sortie');
  }
  return NextResponse.json({ ok: true, compteRetire: !!acqUid });
}
