'use client';

import { use, useEffect, useState } from 'react';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

interface Ligne { description: string; quantite: number; prixUnitaire: number; tva: number; }

interface Facture {
  id: string;
  uid_eleveur: string;
  profile_id: string | null;
  numero_facture: number | null;
  nom_client: string | null;
  prenom_client: string | null;
  email_client: string | null;
  telephone_client: string | null;
  rue_client: string | null;
  cp_client: string | null;
  ville_client: string | null;
  pays_client: string | null;
  date_facture: string | null;
  date_prestation: string | null;
  date_echeance: string | null;
  lignes: Ligne[];
  total_ht: number | null;
  total_tva: number | null;
  total_ttc: number | null;
  statut: string;
}

interface Pro {
  nom?: string;
  firstname?: string;
  lastname?: string;
  profession_pro?: string;
  phone_number?: string;
  siret?: string;
}

const STATUT_LABEL: Record<string, string> = { emise: 'Émise', payee: 'Payée', annulee: 'Annulée' };

function fmtDate(d: string | null | undefined) {
  if (!d) return '—';
  const [y, m, day] = d.slice(0, 10).split('-');
  return `${day}/${m}/${y}`;
}

export default function FacturePublicPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = use(params);
  const [facture, setFacture] = useState<Facture | null>(null);
  const [pro, setPro] = useState<Pro | null>(null);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);

  useEffect(() => {
    supabase.from('factures').select('*').eq('token', token).maybeSingle()
      .then(async ({ data }) => {
        if (!data) { setNotFound(true); setLoading(false); return; }
        setFacture(data as Facture);
        let proQuery = supabase.from('user_profiles')
          .select('nom,firstname,lastname,profession_pro,phone_number,siret');
        proQuery = data.profile_id
          ? proQuery.eq('id', data.profile_id)
          : proQuery.eq('uid', data.uid_eleveur).eq('is_main', true);
        const { data: p } = await proQuery.maybeSingle();
        setPro(p ?? null);
        setLoading(false);
      });
  }, [token]);

  function handlePrint() {
    const el = document.getElementById('facture-print-content');
    if (!el) return;
    const win = window.open('', '_blank', 'width=900,height=1200');
    if (!win) return;
    win.document.write(`<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <title>Facture PetsMatch</title>
  <script src="https://cdn.tailwindcss.com"><\/script>
  <style>
    @page { size: A4; margin: 0; }
    *, *::before, *::after { -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; box-sizing: border-box; }
    html, body { margin: 0; padding: 0; background: white; font-family: system-ui, -apple-system, sans-serif; }
    .print-page { padding: 12mm 14mm 14mm 14mm; max-width: 210mm; margin: 0 auto; }
    .no-break { break-inside: avoid; page-break-inside: avoid; }
  </style>
</head>
<body>
  <div class="print-page">${el.outerHTML}</div>
  <script>
    window.addEventListener('load', function() { setTimeout(function() { window.print(); }, 1200); });
  <\/script>
</body>
</html>`);
    win.document.close();
  }

  if (loading) return <div className="flex justify-center py-32 text-gray-400">Chargement…</div>;
  if (notFound || !facture) return (
    <div className="flex flex-col items-center justify-center min-h-[60vh] gap-3">
      <span className="text-5xl">🔍</span>
      <p className="font-semibold text-gray-700">Facture introuvable ou lien invalide.</p>
    </div>
  );

  const nomPro = pro?.nom?.trim() || `${pro?.firstname ?? ''} ${pro?.lastname ?? ''}`.trim() || '—';

  return (
    <div className="print-wrapper max-w-2xl mx-auto px-4 py-8">
      <div className="no-print flex items-center justify-between mb-6">
        <div>
          <h1 className="text-xl font-bold text-[#1F2A2E]">Facture</h1>
          <p className="text-xs text-gray-500 mt-0.5">{nomPro}{pro?.profession_pro ? ` — ${pro.profession_pro}` : ''}</p>
        </div>
        <button onClick={handlePrint} className="text-sm border border-gray-200 text-gray-600 px-4 py-2 rounded-xl hover:bg-gray-50">🖨️ PDF</button>
      </div>

      {facture.statut === 'payee' && (
        <div className="no-print mb-4 bg-green-50 border border-green-200 rounded-xl p-3 text-sm text-green-700 font-medium">
          ✅ Facture payée.
        </div>
      )}
      {facture.statut === 'annulee' && (
        <div className="no-print mb-4 bg-red-50 border border-red-200 rounded-xl p-3 text-sm text-red-700 font-medium">
          🚫 Facture annulée.
        </div>
      )}

      <div id="facture-print-content" className="border border-gray-300 rounded-xl bg-white text-sm text-gray-800">
        <div className="text-center border-b border-gray-200 px-8 py-6">
          <p className="text-xs font-bold uppercase tracking-widest text-[#0C5C6C] mb-2">PetsMatch</p>
          <h2 className="text-xl font-bold text-[#1F2A2E]">FACTURE {facture.numero_facture ? `n° ${facture.numero_facture}` : ''}</h2>
          <p className="text-xs text-gray-400 mt-2">
            {STATUT_LABEL[facture.statut] ?? facture.statut} · Émise le {fmtDate(facture.date_facture)}
          </p>
          {facture.date_echeance && <p className="text-xs text-gray-400">Échéance le {fmtDate(facture.date_echeance)}</p>}
        </div>

        <div className="p-8 space-y-6">
          <section className="no-break grid grid-cols-2 gap-6">
            <div className="border border-gray-200 rounded-xl p-4">
              <p className="text-[10px] font-bold uppercase tracking-widest text-[#0C5C6C] mb-2">Émetteur</p>
              <p className="font-semibold text-sm">{nomPro}</p>
              {pro?.profession_pro && <p className="text-xs text-gray-500 mt-0.5">{pro.profession_pro}</p>}
              {pro?.siret && <p className="text-xs text-gray-500">SIRET : {pro.siret}</p>}
              {pro?.phone_number && <p className="text-xs text-gray-500">{pro.phone_number}</p>}
            </div>
            <div className="border border-gray-200 rounded-xl p-4">
              <p className="text-[10px] font-bold uppercase tracking-widest text-[#0C5C6C] mb-2">Client</p>
              <p className="font-semibold text-sm">{facture.prenom_client} {facture.nom_client}</p>
              {facture.email_client && <p className="text-xs text-gray-500 mt-0.5">{facture.email_client}</p>}
              {facture.telephone_client && <p className="text-xs text-gray-500">{facture.telephone_client}</p>}
              {(facture.rue_client || facture.ville_client) && (
                <p className="text-xs text-gray-500">
                  {[facture.rue_client, [facture.cp_client, facture.ville_client].filter(Boolean).join(' ')].filter(Boolean).join(', ')}
                </p>
              )}
            </div>
          </section>

          <section className="no-break border border-gray-200 rounded-xl overflow-hidden">
            <div className="grid grid-cols-[1fr_50px_80px_60px_90px] gap-2 bg-gray-50 px-4 py-2 text-[10px] font-bold uppercase text-gray-500">
              <span>Description</span><span className="text-center">Qté</span><span className="text-right">Prix unit.</span><span className="text-right">TVA</span><span className="text-right">Total</span>
            </div>
            {(facture.lignes ?? []).map((l, i) => (
              <div key={i} className={`grid grid-cols-[1fr_50px_80px_60px_90px] gap-2 px-4 py-2.5 text-xs ${i % 2 === 0 ? 'bg-white' : 'bg-gray-50'}`}>
                <span className="text-gray-700">{l.description}</span>
                <span className="text-center text-gray-500">{l.quantite}</span>
                <span className="text-right text-gray-500">{Number(l.prixUnitaire).toFixed(2)} €</span>
                <span className="text-right text-gray-500">{l.tva}%</span>
                <span className="text-right font-medium text-[#1F2A2E]">{(Number(l.quantite) * Number(l.prixUnitaire) * (1 + Number(l.tva) / 100)).toFixed(2)} €</span>
              </div>
            ))}
            <div className="bg-gray-50 px-4 py-3 border-t border-gray-200 space-y-1">
              <div className="flex justify-between text-xs text-gray-500"><span>Total HT</span><span>{(facture.total_ht ?? 0).toFixed(2)} €</span></div>
              <div className="flex justify-between text-xs text-gray-500"><span>TVA</span><span>{(facture.total_tva ?? 0).toFixed(2)} €</span></div>
              <div className="flex justify-between text-base font-bold text-[#1F2A2E]"><span>Total TTC</span><span>{(facture.total_ttc ?? 0).toFixed(2)} €</span></div>
            </div>
          </section>

          <p className="text-[10px] text-gray-400 text-center border-t pt-3">
            Facture générée via PetsMatch · Réf. {facture.id}
          </p>
        </div>
      </div>
    </div>
  );
}
