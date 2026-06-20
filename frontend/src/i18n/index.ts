import i18n from 'i18next';
import { initReactI18next } from 'react-i18next';
import type { Locale } from '@/lib/preferences';

import enCommon from './locales/en/common.json';
import enOnboarding from './locales/en/onboarding.json';
import enSettings from './locales/en/settings.json';
import enSidebar from './locales/en/sidebar.json';
import enRecording from './locales/en/recording.json';
import enMeeting from './locales/en/meeting.json';
import enSummary from './locales/en/summary.json';
import enToasts from './locales/en/toasts.json';
import enModelsettings from './locales/en/modelsettings.json';
import enModels from './locales/en/models.json';
import enRecordingsettings from './locales/en/recordingsettings.json';
import enAbout from './locales/en/about.json';

import ruCommon from './locales/ru/common.json';
import ruOnboarding from './locales/ru/onboarding.json';
import ruSettings from './locales/ru/settings.json';
import ruSidebar from './locales/ru/sidebar.json';
import ruRecording from './locales/ru/recording.json';
import ruMeeting from './locales/ru/meeting.json';
import ruSummary from './locales/ru/summary.json';
import ruToasts from './locales/ru/toasts.json';
import ruModelsettings from './locales/ru/modelsettings.json';
import ruModels from './locales/ru/models.json';
import ruRecordingsettings from './locales/ru/recordingsettings.json';
import ruAbout from './locales/ru/about.json';

import zhCommon from './locales/zh/common.json';
import zhOnboarding from './locales/zh/onboarding.json';
import zhSettings from './locales/zh/settings.json';
import zhSidebar from './locales/zh/sidebar.json';
import zhRecording from './locales/zh/recording.json';
import zhMeeting from './locales/zh/meeting.json';
import zhSummary from './locales/zh/summary.json';
import zhToasts from './locales/zh/toasts.json';
import zhModelsettings from './locales/zh/modelsettings.json';
import zhModels from './locales/zh/models.json';
import zhRecordingsettings from './locales/zh/recordingsettings.json';
import zhAbout from './locales/zh/about.json';

export const LOCALES: Locale[] = ['en', 'ru', 'zh'];
export const NAMESPACES = [
  'common',
  'onboarding',
  'settings',
  'sidebar',
  'recording',
  'meeting',
  'summary',
  'toasts',
  'modelsettings',
  'models',
  'recordingsettings',
  'about',
] as const;

/** Map a BCP-47 navigator language to one of our supported UI locales. */
export function detectInitialLocale(): Locale {
  if (typeof navigator !== 'undefined') {
    const l = (navigator.language || 'en').toLowerCase();
    if (l.startsWith('ru')) return 'ru';
    if (l.startsWith('zh')) return 'zh';
  }
  return 'en';
}

/** App locale → BCP-47 tag for Intl date/number formatting. */
export const BCP47: Record<Locale, string> = {
  en: 'en-US',
  ru: 'ru-RU',
  zh: 'zh-CN',
};

const resources = {
  en: {
    common: enCommon,
    onboarding: enOnboarding,
    settings: enSettings,
    sidebar: enSidebar,
    recording: enRecording,
    meeting: enMeeting,
    summary: enSummary,
    toasts: enToasts,
    modelsettings: enModelsettings,
    models: enModels,
    recordingsettings: enRecordingsettings,
    about: enAbout,
  },
  ru: {
    common: ruCommon,
    onboarding: ruOnboarding,
    settings: ruSettings,
    sidebar: ruSidebar,
    recording: ruRecording,
    meeting: ruMeeting,
    summary: ruSummary,
    toasts: ruToasts,
    modelsettings: ruModelsettings,
    models: ruModels,
    recordingsettings: ruRecordingsettings,
    about: ruAbout,
  },
  zh: {
    common: zhCommon,
    onboarding: zhOnboarding,
    settings: zhSettings,
    sidebar: zhSidebar,
    recording: zhRecording,
    meeting: zhMeeting,
    summary: zhSummary,
    toasts: zhToasts,
    modelsettings: zhModelsettings,
    models: zhModels,
    recordingsettings: zhRecordingsettings,
    about: zhAbout,
  },
};

if (!i18n.isInitialized) {
  i18n.use(initReactI18next).init({
    resources,
    lng: detectInitialLocale(),
    fallbackLng: 'en',
    ns: NAMESPACES as unknown as string[],
    defaultNS: 'common',
    interpolation: { escapeValue: false },
    react: { useSuspense: false },
    returnNull: false,
  });
}

export default i18n;
