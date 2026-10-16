'use client';

import { STORE_ANDROID, STORE_IOS } from '@/lib/stores';
import { appelRecuperation } from '@/components/animaux/RecuperationAnimal';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { use, useEffect, useState } from 'react';
import Link from 'next/link';
import { supabaseLien } from '@/lib/supabase';
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
  // Toutes les requêtes de la page portent le lien (en-tête x-pm-token).
  const supabase = supabaseLien(token);
  const { user } = useAuth();
  const activeProfileId = useActiveProfile();
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
    // Rattachement par le serveur : propriété transférée au compte (fiche
    // d'élevage cédée) ou propriétaire noté (fiche créée par une pension).
    try {
      await appelRecuperation({ action: 'reclamer', token, profileId: activeProfileId || null });
    } catch (e) { setError((e as Error).message); setSaving(false); return; }
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
              Pour récupérer la fiche de {animal.nom}, créez votre compte PetsMatch (gratuit) ou connectez-vous : vous reviendrez directement ici.
            </p>
            <div className="flex gap-3">
              <Link href={`/inscription?suite=${encodeURIComponent(`/reclamer-animal/${token}`)}`} className="flex-1 bg-[#0C5C6C] text-white text-sm font-galey font-semibold py-2.5 rounded-xl hover:bg-[#094F5D] transition-colors">
                Créer mon compte
              </Link>
              <Link href={`/connexion?suite=${encodeURIComponent(`/reclamer-animal/${token}`)}`} className="flex-1 border border-gray-200 text-gray-600 text-sm font-galey font-semibold py-2.5 rounded-xl hover:bg-gray-50 transition-colors">
                J&apos;ai déjà un compte
              </Link>
            </div>
            <div className="mt-6 pt-5 border-t border-gray-100 text-left">
              <p className="text-sm font-semibold text-[#1F2A2E]">Vous préférez l&apos;application ?</p>
              <p className="text-xs text-gray-500 mt-1">
                Téléchargez PetsMatch, créez votre compte avec l&apos;adresse e-mail ou le téléphone donnés à votre éleveur, puis ajoutez {animal.nom} avec son numéro de puce : sa fiche complète vous sera proposée. Vous pouvez aussi revenir sur ce lien une fois votre compte créé.
              </p>
              {(STORE_ANDROID || STORE_IOS) && (
                <div className="flex gap-2 mt-3">
                  {STORE_ANDROID && <a href={STORE_ANDROID} target="_blank" rel="noopener noreferrer" className="flex-1 text-center text-xs font-semibold py-2 rounded-xl border border-gray-200 hover:bg-gray-50">Google Play</a>}
                  {STORE_IOS && <a href={STORE_IOS} target="_blank" rel="noopener noreferrer" className="flex-1 text-center text-xs font-semibold py-2 rounded-xl border border-gray-200 hover:bg-gray-50">App Store</a>}
                </div>
              )}
            </div>
          </>
        ) : (
          <>
            <p className="text-sm text-gray-600 mb-4">
              Récupérez la fiche de {animal.nom} sur votre compte : identité, généalogie, carnet de santé et documents.
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
