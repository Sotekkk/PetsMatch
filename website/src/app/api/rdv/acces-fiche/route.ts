import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { requireUser } from '@/lib/server-auth';

// Fiche d'un animal ouverte par un pro depuis un RDV confirmé (visite de la
// pension, visite d'essai…) : l'accès (animal_access) est accordé ici, côté
// serveur, s'il manque — le partage fait par le navigateur à la confirmation
// pouvait échouer sans bruit. Sinon, la raison exacte est renvoyée pour
// l'afficher sur la fiche. Corps : { animalId, profileId } (profil pro actif).
const admin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
);

type Rdv = {
  id: string; statut: string; animal_id: string | null; animaux_ids: unknown; animaux_detail: unknown;
  client_profile_id: string | null; pro_profile_id: string | null; created_at: string | null;
};

function animauxDuRdv(r: Rdv): string[] {
  const ids = new Set<string>();
  if (r.animal_id) ids.add(String(r.animal_id));
  if (Array.isArray(r.animaux_ids)) for (const x of r.animaux_ids) if (x) ids.add(String(x));
  if (Array.isArray(r.animaux_detail)) for (const x of r.animaux_detail as { id?: unknown }[]) if (x?.id) ids.add(String(x.id));
  return [...ids];
}

export async function POST(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  const { animalId, profileId } = await req.json().catch(() => ({})) as { animalId?: string; profileId?: string };
  if (!animalId || !profileId) return NextResponse.json({ error: 'Paramètres manquants' }, { status: 400 });

  // Profil pro : le mien, ou celui d'un élevage dont je suis cogérant actif.
  const { data: prof } = await admin.from('user_profiles').select('id, uid, cat_pro').eq('id', profileId).maybeSingle();
  const p = prof as { id: string; uid: string; cat_pro: string | null } | null;
  if (!p) return NextResponse.json({ raison: 'profil' });
  if (p.uid !== auth.uid) {
    const { data: co } = await admin.from('elevage_cogerants').select('id')
      .eq('uid_gerant', p.uid).eq('uid_cogerant', auth.uid).eq('statut', 'actif').is('date_fin', null).limit(1);
    if (!(co ?? []).length) return NextResponse.json({ error: 'Non autorisé' }, { status: 403 });
  }

  const { data: rows } = await admin.from('rdv')
    .select('id, statut, animal_id, animaux_ids, animaux_detail, client_profile_id, pro_profile_id, created_at')
    .eq('pro_profile_id', profileId).order('date_heure', { ascending: false }).limit(500);
  const rdvs = ((rows ?? []) as Rdv[]).filter(r => animauxDuRdv(r).includes(animalId));
  const confirme = rdvs.find(r => r.statut === 'confirme' || r.statut === 'termine');
  if (!confirme) {
    const enDemande = rdvs.some(r => r.statut === 'demande' || r.statut === 'contre_proposition');
    return NextResponse.json({ raison: enDemande ? 'demande' : 'aucun_rdv' });
  }

  const { data: acc } = await admin.from('animal_access').select('id, statut, revoked_at')
    .eq('animal_id', animalId).eq('pro_profile_id', profileId).maybeSingle();
  const a = acc as { id: string; statut: string; revoked_at: string | null } | null;
  // Accès retiré (par le propriétaire, ou par la pension à la fin d'un séjour) :
  // un RDV pris APRÈS ce retrait vaut nouveau partage ; retiré après, on le respecte.
  if (a?.statut === 'revoked') {
    const dernierRdv = rdvs.filter(r => r.statut === 'confirme' || r.statut === 'termine')
      .map(r => r.created_at ?? '').sort().pop() ?? '';
    if (!a.revoked_at || !dernierRdv || a.revoked_at > dernierRdv) return NextResponse.json({ raison: 'retire' });
  }
  if (a && a.statut !== 'pending') return NextResponse.json({ ok: true, deja: true });

  // Propriétaire : le client du RDV, sinon le propriétaire actuel de l'animal.
  let owner = confirme.client_profile_id;
  if (!owner) {
    const { data: pr } = await admin.from('animaux_proprietes').select('profile_id_proprio')
      .eq('animal_id', animalId).is('date_fin', null).limit(1);
    owner = ((pr ?? [])[0] as { profile_id_proprio?: string | null } | undefined)?.profile_id_proprio ?? null;
  }
  if (!owner) return NextResponse.json({ raison: 'proprietaire' });
  const permissions = p.cat_pro === 'veterinaire' ? ['read_basic', 'read_health', 'write_health']
    : p.cat_pro === 'pension' ? ['read_basic', 'read_alimentation', 'write_notes']
    : ['read_basic', 'write_notes'];
  const { error } = await admin.from('animal_access').upsert({
    animal_id: animalId, pro_profile_id: profileId, granted_by_profile_id: owner,
    permissions, statut: 'active', granted_at: new Date().toISOString(), revoked_at: null,
  }, { onConflict: 'animal_id,pro_profile_id' });
  if (error) return NextResponse.json({ raison: 'erreur', detail: error.message });
  return NextResponse.json({ ok: true });
}
