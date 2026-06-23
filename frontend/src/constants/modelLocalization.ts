import type { Locale } from '@/lib/preferences';

/**
 * Localized display names and descriptions for the built-in summary LLM models.
 *
 * The canonical strings live in Rust at
 * `src-tauri/src/summary/summary_engine/models.rs` and are returned by the
 * `builtin_ai_list_models` command. Those strings are Russian; this map provides
 * per-locale overrides. The `ru` entries are kept verbatim from `models.rs` so
 * they stay in sync; `en`/`zh` are faithful translations.
 *
 * Keyed by the stable model id (`ModelInfo.name`). Consumers should fall back to
 * the Rust-provided `display_name`/`description` when a key is missing, e.g.:
 *
 *   MODEL_LABELS[locale]?.[model.name]?.displayName ?? model.display_name
 */
export const MODEL_LABELS: Record<
  Locale,
  Record<string, { displayName: string; description: string }>
> = {
  en: {
    'qwen3:1.7b': {
      displayName: 'Qwen3 1.7B (Fast)',
      description:
        'The fastest. Runs on any Apple Silicon Mac (~2GB RAM). Great for quick notes.',
    },
    'qwen3:4b': {
      displayName: 'Qwen3 4B (Balanced)',
      description:
        'A balance of quality and speed. Needs ~6GB RAM.',
    },
    'qwen3:8b': {
      displayName: 'Qwen3 8B (Maximum)',
      description:
        'Recommended. Best quality and the most accurate summaries. Needs ~10GB RAM.',
    },
  },
  ru: {
    'qwen3:1.7b': {
      displayName: 'Qwen3 1.7B (Быстрая)',
      description:
        'Самая быстрая. Работает на любом Mac с Apple Silicon (~2GB RAM). Хороша для быстрых конспектов.',
    },
    'qwen3:4b': {
      displayName: 'Qwen3 4B (Сбалансированная)',
      description: 'Баланс качества и скорости. Нужно ~6GB RAM.',
    },
    'qwen3:8b': {
      displayName: 'Qwen3 8B (Максимум)',
      description:
        'Рекомендуется. Лучшее качество и самые точные саммари. Нужно ~10GB RAM.',
    },
  },
  zh: {
    'qwen3:1.7b': {
      displayName: 'Qwen3 1.7B（快速）',
      description: '最快的模型。可在任何 Apple Silicon Mac 上运行（约 2GB 内存）。适合快速记录要点。',
    },
    'qwen3:4b': {
      displayName: 'Qwen3 4B（均衡）',
      description: '质量与速度的平衡。需要约 6GB 内存。',
    },
    'qwen3:8b': {
      displayName: 'Qwen3 8B（极致）',
      description:
        '推荐。最佳质量，生成的摘要最准确。需要约 10GB 内存。',
    },
  },
};
