'use client';

// Certificat d'engagement et de connaissance (table certificats_engagement)
// à l'étape Documents de la cession — distinct du certificat de cession.
// Miroir de cession_sheet.dart (_certsEngagementTiles / _creerCertEngagement /
// _attesterCertEngagement) : signé ≥ 7 jours avant le départ (chien / chat),
// dans PetsMatch ou hors appli avec attestation du cédant.
import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';

export interface CertEngagement {
  id: string;
  token_signature: string | null;
  statut: string;
  acquereur_nom: string | null;
  acquereur_prenom: string | null;
  signe_le: string | null;
  date_signature_acquereur: string | null;
  notes: string | null;
}

export function delaiLegalEngagement(espece?: string | null) {
  const e = (espece ?? '').toLowerCase();
  return e === 'chien' || e === 'chat';
}

/** Alerte (non bloquante) à la cession, ou null. */
export function alerteEngagement(certs: CertEngagement[], espece: string | null | undefined, dateCession: string): string | null {
  if (!delaiLegalEngagement(espece)) return null;
  const signes = certs.filter(c => c.statut === 'signe');
  if (signes.length === 0) {
    return "Aucun certificat d'engagement signé pour cet animal. La loi impose qu'il soit signé par l'acquéreur au moins 7 jours avant le départ (chien, chat).";
  }
  const dates = signes.map(c => c.signe_le || c.date_signature_acquereur).filter(Boolean)
    .map(d => new Date(d as string)).sort((a, b) => a.getTime() - b.getTime());
  if (!dates.length || !dateCession) return null;
  const jours = Math.floor((new Date(dateCession).setHours(0, 0, 0, 0) - new Date(dates[0]).setHours(0, 0, 0, 0)) / 86400000);
  if (jours < 7) {
    return `Le certificat d'engagement a été signé ${jours} jour${jours > 1 ? 's' : ''} seulement avant la date de cession : le délai légal est de 7 jours.`;
  }
  return null;
}

export default function CertificatEngagementSection({ animal, cedantUid, acquereur, onChange }: {
  animal: { id: string; espece?: string | null; race?: string | null; nom?: string | null; date_naissance?: string | null; identification?: string | null; is_association?: boolean | null };
  cedantUid: string;
  acquereur: { uid?: string | null; prenom: string; nom: string; email: string; tel: string; adresse: string };
  onChange?: (certs: CertEngagement[]) => void;
}) {
  const [certs, setCerts] = useState<CertEngagement[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [attestOpen, setAttestOpen] = useState(false);
  const [attestDate, setAttestDate] = useState(() => {
    const d = new Date(); d.setDate(d.getDate() - 7); return d.toISOString().slice(0, 10);
  });
  const legal = delaiLegalEngagement(animal.espece);

  const load = useCallback(async () => {
    const { data } = await supabase.from('certificats_engagement')
      .select('id, token_signature, statut, acquereur_nom, acquereur_prenom, signe_le, date_signature_acquereur, notes')
      .eq('animal_id', animal.id).eq('cedant_uid', cedantUid).order('created_at', { ascending: false });
    const list = (data ?? []) as CertEngagement[];
    setCerts(list);
    onChange?.(list);
  }, [animal.id, cedantUid, onChange]);

  useEffect(() => { load(); }, [load]);

  function payload() {
    return {
      cedant_uid: cedantUid,
      animal_id: animal.id,
      espece: animal.espece ?? '',
      race: animal.race ?? null,
      nom_animal: animal.nom ?? '',
      date_naissance_animal: animal.date_naissance ?? null,
      num_identification: animal.identification ?? null,
      ...(acquereur.uid ? { acquereur_uid: acquereur.uid } : {}),
      acquereur_nom: acquereur.nom.trim(),
      acquereur_prenom: acquereur.prenom.trim(),
      acquereur_email: acquereur.email.trim(),
      acquereur_telephone: acquereur.tel.trim() || null,
      acquereur_adresse: acquereur.adresse.trim() || null,
      modalite_cession: animal.is_association ? 'adoption' : 'vente',
      date_remise: new Date().toISOString(),
      profil_source: animal.is_association ? 'association' : 'eleveur',
    };
  }

  async function creer() {
    if (!acquereur.nom.trim() || !acquereur.email.trim()) { setError("Nom et e-mail de l'acquéreur requis."); return; }
    setBusy(true); setError('');
    const limite = legal ? new Date(Date.now() + 7 * 86400000).toISOString() : null;
    const { data, error: e } = await supabase.from('certificats_engagement')
      .insert({ ...payload(), date_limite_signature: limite }).select('token_signature').single();
    setBusy(false);
    if (e || !data) { setError(e?.message ?? 'Erreur'); return; }
    window.open(`/certificat/${data.token_signature}`, '_blank', 'noopener');
    load();
  }

  async function attester() {
    if (!acquereur.nom.trim()) { setError("Le nom de l'acquéreur est requis."); return; }
    setBusy(true); setError('');
    const iso = new Date(attestDate).toISOString();
    const { error: e } = await supabase.from('certificats_engagement').insert({
      ...payload(),
      statut: 'signe', signe_le: iso, date_signature_acquereur: iso,
      signataire_nom: `${acquereur.prenom} ${acquereur.nom}`.trim(),
      notes: `Signé hors application — signature attestée par le cédant le ${new Date().toISOString().slice(0, 10)}.`,
    });
    setBusy(false);
    if (e) { setError(e.message); return; }
    setAttestOpen(false);
    load();
  }

  return (
    <div className="space-y-2">
      <div>
        <p className="text-xs font-semibold text-[#1F2A2E]">✍️ Certificat d&apos;engagement et de connaissance</p>
        <p className="text-[10px] text-gray-500">
          {legal ? "Obligatoire : signé par l'acquéreur au moins 7 jours avant le départ." : "Recommandé : à faire signer à l'acquéreur avant le départ."}
        </p>
      </div>
      {certs.length === 0 ? (
        <p className="text-xs text-gray-400 italic">Aucun certificat d&apos;engagement</p>
      ) : (
        <div className="space-y-1.5">
          {certs.map(c => {
            const signe = c.statut === 'signe';
            const d = c.signe_le || c.date_signature_acquereur;
            const horsAppli = (c.notes ?? '').includes('hors application');
            const nomAcq = `${c.acquereur_prenom ?? ''} ${c.acquereur_nom ?? ''}`.trim();
            return (
              <div key={c.id} className={`flex items-center gap-2 rounded-xl border px-3 py-2 ${signe ? 'border-green-300 bg-green-50' : 'border-amber-200 bg-amber-50'}`}>
                <span className="text-sm">{signe ? '✅' : '⏳'}</span>
                <div className="flex-1 min-w-0">
                  <p className="text-xs font-semibold text-[#1F2A2E] truncate">{nomAcq || "Certificat d'engagement"}</p>
                  <p className="text-[10px] text-gray-500">
                    {signe ? `Signé${d ? ` le ${new Date(d).toLocaleDateString('fr-FR')}` : ''}${horsAppli ? ' (hors appli, attesté)' : ''}` : 'En attente de signature'}
                  </p>
                </div>
                {c.token_signature && (
                  <a href={`/certificat/${c.token_signature}`} target="_blank" rel="noreferrer" className="text-xs text-[#0C5C6C] hover:underline">Ouvrir</a>
                )}
              </div>
            );
          })}
        </div>
      )}
      <div className="flex gap-4 flex-wrap">
        <button onClick={creer} disabled={busy} className="text-xs font-semibold text-[#0C5C6C] hover:underline disabled:opacity-50">
          + Créer et faire signer
        </button>
        <button onClick={() => setAttestOpen(v => !v)} disabled={busy} className="text-xs font-semibold text-[#0C5C6C] hover:underline disabled:opacity-50">
          ✓ Signé hors appli
        </button>
      </div>
      {attestOpen && (
        <div className="rounded-xl border border-gray-200 p-3 space-y-2">
          <p className="text-xs text-gray-700">
            Je certifie que {`${acquereur.prenom} ${acquereur.nom}`.trim() || "l'acquéreur"} a signé le certificat d&apos;engagement
            et de connaissance des besoins de l&apos;animal le :
          </p>
          <input type="date" value={attestDate} max={new Date().toISOString().slice(0, 10)}
            onChange={e => setAttestDate(e.target.value)} className="border border-gray-200 rounded-lg px-2 py-1 text-xs" />
          <div className="flex gap-2">
            <button onClick={attester} disabled={busy} className="text-xs bg-[#0C5C6C] text-white rounded-lg px-3 py-1.5 font-semibold disabled:opacity-50">J&apos;atteste</button>
            <button onClick={() => setAttestOpen(false)} className="text-xs text-gray-500">Annuler</button>
          </div>
        </div>
      )}
      {error && <p className="text-xs text-red-600">{error}</p>}
    </div>
  );
}
