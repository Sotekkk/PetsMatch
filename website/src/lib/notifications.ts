import { supabase } from './supabase';

export async function sendNotification(params: {
  uid: string;
  type: string;
  title: string;
  body: string;
  profileType?: string;
  data?: Record<string, unknown>;
}) {
  await supabase.from('notifications').insert({
    uid:          params.uid,
    type:         params.type,
    title:        params.title,
    body:         params.body,
    profile_type: params.profileType ?? '',
    data:         params.data ?? {},
    read:         false,
  });
}

const PROFILE_LABELS: Record<string, string> = {
  eleveur:          'Éleveur',
  association:      'Association',
  veterinaire:      'Vétérinaire',
  sante:            'Santé animale',
  education:        'Éducation',
  garde:            'Garde',
  pension:          'Pension',
  toilettage:       'Toilettage',
  photographe:      'Photographe',
  marechal_ferrant: 'Maréchal-ferrant',
};

export async function notifyProfilePendingValidation(uid: string, profileType: string) {
  const label = PROFILE_LABELS[profileType] ?? profileType;
  await sendNotification({
    uid,
    type:        'profil_en_attente',
    title:       'Profil en cours de validation',
    body:        `Votre profil ${label} est en cours de validation par notre équipe. Vous serez notifié(e) dès qu'il sera approuvé.`,
    profileType,
  });
}

export async function notifyProfileValidated(uid: string, profileType: string) {
  const label = PROFILE_LABELS[profileType] ?? profileType;
  await sendNotification({
    uid,
    type:        'profil_valide',
    title:       'Profil validé !',
    body:        `Votre profil ${label} a été validé. Vous pouvez maintenant publier des annonces et utiliser toutes les fonctionnalités.`,
    profileType,
  });
}
