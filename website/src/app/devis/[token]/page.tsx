'use client';

import { use, useEffect, useState } from 'react';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

interface Ligne { description: string; quantite: number; prix_unitaire: number; total: number; }

interface Devis {
  id: string;
  pro_uid: string;
  numero_devis: string | null;
  date_devis: string;
  date_validite: string | null;
  animal_id: string | null;
  nom_client: string;
  prenom_client: string | null;
  email_client: string;
  telephone_client: string | null;
  lignes: Ligne[];
  total_ttc: number;
  note: string | null;
  statut: string;
  token_acceptation: string;
  date_reponse: string | null;
}

interface Pro {
  name_elevage?: string;
  firstname?: string;
  lastname?: string;
  profession_pro?: string;
  phone_number?: string;
  siret?: string;
}

function fmtDate(d: string | null | undefined) {
  if (!d) return '—';
  return new Date(d).toLocaleDateString('fr-FR');
}

export default function DevisPublicPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = use(params);
  const [devis, setDevis] = useState<Devis | null>(null);
  const [pro, setPro] = useState<Pro | null>(null);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);
  const [action, setAction] = useState<'idle' | 'accepting' | 'refusing' | 'error'>('idle');
  const [errorMsg, setErrorMsg] = useState('');

  useEffect(() => {
    supabase.from('devis').select('*').eq('token_acceptation', token).maybeSingle()
      .then(async ({ data }) => {
        if (!data) { setNotFound(true); setLoading(false); return; }
        setDevis(data as Devis);
        const { data: p } = await supabase.from('user_profiles')
          .select('nom,firstname,lastname,profession_pro,phone_number,siret')
          .eq('uid', data.pro_uid).eq('is_main', true).maybeSingle();
        setPro(p ? {
          name_elevage: p.nom, firstname: p.firstname, lastname: p.lastname,
          profession_pro: p.profession_pro, phone_number: p.phone_number, siret: p.siret,
        } : null);
        setLoading(false);
      });
  }, [token]);

  async function handleRespond(statut: 'accepte' | 'refuse') {
    if (!devis) return;
    setAction(statut === 'accepte' ? 'accepting' : 'refusing');
    try {
      const { error } = await supabase.from('devis')
        .update({ statut, date_reponse: new Date().toISOString(), updated_at: new Date().toISOString() })
        .eq('id', devis.id).eq('statut', 'envoye');
      if (error) { setErrorMsg(error.message); setAction('error'); return; }
      await supabase.from('notifications').insert({
        uid: devis.pro_uid,
        type: statut === 'accepte' ? 'devis_accepte' : 'devis_refuse',
        title: statut === 'accepte' ? 'Devis accepté' : 'Devis refusé',
        body: `${devis.prenom_client ?? ''} ${devis.nom_client} a ${statut === 'accepte' ? 'accepté' : 'refusé'} le devis de ${Number(devis.total_ttc).toFixed(2)} €.`,
        data: { devis_id: devis.id },
        read: false,
      });
      if (devis.animal_id) {
        const docStatut = statut === 'accepte' ? 'signe' : 'refuse';
        const { data: existing } = await supabase.from('documents_animaux').select('id')
          .eq('animal_id', devis.animal_id).eq('type', 'devis').contains('metadata', { devis_id: devis.id }).maybeSingle();
        if (existing) await supabase.from('documents_animaux').update({ statut: docStatut }).eq('id', existing.id);
      }
      setDevis(prev => prev ? { ...prev, statut, date_reponse: new Date().toISOString() } : prev);
      setAction('idle');
    } catch {
      setAction('error');
    }
  }

  function handlePrint() {
    const el = document.getElementById('devis-print-content');
    if (!el) return;
    const win = window.open('', '_blank', 'width=900,height=1200');
    if (!win) return;
    win.document.write(`<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <title>Devis PetsMatch</title>
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
  if (notFound || !devis) return (
    <div className="flex flex-col items-center justify-center min-h-[60vh] gap-3">
      <span className="text-5xl">🔍</span>
      <p className="font-semibold text-gray-700">Devis introuvable ou lien expiré.</p>
    </div>
  );

  const nomPro = pro?.name_elevage?.trim() || `${pro?.firstname ?? ''} ${pro?.lastname ?? ''}`.trim() || '—';
  const isAccepted = devis.statut === 'accepte';
  const isRefused = devis.statut === 'refuse';
  const isDone = isAccepted || isRefused;
  const canRespond = devis.statut === 'envoye';

  return (
    <div className="print-wrapper max-w-2xl mx-auto px-4 py-8">
      <div className="no-print flex items-center justify-between mb-6">
        <div>
          <h1 className="text-xl font-bold text-[#1F2A2E]">Devis</h1>
          <p className="text-xs text-gray-500 mt-0.5">{nomPro}{pro?.profession_pro ? ` — ${pro.profession_pro}` : ''}</p>
        </div>
        <button onClick={handlePrint} className="text-sm border border-gray-200 text-gray-600 px-4 py-2 rounded-xl hover:bg-gray-50">🖨️ PDF</button>
      </div>

      {isAccepted && (
        <div className="no-print mb-4 bg-green-50 border border-green-200 rounded-xl p-3 text-sm text-green-700 font-medium">
          ✅ Devis accepté le {fmtDate(devis.date_reponse)}.
        </div>
      )}
      {isRefused && (
        <div className="no-print mb-4 bg-red-50 border border-red-200 rounded-xl p-3 text-sm text-red-700 font-medium">
          ❌ Devis refusé le {fmtDate(devis.date_reponse)}.
        </div>
      )}

      <div id="devis-print-content" className="border border-gray-300 rounded-xl bg-white text-sm text-gray-800">
        <div className="text-center border-b border-gray-200 px-8 py-6">
          <p className="text-xs font-bold uppercase tracking-widest text-[#0C5C6C] mb-2">PetsMatch</p>
          <h2 className="text-xl font-bold text-[#1F2A2E]">DEVIS</h2>
          <p className="text-xs text-gray-400 mt-2">Réf. DEVIS-{devis.id.substring(0, 8).toUpperCase()} · Émis le {fmtDate(devis.date_devis)}</p>
          {devis.date_validite && <p className="text-xs text-gray-400">Valable jusqu&apos;au {fmtDate(devis.date_validite)}</p>}
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
              <p className="font-semibold text-sm">{devis.prenom_client} {devis.nom_client}</p>
              <p className="text-xs text-gray-500 mt-0.5">{devis.email_client}</p>
              {devis.telephone_client && <p className="text-xs text-gray-500">{devis.telephone_client}</p>}
            </div>
          </section>

          <section className="no-break border border-gray-200 rounded-xl overflow-hidden">
            <div className="grid grid-cols-[1fr_60px_90px_90px] gap-2 bg-gray-50 px-4 py-2 text-[10px] font-bold uppercase text-gray-500">
              <span>Description</span><span className="text-center">Qté</span><span className="text-right">Prix unit.</span><span className="text-right">Total</span>
            </div>
            {devis.lignes.map((l, i) => (
              <div key={i} className={`grid grid-cols-[1fr_60px_90px_90px] gap-2 px-4 py-2.5 text-xs ${i % 2 === 0 ? 'bg-white' : 'bg-gray-50'}`}>
                <span className="text-gray-700">{l.description}</span>
                <span className="text-center text-gray-500">{l.quantite}</span>
                <span className="text-right text-gray-500">{Number(l.prix_unitaire).toFixed(2)} €</span>
                <span className="text-right font-medium text-[#1F2A2E]">{Number(l.total).toFixed(2)} €</span>
              </div>
            ))}
            <div className="flex justify-end px-4 py-3 border-t border-gray-200">
              <span className="text-base font-bold text-[#1F2A2E]">Total : {Number(devis.total_ttc).toFixed(2)} €</span>
            </div>
          </section>

          {devis.note && (
            <section className="no-break">
              <p className="text-[10px] font-bold uppercase tracking-widest text-[#0C5C6C] mb-2">Notes</p>
              <p className="text-xs text-gray-600 whitespace-pre-wrap">{devis.note}</p>
            </section>
          )}

          <p className="text-[10px] text-gray-400 text-center border-t pt-3">
            Devis généré via PetsMatch · Réf. {devis.id}
          </p>
        </div>
      </div>

      {canRespond && !isDone && (
        <div className="no-print mt-6 bg-white border border-gray-200 rounded-xl p-5">
          {action === 'error' && <p className="text-sm text-red-600 text-center mb-3">{errorMsg}</p>}
          <div className="flex gap-3">
            <button onClick={() => handleRespond('refuse')} disabled={action === 'refusing' || action === 'accepting'}
              className="flex-1 border border-gray-200 text-gray-600 font-medium py-3 rounded-xl text-sm hover:bg-gray-50 disabled:opacity-50">
              {action === 'refusing' ? 'Traitement…' : 'Refuser'}
            </button>
            <button onClick={() => handleRespond('accepte')} disabled={action === 'accepting' || action === 'refusing'}
              className="flex-1 bg-[#6E9E57] hover:bg-[#5d8a49] disabled:opacity-50 text-white font-semibold py-3 rounded-xl text-sm">
              {action === 'accepting' ? 'Traitement…' : '✓ Accepter ce devis'}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
