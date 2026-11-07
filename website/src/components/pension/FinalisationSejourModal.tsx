'use client';
// Pension — finalisation de l'arrivée ou du départ, par étapes (comme la fin
// de RDV des autres pros) :
//  1. Arrivée / départ enregistré (heure, logement).
//  2. Contrat d'hébergement : préparé, signé d'office avec la signature
//     enregistrée de la pension (signatures_pro), envoyé au client (appli si
//     compte + e-mail avec lien de signature sans compte). Au départ : état,
//     relance par e-mail si pas encore signé.
//  3. Facture : à l'arrivée (acompte ou séjour, selon le règlement réglé dans
//     Tarifs) ou au départ (séjour), via la fenêtre de facturation existante.
// Miroir appli : lib/pages/pro/pension_finalisation.dart.
import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { apiFetch } from '@/lib/api-fetch';
import { useAuth } from '@/lib/auth-context';
import { maSignaturePro, signerContratAvecSignaturePro } from '@/lib/signature-pro';
import { envoyerContratParEmail } from '@/lib/contrat-email';
import { sejoursFactures } from '@/lib/pension-facture-groupee';
import { PensionFacturationModal } from '@/components/PensionFacturationModal';
import type { PensionEntree } from '@/components/PensionEntreeModal';
import { ACCEPT_DOCUMENT_PRO, TYPE_CONTRAT_PRO, creerContratProSejour, fichierEnPdf } from '@/lib/document-pro';
import { clientDuSejour, nomComplet } from '@/lib/client-pension';

interface Contrat { id: string; token: string; statut: string; client_email: string | null; client_nom: string | null; client_a_compte: boolean; signe_pro: boolean; signe_client: boolean }

/** Pastille d'une étape : faite (coche verte) ou à faire (orange). */
function Pastille({ ok }: { ok: boolean }) {
  return (
    <span className="w-6 h-6 rounded-full flex items-center justify-center flex-shrink-0 text-xs font-bold"
      style={ok ? { background: '#E8F5EE', color: '#2E7D5E' } : { background: '#FFF4E5', color: '#B45309' }}>{ok ? '✓' : '!'}</span>
  );
}

export default function FinalisationSejourModal({ entree, mode, proProfileId, pensionNom, onClose, autresIds = [] }: {
  entree: PensionEntree & { arrivee_reelle_le?: string | null; depart_reel_le?: string | null };
  mode: 'arrivee' | 'depart'; proProfileId: string | null; pensionNom: string; onClose: () => void;
  /** Arrivée / départ groupé : autres séjours du même client (un seul contrat, facture groupée). */
  autresIds?: string[];
}) {
  const tousIds = [entree.id, ...autresIds.filter(i => i !== entree.id)];
  const cleIds = tousIds.join(',');
  const [nomsGroupe, setNomsGroupe] = useState<string[]>([]);
  const { user, userData } = useAuth();
  const [contrat, setContrat] = useState<Contrat | null>(null);
  const [etatContrat, setEtatContrat] = useState<'' | 'envoi' | 'ok' | 'erreur'>('');
  const [messageContrat, setMessageContrat] = useState('');
  const [parEmail, setParEmail] = useState(true);
  const [aSignature, setASignature] = useState<boolean | null>(null);
  const [facture, setFacture] = useState<boolean | null>(null);
  const [solde, setSolde] = useState<'arrivee' | 'depart'>('arrivee');
  const [arrhes, setArrhes] = useState<number | null>(null);
  const [facturer, setFacturer] = useState(false);
  const [logementNom, setLogementNom] = useState<string | null>(null);
  // Contrat de la pension : son modèle (Tarifs) ou un fichier chargé pour ce séjour.
  const [modele, setModele] = useState<{ url: string; nom: string } | null>(null);
  const [choixContrat, setChoixContrat] = useState<'petsmatch' | 'mien'>('petsmatch');
  const [fichier, setFichier] = useState<File | null>(null);

  const charger = useCallback(async () => {
    if (!user) return;
    const [{ data: doc }, sig, factures, { data: legacy }, { data: prof }, { data: lg }] = await Promise.all([
      supabase.from('documents_animaux').select('id, token, statut, metadata, type').in('pension_entree_id', tousIds)
        .in('type', ['contrat_hebergement', TYPE_CONTRAT_PRO]).order('created_at', { ascending: false }).limit(1).maybeSingle(),
      maSignaturePro(user.uid).catch(() => null),
      proProfileId ? sejoursFactures(supabase, proProfileId).catch(() => new Set<string>()) : Promise.resolve(new Set<string>()),
      supabase.from('pension_factures').select('id').eq('entree_id', entree.id).limit(1),
      proProfileId ? supabase.from('user_profiles').select('tarifs_pension').eq('id', proProfileId).maybeSingle() : Promise.resolve({ data: null }),
      entree.logement_id ? supabase.from('enclos_chenil').select('nom').eq('id', entree.logement_id).maybeSingle() : Promise.resolve({ data: null }),
    ]);
    setASignature(!!sig);
    setFacture(factures.has(entree.id) || (legacy ?? []).length > 0);
    const reg = ((prof as { tarifs_pension?: { reglement?: { solde?: string; arrhes_pct?: number | null } } } | null)?.tarifs_pension?.reglement) ?? {};
    setSolde(reg.solde === 'depart' ? 'depart' : 'arrivee');
    setArrhes(typeof reg.arrhes_pct === 'number' && reg.arrhes_pct > 0 ? reg.arrhes_pct : null);
    setLogementNom((lg as { nom?: string } | null)?.nom ?? null);
    if (tousIds.length > 1) {
      const { data: gs } = await supabase.from('pension_entrees').select('id, animal_nom').in('id', tousIds);
      setNomsGroupe(((gs ?? []) as { animal_nom: string | null }[]).map(g => g.animal_nom ?? 'Animal'));
    }
    if (proProfileId) {
      const { data: md } = await supabase.from('user_profiles').select('pension_contrat_modele').eq('id', proProfileId).maybeSingle();
      const m = (md as { pension_contrat_modele?: { url?: string; nom?: string } | null } | null)?.pension_contrat_modele;
      if (m?.url) { setModele({ url: m.url, nom: m.nom || 'Mon contrat' }); setChoixContrat('mien'); }
    }
    const d = doc as { id: string; token: string; statut: string | null; metadata: Record<string, unknown> | null; type?: string } | null;
    if (d) {
      const m = d.metadata ?? {};
      setContrat({ id: d.id, token: d.token, statut: d.statut ?? 'brouillon', client_email: (m.client_email as string) ?? entree.proprietaire_email ?? null,
        client_nom: (m.client_nom as string) ?? entree.proprietaire_nom ?? null, client_a_compte: !!m.client_uid,
        signe_pro: !!m.signature_eleveur, signe_client: !!m.signature_acquereur });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user, entree.id, entree.logement_id, entree.proprietaire_email, entree.proprietaire_nom, proProfileId, cleIds]);
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void charger(); }, [charger]);

  /** Contrat de la pension (modèle ou fichier) : rattaché au séjour, signé
   *  d'office, notifié au client (appli) et envoyé par e-mail. */
  async function monContratSigneEtEnvoye() {
    if (!user) return;
    if (!fichier && !modele) { setEtatContrat('erreur'); setMessageContrat('Chargez votre contrat (PDF ou photo).'); return; }
    setEtatContrat('envoi'); setMessageContrat('');
    try {
      const client = await clientDuSejour(supabase, entree as unknown as Record<string, unknown>, user.uid);
      const clientNom = nomComplet(client) || entree.proprietaire_nom || '';
      const doc = await creerContratProSejour({
        entreeId: entree.id, animalId: entree.animal_id ?? null, uid: user.uid, proProfileId,
        titre: `Contrat d'hébergement — ${entree.animal_nom ?? ''}`, clientNom, clientEmail: client.email || null,
        clientUid: client.uid, clientProfileId: client.profileId,
        url: fichier ? null : modele?.url ?? null, blob: fichier ? await fichierEnPdf(fichier) : null, entreeIds: tousIds,
      });
      const nom = `${userData?.firstname ?? ''} ${userData?.lastname ?? ''}`.trim() || pensionNom;
      const signe = await signerContratAvecSignaturePro(doc.id, user.uid, nom, null, true).catch(() => false);
      if (client.uid) {
        await supabase.from('notifications').insert({
          uid: client.uid, ...(client.profileId ? { profile_id: client.profileId } : {}), type: 'contrat_invite', title: 'Contrat à signer',
          body: `${pensionNom} vous envoie le contrat d'hébergement de ${entree.animal_nom ?? 'votre animal'} : vérifiez et signez`,
          data: { token: doc.token, url: `/signer-contrat/${doc.token}` }, read: false,
        });
      }
      let email = false;
      if (parEmail && client.email) {
        email = await envoyerContratParEmail({ email: client.email, clientNom, proProfileId, token: doc.token, titre: `Contrat d'hébergement — ${entree.animal_nom ?? ''}` }).catch(() => false);
      }
      setContrat({ id: doc.id, token: doc.token, statut: 'en_attente', client_email: client.email || null, client_nom: clientNom,
        client_a_compte: !!client.uid, signe_pro: signe, signe_client: false });
      setFichier(null);
      setEtatContrat('ok');
      setMessageContrat([signe ? 'signé par vous' : 'à signer par vous', client.uid ? 'envoyé au client dans l\'appli' : '',
        email ? `envoyé par e-mail à ${client.email}` : parEmail && client.email ? 'e-mail non envoyé' : ''].filter(Boolean).join(' · '));
    } catch (err) {
      setEtatContrat('erreur'); setMessageContrat(err instanceof Error ? err.message : String(err));
    }
  }

  /** Prépare le contrat, le signe avec la signature enregistrée, l'envoie au client. */
  async function contratSigneEtEnvoye() {
    if (!user) return;
    if (choixContrat === 'mien' && !contrat) { await monContratSigneEtEnvoye(); return; }
    setEtatContrat('envoi'); setMessageContrat('');
    const r = await apiFetch('/api/pension/contrat', { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ entreeId: entree.id, entreeIds: tousIds, transmettre: true }) });
    const c = await r.json().catch(() => ({})) as Contrat & { error?: string };
    if (!r.ok || !c.token) { setEtatContrat('erreur'); setMessageContrat(c.error ?? 'Contrat impossible'); return; }
    const nom = `${userData?.firstname ?? ''} ${userData?.lastname ?? ''}`.trim() || pensionNom;
    let signe = c.signe_pro;
    if (!signe) signe = await signerContratAvecSignaturePro(c.id, user.uid, nom, null, true).catch(() => false);
    let email = false;
    if (parEmail && c.client_email && !c.signe_client) {
      email = await envoyerContratParEmail({ email: c.client_email, clientNom: c.client_nom ?? '', proProfileId, token: c.token,
        titre: `Contrat d'hébergement — ${entree.animal_nom ?? ''}` }).catch(() => false);
    }
    setContrat({ ...c, signe_pro: signe });
    setEtatContrat('ok');
    setMessageContrat([
      signe ? 'signé par vous' : 'à signer par vous',
      c.client_a_compte ? 'envoyé au client dans l\'appli' : '',
      email ? `envoyé par e-mail à ${c.client_email}` : parEmail && c.client_email && !c.signe_client ? 'e-mail non envoyé' : '',
    ].filter(Boolean).join(' · '));
  }

  const etapeFaite = true; // la fenêtre s'ouvre une fois l'arrivée / le départ enregistré
  const contratFait = !!contrat && contrat.statut !== 'brouillon';
  const libContrat = !contrat ? 'À préparer'
    : contrat.statut === 'signe' ? 'Signé par les deux parties'
    : contrat.signe_pro && !contrat.signe_client ? 'Signé par vous, en attente du client'
    : contrat.statut === 'brouillon' ? 'Brouillon, pas encore envoyé' : 'Envoyé, en attente de signature';
  const factureAttendue = mode === 'depart' || solde === 'arrivee' || !!arrhes;
  const libFacture = facture === null ? '…' : facture ? 'Facturé'
    : mode === 'arrivee' ? (solde === 'arrivee' ? 'Séjour à facturer (solde à l\'arrivée)' : arrhes ? `Acompte de ${arrhes} % à facturer` : 'Facturation prévue au départ')
    : 'Séjour à facturer';

  return (
    <>
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 px-4" onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl w-full max-w-md p-5 max-h-[92vh] overflow-y-auto space-y-4" onClick={e => e.stopPropagation()} style={{ fontFamily: 'Galey, sans-serif' }}>
        <div>
          <p className="font-bold text-lg text-[#1F2A2E]">{mode === 'arrivee' ? 'Finaliser l\'arrivée' : 'Finaliser le départ'}</p>
          <p className="text-sm text-gray-500">{nomsGroupe.length > 1 ? nomsGroupe.join(', ') : entree.animal_nom}{entree.proprietaire_nom ? ` · ${entree.proprietaire_nom}` : ''}</p>
          {nomsGroupe.length > 1 && <p className="text-xs text-gray-500">Un seul contrat et une facture groupée pour les {nomsGroupe.length} animaux.</p>}
        </div>

        {/* 1. Arrivée / départ */}
        <div className="flex gap-3">
          <Pastille ok={etapeFaite} />
          <div className="flex-1">
            <p className="text-sm font-bold text-[#1F2A2E]">1. {mode === 'arrivee' ? 'Arrivée enregistrée' : 'Départ enregistré'}</p>
            <p className="text-xs text-gray-500">{mode === 'arrivee' ? (logementNom ? `Logement : ${logementNom}` : 'Sans logement attribué') : 'Restitutions et règlement notés sur la fiche de départ.'}</p>
          </div>
        </div>

        {/* 2. Contrat */}
        <div className="flex gap-3">
          <Pastille ok={contratFait && (contrat?.signe_pro ?? false)} />
          <div className="flex-1 space-y-1.5">
            <p className="text-sm font-bold text-[#1F2A2E]">2. Contrat d&apos;hébergement</p>
            <p className="text-xs text-gray-500">{libContrat}</p>
            {!contrat && (
              <div className="space-y-1.5 border border-gray-100 rounded-xl p-2.5">
                <label className="flex items-center gap-2 text-xs text-[#1F2A2E]">
                  <input type="radio" checked={choixContrat === 'petsmatch'} onChange={() => setChoixContrat('petsmatch')} />
                  Contrat PetsMatch (rempli avec le séjour, les tarifs et le règlement)
                </label>
                <label className="flex items-center gap-2 text-xs text-[#1F2A2E]">
                  <input type="radio" checked={choixContrat === 'mien'} onChange={() => setChoixContrat('mien')} />
                  Mon contrat{modele ? ` (${modele.nom})` : ''}
                </label>
                {choixContrat === 'mien' && (
                  <div className="pl-5 space-y-1">
                    {!modele && <p className="text-[11px] text-gray-500">Chargez votre contrat pour ce séjour, ou enregistrez votre modèle dans Tarifs pour ne plus avoir à le faire.</p>}
                    <input type="file" accept={ACCEPT_DOCUMENT_PRO} onChange={e => setFichier(e.target.files?.[0] ?? null)} className="block w-full text-xs text-gray-600" />
                    {modele && !fichier && <p className="text-[11px] text-gray-500">Sans fichier choisi, votre modèle est envoyé.</p>}
                  </div>
                )}
              </div>
            )}
            {contrat?.statut !== 'signe' && (
              <>
                {aSignature === false && (
                  <p className="text-xs text-[#B45309]">Aucune signature enregistrée : signez une première fois le contrat (bouton « Voir le contrat »), elle sera reprise d&apos;office ensuite.</p>
                )}
                {(contrat?.client_email ?? entree.proprietaire_email) && !contrat?.signe_client && (
                  <label className="flex items-center gap-2 text-xs text-[#1F2A2E]">
                    <input type="checkbox" checked={parEmail} onChange={e => setParEmail(e.target.checked)} />
                    Envoyer aussi par e-mail ({contrat?.client_email ?? entree.proprietaire_email})
                  </label>
                )}
                <button onClick={contratSigneEtEnvoye} disabled={etatContrat === 'envoi'}
                  className="w-full py-2 rounded-xl text-sm font-semibold text-white bg-[#0C5C6C] disabled:opacity-50">
                  {etatContrat === 'envoi' ? 'Envoi…' : contratFait ? (mode === 'depart' ? 'Relancer la signature' : 'Renvoyer au client') : 'Préparer, signer et envoyer'}
                </button>
              </>
            )}
            {messageContrat && <p className={`text-xs ${etatContrat === 'erreur' ? 'text-[#B3261E]' : 'text-[#2E7D5E]'}`}>{messageContrat}</p>}
            {contrat && <a href={`/signer-contrat/${contrat.token}`} target="_blank" rel="noopener" className="text-xs font-semibold text-[#0C5C6C]">Voir le contrat</a>}
          </div>
        </div>

        {/* 3. Facture */}
        <div className="flex gap-3">
          <Pastille ok={!!facture || !factureAttendue} />
          <div className="flex-1 space-y-1.5">
            <p className="text-sm font-bold text-[#1F2A2E]">3. Facture</p>
            <p className="text-xs text-gray-500">{libFacture}</p>
            {!facture && (
              <button onClick={() => setFacturer(true)}
                className={`w-full py-2 rounded-xl text-sm font-semibold ${factureAttendue ? 'text-white bg-[#0C5C6C]' : 'border border-gray-200 text-[#0C5C6C]'}`}>
                {mode === 'arrivee' && solde !== 'arrivee' ? (arrhes ? 'Facturer l\'acompte' : 'Facturer maintenant') : 'Facturer le séjour'}
              </button>
            )}
          </div>
        </div>

        <button onClick={onClose} className="w-full py-2.5 rounded-xl text-sm font-semibold border border-gray-200 text-gray-600">Terminer</button>
      </div>
    </div>
    {facturer && (
      <PensionFacturationModal entree={entree} proProfileId={proProfileId} pensionNom={pensionNom}
        onClose={() => { setFacturer(false); void charger(); }} />
    )}
    </>
  );
}
