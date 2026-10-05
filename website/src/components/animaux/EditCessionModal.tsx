'use client';

// Modifier une cession EN ATTENTE (pas encore signée par les deux parties)
// sans la refaire : coordonnées de l'acquéreur, qualité, date, prix, notes.
// Couvre les deux circuits — cession de l'app (`cessions`, statut animal
// 'cession_en_cours') et cession du site sans ligne `cessions` (statut
// animal 'en_attente_cession', sortie déjà inscrite au registre).
// Miroir app : lib/pages/eleveur/animaux/edit_cession_sheet.dart.

import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { fetchContactAcquereur } from '@/lib/contact-acquereur';

const QUALITES = [
  { value: 'particulier', label: 'Particulier' },
  { value: 'eleveur',     label: 'Éleveur' },
  { value: 'refuge',      label: 'Refuge / Association' },
  { value: 'autre',       label: 'Autre' },
];

export interface EditCessionAnimal {
  id: string;
  nom?: string;
  statut?: string;
  uid_acquereur?: string | null;
  destinataire_qualite?: string;
  destinataire_nom?: string;
  destinataire_adresse?: string;
  cession_prix?: number | null;
  cession_notes?: string;
  date_sortie?: string;
}

interface Props {
  animal: EditCessionAnimal;
  /** Ligne `cessions` en cours (circuit app), null pour une cession du site. */
  cession: Record<string, unknown> | null;
  /** uid du cédant (lignes du registre à corriger). */
  cedantUid: string;
  onClose: () => void;
  onSaved: () => void;
}

const inputCls = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]';

export default function EditCessionModal({ animal, cession, cedantUid, onClose, onSaved }: Props) {
  const str = (v: unknown) => (v ?? '').toString();
  const [qualite, setQualite] = useState(str(cession?.qualite) || animal.destinataire_qualite || 'particulier');
  const [prenom, setPrenom]   = useState(str(cession?.prenom_acquereur));
  const [nom, setNom]         = useState('');
  const [email, setEmail]     = useState(str(cession?.email_acquereur));
  const [tel, setTel]         = useState(str(cession?.tel_acquereur));
  const [adresse, setAdresse] = useState(str(cession?.adresse_acquereur) || animal.destinataire_adresse || '');
  const [dateCession, setDateCession] = useState(
    (str(cession?.date_cession) || animal.date_sortie || new Date().toISOString()).slice(0, 10));
  const [prix, setPrix]   = useState(
    cession?.prix != null ? str(cession.prix) : animal.cession_prix != null ? String(animal.cession_prix) : '');
  const [notes, setNotes] = useState(str(cession?.notes) || animal.cession_notes || '');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving]   = useState(false);
  const [error, setError]     = useState('');

  const dejaSigneAcq = cession?.statut === 'signe_acquereur' || !!cession?.signature_acquereur;

  // Complète avec toutes les sources connues (profil, réservation, certificat…)
  // et sépare le nom du prénom (`nom_acquereur` contient le nom complet).
  useEffect(() => {
    let cancelled = false;
    fetchContactAcquereur({ id: animal.id, uid_acquereur: animal.uid_acquereur, destinataire_nom: animal.destinataire_nom })
      .then(({ contact }) => {
        if (cancelled) return;
        const p = prenom || contact.prenom || '';
        let n = contact.nom || str(cession?.nom_acquereur) || animal.destinataire_nom || '';
        if (p && n.toLowerCase().startsWith(p.toLowerCase() + ' ')) n = n.slice(p.length).trim();
        setPrenom(p); setNom(n);
        setEmail(e => e || contact.email || '');
        setTel(t => t || contact.tel || '');
        setAdresse(a => (contact.adresse && !/\b\d{5}\b/.test(a) && /\b\d{5}\b/.test(contact.adresse)) ? contact.adresse : (a || contact.adresse || ''));
      })
      .catch(() => {})
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function save() {
    if (!nom.trim()) { setError('Le nom de l\'acquéreur est requis.'); return; }
    if (dejaSigneAcq && !confirm('L\'acquéreur a déjà signé : après modification, il devra signer à nouveau le récapitulatif. Continuer ?')) return;
    setSaving(true); setError('');
    const nomComplet = [prenom.trim(), nom.trim()].filter(Boolean).join(' ');
    const prixNum = prix.trim() ? parseFloat(prix.replace(',', '.')) : null;
    try {
      if (cession?.id) {
        const { error: e } = await supabase.from('cessions').update({
          qualite,
          prenom_acquereur:  prenom.trim() || null,
          nom_acquereur:     nomComplet,
          email_acquereur:   email.trim() || null,
          tel_acquereur:     tel.trim() || null,
          adresse_acquereur: adresse.trim() || null,
          date_cession:      dateCession,
          prix:              prixNum,
          notes:             notes.trim() || null,
          // Contenu modifié → la signature de l'acquéreur ne vaut plus.
          ...(dejaSigneAcq ? { statut: 'en_attente_acquereur', signature_acquereur: null, signed_acquereur_at: null } : {}),
        }).eq('id', cession.id as string);
        if (e) throw e;
      }

      const { error: e2 } = await supabase.from('animaux').update({
        destinataire_qualite: qualite,
        destinataire_nom:     nomComplet,
        destinataire_adresse: adresse.trim() || null,
        cession_prix:         prixNum,
        cession_notes:        notes.trim() || null,
        ...(animal.date_sortie ? { date_sortie: dateCession } : {}),
        acquereur_contact_manuel: Object.fromEntries(Object.entries({
          prenom: prenom.trim(), nom: nom.trim(), tel: tel.trim(), email: email.trim(), adresse: adresse.trim(),
        }).filter(([, v]) => v)),
      }).eq('id', animal.id);
      if (e2) throw e2;

      // Cession du site : la sortie est déjà inscrite au registre → on la corrige.
      await supabase.from('registre_mouvements').update({
        destinataire_qualite: qualite,
        destinataire_nom:     nomComplet,
        destinataire_adresse: adresse.trim() || null,
        date_mouvement:       dateCession,
      }).eq('animal_id', animal.id).eq('uid_eleveur', cedantUid).eq('type', 'sortie').eq('motif', 'cession');

      onSaved();
    } catch (e) {
      setError(`Erreur : ${e instanceof Error ? e.message : JSON.stringify(e)}`);
      setSaving(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 backdrop-blur-sm p-0 sm:p-4">
      <div className="bg-white w-full sm:max-w-lg rounded-t-3xl sm:rounded-3xl max-h-[92vh] overflow-y-auto">
        <div className="flex items-start justify-between px-6 pt-5 pb-3 border-b border-gray-100">
          <div>
            <h2 className="text-lg font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
              ✏️ Modifier la cession — {animal.nom ?? 'animal'}
            </h2>
            <p className="text-xs text-gray-500 mt-0.5">Possible tant que la cession n&apos;est pas signée par les deux parties.</p>
          </div>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-xl leading-none">×</button>
        </div>

        {loading ? (
          <div className="flex justify-center py-12">
            <div className="w-7 h-7 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
          </div>
        ) : (
          <div className="px-6 py-4 space-y-3">
            {dejaSigneAcq && (
              <p className="text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded-xl px-3 py-2">
                ✍️ L&apos;acquéreur a déjà signé : s&apos;il y a une modification, il devra signer à nouveau.
              </p>
            )}
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-xs font-semibold text-gray-500 mb-1">Date de cession</label>
                <input type="date" value={dateCession} onChange={e => setDateCession(e.target.value)} className={inputCls} />
              </div>
              <div>
                <label className="block text-xs font-semibold text-gray-500 mb-1">Prix (€)</label>
                <input type="number" min="0" value={prix} onChange={e => setPrix(e.target.value)} className={inputCls} />
              </div>
            </div>
            <div>
              <label className="block text-xs font-semibold text-gray-500 mb-1">Qualité de l&apos;acquéreur</label>
              <div className="flex flex-wrap gap-2">
                {QUALITES.map(q => (
                  <button key={q.value} onClick={() => setQualite(q.value)}
                    className={`px-3 py-1.5 rounded-full text-xs font-semibold border transition-colors ${qualite === q.value ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]' : 'bg-white text-gray-600 border-gray-200'}`}>
                    {q.label}
                  </button>
                ))}
              </div>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-xs font-semibold text-gray-500 mb-1">Prénom</label>
                <input type="text" value={prenom} onChange={e => setPrenom(e.target.value)} className={inputCls} />
              </div>
              <div>
                <label className="block text-xs font-semibold text-gray-500 mb-1">Nom *</label>
                <input type="text" value={nom} onChange={e => setNom(e.target.value)} className={inputCls} />
              </div>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-xs font-semibold text-gray-500 mb-1">Email</label>
                <input type="email" value={email} onChange={e => setEmail(e.target.value)} className={inputCls} />
              </div>
              <div>
                <label className="block text-xs font-semibold text-gray-500 mb-1">Téléphone</label>
                <input type="tel" value={tel} onChange={e => setTel(e.target.value)} className={inputCls} />
              </div>
            </div>
            <div>
              <label className="block text-xs font-semibold text-gray-500 mb-1">Adresse postale</label>
              <input type="text" value={adresse} onChange={e => setAdresse(e.target.value)}
                placeholder="N° et rue, code postal, ville" className={inputCls} />
            </div>
            <div>
              <label className="block text-xs font-semibold text-gray-500 mb-1">Notes / Conditions particulières</label>
              <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={3} className={inputCls} />
            </div>
            {error && <p className="text-xs text-red-600 bg-red-50 px-3 py-2 rounded-xl">{error}</p>}
            <div className="flex gap-3 pt-1 pb-2">
              <button onClick={onClose} className="flex-1 border border-gray-200 text-gray-600 rounded-xl py-2.5 text-sm font-semibold hover:bg-gray-50">
                Annuler
              </button>
              <button onClick={save} disabled={saving || !nom.trim()}
                className="flex-1 bg-[#0C5C6C] hover:bg-[#0a4d5b] disabled:opacity-50 text-white rounded-xl py-2.5 text-sm font-semibold">
                {saving ? 'Enregistrement…' : 'Enregistrer'}
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
