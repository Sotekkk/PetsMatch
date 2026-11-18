'use client';
// Toiletteur — cartes de séances (forfaits_toilettage) dans « Mes prestations » :
// ex. « 5 toilettages complets » payés d'avance, chaque rendez-vous du client
// est décompté de sa carte, sans facture à la séance. Miroir appli :
// toilettage_prestations_page.dart (_ForfaitToilettageForm).
import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { resumeForfaitToilettage, type ForfaitToilettage } from '@/lib/forfait-toilettage';

const ORANGE = '#FFB74D';

type Form = { id?: string; nom: string; prestation_id: string; nb_seances: string; prix: string; validite_mois: string; description: string };
const VIDE: Form = { nom: '', prestation_id: '', nb_seances: '5', prix: '', validite_mois: '', description: '' };

export default function CartesSeances({ proUid, profileId, prestations }: {
  proUid: string; profileId: string; prestations: { id: string; nom: string }[];
}) {
  const [cartes, setCartes] = useState<ForfaitToilettage[]>([]);
  const [form, setForm] = useState<Form | null>(null);
  const [erreur, setErreur] = useState('');
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    const { data, error } = await supabase.from('forfaits_toilettage').select('*')
      .eq('pro_profile_id', profileId).eq('actif', true).order('created_at');
    setCartes(error ? [] : (data ?? []) as ForfaitToilettage[]);
  }, [profileId]);
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    load();
  }, [load]);

  async function save() {
    if (!form) return;
    const nb = parseInt(form.nb_seances, 10) || 0;
    const prix = Number(form.prix.replace(',', '.')) || 0;
    if (!form.nom.trim() || nb < 1 || prix <= 0) { setErreur('Nom, nombre de séances et prix sont obligatoires.'); return; }
    setSaving(true); setErreur('');
    const v = parseInt(form.validite_mois, 10);
    const payload = {
      pro_uid: proUid, pro_profile_id: profileId, nom: form.nom.trim(), prestation_id: form.prestation_id || null,
      nb_seances: nb, prix, validite_mois: v > 0 ? v : null, description: form.description.trim() || null,
    };
    const { error } = form.id
      ? await supabase.from('forfaits_toilettage').update(payload).eq('id', form.id)
      : await supabase.from('forfaits_toilettage').insert(payload);
    setSaving(false);
    if (error) { setErreur(error.message); return; }
    setForm(null);
    await load();
  }

  async function retirer(id: string) {
    // Désactivée : les cartes déjà vendues restent décomptées normalement.
    await supabase.from('forfaits_toilettage').update({ actif: false }).eq('id', id);
    await load();
  }

  const nomPrestation = (id: string | null) => prestations.find(p => p.id === id)?.nom;
  const champ = 'mt-1 w-full border border-gray-200 rounded-xl px-3 py-2 text-sm text-gray-900';

  return (
    <div className="mt-8">
      <div className="flex items-center justify-between mb-1">
        <h2 className="text-base font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Cartes de séances</h2>
        <button onClick={() => { setForm({ ...VIDE }); setErreur(''); }}
          className="text-white rounded-xl px-3 py-2 text-sm font-semibold" style={{ background: ORANGE }}>+ Carte</button>
      </div>
      <p className="text-sm text-gray-500 mb-3">
        Ex. « 5 toilettages complets » payés d&apos;avance : chaque rendez-vous du client est décompté de sa carte, sans facture à la séance.
        Le client peut la choisir en réservant, ou vous la vendez depuis le dossier de la séance.
      </p>

      {form && (
        <div className="border rounded-2xl p-4 mb-4 space-y-3" style={{ borderColor: `${ORANGE}55` }}>
          <label className="block text-xs font-medium text-gray-500">Nom
            <input value={form.nom} onChange={e => setForm({ ...form, nom: e.target.value })} placeholder="Ex. Carte 5 toilettages" className={champ} />
          </label>
          <label className="block text-xs font-medium text-gray-500">Prestation couverte
            <select value={form.prestation_id} onChange={e => setForm({ ...form, prestation_id: e.target.value })} className={`${champ} bg-white`}>
              <option value="">Toutes les prestations</option>
              {prestations.map(p => <option key={p.id} value={p.id}>{p.nom}</option>)}
            </select>
          </label>
          <div className="grid grid-cols-2 gap-3">
            <label className="text-xs font-medium text-gray-500">Nombre de séances
              <input type="number" min={1} value={form.nb_seances} onChange={e => setForm({ ...form, nb_seances: e.target.value })} className={champ} />
            </label>
            <label className="text-xs font-medium text-gray-500">Prix de la carte (€ TTC)
              <input type="number" min={0} step="0.01" value={form.prix} onChange={e => setForm({ ...form, prix: e.target.value })} className={champ} />
            </label>
          </div>
          <label className="block text-xs font-medium text-gray-500">Validité en mois (facultatif)
            <input type="number" min={1} value={form.validite_mois} onChange={e => setForm({ ...form, validite_mois: e.target.value })} className={champ} />
          </label>
          <label className="block text-xs font-medium text-gray-500">Description (facultatif)
            <textarea rows={2} value={form.description} onChange={e => setForm({ ...form, description: e.target.value })} className={champ} />
          </label>
          {erreur && <p className="text-xs text-red-600">{erreur}</p>}
          <div className="flex gap-2">
            <button onClick={save} disabled={saving} className="flex-1 text-white rounded-xl py-2 text-sm font-semibold disabled:opacity-50" style={{ background: ORANGE }}>
              {saving ? 'Enregistrement…' : 'Enregistrer'}
            </button>
            <button onClick={() => setForm(null)} className="px-4 rounded-xl py-2 text-sm font-semibold border border-gray-200">Annuler</button>
          </div>
        </div>
      )}

      {cartes.length === 0 ? (
        <p className="text-sm text-gray-400">Aucune carte de séances.</p>
      ) : (
        <div className="space-y-2">
          {cartes.map(c => (
            <div key={c.id} className="border border-gray-100 rounded-xl p-3 flex items-start gap-3">
              <button type="button" className="flex-1 min-w-0 text-left" onClick={() => setForm({
                id: c.id, nom: c.nom, prestation_id: c.prestation_id ?? '', nb_seances: String(c.nb_seances), prix: String(c.prix),
                validite_mois: c.validite_mois ? String(c.validite_mois) : '', description: c.description ?? '',
              })}>
                <p className="text-sm font-semibold text-[#1F2A2E]">{c.nom}</p>
                <p className="text-xs text-gray-500">{resumeForfaitToilettage(c, nomPrestation(c.prestation_id))}</p>
                {c.description && <p className="text-xs text-gray-600 mt-0.5 line-clamp-2">{c.description}</p>}
              </button>
              <button onClick={() => retirer(c.id)} aria-label="Retirer la carte" className="text-gray-300 hover:text-red-400 shrink-0 text-sm">Retirer</button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
