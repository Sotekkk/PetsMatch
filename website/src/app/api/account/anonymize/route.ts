import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

// Anonymisation appelée depuis la suppression de compte (profil/page.tsx).
// Nécessite service_role, pas un contournement de la RLS : les policies
// d'UPDATE de ces tables réutilisent leur clause USING comme WITH CHECK
// implicite (comportement standard Postgres quand WITH CHECK est omis) —
// mettre la colonne d'identité à NULL viole donc mécaniquement cette même
// condition (la ligne ne "s'appartient" plus après coup). C'est le
// comportement RLS correct pour un UPDATE normal ; l'anonymisation au
// moment de la suppression de compte est un cas particulier volontaire,
// distinct de ce que la RLS doit autoriser au quotidien.
const ANON = 'Compte supprimé';

// Tables liées à un animal_id : l'animal et son historique (soins,
// pedigree, prestations) sont CONSERVÉS — seule l'identité du/des
// humain(s) référencé(s) est retirée (colonne à NULL, ligne conservée).
const ANIMAL_LINKED_OWNER_COLS: [string, string[]][] = [
  ['animaux', ['uid_eleveur', 'uid_proprietaire', 'uid_acquereur', 'owner_uid']],
  ['animaux_proprietes', ['uid_proprio']],
  ['alimentations', ['uid_eleveur']],
  ['bebes_portee', ['uid_eleveur']],
  ['comptes_rendus', ['pro_uid', 'owner_uid']],
  ['education_objectifs', ['pro_uid', 'owner_uid']],
  ['education_progression', ['pro_uid', 'owner_uid']],
  ['exercices_attribues', ['pro_uid', 'owner_uid']],
  ['fiches_toilettage', ['client_uid', 'pro_uid']],
  ['cles_clients', ['pro_uid', 'owner_uid']],
  ['rdv', ['client_uid', 'pro_uid']],
  ['ordonnances', ['pro_uid', 'owner_uid']],
  ['radios', ['vet_id']],
  ['points_osteo', ['pro_uid']],
  ['seances_osteo', ['pro_uid']],
  ['tests_genetiques', ['uid']],
  // vaccinations/traitements/visites/vermifuges/antiparasitaires/allergies/
  // chirurgies/poids/vet_consultations : aucune colonne d'identité propre
  // (résolues via animaux.uid_eleveur), déjà couvertes par la ligne
  // `animaux` ci-dessus — rien à anonymiser dessus séparément.
];

export async function POST(req: NextRequest) {
  try {
    const { uid } = await req.json() as { uid?: string };
    if (!uid) return NextResponse.json({ error: 'uid requis' }, { status: 400 });

    await Promise.all(
      ANIMAL_LINKED_OWNER_COLS.flatMap(([table, cols]) =>
        cols.map(col =>
          Promise.resolve(supabase.from(table).update({ [col]: null }).eq(col, uid)).then(() => null).catch(() => null)
        )
      )
    );

    await Promise.all([
      supabase.from('devis').update({
        nom_client: ANON, prenom_client: null, email_client: null, telephone_client: null,
      }).eq('client_uid', uid),
      supabase.from('reservations_animaux').update({
        nom: ANON, email: null, tel: null, adresse: null,
      }).eq('uid_acquereur', uid),
    ]);

    return NextResponse.json({ ok: true });
  } catch (err) {
    console.error('[account/anonymize]', err);
    return NextResponse.json({ error: 'Erreur serveur' }, { status: 500 });
  }
}
