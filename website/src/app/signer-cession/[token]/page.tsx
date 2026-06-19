'use client';

import { useEffect, useRef, useState } from 'react';
import { supabase } from '@/lib/supabase';

interface Cession {
  id: string;
  token: string;
  statut: string;
  nom_acquereur: string;
  email_acquereur?: string;
  prix?: number;
  date_cession?: string;
  notes?: string;
  contrat_url?: string;
  signature_acquereur?: string;
  animal: {
    nom?: string;
    espece?: string;
    race?: string;
    sexe?: string;
    identification?: string;
    date_naissance?: string;
  };
  eleveur: {
    nom: string;
    adresse?: string;
    email?: string;
    siret?: string;
  };
}

export default function SignerCessionPage({ params }: { params: { token: string } }) {
  const [cession, setCession] = useState<Cession | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError]     = useState('');
  const [signed, setSigned]   = useState(false);
  const [signing, setSigning] = useState(false);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const padRef    = useRef<unknown>(null);

  useEffect(() => {
    load();
  }, [params.token]);

  useEffect(() => {
    if (!cession || signed) return;
    // Charger signature_pad depuis CDN
    const s = document.createElement('script');
    s.src = 'https://cdn.jsdelivr.net/npm/signature_pad@4.1.7/dist/signature_pad.umd.min.js';
    s.onload = () => {
      if (canvasRef.current && (window as unknown as { SignaturePad: new (c: HTMLCanvasElement, o: object) => unknown }).SignaturePad) {
        const SP = (window as unknown as { SignaturePad: new (c: HTMLCanvasElement, o: object) => unknown }).SignaturePad;
        padRef.current = new SP(canvasRef.current, { backgroundColor: 'rgba(0,0,0,0)', penColor: '#1F2A2E', minWidth: 1, maxWidth: 2.5 });
        resizeCanvas();
      }
    };
    document.head.appendChild(s);
    return () => { document.head.removeChild(s); };
  }, [cession, signed]);

  function resizeCanvas() {
    const c = canvasRef.current;
    if (!c) return;
    const ratio = Math.max(window.devicePixelRatio || 1, 1);
    c.width  = c.offsetWidth * ratio;
    c.height = c.offsetHeight * ratio;
    c.getContext('2d')?.scale(ratio, ratio);
  }

  async function load() {
    try {
      const { data, error: e } = await supabase
        .from('cessions')
        .select(`*, animaux!animal_id(nom, espece, race, sexe, identification, date_naissance), users!uid_eleveur(firstname, lastname, name_elevage, is_elevage, adress_elevage, adress, siret, email)`)
        .eq('token', params.token)
        .maybeSingle();

      if (e || !data) { setError('Lien invalide ou expiré.'); return; }
      if (data.statut === 'confirme') { setSigned(true); }

      const animalData = (data as Record<string, unknown>).animaux as Record<string, unknown> || {};
      const userData   = (data as Record<string, unknown>).users   as Record<string, unknown> || {};
      const isElv = userData.is_elevage === true;
      const eleveurNom = isElv
        ? ((userData.name_elevage as string) || `${userData.firstname ?? ''} ${userData.lastname ?? ''}`.trim())
        : `${userData.firstname ?? ''} ${userData.lastname ?? ''}`.trim();

      setCession({
        id:              data.id,
        token:           data.token,
        statut:          data.statut,
        nom_acquereur:   data.nom_acquereur || '',
        email_acquereur: data.email_acquereur,
        prix:            data.prix,
        date_cession:    data.date_cession,
        notes:           data.notes,
        contrat_url:     data.contrat_url,
        signature_acquereur: data.signature_acquereur,
        animal:  { nom: animalData.nom as string, espece: animalData.espece as string, race: animalData.race as string, sexe: animalData.sexe as string, identification: animalData.identification as string, date_naissance: animalData.date_naissance as string },
        eleveur: { nom: eleveurNom, adresse: (isElv ? userData.adress_elevage : userData.adress) as string, email: userData.email as string, siret: userData.siret as string },
      });

      if (data.signature_acquereur) setSigned(true);
    } catch (err) {
      setError(`Erreur : ${err}`);
    } finally {
      setLoading(false);
    }
  }

  async function signer() {
    const pad = padRef.current as { isEmpty(): boolean; toDataURL(t: string): string } | null;
    if (!pad || pad.isEmpty()) { alert('Veuillez signer dans le cadre avant de valider.'); return; }
    if (!cession) return;
    setSigning(true);
    try {
      const sig = pad.toDataURL('image/png');
      const { error: e } = await supabase.from('cessions').update({
        signature_acquereur:    sig,
        statut:                 'signe_acquereur',
        signed_acquereur_at:    new Date().toISOString(),
      }).eq('id', cession.id);
      if (e) throw e;

      // Notifier l'éleveur
      const { data: eleveurUser } = await supabase.from('users').select('uid').eq('email', cession.eleveur.email ?? '').maybeSingle();
      if (eleveurUser?.uid) {
        await supabase.from('notifications').insert({
          uid:   eleveurUser.uid,
          type:  'cession_signee_acquereur',
          title: `✍️ ${cession.nom_acquereur} a signé — ${cession.animal.nom ?? 'Animal'}`,
          body:  `L'acquéreur a signé le contrat de cession. Vous pouvez maintenant confirmer le transfert.`,
          data:  { animalId: cession.id, token: cession.token },
          read:  false,
        });
      }
      setSigned(true);
    } catch (err) {
      alert(`Erreur lors de la signature : ${err}`);
    } finally {
      setSigning(false);
    }
  }

  if (loading) return (
    <div className="min-h-screen flex items-center justify-center">
      <div className="animate-spin w-8 h-8 border-4 border-[#0C5C6C] border-t-transparent rounded-full" />
    </div>
  );

  if (error) return (
    <div className="min-h-screen flex items-center justify-center p-6">
      <div className="text-center max-w-sm">
        <div className="text-4xl mb-4">❌</div>
        <p className="text-lg font-bold text-gray-800">Lien invalide</p>
        <p className="text-gray-500 mt-2">{error}</p>
      </div>
    </div>
  );

  if (!cession) return null;

  const dn = cession.animal.date_naissance ? new Date(cession.animal.date_naissance).toLocaleDateString('fr-FR') : '';
  const prixStr = cession.prix && cession.prix > 0 ? `${cession.prix.toLocaleString('fr-FR')} €` : 'Gratuit';

  return (
    <div className="min-h-screen bg-gray-50 py-8 px-4">
      <div className="max-w-2xl mx-auto space-y-6">

        {/* Header */}
        <div className="bg-[#0C5C6C] text-white rounded-2xl p-6 text-center">
          <img src="/logo.png" alt="PetsMatch" className="h-8 mx-auto mb-3 opacity-90" onError={e => (e.currentTarget.style.display='none')} />
          <h1 className="text-xl font-bold font-galey">Contrat de cession</h1>
          <p className="text-sm opacity-80 mt-1">Signature électronique requise</p>
        </div>

        {signed ? (
          <div className="bg-green-50 border border-green-200 rounded-2xl p-6 text-center">
            <div className="text-5xl mb-3">✅</div>
            <h2 className="text-lg font-bold text-green-800 font-galey">Contrat signé</h2>
            <p className="text-sm text-green-700 mt-2">
              Merci {cession.nom_acquereur}. Votre signature a bien été enregistrée.<br />
              L&apos;éleveur recevra une notification et confirmera le transfert.
            </p>
          </div>
        ) : (
          <>
            {/* Récapitulatif */}
            <div className="bg-white rounded-2xl p-5 shadow-sm border border-gray-100 space-y-4">
              <h2 className="font-bold text-[#1F2A2E] font-galey">📋 Récapitulatif</h2>
              <div className="grid grid-cols-2 gap-3 text-sm">
                <Field label="Animal" value={`${cession.animal.nom ?? '—'} (${cession.animal.espece ?? '—'})`} />
                <Field label="Race" value={cession.animal.race ?? '—'} />
                {dn && <Field label="Né le" value={dn} />}
                <Field label="Puce" value={cession.animal.identification ?? '—'} />
                <Field label="Vendeur" value={cession.eleveur.nom} />
                <Field label="Acheteur" value={cession.nom_acquereur} />
                <Field label="Prix" value={prixStr} />
                {cession.date_cession && <Field label="Date" value={new Date(cession.date_cession).toLocaleDateString('fr-FR')} />}
              </div>
              {cession.notes && (
                <div className="bg-gray-50 rounded-xl p-3 text-sm text-gray-600">
                  <span className="font-semibold">Notes : </span>{cession.notes}
                </div>
              )}
              {cession.contrat_url && (
                <a href={cession.contrat_url} target="_blank" rel="noreferrer"
                  className="flex items-center gap-2 text-sm text-[#0C5C6C] hover:underline">
                  📄 Lire le contrat complet
                </a>
              )}
            </div>

            {/* Engagements */}
            <div className="bg-amber-50 border border-amber-200 rounded-2xl p-5 text-sm text-amber-800 space-y-2">
              <p className="font-bold">En signant ce document, vous confirmez :</p>
              <ul className="list-disc list-inside space-y-1 text-amber-700">
                <li>Avoir lu et accepté le contrat de cession</li>
                <li>Prendre l&apos;entière responsabilité de l&apos;animal dès la livraison</li>
                <li>Avoir été informé des conditions légales de détention</li>
                <li>Disposer des moyens pour assurer le bien-être de l&apos;animal</li>
              </ul>
            </div>

            {/* Zone de signature */}
            <div className="bg-white rounded-2xl p-5 shadow-sm border border-gray-100">
              <h2 className="font-bold text-[#1F2A2E] font-galey mb-1">✍️ Votre signature</h2>
              <p className="text-xs text-gray-400 mb-3">{cession.nom_acquereur} — Signez dans le cadre ci-dessous</p>
              <div className="border-2 border-dashed border-[#0C5C6C]/30 rounded-xl overflow-hidden bg-[#FAFCFF]">
                <canvas ref={canvasRef} style={{ width: '100%', height: '140px', touchAction: 'none', display: 'block' }} />
              </div>
              <button onClick={() => (padRef.current as { clear(): void } | null)?.clear()}
                className="mt-2 text-xs text-gray-400 hover:text-gray-600">
                ✕ Effacer
              </button>
            </div>

            {/* Bouton valider */}
            <button onClick={signer} disabled={signing}
              className="w-full bg-[#6E9E57] hover:bg-[#5a8a45] text-white font-bold py-4 rounded-2xl font-galey text-base transition-colors disabled:opacity-50">
              {signing ? '⏳ Enregistrement…' : '✅ Valider ma signature'}
            </button>

            <p className="text-center text-xs text-gray-400">
              Signature électronique simple · Valeur légale pour contrats non-contestés<br />
              Propulsé par <span className="text-[#0C5C6C]">PetsMatch</span>
            </p>
          </>
        )}
      </div>
    </div>
  );
}

function Field({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <span className="text-gray-400 text-xs">{label}</span>
      <p className="font-semibold text-[#1F2A2E]">{value}</p>
    </div>
  );
}
