
export interface SystemAudioCommands {
  startSystemAudioCaptureCommand(): Promise<string>;

  listSystemAudioDevicesCommand(): Promise<string[]>;

  checkSystemAudioPermissionsCommand(): Promise<boolean>;

  startSystemAudioMonitoring(): Promise<void>;

  stopSystemAudioMonitoring(): Promise<void>;

  getSystemAudioMonitoringStatus(): Promise<boolean>;
}

export interface SystemAudioEvents {
  'system-audio-started': string[];
  'system-audio-stopped': void;
}

