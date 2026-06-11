'use client';

import { useState } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';

const inputCls = 'w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white';
const labelCls = 'block text-sm font-medium text-[#1F2A2E] mb-1';

const SUBJECTS = [
  'Réclamation dossier refusé',
  'Problème technique',
  'Signalement abusif',
  'Question sur mon compte',
  'Autre',
];

export default function ContactPage() {
  const [name, setName]       = useState('');
  const [email, setEmail]     = useState('');
  const [subject, setSubject] = useState('');
  const [message, setMessage] = useState('');
  const [loading, setLoading] = useState(false);
  const [sent, setSent]       = useState(false);
  const [error, setError]     = useState('');

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!name.trim() || !email.trim() || !message.trim()) {
      setError('Veuillez remplir tous les champs obligatoires.');
      return;
    }
    setError('');
    setLoading(true);
    try {
      const { error: dbError } = await supabase.from('contact_messages').insert({
        name:    name.trim(),
        email:   email.trim(),
        subject: subject || 'Autre',
        message: message.trim(),
      });
      if (dbError) throw dbError;
      setSent(true);
    } catch {
      setError('Une erreur est survenue. Vous pouvez aussi nous écrire directement à support@petsmatch.com');
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="min-h-[80vh] flex items-center justify-center px-4 py-12">
      <div className="w-full max-w-lg">
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-8">

          <div className="flex flex-col items-center mb-6">
            <Link href="/">
              <Image src="/Banniere_petsmatch.png" alt="PetsMatch" width={240} height={76} className="object-contain mb-4" />
            </Link>
            <h1 className="text-xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
              Nous contacter
            </h1>
            <p className="text-sm text-gray-500 mt-1 text-center">
              Une question, une réclamation, un problème ? Notre équipe vous répond sous 48h ouvrées.
            </p>
          </div>

          {sent ? (
            <div className="text-center py-8">
              <div className="w-16 h-16 bg-green-50 rounded-full flex items-center justify-center mx-auto mb-4">
                <svg className="w-8 h-8 text-green-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                </svg>
              </div>
              <h2 className="text-lg font-bold text-[#1F2A2E] mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>
                Message envoyé !
              </h2>
              <p className="text-sm text-gray-500 mb-6">
                Notre équipe vous répondra à l'adresse <strong>{email}</strong> sous 48h ouvrées.
              </p>
              <Link
                href="/"
                className="inline-block bg-[#0C5C6C] text-white font-semibold px-6 py-2.5 rounded-xl text-sm hover:bg-[#094F5D] transition-colors"
                style={{ fontFamily: 'Galey, sans-serif' }}
              >
                Retour à l'accueil
              </Link>
            </div>
          ) : (
            <form onSubmit={handleSubmit} className="space-y-4">
              <div className="flex gap-3">
                <div className="flex-1">
                  <label className={labelCls}>Nom / Prénom *</label>
                  <input
                    type="text" value={name} onChange={e => setName(e.target.value)}
                    placeholder="Jean Dupont" className={inputCls} required
                  />
                </div>
              </div>

              <div>
                <label className={labelCls}>Email *</label>
                <input
                  type="email" value={email} onChange={e => setEmail(e.target.value)}
                  placeholder="votre@email.com" className={inputCls} required
                />
              </div>

              <div>
                <label className={labelCls}>Objet</label>
                <select value={subject} onChange={e => setSubject(e.target.value)} className={inputCls}>
                  <option value="">Sélectionner…</option>
                  {SUBJECTS.map(s => <option key={s} value={s}>{s}</option>)}
                </select>
              </div>

              <div>
                <label className={labelCls}>Message *</label>
                <textarea
                  value={message} onChange={e => setMessage(e.target.value)}
                  rows={5} placeholder="Décrivez votre demande…"
                  className={`${inputCls} resize-none`} required
                />
              </div>

              {error && (
                <p className="text-red-500 text-sm">{error}</p>
              )}

              <button
                type="submit" disabled={loading}
                className="w-full bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-60 text-white font-semibold py-3 rounded-xl transition-colors"
                style={{ fontFamily: 'Galey, sans-serif' }}
              >
                {loading ? 'Envoi en cours…' : 'Envoyer le message'}
              </button>

              <p className="text-center text-xs text-gray-400">
                Ou par email directement :{' '}
                <a href="mailto:support@petsmatch.com" className="text-[#0C5C6C] underline">
                  support@petsmatch.com
                </a>
              </p>
            </form>
          )}
        </div>
      </div>
    </div>
  );
}
