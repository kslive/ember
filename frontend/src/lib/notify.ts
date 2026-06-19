import {
  isPermissionGranted,
  requestPermission,
  sendNotification,
} from '@tauri-apps/plugin-notification';

let cachedGranted: boolean | null = null;

async function ensurePermission(): Promise<boolean> {
  if (cachedGranted === true) return true;
  try {
    let granted = await isPermissionGranted();
    if (!granted) {
      const res = await requestPermission();
      granted = res === 'granted';
    }
    cachedGranted = granted;
    return granted;
  } catch (e) {
    console.warn('notify: permission check failed:', e);
    return false;
  }
}

async function send(title: string, body?: string): Promise<void> {
  try {
    const ok = await ensurePermission();
    if (!ok) return;
    sendNotification({ title, body });
  } catch (e) {
    console.warn('notify: send failed:', e);
  }
}

export const notify = {
  recordingStarted: () => send('Запись начата', 'Ember записывает встречу.'),
  recordingStopped: (meetingTitle?: string) =>
    send('Запись остановлена', meetingTitle ? `«${meetingTitle}» сохранена.` : 'Встреча сохранена.'),
  summaryReady: (meetingTitle?: string) =>
    send('Саммари готово', meetingTitle ? `«${meetingTitle}» — сводка сгенерирована.` : 'Сводка встречи готова.'),
  summaryFailed: (msg?: string) =>
    send('Саммари не сгенерировалось', msg || 'Подробности в окне встречи.'),
};

export default notify;
