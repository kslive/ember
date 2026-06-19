import { useState, useEffect } from 'react';

export type Platform = 'macos' | 'windows' | 'linux' | 'unknown';

declare global {
  interface Window {
    __TAURI_INTERNALS__?: unknown;
  }
}

function detectPlatformFromUserAgent(): Platform {
  if (typeof navigator === 'undefined') return 'unknown';

  const userAgent = navigator.userAgent.toLowerCase();
  if (userAgent.includes('mac')) {
    return 'macos';
  } else if (userAgent.includes('win')) {
    return 'windows';
  } else if (userAgent.includes('linux')) {
    return 'linux';
  }
  return 'unknown';
}

export function usePlatform(): Platform {
  const [currentPlatform, setCurrentPlatform] = useState<Platform>(() => detectPlatformFromUserAgent());

  useEffect(() => {
    async function detectPlatform() {
      if (typeof window === 'undefined' || !window.__TAURI_INTERNALS__) {
        setCurrentPlatform(detectPlatformFromUserAgent());
        return;
      }

      try {
        const { platform } = await import('@tauri-apps/plugin-os');
        const platformName = await platform();

        switch (platformName) {
          case 'macos':
          case 'ios':
            setCurrentPlatform('macos');
            break;
          case 'windows':
            setCurrentPlatform('windows');
            break;
          case 'linux':
          case 'android':
            setCurrentPlatform('linux');
            break;
          default:
            setCurrentPlatform('unknown');
        }
      } catch (error) {
        console.warn('[usePlatform] Tauri platform detection failed, using user agent:', error);
        setCurrentPlatform(detectPlatformFromUserAgent());
      }
    }

    detectPlatform();
  }, []);

  return currentPlatform;
}

export function useIsLinux(): boolean {
  const currentPlatform = usePlatform();
  return currentPlatform === 'linux';
}
