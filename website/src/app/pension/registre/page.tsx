'use client';

import { useState, useEffect, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { usePensionAccess } from '@/hooks/usePensionAccess';
import { supabase } from '@/lib/supabase';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { PensionEntreeModal, type PensionEntree } from '@/components/PensionEntreeModal';

// ── Helpers ───────────────────────────────────────────────────────────────────

const TEAL   = '#0C5C6C';
const GREEN  = '#6E9E57';
const PURPLE = '#7B5EA7';

function fmtDate(iso?: string | null) {
  if (!iso) return '—';
  try { return new Date(iso).toLocaleDateString('fr-FR'); } catch { return iso; }
}

function normalizeChip(s?: string | null) {
  return (s ?? '').replace(/[\s\-]/g, '');
}

const ESP_EMOJI: Record<string, string> = {
  chien: '🐕', chat: '🐈', lapin: '🐇', oiseau: '🦜',
  cheval: '🐴', nac: '🐹', ovin: '🐑', caprin: '🐐', porcin: '🐷',
};
const ESP_LABEL: Record<string, string> = {
  chien: 'Chien', chat: 'Chat', lapin: 'Lapin', oiseau: 'Oiseau',
  cheval: 'Cheval', nac: 'NAC', ovin: 'Ovin', caprin: 'Caprin', porcin: 'Porc',
};

function espEmoji(e?: string) { return ESP_EMOJI[e ?? ''] ?? '🐾'; }
function espLabel(e?: string) { return ESP_LABEL[e ?? ''] ?? (e ?? ''); }

// ── Page principale ───────────────────────────────────────────────────────────

export default function RegistrePensionPage() {
  const { user, userData, isPension, loading: authLoading } = usePensionAccess();
  const router = useRouter();
  const activeProfileId = useActiveProfile();

  const [tab, setTab]                   = useState<'en_pension' | 'sorti' | 'tous'>('en_pension');
  const [entrees, setEntrees]           = useState<PensionEntree[]>([]);
  const [puceToAnimalId, setPuceToAnimalId] = useState<Record<string, string>>({});
  const [loading, setLoading]           = useState(true);
  const [showForm, setShowForm]         = useState(false);
  const [editEntree, setEditEntree]     = useState<PensionEntree | null>(null);
  const [filterEspece, setFilterEspece] = useState('');
  const [showFilter, setShowFilter]     = useState(false);


  useEffect(() => {
    if (authLoading) return;
    if (!user) { router.push('/connexion'); return; }
    if (userData && !isPension) { router.push('/'); return; }
  }, [user, userData, isPension, authLoading, router]);

  const load = useCallback(async () => {
    if (!user) return;
    setLoading(true);
    let qEnt = supabase.from('pension_entrees').select('*').eq('pro_uid', user.uid).order('date_entree', { ascending: false });
    if (activeProfileId) qEnt = qEnt.eq('pro_profile_id', activeProfileId) as typeof qEnt;
    let qAcc = supabase.from('pension_acces').select('animal_id').eq('pro_uid', user.uid).eq('statut', 'approved');
    if (activeProfileId) qAcc = qAcc.eq('pro_profile_id', activeProfileId) as typeof qAcc;
    const [{ data: ent }, { data: acc }] = await Promise.all([qEnt, qAcc]);
    setEntrees((ent ?? []) as PensionEntree[]);

    const ids = (acc ?? []).map((a: { animal_id: string }) => a.animal_id);

    if (ids.length > 0) {
      const { data: animaux } = await supabase
        .from('animaux').select('id,identification').in('id', ids);
      const map: Record<string, string> = {};
      for (const a of animaux ?? []) {
        const puce = normalizeChip(a.identification);
        if (puce) map[puce] = a.id;
      }
      setPuceToAnimalId(map);
    }
    setLoading(false);
  }, [user, activeProfileId]);

  useEffect(() => { load(); }, [load]);

  async function marquerSorti(id: string) {
    const today = new Date().toISOString().split('T')[0];
    await supabase.from('pension_entrees').update({ statut: 'sorti', date_sortie_effective: today }).eq('id', id);
    setEntrees(prev => prev.map(e => e.id === id ? { ...e, statut: 'sorti', date_sortie_effective: today } : e));
  }

  // Export CSV
  function exportCsv() {
    const rows = filtered;
    const headers = ['Nom', 'Espèce', 'Race', 'Puce', 'Client', 'Téléphone', 'Email',
      'Date entrée', 'Sortie prévue', 'Sortie effective', 'Statut', 'Notes'];
    const csv = [
      headers.join(';'),
      ...rows.map(e => [
        e.animal_nom,
        espLabel(e.espece),
        e.race ?? '',
        e.puce ?? '',
        e.proprietaire_nom ?? '',
        e.proprietaire_contact ?? '',
        e.proprietaire_email ?? '',
        fmtDate(e.date_entree),
        fmtDate(e.date_sortie_prevue),
        fmtDate(e.date_sortie_effective),
        e.statut === 'en_pension' ? 'En pension' : 'Sorti',
        (e.notes ?? '').replace(/;/g, ','),
      ].join(';')),
    ].join('\n');
    const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8;' });
    const url  = URL.createObjectURL(blob);
    const a    = document.createElement('a');
    a.href = url; a.download = `registre-pension-${new Date().toISOString().split('T')[0]}.csv`;
    a.click(); URL.revokeObjectURL(url);
  }

  const allEspeces = [...new Set(entrees.map(e => e.espece).filter(Boolean))] as string[];

  let filtered = entrees;
  if (tab !== 'tous') filtered = filtered.filter(e => e.statut === tab);
  if (filterEspece) filtered = filtered.filter(e => e.espece === filterEspece);

  const counts = {
    en_pension: entrees.filter(e => e.statut === 'en_pension').length,
    sorti:      entrees.filter(e => e.statut === 'sorti').length,
    tous:       entrees.length,
  };

  if (!user || !userData) return null;

  return (
    <div style={{ minHeight: '100vh', background: '#F8F8F6', paddingBottom: 60 }}>
      {/* Header */}
      <div style={{ background: TEAL, padding: '20px 24px 0' }}>
        <div style={{ maxWidth: 900, margin: '0 auto' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 16 }}>
            <button onClick={() => router.back()}
              style={{ background: 'none', border: 'none', color: 'white', fontSize: 20, cursor: 'pointer', padding: 0 }}>←</button>
            <h1 style={{ margin: 0, fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 20, color: 'white', flex: 1 }}>
              Registre pension
            </h1>
            <button onClick={() => setShowFilter(f => !f)}
              style={{ background: 'rgba(255,255,255,0.15)', border: '1px solid rgba(255,255,255,0.3)',
                color: 'white', borderRadius: 20, padding: '6px 14px', cursor: 'pointer',
                fontFamily: 'Galey, sans-serif', fontSize: 12, fontWeight: 700 }}>
              ⚙ Filtrer{filterEspece ? ' ●' : ''}
            </button>
            <button onClick={exportCsv} disabled={entrees.length === 0}
              style={{ background: 'rgba(255,255,255,0.15)', border: '1px solid rgba(255,255,255,0.3)',
                color: 'white', borderRadius: 20, padding: '6px 14px', cursor: 'pointer',
                fontFamily: 'Galey, sans-serif', fontSize: 12, fontWeight: 700,
                opacity: entrees.length === 0 ? 0.4 : 1 }}>
              ↓ CSV
            </button>
            <button onClick={() => setShowForm(true)}
              style={{ background: 'rgba(255,255,255,0.2)', border: '1px solid rgba(255,255,255,0.4)',
                color: 'white', borderRadius: 20, padding: '6px 16px', cursor: 'pointer',
                fontFamily: 'Galey, sans-serif', fontSize: 13, fontWeight: 700 }}>
              + Nouvelle entrée
            </button>
          </div>

          {/* Filtres espèce */}
          {showFilter && (
            <div style={{ marginBottom: 12, display: 'flex', gap: 8, flexWrap: 'wrap' }}>
              {['', ...allEspeces].map(e => (
                <button key={e} onClick={() => setFilterEspece(e)}
                  style={{ padding: '4px 12px', borderRadius: 20,
                    background: filterEspece === e ? 'rgba(255,255,255,0.9)' : 'rgba(255,255,255,0.15)',
                    border: '1px solid rgba(255,255,255,0.3)',
                    color: filterEspece === e ? TEAL : 'white',
                    fontFamily: 'Galey, sans-serif', fontSize: 12, fontWeight: 700, cursor: 'pointer' }}>
                  {e ? `${espEmoji(e)} ${espLabel(e)}` : 'Toutes les espèces'}
                </button>
              ))}
            </div>
          )}

          {/* Onglets */}
          <div style={{ display: 'flex', gap: 0 }}>
            {([['en_pension', 'En pension'], ['sorti', 'Sortis'], ['tous', 'Tous']] as const).map(([val, label]) => (
              <button key={val} onClick={() => setTab(val)} style={{
                flex: 1, padding: '10px 0', background: 'none', border: 'none',
                borderBottom: tab === val ? '2px solid white' : '2px solid transparent',
                color: tab === val ? 'white' : 'rgba(255,255,255,0.6)',
                fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 13, cursor: 'pointer',
              }}>
                {label}{counts[val] > 0 ? ` (${counts[val]})` : ''}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Contenu */}
      <div style={{ maxWidth: 900, margin: '24px auto', padding: '0 16px' }}>
        {loading ? (
          <div style={{ textAlign: 'center', padding: 60, color: '#999' }}>Chargement…</div>
        ) : filtered.length === 0 ? (
          <div style={{ textAlign: 'center', padding: 60, color: '#aaa' }}>
            <div style={{ fontSize: 48, marginBottom: 12 }}>🐾</div>
            <p style={{ fontFamily: 'Galey, sans-serif', fontSize: 16 }}>Aucune entrée</p>
            <p style={{ fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#ccc' }}>
              Ajoutez manuellement ou scannez une puce depuis l&apos;application mobile
            </p>
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            {filtered.map(e => {
              const puce = normalizeChip(e.puce);
              const animalId = e.animal_id ?? puceToAnimalId[puce];
              return (
                <EntreeCard
                  key={e.id}
                  entree={e}
                  animalId={animalId}
                  proUid={user.uid}
                  proNom={userData?.nameElevage || userData?.firstname || 'Votre pension'}
                  onEdit={() => setEditEntree(e)}
                  onSorti={() => marquerSorti(e.id)}
                />
              );
            })}
          </div>
        )}
      </div>

      {/* Modals */}
      {showForm && (
        <PensionEntreeModal
          proUid={user.uid}
          proProfileId={activeProfileId || null}
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); load(); }}
        />
      )}
      {editEntree && (
        <PensionEntreeModal
          proUid={user.uid}
          proProfileId={activeProfileId || null}
          entree={editEntree}
          onClose={() => setEditEntree(null)}
          onSaved={() => { setEditEntree(null); load(); }}
        />
      )}
    </div>
  );
}

// ── Carte entrée ──────────────────────────────────────────────────────────────

function EntreeCard({ entree, animalId, proUid, proNom, onEdit, onSorti }: {
  entree: PensionEntree;
  animalId?: string;
  proUid: string;
  proNom: string;
  onEdit: () => void;
  onSorti: () => void;
}) {
  const inPension = entree.statut === 'en_pension';
  const bgColor   = inPension ? '#E0F2F1' : '#f3f4f6';
  const txtColor  = inPension ? TEAL : '#6b7280';
  const [sendingClaim, setSendingClaim] = useState(false);
  const [claimSent, setClaimSent] = useState(false);

  async function envoyerLienReclamation(e: React.MouseEvent) {
    e.stopPropagation();
    if (!animalId || !entree.proprietaire_email) return;
    setSendingClaim(true);
    try {
      const { data: claimRow, error } = await supabase.from('animal_claims').insert({
        animal_id: animalId,
        created_by_uid: proUid,
        email_destinataire: entree.proprietaire_email,
        nom_destinataire: entree.proprietaire_nom ?? null,
        tel_destinataire: entree.proprietaire_contact ?? null,
      }).select('token').single();
      if (error || !claimRow) { setSendingClaim(false); return; }
      const claimUrl = `${window.location.origin}/reclamer-animal/${claimRow.token}`;
      await fetch('/api/animal-claim/notify-email', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email: entree.proprietaire_email,
          nom_destinataire: entree.proprietaire_nom,
          animal_nom: entree.animal_nom,
          pro_nom: proNom,
          claim_url: claimUrl,
        }),
      });
      setClaimSent(true);
    } finally {
      setSendingClaim(false);
    }
  }

  return (
    <div style={{
      background: 'white', borderRadius: 14, padding: 16,
      border: `1px solid ${inPension ? 'rgba(12,92,108,0.18)' : '#e5e7eb'}`,
      boxShadow: '0 2px 8px rgba(0,0,0,0.04)',
      cursor: 'pointer',
    }} onClick={onEdit}>
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 14 }}>
        {/* Icône espèce */}
        <div style={{
          width: 46, height: 46, borderRadius: 10, background: bgColor,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: 22, flexShrink: 0,
        }}>
          {espEmoji(entree.espece)}
        </div>

        <div style={{ flex: 1, minWidth: 0 }}>
          {/* Nom + badge statut */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 3 }}>
            <span style={{ fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 15, color: '#1E2025' }}>
              {entree.animal_nom}
            </span>
            <span style={{
              padding: '2px 10px', borderRadius: 20, fontSize: 10, fontWeight: 700,
              fontFamily: 'Galey, sans-serif', background: bgColor, color: txtColor, whiteSpace: 'nowrap',
            }}>
              {inPension ? 'En pension' : 'Sorti'}
            </span>
            {animalId && (
              <a href={`/pension/fiche/${animalId}`}
                onClick={e => e.stopPropagation()}
                style={{
                  padding: '2px 10px', borderRadius: 20, fontSize: 10, fontWeight: 700,
                  fontFamily: 'Galey, sans-serif', background: 'rgba(123,94,167,0.1)',
                  color: PURPLE, textDecoration: 'none', whiteSpace: 'nowrap',
                }}>
                🔍 Voir fiche
              </a>
            )}
          </div>

          {/* Espèce + race + puce */}
          <p style={{ margin: '0 0 5px', fontFamily: 'Galey, sans-serif', fontSize: 12, color: '#9ca3af' }}>
            {[espLabel(entree.espece), entree.race].filter(Boolean).join(' · ')}
            {entree.puce ? ` — Puce ${entree.puce}` : ''}
          </p>

          <div style={{ borderTop: '1px solid #f3f4f6', margin: '8px 0' }} />

          {/* Client */}
          {(entree.proprietaire_nom || entree.proprietaire_contact || entree.proprietaire_email) && (
            <div style={{ margin: '0 0 4px' }}>
              {(entree.proprietaire_nom || entree.proprietaire_contact) && (
                <p style={{ margin: '0 0 1px', fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#374151' }}>
                  👤 {[entree.proprietaire_nom, entree.proprietaire_contact].filter(Boolean).join(' · ')}
                </p>
              )}
              {entree.proprietaire_email && (
                <p style={{ margin: 0, fontFamily: 'Galey, sans-serif', fontSize: 12, color: '#6b7280' }}>
                  ✉ {entree.proprietaire_email}
                </p>
              )}
              {animalId && entree.proprietaire_email && (
                <button onClick={envoyerLienReclamation} disabled={sendingClaim || claimSent}
                  style={{
                    marginTop: 6, padding: '4px 10px', borderRadius: 20, border: `1px solid ${claimSent ? GREEN : PURPLE}`,
                    background: 'transparent', color: claimSent ? GREEN : PURPLE,
                    cursor: sendingClaim || claimSent ? 'default' : 'pointer',
                    fontFamily: 'Galey, sans-serif', fontSize: 11, fontWeight: 700,
                  }}>
                  {claimSent ? '✓ Lien envoyé' : sendingClaim ? 'Envoi…' : '🔗 Envoyer le lien de réclamation'}
                </button>
              )}
            </div>
          )}

          {/* Dates */}
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: '4px 16px' }}>
            <span style={{ fontFamily: 'Galey, sans-serif', fontSize: 12, color: '#6b7280' }}>
              🔑 Entrée : {fmtDate(entree.date_entree)}
            </span>
            {entree.date_sortie_prevue && (
              <span style={{ fontFamily: 'Galey, sans-serif', fontSize: 12, color: '#6b7280' }}>
                📅 Prévue : {fmtDate(entree.date_sortie_prevue)}
              </span>
            )}
            {entree.date_sortie_effective && (
              <span style={{ fontFamily: 'Galey, sans-serif', fontSize: 12, color: GREEN, fontWeight: 600 }}>
                ✓ Sorti le : {fmtDate(entree.date_sortie_effective)}
              </span>
            )}
          </div>

          {/* Notes */}
          {entree.notes && (
            <p style={{ margin: '6px 0 0', fontFamily: 'Galey, sans-serif', fontSize: 12, color: '#6b7280',
              overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
              {entree.notes}
            </p>
          )}
        </div>

        {/* Bouton marquer sorti */}
        {inPension && (
          <button onClick={e => { e.stopPropagation(); onSorti(); }} style={{
            padding: '6px 14px', borderRadius: 20, border: `1px solid ${TEAL}`,
            background: 'transparent', color: TEAL, cursor: 'pointer',
            fontFamily: 'Galey, sans-serif', fontSize: 12, fontWeight: 700, whiteSpace: 'nowrap',
            flexShrink: 0,
          }}>
            Sorti →
          </button>
        )}
      </div>
    </div>
  );
}

