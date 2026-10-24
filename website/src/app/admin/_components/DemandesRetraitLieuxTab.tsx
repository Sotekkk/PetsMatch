'use client';
// Demandes de retrait d'un lieu (lieu naturel, ou lieu pet-friendly sans
// gestionnaire) envoyées par les membres. Accepter : lieu naturel supprimé,
// fiche pet-friendly masquée ; refuser : motif transmis au demandeur.
// API : /api/admin/moderation (type=retraits, actions retrait_accepter / retrait_refuser).
import React, { useCallback, useEffect, useState } from 'react';
import { apiFetch } from '@/lib/api-fetch';
import { libelleRaisonRetrait } from '@/components/lieux/DemandeRetraitLieu';
import { ActionBtn, Badge, fmtDate } from './ui';

interface Demande {
  id: string; nature: string; raison: string; commentaire: string | null; statut: string; motif: string | null;
  place_nom: string | null; created_at: string; traite_le: string | null;
  natural_place_id: string | null; petfriendly_place_id: string | null;
  demandeur: string; nb_demandes: number;
  place: { id: string; nom: string | null; adresse: string | null; ville?: string | null; lat: number | null; lng: number | null; photo_url: string | null; statut: string | null } | null;
}

export default function DemandesRetraitLieuxTab({ nature, onCount }: { nature: 'naturel' | 'petfriendly'; onCount?: (n: number) => void }) {
  const [vue, setVue] = useState<'en_attente' | 'traitees'>('en_attente');
  const [demandes, setDemandes] = useState<Demande[]>([]);
  const [loading, setLoading] = useState(true);
  const [erreur, setErreur] = useState<string | null>(null);
  const [ouvert, setOuvert] = useState<string | null>(null);
  const [motif, setMotif] = useState('');
  const [enCours, setEnCours] = useState(false);

  const load = useCallback(async () => {
    setLoading(true); setErreur(null);
    const r = await apiFetch(`/api/admin/moderation?type=retraits&nature=${nature}&statut=${vue}`);
    const j = await r.json().catch(() => ({}));
    if (!r.ok) setErreur(j.error ?? 'Erreur de chargement');
    const items = (j.items ?? []) as Demande[];
    setDemandes(items);
    if (vue === 'en_attente') onCount?.(items.length);
    setLoading(false);
  }, [nature, vue, onCount]);
  useEffect(() => { void load(); }, [load]);

  async function agir(action: 'retrait_accepter' | 'retrait_refuser', d: Demande) {
    if (action === 'retrait_refuser' && !motif.trim()) { alert('Indiquez le motif : il est transmis à la personne.'); return; }
    if (action === 'retrait_accepter' && !confirm(nature === 'naturel'
      ? `Supprimer définitivement « ${d.place?.nom ?? d.place_nom ?? ''} » (avis et photos compris) ?`
      : `Masquer « ${d.place?.nom ?? d.place_nom ?? ''} » de la carte ?`)) return;
    setEnCours(true);
    const r = await apiFetch('/api/admin/moderation', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action, id: d.id, motif: motif.trim() }),
    });
    setEnCours(false);
    if (!r.ok) { alert((await r.json().catch(() => ({}))).error ?? 'Erreur'); return; }
    setMotif(''); setOuvert(null);
    void load();
  }

  const lienFiche = (d: Demande) => {
    const id = d.natural_place_id ?? d.petfriendly_place_id;
    if (!id) return null;
    return nature === 'naturel' ? `/lieux-naturels/${id}` : `/animal-friendly/${id}`;
  };

  return (
    <div className="space-y-3">
      <div className="flex gap-2">
        {([['en_attente', 'En attente'], ['traitees', 'Traitées']] as const).map(([k, l]) => (
          <button key={k} type="button" onClick={() => { setVue(k); setOuvert(null); setMotif(''); }}
            className={`px-3 py-1.5 rounded-full text-xs font-semibold border ${vue === k ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]' : 'bg-white text-gray-600 border-gray-200'}`}>{l}</button>
        ))}
      </div>
      {erreur && <p className="text-sm text-red-600">{erreur}</p>}
      {loading ? <p className="text-sm text-gray-400">Chargement…</p> : demandes.length === 0 ? (
        <div className="bg-white rounded-2xl border border-gray-100 p-10 text-center text-sm text-gray-500">
          {vue === 'en_attente' ? 'Aucune demande de retrait en attente.' : 'Aucune demande traitée.'}
        </div>
      ) : demandes.map(d => {
        const lien = lienFiche(d);
        const lat = d.place?.lat, lng = d.place?.lng;
        return (
          <div key={d.id} className="bg-white rounded-2xl p-4 shadow-sm flex gap-4">
            <div className="w-24 h-24 rounded-lg overflow-hidden bg-gray-100 shrink-0">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              {d.place?.photo_url && <img src={d.place.photo_url} alt="" className="w-full h-full object-cover" />}
            </div>
            <div className="flex-1 min-w-0 space-y-1">
              <div className="flex items-center gap-2 flex-wrap">
                <p className="font-semibold text-gray-800" style={{ fontFamily: 'Galey, sans-serif' }}>{d.place?.nom ?? d.place_nom ?? 'Lieu supprimé'}</p>
                {d.statut === 'acceptee' && <Badge label="Acceptée" color="#16a34a" />}
                {d.statut === 'refusee' && <Badge label="Refusée" color="#dc2626" />}
                {d.statut === 'en_attente' && d.nb_demandes > 1 && <Badge label={`${d.nb_demandes} demandes sur ce lieu`} color="#d97706" />}
              </div>
              <p className="text-xs text-gray-500 truncate">{[d.place?.adresse, d.place?.ville].filter(Boolean).join(' · ') || 'sans adresse'}</p>
              <p className="text-sm text-gray-800"><span className="font-semibold">{libelleRaisonRetrait(d.raison)}</span></p>
              {d.commentaire && <p className="text-sm text-gray-700">« {d.commentaire} »</p>}
              <p className="text-xs text-gray-500">Demandé par {d.demandeur} le {fmtDate(d.created_at)}{d.traite_le ? ` · traité le ${fmtDate(d.traite_le)}` : ''}</p>
              {d.motif && <p className="text-xs text-gray-600">Réponse : {d.motif}</p>}
              <div className="flex gap-3 text-xs">
                {lien && <a href={lien} target="_blank" rel="noopener noreferrer" className="text-[#0C5C6C] underline">Fiche du lieu</a>}
                {lat != null && lng != null && (
                  <a href={`https://www.google.com/maps?q=${lat},${lng}`} target="_blank" rel="noopener noreferrer" className="text-[#0C5C6C] underline">Voir sur la carte</a>
                )}
              </div>
              {d.statut === 'en_attente' && (ouvert === d.id ? (
                <div className="space-y-2 pt-2">
                  <label className="block">
                    <span className="text-xs font-semibold text-gray-500">Motif (obligatoire en cas de refus, transmis à la personne)</span>
                    <textarea value={motif} onChange={e => setMotif(e.target.value)} rows={2}
                      className="w-full mt-1 border border-gray-200 rounded-xl px-3 py-2 text-sm resize-none" />
                  </label>
                  <div className="flex gap-2 flex-wrap">
                    <ActionBtn label={nature === 'naturel' ? 'Accepter (supprimer le lieu)' : 'Accepter (masquer la fiche)'} color="#16a34a" disabled={enCours} onClick={() => agir('retrait_accepter', d)} />
                    <ActionBtn label="Refuser" color="#dc2626" disabled={enCours} onClick={() => agir('retrait_refuser', d)} />
                    <ActionBtn label="Annuler" color="#64748b" disabled={enCours} onClick={() => { setOuvert(null); setMotif(''); }} />
                  </div>
                </div>
              ) : (
                <div className="pt-2"><ActionBtn label="Traiter" color="#0C5C6C" onClick={() => { setOuvert(d.id); setMotif(''); }} /></div>
              ))}
            </div>
          </div>
        );
      })}
    </div>
  );
}
