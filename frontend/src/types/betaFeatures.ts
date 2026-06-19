
export interface BetaFeatures { importAndRetranscribe: boolean }
export type BetaFeatureKey = keyof BetaFeatures;

export const DEFAULT_BETA_FEATURES: BetaFeatures = { importAndRetranscribe: false };

export const BETA_FEATURE_NAMES: Record<keyof BetaFeatures, string> = {
  importAndRetranscribe: 'Импорт и ретранскрипция',
};

export const BETA_FEATURE_DESCRIPTIONS: Record<keyof BetaFeatures, string> = {
  importAndRetranscribe: '',
};

export function loadBetaFeatures(): BetaFeatures { return { ...DEFAULT_BETA_FEATURES }; }
export function saveBetaFeatures(_features: BetaFeatures): void {}
