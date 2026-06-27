'use client';

import { useEffect } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';

const ESPECE_EMOJI: Record<string, string> = {
  chien: '🐕', chat: '🐈', cheval: '🐴', lapin: '🐰',
  oiseau: '🦜', nac: '🦎', ovin: '🐑', caprin: '🐐',
  porcin: '🐷', autre: '🐾',
};
const ESPECE_LABEL: Record<string, string> = {
  chien: 'Chien', chat: 'Chat', cheval: 'Cheval', lapin: 'Lapin',
  oiseau: 'Oiseau', nac: 'NAC', ovin: 'Ovin', caprin: 'Caprin',
  porcin: 'Porcin', autre: 'Autre',
};

export default function ProfilEleveurPage() {
  const { user, userData, loading } = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (!loading && !user) router.push('/connexion');
  }, [loading, user, router]);

  if (loading || !userData) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-teal-600" />
      </div>
    );
  }

  const avatar  = userData.profilePictureUrlElevage ?? userData.profilePictureUrl ?? null;
  const banner  = userData.bannerUrl ?? null;
  const fullName = `${userData.firstname ?? ''} ${userData.lastname ?? ''}`.trim();
  const nom     = userData.nameElevage ?? (fullName || 'Mon élevage');
  const ville   = userData.villeElevage ?? userData.ville ?? '';
  const cp      = userData.codePostalElevage ?? userData.codePostal ?? '';
  const rue     = userData.rueElevage ?? '';
  const desc    = userData.descriptionElevage ?? userData.descEntreprise ?? '';
  const tel     = userData.numeroElevage ?? userData.phone ?? '';
  const siret   = userData.siret ?? '';
  const acaced  = userData.acaced ?? '';
  const instagram = (userData.instagram as string | undefined) ?? '';
  const facebook  = (userData.facebook  as string | undefined) ?? '';
  const siteWeb   = (userData.siteWeb   as string | undefined) ?? '';
  const acacedDate = userData.acacedDateObtention ?? '';
  const isValidated = userData.isValidate === true;

  const especes = userData.especesElevees && userData.especesElevees.length > 0
    ? userData.especesElevees
    : [
        ...(userData.isDog ? [{ espece: 'chien', races: userData.dogBreeds ?? [] }] : []),
        ...(userData.isCat ? [{ espece: 'chat',  races: userData.catBreeds ?? [] }] : []),
      ];

  const siretOk  = siret.length >= 9;
  const acacedOk = !!acaced;
  const kbisOk   = !!userData.kbisUrl;
  const acacedDocOk = !!userData.acacedDocUrl;

  return (
    <div className="max-w-2xl mx-auto px-4 py-6">

      {/* Header */}
      <div className="flex items-center gap-3 mb-6">
        <Link href="/" className="text-gray-400 hover:text-gray-600 transition-colors">
          <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
          </svg>
        </Link>
        <h1 className="text-2xl font-bold text-gray-800" style={{ fontFamily: 'Galey, sans-serif' }}>
          Mon profil d&rsquo;élevage
        </h1>
      </div>

      {/* Bannière + Avatar */}
      <div className="relative rounded-2xl overflow-hidden mb-4">
        <div className="h-36 bg-gradient-to-br from-teal-100 to-green-100">
          {banner && (
            <Image src={banner} alt="Bannière" fill className="object-cover" sizes="672px" />
          )}
        </div>
        <div className="absolute -bottom-8 left-5">
          <div className="w-16 h-16 rounded-full border-3 border-white shadow-md overflow-hidden bg-teal-100 flex items-center justify-center">
            {avatar
              ? <Image src={avatar} alt={nom} width={64} height={64} className="object-cover w-full h-full" />
              : <span className="text-teal-600 font-bold text-xl">{nom[0]?.toUpperCase()}</span>
            }
          </div>
        </div>
      </div>

      {/* Nom + Ville */}
      <div className="mt-10 mb-4">
        <h2 className="text-xl font-bold text-gray-900" style={{ fontFamily: 'Galey, sans-serif' }}>{nom}</h2>
        {ville && <p className="text-sm text-gray-500 mt-0.5">📍 {[ville, cp].filter(Boolean).join(' ')}</p>}
      </div>

      {/* Badge validation */}
      {isValidated ? (
        <div className="flex items-center gap-2 bg-green-50 border border-green-200 rounded-xl px-4 py-2.5 mb-4 text-sm text-green-700 font-medium">
          <span className="text-green-500 text-base">✓</span>
          Profil validé — visible sur PetsMatch
        </div>
      ) : (
        <div className="flex items-center gap-2 bg-amber-50 border border-amber-200 rounded-xl px-4 py-2.5 mb-4 text-sm text-amber-700 font-medium">
          <span className="text-base">⏳</span>
          En attente de validation par l&rsquo;équipe PetsMatch
        </div>
      )}

      {/* Espèces élevées */}
      {especes.length > 0 && (
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4 mb-3">
          <h3 className="text-xs font-bold text-gray-400 uppercase tracking-wider mb-3">Espèces élevées</h3>
          <div className="flex flex-wrap gap-2">
            {especes.map(e => (
              <div key={e.espece} className="bg-teal-50 border border-teal-100 rounded-xl px-3 py-1.5 text-sm">
                <span className="mr-1">{ESPECE_EMOJI[e.espece] ?? '🐾'}</span>
                <span className="font-medium text-teal-800">{ESPECE_LABEL[e.espece] ?? e.espece}</span>
                {e.races && e.races.length > 0 && (
                  <span className="text-teal-500 ml-1 text-xs">· {e.races.slice(0, 3).join(', ')}{e.races.length > 3 ? '…' : ''}</span>
                )}
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Description */}
      {desc && (
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4 mb-3">
          <h3 className="text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">Description</h3>
          <p className="text-sm text-gray-700 leading-relaxed whitespace-pre-line">{desc}</p>
        </div>
      )}

      {/* Réseaux sociaux */}
      {(instagram || facebook || siteWeb) && (
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4 mb-3">
          <h3 className="text-xs font-bold text-gray-400 uppercase tracking-wider mb-3">Réseaux sociaux</h3>
          <div className="flex flex-wrap gap-2">
            {instagram && (
              <a
                href={instagram.startsWith('http') ? instagram : `https://instagram.com/${instagram.replace('@', '')}`}
                target="_blank" rel="noopener noreferrer"
                className="flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-semibold border"
                style={{ color: '#E1306C', borderColor: '#E1306C33', background: '#E1306C12' }}
              >
                📸 {instagram.startsWith('@') ? instagram : `@${instagram.replace(/^https?:\/\/(www\.)?instagram\.com\//, '')}`}
              </a>
            )}
            {facebook && (
              <a
                href={facebook.startsWith('http') ? facebook : `https://facebook.com/${facebook}`}
                target="_blank" rel="noopener noreferrer"
                className="flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-semibold border"
                style={{ color: '#1877F2', borderColor: '#1877F233', background: '#1877F212' }}
              >
                👥 Facebook
              </a>
            )}
            {siteWeb && (
              <a
                href={siteWeb.startsWith('http') ? siteWeb : `https://${siteWeb}`}
                target="_blank" rel="noopener noreferrer"
                className="flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-semibold border"
                style={{ color: '#0C5C6C', borderColor: '#0C5C6C33', background: '#0C5C6C12' }}
              >
                🌐 Site web
              </a>
            )}
          </div>
        </div>
      )}

      {/* Coordonnées */}
      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4 mb-3">
        <h3 className="text-xs font-bold text-gray-400 uppercase tracking-wider mb-3">Coordonnées</h3>
        <div className="space-y-2">
          {tel && (
            <div className="flex items-center gap-3 text-sm text-gray-700">
              <span className="w-6 text-center text-base">📞</span>
              <span>{tel}</span>
            </div>
          )}
          {(rue || ville) && (
            <div className="flex items-start gap-3 text-sm text-gray-700">
              <span className="w-6 text-center text-base">📍</span>
              <span>{[rue, [cp, ville].filter(Boolean).join(' ')].filter(Boolean).join(', ')}</span>
            </div>
          )}
          {!tel && !rue && !ville && (
            <p className="text-sm text-gray-400 italic">Aucune coordonnée renseignée</p>
          )}
        </div>
      </div>

      {/* Certifications */}
      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4 mb-6">
        <h3 className="text-xs font-bold text-gray-400 uppercase tracking-wider mb-3">Certifications</h3>
        <div className="space-y-2.5">
          <CertRow label="SIRET" value={siretOk ? `${siret.slice(0, 3)} ${siret.slice(3, 6)} ${siret.slice(6, 9)}…` : '—'} ok={siretOk} />
          <CertRow label="Justificatif SIRET" ok={kbisOk} />
          <CertRow label="N° ACACED" value={acacedOk ? acaced : '—'} ok={acacedOk} />
          {acacedDate && <CertRow label="Date obtention ACACED" value={new Date(acacedDate).toLocaleDateString('fr-FR')} ok={true} />}
          <CertRow label="Certificat ACACED" ok={acacedDocOk} />
        </div>
        {(!siretOk || !acacedOk || !kbisOk || !acacedDocOk) && (
          <p className="text-xs text-amber-600 mt-3">
            Des informations sont manquantes. Complétez votre profil pour accélérer la validation.
          </p>
        )}
      </div>

      {/* Actions */}
      <div className="flex flex-col gap-3">
        <Link href="/elevage/profil/edit"
          className="flex items-center justify-center gap-2 bg-[#0C5C6C] hover:bg-[#094F5D] text-white font-semibold text-sm py-3.5 rounded-2xl transition-colors shadow-sm">
          ✏️ Modifier mon profil
        </Link>
        {isValidated && user && (
          <Link href={`/elevages/${user.uid}`}
            className="flex items-center justify-center gap-2 border border-[#0C5C6C] text-[#0C5C6C] hover:bg-teal-50 font-semibold text-sm py-3.5 rounded-2xl transition-colors">
            👁 Voir mon profil public
          </Link>
        )}
      </div>

    </div>
  );
}

function CertRow({ label, value, ok }: { label: string; value?: string; ok: boolean }) {
  return (
    <div className="flex items-center gap-3 text-sm">
      <span className={`w-5 h-5 rounded-full flex items-center justify-center text-xs flex-shrink-0 ${ok ? 'bg-green-100 text-green-600' : 'bg-red-50 text-red-400'}`}>
        {ok ? '✓' : '✗'}
      </span>
      <span className="text-gray-500 flex-1">{label}</span>
      {value && <span className="text-gray-700 font-medium">{value}</span>}
    </div>
  );
}
