
export const DEFAULT_WHISPER_MODEL = 'large-v3-turbo';

export const DEFAULT_PARAKEET_MODEL = 'parakeet-tdt-0.6b-v3-int8';

export const MODEL_DEFAULTS = {
  whisper: DEFAULT_WHISPER_MODEL,
  localWhisper: DEFAULT_WHISPER_MODEL,
  parakeet: DEFAULT_PARAKEET_MODEL,
} as const;
