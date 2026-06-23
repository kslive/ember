import { useCallback, useEffect, useRef, useState } from 'react';
import { invoke } from '@tauri-apps/api/core';

export interface UpdateInfo {
  available: boolean;
  version: string;
  notes: string | null;
  pub_date: string | null;
}

const CHECK_INTERVAL_MS = 24 * 60 * 60 * 1000;

export function useUpdater() {
  const [updateInfo, setUpdateInfo] = useState<UpdateInfo | null>(null);
  const [isChecking, setIsChecking] = useState(false);
  const [isInstalling, setIsInstalling] = useState(false);
  const lastCheckRef = useRef<number>(0);

  const checkForUpdates = useCallback(async (force = false) => {
    const now = Date.now();
    if (!force && lastCheckRef.current !== 0 && now - lastCheckRef.current < CHECK_INTERVAL_MS) {
      return;
    }
    lastCheckRef.current = now;

    setIsChecking(true);
    try {
      const info = await invoke<UpdateInfo>('check_update');
      setUpdateInfo(info);
    } catch (error) {
      console.warn('[useUpdater] check_update failed:', error);
    } finally {
      setIsChecking(false);
    }
  }, []);

  const installUpdate = useCallback(async () => {
    setIsInstalling(true);
    try {
      await invoke('install_update');
    } catch (error) {
      console.warn('[useUpdater] install_update failed:', error);
    } finally {
      setIsInstalling(false);
    }
  }, []);

  useEffect(() => {
    if (typeof window === 'undefined' || !window.__TAURI_INTERNALS__) return;

    checkForUpdates();
    const interval = setInterval(() => checkForUpdates(), CHECK_INTERVAL_MS);
    return () => clearInterval(interval);
  }, [checkForUpdates]);

  return { updateInfo, isChecking, isInstalling, checkForUpdates, installUpdate };
}
