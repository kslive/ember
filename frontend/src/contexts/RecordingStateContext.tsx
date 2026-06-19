'use client';

import React, { createContext, useContext, useState, useEffect, useRef, useCallback, useMemo } from 'react';
import { listen } from '@tauri-apps/api/event';
import { recordingService } from '@/services/recordingService';

export enum RecordingStatus {
  IDLE = 'idle',
  STARTING = 'starting',
  RECORDING = 'recording',
  STOPPING = 'stopping',
  PROCESSING_TRANSCRIPTS = 'processing',
  SAVING = 'saving',
  COMPLETED = 'completed',
  ERROR = 'error'
}

interface RecordingState {
  isRecording: boolean;
  isPaused: boolean;
  isActive: boolean;
  recordingDuration: number | null;
  activeDuration: number | null;

  status: RecordingStatus;
  statusMessage?: string;
}

interface RecordingStateContextType extends RecordingState {
  setStatus: (status: RecordingStatus, message?: string) => void;

  isStopping: boolean;
  isProcessing: boolean;
  isSaving: boolean;
  isFinalizing: boolean;
}

const RecordingStateContext = createContext<RecordingStateContextType | null>(null);

export const useRecordingState = () => {
  const context = useContext(RecordingStateContext);
  if (!context) {
    throw new Error('useRecordingState must be used within a RecordingStateProvider');
  }
  return context;
};

export function RecordingStateProvider({ children }: { children: React.ReactNode }) {
  const [state, setState] = useState<RecordingState>({
    isRecording: false,
    isPaused: false,
    isActive: false,
    recordingDuration: null,
    activeDuration: null,
    status: RecordingStatus.IDLE,
    statusMessage: undefined,
  });

  const pollingIntervalRef = useRef<NodeJS.Timeout | null>(null);

  const setStatus = useCallback((status: RecordingStatus, message?: string) => {
    console.log(`[RecordingState] Status: ${state.status} → ${status}`, message || '');

    setState(prev => ({
      ...prev,
      status,
      statusMessage: message,
    }));
  }, [state.status, state.isRecording, state.isPaused]);

  const syncWithBackend = useCallback(async () => {
    try {
      const backendState = await recordingService.getRecordingState();

      setState(prev => ({
        ...prev,
        isRecording: backendState.is_recording,
        isPaused: backendState.is_paused,
        isActive: backendState.is_active,
        recordingDuration: backendState.recording_duration,
        activeDuration: backendState.active_duration,
        status: backendState.is_recording && prev.status === RecordingStatus.IDLE
          ? RecordingStatus.RECORDING
          : prev.status,
      }));

      return backendState;
    } catch (error) {
      console.error('[RecordingStateContext] Failed to sync with backend:', error);
      return null;
    }
  }, []);

  const startPolling = useCallback(() => {
    if (pollingIntervalRef.current) return;
    console.log('[RecordingStateContext] Starting state polling (500ms interval)');
    pollingIntervalRef.current = setInterval(syncWithBackend, 500);
  }, [syncWithBackend]);

  const stopPolling = useCallback(() => {
    if (pollingIntervalRef.current) {
      console.log('[RecordingStateContext] Stopping state polling');
      clearInterval(pollingIntervalRef.current);
      pollingIntervalRef.current = null;
    }
  }, []);

  useEffect(() => {
    console.log('[RecordingStateContext] Setting up event listeners');
    const unsubscribers: (() => void)[] = [];

    const setupListeners = async () => {
      try {
        const unlistenStarted = await recordingService.onRecordingStarted(() => {
          console.log('[RecordingStateContext] Recording started event');
          setState(prev => ({
            ...prev,
            isRecording: true,
            isPaused: false,
            isActive: true,
            status: RecordingStatus.RECORDING,
          }));
          startPolling();
        });
        unsubscribers.push(unlistenStarted);

        const unlistenStopped = await recordingService.onRecordingStopped((payload) => {
          console.log('[RecordingStateContext] Recording stopped event:', payload);
          setState(prev => {
            const newStatus = [
              RecordingStatus.STOPPING,
              RecordingStatus.PROCESSING_TRANSCRIPTS,
              RecordingStatus.SAVING
            ].includes(prev.status)
              ? prev.status
              : RecordingStatus.STOPPING;

            return {
              ...prev,
              status: newStatus,
              statusMessage: newStatus === RecordingStatus.STOPPING ? 'Stopping recording...' : prev.statusMessage,
              isRecording: false,
              isPaused: false,
              isActive: false,
              recordingDuration: null,
              activeDuration: null,
            };
          });
          stopPolling();
        });
        unsubscribers.push(unlistenStopped);

        const unlistenPaused = await recordingService.onRecordingPaused(() => {
          console.log('[RecordingStateContext] Recording paused event');
          setState(prev => ({
            ...prev,
            isPaused: true,
            isActive: false,
          }));
        });
        unsubscribers.push(unlistenPaused);

        const unlistenResumed = await recordingService.onRecordingResumed(() => {
          console.log('[RecordingStateContext] Recording resumed event');
          setState(prev => ({
            ...prev,
            isPaused: false,
            isActive: true,
          }));
        });
        unsubscribers.push(unlistenResumed);

        console.log('[RecordingStateContext] Event listeners set up successfully');
      } catch (error) {
        console.error('[RecordingStateContext] Failed to set up event listeners:', error);
      }
    };

    setupListeners();

    return () => {
      console.log('[RecordingStateContext] Cleaning up event listeners');
      unsubscribers.forEach(unsub => unsub());
      stopPolling();
    };
  }, []);

  useEffect(() => {
    let cancelled = false;
    const rehydrate = async (reason: string) => {
      if (cancelled) return;
      const backendState = await syncWithBackend();
      if (cancelled || !backendState) return;
      if (backendState.is_recording) {
        if (!pollingIntervalRef.current) {
          console.log(`[RecordingStateContext] ${reason}: backend is recording, ensuring polling is active`);
          startPolling();
        }
      } else if (pollingIntervalRef.current) {
        console.log(`[RecordingStateContext] ${reason}: backend is idle, stopping stale polling`);
        stopPolling();
      }
    };

    rehydrate('initial mount');

    const onVisibility = () => {
      if (document.visibilityState === 'visible') {
        rehydrate('visibilitychange');
      }
    };
    document.addEventListener('visibilitychange', onVisibility);

    const focusUnlistenP = listen('tauri://focus', () => rehydrate('tauri focus'))
      .catch((e) => { console.warn('[RecordingStateContext] tauri://focus listener failed:', e); return null; });

    return () => {
      cancelled = true;
      document.removeEventListener('visibilitychange', onVisibility);
      focusUnlistenP.then((u) => { if (typeof u === 'function') u(); }).catch(() => {});
    };
  }, [syncWithBackend, startPolling, stopPolling]);

  const contextValue = useMemo(() => ({
    ...state,
    setStatus,
    isStopping: state.status === RecordingStatus.STOPPING,
    isProcessing: state.status === RecordingStatus.PROCESSING_TRANSCRIPTS,
    isSaving: state.status === RecordingStatus.SAVING,
    isFinalizing:
      !state.isRecording &&
      (state.status === RecordingStatus.STOPPING ||
        state.status === RecordingStatus.PROCESSING_TRANSCRIPTS ||
        state.status === RecordingStatus.SAVING ||
        state.status === RecordingStatus.COMPLETED),
  }), [state, setStatus]);

  return (
    <RecordingStateContext.Provider value={contextValue}>
      {children}
    </RecordingStateContext.Provider>
  );
}
