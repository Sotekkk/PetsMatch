'use client';

import { useState } from 'react';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import Link from 'next/link';

const CATEGORIES = [
  { value: 'boutique',      label: 'Boutique & Accessoires', icon: '🏪' },
  { value: 'alimentation',  label: 'Alimentation & Petfood', icon: '🥩' },
  { value: 'artisan',       label: 'Créateur artisanal',     icon: '🎨' },
  { value: 'assurance',     label: 'Assurance animaux',      icon: '🛡️' },
];

const ESPECES = [
  { value: 'chien',  label: 'Chien 🐕' },
  { value: 'chat',   label: 'Chat 🐈' },
  { value: 'equide', label: 'Équidé 🐴' },
  { value: 'lapin',  label: 'Lapin 🐇' },
  { value: 'autre',  label: 'Autre' },
];

const PLANS = [
  { value: 'starter', label: 'Starter',  prix: '29€/mois',  desc: 'Logo + nom + lien, listing basique' },
  { value: 'visible', label: 'Visible',  prix: '59€/mois',  desc: 'Mise en avant + badge Vérifié + description' },
  { value: 'premium', label: 'Premium',  prix: '99€/mois',  desc: 'Top catégorie + bannières + ciblage avancé' },
];

export default function PartenaireSignupPage() {
  const { user } = useAuth();
  const [loading, setLoading] = useState(false);
  const [done, setDone] = useState(false);

  const [nom, setNom] = useState('');
  const [siret, setSiret] = useState('');
  const [site, setSite] = useState('');
  const [email, setEmail] = useState('');
  const [desc, setDesc] = useState('');
  const [categorie, setCategorie] = useState('boutique');
  const [plan, setPlan] = useState('starter');
  const [especes, setEspeces] = useState<string[]>([]);

  function toggleEspece(v: string) {
    setEspeces(prev => prev.includes(v) ? prev.filter(e => e !== v) : [...prev, v]);
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!nom || !site || !email || especes.length === 0) return;
    setLoading(true);
    try {
      await supabase.from('marketplace_partners').insert({
        user_id: user?.uid ?? 'anonymous',
        nom, siret, site_url: site, description: desc,
        contact_email: email, categorie, plan,
        especes_cibles: especes, statut: 'en_attente',
      });
      setDone(true);
    } catch (_) {}
    setLoading(false);
  }

  if (done) return (
    <div style={{ minHeight: '100vh', background: '#F8F8F6', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      <div style={{ background: 'white', borderRadius: 20, padding: '48px 40px', maxWidth: 480, textAlign: 'center', boxShadow: '0 4px 20px rgba(0,0,0,0.08)' }}>
        <div style={{ fontSize: 56 }}>✅</div>
        <h2 style={{ margin: '16px 0 8px', fontSize: 22, fontWeight: 700 }}>Demande envoyée !</h2>
        <p style={{ color: '#666', fontSize: 15, marginBottom: 24 }}>
          Nous examinerons votre dossier sous 48h et vous contacterons à l&apos;adresse fournie.
        </p>
        <Link href="/marketplace" style={{ background: '#6E9E57', color: 'white', padding: '12px 28px', borderRadius: 12, fontWeight: 700, textDecoration: 'none', fontSize: 14 }}>
          Retour Marketplace
        </Link>
      </div>
    </div>
  );

  return (
    <div style={{ minHeight: '100vh', background: '#F8F8F6' }}>
      <div style={{ background: '#A7C79A', padding: '24px 24px 20px' }}>
        <div style={{ maxWidth: 700, margin: '0 auto' }}>
          <Link href="/marketplace" style={{ color: '#333', fontSize: 13, textDecoration: 'none' }}>← Marketplace</Link>
          <h1 style={{ margin: '8px 0 0', fontWeight: 700, fontSize: 24 }}>Devenir partenaire</h1>
        </div>
      </div>

      <div style={{ maxWidth: 700, margin: '0 auto', padding: '32px 16px' }}>
        {/* Intro */}
        <div style={{ background: 'linear-gradient(135deg,#6E9E57,#4A7A3D)', borderRadius: 16, padding: '20px 24px', color: 'white', marginBottom: 32 }}>
          <h3 style={{ margin: '0 0 6px', fontSize: 18 }}>Rejoignez notre réseau</h3>
          <p style={{ margin: 0, fontSize: 13, opacity: 0.9 }}>
            Touchez des milliers d&apos;amoureux des animaux qualifiés. Votre demande sera examinée sous 48h.
          </p>
        </div>

        <form onSubmit={handleSubmit}>
          {/* Infos entreprise */}
          <Section title="Informations entreprise">
            <InputField label="Nom de l'entreprise *" value={nom} onChange={setNom} required />
            <InputField label="SIRET" value={siret} onChange={setSiret} />
            <InputField label="Site web (URL) *" value={site} onChange={setSite} type="url" required />
            <InputField label="Email de contact *" value={email} onChange={setEmail} type="email" required />
            <InputField label="Description courte" value={desc} onChange={setDesc} multiline />
          </Section>

          {/* Catégorie */}
          <Section title="Catégorie">
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              {CATEGORIES.map(c => (
                <label key={c.value} style={{ display: 'flex', alignItems: 'center', gap: 12, background: categorie === c.value ? '#E8F5E9' : 'white', border: `1.5px solid ${categorie === c.value ? '#6E9E57' : '#ddd'}`, borderRadius: 12, padding: '12px 16px', cursor: 'pointer' }}>
                  <input type="radio" name="cat" value={c.value} checked={categorie === c.value} onChange={() => setCategorie(c.value)} style={{ accentColor: '#6E9E57' }} />
                  <span style={{ fontSize: 20 }}>{c.icon}</span>
                  <span style={{ fontWeight: categorie === c.value ? 600 : 400, fontSize: 14 }}>{c.label}</span>
                </label>
              ))}
            </div>
          </Section>

          {/* Espèces */}
          <Section title="Espèces ciblées *">
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
              {ESPECES.map(e => {
                const sel = especes.includes(e.value);
                return (
                  <button key={e.value} type="button" onClick={() => toggleEspece(e.value)}
                    style={{ padding: '8px 16px', borderRadius: 20, border: `1.5px solid ${sel ? '#6E9E57' : '#ddd'}`, background: sel ? '#6E9E57' : 'white', color: sel ? 'white' : '#333', cursor: 'pointer', fontWeight: sel ? 600 : 400, fontSize: 13 }}>
                    {e.label}
                  </button>
                );
              })}
            </div>
          </Section>

          {/* Plans */}
          <Section title="Plan de visibilité">
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
              {PLANS.map(p => (
                <label key={p.value} style={{ display: 'flex', alignItems: 'center', gap: 14, background: plan === p.value ? '#E8F5E9' : 'white', border: `2px solid ${plan === p.value ? '#6E9E57' : '#ddd'}`, borderRadius: 14, padding: '14px 18px', cursor: 'pointer' }}>
                  <input type="radio" name="plan" value={p.value} checked={plan === p.value} onChange={() => setPlan(p.value)} style={{ accentColor: '#6E9E57' }} />
                  <div style={{ flex: 1 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                      <span style={{ fontWeight: 700, fontSize: 15 }}>{p.label}</span>
                      <span style={{ background: '#6E9E57', color: 'white', padding: '2px 10px', borderRadius: 20, fontSize: 12, fontWeight: 600 }}>{p.prix}</span>
                    </div>
                    <p style={{ margin: '3px 0 0', fontSize: 12, color: '#666' }}>{p.desc}</p>
                  </div>
                  {plan === p.value && <span style={{ color: '#6E9E57', fontSize: 20 }}>✓</span>}
                </label>
              ))}
            </div>
          </Section>

          <button type="submit" disabled={loading}
            style={{ width: '100%', background: '#6E9E57', color: 'white', border: 'none', borderRadius: 14, padding: '16px', fontSize: 15, fontWeight: 700, cursor: loading ? 'not-allowed' : 'pointer', opacity: loading ? 0.7 : 1, marginTop: 8 }}>
            {loading ? 'Envoi…' : 'Envoyer ma demande'}
          </button>
        </form>
      </div>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div style={{ marginBottom: 28 }}>
      <h3 style={{ fontSize: 15, fontWeight: 700, margin: '0 0 12px', color: '#1a1a1a' }}>{title}</h3>
      {children}
    </div>
  );
}

function InputField({ label, value, onChange, type = 'text', required, multiline }: {
  label: string; value: string; onChange: (v: string) => void;
  type?: string; required?: boolean; multiline?: boolean;
}) {
  const style: React.CSSProperties = { width: '100%', padding: '10px 14px', borderRadius: 10, border: '1px solid #ddd', fontSize: 14, background: 'white', boxSizing: 'border-box', marginBottom: 10, fontFamily: 'inherit', outline: 'none' };
  return (
    <div>
      {multiline
        ? <textarea value={value} onChange={e => onChange(e.target.value)} placeholder={label} rows={3} style={{ ...style, resize: 'vertical' }} />
        : <input type={type} value={value} onChange={e => onChange(e.target.value)} placeholder={label} required={required} style={style} />
      }
    </div>
  );
}
