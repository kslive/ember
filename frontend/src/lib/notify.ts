import {
  isPermissionGranted,
  requestPermission,
  sendNotification,
} from '@tauri-apps/plugin-notification';
import i18n from '@/i18n';

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
  recordingStarted: () =>
    send(i18n.t('recording:notify.started.title'), i18n.t('recording:notify.started.body')),
  recordingStopped: (meetingTitle?: string) =>
    send(
      i18n.t('recording:notify.stopped.title'),
      meetingTitle
        ? i18n.t('recording:notify.stopped.bodyWithTitle', { title: meetingTitle })
        : i18n.t('recording:notify.stopped.body')
    ),
  summaryReady: (meetingTitle?: string) =>
    send(
      i18n.t('recording:notify.summaryReady.title'),
      meetingTitle
        ? i18n.t('recording:notify.summaryReady.bodyWithTitle', { title: meetingTitle })
        : i18n.t('recording:notify.summaryReady.body')
    ),
  summaryFailed: (msg?: string) =>
    send(i18n.t('recording:notify.summaryFailed.title'), msg || i18n.t('recording:notify.summaryFailed.body')),
};

export default notify;
