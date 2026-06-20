'use client';

import React, { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { invoke } from '@tauri-apps/api/core';
import { toast } from 'sonner';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { Summary, SummaryDataResponse } from '@/types';
import {
  exportSummaryToMd,
  getSummaryFolder,
  pickSummaryMarkdown,
  cleanLeakedMarkdown,
  stripLeadingFrontmatter,
} from '@/lib/summaryExport';

const SparkleIcon = ({ className, size = 14 }: { className?: string; size?: number }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" className={className} aria-hidden="true">
    <path d="M12 2l1.8 5.2L19 9l-5.2 1.8L12 16l-1.8-5.2L5 9l5.2-1.8z" />
  </svg>
);

type CalloutKind = 'tip' | 'success' | 'warning' | 'note' | 'important';

function normalizeCalloutKind(raw: string): CalloutKind | null {
  const t = raw.trim().toLowerCase();
  if (t === 'tip' || t === 'hint') return 'tip';
  if (t === 'success' || t === 'check' || t === 'done') return 'success';
  if (t === 'warning' || t === 'caution' || t === 'attention') return 'warning';
  if (t === 'important') return 'important';
  if (t === 'note' || t === 'info' || t === 'abstract' || t === 'summary') return 'note';
  return null;
}

const CALLOUT_STYLES: Record<CalloutKind, { box: string; icon: string; text: string }> = {
  tip:       { box: 'bg-accent-weak border-accent/30', icon: 'text-accent-text', text: 'text-fg' },
  success:   { box: 'bg-good/10 border-good/30',       icon: 'text-good',        text: 'text-fg' },
  warning:   { box: 'bg-warn/10 border-warn/30',       icon: 'text-warn',        text: 'text-fg' },
  note:      { box: 'bg-surface border-line',          icon: 'text-fg-faint',    text: 'text-fg' },
  important: { box: 'bg-surface border-line',          icon: 'text-accent-text', text: 'text-fg' },
};

function CalloutIcon({ kind, className }: { kind: CalloutKind; className?: string }) {
  const common = {
    width: 17,
    height: 17,
    viewBox: '0 0 24 24',
    fill: 'none',
    stroke: 'currentColor',
    strokeWidth: 1.8,
    strokeLinecap: 'round' as const,
    strokeLinejoin: 'round' as const,
    className,
    'aria-hidden': true,
  };
  switch (kind) {
    case 'tip':
      return (
        <svg {...common}><path d="M9 18h6M10 22h4M12 2a7 7 0 0 0-4 12.7c.6.5 1 1.3 1 2.1h6c0-.8.4-1.6 1-2.1A7 7 0 0 0 12 2z" /></svg>
      );
    case 'success':
      return (
        <svg {...common}><path d="M12 2 4 5v6c0 5 3.4 8.6 8 10 4.6-1.4 8-5 8-10V5z" /><path d="M9 12l2 2 4-4" /></svg>
      );
    case 'warning':
      return (
        <svg {...common}><path d="M10.3 3.3 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.3a2 2 0 0 0-3.4 0z" /><line x1="12" y1="9" x2="12" y2="13" /><line x1="12" y1="17" x2="12" y2="17" /></svg>
      );
    case 'important':
      return (
        <svg width="17" height="17" viewBox="0 0 24 24" fill="currentColor" className={className} aria-hidden="true"><path d="M12 2l1.8 5.2L19 9l-5.2 1.8L12 16l-1.8-5.2L5 9l5.2-1.8z" /></svg>
      );
    case 'note':
    default:
      return (
        <svg {...common}><circle cx="12" cy="12" r="9" /><path d="M12 16v-4M12 8h.01" /></svg>
      );
  }
}

function EmberCallout({ kind, children }: { kind: CalloutKind; children: React.ReactNode }) {
  const s = CALLOUT_STYLES[kind];
  return (
    <div className={`my-4 first:mt-0 rounded-[12px] border px-[18px] py-3.5 flex gap-3 items-start ${s.box}`}>
      <span className={`shrink-0 mt-px ${s.icon}`}>
        <CalloutIcon kind={kind} />
      </span>
      <div className={`flex-1 min-w-0 text-[13.5px] leading-[1.6] ${s.text} [&>p]:my-0 [&>p]:text-inherit [&>p:not(:first-child)]:mt-2 [&_strong]:text-fg [&_strong]:font-semibold`}>
        {children}
      </div>
    </div>
  );
}

function extractCallout(children: React.ReactNode): { kind: CalloutKind; rest: React.ReactNode } | null {
  const arr = React.Children.toArray(children);
  if (arr.length === 0) return null;

  let idx = 0;
  while (idx < arr.length && typeof arr[idx] === 'string' && !(arr[idx] as string).trim()) idx++;
  const first = arr[idx];
  if (typeof first !== 'string') return null;

  const m = first.match(/^\s*\[!(\w+)\]\s*([\s\S]*)$/);
  if (!m) return null;
  const kind = normalizeCalloutKind(m[1]);
  if (!kind) return null;

  const remainderFirst = m[2];
  const rest = [
    ...arr.slice(0, idx),
    ...(remainderFirst ? [remainderFirst] : []),
    ...arr.slice(idx + 1),
  ];
  return { kind, rest };
}

interface Props {
  meeting: { id: string; title: string; created_at: string };
  aiSummary: SummaryDataResponse | Summary | null;
  customPrompt?: string;
  onPromptChange?: (value: string) => void;
  onGenerate?: (customPrompt: string) => void | Promise<void>;
  isGenerating?: boolean;
  canGenerate?: boolean;
}

function hasSummary(data: Props['aiSummary']): boolean {
  return !!pickSummaryMarkdown(data).trim();
}

const emberMarkdownComponents = {
  h1: ({ children }: any) => (
    <h2 className="text-[15px] font-semibold text-fg mt-6 first:mt-0 mb-2.5 tracking-[-0.01em]">{children}</h2>
  ),
  h2: ({ children }: any) => (
    <h3 className="text-[14px] font-semibold text-fg mt-6 first:mt-0 mb-2.5">{children}</h3>
  ),
  h3: ({ children }: any) => (
    <h3 className="text-[14px] font-semibold text-fg mt-6 first:mt-0 mb-2.5">{children}</h3>
  ),
  h4: ({ children }: any) => (
    <h4 className="text-[13.5px] font-semibold text-fg mt-5 first:mt-0 mb-2">{children}</h4>
  ),
  p: ({ children }: any) => {
    const callout = extractCallout(children);
    if (callout) {
      return <EmberCallout kind={callout.kind}>{callout.rest}</EmberCallout>;
    }
    return <p className="text-[13.5px] leading-[1.65] text-fg-muted my-3 first:mt-0">{children}</p>;
  },
  ul: ({ children }: any) => (
    <ul className="flex flex-col gap-2.5 my-3 first:mt-0 marker:content-['']">{children}</ul>
  ),
  ol: ({ children }: any) => (
    <ol className="flex flex-col gap-2.5 my-3 first:mt-0 list-decimal list-inside">{children}</ol>
  ),
  li: ({ children, className }: any) => {
    const isTask = typeof className === 'string' && className.includes('task-list-item');
    if (isTask) {
      const findChecked = (nodes: React.ReactNode): boolean =>
        React.Children.toArray(nodes).some((c: any) => {
          if (!React.isValidElement(c)) return false;
          const p = (c.props as any) || {};
          if (p.type === 'checkbox') return !!p.checked;
          return findChecked(p.children);
        });
      const checked = findChecked(children);
      return (
        <li className="flex items-center gap-2.5 text-[13.5px] leading-[1.55] text-fg-muted list-none [&_input]:hidden">
          {checked ? (
            <span
              className="w-4 h-4 rounded-[5px] bg-accent flex items-center justify-center shrink-0"
              aria-hidden="true"
            >
              <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
                <path d="M5 12l5 5L20 6" />
              </svg>
            </span>
          ) : (
            <span className="w-4 h-4 rounded-[5px] border-[1.5px] border-line-strong shrink-0" aria-hidden="true" />
          )}
          <span className="flex-1 min-w-0">{children}</span>
        </li>
      );
    }
    return (
      <li className="flex gap-2.5 text-[13.5px] leading-[1.55] text-fg-muted">
        <span className="text-accent select-none" aria-hidden="true">—</span>
        <span className="flex-1 min-w-0">{children}</span>
      </li>
    );
  },
  strong: ({ children }: any) => <strong className="font-semibold text-fg">{children}</strong>,
  em: ({ children }: any) => <em className="italic">{children}</em>,
  a: ({ children, href }: any) => (
    <a href={href} className="text-accent-text font-medium hover:opacity-80 transition-opacity">{children}</a>
  ),
  code: ({ children }: any) => (
    <span className="text-[11px] px-2 py-0.5 rounded-[6px] bg-surface text-fg-muted">{children}</span>
  ),
  blockquote: ({ children }: any) => {
    const arr = React.Children.toArray(children).filter(
      (c: any) => !(typeof c === 'string' && !c.trim())
    );
    const firstEl = arr.find((c: any) => React.isValidElement(c)) as any;
    if (firstEl && React.isValidElement(firstEl)) {
      const callout = extractCallout((firstEl.props as any)?.children);
      if (callout) {
        const restChildren = arr.map((c: any) =>
          c === firstEl ? <p key="head">{callout.rest}</p> : c
        );
        return <EmberCallout kind={callout.kind}>{restChildren}</EmberCallout>;
      }
    }
    return (
      <blockquote className="border-l-2 border-line-strong pl-3.5 my-3 text-[13.5px] leading-[1.6] text-fg-muted">{children}</blockquote>
    );
  },
  hr: () => <hr className="border-0 border-t border-line my-5" />,
};

export function SummaryObsidianCard({
  meeting,
  aiSummary,
  customPrompt = '',
  onPromptChange,
  onGenerate,
  isGenerating = false,
  canGenerate = true,
}: Props) {
  const { t } = useTranslation('meeting');
  const [opening, setOpening] = useState(false);

  const openInObsidian = async () => {
    setOpening(true);
    try {
      const folder = await getSummaryFolder();
      if (!folder) {
        toast.error(t('toasts.summaryFolderNotConfigured'), {
          description: t('toasts.summaryFolderNotConfiguredDescription'),
        });
        return;
      }

      const markdown = pickSummaryMarkdown(aiSummary);
      const path = await exportSummaryToMd(meeting, markdown);
      if (!path) {
        toast.error(t('toasts.nothingToOpen'), { description: t('toasts.nothingToOpenDescription') });
        return;
      }

      await invoke('open_in_obsidian', { filePath: path });
    } catch (e: any) {
      toast.error(t('toasts.obsidianOpenFailed'), {
        description: e?.message ?? String(e),
      });
    } finally {
      setOpening(false);
    }
  };

  if (!hasSummary(aiSummary)) {
    return (
      <div className="flex flex-col items-center justify-center text-center py-16">
        <div className="w-[54px] h-[54px] rounded-[16px] bg-surface flex items-center justify-center text-accent-text mb-[18px]">
          <SparkleIcon size={24} />
        </div>
        <h3 className="text-[17px] font-semibold text-fg mb-2">{t('empty.title')}</h3>
        <p className="text-[13.5px] leading-[1.6] text-fg-muted max-w-[300px] mb-[22px]">
          {t('empty.description')}
        </p>

        {onPromptChange && (
          <div className="w-full max-w-[320px] mb-3.5 text-left">
            <input
              type="text"
              value={customPrompt}
              onChange={(e) => onPromptChange(e.target.value)}
              placeholder={t('empty.promptPlaceholder')}
              className="w-full px-3.5 py-3 rounded-md bg-elevated border border-line text-[13px] text-fg placeholder:text-fg-faint focus:outline-none focus:ring-1 focus:ring-accent focus:border-accent/40 transition-colors"
            />
          </div>
        )}

        {onGenerate && (
          <button
            type="button"
            onClick={() => onGenerate(customPrompt)}
            disabled={isGenerating || !canGenerate}
            className="w-full max-w-[320px] h-[46px] rounded-md bg-accent hover:opacity-90 text-white text-[14.5px] font-medium inline-flex items-center justify-center gap-2.5 shadow-glow transition-opacity disabled:opacity-50"
          >
            <SparkleIcon size={16} />
            {t('empty.generate')}
          </button>
        )}
      </div>
    );
  }

  const markdown = stripLeadingFrontmatter(cleanLeakedMarkdown(pickSummaryMarkdown(aiSummary)));

  return (
    <div className="flex flex-col h-full">
      {}
      <div className="flex-1 min-w-0">
        <ReactMarkdown remarkPlugins={[remarkGfm]} components={emberMarkdownComponents}>
          {markdown}
        </ReactMarkdown>
      </div>

      <div className="sticky bottom-0 z-10 bg-canvas border-t border-line pt-3.5 pb-4 mt-[18px] flex items-center justify-between gap-3">
        <span className="text-[12px] text-fg-faint">{t('obsidian.savedToMarkdown')}</span>
        <button
          type="button"
          onClick={openInObsidian}
          disabled={opening}
          className="text-[12.5px] font-medium text-accent-text hover:opacity-80 disabled:opacity-60 transition-opacity"
        >
          {opening ? t('obsidian.opening') : t('obsidian.open')}
        </button>
      </div>
    </div>
  );
}

export default SummaryObsidianCard;
