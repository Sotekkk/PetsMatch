'use client';

import { usePushNotifications } from '@/hooks/usePushNotifications';

export default function PushInit() {
  usePushNotifications();
  return null;
}
