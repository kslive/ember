import React, { useEffect, useState, useCallback } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { Mic, Volume2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { OnboardingContainer } from '../OnboardingContainer';
import { PermissionRow } from '../shared';
import { useOnboarding } from '@/contexts/OnboardingContext';

export function PermissionsStep() {
  const { setPermissionStatus, setPermissionsSkipped, permissions, completeOnboarding } = useOnboarding();
  const [pending, setPending] = useState<null | 'microphone' | 'systemAudio'>(null);

  const checkPermissions = useCallback(async () => {
    console.log('[PermissionsStep] Current permission states:');
    console.log(`  - Microphone: ${permissions.microphone}`);
    console.log(`  - System Audio: ${permissions.systemAudio}`);
  }, [permissions.microphone, permissions.systemAudio]);

  useEffect(() => {
    checkPermissions();
  }, [checkPermissions]);

  const handleMicrophoneAction = async () => {
    if (permissions.microphone === 'denied') {
      try {
        await invoke('open_system_settings');
      } catch {
        alert('Разрешите доступ к микрофону в Системных настройках → Конфиденциальность и безопасность → Микрофон');
      }
      return;
    }

    setPending('microphone');
    try {
      console.log('[PermissionsStep] Triggering microphone permission...');
      const granted = await invoke<boolean>('trigger_microphone_permission');
      console.log('[PermissionsStep] Microphone permission result:', granted);

      if (granted) {
        setPermissionStatus('microphone', 'authorized');
      } else {
        setPermissionStatus('microphone', 'denied');
      }
    } catch (err) {
      console.error('[PermissionsStep] Failed to request microphone permission:', err);
      setPermissionStatus('microphone', 'denied');
    } finally {
      setPending(null);
    }
  };

  const handleSystemAudioAction = async () => {
    if (permissions.systemAudio === 'denied') {
      try {
        await invoke('open_system_settings');
      } catch {
        alert('Разрешите захват аудио в Системных настройках → Конфиденциальность и безопасность → Захват аудио');
      }
      return;
    }

    setPending('systemAudio');
    try {
      console.log('[PermissionsStep] Triggering Audio Capture permission...');
      const granted = await invoke<boolean>('trigger_system_audio_permission_command');
      console.log('[PermissionsStep] System audio permission result:', granted);

      if (granted) {
        setPermissionStatus('systemAudio', 'authorized');
        console.log('[PermissionsStep] Audio Capture permission verified - audio is not silence');
      } else {
        setPermissionStatus('systemAudio', 'denied');
        console.log('[PermissionsStep] Audio Capture permission denied - audio is silence');
      }
    } catch (err) {
      console.error('[PermissionsStep] Failed to request system audio permission:', err);
      setPermissionStatus('systemAudio', 'denied');
    } finally {
      setPending(null);
    }
  };

  const handleFinish = async () => {
    try {
      await completeOnboarding();
      window.location.reload();
    } catch (error) {
      console.error('Failed to complete onboarding:', error);
    }
  };

  const handleSkip = async () => {
    setPermissionsSkipped(true);
    await handleFinish();
  };

  const allPermissionsGranted =
    permissions.microphone === 'authorized' &&
    permissions.systemAudio === 'authorized';

  return (
    <OnboardingContainer
      title="Доступы"
      description="Ember нужен доступ к микрофону и системному звуку для записи встреч"
      step={4}
      hideProgress={true}
      className="max-w-lg"
    >
      <div className="space-y-6">
        {}
        <div className="space-y-3">
          {}
          <PermissionRow
            icon={<Mic className="w-[19px] h-[19px]" strokeWidth={1.8} />}
            title="Микрофон"
            description="Требуется для записи вашего голоса во время встреч"
            status={permissions.microphone}
            isPending={pending === 'microphone'}
            onAction={handleMicrophoneAction}
          />

          {}
          <PermissionRow
            icon={<Volume2 className="w-[19px] h-[19px]" strokeWidth={1.8} />}
            title="Системный звук"
            description="Нажмите «Разрешить», чтобы предоставить доступ к захвату аудио"
            status={permissions.systemAudio}
            isPending={pending === 'systemAudio'}
            onAction={handleSystemAudioAction}
          />
        </div>

        {}
        <div className="flex flex-col items-center gap-3 pt-2">
          <Button
            onClick={handleFinish}
            disabled={!allPermissionsGranted}
            className="h-[46px] w-full text-[15px]"
          >
            Завершить настройку
          </Button>

          <button
            onClick={handleSkip}
            className="font-mono text-[11px] text-fg-faint transition-colors hover:text-fg-muted"
          >
            Сделаю это позже
          </button>

          {!allPermissionsGranted && (
            <p className="text-center text-[12px] text-fg-faint">
              Без доступов запись работать не будет. Их можно предоставить позже в настройках.
            </p>
          )}
        </div>
      </div>
    </OnboardingContainer>
  );
}
