'use client';

import { useState } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { signOut } from 'firebase/auth';
import { auth } from '@/lib/firebase';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

export default function CguAcceptationPage() {
  const { user, refreshUserData } = useAuth();
  const router = useRouter();
  const [accepted, setAccepted] = useState(false);
  const [saving, setSaving] = useState(false);

  async function handleAccept() {
    if (!user || !accepted) return;
    setSaving(true);
    try {
      await supabase.from('users').update({
        cgu_accepted_at: new Date().toISOString(),
      }).eq('uid', user.uid);
      await refreshUserData();
      router.replace('/');
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="min-h-[75vh] flex items-center justify-center px-4 py-12">
      <div className="w-full max-w-md">
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-8">
          <div className="flex justify-center mb-6">
            <Image src="/Banniere_petsmatch.png" alt="PetsMatch" width={220} height={70} className="object-contain" />
          </div>

          <h1 className="text-xl font-bold text-[#1F2A2E] mb-2 text-center" style={{ fontFamily: 'Galey, sans-serif' }}>
            Conditions générales d&apos;utilisation
          </h1>
          <p className="text-sm text-gray-500 text-center mb-6">
            Pour continuer, vous devez accepter nos CGU mises à jour.
          </p>

          <div className="bg-gray-50 rounded-xl p-4 mb-6 text-sm text-gray-600 max-h-48 overflow-y-auto leading-relaxed">
            <p className="font-semibold text-[#1F2A2E] mb-2">Résumé des points clés :</p>
            <ul className="space-y-2 list-disc list-inside">
              <li>PetsMatch connecte acheteurs et éleveurs certifiés dans le respect du bien-être animal.</li>
              <li>Seuls les éleveurs disposant d&apos;un SIRET valide et d&apos;un dossier approuvé peuvent publier des annonces.</li>
              <li>Toute maltraitance animale ou fraude entraîne la suspension immédiate du compte.</li>
              <li>Vos données personnelles sont traitées conformément au RGPD.</li>
              <li>Les annonces font l&apos;objet d&apos;une modération et peuvent être signalées.</li>
            </ul>
            <p className="mt-3">
              <Link href="/cgu" target="_blank" className="text-[#0C5C6C] underline font-medium">
                Lire les CGU complètes ↗
              </Link>
            </p>
          </div>

          <label className="flex items-start gap-3 cursor-pointer mb-6">
            <input
              type="checkbox"
              checked={accepted}
              onChange={e => setAccepted(e.target.checked)}
              className="mt-0.5 w-4 h-4 rounded border-gray-300 text-[#0C5C6C] focus:ring-[#0C5C6C]"
            />
            <span className="text-sm text-gray-600">
              J&apos;ai lu et j&apos;accepte les{' '}
              <Link href="/cgu" target="_blank" className="text-[#0C5C6C] underline">
                conditions générales d&apos;utilisation
              </Link>{' '}
              et la{' '}
              <Link href="/confidentialite" target="_blank" className="text-[#0C5C6C] underline">
                politique de confidentialité
              </Link>{' '}
              de PetsMatch.
            </span>
          </label>

          <button
            onClick={handleAccept}
            disabled={!accepted || saving}
            className="w-full bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-50 text-white font-semibold py-3 rounded-xl transition-colors mb-3"
            style={{ fontFamily: 'Galey, sans-serif' }}>
            {saving ? 'Enregistrement…' : 'Accepter et continuer'}
          </button>

          <button
            onClick={() => signOut(auth)}
            className="w-full text-sm text-gray-400 hover:text-gray-600 py-2">
            Se déconnecter
          </button>
        </div>
      </div>
    </div>
  );
}
