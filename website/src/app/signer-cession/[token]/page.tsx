'use client';

import { use, useEffect, useRef, useState } from 'react';
import { supabase } from '@/lib/supabase';

interface Cession {
  id: string;
  animal_id: string;
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

export default function SignerCessionPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = use(params);
  const [cession, setCession] = useState<Cession | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError]     = useState('');
  const [signed, setSigned]   = useState(false);
  const [signing, setSigning] = useState(false);
  const [confirmed, setConfirmed] = useState(false);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const padRef    = useRef<unknown>(null);

  useEffect(() => {
    load();
  }, [token]);

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
        .eq('token', token)
        .maybeSingle();

      if (e || !data) { setError('Lien invalide ou expiré.'); return; }
      if (data.statut === 'confirme') { setSigned(true); setConfirmed(true); }

      const animalData = (data as Record<string, unknown>).animaux as Record<string, unknown> || {};
      const userData   = (data as Record<string, unknown>).users   as Record<string, unknown> || {};
      const isElv = userData.is_elevage === true;
      const eleveurNom = isElv
        ? ((userData.name_elevage as string) || `${userData.firstname ?? ''} ${userData.lastname ?? ''}`.trim())
        : `${userData.firstname ?? ''} ${userData.lastname ?? ''}`.trim();

      setCession({
        id:              data.id,
        animal_id:       data.animal_id,
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
          data:  { animalId: cession.animal_id, token: cession.token },
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

  function handlePrint() {
    const sigImgHtml = cession!.signature_acquereur
      ? `<img src="${cession!.signature_acquereur}" style="max-height:70px;max-width:100%;object-fit:contain;display:block;margin:4px auto">`
      : '<span style="font-size:10px;color:#aaa;font-style:italic">Signature manuscrite</span>';
    const vendeurHtml = confirmed
      ? `<div style="padding:10px;text-align:center"><p style="font-size:22px;margin:0">✅</p><p style="font-size:11px;color:#166534;font-weight:bold;margin:4px 0">Cession confirmée</p><p style="font-size:10px;color:#166534;margin:0">Transfert de propriété effectif</p></div>`
      : `<div style="padding:10px;text-align:center"><p style="font-size:22px;margin:0">⏳</p><p style="font-size:11px;color:#92400e;font-weight:bold;margin:4px 0">En attente de confirmation</p></div>`;

    const printHtml = `<!DOCTYPE html>
<html lang="fr"><head><meta charset="UTF-8">
<title>Contrat de cession — ${cession!.animal.nom ?? 'animal'}</title>
<style>
@page{size:A4;margin:15mm 20mm}
*,*::before,*::after{-webkit-print-color-adjust:exact!important;print-color-adjust:exact!important;box-sizing:border-box}
body{font-family:Arial,sans-serif;font-size:12px;color:#1F2A2E;margin:0;line-height:1.6}
h1{font-size:18px;text-align:center;color:#0C5C6C;margin:0 0 4px}
h2{font-size:13px;color:#0C5C6C;margin:20px 0 10px;border-bottom:1px solid #e5e7eb;padding-bottom:4px}
.header{text-align:center;padding-bottom:12px;margin-bottom:16px;border-bottom:2px solid #0C5C6C}
.grid{display:flex;flex-wrap:wrap;gap:6px 20px;margin-bottom:12px}
.field{flex:1;min-width:200px}
.field-label{font-size:10px;color:#888;margin-bottom:1px}
.field-value{font-weight:bold}
.notes{background:#f8f8f8;border:1px solid #eee;border-radius:4px;padding:8px 12px;margin:8px 0;font-size:11px}
.sig-section{page-break-inside:avoid;break-inside:avoid;margin-top:20px}
.sig-row{display:flex;gap:20px}
.sig-block{flex:1;border:1px solid #ddd;border-radius:8px;padding:12px;text-align:center;page-break-inside:avoid;break-inside:avoid}
.sig-label{font-size:10px;font-weight:bold;text-transform:uppercase;color:#0C5C6C;margin-bottom:2px}
.sig-name{font-size:11px;color:#555;margin-bottom:6px}
.sig-img{min-height:70px;border-bottom:1px solid #ccc;display:flex;align-items:center;justify-content:center;margin-bottom:4px;padding:4px}
.sig-note{font-size:9px;color:#888;margin-top:2px}
.status{text-align:center;padding:6px 14px;border-radius:6px;font-size:11px;font-weight:bold;margin-bottom:14px}
.status-ok{background:#dcfce7;color:#166534;border:1px solid #bbf7d0}
.status-wait{background:#fef9c3;color:#92400e;border:1px solid #fde68a}
.foot{font-size:9px;color:#aaa;text-align:center;margin-top:20px}
</style>
</head><body>
<div class="header">
  <h1>Contrat de cession</h1>
  <p style="font-size:10px;color:#666;margin:2px 0">PetsMatch — Signature électronique</p>
  <div class="status ${confirmed ? 'status-ok' : 'status-wait'}" style="margin-top:10px">
    ${confirmed ? '✅ Cession confirmée — transfert de propriété effectif' : '⏳ Signature acquéreur enregistrée — en attente de confirmation vendeur'}
  </div>
</div>
<h2>Informations</h2>
<div class="grid">
  <div class="field"><div class="field-label">Animal</div><div class="field-value">${cession!.animal.nom ?? '—'} (${cession!.animal.espece ?? '—'})</div></div>
  <div class="field"><div class="field-label">Race</div><div class="field-value">${cession!.animal.race ?? '—'}</div></div>
  ${dn ? `<div class="field"><div class="field-label">Né(e) le</div><div class="field-value">${dn}</div></div>` : ''}
  <div class="field"><div class="field-label">Identification</div><div class="field-value">${cession!.animal.identification ?? '—'}</div></div>
  <div class="field"><div class="field-label">Vendeur</div><div class="field-value">${cession!.eleveur.nom}</div></div>
  <div class="field"><div class="field-label">Acheteur</div><div class="field-value">${cession!.nom_acquereur}</div></div>
  <div class="field"><div class="field-label">Prix</div><div class="field-value">${prixStr}</div></div>
  ${cession!.date_cession ? `<div class="field"><div class="field-label">Date</div><div class="field-value">${new Date(cession!.date_cession).toLocaleDateString('fr-FR')}</div></div>` : ''}
</div>
${cession!.notes ? `<div class="notes"><strong>Notes : </strong>${cession!.notes}</div>` : ''}
<div class="sig-section">
  <h2 style="margin-top:0">Signatures</h2>
  <div class="sig-row">
    <div class="sig-block">
      <div class="sig-label">Acquéreur</div>
      <div class="sig-name">${cession!.nom_acquereur}</div>
      <div class="sig-img">${sigImgHtml}</div>
      <div class="sig-note">✅ Signature électronique validée</div>
    </div>
    <div class="sig-block">
      <div class="sig-label">Vendeur</div>
      <div class="sig-name">${cession!.eleveur.nom}</div>
      <div class="sig-img">${vendeurHtml}</div>
      <div class="sig-note">${confirmed ? '✅ Cession confirmée' : '⏳ En attente de confirmation'}</div>
    </div>
  </div>
</div>
<div class="foot">Document généré par PetsMatch · Signature électronique simple · Réf. ${cession!.id}</div>
<script>window.addEventListener('load',function(){setTimeout(function(){window.print();},400)});<\/script>
</body></html>`;

    const win = window.open('', '_blank', 'width=900,height=1100');
    if (!win) return;
    win.document.write(printHtml);
    win.document.close();
  }

  return (
    <div className="min-h-screen bg-gray-50 py-8 px-4">
      <div className="max-w-2xl mx-auto space-y-6">

        {/* Header */}
        <div className="bg-[#0C5C6C] text-white rounded-2xl p-6 text-center">
          <img src="/logo.png" alt="PetsMatch" className="h-8 mx-auto mb-3 opacity-90" onError={e => (e.currentTarget.style.display='none')} />
          <h1 className="text-xl font-bold font-galey">Contrat de cession</h1>
          <p className="text-sm opacity-80 mt-1">Signature électronique requise</p>
        </div>

        {/* Bandeau statut */}
        {signed && (
          <div className={`rounded-2xl p-4 text-center text-sm font-semibold ${confirmed ? 'bg-green-600 text-white' : 'bg-green-50 border border-green-200 text-green-800'}`}>
            {confirmed
              ? '✅ Cession confirmée — le transfert de propriété est effectif'
              : '✅ Signature enregistrée — en attente de confirmation par le vendeur'}
          </div>
        )}

        {signed ? (
          <>
            {/* Récapitulatif — toujours visible */}
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

            {/* Signatures des deux parties */}
            <div className="bg-white rounded-2xl p-5 shadow-sm border border-gray-100">
              <h2 className="font-bold text-[#1F2A2E] font-galey mb-4">✍️ Signatures</h2>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
                {/* Signature acquéreur */}
                <div>
                  <p className="text-xs text-gray-500 mb-1 font-semibold">Acquéreur — {cession.nom_acquereur}</p>
                  {cession.signature_acquereur ? (
                    <div className="border border-green-200 rounded-xl overflow-hidden bg-green-50 p-2">
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img src={cession.signature_acquereur} alt="Signature acquéreur"
                        className="w-full h-20 object-contain" />
                      <p className="text-[10px] text-green-700 text-center mt-1 font-medium">✅ Signature électronique validée</p>
                    </div>
                  ) : (
                    <div className="border border-dashed border-gray-200 rounded-xl h-24 flex items-center justify-center">
                      <p className="text-xs text-gray-400">En attente de signature</p>
                    </div>
                  )}
                </div>
                {/* Signature / confirmation vendeur */}
                <div>
                  <p className="text-xs text-gray-500 mb-1 font-semibold">Vendeur — {cession.eleveur.nom}</p>
                  {confirmed ? (
                    <div className="border border-green-200 rounded-xl bg-green-50 p-3 h-24 flex flex-col items-center justify-center gap-1">
                      <p className="text-2xl">✅</p>
                      <p className="text-xs text-green-700 font-semibold text-center">Cession confirmée</p>
                      <p className="text-[10px] text-green-600 text-center">Transfert de propriété effectif</p>
                    </div>
                  ) : (
                    <div className="border border-dashed border-amber-200 rounded-xl bg-amber-50 p-3 h-24 flex flex-col items-center justify-center gap-1">
                      <p className="text-2xl">⏳</p>
                      <p className="text-xs text-amber-700 font-semibold text-center">En attente de confirmation</p>
                      <p className="text-[10px] text-amber-600 text-center">Le vendeur confirmera le transfert</p>
                    </div>
                  )}
                </div>
              </div>
            </div>

            <button onClick={handlePrint}
              className="w-full border border-[#0C5C6C] text-[#0C5C6C] font-semibold py-3 rounded-2xl text-sm hover:bg-[#0C5C6C]/5 transition-colors">
              🖨️ Imprimer / Sauvegarder en PDF
            </button>
          </>
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
