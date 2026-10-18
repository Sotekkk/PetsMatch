'use client';
// Consignes avant un rendez-vous, par lien personnel (reçu par e-mail ou
// notification) : sans compte. Invite ensuite à utiliser PetsMatch.
import { useParams } from 'next/navigation';
import Link from 'next/link';
import ConsignesRdvForm from '@/components/ConsignesRdvForm';
import { STORE_ANDROID, STORE_IOS } from '@/lib/stores';

export default function ConsignesPage() {
  const { token } = useParams<{ token: string }>();
  return (
    <div className="min-h-screen bg-[#F6F7F5] px-4 py-8" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="max-w-lg mx-auto bg-white rounded-2xl border border-gray-100 p-5">
        <ConsignesRdvForm token={token} />
      </div>
      <div className="max-w-lg mx-auto text-center mt-5 text-sm text-gray-500 space-y-1">
        <p>Retrouvez vos rendez-vous, factures et le carnet de votre animal sur PetsMatch.</p>
        <p className="space-x-3">
          <Link href="/inscription" className="font-semibold text-[#0C5C6C]">Créer un compte</Link>
          <a href={STORE_ANDROID} target="_blank" rel="noopener noreferrer" className="font-semibold text-[#0C5C6C]">Android</a>
          <a href={STORE_IOS} target="_blank" rel="noopener noreferrer" className="font-semibold text-[#0C5C6C]">iPhone</a>
        </p>
      </div>
    </div>
  );
}
