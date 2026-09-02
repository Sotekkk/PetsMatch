'use client';

import { use, useEffect, useState } from 'react';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

interface Ligne {
  designation?: string;
  description?: string;
  quantite?: number;
  prixUnitaireHT?: number;
  prixUnitaire?: number;
  tauxTVA?: number;
  tva?: number;
  totalHT?: number;
  totalTTC?: number;
}

interface Facture {
  id: string;
  uid_eleveur: string;
  profile_id: string | null;
  numero_facture: number | null;
  numero_affichage: string | null;
  regime_tva: string | null;
  // client
  nom_client: string | null;
  prenom_client: string | null;
  email_client: string | null;
  telephone_client: string | null;
  rue_client: string | null;
  cp_client: string | null;
  ville_client: string | null;
  pays_client: string | null;
  siret_client: string | null;
  tva_client: string | null;
  // émetteur (figé à l'émission)
  nom_emetteur: string | null;
  rue_emetteur: string | null;
  cp_emetteur: string | null;
  ville_emetteur: string | null;
  pays_emetteur: string | null;
  tel_emetteur: string | null;
  email_emetteur: string | null;
  siret_emetteur: string | null;
  tva_emetteur: string | null;
  forme_juridique_emetteur: string | null;
  capital_emetteur: string | null;
  rcs_emetteur: string | null;
  rm_emetteur: string | null;
  // dates & paiement
  date_facture: string | null;
  date_prestation: string | null;
  date_echeance: string | null;
  mode_paiement: string | null;
  delai_paiement: string | null;
  conditions_escompte: string | null;
  note_complementaire: string | null;
  // totaux
  lignes: Ligne[];
  total_ht: number | null;
  total_tva: number | null;
  total_ttc: number | null;
  statut: string;
}

interface ProFallback {
  nom?: string;
  firstname?: string;
  lastname?: string;
  phone_number?: string;
  siret?: string;
  numero_tva?: string;
  rue_pro?: string;
  code_postal_pro?: string;
  ville_pro?: string;
}

const STATUT_LABEL: Record<string, string> = { emise: 'Émise', payee: 'Payée', annulee: 'Annulée' };
const ESCOMPTE_DEFAUT = 'Escompte pour paiement anticipé : néant.';

function fmtDate(d: string | null | undefined) {
  if (!d) return '—';
  const [y, m, day] = d.slice(0, 10).split('-');
  return `${day}/${m}/${y}`;
}
const eur = (v: number) => `${v.toFixed(2).replace('.', ',')} €`;

export default function FacturePublicPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = use(params);
  const [facture, setFacture] = useState<Facture | null>(null);
  const [pro, setPro] = useState<ProFallback | null>(null);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);

  useEffect(() => {
    supabase.from('factures').select('*').eq('token', token).maybeSingle()
      .then(async ({ data }) => {
        if (!data) { setNotFound(true); setLoading(false); return; }
        setFacture(data as Facture);
        // Repli : anciennes factures sans identité émetteur figée
        if (!data.nom_emetteur || !data.siret_emetteur || !data.rue_emetteur) {
          let q = supabase.from('user_profiles')
            .select('nom,firstname,lastname,phone_number,siret,numero_tva,rue_pro,code_postal_pro,ville_pro');
          q = data.profile_id
            ? q.eq('id', data.profile_id)
            : q.eq('uid', data.uid_eleveur).eq('is_main', true);
          const { data: p } = await q.maybeSingle();
          setPro(p ?? null);
        }
        setLoading(false);
      });
  }, [token]);

  function handlePrint() {
    const el = document.getElementById('facture-print-content');
    if (!el) return;
    const win = window.open('', '_blank', 'width=900,height=1200');
    if (!win) return;
    win.document.write(`<!DOCTYPE html>
<html lang="fr"><head><meta charset="UTF-8"><title>Facture n° ${facture?.numero_affichage || facture?.numero_facture || ''}</title>
<script src="https://cdn.tailwindcss.com"><\/script>
<style>
  @page { size: A4; margin: 0; }
  *, *::before, *::after { -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }
  html, body { margin: 0; padding: 0; background: #fff; font-family: Arial, system-ui, sans-serif; }
  .print-page { padding: 12mm 14mm; max-width: 210mm; margin: 0 auto; }
</style></head><body><div class="print-page">${el.outerHTML}</div>
<script>window.addEventListener('load',function(){setTimeout(function(){window.print();},900);});<\/script>
</body></html>`);
    win.document.close();
  }

  if (loading) return <div className="flex justify-center py-32 text-gray-400">Chargement…</div>;
  if (notFound || !facture) return (
    <div className="flex flex-col items-center justify-center min-h-[60vh] gap-3">
      <span className="text-5xl">🔍</span>
      <p className="font-semibold text-gray-700">Facture introuvable ou lien invalide.</p>
    </div>
  );

  const f = facture;
  const franchise = f.regime_tva === 'franchise';

  // Émetteur : priorité aux champs figés sur la facture, repli sur le profil
  const em = {
    nom: f.nom_emetteur || pro?.nom || `${pro?.firstname ?? ''} ${pro?.lastname ?? ''}`.trim() || '—',
    forme: f.forme_juridique_emetteur || '',
    capital: f.capital_emetteur || '',
    rue: f.rue_emetteur || pro?.rue_pro || '',
    cp: f.cp_emetteur || pro?.code_postal_pro || '',
    ville: f.ville_emetteur || pro?.ville_pro || '',
    pays: f.pays_emetteur || 'France',
    tel: f.tel_emetteur || pro?.phone_number || '',
    email: f.email_emetteur || '',
    siret: f.siret_emetteur || pro?.siret || '',
    tva: f.tva_emetteur || pro?.numero_tva || '',
    rcs: f.rcs_emetteur || '',
    rm: f.rm_emetteur || '',
  };

  const lignes = (f.lignes ?? []).map(l => {
    const qte = Number(l.quantite ?? 1);
    const pu = Number(l.prixUnitaireHT ?? l.prixUnitaire ?? 0);
    const taux = Number(l.tauxTVA ?? l.tva ?? 0);
    const ht = l.totalHT != null ? Number(l.totalHT) : qte * pu;
    const ttc = franchise ? ht : (l.totalTTC != null ? Number(l.totalTTC) : ht * (1 + taux / 100));
    return { lib: l.designation || l.description || '', desc: l.designation ? (l.description || '') : '', qte, pu, taux, ht, ttc };
  });
  const totalHT = f.total_ht ?? lignes.reduce((s, l) => s + l.ht, 0);
  const totalTVA = franchise ? 0 : (f.total_tva ?? lignes.reduce((s, l) => s + (l.ttc - l.ht), 0));
  const totalTTC = f.total_ttc ?? (totalHT + totalTVA);
  const escompte = f.conditions_escompte?.trim() || ESCOMPTE_DEFAUT;
  const annee = new Date().getFullYear();

  return (
    <div className="max-w-2xl mx-auto px-4 py-8">
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-xl font-bold text-[#1F2A2E]">Facture n° {f.numero_affichage || f.numero_facture || '—'}</h1>
        <button onClick={handlePrint} className="text-sm border border-gray-200 text-gray-600 px-4 py-2 rounded-xl hover:bg-gray-50">🖨️ PDF</button>
      </div>

      {f.statut === 'payee' && <div className="mb-4 bg-green-50 border border-green-200 rounded-xl p-3 text-sm text-green-700 font-medium">✅ Facture payée.</div>}
      {f.statut === 'annulee' && <div className="mb-4 bg-red-50 border border-red-200 rounded-xl p-3 text-sm text-red-700 font-medium">🚫 Facture annulée.</div>}

      <div id="facture-print-content" className="border border-gray-300 rounded-xl bg-white text-sm text-gray-800 p-8 space-y-6">
        <div className="flex items-start justify-between gap-6">
          <div>
            <h1 className="text-lg font-bold text-[#0C5C6C]">{em.nom}</h1>
            {em.forme && <p className="text-xs text-gray-500">{em.forme}{em.capital ? ` — capital ${em.capital}` : ''}</p>}
            {(em.rue || em.ville) && <p className="text-xs text-gray-500">{[em.rue, [em.cp, em.ville].filter(Boolean).join(' ')].filter(Boolean).join(', ')}{em.pays ? `, ${em.pays}` : ''}</p>}
            {em.tel && <p className="text-xs text-gray-500">Tél. : {em.tel}</p>}
            {em.email && <p className="text-xs text-gray-500">{em.email}</p>}
            {em.siret && <p className="text-xs text-gray-500">SIRET : {em.siret}</p>}
            {em.tva && <p className="text-xs text-gray-500">N° TVA : {em.tva}</p>}
            {em.rcs && <p className="text-xs text-gray-500">{em.rcs}</p>}
            {em.rm && <p className="text-xs text-gray-500">RM : {em.rm}</p>}
          </div>
          <div className="text-right flex-shrink-0">
            <p className="text-xl font-bold text-[#1F2A2E]">FACTURE</p>
            <p className="text-sm font-bold">N° {f.numero_affichage || f.numero_facture || '—'}</p>
            <p className="text-xs text-gray-400 mt-2">{STATUT_LABEL[f.statut] ?? f.statut}</p>
            <p className="text-xs text-gray-500">Émise le {fmtDate(f.date_facture)}</p>
            <p className="text-xs text-gray-500">Prestation : {fmtDate(f.date_prestation)}</p>
            {f.date_echeance && <p className="text-xs font-semibold text-gray-600">Échéance : {fmtDate(f.date_echeance)}</p>}
          </div>
        </div>

        <div className="flex justify-end">
          <div className="border border-gray-200 rounded-xl p-4 w-64">
            <h2>Client</h2>
            <p className="font-semibold text-sm">{[f.prenom_client, f.nom_client].filter(Boolean).join(' ') || '—'}</p>
            {(f.rue_client || f.ville_client) && (
              <p className="text-xs text-gray-500">
                {[f.rue_client, [f.cp_client, f.ville_client].filter(Boolean).join(' '), f.pays_client].filter(Boolean).join(', ')}
              </p>
            )}
            {f.email_client && <p className="text-xs text-gray-500">{f.email_client}</p>}
            {f.telephone_client && <p className="text-xs text-gray-500">{f.telephone_client}</p>}
            {f.siret_client && <p className="text-xs text-gray-500">SIRET : {f.siret_client}</p>}
            {f.tva_client && <p className="text-xs text-gray-500">N° TVA : {f.tva_client}</p>}
          </div>
        </div>

        <div className="border border-gray-200 rounded-xl overflow-hidden">
          <div className={`grid ${franchise ? 'grid-cols-[1fr_50px_90px_90px]' : 'grid-cols-[1fr_46px_78px_54px_88px]'} gap-2 bg-gray-50 px-4 py-2 text-[10px] font-bold uppercase text-gray-500`}>
            <span>Désignation</span>
            <span className="text-right">Qté</span>
            <span className="text-right">P.U. HT</span>
            {!franchise && <span className="text-right">TVA</span>}
            <span className="text-right">{franchise ? 'Total' : 'Total TTC'}</span>
          </div>
          {lignes.map((l, i) => (
            <div key={i} className={`grid ${franchise ? 'grid-cols-[1fr_50px_90px_90px]' : 'grid-cols-[1fr_46px_78px_54px_88px]'} gap-2 px-4 py-2.5 text-xs ${i % 2 ? 'bg-gray-50' : 'bg-white'}`}>
              <span className="text-gray-700">
                <span className="font-medium">{l.lib}</span>
                {l.desc && <span className="block text-gray-400">{l.desc}</span>}
              </span>
              <span className="text-right text-gray-500">{l.qte}</span>
              <span className="text-right text-gray-500">{eur(l.pu)}</span>
              {!franchise && <span className="text-right text-gray-500">{l.taux}%</span>}
              <span className="text-right font-medium text-[#1F2A2E]">{eur(l.ttc)}</span>
            </div>
          ))}
          <div className="bg-gray-50 px-4 py-3 border-t border-gray-200">
            <div className="totals ml-auto max-w-[240px] space-y-1">
              {!franchise && <div className="flex justify-between text-xs text-gray-500"><span>Total HT</span><span>{eur(totalHT)}</span></div>}
              {!franchise && <div className="flex justify-between text-xs text-gray-500"><span>TVA</span><span>{eur(totalTVA)}</span></div>}
              <div className="flex justify-between text-base font-bold text-[#1F2A2E]"><span>{franchise ? 'Total' : 'Total TTC'}</span><span>{eur(totalTTC)}</span></div>
            </div>
          </div>
        </div>

        <div className="bg-gray-50 rounded-xl p-3 text-xs text-gray-600 space-y-0.5">
          <p>Mode de paiement : {f.mode_paiement || '—'}</p>
          {f.delai_paiement && <p>Délai de règlement : {f.delai_paiement} jours à compter de la date d&apos;émission.</p>}
          {f.note_complementaire && <p className="whitespace-pre-line">{f.note_complementaire}</p>}
        </div>

        <div className="mentions border border-gray-200 rounded-xl p-3 text-[11px] text-gray-500 space-y-1">
          {franchise && <p className="font-semibold text-gray-700">TVA non applicable, art. 293 B du CGI.</p>}
          <p>{escompte}</p>
          <p>En cas de retard de paiement : pénalités au taux de 3 fois le taux d&apos;intérêt légal en vigueur ({annee}), exigibles sans rappel le lendemain de la date d&apos;échéance, et indemnité forfaitaire de recouvrement de 40 € (art. L441-10 et D441-5 du Code de commerce).</p>
        </div>

        <p className="text-[10px] text-gray-400 text-center border-t pt-3">Réf. {f.id}</p>
      </div>
    </div>
  );
}
