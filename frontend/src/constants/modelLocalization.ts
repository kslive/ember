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
    'gemma3:1b': {
      displayName: 'Gemma 3 1B (Fast)',
      description:
        'The fastest. Runs on any hardware (~1GB RAM). Great for quick notes.',
    },
    'gemma3:4b': {
      displayName: 'Gemma 3 4B (Balanced)',
      description: 'A balance of quality and speed. Needs ~3.5GB RAM.',
    },
    'qwen2.5:7b': {
      displayName: 'Qwen2.5 7B (Smart)',
      description:
        'Noticeably smarter than Gemma 4B: strong multilingual quality and instruction following. Needs ~6GB RAM.',
    },
    'qwen2.5:14b': {
      displayName: 'Qwen2.5 14B (Maximum)',
      description:
        'Best quality for 16GB. Slower and hungrier (~10GB RAM), but the most accurate summaries.',
    },
  },
  ru: {
    'gemma3:1b': {
      displayName: 'Gemma 3 1B (Быстрая)',
      description:
        'Самая быстрая. Работает на любом железе (~1GB RAM). Хороша для быстрых конспектов.',
    },
    'gemma3:4b': {
      displayName: 'Gemma 3 4B (Сбалансированная)',
      description: 'Баланс качества и скорости. Нужно ~3.5GB RAM.',
    },
    'qwen2.5:7b': {
      displayName: 'Qwen2.5 7B (Умная)',
      description:
        'Заметно умнее Gemma 4B: лучше русский и следование инструкциям. Нужно ~6GB RAM.',
    },
    'qwen2.5:14b': {
      displayName: 'Qwen2.5 14B (Максимум)',
      description:
        'Лучшее качество для 16GB. Медленнее и прожорливее (~10GB RAM), но самые точные саммари.',
    },
  },
  zh: {
    'gemma3:1b': {
      displayName: 'Gemma 3 1B（快速）',
      description: '最快的模型。可在任何硬件上运行（约 1GB 内存）。适合快速记录要点。',
    },
    'gemma3:4b': {
      displayName: 'Gemma 3 4B（均衡）',
      description: '质量与速度的平衡。需要约 3.5GB 内存。',
    },
    'qwen2.5:7b': {
      displayName: 'Qwen2.5 7B（智能）',
      description:
        '明显比 Gemma 4B 更聪明：多语言质量出色，指令遵循能力更强。需要约 6GB 内存。',
    },
    'qwen2.5:14b': {
      displayName: 'Qwen2.5 14B（极致）',
      description:
        '16GB 内存下的最佳质量。速度更慢、占用更高（约 10GB 内存），但生成的摘要最准确。',
    },
  },
};
