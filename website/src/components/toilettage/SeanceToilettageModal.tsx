'use client';
// Fiche technique d'une prestation de toilettage (une par rendez-vous) :
// travail effectué, produits, comportement, observations, photos avant /
// après, compte rendu partagé seulement si le pro le choisit. Miroir appli :
// lib/pages/pro/toilettage_seance_page.dart. Scopé au profil actif.
import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { uploadPhoto } from '@/lib/upload-media';
import { TRAVAUX_TOILETTAGE, COOPERATION_TOILETTAGE } from '@/lib/toilettage';

const TEAL = '#0C5C6C';
const horodatage = () => Date.now();

export interface RdvSeance {
  id: string; date_heure: string; duree_minutes: number | null; client_uid: string | null; client_profile_id: string | null;
  employe_id: string | null; prestation_debut_le?: string | null; pret_le?: string | null;
}
export interface SeanceToilettage {
  id: string; rdv_id: string | null; fiche_id: string | null; animal_id: string; employe_id: string | null;
  date_seance: string; duree_minutes: number | null; travaux: string[] | null;
  longueur_coupe: string | null; zones: string | null; finition: string | null; produits: string | null;
  cooperation: string | null; sensibilites: string | null; difficultes: string | null; precautions: string | null;
  observations: string | null; compte_rendu: string | null; conseils_pelage?: string | null; partage_proprietaire: boolean;
}
interface Photo { id: string; type: string; url: string; rdv_id: string | null }

const CHAMPS = ['longueur_coupe', 'zones', 'finition', 'produits', 'sensibilites', 'difficultes', 'precautions', 'observations', 'compte_rendu', 'conseils_pelage'] as const;
type Champ = typeof CHAMPS[number];

export default function SeanceToilettageModal({ animalId, animalNom, proUid, profileId, rdv, seance, prestation, onClose, onSaved }: {
  animalId: string; animalNom: string; proUid: string; profileId: string;
  rdv?: RdvSeance | null; seance?: SeanceToilettage | null; prestation?: string;
  onClose: () => void; onSaved: () => void;
}) {
  const rdvId = rdv?.id ?? seance?.rdv_id ?? null;
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [seanceId, setSeanceId] = useState<string | null>(seance?.id ?? null);
  const [ficheId, setFicheId] = useState<string | null>(null);
  const [dejaPartage, setDejaPartage] = useState(!!seance?.partage_proprietaire);
  const [travaux, setTravaux] = useState<string[]>(seance?.travaux ?? []);
  const [cooperation, setCooperation] = useState<string | null>(seance?.cooperation ?? null);
  const [partage, setPartage] = useState(!!seance?.partage_proprietaire);
  const [date, setDate] = useState((seance?.date_seance ?? rdv?.date_heure ?? new Date().toISOString()).slice(0, 10));
  const [duree, setDuree] = useState('');
  const [v, setV] = useState<Record<Champ, string>>(() => Object.fromEntries(CHAMPS.map(k => [k, (seance?.[k] as string | null) ?? ''])) as Record<Champ, string>);
  const [photos, setPhotos] = useState<Photo[]>([]);

  useEffect(() => {
    let annule = false;
    (async () => {
      const { data: f } = await supabase.from('fiches_toilettage').select('id, longueur_coupe, shampooing_prefere')
        .eq('pro_profile_id', profileId).eq('animal_id', animalId).maybeSingle();
      const fiche = f as { id: string; longueur_coupe?: string | null; shampooing_prefere?: string | null } | null;
      let s = seance ?? null;
      if (!s && rdvId) {
        const { data } = await supabase.from('seances_toilettage').select('*').eq('rdv_id', rdvId).maybeSingle();
        s = data as SeanceToilettage | null;
      }
      if (annule) return;
      setFicheId(fiche?.id ?? null);
      if (s) {
        setSeanceId(s.id); setTravaux(s.travaux ?? []); setCooperation(s.cooperation); setPartage(s.partage_proprietaire);
        setDejaPartage(s.partage_proprietaire); setDate(s.date_seance.slice(0, 10));
        setDuree(s.duree_minutes ? String(s.duree_minutes) : '');
        setV(Object.fromEntries(CHAMPS.map(k => [k, (s![k] as string | null) ?? ''])) as Record<Champ, string>);
      } else {
        // Nouvelle fiche : préremplie (durée réelle, coupe et shampooing habituels).
        const d = rdv?.prestation_debut_le && rdv?.pret_le
          ? Math.round((new Date(rdv.pret_le).getTime() - new Date(rdv.prestation_debut_le).getTime()) / 60000)
          : rdv?.duree_minutes ?? 0;
        if (d > 0) setDuree(String(d));
        setV(x => ({ ...x, longueur_coupe: fiche?.longueur_coupe ?? '', produits: fiche?.shampooing_prefere ?? '' }));
      }
      if (fiche?.id && rdvId) {
        const { data: ph } = await supabase.from('fiches_toilettage_photos').select('id, type, url, rdv_id')
          .eq('fiche_id', fiche.id).eq('rdv_id', rdvId).order('created_at');
        if (!annule) setPhotos((ph ?? []) as Photo[]);
      }
      if (!annule) setLoading(false);
    })();
    return () => { annule = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [animalId, profileId, rdvId]);

  async function assurerFiche(): Promise<string> {
    if (ficheId) return ficheId;
    const { data, error } = await supabase.from('fiches_toilettage').insert({
      pro_uid: proUid, pro_profile_id: profileId, animal_id: animalId,
      ...(rdv?.client_uid ? { client_uid: rdv.client_uid } : {}),
      ...(rdv?.client_profile_id ? { client_profile_id: rdv.client_profile_id } : {}),
    }).select('id').single();
    if (error) throw error;
    setFicheId(data.id as string);
    return data.id as string;
  }

  async function ajouterPhoto(type: 'avant' | 'apres', file: File) {
    setUploading(true);
    try {
      const fid = await assurerFiche();
      const url = await uploadPhoto(file, `fiches_toilettage/${fid}_${type}_${horodatage()}.jpg`, { maxDim: 1600 });
      const { data, error } = await supabase.from('fiches_toilettage_photos')
        .insert({ fiche_id: fid, ...(rdvId ? { rdv_id: rdvId } : {}), type, url }).select('id, type, url, rdv_id').single();
      if (error) throw error;
      setPhotos(p => [...p, data as Photo]);
    } catch (e) { alert(`Photo non enregistrée : ${(e as Error).message}`); }
    setUploading(false);
  }

  async function supprimerPhoto(p: Photo) {
    await supabase.from('fiches_toilettage_photos').delete().eq('id', p.id);
    setPhotos(x => x.filter(y => y.id !== p.id));
  }

  async function enregistrer() {
    if (partage && !v.compte_rendu.trim()) { alert('Rédigez le compte rendu à partager avec le propriétaire.'); return; }
    setSaving(true);
    try {
      const fid = await assurerFiche();
      const t = (k: Champ) => v[k].trim() || null;
      const data = {
        fiche_id: fid, animal_id: animalId, pro_uid: proUid, pro_profile_id: profileId,
        ...(rdvId ? { rdv_id: rdvId } : {}), ...(rdv?.employe_id ? { employe_id: rdv.employe_id } : {}),
        date_seance: date, duree_minutes: parseInt(duree) || null, travaux, cooperation,
        ...Object.fromEntries(CHAMPS.map(k => [k, t(k)])),
        partage_proprietaire: partage, updated_at: new Date().toISOString(),
      };
      let id = seanceId;
      if (id) {
        const { error } = await supabase.from('seances_toilettage').update(data).eq('id', id);
        if (error) throw error;
      } else {
        const { data: row, error } = await supabase.from('seances_toilettage').insert(data).select('id').single();
        if (error) throw error;
        id = row.id as string; setSeanceId(id);
      }
      // Partagé pour la première fois : le propriétaire est prévenu (choix du pro).
      if (partage && !dejaPartage && rdv?.client_uid) {
        await supabase.from('notifications').insert({
          uid: rdv.client_uid, type: 'toilettage_cr', title: 'Compte rendu de toilettage',
          body: `Le compte rendu du toilettage de ${animalNom} est disponible.`,
          ...(rdv.client_profile_id ? { profile_id: rdv.client_profile_id } : {}),
          data: { animalId, seance_id: id }, read: false,
        });
        setDejaPartage(true);
      }
      onSaved(); onClose();
    } catch (e) {
      const m = (e as Error).message ?? '';
      alert(m.includes('seances_toilettage') || m.includes('column') ? 'Migration migration_toilettage_fiche.sql à passer.' : m);
    }
    setSaving(false);
  }

  const champ = (k: Champ, label: string, lignes = 1) => (
    <label className="block">
      <span className="text-xs font-semibold text-gray-600">{label}</span>
      {lignes > 1
        ? <textarea value={v[k]} onChange={e => setV(x => ({ ...x, [k]: e.target.value }))} rows={lignes} className="mt-1 w-full border border-gray-200 rounded-xl px-3 py-2 text-sm resize-none" />
        : <input value={v[k]} onChange={e => setV(x => ({ ...x, [k]: e.target.value }))} className="mt-1 w-full border border-gray-200 rounded-xl px-3 py-2 text-sm" />}
    </label>
  );
  const puce = (actif: boolean, label: string, onClick: () => void) => (
    <button key={label} type="button" onClick={onClick} className="px-3 py-1.5 rounded-full text-xs font-semibold border"
      style={actif ? { background: TEAL, color: '#fff', borderColor: TEAL } : { background: '#fff', color: '#1F2A2E', borderColor: '#E5E7EB' }}>{label}</button>
  );
  const photosType = (type: 'avant' | 'apres', titre: string) => (
    <div>
      <div className="flex items-center justify-between">
        <p className="text-sm font-semibold text-[#1F2A2E]">{titre}</p>
        <label className={`text-xs font-semibold cursor-pointer ${uploading ? 'opacity-50 pointer-events-none' : ''}`} style={{ color: TEAL }}>
          Ajouter
          <input type="file" accept="image/*" className="hidden" onChange={e => { const f = e.target.files?.[0]; if (f) ajouterPhoto(type, f); e.target.value = ''; }} />
        </label>
      </div>
      <div className="flex gap-2 flex-wrap mt-1">
        {photos.filter(p => p.type === type).length === 0 && <p className="text-xs text-gray-400">Aucune photo.</p>}
        {photos.filter(p => p.type === type).map(p => (
          <div key={p.id} className="relative">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={p.url} alt="" className="w-20 h-20 rounded-lg object-cover" />
            <button onClick={() => supprimerPhoto(p)} className="absolute top-0.5 right-0.5 w-5 h-5 rounded-full bg-black/60 text-white text-xs leading-none">×</button>
          </div>
        ))}
      </div>
    </div>
  );
  const section = (titre: string, children: React.ReactNode) => (
    <div className="border border-gray-100 rounded-2xl p-4 space-y-3">
      <p className="text-sm font-bold text-[#1F2A2E]">{titre}</p>
      {children}
    </div>
  );

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 sm:px-4" onClick={onClose}>
      <div className="bg-[#F8F8F6] rounded-t-3xl sm:rounded-2xl w-full max-w-2xl max-h-[92vh] flex flex-col" onClick={e => e.stopPropagation()}>
        <div className="px-5 pt-5 pb-3">
          <p className="font-bold text-[#1F2A2E]">Fiche technique — {animalNom}</p>
          {prestation && <p className="text-sm text-gray-500">{prestation}</p>}
        </div>
        {loading ? <div className="flex justify-center py-16"><div className="w-7 h-7 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div> : (
          <div className="flex-1 overflow-y-auto px-5 pb-4 space-y-3 bg-[#F8F8F6]">
            <div className="bg-white rounded-2xl p-4 grid grid-cols-2 gap-3">
              <label className="block"><span className="text-xs font-semibold text-gray-600">Date</span>
                <input type="date" value={date} onChange={e => setDate(e.target.value)} className="mt-1 w-full border border-gray-200 rounded-xl px-3 py-2 text-sm" /></label>
              <label className="block"><span className="text-xs font-semibold text-gray-600">Durée (min)</span>
                <input inputMode="numeric" value={duree} onChange={e => setDuree(e.target.value.replace(/\D/g, ''))} className="mt-1 w-full border border-gray-200 rounded-xl px-3 py-2 text-sm" /></label>
            </div>
            <div className="bg-white rounded-2xl">{section('Travail effectué', <>
              <div className="flex flex-wrap gap-1.5">
                {TRAVAUX_TOILETTAGE.map(([k, l]) => puce(travaux.includes(k), l, () => setTravaux(t => t.includes(k) ? t.filter(x => x !== k) : [...t, k])))}
              </div>
              {champ('longueur_coupe', 'Longueur de coupe / sabot')}
              {champ('zones', 'Zones travaillées', 2)}
              {champ('finition', 'Finition')}
              {champ('produits', 'Produits utilisés', 2)}
            </>)}</div>
            <div className="bg-white rounded-2xl">{section('Comportement', <>
              <div className="flex flex-wrap gap-1.5">
                {COOPERATION_TOILETTAGE.map(([k, l]) => puce(cooperation === k, l, () => setCooperation(c => c === k ? null : k)))}
              </div>
              {champ('sensibilites', 'Sensibilités observées', 2)}
              {champ('difficultes', 'Difficultés rencontrées', 2)}
              {champ('precautions', 'Précautions pour la prochaine fois', 2)}
            </>)}</div>
            <div className="bg-white rounded-2xl">{section('Observations', <>
              {champ('observations', 'Observations (peau, pelage, parasites, nœuds…) — usage interne', 3)}
              <p className="text-xs text-gray-500">Une anomalie de santé se signale au propriétaire, sans diagnostic.</p>
            </>)}</div>
            <div className="bg-white rounded-2xl">{section('Photos avant / après', <>
              {photosType('avant', 'Avant')}
              {photosType('apres', 'Après')}
              <p className="text-xs text-gray-500">Les photos restent dans la fiche du salon : elles ne sont jamais publiées.</p>
            </>)}</div>
            <div className="bg-white rounded-2xl">{section('Compte rendu pour le propriétaire', <>
              {champ('compte_rendu', 'Compte rendu court', 4)}
              {champ('conseils_pelage', 'Conseils de soin du pelage (brossage, produits, prochain toilettage conseillé…)', 4)}
              <label className="flex items-start gap-2 text-sm">
                <input type="checkbox" checked={partage} onChange={e => setPartage(e.target.checked)} className="mt-0.5" />
                <span>Partager avec le propriétaire
                  <span className="block text-xs text-gray-500">{dejaPartage ? "Déjà partagé : visible dans l'onglet Consultations de son animal." : "Il le retrouvera dans l'onglet Consultations de son animal et sera prévenu."}</span>
                </span>
              </label>
            </>)}</div>
          </div>
        )}
        <div className="px-5 py-3 flex gap-2 border-t border-gray-100 bg-white rounded-b-2xl">
          <button onClick={onClose} className="flex-1 py-2.5 rounded-xl text-sm font-semibold border border-gray-200">Annuler</button>
          <button onClick={enregistrer} disabled={saving || loading} className="flex-1 py-2.5 rounded-xl text-sm font-semibold text-white disabled:opacity-50" style={{ background: TEAL }}>
            {saving ? 'Enregistrement…' : 'Enregistrer la fiche technique'}
          </button>
        </div>
      </div>
    </div>
  );
}
