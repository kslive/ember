'use client';

import React, { useEffect } from 'react';
import { listen } from '@tauri-apps/api/event';
import { useRecordingStop, resetStopGuard } from '@/hooks/useRecordingStop';

export function RecordingPostProcessingProvider({ children }: { children: React.ReactNode }) {
  const setIsRecording = () => { };
  const setIsRecordingDisabled = () => { };

  const {
    handleRecordingStop,
  } = useRecordingStop(setIsRecording, setIsRecordingDisabled);

  useEffect(() => {
    let unlistenFn: (() => void) | undefined;
    let unlistenStartedFn: (() => void) | undefined;

    const setupListener = async () => {
      try {
        unlistenFn = await listen<boolean>('recording-stop-complete', (event) => {
          console.log('[RecordingPostProcessing] Received recording-stop-complete event:', event.payload);

          handleRecordingStop(event.payload);
        });

        unlistenStartedFn = await listen('recording-started', () => {
          console.log('[RecordingPostProcessing] recording-started → resetting stop guard');
          resetStopGuard();
        });

        console.log('[RecordingPostProcessing] Event listener set up successfully');
      } catch (error) {
        console.error('[RecordingPostProcessing] Failed to set up event listener:', error);
      }
    };

    setupListener();

    return () => {
      if (unlistenFn) {
        console.log('[RecordingPostProcessing] Cleaning up event listener');
        unlistenFn();
      }
      if (unlistenStartedFn) unlistenStartedFn();
    };
  }, [handleRecordingStop]);

  return <>{children}</>;
}
