// Galeries privées photographe — logique serveur partagée par les routes
// /api/galeries/*. Le bucket « galeries » est privé (aucune policy storage) :
// seul ce code (service role) y lit / écrit, après contrôle de l'appelant.
// Identité : jeton Firebase vérifié (server-auth.ts), jamais un uid client.
import { createClient } from '@supabase/supabase-js';

export const admin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? '',
  { auth: { persistSession: false } },
);
export const BUCKET_GALERIES = 'galeries';
/** Durée de validité des URL signées d'aperçu (secondes). */
export const DUREE_URL = 3600;
/** Réponses de galerie : jamais en cache partagé, jamais indexées. */
export const ENTETES_PRIVEES = { 'Cache-Control': 'private, no-store', 'X-Robots-Tag': 'noindex, nofollow' };

export interface AlbumRow {
  id: string; pro_uid: string; pro_profile_id: string | null; rdv_id: string | null;
  client_uid: string | null; client_profile_id: string | null; titre: string | null;
  description?: string | null; statut?: string | null; date_seance?: string | null; couverture_url?: string | null;
  filigrane?: boolean | null; partage_client?: boolean | null; created_at: string; updated_at?: string | null;
  selection_confirmee_le?: string | null; selection_commentaire?: string | null; nb_photos_incluses?: number | null;
  livree_le?: string | null; prix_photo_supp?: number | null; client_email?: string | null;
  relance_selection_le?: string | null;
}
export const BUCKET_LIVRAISONS = 'livraisons';

export async function chargerAlbum(id: string): Promise<AlbumRow | null> {
  if (!/^[0-9a-f-]{36}$/i.test(id)) return null;
  const { data } = await admin.from('albums_photo').select('*').eq('id', id).maybeSingle();
  return (data as AlbumRow | null) ?? null;
}

/** Le photographe propriétaire, ou un cogérant actif de son compte. */
export async function estGestionnaire(album: AlbumRow, uid: string | null): Promise<boolean> {
  if (!uid) return false;
  if (album.pro_uid === uid) return true;
  const { data } = await admin.from('elevage_cogerants').select('id')
    .eq('uid_gerant', album.pro_uid).eq('uid_cogerant', uid).eq('statut', 'actif').is('date_fin', null).limit(1);
  return (data ?? []).length > 0;
}

/** Formule photographe Premium active (galeries clients privées). */
export async function estPremium(proUid: string): Promise<boolean> {
  const { data } = await admin.from('abonnements').select('plan_code')
    .eq('uid', proUid).eq('profil_type', 'photographe').eq('statut', 'actif')
    .order('created_at', { ascending: false }).limit(1).maybeSingle();
  const plan = (data as { plan_code?: string } | null)?.plan_code ?? 'free';
  return plan === 'premium';
}

/** Lien privé valide (actif, non expiré) pour CETTE galerie uniquement.
 *  Seuls les liens « client » (créés par le photographe) donnent le rôle
 *  client ; un lien « proches » ne permet que la consultation filigranée. */
export async function lienValide(albumId: string, token: string | null): Promise<boolean> {
  if (!token || token.length < 16) return false;
  const { data } = await admin.from('album_partage').select('album_id, expire_at, actif, type')
    .eq('token', token).maybeSingle();
  const l = data as { album_id: string; expire_at: string; actif: boolean; type?: string | null } | null;
  return !!l && l.actif && (l.type ?? 'client') === 'client' && l.album_id === albumId && new Date(l.expire_at).getTime() > Date.now();
}

/** Galerie ouverte par un lien « proches » valide (créé par le client),
 *  jamais en brouillon ni archivée. */
export async function albumProches(token: string): Promise<AlbumRow | null> {
  if (!token || token.length < 16) return null;
  const { data } = await admin.from('album_partage').select('album_id, expire_at, actif, type')
    .eq('token', token).maybeSingle();
  const l = data as { album_id: string; expire_at: string; actif: boolean; type?: string | null } | null;
  if (!l || !l.actif || l.type !== 'proches' || new Date(l.expire_at).getTime() <= Date.now()) return null;
  const album = await chargerAlbum(l.album_id);
  if (!album || album.statut === 'brouillon' || album.statut === 'archivee') return null;
  return album;
}

/** Nom affiché du studio (profil photographe de la galerie). */
export async function nomStudio(album: AlbumRow): Promise<{ nom: string; avatar: string | null }> {
  const { data: pro } = await admin.from('user_profiles_complet').select('nom, firstname, lastname, avatar_url')
    .eq('id', album.pro_profile_id ?? '').maybeSingle();
  const p = pro as { nom?: string | null; firstname?: string | null; lastname?: string | null; avatar_url?: string | null } | null;
  return { nom: (p?.nom ?? '').trim() || `${p?.firstname ?? ''} ${p?.lastname ?? ''}`.trim(), avatar: p?.avatar_url ?? null };
}

/** Accès en lecture : gestionnaire, client destinataire (galerie partagée),
 *  ou lien privé valide. Une galerie archivée ou en brouillon n'est visible
 *  que du photographe. */
export async function roleLecture(album: AlbumRow, uid: string | null, token: string | null): Promise<'pro' | 'client' | null> {
  if (await estGestionnaire(album, uid)) return 'pro';
  const visible = album.statut !== 'brouillon' && album.statut !== 'archivee';
  if (!visible) return null;
  if (uid && album.partage_client && album.client_uid === uid) return 'client';
  if (await lienValide(album.id, token)) return 'client';
  return null;
}

/** Contenu d'une galerie pour un rôle donné : fiche + aperçus en URL signées
 *  courtes. Les données de gestion ne sont renvoyées qu'au photographe. */
export async function contenuGalerie(album: AlbumRow, role: 'pro' | 'client') {
  const id = album.id;
  const { data: rows } = await admin.from('album_photos')
    .select('*')
    .eq('album_id', id).order('ordre').order('created_at');
  const photos = (rows ?? []) as { id: string; storage_path: string | null; photo_url: string | null; nom_fichier: string | null;
    largeur: number | null; hauteur: number | null; ordre: number; favori: boolean; created_at: string; selectionnee?: boolean | null; aimee?: boolean | null }[];
  const chemins = photos.map(p => p.storage_path).filter((x): x is string => !!x);
  const signees: Record<string, string> = {};
  if (chemins.length) {
    const { data } = await admin.storage.from(BUCKET_GALERIES).createSignedUrls(chemins, DUREE_URL);
    for (const s of data ?? []) if (s.path && s.signedUrl) signees[s.path] = s.signedUrl;
  }
  const studio = await nomStudio(album);
  // Livraison en cours (sans URL : le téléchargement passe par une URL
  // signée de 10 min, demandée au moment du clic).
  const { data: liv } = await admin.from('album_livraisons').select('id, numero, nom_fichier, taille_octets, nb_fichiers, expire_le, telechargements, prolongee')
    .eq('album_id', id).gt('expire_le', new Date().toISOString()).order('numero');

  return {
    role,
    album: {
      id: album.id, titre: album.titre, description: album.description ?? null, statut: album.statut ?? 'brouillon',
      date_seance: album.date_seance ?? null, couverture_url: album.couverture_url ?? null,
      filigrane: album.filigrane ?? true, partage_client: album.partage_client ?? false,
      selection_confirmee_le: album.selection_confirmee_le ?? null, selection_commentaire: album.selection_commentaire ?? null,
      nb_photos_incluses: album.nb_photos_incluses ?? null, livree_le: album.livree_le ?? null,
      prix_photo_supp: album.prix_photo_supp != null ? Number(album.prix_photo_supp) : null,
      // Données de gestion réservées au photographe.
      ...(role === 'pro' ? { rdv_id: album.rdv_id, client_uid: album.client_uid, client_profile_id: album.client_profile_id,
        client_email: await emailClientAlbum(album), relance_selection_le: album.relance_selection_le ?? null } : {}),
    },
    studio,
    photos: photos.map(ph => ({
      id: ph.id,
      url: ph.storage_path ? signees[ph.storage_path] ?? null : ph.photo_url,
      largeur: ph.largeur, hauteur: ph.hauteur, ordre: ph.ordre, selectionnee: !!ph.selectionnee, aimee: !!ph.aimee,
      ...(role === 'pro' ? { nom_fichier: ph.nom_fichier, storage_path: ph.storage_path, favori: ph.favori } : {}),
    })).filter(ph => !!ph.url),
    livraison: ((liv ?? []) as { id: string; numero: number; nom_fichier: string; taille_octets: number | null; nb_fichiers: number | null; expire_le: string; telechargements: number; prolongee?: boolean }[])
      .map(l => ({ id: l.id, numero: l.numero, nom: l.nom_fichier, taille: l.taille_octets, nb: l.nb_fichiers, expire_le: l.expire_le,
        ...(role === 'pro' ? { telechargements: l.telechargements, prolongee: !!l.prolongee } : {}) })),
    // Photographe : facture de la séance (paiement avant livraison).
    ...(role === 'pro' ? { facture: await (async () => {
      const f = await factureSeance(album);
      return f ? { statut: String(f.statut ?? ''), numero: String(f.numero_affichage ?? f.numero_facture ?? ''), total_ttc: Number(f.total_ttc ?? 0) } : null;
    })() } : {}),
  };
}

/** E-mail du client : saisi sur la galerie, sinon son profil, le rendez-vous, puis l'e-mail de son compte PetsMatch. */
export async function emailClientAlbum(album: AlbumRow): Promise<string | null> {
  if (album.client_email?.trim()) return album.client_email.trim();
  if (album.client_profile_id) {
    const { data } = await admin.from('user_profiles_complet').select('email_contact').eq('id', album.client_profile_id).maybeSingle();
    const e = (data as { email_contact?: string | null } | null)?.email_contact?.trim();
    if (e) return e;
  }
  if (album.rdv_id) {
    const { data } = await admin.from('rdv').select('client_email_manuel').eq('id', album.rdv_id).maybeSingle();
    const e = (data as { client_email_manuel?: string | null } | null)?.client_email_manuel?.trim();
    if (e) return e;
  }
  // Client avec un compte PetsMatch : e-mail du compte.
  if (album.client_uid) {
    const { data } = await admin.from('users').select('email').eq('uid', album.client_uid).maybeSingle();
    const e = (data as { email?: string | null } | null)?.email?.trim();
    if (e) return e;
  }
  return null;
}

/** Nom affiché du client (profil, sinon rendez-vous). */
export async function nomClientAlbum(album: AlbumRow): Promise<string> {
  if (album.client_profile_id) {
    const { data } = await admin.from('user_profiles_complet').select('firstname, lastname').eq('id', album.client_profile_id).maybeSingle();
    const p = data as { firstname?: string | null; lastname?: string | null } | null;
    const n = `${p?.firstname ?? ''} ${p?.lastname ?? ''}`.trim();
    if (n) return n;
  }
  if (album.rdv_id) {
    const { data } = await admin.from('rdv').select('client_nom_manuel').eq('id', album.rdv_id).maybeSingle();
    const n = (data as { client_nom_manuel?: string | null } | null)?.client_nom_manuel?.trim();
    if (n) return n;
  }
  return '';
}

/** Lien privé « client » actif jusqu'à au moins `jusquA` (créé ou prolongé au besoin). */
export async function lienClientAlbum(albumId: string, jusquA: Date): Promise<string> {
  const { data } = await admin.from('album_partage').select('id, token, expire_at')
    .eq('album_id', albumId).eq('type', 'client').eq('actif', true).gt('expire_at', new Date().toISOString())
    .order('expire_at', { ascending: false }).limit(1);
  const l = (data ?? [])[0] as { id: string; token: string; expire_at: string } | undefined;
  if (l) {
    if (new Date(l.expire_at) < jusquA) await admin.from('album_partage').update({ expire_at: jusquA.toISOString() }).eq('id', l.id);
    return l.token;
  }
  const { data: cree, error } = await admin.from('album_partage')
    .insert({ album_id: albumId, type: 'client', expire_at: jusquA.toISOString(), actif: true }).select('token').single();
  if (error || !cree) throw new Error(error?.message ?? 'Lien impossible');
  return (cree as { token: string }).token;
}

/** Facture de la séance (hors acompte, avoir et annulée), la plus récente. */
export async function factureSeance(album: AlbumRow): Promise<Record<string, unknown> | null> {
  if (!album.rdv_id) return null;
  const { data } = await admin.from('factures').select('*').eq('source_rdv_id', album.rdv_id)
    .neq('statut', 'annulee').order('created_at', { ascending: false });
  const l = ((data ?? []) as Record<string, unknown>[]).filter(f => f.type_facture !== 'acompte' && f.type_facture !== 'avoir');
  return l[0] ?? null;
}
