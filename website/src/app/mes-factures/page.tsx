'use client';

// Factures REÇUES par un particulier — miroir de l'appli
// (lib/pages/particulier/mes_factures_particulier_page.dart). Scopé au
// profil actif (client_profile_id), repli sur client_uid.
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { marquerFacturesVues } from '@/lib/factures-non-vues';

interface FactureRow {
  id: string;
  token: string | null;
  numero_facture: number | null;
  numero_affichage: string | null;
  date_facture: string | null;
  total_ttc: number | null;
  nom_emetteur: string | null;
  statut: string | null;
  created_at: string | null;
}

const STATUT: Record<string, { label: string; cls: string }> = {
  emise:   { label: 'Émise',   cls: 'bg-amber-100 text-amber-700' },
  payee:   { label: 'Payée',   cls: 'bg-green-100 text-green-700' },
  annulee: { label: 'Annulée', cls: 'bg-red-100 text-red-600' },
};

export default function MesFacturesPage() {
  const { user, loading } = useAuth();
  const activePid = useActiveProfile();
  const router = useRouter();
  const [factures, setFactures] = useState<FactureRow[]>([]);
  const [fetching, setFetching] = useState(true);
  // Dernière ouverture avant celle-ci : les factures plus récentes sont « nouvelles ».
  const [vuAvant, setVuAvant] = useState<string | null>(null);
  const [il30j] = useState(() => new Date(Date.now() - 30 * 86400000).toISOString());

  useEffect(() => {
    if (!loading && !user) router.push('/connexion');
  }, [loading, user, router]);

  useEffect(() => {
    if (!user?.uid) return;
    const uid = user.uid;
    const cols = 'id, token, numero_facture, numero_affichage, date_facture, total_ttc, nom_emetteur, statut, created_at';
    (async () => {
      const { data: vu } = await supabase.from('factures_vues').select('vu_le').eq('cle', activePid || uid).maybeSingle();
      setVuAvant((vu as { vu_le: string } | null)?.vu_le ?? null);
      const q = supabase.from('factures').select(cols);
      const { data } = await (activePid ? q.eq('client_profile_id', activePid) : q.eq('client_uid', uid))
        .order('created_at', { ascending: false });
      setFactures((data ?? []) as FactureRow[]);
      setFetching(false);
      // Ouverture de « Mes Factures » : la bulle rouge du menu disparaît.
      marquerFacturesVues(uid, activePid);
    })();
  }, [user?.uid, activePid]);

  if (loading || fetching) return (
    <div className="flex justify-center items-center min-h-[60vh]">
      <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
    </div>
  );

  return (
    <div className="max-w-2xl mx-auto px-4 py-8 space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-[#1F2A2E] font-galey">🧾 Mes Factures</h1>
        <p className="text-sm text-gray-500 mt-0.5">Factures reçues de vos éleveurs et professionnels</p>
      </div>

      {factures.length === 0 ? (
        <div className="text-center py-16 border-2 border-dashed border-gray-200 rounded-2xl text-gray-400">
          <div className="text-5xl mb-3">🧾</div>
          <p className="font-medium">Aucune facture reçue</p>
        </div>
      ) : (
        <div className="space-y-3">
          {factures.map(f => {
            const st = STATUT[f.statut ?? 'emise'] ?? STATUT.emise;
            const num = f.numero_affichage?.trim() || (f.numero_facture != null ? String(f.numero_facture) : '—');
            const date = f.date_facture ? new Date(f.date_facture).toLocaleDateString('fr-FR') : '';
            const nouvelle = !!f.created_at && f.statut !== 'annulee' && f.created_at > (vuAvant ?? il30j);
            const contenu = (
              <div className="bg-white border border-gray-100 rounded-2xl p-4 shadow-sm flex items-center gap-4 hover:border-teal-200 transition-colors">
                <div className="w-11 h-11 rounded-xl bg-[#EEF5EA] flex items-center justify-center text-xl shrink-0">🧾</div>
                <div className="flex-1 min-w-0">
                  <p className="font-semibold text-[#1F2A2E] text-sm flex items-center gap-2">
                    Facture n° {num}
                    {nouvelle && <span className="text-[10px] font-bold text-white bg-red-500 rounded-full px-2 py-0.5">Nouvelle</span>}
                  </p>
                  {f.nom_emetteur && <p className="text-xs text-gray-500 truncate">{f.nom_emetteur}</p>}
                  {date && <p className="text-xs text-gray-400">{date}</p>}
                </div>
                <div className="text-right shrink-0">
                  <p className="font-bold text-[#1F2A2E] text-sm">{(f.total_ttc ?? 0).toFixed(2)} €</p>
                  <span className={`inline-block mt-1 text-xs px-2 py-0.5 rounded-full font-medium ${st.cls}`}>{st.label}</span>
                </div>
              </div>
            );
            return f.token
              ? <Link key={f.id} href={`/facture/${f.token}`} className="block">{contenu}</Link>
              : <div key={f.id}>{contenu}</div>;
          })}
        </div>
      )}
    </div>
  );
}
