'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { clientDuSejour } from '@/lib/client-pension';
import type { PensionEntree } from '@/components/PensionEntreeModal';
import { type TarifsPension } from '@/lib/pension-especes';
import { nuitsSejour, sejoursMemeClient, tarifPensionSuggere } from '@/lib/pension-facture-groupee';
import { type PensionFactureEmetteur } from '@/lib/pension-facture-html';

const TEAL = '#0C5C6C';

function fmt(v: number) { return `${v.toFixed(2).replace('.', ',')} €`; }
const num = (v: string) => parseFloat(v.replace(',', '.')) || 0;

/** Séjour d'un autre animal du même client, ajoutable à la facture. */
interface AutreSejour { entree: Record<string, unknown>; nuits: string; tarif: string; reduction: string; inclus: boolean }

export function PensionFacturationModal({ entree, proProfileId, pensionNom, onClose, acompte, retour }: {
  entree: PensionEntree;
  proProfileId: string | null;
  pensionNom: string;
  onClose: () => void;
  /** Arrhes à la réservation : facture d'acompte pré-cochée, au pourcentage donné. */
  acompte?: number | null;
  /** Page où revenir après l'émission de la facture (ex. /pension/sejours). */
  retour?: string;
}) {
  const router = useRouter();
  const dateEntree = entree.date_entree ? new Date(entree.date_entree) : null;
  const dateSortie = entree.date_sortie_effective
    ? new Date(entree.date_sortie_effective)
    : (entree.date_sortie_prevue ? new Date(entree.date_sortie_prevue) : new Date());
  const nuitsInitiales = dateEntree
    ? Math.max(1, Math.round((dateSortie.getTime() - dateEntree.getTime()) / 86400000))
    : 1;

  const [tarif, setTarif] = useState('');
  const [nbNuits, setNbNuits] = useState(String(nuitsInitiales));
  const [suppDesc, setSuppDesc] = useState('');
  const [suppMontant, setSuppMontant] = useState('');
  const [avecTVA, setAvecTVA] = useState(false);
  const [isAcompte, setIsAcompte] = useState(!!acompte);
  const [acomptePct, setAcomptePct] = useState(acompte ? String(acompte) : '30');
  const [error, setError] = useState('');
  const [emetteur, setEmetteur] = useState<PensionFactureEmetteur | null>(null);
  const [reduction, setReduction] = useState('');
  const [autres, setAutres] = useState<AutreSejour[]>([]);

  // Tarification automatisée — pré-remplit le tarif/nuit suggéré à partir de
  // la config du pro (prix par espèce + réduction séjour long), reste
  // librement modifiable ensuite. N'écrase jamais une saisie déjà en cours.
  useEffect(() => {
    (async () => {
      if (!proProfileId) return;
      const { data: profil } = await supabase.from('user_profiles_complet')
        .select('tarifs_pension, nom, rue_pro, code_postal_pro, ville_pro, pays_pro, siret, numero_tva, phone_number')
        .eq('id', proProfileId).maybeSingle();
      if (profil) {
        const adresse = [profil.rue_pro, [profil.code_postal_pro, profil.ville_pro].filter(Boolean).join(' '), profil.pays_pro || 'France']
          .filter(Boolean).join(', ');
        setEmetteur({
          nom: profil.nom || pensionNom,
          adresse: adresse || null,
          siret: profil.siret || null,
          tva: profil.numero_tva || null,
          tel: profil.phone_number || null,
        });
      }
      const config = profil?.tarifs_pension as TarifsPension | null;
      // Essai facturé : prix de l'essai (Tarifs), une journée.
      const essaiCfg = (config as { essai?: { facture?: boolean; prix?: number | null } } | null)?.essai;
      if ((entree as { essai?: boolean }).essai && essaiCfg?.facture && (essaiCfg.prix ?? 0) > 0) {
        setTarif(prev => prev === '' ? Number(essaiCfg.prix).toFixed(2) : prev);
        setNbNuits('1');
      }
      // Plein tarif (espèce + logement attribué) + réduction long séjour à part.
      // Essai facturé à son prix : celui-ci ; sinon (essai non facturé dans
      // Tarifs mais facturé quand même) : le tarif normal, comme au contrat.
      const essaiPrix = (entree as { essai?: boolean }).essai && essaiCfg?.facture && (essaiCfg.prix ?? 0) > 0;
      const sugg = essaiPrix ? null : await tarifPensionSuggere(supabase, entree as unknown as Record<string, unknown>, config, nuitsInitiales);
      if (sugg && sugg.prixNuit > 0) {
        setTarif(prev => prev === '' ? sugg.prixNuit.toFixed(2) : prev);
        setReduction(prev => prev === '' ? String(sugg.reductionPct || '') : prev);
      }
      // Autres animaux du même client présents sur la période : facture groupée.
      const autresSejours = await sejoursMemeClient(supabase, entree as unknown as Record<string, unknown>, proProfileId);
      const liste: AutreSejour[] = [];
      for (const x of autresSejours) {
        const n = nuitsSejour(x);
        const sx = await tarifPensionSuggere(supabase, x, config, n);
        liste.push({ entree: x, nuits: String(n), tarif: sx && sx.prixNuit > 0 ? sx.prixNuit.toFixed(2) : '',
          // Animaux du même client : inclus d'office (arrivée groupée, facture unique), décochables.
          reduction: sx?.reductionPct ? String(sx.reductionPct) : '', inclus: true });
      }
      setAutres(liste);
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [proProfileId, entree.id]);

  const tarifNum = parseFloat(tarif.replace(',', '.')) || 0;
  const nuitsNum = parseInt(nbNuits, 10) || 1;
  const suppNum = parseFloat(suppMontant.replace(',', '.')) || 0;
  const reductionNum = Math.min(100, Math.max(0, num(reduction)));
  // Pension d'un animal, réduction long séjour déduite (arrondie au centime).
  const pension = (tarifNuit: number, nuits: number, red: number) =>
    Math.round(tarifNuit * nuits * (1 - Math.min(100, Math.max(0, red)) / 100) * 100) / 100;
  const autresInclus = autres.filter(a => a.inclus);
  const sousTotal = pension(tarifNum, nuitsNum, reductionNum)
    + autresInclus.reduce((s, a) => s + pension(num(a.tarif), parseInt(a.nuits, 10) || 1, num(a.reduction)), 0) + suppNum;
  const tvaAmt = avecTVA ? sousTotal * 0.2 : 0;
  const total = sousTotal + tvaAmt;
  const pctNum = Math.min(100, Math.max(1, Math.round(parseFloat(acomptePct.replace(',', '.')) || 30)));
  // Montant réellement facturé : total du séjour, ou une fraction si c'est un acompte.
  const montantFacture = isAcompte ? Math.round(total * pctNum) / 100 : total;

  function fmtIso(iso?: string | null) {
    if (!iso) return '?';
    const [y, m, d] = iso.slice(0, 10).split('-');
    return `${d}/${m}/${y}`;
  }

  // Bascule vers le moteur de facturation commun (numérotation, PDF archivé,
  // envoi email + notification) — mêmes lignes que celles calculées ci-dessus
  // (pension/nuit, acompte, TVA…), déposées en sessionStorage le temps de la
  // navigation (voir /elevage/facturation).
  async function continuer() {
    if (tarifNum <= 0) { setError('Renseignez un tarif par nuit.'); return; }
    const dateSortie = entree.date_sortie_effective ?? entree.date_sortie_prevue;
    const tva = avecTVA ? 20 : 0;
    const groupe = autresInclus.length > 0;
    const noms = [entree.animal_nom ?? '', ...autresInclus.map(a => String(a.entree.animal_nom ?? ''))].filter(Boolean).join(', ');
    const desc = `Pension du ${fmtIso(entree.date_entree)} au ${fmtIso(dateSortie)}${groupe ? '' : ` — ${entree.animal_nom ?? ''}`}`;
    // Une ligne de pension par animal (section du PDF), réduction long séjour
    // en remise identifiable ; suppléments rattachés au 1er animal.
    const lignePension = (e: Record<string, unknown>, tarifNuit: number, nuits: number, red: number) => {
      const sortie = (e.date_sortie_effective ?? e.date_sortie_prevue) as string | null;
      return {
        description: `Pension du ${fmtIso(e.date_entree as string | null)} au ${fmtIso(sortie)}`,
        quantite: nuits, prixUnitaire: tarifNuit, tva,
        animalId: (e.animal_id as string | null) ?? null, animalNom: (e.animal_nom as string | null) ?? null,
        pensionEntreeId: String(e.id),
        ...(red > 0 ? { remise: red, remiseMotif: `Réduction long séjour (${nuits} nuit${nuits > 1 ? 's' : ''})` } : {}),
      };
    };
    const lignes = isAcompte
      ? [{ description: `Acompte ${pctNum}% — ${desc}${groupe ? ` — ${noms}` : ''}`, quantite: 1, prixUnitaire: montantFacture, tva,
          ...(groupe ? {} : { animalId: entree.animal_id ?? null, animalNom: entree.animal_nom ?? null }) }]
      : [
          lignePension(entree as unknown as Record<string, unknown>, tarifNum, nuitsNum, reductionNum),
          ...(suppNum > 0 ? [{ description: suppDesc.trim() || 'Suppléments', quantite: 1, prixUnitaire: suppNum, tva,
            animalId: entree.animal_id ?? null, animalNom: entree.animal_nom ?? null }] : []),
          ...autresInclus.map(a => lignePension(a.entree, num(a.tarif), parseInt(a.nuits, 10) || 1, num(a.reduction))),
        ];
    // Client du séjour (demande, sinon propriétaire de la fiche — profil exact).
    const c = await clientDuSejour(supabase, entree as unknown as Record<string, unknown>);
    const prefill = {
      nomClient: c.nom || (entree.proprietaire_nom ?? ''),
      prenomClient: c.prenom || undefined,
      emailClient: c.email || (entree.proprietaire_email ?? ''),
      telClient: c.tel || (entree.proprietaire_contact ?? ''),
      rueClient: c.rue || undefined, cpClient: c.cp || undefined, villeClient: c.ville || undefined,
      clientUid: c.uid ?? undefined, clientProfileId: c.profileId ?? undefined,
      sourceAnimalId: entree.animal_id ?? undefined,
      note: isAcompte
        ? `Total du séjour : ${fmt(total)} — solde de ${fmt(total - montantFacture)} facturé à la sortie.`
        : '',
      lignes,
      sourcePensionEntreeId: entree.id,
      // Après l'émission : retour à la page d'où la facture est partie.
      ...(retour?.startsWith('/') ? { retour } : {}),
    };
    try {
      sessionStorage.setItem('pm_facture_prefill', JSON.stringify(prefill));
    } catch { /* ignore */ }
    onClose();
    router.push('/elevage/facturation');
  }

  const inp: React.CSSProperties = {
    width: '100%', padding: '10px 12px', borderRadius: 8, border: '1px solid #d1d5db',
    fontFamily: 'Galey, sans-serif', fontSize: 14, boxSizing: 'border-box', background: 'white', outline: 'none',
  };
  const lbl: React.CSSProperties = { fontFamily: 'Galey, sans-serif', fontSize: 12, fontWeight: 600, color: '#6b7280', marginBottom: 4, display: 'block' };

  return (
    <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.5)', display: 'flex', alignItems: 'flex-end', justifyContent: 'center', zIndex: 1000 }}
      onClick={e => e.target === e.currentTarget && onClose()}>
      <div style={{ background: 'white', borderRadius: '24px 24px 0 0', width: '100%', maxWidth: 560, maxHeight: '90vh', overflowY: 'auto', padding: '20px 24px 32px' }}>
        <div style={{ display: 'flex', alignItems: 'center', marginBottom: 4 }}>
          <div style={{ flex: 1 }}>
            <h2 style={{ margin: 0, fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 17 }}>Facturation pension</h2>
            <p style={{ margin: 0, fontFamily: 'Galey, sans-serif', fontSize: 12, color: '#6b7280' }}>{entree.animal_nom} — {entree.proprietaire_nom ?? '—'}</p>
          </div>
          <button onClick={onClose} style={{ background: 'none', border: 'none', fontSize: 22, cursor: 'pointer', color: '#9ca3af' }}>×</button>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginTop: 16, marginBottom: 12 }}>
          <div>
            <label style={lbl}>Tarif par nuit (€)</label>
            <input style={inp} type="number" step="0.01" placeholder="25" value={tarif} onChange={e => setTarif(e.target.value)} />
          </div>
          <div>
            <label style={lbl}>Nombre de nuits</label>
            <input style={inp} type="number" value={nbNuits} onChange={e => setNbNuits(e.target.value)} />
          </div>
          <div>
            <label style={lbl}>Réduction long séjour (%)</label>
            <input style={inp} type="number" min={0} max={100} step="0.5" placeholder="0" value={reduction} onChange={e => setReduction(e.target.value)} />
          </div>
        </div>

        {autres.length > 0 && (
          <div style={{ border: '1px solid #e5e7eb', borderRadius: 10, padding: '10px 12px', marginBottom: 12 }}>
            <p style={{ margin: '0 0 6px', fontFamily: 'Galey, sans-serif', fontSize: 13, fontWeight: 700, color: '#374151' }}>
              Autres animaux de ce client sur la période
            </p>
            <p style={{ margin: '0 0 8px', fontFamily: 'Galey, sans-serif', fontSize: 11, color: '#6b7280' }}>
              Cochés : facturés sur la même facture, une section par animal.
            </p>
            {autres.map((a, i) => (
              <div key={String(a.entree.id)} style={{ marginBottom: 8 }}>
                <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer', fontFamily: 'Galey, sans-serif', fontSize: 13 }}>
                  <input type="checkbox" checked={a.inclus} onChange={e => setAutres(prev => prev.map((x, j) => j === i ? { ...x, inclus: e.target.checked } : x))} />
                  <span style={{ flex: 1 }}>{String(a.entree.animal_nom ?? 'Animal')} · du {fmtIso(a.entree.date_entree as string | null)} au {fmtIso((a.entree.date_sortie_effective ?? a.entree.date_sortie_prevue) as string | null)}</span>
                </label>
                {a.inclus && (
                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 8, marginTop: 6 }}>
                    {([['tarif', 'Tarif / nuit (€)'], ['nuits', 'Nuits'], ['reduction', 'Réduction (%)']] as const).map(([k, l]) => (
                      <div key={k}>
                        <label style={lbl}>{l}</label>
                        <input style={inp} type="number" step="0.01" value={a[k]}
                          onChange={e => setAutres(prev => prev.map((x, j) => j === i ? { ...x, [k]: e.target.value } : x))} />
                      </div>
                    ))}
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
        <div style={{ marginBottom: 8 }}>
          <label style={lbl}>Suppléments (optionnel)</label>
          <input style={inp} placeholder="Ex : Frais vétérinaires, médicaments…" value={suppDesc} onChange={e => setSuppDesc(e.target.value)} />
        </div>
        <div style={{ marginBottom: 16 }}>
          <label style={lbl}>Montant suppléments (€)</label>
          <input style={inp} type="number" step="0.01" placeholder="0" value={suppMontant} onChange={e => setSuppMontant(e.target.value)} />
        </div>

        <label style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '10px 12px', borderRadius: 10, border: `1px solid ${avecTVA ? TEAL + '4d' : '#e5e7eb'}`, background: avecTVA ? TEAL + '0d' : '#f9fafb', marginBottom: 10, cursor: 'pointer' }}>
          <input type="checkbox" checked={avecTVA} onChange={e => setAvecTVA(e.target.checked)} />
          <span style={{ fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#374151', flex: 1 }}>Assujetti à la TVA (20%)</span>
        </label>

        <div style={{ padding: '10px 12px', borderRadius: 10, border: `1px solid ${isAcompte ? TEAL + '4d' : '#e5e7eb'}`, background: isAcompte ? TEAL + '0d' : '#f9fafb', marginBottom: 16 }}>
          <label style={{ display: 'flex', alignItems: 'center', gap: 10, cursor: 'pointer' }}>
            <input type="checkbox" checked={isAcompte} onChange={e => setIsAcompte(e.target.checked)} />
            <span style={{ fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#374151', flex: 1 }}>Facture d&apos;acompte (réservation)</span>
          </label>
          {isAcompte && (
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginTop: 10 }}>
              <span style={{ fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#6b7280' }}>Pourcentage</span>
              <input style={{ ...inp, width: 90 }} type="number" min={1} max={100} value={acomptePct} onChange={e => setAcomptePct(e.target.value)} />
              <span style={{ fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#6b7280' }}>
                % · solde {fmt(total - montantFacture)} à la sortie
              </span>
            </div>
          )}
        </div>

        <div style={{ background: TEAL + '0a', border: `1px solid ${TEAL}26`, borderRadius: 12, padding: 14, marginBottom: 20 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#6b7280', marginBottom: 4 }}>
            <span>Pension{autresInclus.length ? ` ${entree.animal_nom ?? ''}` : ''} ({nuitsNum} nuit{nuitsNum > 1 ? 's' : ''} × {fmt(tarifNum)}){reductionNum > 0 ? ` − ${reductionNum} %` : ''}</span><span>{fmt(pension(tarifNum, nuitsNum, reductionNum))}</span>
          </div>
          {autresInclus.map(a => {
            const n = parseInt(a.nuits, 10) || 1;
            return (
              <div key={String(a.entree.id)} style={{ display: 'flex', justifyContent: 'space-between', fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#6b7280', marginBottom: 4 }}>
                <span>Pension {String(a.entree.animal_nom ?? '')} ({n} nuit{n > 1 ? 's' : ''} × {fmt(num(a.tarif))}){num(a.reduction) > 0 ? ` − ${num(a.reduction)} %` : ''}</span>
                <span>{fmt(pension(num(a.tarif), n, num(a.reduction)))}</span>
              </div>
            );
          })}
          {suppNum > 0 && (
            <div style={{ display: 'flex', justifyContent: 'space-between', fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#6b7280', marginBottom: 4 }}>
              <span>Suppléments</span><span>{fmt(suppNum)}</span>
            </div>
          )}
          <div style={{ borderTop: '1px solid #e5e7eb', margin: '10px 0' }} />
          {avecTVA && (
            <>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#6b7280', marginBottom: 4 }}>
                <span>Sous-total HT</span><span>{fmt(sousTotal)}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#6b7280', marginBottom: 8 }}>
                <span>TVA 20%</span><span>{fmt(tvaAmt)}</span>
              </div>
              <div style={{ borderTop: '1px solid #e5e7eb', margin: '8px 0' }} />
            </>
          )}
          <div style={{ display: 'flex', justifyContent: 'space-between', fontFamily: 'Galey, sans-serif', fontSize: isAcompte ? 13 : 15, fontWeight: isAcompte ? 400 : 700, color: isAcompte ? '#6b7280' : TEAL }}>
            <span>{avecTVA ? 'TOTAL TTC séjour' : 'TOTAL séjour'}</span><span>{fmt(total)}</span>
          </div>
          {isAcompte && (
            <>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#6b7280', margin: '4px 0' }}>
                <span>Solde restant à la sortie</span><span>{fmt(total - montantFacture)}</span>
              </div>
              <div style={{ borderTop: '1px solid #e5e7eb', margin: '8px 0' }} />
              <div style={{ display: 'flex', justifyContent: 'space-between', fontFamily: 'Galey, sans-serif', fontSize: 15, fontWeight: 700, color: TEAL }}>
                <span>Acompte {pctNum}% à facturer</span><span>{fmt(montantFacture)}</span>
              </div>
            </>
          )}
        </div>

        {(!emetteur?.siret || !emetteur?.adresse) && (
          <p style={{ background: '#FEF3C7', color: '#92400E', fontFamily: 'Galey, sans-serif', fontSize: 12, padding: '8px 10px', borderRadius: 8, marginBottom: 12 }}>
            Votre adresse et votre SIRET doivent figurer sur la facture. Complétez-les dans votre profil pro.
          </p>
        )}

        {error && <p style={{ color: '#dc2626', fontFamily: 'Galey, sans-serif', fontSize: 13, marginBottom: 12 }}>{error}</p>}

        <button onClick={continuer} disabled={tarifNum <= 0} style={{
          width: '100%', padding: '13px 0', background: TEAL, color: 'white', border: 'none', borderRadius: 12,
          fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 14,
          cursor: tarifNum <= 0 ? 'not-allowed' : 'pointer',
          opacity: tarifNum <= 0 ? 0.6 : 1, marginBottom: 10,
        }}>
          Continuer vers la facture →
        </button>
      </div>
    </div>
  );
}
