'use client';

import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { useRouter, usePathname } from 'next/navigation';
import { useTranslation } from 'react-i18next';
import i18n, { BCP47 } from '@/i18n';
import type { Locale } from '@/lib/preferences';
import {
  Pencil, Trash2, Search, X,
} from 'lucide-react';
import { useSidebar, CurrentMeeting } from './SidebarProvider';
import { useRecordingState } from '@/contexts/RecordingStateContext';
import { invoke } from '@tauri-apps/api/core';
import { toast } from 'sonner';
import {
  Dialog, DialogContent, DialogFooter, DialogTitle, DialogDescription,
} from '@/components/ui/dialog';
import { EmberDialog } from '@/components/ui/ember-dialog';
import { VisuallyHidden } from '@/components/ui/visually-hidden';
import Logo from '../Logo';

interface DeleteState { open: boolean; id: string | null; title: string }
interface RenameState { open: boolean; id: string | null; value: string }

function highlightMatch(text: string, term?: string): React.ReactNode {
  const t = term?.trim();
  if (!t || !text) return text;

  const lowerText = text.toLocaleLowerCase();
  const lowerTerm = t.toLocaleLowerCase();
  const out: React.ReactNode[] = [];
  let from = 0;
  let key = 0;

  while (from < text.length) {
    const idx = lowerText.indexOf(lowerTerm, from);
    if (idx === -1) { out.push(text.slice(from)); break; }
    if (idx > from) out.push(text.slice(from, idx));
    out.push(
      <mark
        key={key++}
        className="bg-accent/20 text-accent-text rounded-[3px] px-0.5"
      >
        {text.slice(idx, idx + lowerTerm.length)}
      </mark>,
    );
    from = idx + lowerTerm.length;
  }

  return out;
}

function cleanMeetingTitle(t: string): string {
  const raw = (t || '').trim();
  const isAutoName =
    raw === '' ||
    /^(recording|запись|录音)[\s_-]*\d/i.test(raw) ||
    /^(\+\s*)?new call$/i.test(raw) ||
    raw === 'intro-call' ||
    /^meeting notes?$/i.test(raw);
  if (isAutoName) return i18n.t('sidebar:untitledMeeting');
  const cleaned = raw.replace(/^(?:[\p{Extended_Pictographic}‍️#\s—·-])+/u, '').trim();
  return cleaned || i18n.t('sidebar:untitledMeeting');
}

function dayKey(d: Date): string {
  return `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
}

function dayLabel(d: Date, todayKey: string, yesterdayKey: string): string {
  const key = dayKey(d);
  if (key === todayKey) return i18n.t('sidebar:dateGroups.today');
  if (key === yesterdayKey) return i18n.t('sidebar:dateGroups.yesterday');
  const locale = BCP47[(i18n.language as Locale)] ?? i18n.language;
  return new Intl.DateTimeFormat(locale, {
    day: 'numeric', month: 'long', year: 'numeric',
  }).format(d);
}

function timeLabel(m: CurrentMeeting): string | null {
  if (!m.created_at) return null;
  const d = new Date(m.created_at);
  if (Number.isNaN(d.getTime())) return null;
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
}

function groupMeetingsByDate(
  meetings: CurrentMeeting[],
): { label: string; items: CurrentMeeting[] }[] {
  const now = new Date();
  const todayKey = dayKey(now);
  const yesterdayKey = dayKey(new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1));

  const buckets = new Map<string, CurrentMeeting[]>();
  const order: string[] = [];
  const push = (label: string, m: CurrentMeeting) => {
    let arr = buckets.get(label);
    if (!arr) { arr = []; buckets.set(label, arr); order.push(label); }
    arr.push(m);
  };

  for (const m of meetings) {
    const t = m.created_at ? new Date(m.created_at) : null;
    if (!t || Number.isNaN(t.getTime())) { push(i18n.t('sidebar:dateGroups.noDate'), m); continue; }
    push(dayLabel(t, todayKey, yesterdayKey), m);
  }

  return order.map((label) => ({ label, items: buckets.get(label)! }));
}

export default function Sidebar() {
  const { t } = useTranslation('sidebar');
  const router = useRouter();
  const pathname = usePathname();
  const {
    currentMeeting,
    setCurrentMeeting,
    searchTranscripts,
    searchResults,
    isSearching,
    meetings,
    setMeetings,
  } = useSidebar();
  const { isRecording } = useRecordingState();

  const [query, setQuery] = useState('');
  const [delState, setDelState] = useState<DeleteState>({ open: false, id: null, title: '' });
  const [renState, setRenState] = useState<RenameState>({ open: false, id: null, value: '' });

  const onSearch = useCallback(async (v: string) => {
    setQuery(v);
    await searchTranscripts(v);
  }, [searchTranscripts]);

  const resultsById = useMemo(() => {
    const map = new Map<string, (typeof searchResults)[number]>();
    for (const r of searchResults) map.set(r.id, r);
    return map;
  }, [searchResults]);

  const filteredMeetings = useMemo(() => {
    if (!query.trim()) return meetings;
    const q = query.toLocaleLowerCase();
    return meetings.filter(m => resultsById.has(m.id) || m.title.toLocaleLowerCase().includes(q));
  }, [meetings, query, resultsById]);

  const groupedMeetings = useMemo(
    () => groupMeetingsByDate(filteredMeetings),
    [filteredMeetings],
  );

  const openMeeting = (m: CurrentMeeting) => {
    setCurrentMeeting(m);
    router.push(`/meeting-details?id=${encodeURIComponent(m.id)}`);
  };

  const handleDelete = async () => {
    if (!delState.id) return;
    try {
      await invoke('api_delete_meeting', { meetingId: delState.id });
      setMeetings(meetings.filter(m => m.id !== delState.id));
      if (currentMeeting?.id === delState.id) {
        setCurrentMeeting({ id: 'intro-call', title: '+ New Call' });
        router.push('/');
      }
      toast.success(t('toasts.deleted'));
    } catch (e: any) {
      toast.error(t('toasts.deleteFailed'), { description: e?.message ?? String(e) });
    } finally {
      setDelState({ open: false, id: null, title: '' });
    }
  };

  const handleRename = async () => {
    if (!renState.id) return;
    const title = renState.value.trim();
    if (!title) { toast.error(t('toasts.titleEmpty')); return; }
    try {
      await invoke('api_save_meeting_title', { meetingId: renState.id, title });
      setMeetings(meetings.map(m => m.id === renState.id ? { ...m, title } : m));
      if (currentMeeting?.id === renState.id) setCurrentMeeting({ id: renState.id, title });
      toast.success(t('toasts.titleUpdated'));
    } catch (e: any) {
      toast.error(t('toasts.updateFailed'), { description: e?.message ?? String(e) });
    } finally {
      setRenState({ open: false, id: null, value: '' });
    }
  };

  useEffect(() => {
    (window as any).openSettings = () => router.push('/settings');
  }, [router]);

  const onHome = pathname === '/';
  const onSettings = pathname?.startsWith('/settings');

  return (
    <>
      <aside
        className="relative flex flex-col w-full h-screen bg-canvas border-r border-line select-none titlebar-drag"
      >
        {}
        <div className="h-9 shrink-0" />

        {}
        <div className="titlebar-no-drag px-4 pb-3">
          <Logo />
        </div>

        {}
        <div className="titlebar-no-drag px-3 pb-3 min-w-0">
          <div className="relative min-w-0">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-[15px] h-[15px] text-fg-faint" />
            <input
              value={query}
              onChange={(e) => onSearch(e.target.value)}
              placeholder={t('searchPlaceholder')}
              className="w-full min-w-0 h-10 pl-9 pr-8 text-[13.5px] rounded-[11px] bg-surface text-fg focus:bg-canvas focus:outline-none focus:ring-1 focus:ring-accent placeholder:text-fg-faint transition-colors text-ellipsis overflow-hidden"
            />
            {query && (
              <button
                type="button"
                onClick={() => onSearch('')}
                className="absolute right-1.5 top-1/2 -translate-y-1/2 w-6 h-6 rounded-md inline-flex items-center justify-center text-fg-faint hover:text-fg hover:bg-fg/[0.06]"
              >
                <X className="w-3.5 h-3.5" />
              </button>
            )}
          </div>
        </div>

        {}
        <nav className="titlebar-no-drag px-3 pb-1 flex flex-col gap-0.5">
          <NavButton
            icon={
              <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                <path d="M3 10.5 12 3l9 7.5" /><path d="M5 9.5V21h14V9.5" />
              </svg>
            }
            label={t('nav.home')}
            active={onHome}
            onClick={() => router.push('/')}
          />
          <NavButton
            icon={
              <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
                <line x1="4" y1="8" x2="20" y2="8" /><line x1="4" y1="16" x2="20" y2="16" />
                <circle cx="9" cy="8" r="2.3" fill="currentColor" stroke="none" />
                <circle cx="15" cy="16" r="2.3" fill="currentColor" stroke="none" />
              </svg>
            }
            label={t('nav.settings')}
            active={!!onSettings}
            onClick={() => router.push('/settings')}
          />
        </nav>

        {}
        <div className="titlebar-no-drag flex-1 min-h-0 overflow-y-auto custom-scrollbar pb-2 mt-1">
          <div className="flex items-center justify-between px-4 mt-2 mb-1.5">
            <span className="font-mono text-[10.5px] uppercase tracking-[0.1em] text-fg-faint">
              {t('meetingsHeader')}
            </span>
            <span className="font-mono text-[10.5px] text-fg-faint tabular-nums">{filteredMeetings.length}</span>
          </div>

          {filteredMeetings.length === 0 && (
            query ? (
              <div className="px-4 py-3 text-caption text-fg-faint">
                {isSearching ? t('search.inProgress') : t('search.noResults')}
              </div>
            ) : (
              <div className="mx-3 mt-2 px-4 py-5 rounded-[11px] border border-dashed border-line-strong text-center">
                <p className="text-[13px] leading-relaxed text-fg-faint">
                  {t('empty.noMeetings')}<br />{t('empty.startFirst')}
                </p>
              </div>
            )
          )}

          {groupedMeetings.map((group) => (
            <div key={group.label} className="mt-1">
              <div className="px-4 pt-3 pb-1.5 font-mono text-[10.5px] uppercase tracking-[0.1em] text-fg-faint select-none">
                {group.label}
              </div>
              <ul className="px-2 flex flex-col gap-px">
                {group.items.map((m) => {
                  const isActive = currentMeeting?.id === m.id;
                  const time = timeLabel(m);
                  const title = cleanMeetingTitle(m.title);
                  const result = query.trim() ? resultsById.get(m.id) : undefined;
                  const term = result?.matchTerm;
                  const snippet = result?.matchContext?.trim();
                  return (
                    <li key={m.id} className="group relative">
                      <button
                        type="button"
                        onClick={() => openMeeting(m)}
                        className={[
                          'w-full text-left flex flex-col gap-0.5 px-3 py-2 rounded-[9px] transition-[background-color,color,transform] duration-150 active:scale-[0.99]',
                          isActive ? 'bg-accent-weak' : 'hover:bg-fg/[0.05]',
                        ].join(' ')}
                        title={title}
                      >
                        <span className={[
                          'text-[13.5px] leading-tight truncate pr-12',
                          isActive ? 'text-accent-text font-medium' : 'text-fg',
                        ].join(' ')}>
                          {highlightMatch(title, term)}
                        </span>
                        {snippet && (
                          <span className="text-[11.5px] leading-snug text-fg-muted line-clamp-2 pr-2">
                            {highlightMatch(snippet, term)}
                          </span>
                        )}
                        {time && (
                          <span className="font-mono text-[11px] text-fg-faint">{time}</span>
                        )}
                      </button>
                      <span className="absolute right-2 top-1.5 hidden group-hover:flex items-center gap-0.5">
                        <button
                          type="button"
                          onClick={(e) => { e.stopPropagation(); setRenState({ open: true, id: m.id, value: m.title }); }}
                          className="w-6 h-6 inline-flex items-center justify-center rounded-md text-fg-faint hover:text-fg hover:bg-fg/[0.08]"
                          aria-label={t('actions.rename')}
                        ><Pencil className="w-3.5 h-3.5" /></button>
                        <button
                          type="button"
                          onClick={(e) => { e.stopPropagation(); setDelState({ open: true, id: m.id, title: m.title }); }}
                          className="w-6 h-6 inline-flex items-center justify-center rounded-md text-fg-faint hover:text-rec hover:bg-fg/[0.08]"
                          aria-label={t('actions.delete')}
                        ><Trash2 className="w-3.5 h-3.5" /></button>
                      </span>
                    </li>
                  );
                })}
              </ul>
            </div>
          ))}
        </div>
      </aside>

      {}
      <EmberDialog
        open={delState.open}
        onOpenChange={(o) => !o && setDelState({ open: false, id: null, title: '' })}
        onConfirm={handleDelete}
        tone="danger"
        title={t('deleteDialog.title')}
        message={t('deleteDialog.message', { title: cleanMeetingTitle(delState.title) })}
        confirmLabel={t('deleteDialog.confirm')}
        cancelLabel={t('deleteDialog.cancel')}
      />

      {}
      <Dialog open={renState.open} onOpenChange={(o) => !o && setRenState({ open: false, id: null, value: '' })}>
        <DialogContent>
          <DialogTitle>{t('renameDialog.title')}</DialogTitle>
          <VisuallyHidden>
            <DialogDescription>{t('renameDialog.description')}</DialogDescription>
          </VisuallyHidden>
          <input
            autoFocus
            value={renState.value}
            onChange={(e) => setRenState((s) => ({ ...s, value: e.target.value }))}
            onKeyDown={(e) => { if (e.key === 'Enter') handleRename(); }}
            placeholder={t('renameDialog.placeholder')}
            className="w-full h-10 px-3 text-small rounded-[11px] bg-surface border border-line focus:outline-none focus:ring-2 focus:ring-accent"
          />
          <DialogFooter className="gap-2">
            <button onClick={() => setRenState({ open: false, id: null, value: '' })}
                    className="px-3.5 h-9 rounded-[11px] text-small text-fg-muted hover:bg-fg/[0.06]">{t('renameDialog.cancel')}</button>
            <button onClick={handleRename}
                    className="px-3.5 h-9 rounded-[11px] text-small text-white bg-accent hover:opacity-90">{t('renameDialog.save')}</button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

function NavButton({ icon, label, active, onClick }: {
  icon: React.ReactNode; label: string; active?: boolean; onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={[
        'group w-full flex items-center gap-[11px] h-[38px] px-3 rounded-[10px] text-sm transition-[background-color,color,transform] duration-150 active:scale-[0.98]',
        active ? 'bg-accent-weak text-accent-text font-medium' : 'text-fg-muted hover:bg-fg/[0.05] hover:text-fg',
      ].join(' ')}
      title={label}
    >
      {}
      <span className={active ? 'text-accent-text' : 'text-fg-faint group-hover:text-fg'}>{icon}</span>
      <span className="truncate">{label}</span>
    </button>
  );
}
