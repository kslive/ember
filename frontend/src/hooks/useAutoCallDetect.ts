'use client';

import { useEffect, useRef } from 'react';
import { useRouter } from 'next/navigation';
import { listen } from '@tauri-apps/api/event';
import { invoke } from '@tauri-apps/api/core';
import { useRecordingState } from '@/contexts/RecordingStateContext';

export function useAutoCallDetect(opts: { enabled: boolean }) {
  const { isRecording } = useRecordingState();
  const router = useRouter();
  const isRecordingRef = useRef(isRecording);
  useEffect(() => { isRecordingRef.current = isRecording; }, [isRecording]);

  const autoSessionRef = useRef(false);
  const pendingStartTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const triggerAutoStart = () => {
    try {
      const onHome = typeof window !== 'undefined' && window.location.pathname === '/';
      if (onHome) {
        window.dispatchEvent(new CustomEvent('start-recording-from-sidebar'));
      } else {
        sessionStorage.setItem('autoStartRecording', 'true');
        router.push('/');
      }
    } catch (e) {
      console.error('[auto-call] triggerAutoStart failed:', e);
    }
  };

  useEffect(() => {
    if (!opts.enabled) return;

    const unlistenPromise = listen<{ active: boolean; pids: number[] }>(
      'mic-usage-changed',
      (event) => {
        const active = !!event.payload?.active;

        if (active) {
          if (!isRecordingRef.current && !pendingStartTimerRef.current) {
            pendingStartTimerRef.current = setTimeout(() => {
              pendingStartTimerRef.current = null;
              if (!isRecordingRef.current) {
                console.log('[auto-call] external mic active for 5s → starting recording');
                autoSessionRef.current = true;
                triggerAutoStart();
              }
            }, 5000);
          }
        } else {
          if (pendingStartTimerRef.current) {
            clearTimeout(pendingStartTimerRef.current);
            pendingStartTimerRef.current = null;
          }
          if (isRecordingRef.current && autoSessionRef.current) {
            console.log('[auto-call] external mic released → stopping recording');
            autoSessionRef.current = false;
            invoke('auto_stop_recording').catch((e) =>
              console.error('[auto-call] auto_stop_recording invoke failed:', e),
            );
          }
        }
      },
    );

    return () => {
      unlistenPromise.then((u) => u()).catch(() => {});
      if (pendingStartTimerRef.current) clearTimeout(pendingStartTimerRef.current);
    };
  }, [opts.enabled]);

  useEffect(() => {
    if (!isRecording) {
      autoSessionRef.current = false;
      if (opts.enabled) {
        invoke('mic_watcher_resync').catch(() => {});
      }
    }
  }, [isRecording, opts.enabled]);
}
