'use client';

import { use, useEffect, useState } from 'react';
import { createClient } from '@supabase/supabase-js';
import { pensionInvoiceHtml, type PensionFactureData } from '@/lib/pension-facture-html';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
);

interface Row {
  numero: string;
  numero_affichage: string | null;
  animal_nom: string | null;
  proprietaire_nom: string | null;
  montant: number | null;
  statut: string;
  type: string | null;
  pdf_url: string | null;
  details: PensionFactureData | null;
  date_envoi: string | null;
  date_paiement: string | null;
}

export default function FacturePensionPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = use(params);
  const [row, setRow] = useState<Row | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      const { data } = await supabase.from('pension_factures')
        .select('numero, numero_affichage, animal_nom, proprietaire_nom, montant, statut, type, pdf_url, details, date_envoi, date_paiement')
        .eq('token', token).maybeSingle();
      setRow((data as Row) ?? null);
      setLoading(false);
    })();
  }, [token]);

  if (loading) {
    return <div style={{ minHeight: '60vh', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#9ca3af', fontFamily: 'Galey, sans-serif' }}>Chargement…</div>;
  }
  if (!row) {
    return (
      <div style={{ minHeight: '60vh', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 8, fontFamily: 'Galey, sans-serif' }}>
        <span style={{ fontSize: 40 }}>🧾</span>
        <p style={{ color: '#6b7280' }}>Facture introuvable ou lien expiré.</p>
      </div>
    );
  }

  const paye = row.statut === 'payee';
  const data: PensionFactureData = row.details
    ? { ...row.details, numero: row.numero_affichage || row.numero }
    : {
        numero: row.numero_affichage || row.numero, pensionNom: 'Votre pension', emiseLe: row.date_envoi,
        animal: { nom: row.animal_nom }, proprietaire: { nom: row.proprietaire_nom },
        sejour: {}, nuits: 1, tarifNuit: row.montant ?? 0, avecTVA: false,
        isAcompte: row.type === 'acompte', acomptePct: 100,
      };

  return (
    <div style={{ maxWidth: 780, margin: '0 auto', padding: '20px 16px 60px' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 16, flexWrap: 'wrap' }}>
        <span style={{
          fontFamily: 'Galey, sans-serif', fontSize: 12, fontWeight: 700, padding: '3px 12px', borderRadius: 20,
          background: paye ? 'rgba(110,158,87,0.12)' : '#FEF3C7', color: paye ? '#6E9E57' : '#92400E',
        }}>
          {paye ? '✓ Payée' : 'À régler'}
        </span>
        <span style={{ flex: 1 }} />
        <button onClick={() => window.print()} style={{
          fontFamily: 'Galey, sans-serif', fontSize: 13, fontWeight: 700, padding: '8px 16px', borderRadius: 10,
          border: '1px solid #0C5C6C', background: 'white', color: '#0C5C6C', cursor: 'pointer',
        }}>
          🖨️ Imprimer / PDF
        </button>
        {row.pdf_url && (
          <a href={row.pdf_url} target="_blank" rel="noopener noreferrer" style={{
            fontFamily: 'Galey, sans-serif', fontSize: 13, fontWeight: 700, padding: '8px 16px', borderRadius: 10,
            border: '1px solid #0C5C6C', background: '#0C5C6C', color: 'white', textDecoration: 'none',
          }}>
            PDF ↗
          </a>
        )}
      </div>
      <div style={{ border: '1px solid #e5e7eb', borderRadius: 12, overflow: 'hidden', background: 'white' }}
        dangerouslySetInnerHTML={{ __html: pensionInvoiceHtml(data) }} />
    </div>
  );
}
