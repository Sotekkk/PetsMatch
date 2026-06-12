'use client';

import { use, useEffect, useState } from 'react';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

interface Cert {
  id: string;
  nom_animal: string;
  espece: string;
  race: string;
  date_naissance_animal: string;
  num_identification: string;
  acquereur_nom: string;
  acquereur_prenom: string;
  acquereur_email: string;
  acquereur_telephone: string;
  acquereur_adresse: string;
  modalite_cession: string;
  prix: number | null;
  date_remise: string;
  date_limite_signature: string | null;
  date_signature_acquereur: string | null;
  statut: string;
  token_signature: string;
  notes: string;
  cedant_uid: string;
}

interface Cedant {
  name_elevage: string;
  first_name: string;
  last_name: string;
  siret: string;
  phone: string;
  rue_elevage: string;
  ville_elevage: string;
  code_postal_elevage: string;
}

const ENGAGEMENTS = [
  'Répondre à ses besoins physiologiques (alimentation adaptée, eau fraîche, soins vétérinaires réguliers).',
  'Permettre l\'expression de ses comportements naturels (exercice, enrichissement, socialisation adaptée à l\'espèce).',
  'Le protéger de la souffrance, de l\'anxiété et de la peur.',
  'Lui assurer un environnement adapté (espace suffisant, température, abri, hygiène).',
  'Veiller à sa santé et son bien-être tout au long de sa vie.',
  'Prendre en compte sa durée de vie estimée et m\'y engager pour toute sa vie.',
  'Estimer et assumer les coûts annuels (alimentation, soins vétérinaires, assurance).',
  'Vérifier la compatibilité avec ma situation personnelle (logement, mode de vie, enfants, autres animaux).',
  'Ne jamais abandonner l\'animal et contacter le cédant en priorité en cas de difficulté.',
  'Respecter la législation en vigueur (identification obligatoire, vaccination antirabique si voyage, stérilisation recommandée).',
];

export default function CertificatPublicPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = use(params);
  const [cert, setCert] = useState<Cert | null>(null);
  const [cedant, setCedant] = useState<Cedant | null>(null);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);
  const [action, setAction] = useState<'idle' | 'signing' | 'refusing' | 'done_sign' | 'done_refuse' | 'error'>('idle');
  const [errorMsg, setErrorMsg] = useState('');
  const [delaiBloq, setDelaiBloq] = useState(false);
  const [joursRestants, setJoursRestants] = useState(0);

  useEffect(() => {
    supabase.from('certificats_engagement').select('*').eq('token_signature', token).maybeSingle()
      .then(async ({ data }) => {
        if (!data) { setNotFound(true); setLoading(false); return; }
        setCert(data as Cert);

        // Marquer comme "lu" si encore "envoye"
        if (data.statut === 'envoye') {
          await fetch('/api/certificat/sign', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ token: token, action: 'lu' }),
          });
        }

        // Vérifier délai légal
        if (data.date_limite_signature) {
          const now = new Date();
          const limite = new Date(data.date_limite_signature);
          if (now < limite) {
            setDelaiBloq(true);
            setJoursRestants(Math.ceil((limite.getTime() - now.getTime()) / 86400_000));
          }
        }

        // Charger le cédant
        const { data: ced } = await supabase.from('users').select('name_elevage,first_name,last_name,siret,phone,rue_elevage,ville_elevage,code_postal_elevage').eq('uid', data.cedant_uid).maybeSingle();
        setCedant(ced as Cedant | null);
        setLoading(false);
      });
  }, [token]);

  async function handleSign(actionType: 'signe' | 'refuse') {
    setAction(actionType === 'signe' ? 'signing' : 'refusing');
    const res = await fetch('/api/certificat/sign', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: token, action: actionType }),
    });
    const json = await res.json();
    if (!res.ok) {
      setErrorMsg(json.error ?? 'Erreur');
      setAction('error');
    } else {
      setAction(actionType === 'signe' ? 'done_sign' : 'done_refuse');
      setCert(prev => prev ? { ...prev, statut: actionType, date_signature_acquereur: actionType === 'signe' ? new Date().toISOString() : prev.date_signature_acquereur } : prev);
    }
  }

  if (loading) return <div className="flex justify-center py-32 text-gray-400">Chargement…</div>;
  if (notFound) return (
    <div className="flex flex-col items-center justify-center min-h-[60vh] gap-3">
      <span className="text-5xl">🔍</span>
      <p className="font-semibold text-gray-700">Certificat introuvable ou lien expiré.</p>
    </div>
  );

  const nomCedant = cedant?.name_elevage || `${cedant?.first_name ?? ''} ${cedant?.last_name ?? ''}`.trim();
  const adresseCedant = [cedant?.rue_elevage, cedant?.code_postal_elevage, cedant?.ville_elevage].filter(Boolean).join(', ');
  const dateRemise = new Date(cert!.date_remise).toLocaleDateString('fr-FR');
  const isSigned = cert!.statut === 'signe';
  const isRefused = cert!.statut === 'refuse';
  const isDone = isSigned || isRefused;

  return (
    <>
      {/* CSS impression */}
      <style>{`
        @media print {
          .no-print { display: none !important; }
          body { font-size: 11pt; }
          .print-page { max-width: 100%; padding: 0; }
        }
      `}</style>

      <div className="max-w-3xl mx-auto px-4 py-10 print-page">

        {/* Boutons actions — masqués à l'impression */}
        <div className="no-print flex items-center justify-between mb-6">
          <h1 className="text-xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
            Certificat d'Engagement et d'Information
          </h1>
          <button onClick={() => window.print()} className="text-sm border border-gray-200 text-gray-600 px-4 py-2 rounded-xl hover:bg-gray-50">
            🖨️ Imprimer / PDF
          </button>
        </div>

        {/* Statut */}
        {isSigned && (
          <div className="no-print mb-4 bg-green-50 border border-green-200 rounded-xl p-3 text-sm text-green-700 font-medium">
            ✅ Ce certificat a été signé le {new Date(cert!.date_signature_acquereur!).toLocaleDateString('fr-FR')}.
          </div>
        )}
        {isRefused && (
          <div className="no-print mb-4 bg-red-50 border border-red-200 rounded-xl p-3 text-sm text-red-700 font-medium">
            ❌ Ce certificat a été refusé.
          </div>
        )}
        {action === 'done_sign' && (
          <div className="no-print mb-4 bg-green-50 border border-green-200 rounded-xl p-3 text-sm text-green-700 font-semibold">
            ✅ Vous avez signé ce certificat. Le cédant en est informé.
          </div>
        )}
        {action === 'done_refuse' && (
          <div className="no-print mb-4 bg-amber-50 border border-amber-200 rounded-xl p-3 text-sm text-amber-700 font-semibold">
            Vous avez refusé ce certificat. Le cédant en est informé.
          </div>
        )}

        {/* Certificat */}
        <div className="border border-gray-300 rounded-xl p-8 bg-white text-sm text-gray-800 space-y-6">

          <div className="text-center border-b pb-4">
            <p className="text-xs font-bold uppercase tracking-widest text-gray-400 mb-1">PetsMatch</p>
            <h2 className="text-lg font-bold text-[#1F2A2E]">CERTIFICAT D'ENGAGEMENT ET D'INFORMATION</h2>
            <p className="text-xs text-gray-500 mt-1">Loi n° 2021-1539 du 30 novembre 2021 — Art. L. 214-8 Code Rural</p>
            <p className="text-xs text-gray-500">Date de remise : <strong>{dateRemise}</strong></p>
          </div>

          {/* A — Cédant */}
          <section>
            <h3 className="font-bold text-[#0C5C6C] mb-2 text-xs uppercase tracking-wide">A — Identification du cédant</h3>
            <div className="grid grid-cols-2 gap-1 text-xs">
              <span className="text-gray-500">Nom / Structure :</span><span className="font-medium">{nomCedant || '—'}</span>
              {cedant?.siret && <><span className="text-gray-500">SIRET :</span><span className="font-medium">{cedant.siret}</span></>}
              {adresseCedant && <><span className="text-gray-500">Adresse :</span><span className="font-medium">{adresseCedant}</span></>}
              {cedant?.phone && <><span className="text-gray-500">Téléphone :</span><span className="font-medium">{cedant.phone}</span></>}
            </div>
          </section>

          {/* B — Acquéreur */}
          <section>
            <h3 className="font-bold text-[#0C5C6C] mb-2 text-xs uppercase tracking-wide">B — Identification de l'acquéreur</h3>
            <div className="grid grid-cols-2 gap-1 text-xs">
              <span className="text-gray-500">Nom / Prénom :</span><span className="font-medium">{cert!.acquereur_prenom} {cert!.acquereur_nom}</span>
              <span className="text-gray-500">Email :</span><span className="font-medium">{cert!.acquereur_email}</span>
              {cert!.acquereur_telephone && <><span className="text-gray-500">Téléphone :</span><span className="font-medium">{cert!.acquereur_telephone}</span></>}
              {cert!.acquereur_adresse && <><span className="text-gray-500">Adresse :</span><span className="font-medium">{cert!.acquereur_adresse}</span></>}
            </div>
          </section>

          {/* C — Animal */}
          <section>
            <h3 className="font-bold text-[#0C5C6C] mb-2 text-xs uppercase tracking-wide">C — Identification de l'animal</h3>
            <div className="grid grid-cols-2 gap-1 text-xs">
              <span className="text-gray-500">Nom :</span><span className="font-medium">{cert!.nom_animal}</span>
              <span className="text-gray-500">Espèce / Race :</span><span className="font-medium">{cert!.espece}{cert!.race ? ` — ${cert!.race}` : ''}</span>
              {cert!.date_naissance_animal && <><span className="text-gray-500">Date de naissance :</span><span className="font-medium">{new Date(cert!.date_naissance_animal).toLocaleDateString('fr-FR')}</span></>}
              {cert!.num_identification && <><span className="text-gray-500">N° identification :</span><span className="font-medium">{cert!.num_identification}</span></>}
            </div>
          </section>

          {/* D — Cession */}
          <section>
            <h3 className="font-bold text-[#0C5C6C] mb-2 text-xs uppercase tracking-wide">D — Conditions de cession</h3>
            <div className="grid grid-cols-2 gap-1 text-xs">
              <span className="text-gray-500">Modalité :</span>
              <span className="font-medium capitalize">{cert!.modalite_cession === 'gratuit' ? 'Cession gratuite' : cert!.modalite_cession}</span>
              {cert!.prix != null && <><span className="text-gray-500">Prix :</span><span className="font-medium">{cert!.prix} €</span></>}
            </div>
          </section>

          {/* E — Engagements */}
          <section>
            <h3 className="font-bold text-[#0C5C6C] mb-2 text-xs uppercase tracking-wide">E — Engagements de l'acquéreur</h3>
            <p className="text-xs text-gray-700 mb-2 italic">
              Je soussigné(e) <strong>{cert!.acquereur_prenom} {cert!.acquereur_nom}</strong>, certifie avoir pris connaissance des besoins spécifiques de l'animal et m'engage à :
            </p>
            <ol className="list-decimal list-inside space-y-1 text-xs text-gray-700">
              {ENGAGEMENTS.map((e, i) => <li key={i}>{e}</li>)}
            </ol>
          </section>

          {/* F — Délai légal */}
          {cert!.date_limite_signature && (
            <section className="bg-amber-50 border border-amber-200 rounded-lg p-3">
              <h3 className="font-bold text-amber-800 mb-1 text-xs uppercase tracking-wide">F — Délai de réflexion légal</h3>
              <p className="text-xs text-amber-800">
                Pour les <strong>{cert!.espece}s</strong> : l'acquéreur dispose de <strong>7 jours calendaires</strong> à compter
                de la remise de ce certificat ({dateRemise}) avant de pouvoir le signer.
                Signature possible à partir du : <strong>{new Date(cert!.date_limite_signature).toLocaleDateString('fr-FR')}</strong>.
                Aucune somme ne peut être perçue pendant ce délai.
              </p>
            </section>
          )}

          {/* G — Signatures */}
          <section>
            <h3 className="font-bold text-[#0C5C6C] mb-3 text-xs uppercase tracking-wide">G — Signatures</h3>
            <div className="grid grid-cols-2 gap-6">
              <div className="border-t pt-3">
                <p className="text-xs text-gray-500 mb-1">Cédant ({nomCedant})</p>
                <p className="text-xs text-gray-700">Remis le {dateRemise}</p>
                <div className="mt-3 h-12 border-b border-dashed border-gray-300 flex items-end">
                  <p className="text-xs text-gray-400 pb-1">Signature électronique PetsMatch</p>
                </div>
              </div>
              <div className="border-t pt-3">
                <p className="text-xs text-gray-500 mb-1">Acquéreur ({cert!.acquereur_prenom} {cert!.acquereur_nom})</p>
                {isSigned ? (
                  <>
                    <p className="text-xs text-green-700">Signé le {new Date(cert!.date_signature_acquereur!).toLocaleDateString('fr-FR')}</p>
                    <div className="mt-3 h-12 border-b border-dashed border-green-300 flex items-end">
                      <p className="text-xs text-green-600 pb-1">✅ Signature électronique validée</p>
                    </div>
                  </>
                ) : (
                  <div className="mt-3 h-12 border-b border-dashed border-gray-300 flex items-end">
                    <p className="text-xs text-gray-400 pb-1">En attente de signature</p>
                  </div>
                )}
              </div>
            </div>
          </section>

          <p className="text-[10px] text-gray-400 text-center border-t pt-3">
            Document généré via PetsMatch · Référence : {cert!.id}
          </p>
        </div>

        {/* Boutons signature — masqués à l'impression */}
        {!isDone && action !== 'done_sign' && action !== 'done_refuse' && (
          <div className="no-print mt-6 bg-white border border-gray-200 rounded-xl p-5">
            {delaiBloq ? (
              <div className="text-center">
                <p className="text-sm font-semibold text-amber-700">⏳ Délai légal en cours</p>
                <p className="text-xs text-gray-500 mt-1">
                  Vous pourrez signer ce certificat dans <strong>{joursRestants} jour(s)</strong>.
                  Ce délai est imposé par la loi pour les {cert!.espece}s.
                </p>
              </div>
            ) : (
              <>
                <p className="text-sm text-gray-700 mb-4 text-center">
                  En cliquant sur <strong>"Je signe ce certificat"</strong>, vous confirmez avoir lu et accepté l'ensemble des engagements ci-dessus.
                </p>
                {action === 'error' && <p className="text-sm text-red-600 text-center mb-3">{errorMsg}</p>}
                <div className="flex gap-3">
                  <button onClick={() => handleSign('refuse')} disabled={action === 'refusing'}
                    className="flex-1 border border-gray-200 text-gray-600 font-medium py-3 rounded-xl text-sm hover:bg-gray-50 disabled:opacity-50">
                    {action === 'refusing' ? 'Traitement…' : 'Refuser'}
                  </button>
                  <button onClick={() => handleSign('signe')} disabled={action === 'signing'}
                    className="flex-1 bg-[#6E9E57] hover:bg-[#5d8a49] disabled:opacity-50 text-white font-semibold py-3 rounded-xl text-sm">
                    {action === 'signing' ? 'Signature…' : '✍️ Je signe ce certificat'}
                  </button>
                </div>
              </>
            )}
          </div>
        )}

      </div>
    </>
  );
}
