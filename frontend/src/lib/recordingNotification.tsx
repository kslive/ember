import { toast } from 'sonner';
import Analytics from '@/lib/analytics';
import { getPref, setPref } from '@/lib/preferences';

export async function showRecordingNotification(): Promise<void> {
  try {
    const showNotification = await getPref('show_recording_notification');

    if (showNotification) {
      let dontShowAgain = false;

      const toastId = toast.info('Запись началась', {
        description: (
          <div className="space-y-3 min-w-[260px]">
            <p className="text-sm text-fg-muted">
              Предупредите участников, что встреча записывается.
            </p>
            <label className="flex items-center gap-2 text-xs cursor-pointer text-fg-faint hover:text-fg-muted transition-colors">
              <input
                type="checkbox"
                onChange={async (e) => {
                  dontShowAgain = e.target.checked;
                  try {
                    await setPref('show_recording_notification', !e.target.checked);
                  } catch {
                  }
                }}
                className="rounded border-black/20 text-accent focus:ring-accent/40"
              />
              <span className="select-none">Больше не показывать</span>
            </label>
            <button
              onClick={async () => {
                if (dontShowAgain) {
                  await setPref('show_recording_notification', false);
                }
                Analytics.trackButtonClick('recording_notification_acknowledged', 'toast');
                toast.dismiss(toastId);
              }}
              className="w-full px-3 py-1.5 bg-surface text-white text-xs rounded-lg hover:bg-surface transition-colors font-medium"
            >
              Участники предупреждены
            </button>
          </div>
        ),
        duration: 8000,
        position: 'bottom-right',
      });
    }
  } catch (notificationError) {
    console.error('Failed to show recording notification:', notificationError);
  }
}
