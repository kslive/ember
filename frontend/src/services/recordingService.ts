
import { invoke } from '@tauri-apps/api/core';
import { listen, UnlistenFn } from '@tauri-apps/api/event';

export interface RecordingState {
  is_recording: boolean;
  is_paused: boolean;
  is_active: boolean;
  recording_duration: number | null;
  active_duration: number | null;
}

export interface RecordingStoppedPayload {
  message: string;
  folder_path?: string;
  meeting_name?: string;
}

export class RecordingService {
  async isRecording(): Promise<boolean> {
    return invoke<boolean>('is_recording');
  }

  async getRecordingState(): Promise<RecordingState> {
    return invoke<RecordingState>('get_recording_state');
  }

  async getRecordingMeetingName(): Promise<string | null> {
    return invoke<string | null>('get_recording_meeting_name');
  }

  async startRecording(): Promise<void> {
    return invoke('start_recording');
  }

  async startRecordingWithDevices(
    micDeviceName: string | null,
    systemDeviceName: string | null,
    meetingName: string
  ): Promise<void> {
    return invoke('start_recording_with_devices_and_meeting', {
      mic_device_name: micDeviceName,
      system_device_name: systemDeviceName,
      meeting_name: meetingName
    });
  }

  async stopRecording(savePath: string): Promise<void> {
    return invoke('stop_recording', {
      args: { save_path: savePath }
    });
  }

  async pauseRecording(): Promise<void> {
    return invoke('pause_recording');
  }

  async resumeRecording(): Promise<void> {
    return invoke('resume_recording');
  }

  async onRecordingStarted(callback: () => void): Promise<UnlistenFn> {
    return listen('recording-started', callback);
  }

  async onRecordingStopped(callback: (payload: RecordingStoppedPayload) => void): Promise<UnlistenFn> {
    return listen<RecordingStoppedPayload>('recording-stopped', (event) => {
      callback(event.payload);
    });
  }

  async onRecordingPaused(callback: () => void): Promise<UnlistenFn> {
    return listen('recording-paused', callback);
  }

  async onRecordingResumed(callback: () => void): Promise<UnlistenFn> {
    return listen('recording-resumed', callback);
  }

  async onChunkDropWarning(callback: (warning: string) => void): Promise<UnlistenFn> {
    return listen<string>('chunk-drop-warning', (event) => {
      callback(event.payload);
    });
  }

  async onSpeechDetected(callback: () => void): Promise<UnlistenFn> {
    return listen('speech-detected', callback);
  }
}

export const recordingService = new RecordingService();
