import { NextRequest, NextResponse } from 'next/server';
import { requireUser, sanitizeEmailBody } from '@/lib/server-auth';
import { mailTransporter, MAIL_FROM } from '@/lib/mailer';
import { admin } from '@/lib/galeries-server';

/** Propriétaire PetsMatch d'un animal : adresse de son compte, résolue ici
 *  (jamais renvoyée au professionnel), si l'appelant a accès à l'animal —
 *  partage actif (animal_access) avec un de ses profils, ou employé actif du
 *  profil qui a l'accès. null : pas de compte / pas d'accès / pas d'adresse. */
async function emailProprietaire(animalId: string, appelant: string): Promise<{ email: string; nom: string } | null> {
  const { data: acces } = await admin.from('animal_access').select('pro_profile_id').eq('animal_id', animalId).eq('statut', 'active');
  const profils = [...new Set((acces ?? []).map(a => String(a.pro_profile_id)).filter(Boolean))];
  if (!profils.length) return null;
  const [{ data: miens }, { data: emp }] = await Promise.all([
    admin.from('user_profiles').select('id').in('id', profils).eq('uid', appelant),
    admin.from('employes').select('eleveur_profile_id').in('eleveur_profile_id', profils).eq('uid_employe', appelant).eq('actif', true),
  ]);
  if (!miens?.length && !emp?.length) return null;
  const { data: prop } = await admin.from('animaux_proprietes').select('uid_proprio, profile_id_proprio')
    .eq('animal_id', animalId).eq('role_proprio', 'principal').eq('statut', 'actif').is('date_fin', null).limit(1).maybeSingle();
  let uid = prop?.uid_proprio as string | undefined;
  if (!uid) {
    const { data: a } = await admin.from('animaux').select('uid_proprietaire').eq('id', animalId).maybeSingle();
    uid = (a?.uid_proprietaire as string | null) ?? undefined;
  }
  if (!uid) return null;
  const [{ data: profil }, { data: u }] = await Promise.all([
    prop?.profile_id_proprio
      ? admin.from('user_profiles').select('email_contact, firstname, lastname, nom').eq('id', prop.profile_id_proprio).maybeSingle()
      : Promise.resolve({ data: null }),
    admin.from('users').select('email, firstname, lastname').eq('uid', uid).maybeSingle(),
  ]);
  const email = String(profil?.email_contact || u?.email || '').trim();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return null;
  const nom = `${profil?.firstname ?? u?.firstname ?? ''} ${profil?.lastname ?? u?.lastname ?? ''}`.trim() || String(profil?.nom ?? '');
  return { email, nom };
}

// Envoi d'une ordonnance / d'un compte rendu (PDF joint) au propriétaire, y
// compris s'il n'a pas PetsMatch (patient créé par la clinique). Appelant
// authentifié ; textes nettoyés ; pièce jointe PDF uniquement, taille limitée.
const MAX_OCTETS = 4 * 1024 * 1024;

export async function POST(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  const clean = sanitizeEmailBody(await req.json().catch(() => ({})), [], req);
  if (clean instanceof NextResponse) return clean;
  const { animal_id, expediteur_nom, document_type, animal_nom, fichier_nom, pdf_base64, pieces } = clean as {
    email?: string; destinataire_nom?: string; expediteur_nom?: string; document_type?: string;
    animal_nom?: string; fichier_nom?: string; pdf_base64?: string; animal_id?: string;
    /** Fin de consultation : plusieurs documents dans un seul e-mail. */
    pieces?: { document_type?: string; fichier_nom?: string; pdf_base64?: string }[];
  };
  let { email, destinataire_nom } = clean as { email?: string; destinataire_nom?: string };

  // Propriétaire avec un compte PetsMatch : adresse résolue côté serveur.
  if (!email && animal_id) {
    const p = await emailProprietaire(String(animal_id), auth.uid);
    if (!p) return NextResponse.json({ error: 'Adresse du propriétaire introuvable', code: 'sans_email' }, { status: 404 });
    email = p.email;
    destinataire_nom = destinataire_nom || p.nom;
  }

  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return NextResponse.json({ error: 'Adresse e-mail invalide' }, { status: 400 });
  }
  // Un document, ou plusieurs (fin de consultation : CR, ordonnance, facture).
  const docs = Array.isArray(pieces) && pieces.length > 0
    ? pieces.slice(0, 5)
    : [{ document_type, fichier_nom, pdf_base64 }];
  const libelle = (t?: string) => t === 'ordonnance' ? ['une ordonnance', 'Ordonnance'] : t === 'facture' ? ['une facture', 'Facture'] : ['un compte rendu', 'Compte rendu'];
  const jointes: { filename: string; content: Buffer; contentType: string }[] = [];
  for (const d of docs) {
    if (!d?.pdf_base64) return NextResponse.json({ error: 'Document manquant' }, { status: 400 });
    const contenu = Buffer.from(String(d.pdf_base64), 'base64');
    if (contenu.length === 0 || contenu.length > MAX_OCTETS || contenu.subarray(0, 4).toString() !== '%PDF') {
      return NextResponse.json({ error: 'Document PDF invalide' }, { status: 400 });
    }
    jointes.push({
      filename: String(d.fichier_nom || `${libelle(d.document_type)[1].toLowerCase().replace(' ', '-')}.pdf`).replace(/[^\w.\-À-ÿ ]/g, '_'),
      content: contenu, contentType: 'application/pdf',
    });
  }
  const plusieurs = jointes.length > 1;
  const noms = docs.map(d => libelle(d.document_type)[0]);
  const quoi = plusieurs ? `${noms.slice(0, -1).join(', ')} et ${noms[noms.length - 1]}` : noms[0];
  const titre = plusieurs ? 'Documents de consultation' : libelle(docs[0].document_type)[1];
  const pro = expediteur_nom || 'Votre vétérinaire';
  const html = `<!DOCTYPE html>
<html lang="fr"><head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/></head>
<body style="margin:0;padding:0;background:#f5f7fa;font-family:'Segoe UI',Arial,sans-serif;">
  <div style="max-width:580px;margin:32px auto;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,0.08);">
    <div style="background:#0C5C6C;padding:24px 32px;text-align:center;">
      <p style="color:#ffffff;font-size:20px;font-weight:700;margin:0;">PetsMatch</p>
      <p style="color:rgba(255,255,255,0.85);font-size:13px;margin:6px 0 0;">${titre}${animal_nom ? ` — ${animal_nom}` : ''}</p>
    </div>
    <div style="padding:28px 32px;">
      <p style="font-size:15px;color:#1F2A2E;margin:0 0 14px;">Bonjour${destinataire_nom ? ` <strong>${destinataire_nom}</strong>` : ''},</p>
      <p style="font-size:14px;color:#4B5563;line-height:1.6;margin:0 0 18px;">
        <strong>${pro}</strong> vous transmet ${quoi}${animal_nom ? ` pour <strong>${animal_nom}</strong>` : ''}. ${plusieurs ? 'Vous les trouverez en pièces jointes (PDF).' : 'Vous le trouverez en pièce jointe (PDF).'}
      </p>
      <p style="font-size:13px;color:#4B5563;line-height:1.6;margin:0 0 18px;">
        Avec l'application PetsMatch, retrouvez le carnet de santé de votre animal, ses ordonnances et des rappels automatiques (vaccins, traitements).
      </p>
      <div style="text-align:center;margin-bottom:18px;">
        <a href="https://petsmatchapp.com" style="display:inline-block;background:#0C5C6C;color:#ffffff;font-size:14px;font-weight:700;text-decoration:none;padding:11px 28px;border-radius:12px;">Découvrir PetsMatch</a>
      </div>
      <p style="font-size:12px;color:#9CA3AF;text-align:center;margin:0;">Message envoyé via PetsMatch pour le compte de ${pro}.</p>
    </div>
  </div>
</body></html>`;

  try {
    await mailTransporter.sendMail({
      from: MAIL_FROM,
      to: email,
      subject: `${titre}${animal_nom ? ` — ${animal_nom}` : ''} (${pro})`,
      html,
      attachments: jointes,
    });
    // L'adresse n'est pas renvoyée (compte du propriétaire : donnée privée).
    return NextResponse.json({ success: true });
  } catch (e) {
    console.error('[documents/envoyer-email]', e);
    return NextResponse.json({ error: 'Envoi impossible' }, { status: 500 });
  }
}
