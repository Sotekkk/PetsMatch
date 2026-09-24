import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

// Sélection de la femelle (contrepartie) par le propriétaire de la femelle,
// connecté, sur un contrat de saillie — cf. signer-contrat/[token]/page.tsx.
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params;
    const { femelleId, actorUid, actorEmail } = await req.json() as {
      femelleId: string; actorUid?: string; actorEmail?: string;
    };
    if (!femelleId) return NextResponse.json({ error: 'femelleId requis' }, { status: 400 });

    const { data: doc } = await supabase
      .from('documents_animaux')
      .select('id, type, statut, metadata')
      .eq('id', id)
      .maybeSingle();
    if (!doc) return NextResponse.json({ error: 'Contrat introuvable' }, { status: 404 });
    if (doc.type !== 'contrat_saillie') return NextResponse.json({ error: 'Non applicable à ce type de contrat' }, { status: 400 });
    if (['signe', 'annule', 'refuse', 'expire'].includes(doc.statut)) {
      return NextResponse.json({ error: `Contrat déjà ${doc.statut}` }, { status: 400 });
    }
    const meta = (doc.metadata ?? {}) as Record<string, unknown>;
    if (actorEmail && meta.acquereur_email && actorEmail !== meta.acquereur_email) {
      return NextResponse.json({ error: 'Non autorisé' }, { status: 403 });
    }

    const { data: femelle } = await supabase.from('animaux')
      .select('id, nom, race, couleur, identification, date_naissance, pedigree_numero, pedigree_lof')
      .eq('id', femelleId)
      .maybeSingle();
    if (!femelle) return NextResponse.json({ error: 'Femelle introuvable' }, { status: 404 });
    if (actorUid) {
      const { data: owns } = await supabase.from('animaux')
        .select('id').eq('id', femelleId).eq('uid_eleveur', actorUid).maybeSingle();
      if (!owns) return NextResponse.json({ error: 'Cet animal ne vous appartient pas' }, { status: 403 });
    }

    const femelleData = {
      femelle_animal_id: femelle.id,
      femelle_nom: femelle.nom ?? '',
      femelle_race: femelle.race ?? '',
      femelle_couleur: femelle.couleur ?? '',
      femelle_identification: femelle.identification ?? '',
      femelle_pedigree: femelle.pedigree_numero ?? femelle.pedigree_lof ?? '',
      femelle_naissance: femelle.date_naissance ?? '',
    };
    const newMeta = { ...meta, ...femelleData };

    const { error } = await supabase.from('documents_animaux').update({ metadata: newMeta }).eq('id', doc.id);
    if (error) return NextResponse.json({ error: error.message }, { status: 500 });

    return NextResponse.json({ ok: true, metadata: newMeta, femelle });
  } catch (err) {
    console.error('[contracts/femelle]', err);
    return NextResponse.json({ error: 'Erreur serveur' }, { status: 500 });
  }
}
