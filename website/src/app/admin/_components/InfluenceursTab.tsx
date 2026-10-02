'use client';
// Demandes de badge influenceur (ex-onglet de l'appli).
import React, { useCallback, useEffect, useState } from 'react';
import { apiFetch } from '@/lib/api-fetch';
import { ActionBtn, Badge, fmtDate } from './ui';

interface Demande {
  id: string; uid: string; pseudo: string | null; email_contact: string | null;
  lien_instagram: string | null; lien_tiktok: string | null; lien_autre: string | null;
  message: string | null; preuves_urls: string[] | null; statut: string; created_at: string;
}
const FILTRES = [
  { key: 'pending', label: 'En attente', color: '#d97706' },
  { key: 'approved', label: 'Approuvés', color: '#16a34a' },
  { key: 'refused', label: 'Refusés', color: '#dc2626' },
] as const;

export default function InfluenceursTab() {
  const [filtre, setFiltre] = useState<string>('pending');
  const [items, setItems] = useState<Demande[]>([]);
  const [loading, setLoading] = useState(true);
  const [erreur, setErreur] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true); setErreur(null);
    const r = await apiFetch(`/api/admin/moderation?type=influenceurs&statut=${filtre}`);
    const j = await r.json().catch(() => ({}));
    if (!r.ok) setErreur(j.error ?? 'Erreur de chargement');
    setItems(j.items ?? []);
    setLoading(false);
  }, [filtre]);
  useEffect(() => { void load(); }, [load]);

  async function agir(action: string, d: Demande) {
    if (action === 'influenceur_revoquer' && !confirm(`Retirer le badge influenceur de ${d.pseudo ?? d.uid} ?`)) return;
    const r = await apiFetch('/api/admin/moderation', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action, id: d.id }),
    });
    if (!r.ok) { alert((await r.json().catch(() => ({}))).error ?? 'Erreur'); return; }
    void load();
  }

  const lien = (u: string | null, label: string) => u
    ? <a href={u.startsWith('http') ? u : `https://${u}`} target="_blank" rel="noopener noreferrer"
        className="text-xs text-[#0C5C6C] underline mr-3">{label}</a>
    : null;

  return (
    <div className="space-y-4">
      <div className="flex gap-2">
        {FILTRES.map((f) => (
          <button key={f.key} onClick={() => setFiltre(f.key)}
            className={`px-3 py-1.5 rounded-xl text-sm font-semibold border ${filtre === f.key ? 'text-white' : 'bg-white'}`}
            style={filtre === f.key ? { background: f.color, borderColor: f.color } : { borderColor: `${f.color}66`, color: f.color }}>
            {f.label}
          </button>
        ))}
      </div>
      {erreur && <p className="text-sm text-red-600">{erreur}</p>}
      {loading ? <p className="text-sm text-gray-400">Chargement…</p>
        : items.length === 0 ? <p className="text-sm text-gray-400">Aucune demande.</p>
        : items.map((d) => (
          <div key={d.id} className="bg-white rounded-2xl p-4 shadow-sm space-y-2">
            <div className="flex items-center justify-between gap-2">
              <p className="font-semibold text-gray-800" style={{ fontFamily: 'Galey, sans-serif' }}>
                {d.pseudo ?? '—'} <span className="text-xs text-gray-400 font-normal">· {fmtDate(d.created_at)}</span>
              </p>
              <Badge label={FILTRES.find((f) => f.key === d.statut)?.label ?? d.statut}
                color={FILTRES.find((f) => f.key === d.statut)?.color ?? '#64748b'} />
            </div>
            {d.email_contact && <p className="text-xs text-gray-500">{d.email_contact}</p>}
            <div>{lien(d.lien_instagram, 'Instagram')}{lien(d.lien_tiktok, 'TikTok')}{lien(d.lien_autre, 'Autre lien')}</div>
            {d.message && <p className="text-sm text-gray-700 whitespace-pre-line">{d.message}</p>}
            {!!d.preuves_urls?.length && (
              <div className="flex gap-2 flex-wrap">
                {d.preuves_urls.map((u, i) => (
                  <a key={i} href={u} target="_blank" rel="noopener noreferrer">
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={u} alt={`preuve ${i + 1}`} className="w-20 h-20 object-cover rounded-lg border" />
                  </a>
                ))}
              </div>
            )}
            <div className="flex gap-2 pt-1">
              {d.statut === 'pending' && <>
                <ActionBtn label="Accorder le badge" color="#16a34a" onClick={() => agir('influenceur_valider', d)} />
                <ActionBtn label="Refuser" color="#dc2626" onClick={() => agir('influenceur_refuser', d)} />
              </>}
              {d.statut === 'approved' && <ActionBtn label="Révoquer le badge" color="#dc2626" onClick={() => agir('influenceur_revoquer', d)} />}
            </div>
          </div>
        ))}
    </div>
  );
}
