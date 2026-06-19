import { useState, useEffect, useCallback } from 'react';
import { listen } from '@tauri-apps/api/event';
import { toast } from 'sonner';
import { TranscriptModelProps } from '@/components/TranscriptSettings';

export type ModalType =
  | 'modelSettings'
  | 'deviceSettings'
  | 'languageSettings'
  | 'modelSelector'
  | 'errorAlert'
  | 'chunkDropWarning';

interface ModalState {
  modelSettings: boolean;
  deviceSettings: boolean;
  languageSettings: boolean;
  modelSelector: boolean;
  errorAlert: boolean;
  chunkDropWarning: boolean;
}

interface ModalMessages {
  errorAlert: string;
  chunkDropWarning: string;
  modelSelector: string;
}

interface UseModalStateReturn {
  modals: ModalState;
  messages: ModalMessages;
  showModal: (name: ModalType, message?: string) => void;
  hideModal: (name: ModalType) => void;
  hideAllModals: () => void;
}

export function useModalState(transcriptModelConfig?: TranscriptModelProps): UseModalStateReturn {
  const [modals, setModals] = useState<ModalState>({
    modelSettings: false,
    deviceSettings: false,
    languageSettings: false,
    modelSelector: false,
    errorAlert: false,
    chunkDropWarning: false,
  });

  const [messages, setMessages] = useState<ModalMessages>({
    errorAlert: '',
    chunkDropWarning: '',
    modelSelector: '',
  });

  const showModal = useCallback((name: ModalType, message?: string) => {
    setModals(prev => ({ ...prev, [name]: true }));

    if (message && (name === 'errorAlert' || name === 'chunkDropWarning' || name === 'modelSelector')) {
      setMessages(prev => ({ ...prev, [name]: message }));
    }
  }, []);

  const hideModal = useCallback((name: ModalType) => {
    setModals(prev => ({ ...prev, [name]: false }));

    if (name === 'errorAlert' || name === 'chunkDropWarning' || name === 'modelSelector') {
      setMessages(prev => ({ ...prev, [name]: '' }));
    }
  }, []);

  const hideAllModals = useCallback(() => {
    setModals({
      modelSettings: false,
      deviceSettings: false,
      languageSettings: false,
      modelSelector: false,
      errorAlert: false,
      chunkDropWarning: false,
    });
    setMessages({
      errorAlert: '',
      chunkDropWarning: '',
      modelSelector: '',
    });
  }, []);

  useEffect(() => {
    let unlistenFn: (() => void) | undefined;

    const setupChunkDropListener = async () => {
      try {
        console.log('Setting up chunk-drop-warning listener...');
        unlistenFn = await listen<string>('chunk-drop-warning', (event) => {
          console.log('Chunk drop warning received:', event.payload);
          showModal('chunkDropWarning', event.payload);
        });
        console.log('Chunk drop warning listener setup complete');
      } catch (error) {
        console.error('Failed to setup chunk drop warning listener:', error);
      }
    };

    setupChunkDropListener();

    return () => {
      console.log('Cleaning up chunk drop warning listener...');
      if (unlistenFn) {
        unlistenFn();
      }
    };
  }, [showModal]);

  useEffect(() => {
    let unlistenFn: (() => void) | undefined;

    const setupTranscriptionErrorListener = async () => {
      try {
        console.log('Setting up transcription-error listener...');
        unlistenFn = await listen<{ error: string, userMessage: string, actionable: boolean }>('transcription-error', (event) => {
          console.log('Transcription error received:', event.payload);
          const { userMessage, actionable } = event.payload;

          if (actionable) {
            showModal('modelSelector', userMessage);
          } else {
            toast.error('', {
              description: userMessage,
              duration: 5000,
            });
          }
        });
        console.log('Transcription error listener setup complete');
      } catch (error) {
        console.error('Failed to setup transcription error listener:', error);
      }
    };

    setupTranscriptionErrorListener();

    return () => {
      console.log('Cleaning up transcription error listener...');
      if (unlistenFn) {
        unlistenFn();
      }
    };
  }, [showModal]);

  useEffect(() => {
    const setupDownloadListeners = async () => {
      const unlisteners: (() => void)[] = [];

      const unlistenWhisper = await listen<{ modelName: string }>('model-download-complete', (event) => {
        const { modelName } = event.payload;
        console.log('[useModalState] Whisper model download complete:', modelName);

        if (transcriptModelConfig?.provider === 'localWhisper' && transcriptModelConfig?.model === modelName) {
          toast.success('Model ready! Closing window...', { duration: 1500 });
          setTimeout(() => hideModal('modelSelector'), 1500);
        }
      });
      unlisteners.push(unlistenWhisper);

      return () => {
        unlisteners.forEach(unsub => unsub());
      };
    };

    setupDownloadListeners();
  }, [transcriptModelConfig, hideModal]);

  return {
    modals,
    messages,
    showModal,
    hideModal,
    hideAllModals,
  };
}
