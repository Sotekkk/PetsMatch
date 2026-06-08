'use client';

import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import Link from 'next/link';

interface DayStats { day: string; impressions: number; clics: number; leads: number; }

export default function PartnerDashboardPage() {
  const { user } = useAuth();
  const [partner, setPartner] = useState<any>(null);
  const [impressions, setImpressions] = useState(0);
  const [clics, setClics] = useState(0);
  const [leads, setLeads] = useState(0);
  const [history, setHistory] = useState<DayStats[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => { if (user) load(); }, [user]);

  async function load() {
    setLoading(true);
    const { data: partners } = await supabase.from('marketplace_partners').select('*').eq('user_id', user!.uid).limit(1);
    if (!partners || partners.length === 0) { setLoading(false); return; }
    const p = partners[0];
    setPartner(p);

    const now = new Date();
    const firstOfMonth = new Date(now.getFullYear(), now.getMonth(), 1).toISOString();
    const { data: events } = await supabase.from('marketplace_events').select('event_type,created_at').eq('partner_id', p.id).gte('created_at', firstOfMonth);

    let imp = 0, cl = 0, ld = 0;
    (events ?? []).forEach((e: any) => {
      if (e.event_type === 'impression') imp++;
      else if (e.event_type === 'clic') cl++;
      else if (e.event_type === 'lead') ld++;
    });
    setImpressions(imp); setClics(cl); setLeads(ld);

    const since30 = new Date(Date.now() - 30 * 86400000).toISOString();
    const { data: hist } = await supabase.from('marketplace_events').select('event_type,created_at').eq('partner_id', p.id).gte('created_at', since30);

    const map: Record<string, DayStats> = {};
    (hist ?? []).forEach((e: any) => {
      const day = e.created_at.substring(0, 10);
      if (!map[day]) map[day] = { day, impressions: 0, clics: 0, leads: 0 };
      if (e.event_type === 'impression') map[day].impressions++;
      else if (e.event_type === 'clic') map[day].clics++;
      else if (e.event_type === 'lead') map[day].leads++;
    });
    setHistory(Object.values(map).sort((a, b) => a.day.localeCompare(b.day)));
    setLoading(false);
  }

  const ctr = impressions > 0 ? (clics / impressions * 100).toFixed(1) : '0.0';

  if (loading) return <div style={{ textAlign: 'center', padding: 80, color: '#6E9E57' }}>Chargement…</div>;

  if (!partner) return (
    <div style={{ minHeight: '100vh', background: '#F8F8F6', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      <div style={{ textAlign: 'center', padding: 40 }}>
        <div style={{ fontSize: 56 }}>🏪</div>
        <h2 style={{ margin: '16px 0 8px' }}>Vous n&apos;êtes pas encore partenaire</h2>
        <Link href="/marketplace/partenaire" style={{ background: '#6E9E57', color: 'white', padding: '12px 24px', borderRadius: 12, textDecoration: 'none', fontWeight: 700 }}>
          Devenir partenaire
        </Link>
      </div>
    </div>
  );

  const planColor: Record<string, string> = { starter: '#888', visible: '#1E88E5', premium: '#8E24AA' };

  return (
    <div style={{ minHeight: '100vh', background: '#F8F8F6' }}>
      <div style={{ background: '#A7C79A', padding: '24px 24px 20px' }}>
        <div style={{ maxWidth: 900, margin: '0 auto' }}>
          <Link href="/marketplace" style={{ color: '#333', fontSize: 13, textDecoration: 'none' }}>← Marketplace</Link>
          <h1 style={{ margin: '8px 0 0', fontWeight: 700, fontSize: 26 }}>Ma campagne</h1>
        </div>
      </div>

      <div style={{ maxWidth: 900, margin: '0 auto', padding: '28px 16px' }}>
        {/* Header partenaire */}
        <div style={{ background: 'white', borderRadius: 16, padding: '18px 20px', boxShadow: '0 2px 8px rgba(0,0,0,0.05)', marginBottom: 20, display: 'flex', alignItems: 'center', gap: 14 }}>
          <div style={{ width: 50, height: 50, background: '#F0F7EC', borderRadius: 12, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 24 }}>🏪</div>
          <div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <span style={{ fontWeight: 700, fontSize: 18 }}>{partner.nom}</span>
              <span style={{ background: `${planColor[partner.plan]}22`, color: planColor[partner.plan], padding: '2px 10px', borderRadius: 20, fontSize: 11, fontWeight: 700 }}>{partner.plan.toUpperCase()}</span>
              <span style={{ background: partner.statut === 'actif' ? '#E8F5E9' : '#FFF3E0', color: partner.statut === 'actif' ? '#2E7D32' : '#E65100', padding: '2px 10px', borderRadius: 20, fontSize: 11, fontWeight: 600 }}>
                {partner.statut === 'actif' ? '● Actif' : '● En attente'}
              </span>
            </div>
            <p style={{ margin: '4px 0 0', fontSize: 13, color: '#666' }}>{partner.site_url}</p>
          </div>
        </div>

        {/* Métriques */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 12, marginBottom: 20 }}>
          <MetricCard label="Impressions" value={impressions} color="#1E88E5" icon="👁️" />
          <MetricCard label="Clics" value={clics} color="#6E9E57" icon="👆" />
          <MetricCard label="Leads" value={leads} color="#8E24AA" icon="👤" />
        </div>

        {/* CTR */}
        <div style={{ background: 'white', borderRadius: 16, padding: '16px 20px', boxShadow: '0 2px 8px rgba(0,0,0,0.05)', marginBottom: 20, display: 'flex', gap: 24 }}>
          <div>
            <p style={{ margin: '0 0 2px', fontSize: 12, color: '#888' }}>CTR moyen</p>
            <p style={{ margin: 0, fontSize: 24, fontWeight: 700, color: '#1a1a1a' }}>{ctr}%</p>
            <p style={{ margin: 0, fontSize: 11, color: '#aaa' }}>clics / impressions</p>
          </div>
          <div style={{ width: 1, background: '#eee' }} />
          <div>
            <p style={{ margin: '0 0 2px', fontSize: 12, color: '#888' }}>Total événements</p>
            <p style={{ margin: 0, fontSize: 24, fontWeight: 700 }}>{impressions + clics + leads}</p>
            <p style={{ margin: 0, fontSize: 11, color: '#aaa' }}>ce mois</p>
          </div>
        </div>

        {/* Graphique 30j */}
        <div style={{ background: 'white', borderRadius: 16, padding: '16px 20px', boxShadow: '0 2px 8px rgba(0,0,0,0.05)' }}>
          <h3 style={{ margin: '0 0 12px', fontSize: 15, fontWeight: 700 }}>Évolution 30 jours</h3>
          <div style={{ display: 'flex', gap: 12, marginBottom: 10 }}>
            {[['#1E88E5','Impressions'],['#6E9E57','Clics'],['#8E24AA','Leads']].map(([c,l]) => (
              <div key={l} style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                <div style={{ width: 8, height: 8, borderRadius: '50%', background: c }} />
                <span style={{ fontSize: 11, color: '#666' }}>{l}</span>
              </div>
            ))}
          </div>
          {history.length === 0
            ? <p style={{ textAlign: 'center', color: '#aaa', fontSize: 13, padding: '20px 0' }}>Aucune donnée sur 30 jours</p>
            : <MiniChart data={history} />
          }
        </div>
      </div>
    </div>
  );
}

function MetricCard({ label, value, color, icon }: { label: string; value: number; color: string; icon: string }) {
  return (
    <div style={{ background: 'white', borderRadius: 14, padding: '16px', boxShadow: '0 2px 8px rgba(0,0,0,0.05)' }}>
      <div style={{ fontSize: 22, marginBottom: 8 }}>{icon}</div>
      <div style={{ fontSize: 28, fontWeight: 700, color }}>{value}</div>
      <div style={{ fontSize: 12, color: '#888', marginTop: 2 }}>{label}</div>
    </div>
  );
}

function MiniChart({ data }: { data: DayStats[] }) {
  const maxVal = Math.max(...data.map(d => Math.max(d.impressions, d.clics, d.leads)), 1);
  const w = 100 / (data.length - 1 || 1);

  function points(vals: number[]) {
    return vals.map((v, i) => `${i * w},${100 - (v / maxVal) * 100}`).join(' ');
  }

  return (
    <svg viewBox="0 0 100 100" preserveAspectRatio="none" style={{ width: '100%', height: 120 }}>
      <polyline points={points(data.map(d => d.impressions))} fill="none" stroke="#1E88E5" strokeWidth="1.5" />
      <polyline points={points(data.map(d => d.clics))} fill="none" stroke="#6E9E57" strokeWidth="1.5" />
      <polyline points={points(data.map(d => d.leads))} fill="none" stroke="#8E24AA" strokeWidth="1.5" />
    </svg>
  );
}
