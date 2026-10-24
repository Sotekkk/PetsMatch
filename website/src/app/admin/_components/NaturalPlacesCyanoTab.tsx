'use client';
// Lieux naturels : alertes cyanobactéries en cours. L'équipe vérifie les
// alertes confirmées par photo (« Valider »), peut refuser la photo (l'alerte
// redevient « suspectée ») ou retirer l'alerte. Une alerte vérifiée ne peut
// plus être levée que par l'équipe (pm_natural_places_garde,
// migration_cyano_moderation.sql).
import React, { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { ActionBtn, Badge, fmtDate } from './ui';

interface Alerte {
  id: string; nom: string | null; adresse: string | null;
  lat: number | null; lng: number | null;
  alerte_cyano_statut: string | null; alerte_cyano_photo_url: string | null;
  alerte_cyano_date: string | null; alerte_cyano_uid: string | null;
  alerte_cyano_lat: number | null; alerte_cyano_lng: number | null;
  alerte_cyano_validee: boolean | null; alerte_cyano_validee_at: string | null;
}

const COLONNES = 'id, nom, adresse, lat, lng, alerte_cyano_statut, alerte_cyano_photo_url, alerte_cyano_date, alerte_cyano_uid, alerte_cyano_lat, alerte_cyano_lng, alerte_cyano_validee, alerte_cyano_validee_at';
const LEVEE = {
  alerte_cyano: false, alerte_cyano_date: null, alerte_cyano_profile_id: null, alerte_cyano_uid: null,
  alerte_cyano_statut: null, alerte_cyano_lat: null, alerte_cyano_lng: null, alerte_cyano_photo_url: null,
  alerte_cyano_validee: false, alerte_cyano_validee_at: null,
};

const aVerifier = (a: Alerte) => a.alerte_cyano_statut === 'confirme' && !a.alerte_cyano_validee;

export default function NaturalPlacesCyanoTab({ onAVerifier }: { onAVerifier?: (n: number) => void }) {
  const [alertes, setAlertes] = useState<Alerte[]>([]);
  const [auteurs, setAuteurs] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [enCours, setEnCours] = useState<string | null>(null);
  const [erreur, setErreur] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    const { data, error } = await supabase.from('natural_places').select(COLONNES)
      .eq('alerte_cyano', true).order('alerte_cyano_date', { ascending: false });
    if (error) setErreur(error.message);
    // Photos à vérifier d'abord.
    const liste = ((data ?? []) as Alerte[]).sort((a, b) => Number(aVerifier(b)) - Number(aVerifier(a)));
    setAlertes(liste);
    onAVerifier?.(liste.filter(aVerifier).length);
    const uids = [...new Set(liste.map((a) => a.alerte_cyano_uid).filter(Boolean))] as string[];
    if (uids.length) {
      const { data: profils } = await supabase.from('user_profiles')
        .select('uid, firstname, lastname, is_main').in('uid', uids);
      const noms: Record<string, string> = {};
      for (const p of (profils ?? []) as { uid: string; firstname: string | null; lastname: string | null; is_main: boolean | null }[]) {
        if (noms[p.uid] && !p.is_main) continue;
        noms[p.uid] = [p.firstname, p.lastname].filter(Boolean).join(' ') || p.uid;
      }
      setAuteurs(noms);
    }
    setLoading(false);
  }, [onAVerifier]);

  useEffect(() => { void load(); }, [load]);

  async function maj(a: Alerte, patch: Record<string, unknown>, question?: string) {
    if (question && !confirm(question)) return;
    setEnCours(a.id); setErreur(null);
    const { error } = await supabase.from('natural_places').update(patch).eq('id', a.id);
    setEnCours(null);
    if (error) { setErreur(error.message); return; }
    void load();
  }

  if (loading) return <p className="text-sm text-gray-400">Chargement…</p>;

  return (
    <div className="space-y-3">
      {erreur && <p className="text-sm text-red-600">{erreur}</p>}
      {alertes.length === 0 && (
        <div className="bg-white rounded-2xl border border-gray-100 p-12 text-center text-sm text-gray-500">Aucune alerte cyanobactéries en cours.</div>
      )}
      {alertes.map((a) => {
        const lat = a.alerte_cyano_lat ?? a.lat;
        const lng = a.alerte_cyano_lng ?? a.lng;
        const occupe = enCours === a.id;
        return (
          <div key={a.id} className="bg-white rounded-2xl p-4 shadow-sm flex gap-4">
            {a.alerte_cyano_photo_url ? (
              <a href={a.alerte_cyano_photo_url} target="_blank" rel="noopener noreferrer" className="shrink-0">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={a.alerte_cyano_photo_url} alt="" className="w-36 h-28 rounded-lg object-cover" />
              </a>
            ) : (
              <div className="w-36 h-28 rounded-lg bg-gray-100 shrink-0 flex items-center justify-center text-xs text-gray-400">Sans photo</div>
            )}
            <div className="flex-1 min-w-0 space-y-1">
              <div className="flex items-center gap-2 flex-wrap">
                <p className="font-semibold text-gray-800" style={{ fontFamily: 'Galey, sans-serif' }}>{a.nom ?? '—'}</p>
                {a.alerte_cyano_validee
                  ? <Badge label="Vérifiée" color="#dc2626" />
                  : a.alerte_cyano_statut === 'confirme'
                    ? <Badge label="Photo à vérifier" color="#d97706" />
                    : <Badge label="Suspectée" color="#d97706" />}
              </div>
              <p className="text-xs text-gray-500 truncate">{a.adresse ?? 'sans adresse'}</p>
              <p className="text-xs text-gray-500">
                Signalée le {a.alerte_cyano_date ? fmtDate(a.alerte_cyano_date) : '—'}
                {a.alerte_cyano_uid ? ` par ${auteurs[a.alerte_cyano_uid] ?? a.alerte_cyano_uid}` : ''}
                {a.alerte_cyano_validee && a.alerte_cyano_validee_at ? ` · vérifiée le ${fmtDate(a.alerte_cyano_validee_at)}` : ''}
              </p>
              <div className="flex gap-3 text-xs">
                <a href={`/lieux-naturels/${a.id}`} target="_blank" rel="noopener noreferrer" className="text-[#0C5C6C] underline">Fiche du lieu</a>
                {lat != null && lng != null && (
                  <a href={`https://www.google.com/maps?q=${lat},${lng}`} target="_blank" rel="noopener noreferrer" className="text-[#0C5C6C] underline">Point signalé sur la carte</a>
                )}
              </div>
              <div className="flex gap-2 flex-wrap pt-2">
                {aVerifier(a) && (
                  <>
                    <ActionBtn label="Valider" color="#16a34a" disabled={occupe}
                      onClick={() => maj(a, { alerte_cyano_validee: true, alerte_cyano_validee_at: new Date().toISOString() })} />
                    <ActionBtn label="Refuser la photo" color="#d97706" disabled={occupe}
                      onClick={() => maj(a, { alerte_cyano_statut: 'suspecte', alerte_cyano_photo_url: null },
                        'Refuser la photo ? L’alerte reste affichée comme « suspectée ».')} />
                  </>
                )}
                <ActionBtn label="Retirer l'alerte" color="#dc2626" disabled={occupe}
                  onClick={() => maj(a, LEVEE, `Retirer l’alerte cyanobactéries de « ${a.nom ?? ''} » ?`)} />
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}
