'use client';

// Règlements d'une facture émise (facture_reglements) : paiements partiels,
// solde, reste à payer. Le total réglé et le statut (partiellement payée /
// payée) sont recalculés en base ; le contenu de la facture ne change pas.
// Miroir appli : lib/pages/eleveur/admin/facturation.dart (_ReglementsFacture).

import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';

const MODES = ['Carte bancaire', 'Espèces', 'Chèque', 'Virement'];
const eur = (v: number) => `${v.toFixed(2).replace('.', ',')} €`;

interface Reglement { id: string; montant: number; date_reglement: string; mode: string | null; reference: string | null }

export default function ReglementsFacture({ facture, uid, onChange }: {
  facture: { id: string; total_ttc?: number | null; statut?: string | null };
  uid: string;
  /** Après un règlement : statut et total réglé à jour. */
  onChange: (maj: { statut: string; montant_regle: number; mode_paiement?: string | null; date_paiement?: string | null }) => void;
}) {
  const [liste, setListe] = useState<Reglement[]>([]);
  const [form, setForm] = useState<{ montant: string; date: string; mode: string; reference: string } | null>(null);
  const [enCours, setEnCours] = useState(false);
  const total = Number(facture.total_ttc ?? 0);
  // Facture marquée payée avant les règlements (aucun enregistré) : soldée.
  const payeeSansDetail = facture.statut === 'payee' && liste.length === 0;
  const regle = payeeSansDetail ? total : liste.reduce((s, r) => s + Number(r.montant), 0);
  const reste = Math.max(0, Math.round((total - regle) * 100) / 100);

  const charger = useCallback(async () => {
    const { data } = await supabase.from('facture_reglements').select('id, montant, date_reglement, mode, reference')
      .eq('facture_id', facture.id).order('date_reglement').order('created_at');
    setListe((data ?? []) as Reglement[]);
  }, [facture.id]);
  useEffect(() => { charger(); }, [charger]);

  async function rafraichirFacture() {
    const { data } = await supabase.from('factures').select('statut, montant_regle, mode_paiement, date_paiement').eq('id', facture.id).maybeSingle();
    if (data) onChange(data as { statut: string; montant_regle: number; mode_paiement?: string | null; date_paiement?: string | null });
  }

  async function enregistrer(montant: number, mode: string, date: string, reference: string) {
    if (!(montant > 0)) return;
    setEnCours(true);
    const { error } = await supabase.from('facture_reglements').insert({
      facture_id: facture.id, uid_eleveur: uid, montant: Math.round(montant * 100) / 100,
      date_reglement: date, mode: mode || null, reference: reference.trim() || null,
    });
    setEnCours(false);
    if (error) { alert(`Règlement non enregistré : ${error.message}`); return; }
    setForm(null);
    await charger();
    await rafraichirFacture();
  }

  async function supprimer(r: Reglement) {
    if (!confirm(`Supprimer le règlement de ${eur(Number(r.montant))} du ${new Date(r.date_reglement).toLocaleDateString('fr-FR')} ?`)) return;
    await supabase.from('facture_reglements').delete().eq('id', r.id);
    await charger();
    await rafraichirFacture();
  }

  if (facture.statut === 'annulee' || facture.statut === 'brouillon') return null;
  const jour = new Date().toISOString().slice(0, 10);
  return (
    <div className="border border-gray-100 rounded-xl p-3 mb-3 space-y-2">
      <div className="flex items-center justify-between">
        <p className="text-sm font-semibold text-[#1F2A2E]">Règlements</p>
        <p className="text-xs text-gray-500">Réglé {eur(regle)} · <span className="font-bold text-[#1F2A2E]">Reste à payer {eur(reste)}</span></p>
      </div>
      {liste.map(r => (
        <div key={r.id} className="flex items-center gap-2 text-xs text-gray-600">
          <span className="flex-1">{new Date(r.date_reglement).toLocaleDateString('fr-FR')} · {r.mode ?? '—'}{r.reference ? ` · ${r.reference}` : ''}</span>
          <span className="font-semibold">{eur(Number(r.montant))}</span>
          <button type="button" onClick={() => supprimer(r)} className="text-gray-400 hover:text-red-500">Supprimer</button>
        </div>
      ))}
      {reste > 0 && !form && (
        <div className="flex gap-2">
          <button type="button" disabled={enCours} onClick={() => setForm({ montant: String(reste), date: jour, mode: MODES[0], reference: '' })}
            className="flex-1 border border-[#0C5C6C] text-[#0C5C6C] font-semibold py-2 rounded-xl text-sm">Enregistrer un règlement</button>
          <button type="button" disabled={enCours} onClick={() => {
              const mode = window.prompt('Réglée par (Carte bancaire, Espèces, Chèque, Virement)', MODES[0]);
              if (mode !== null) enregistrer(reste, mode.trim() || MODES[0], jour, '');
            }}
            className="flex-1 bg-[#6E9E57] hover:bg-[#5A8A45] text-white font-semibold py-2 rounded-xl text-sm">Solder ({eur(reste)})</button>
        </div>
      )}
      {form && (
        <div className="space-y-2">
          <div className="grid grid-cols-2 gap-2">
            <label className="text-xs text-gray-500">Montant (€)
              <input type="number" min={0} step="0.01" value={form.montant} onChange={e => setForm({ ...form, montant: e.target.value })}
                className="mt-1 w-full border border-gray-200 rounded-lg px-2 py-1.5 text-sm" />
            </label>
            <label className="text-xs text-gray-500">Date
              <input type="date" value={form.date} onChange={e => setForm({ ...form, date: e.target.value })}
                className="mt-1 w-full border border-gray-200 rounded-lg px-2 py-1.5 text-sm" />
            </label>
          </div>
          <div className="flex flex-wrap gap-1.5">
            {MODES.map(m => (
              <button key={m} type="button" onClick={() => setForm({ ...form, mode: m })}
                className="px-3 py-1 rounded-full text-xs font-semibold border"
                style={form.mode === m ? { background: '#0C5C6C', color: 'white', borderColor: '#0C5C6C' } : { color: '#0C5C6C', borderColor: '#0C5C6C' }}>{m}</button>
            ))}
          </div>
          <input value={form.reference} onChange={e => setForm({ ...form, reference: e.target.value })} placeholder="Référence (n° de chèque, virement…) — facultatif"
            className="w-full border border-gray-200 rounded-lg px-2 py-1.5 text-sm" />
          <div className="flex gap-2">
            <button type="button" onClick={() => setForm(null)} className="flex-1 border border-gray-200 text-gray-600 py-2 rounded-xl text-sm">Annuler</button>
            <button type="button" disabled={enCours || !(Number(form.montant.replace(',', '.')) > 0)}
              onClick={() => enregistrer(Number(form.montant.replace(',', '.')), form.mode, form.date, form.reference)}
              className="flex-1 bg-[#0C5C6C] text-white font-semibold py-2 rounded-xl text-sm disabled:opacity-40">{enCours ? '…' : 'Enregistrer'}</button>
          </div>
        </div>
      )}
    </div>
  );
}
