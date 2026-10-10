import { NextRequest, NextResponse } from 'next/server';
import { stripe } from '@/lib/stripe';
import { requireUser } from '@/lib/server-auth';
import { supabaseService, trierChangements, estProprietaire, type TableAnnonce } from '@/lib/annonce-modification';

// POST /api/annonces/modifier — appli et site (jeton Firebase requis).
//   { table: 'annonces' | 'annonces_objets', id, action: 'modification', changements }
//   { table, id, action: 'renouvellement' }
// Brouillon : tout est appliqué. Annonce publiée : changements gratuits
// appliqués tout de suite ; s'il reste des changements payants (ou pour un
// renouvellement), modification mise en attente + session Stripe → { url }.
// Le webhook applique la modification au paiement.
export async function POST(req: NextRequest) {
  try {
    const auth = await requireUser(req);
    if (auth instanceof NextResponse) return auth;
    const uid = auth.uid;
    const { table, id, action, changements } = await req.json() as {
      table: TableAnnonce; id: string; action: 'modification' | 'renouvellement'; changements?: Record<string, unknown>;
    };
    if (!['annonces', 'annonces_objets'].includes(table) || !id || !['modification', 'renouvellement'].includes(action)) {
      return NextResponse.json({ error: 'Paramètres invalides' }, { status: 400 });
    }
    const { data: row } = await supabaseService.from(table).select('*').eq('id', id).maybeSingle();
    if (!row) return NextResponse.json({ error: 'Annonce introuvable' }, { status: 404 });
    if (!(await estProprietaire(table, row, uid))) return NextResponse.json({ error: 'Annonce non autorisée' }, { status: 403 });

    let enAttente: Record<string, unknown> = {};
    if (action === 'modification') {
      const { libres, payants } = trierChangements(table, row, changements ?? {});
      if (row.statut === 'brouillon') {
        const tout = { ...libres, ...payants };
        if (Object.keys(tout).length) {
          const { error } = await supabaseService.from(table).update(tout).eq('id', id);
          if (error) return NextResponse.json({ error: error.message }, { status: 500 });
        }
        return NextResponse.json({ applique: true });
      }
      if (Object.keys(libres).length) {
        const { error } = await supabaseService.from(table).update(libres).eq('id', id);
        if (error) return NextResponse.json({ error: error.message }, { status: 500 });
      }
      if (!Object.keys(payants).length) return NextResponse.json({ applique: true });
      enAttente = payants;
    }

    const code = action === 'modification' ? 'annonce_modification' : 'annonce_renouvellement';
    const { data: produit } = await supabaseService.from('produits_ponctuels').select('stripe_price_id, prix, actif')
      .eq('code', code).maybeSingle();
    if (!produit?.actif || !produit.stripe_price_id) {
      return NextResponse.json({ error: 'Paiement indisponible : prix Stripe non configuré (admin → Produits ponctuels).' }, { status: 503 });
    }
    const { data: modif, error: errModif } = await supabaseService.from('annonces_modifications').insert({
      table_source: table, annonce_id: id, uid, action, changements: enAttente,
    }).select('id').single();
    if (errModif || !modif) return NextResponse.json({ error: errModif?.message ?? 'Erreur' }, { status: 500 });

    const origin = req.headers.get('origin') ?? process.env.NEXT_PUBLIC_SITE_URL ?? 'https://petsmatchapp.com';
    const retour = table === 'annonces_objets' ? '/mes-annonces-materiel' : '/mes-annonces';
    const session = await stripe.checkout.sessions.create({
      mode: 'payment',
      line_items: [{ price: produit.stripe_price_id as string, quantity: 1 }],
      success_url: `${origin}${retour}?paiement=${action}`,
      cancel_url: `${origin}${retour}?paiement=annule`,
      metadata: { uid, produit_code: code, modification_id: modif.id },
    });
    await supabaseService.from('annonces_modifications').update({ stripe_session_id: session.id }).eq('id', modif.id);
    return NextResponse.json({ url: session.url, prix: produit.prix, payants: Object.keys(enAttente) });
  } catch (err) {
    console.error('[annonces/modifier]', err);
    return NextResponse.json({ error: 'Erreur serveur' }, { status: 500 });
  }
}
