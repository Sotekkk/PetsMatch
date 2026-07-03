'use client';

import { use, useEffect, useState } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

interface Claim {
  id: string;
  animal_id: string;
  statut: string;
  nom_destinataire?: string | null;
}

interface Animal {
  id: string;
  nom: string | null;
  espece: string | null;
  race: string | null;
  photo_url: string | null;
}

export default function ReclamerAnimalPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = use(params);
  const { user } = useAuth();
  const [claim, setClaim] = useState<Claim | null>(null);
  const [animal, setAnimal] = useState<Animal | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [done, setDone] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    (async () => {
      const { data: claimRow } = await supabase
        .from('animal_claims').select('id, animal_id, statut, nom_destinataire')
        .eq('token', token).maybeSingle();
      if (!claimRow) { setLoading(false); return; }
      setClaim(claimRow as Claim);
      const { data: animalRow } = await supabase
        .from('animaux').select('id, nom, espece, race, photo_url')
        .eq('id', claimRow.animal_id).maybeSingle();
      setAnimal(animalRow as Animal);
      setLoading(false);
    })();
  }, [token]);

  async function claimIt() {
    if (!user || !claim) return;
    setSaving(true);
    setError('');
    const [{ error: e1 }, { error: e2 }] = await Promise.all([
      supabase.from('animaux').update({ owner_uid: user.uid }).eq('id', claim.animal_id),
      supabase.from('animal_claims').update({
        statut: 'reclame', claimed_by_uid: user.uid, claimed_at: new Date().toISOString(),
      }).eq('id', claim.id),
    ]);
    if (e1 || e2) { setError((e1 ?? e2)?.message ?? 'Erreur'); setSaving(false); return; }
    setDone(true);
    setSaving(false);
  }

  if (loading) {
    return <div className="flex justify-center py-24"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;
  }

  if (!claim || !animal) {
    return (
      <div className="max-w-md mx-auto px-4 py-24 text-center">
        <p className="text-4xl mb-4">🔗</p>
        <h1 className="font-['Galey'] font-bold text-xl text-[#1F2A2E] mb-2">Lien invalide</h1>
        <p className="text-gray-500 text-sm">Ce lien de réclamation n&apos;existe pas ou a expiré.</p>
      </div>
    );
  }

  const alreadyClaimed = claim.statut === 'reclame';

  return (
    <div className="max-w-md mx-auto px-4 py-16">
      <div className="bg-white rounded-2xl border border-gray-100 shadow-sm p-6 text-center">
        {animal.photo_url ? (
          <img src={animal.photo_url} alt={animal.nom ?? ''} className="w-24 h-24 rounded-full object-cover mx-auto mb-4" />
        ) : (
          <div className="w-24 h-24 rounded-full bg-[#EEF5EA] flex items-center justify-center text-4xl mx-auto mb-4">🐾</div>
        )}
        <h1 className="font-['Galey'] font-bold text-xl text-[#1F2A2E] mb-1">{animal.nom}</h1>
        <p className="text-gray-500 text-sm mb-6">{[animal.espece, animal.race].filter(Boolean).join(' · ') || 'Fiche animal'}</p>

        {done || alreadyClaimed ? (
          <div className="bg-[#EEF5EA] text-[#0C5C6C] rounded-xl p-4 text-sm font-galey font-semibold">
            {done ? '🎉 Fiche récupérée ! Retrouvez-la dans "Mes animaux".' : 'Cette fiche a déjà été réclamée.'}
          </div>
        ) : !user ? (
          <>
            <p className="text-sm text-gray-600 mb-4">
              Connectez-vous ou créez un compte PetsMatch, puis revenez sur ce lien pour récupérer cette fiche.
            </p>
            <div className="flex gap-3">
              <Link href="/connexion" className="flex-1 bg-[#0C5C6C] text-white text-sm font-galey font-semibold py-2.5 rounded-xl hover:bg-[#094F5D] transition-colors">
                Se connecter
              </Link>
              <Link href="/inscription" className="flex-1 border border-gray-200 text-gray-600 text-sm font-galey font-semibold py-2.5 rounded-xl hover:bg-gray-50 transition-colors">
                Créer un compte
              </Link>
            </div>
          </>
        ) : (
          <>
            <p className="text-sm text-gray-600 mb-4">
              Récupérez cette fiche pour suivre le carnet de santé de {animal.nom} et recevoir des nouvelles pendant ses séjours.
            </p>
            {error && <p className="text-sm text-red-600 mb-3">{error}</p>}
            <button onClick={claimIt} disabled={saving}
              className="w-full bg-[#6E9E57] text-white text-sm font-galey font-semibold py-2.5 rounded-xl hover:bg-[#5A8A45] disabled:opacity-50 transition-colors">
              {saving ? 'Récupération…' : `🐾 Récupérer la fiche de ${animal.nom}`}
            </button>
          </>
        )}
      </div>
    </div>
  );
}
