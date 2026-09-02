'use client';

import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';

interface Ident {
  nom?: string | null;
  siret?: string | null;
  rue_pro?: string | null;
  code_postal_pro?: string | null;
  ville_pro?: string | null;
}

const VERSION = 'PetsMatch — module de facturation v2 (2026)';

export default function AttestationPage() {
  const { user, userData } = useAuth();
  const activeProfileId = useActiveProfile();
  const [ident, setIdent] = useState<Ident | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!user) return;
    let q = supabase.from('user_profiles').select('nom, siret, rue_pro, code_postal_pro, ville_pro');
    q = activeProfileId ? q.eq('id', activeProfileId) : q.eq('uid', user.uid).eq('is_main', true);
    q.maybeSingle().then(({ data }) => { setIdent(data ?? null); setLoading(false); });
  }, [user, activeProfileId]);

  if (loading) return <div className="flex justify-center py-32 text-gray-400">Chargement…</div>;

  const nom = ident?.nom?.trim()
    || userData?.nameElevage
    || `${userData?.firstname ?? ''} ${userData?.lastname ?? ''}`.trim()
    || 'votre entreprise';
  const adresse = [ident?.rue_pro, [ident?.code_postal_pro, ident?.ville_pro].filter(Boolean).join(' ')]
    .filter(Boolean).join(', ');
  const dateJour = new Date().toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' });

  return (
    <div className="max-w-2xl mx-auto px-4 py-10">
      <div className="no-print flex items-center justify-between mb-6">
        <h1 className="text-xl font-bold text-[#1F2A2E]">Attestation de conformité</h1>
        <button onClick={() => window.print()}
          className="text-sm border border-gray-200 text-gray-600 px-4 py-2 rounded-xl hover:bg-gray-50">🖨️ Imprimer</button>
      </div>

      <div className="border border-gray-300 rounded-xl bg-white p-8 text-sm text-gray-800 leading-relaxed space-y-4">
        <div className="text-center border-b border-gray-200 pb-4">
          <p className="text-xs font-bold uppercase tracking-widest text-[#0C5C6C] mb-2">PetsMatch</p>
          <h2 className="text-lg font-bold text-[#1F2A2E]">
            Attestation individuelle de conformité du logiciel de facturation
          </h2>
          <p className="text-xs text-gray-400 mt-1">Article 286‑I‑3° bis du Code général des impôts</p>
        </div>

        <p>
          La société éditrice de l&apos;application <strong>PetsMatch</strong> atteste que le module de
          facturation mis à disposition de&nbsp;:
        </p>
        <div className="bg-gray-50 rounded-lg px-4 py-3">
          <p className="font-semibold">{nom}</p>
          {ident?.siret && <p className="text-gray-600">SIRET : {ident.siret}</p>}
          {adresse && <p className="text-gray-600">{adresse}</p>}
        </div>

        <p>
          satisfait aux conditions d&apos;<strong>inaltérabilité</strong>, de <strong>sécurisation</strong>,
          de <strong>conservation</strong> et d&apos;<strong>archivage</strong> des données prévues à
          l&apos;article 286‑I‑3° bis du CGI, dans les conditions suivantes&nbsp;:
        </p>
        <ul className="list-disc pl-5 space-y-1.5">
          <li>
            <strong>Inaltérabilité</strong> — toute facture émise est verrouillée&nbsp;: son contenu (lignes,
            montants, identités, date, numéro) ne peut plus être modifié ni supprimé. Toute correction est
            réalisée par l&apos;émission d&apos;une <strong>facture d&apos;avoir</strong> rattachée à la
            facture d&apos;origine.
          </li>
          <li>
            <strong>Numérotation</strong> — chaque facture reçoit un numéro unique dans une séquence
            chronologique continue et sans rupture, au format <code>AAAA‑NNNN</code>, attribué automatiquement
            par le serveur sous verrou transactionnel.
          </li>
          <li>
            <strong>Sécurisation &amp; traçabilité</strong> — chaque création et chaque changement de statut
            est inscrit dans un <strong>journal d&apos;audit en ajout seul</strong>, non modifiable et non
            supprimable, horodaté et associé à l&apos;auteur de l&apos;opération.
          </li>
          <li>
            <strong>Conservation &amp; archivage</strong> — le document PDF est <strong>figé au moment de
            l&apos;émission</strong>, stocké de façon pérenne, et son <strong>empreinte numérique (SHA‑256)</strong>
            est enregistrée pour permettre de vérifier à tout moment qu&apos;il n&apos;a pas été altéré. Les
            données sont conservées au moins 10 ans.
          </li>
        </ul>

        <p className="pt-2">
          La présente attestation est délivrée pour servir et valoir ce que de droit, et pourra être présentée
          à l&apos;administration fiscale en cas de contrôle.
        </p>

        <div className="flex justify-between items-end pt-6">
          <div className="text-xs text-gray-500">
            <p>Version du module&nbsp;: {VERSION}</p>
            <p>Délivrée le {dateJour}</p>
          </div>
          <div className="text-right">
            <p className="text-xs text-gray-400">Pour l&apos;éditeur</p>
            <p className="font-semibold text-[#0C5C6C]">PetsMatch</p>
          </div>
        </div>
      </div>

      <p className="no-print text-xs text-gray-400 mt-4">
        Ce document est généré automatiquement à partir de votre profil. Vérifiez que votre raison sociale,
        votre SIRET et votre adresse y sont exacts (rubrique « Facturation » de votre profil).
      </p>
    </div>
  );
}
