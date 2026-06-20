import { invoke } from '@tauri-apps/api/core';
import { load } from '@tauri-apps/plugin-store';
import i18n from '@/i18n';

export function pad2(n: number): string {
  return n.toString().padStart(2, '0');
}

export function summaryFileName(createdAt?: string): string {
  const d = createdAt ? new Date(createdAt) : new Date();
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}-${pad2(d.getHours())}-${pad2(d.getMinutes())}.md`;
}

export function sanitizeFileName(s: string): string {
  return s.replace(/[\\/:*?"<>|]/g, '-').replace(/\s+/g, ' ').trim().slice(0, 120);
}

export function summaryFileNameFor(createdAt: string | undefined, body: string): string {
  const h1 = extractTopicFromBody(body);
  if (h1) return `${sanitizeFileName(h1)}.md`;
  return summaryFileName(createdAt);
}

export function cleanLeakedMarkdown(md: string): string {
  return md
    .replace(/<\/?template[^>]*>/gi, '')
    .replace(/\[\/?temp_chunk\]/gi, '')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

export function stripLeadingFrontmatter(md: string): string {
  if (!md.startsWith('---')) return md;
  const m = md.match(/^---\s*\n[\s\S]*?\n---\s*\n?/);
  if (m) return md.slice(m[0].length).replace(/^\s+/, '');
  return md;
}

export function extractTopicFromBody(md: string): string | null {
  const m = md.match(/^#\s+(.+?)\s*$/m);
  if (!m) return null;
  const t = m[1].trim();
  if (/Встреча\s+—\s+\d{4}-\d{2}-\d{2}\s+\d{1,2}:\d{2}/.test(t)) return null;
  return t.replace(/^[#📞\s]+/, '').slice(0, 140);
}

export function buildFrontmatter(meeting: any, body: string): string {
  const d = meeting?.created_at ? new Date(meeting.created_at) : new Date();
  const date = `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
  const time = `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
  const topic = extractTopicFromBody(body) ?? '';
  return [
    '---',
    `date: ${date}`,
    `time: "${time}"`,
    `device: "${i18n.t('common:summaryExport.device')}"`,
    `type: "${i18n.t('common:summaryExport.type')}"`,
    `topic: "${topic.replace(/"/g, '\\"')}"`,
    `participants: []`,
    `tags: [meeting]`,
    '---',
    '',
  ].join('\n');
}

export function pickSummaryMarkdown(data: any): string {
  if (!data) return '';
  if (typeof data.markdown === 'string') return data.markdown;
  if (typeof data.raw_summary === 'string') return data.raw_summary;
  return '';
}

export async function getSummaryFolder(): Promise<string | null> {
  const store = await load('preferences.json');
  return (await store.get('save_summary_folder')) as string | null;
}

export async function exportSummaryToMd(meeting: any, markdown: string): Promise<string | null> {
  const folder = await getSummaryFolder();
  if (!folder) return null;
  const body = stripLeadingFrontmatter(cleanLeakedMarkdown(markdown || ''));
  if (!body.trim()) return null;
  const content = buildFrontmatter(meeting, body) + body;
  const fileName = summaryFileNameFor(meeting?.created_at, body);
  const path = await invoke<string>('save_summary_md', { folder, fileName, content });
  return path;
}
