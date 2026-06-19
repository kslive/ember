import React, { useState, useEffect } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import { RefreshCw } from 'lucide-react';
import { AudioLevelMeter, CompactAudioLevelMeter } from './AudioLevelMeter';
import { AudioBackendSelector } from './AudioBackendSelector';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Label } from '@/components/ui/label';
import Analytics from '@/lib/analytics';

export interface AudioDevice {
  name: string;
  device_type: 'Input' | 'Output';
}

export interface SelectedDevices {
  micDevice: string | null;
  systemDevice: string | null;
}

export interface AudioLevelData {
  device_name: string;
  device_type: string;
  rms_level: number;
  peak_level: number;
  is_active: boolean;
}

export interface AudioLevelUpdate {
  timestamp: number;
  levels: AudioLevelData[];
}

interface DeviceSelectionProps {
  selectedDevices: SelectedDevices;
  onDeviceChange: (devices: SelectedDevices) => void;
  disabled?: boolean;
}

export function DeviceSelection({ selectedDevices, onDeviceChange, disabled = false }: DeviceSelectionProps) {
  const [devices, setDevices] = useState<AudioDevice[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [audioLevels, setAudioLevels] = useState<Map<string, AudioLevelData>>(new Map());
  const [isMonitoring, setIsMonitoring] = useState(false);
  const [showLevels, setShowLevels] = useState(false);

  const inputDevices = devices.filter(device => device.device_type === 'Input');
  const outputDevices = devices.filter(device => device.device_type === 'Output');

  const fetchDevices = async () => {
    try {
      setError(null);
      const result = await invoke<AudioDevice[]>('get_audio_devices');
      setDevices(result);
      console.log('Fetched audio devices:', result);
    } catch (err) {
      console.error('Failed to fetch audio devices:', err);
      setError('Failed to load audio devices. Please check your system audio settings.');
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  useEffect(() => {
    fetchDevices();
  }, []);

  useEffect(() => {
    let unlisten: (() => void) | undefined;

    const setupAudioLevelListener = async () => {
      try {
        unlisten = await listen<AudioLevelUpdate>('audio-levels', (event) => {
          const levelUpdate = event.payload;
          const newLevels = new Map<string, AudioLevelData>();

          levelUpdate.levels.forEach(level => {
            newLevels.set(level.device_name, level);
          });

          setAudioLevels(newLevels);
        });
      } catch (err) {
        console.error('Failed to setup audio level listener:', err);
      }
    };

    setupAudioLevelListener();

    return () => {
      if (unlisten) {
        unlisten();
      }
      if (isMonitoring) {
        stopAudioLevelMonitoring();
      }
    };
  }, [isMonitoring]);

  const handleRefresh = async () => {
    setRefreshing(true);
    await fetchDevices();
  };

  const getDeviceMetadata = (deviceName: string) => {
    const nameLower = deviceName.toLowerCase();

    const isBluetooth = nameLower.includes('airpods')
      || nameLower.includes('bluetooth')
      || nameLower.includes('wireless')
      || nameLower.includes('wh-')
      || nameLower.includes('bt ');

    let category = 'wired';
    if (deviceName === 'default') {
      category = 'default';
    } else if (nameLower.includes('airpods')) {
      category = 'airpods';
    } else if (isBluetooth) {
      category = 'bluetooth';
    }

    return { isBluetooth, category };
  };

  const handleMicDeviceChange = (deviceName: string) => {
    const newDevices = {
      ...selectedDevices,
      micDevice: deviceName === 'default' ? null : deviceName
    };
    onDeviceChange(newDevices);

    const metadata = getDeviceMetadata(deviceName);
    Analytics.track('microphone_selected', {
      device_name: deviceName,
      device_category: metadata.category,
      is_bluetooth: metadata.isBluetooth.toString(),
      has_system_audio: (!!selectedDevices.systemDevice).toString()
    }).catch(err => console.error('Failed to track microphone selection:', err));
  };

  const handleSystemDeviceChange = (deviceName: string) => {
    const newDevices = {
      ...selectedDevices,
      systemDevice: deviceName === 'default' ? null : deviceName
    };
    onDeviceChange(newDevices);

    const metadata = getDeviceMetadata(deviceName);
    Analytics.track('system_audio_selected', {
      device_name: deviceName,
      device_category: metadata.category,
      is_bluetooth: metadata.isBluetooth.toString(),
      has_microphone: (!!selectedDevices.micDevice).toString()
    }).catch(err => console.error('Failed to track system audio selection:', err));
  };

  const startAudioLevelMonitoring = async () => {
    try {
      const deviceNames = inputDevices.map(device => device.name);
      if (deviceNames.length === 0) {
        setError('No microphone devices found to monitor');
        return;
      }

      await invoke('start_audio_level_monitoring', { deviceNames });
      setIsMonitoring(true);
      setShowLevels(true);
      console.log('Started audio level monitoring for input devices:', deviceNames);
    } catch (err) {
      console.error('Failed to start audio level monitoring:', err);
      setError('Failed to start audio level monitoring');
    }
  };

  const stopAudioLevelMonitoring = async () => {
    try {
      await invoke('stop_audio_level_monitoring');
      setIsMonitoring(false);
      setAudioLevels(new Map());
      console.log('Stopped audio level monitoring');
    } catch (err) {
      console.error('Failed to stop audio level monitoring:', err);
    }
  };

  const toggleAudioLevelMonitoring = async () => {
    if (isMonitoring) {
      await stopAudioLevelMonitoring();
    } else {
      await startAudioLevelMonitoring();
    }
  };

  if (loading) {
    return (
      <div className="space-y-3">
        <div className="animate-pulse flex gap-3">
          <div className="flex-1 h-[42px] bg-surface rounded-[11px]"></div>
          <div className="flex-1 h-[42px] bg-surface rounded-[11px]"></div>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-end">
        <button
          onClick={handleRefresh}
          disabled={refreshing || disabled}
          className="h-8 w-8 p-0 inline-flex items-center justify-center rounded-lg text-fg-muted transition-colors hover:bg-fg/[0.06] disabled:pointer-events-none disabled:opacity-50"
          title="Обновить список устройств"
        >
          <RefreshCw className={`h-4 w-4 ${refreshing ? 'animate-spin' : ''}`} />
        </button>
      </div>

      {error && (
        <div
          className="flex items-start gap-3 rounded-[11px] px-3.5 py-3 text-[13px] text-warn"
          style={{ background: 'rgba(180,83,9,.1)', border: '1px solid rgba(180,83,9,.25)' }}
        >
          {error}
        </div>
      )}

      <div className="flex flex-col gap-3 sm:flex-row">
        {}
        <div className="flex-1 space-y-1.5">
          <Label htmlFor="mic-selection" className="block font-mono text-[10px] uppercase tracking-[0.1em] text-fg-faint">
            Микрофон
          </Label>
          <Select
            value={selectedDevices.micDevice || 'default'}
            onValueChange={handleMicDeviceChange}
            disabled={disabled}
          >
            <SelectTrigger id="mic-selection" className="w-full h-[42px] px-3.5 rounded-[11px] bg-surface border-line text-[13.5px]">
              <SelectValue placeholder="Выберите микрофон" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="default">Микрофон по умолчанию</SelectItem>
              {inputDevices.map((device) => (
                <SelectItem
                  key={device.name}
                  value={`${device.name} (${device.device_type.toLowerCase()})`}
                >
                  {device.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          {inputDevices.length === 0 && (
            <p className="text-[11px] text-fg-faint">Микрофоны не найдены</p>
          )}

          {}
          {showLevels && inputDevices.length > 0 && (
            <div className="space-y-2 pt-2 border-t border-line">
              <p className="text-xs text-fg-muted font-medium">Уровни микрофона:</p>
              {inputDevices.map((device) => {
                const levelData = audioLevels.get(device.name);
                return (
                  <div key={`level-${device.name}`} className="space-y-1">
                    <div className="flex items-center justify-between">
                      <span className="text-xs text-fg-muted truncate max-w-[200px]">
                        {device.name}
                      </span>
                      {levelData && (
                        <CompactAudioLevelMeter
                          rmsLevel={levelData.rms_level}
                          peakLevel={levelData.peak_level}
                          isActive={levelData.is_active}
                        />
                      )}
                    </div>
                    {levelData && (
                      <AudioLevelMeter
                        rmsLevel={levelData.rms_level}
                        peakLevel={levelData.peak_level}
                        isActive={levelData.is_active}
                        deviceName={device.name}
                        size="small"
                      />
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </div>

        {}
        <div className="flex-1 space-y-1.5">
          <Label htmlFor="system-selection" className="block font-mono text-[10px] uppercase tracking-[0.1em] text-fg-faint">
            Системный звук
          </Label>

          <Select
            value={selectedDevices.systemDevice || 'default'}
            onValueChange={handleSystemDeviceChange}
            disabled={disabled}
          >
            <SelectTrigger id="system-selection" className="w-full h-[42px] px-3.5 rounded-[11px] bg-surface border-line text-[13.5px]">
              <SelectValue placeholder="Выберите системный звук" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="default">Системный звук по умолчанию</SelectItem>
              {outputDevices.map((device) => (
                <SelectItem
                  key={device.name}
                  value={`${device.name} (${device.device_type.toLowerCase()})`}
                >
                  {device.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>

          {outputDevices.length === 0 && (
            <p className="text-[11px] text-fg-faint">Устройства системного звука не найдены</p>
          )}
        </div>
      </div>

      {}
      {!disabled && (
        <div className="pt-4 border-t border-line">
          <AudioBackendSelector disabled={disabled} />
        </div>
      )}

      {}
      <div className="text-[11px] text-fg-muted space-y-1">
        <p>• <strong className="font-medium text-fg">Микрофон:</strong> записывает ваш голос и звуки вокруг</p>
        <p>• <strong className="font-medium text-fg">Системный звук:</strong> записывает звук с компьютера (музыка, звонки и т.д.)</p>
      </div>
    </div>
  );
}