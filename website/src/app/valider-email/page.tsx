'use client';
// Étape « Valider mon adresse » du lien d'inscription envoyé par e-mail : la
// validation n'a lieu qu'au clic (api/inscription/lien?ok=1). Ouvrir le lien
// ne suffit plus — les analyseurs de liens des messageries (Gmail, antivirus)
// l'ouvraient et validaient l'adresse à la place de la personne.
import { Suspense } from 'react';
import { useSearchParams } from 'next/navigation';

function ValiderEmail() {
  const t = useSearchParams().get('t') ?? '';
  const valide = /^[a-f0-9]{48}$/.test(t);
  return (
    <div className="min-h-screen flex items-center justify-center bg-[#F4F7F6] px-4" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="bg-white rounded-2xl shadow-sm p-8 max-w-sm w-full text-center">
        <h1 className="text-xl font-bold text-[#1F2A2E] mb-2">Validez votre adresse e-mail</h1>
        {valide ? (
          <>
            <p className="text-sm text-gray-600 mb-6">Cliquez sur le bouton pour confirmer votre adresse et finaliser votre inscription sur PetsMatch.</p>
            <a href={`/api/inscription/lien?t=${t}&ok=1`}
              className="block w-full py-3 rounded-xl bg-[#0C5C6C] text-white font-bold hover:bg-[#094F5D]">
              Valider mon adresse
            </a>
          </>
        ) : (
          <p className="text-sm text-gray-600">Lien invalide. Demandez un nouveau lien depuis la page de validation.</p>
        )}
      </div>
    </div>
  );
}

export default function ValiderEmailPage() {
  return <Suspense fallback={null}><ValiderEmail /></Suspense>;
}
