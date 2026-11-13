// Rappels d'abonnement envoyés par la Cloud Function quotidienne
// (processAbonnementsExpiration) : notification + e-mail au pro —
// renouvellement annuel J-30 / J-7, fin de résiliation J-3, abonnement
// suspendu (grâce dépassée), carte bientôt expirée.
// Appel serveur → serveur uniquement (x-internal-secret = INTERNAL_API_SECRET).
import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { prevenirPro, type LigneAbonnement, type TypeMessage } from '@/lib/abonnement-gestion';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
);

const TYPES = new Set<TypeMessage>(['renouvellement', 'fin_resiliation', 'suspendu', 'carte_expire']);

export async function POST(req: NextRequest) {
  const secret = process.env.INTERNAL_API_SECRET;
  if (!secret || req.headers.get('x-internal-secret') !== secret) {
    return NextResponse.json({ error: 'Non autorisé' }, { status: 401 });
  }
  const { abonnement_id, type, date, montant, jours } = await req.json().catch(() => ({})) as {
    abonnement_id?: string; type?: TypeMessage; date?: string | null; montant?: string | null; jours?: number;
  };
  if (!abonnement_id || !type || !TYPES.has(type)) return NextResponse.json({ error: 'Requête invalide' }, { status: 400 });
  const { data } = await supabase.from('abonnements').select('*').eq('id', abonnement_id).maybeSingle();
  if (!data) return NextResponse.json({ error: 'Abonnement introuvable' }, { status: 404 });
  await prevenirPro(supabase, data as LigneAbonnement, type, { date, montant, jours });
  return NextResponse.json({ ok: true });
}
