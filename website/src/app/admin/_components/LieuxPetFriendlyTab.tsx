'use client';
// Modération des établissements pet-friendly (ex-onglet « Lieux » de l'appli).
import React, { useCallback, useEffect, useState } from 'react';
import { apiFetch } from '@/lib/api-fetch';
import { ActionBtn, Badge, InfoRow, Section, fmtDate } from './ui';

type Lieu = Record<string, unknown> & { id: string; nom?: string; statut?: string; created_at?: string };

const STATUTS: Record<string, { label: string; color: string }> = {
  en_attente_validation: { label: 'En attente', color: '#d97706' },
  actif: { label: 'Publié', color: '#16a34a' },
  suspendu: { label: 'Suspendu', color: '#dc2626' },
};
const OUI_NON: [string, string][] = [
  ['animaux_en_salle', 'Animaux en salle'], ['terrasse', 'Terrasse'], ['animaux_dans_chambre', 'Animaux en chambre'],
  ['eau_fournie', 'Eau fournie'], ['friandises', 'Friandises'], ['espace_detente', 'Espace détente'],
];

export default function LieuxPetFriendlyTab() {
  const [enAttente, setEnAttente] = useState<Lieu[]>([]);
  const [publies, setPublies] = useState<Lieu[]>([]);
  const [ouvert, setOuvert] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [erreur, setErreur] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true); setErreur(null);
    const r = await apiFetch('/api/admin/moderation?type=lieux');
    const j = await r.json().catch(() => ({}));
    if (!r.ok) setErreur(j.error ?? 'Erreur de chargement');
    setEnAttente(j.enAttente ?? []); setPublies(j.publies ?? []);
    setLoading(false);
  }, []);
  useEffect(() => { void load(); }, [load]);

  async function agir(action: string, l: Lieu) {
    if (action === 'lieu_suspendre' && !confirm(`Suspendre « ${l.nom ?? ''} » ? Il ne sera plus visible.`)) return;
    const r = await apiFetch('/api/admin/moderation', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action, id: l.id }),
    });
    if (!r.ok) { alert((await r.json().catch(() => ({}))).error ?? 'Erreur'); return; }
    void load();
  }

  const s = (v: unknown) => (v === null || v === undefined || v === '' ? null : String(v));

  function carte(l: Lieu) {
    const st = STATUTS[l.statut ?? ''] ?? { label: l.statut ?? '—', color: '#64748b' };
    const photos = [s(l.photo_profil_url), ...((l.photos as string[] | null) ?? [])].filter(Boolean) as string[];
    const detail = ouvert === l.id;
    return (
      <div key={l.id} className="bg-white rounded-2xl p-4 shadow-sm space-y-2">
        <div className="flex items-start justify-between gap-2 cursor-pointer" onClick={() => setOuvert(detail ? null : l.id)}>
          <div>
            <p className="font-semibold text-gray-800" style={{ fontFamily: 'Galey, sans-serif' }}>{l.nom ?? '—'}</p>
            <p className="text-xs text-gray-500">
              {[s(l.categorie), s(l.sous_categorie), s(l.ville)].filter(Boolean).join(' · ')} · déposé le {fmtDate(l.created_at)}
            </p>
          </div>
          <Badge label={st.label} color={st.color} />
        </div>
        {detail && (
          <div className="space-y-3 pt-2 border-t">
            {photos.length > 0 && (
              <div className="flex gap-2 flex-wrap">
                {photos.map((u, i) => (
                  <a key={i} href={u} target="_blank" rel="noopener noreferrer">
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={u} alt="" className="w-24 h-24 object-cover rounded-lg border" />
                  </a>
                ))}
              </div>
            )}
            {s(l.description) && <p className="text-sm text-gray-700 whitespace-pre-line">{s(l.description)}</p>}
            <div className="grid grid-cols-2 gap-3">
              <InfoRow label="Adresse" value={[s(l.adresse), s(l.code_postal), s(l.ville)].filter(Boolean).join(' ')} />
              <InfoRow label="SIRET" value={s(l.siret)} mono />
              <InfoRow label="Téléphone" value={s(l.telephone)} />
              <InfoRow label="E-mail" value={s(l.email_contact)} />
              <InfoRow label="Site web" value={s(l.site_web)} />
              <InfoRow label="Formule" value={s(l.plan)} />
              <InfoRow label="Espèces acceptées" value={Array.isArray(l.especes_acceptees) ? (l.especes_acceptees as string[]).join(', ') : s(l.especes_acceptees)} />
              <InfoRow label="Animaux max / poids max" value={[s(l.nb_animaux_max), s(l.poids_max_kg) && `${s(l.poids_max_kg)} kg`].filter(Boolean).join(' / ')} />
              <InfoRow label="Frais par nuit (animal)" value={s(l.frais_animal_nuit) && `${s(l.frais_animal_nuit)} €`} />
            </div>
            <div className="flex flex-wrap gap-1.5">
              {OUI_NON.filter(([k]) => l[k] === true).map(([, label]) => <Badge key={label} label={label} color="#0C5C6C" />)}
            </div>
          </div>
        )}
        <div className="flex gap-2 pt-1">
          {l.statut === 'en_attente_validation' && <>
            <ActionBtn label="Valider et publier" color="#16a34a" onClick={() => agir('lieu_valider', l)} />
            <ActionBtn label="Refuser" color="#dc2626" onClick={() => agir('lieu_suspendre', l)} />
          </>}
          {l.statut === 'actif' && <ActionBtn label="Suspendre" color="#dc2626" onClick={() => agir('lieu_suspendre', l)} />}
          {l.statut === 'suspendu' && <ActionBtn label="Réactiver" color="#16a34a" onClick={() => agir('lieu_reactiver', l)} />}
        </div>
      </div>
    );
  }

  if (loading) return <p className="text-sm text-gray-400">Chargement…</p>;
  return (
    <div className="space-y-6">
      {erreur && <p className="text-sm text-red-600">{erreur}</p>}
      <Section title={`En attente de validation (${enAttente.length})`}>
        {enAttente.length === 0 ? <p className="text-sm text-gray-400">Rien à valider.</p> : enAttente.map(carte)}
      </Section>
      <Section title={`Publiés et suspendus (${publies.length})`}>
        {publies.length === 0 ? <p className="text-sm text-gray-400">Aucun établissement.</p> : publies.map(carte)}
      </Section>
    </div>
  );
}
