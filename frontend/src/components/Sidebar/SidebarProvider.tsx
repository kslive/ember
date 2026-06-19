'use client';

import React, { createContext, useContext, useState, useEffect } from 'react';
import { usePathname, useRouter } from 'next/navigation';
import Analytics from '@/lib/analytics';
import { invoke } from '@tauri-apps/api/core';
import { useRecordingState } from '@/contexts/RecordingStateContext';

interface SidebarItem {
  id: string;
  title: string;
  type: 'folder' | 'file';
  children?: SidebarItem[];
}

export interface CurrentMeeting {
  id: string;
  title: string;
  created_at?: string;
}

interface TranscriptSearchResult {
  id: string;
  title: string;
  matchContext: string;
  timestamp: string;
  matchTerm?: string;
};

interface MeetingSearchContent {
  transcript: string;
  summary: string;
}

function extractSummaryText(data: any): string {
  if (!data) return '';
  let parsed: any = data;
  if (typeof parsed === 'string') {
    try { parsed = JSON.parse(parsed); } catch { return parsed; }
  }
  if (typeof parsed !== 'object') return String(parsed ?? '');

  const out: string[] = [];
  const visit = (node: any) => {
    if (node == null) return;
    if (typeof node === 'string') { out.push(node); return; }
    if (typeof node === 'number' || typeof node === 'boolean') return;
    if (Array.isArray(node)) { node.forEach(visit); return; }
    if (typeof node === 'object') {
      for (const v of Object.values(node)) visit(v);
    }
  };

  if (typeof parsed.markdown === 'string') out.push(parsed.markdown);
  if (parsed.summary_json) visit(parsed.summary_json);
  visit(parsed);

  return out.join(' ');
}

function buildSnippet(source: string, needle: string): string {
  const text = source.replace(/\s+/g, ' ').trim();
  if (!text) return '';
  const idx = text.toLocaleLowerCase().indexOf(needle);
  if (idx === -1) return text.slice(0, 160);

  const pad = 60;
  const start = Math.max(0, idx - pad);
  const end = Math.min(text.length, idx + needle.length + pad);
  let snippet = text.slice(start, end);
  if (start > 0) snippet = `…${snippet}`;
  if (end < text.length) snippet = `${snippet}…`;
  return snippet;
}

interface SidebarContextType {
  currentMeeting: CurrentMeeting | null;
  setCurrentMeeting: (meeting: CurrentMeeting | null) => void;
  sidebarItems: SidebarItem[];
  isCollapsed: boolean;
  toggleCollapse: () => void;
  meetings: CurrentMeeting[];
  setMeetings: (meetings: CurrentMeeting[]) => void;
  isMeetingActive: boolean;
  setIsMeetingActive: (active: boolean) => void;
  handleRecordingToggle: () => void;
  searchTranscripts: (query: string) => Promise<void>;
  searchResults: TranscriptSearchResult[];
  isSearching: boolean;
  setServerAddress: (address: string) => void;
  serverAddress: string;
  transcriptServerAddress: string;
  setTranscriptServerAddress: (address: string) => void;
  activeSummaryPolls: Map<string, NodeJS.Timeout>;
  startSummaryPolling: (meetingId: string, processId: string, onUpdate: (result: any) => void) => void;
  stopSummaryPolling: (meetingId: string) => void;
  refetchMeetings: () => Promise<void>;

}

const SidebarContext = createContext<SidebarContextType | null>(null);

export const useSidebar = () => {
  const context = useContext(SidebarContext);
  if (!context) {
    throw new Error('useSidebar must be used within a SidebarProvider');
  }
  return context;
};

export function SidebarProvider({ children }: { children: React.ReactNode }) {
  const [currentMeeting, setCurrentMeeting] = useState<CurrentMeeting | null>({ id: 'intro-call', title: '+ New Call' });
  const [isCollapsed, setIsCollapsed] = useState(true);
  const [meetings, setMeetings] = useState<CurrentMeeting[]>([]);
  const [sidebarItems, setSidebarItems] = useState<SidebarItem[]>([]);
  const [isMeetingActive, setIsMeetingActive] = useState(false);
  const [searchResults, setSearchResults] = useState<any[]>([]);
  const [isSearching, setIsSearching] = useState(false);
  const [serverAddress, setServerAddress] = useState('');
  const [transcriptServerAddress, setTranscriptServerAddress] = useState('');
  const [activeSummaryPolls, setActiveSummaryPolls] = useState<Map<string, NodeJS.Timeout>>(new Map());

  const searchContentCache = React.useRef<Map<string, MeetingSearchContent>>(new Map());
  const searchToken = React.useRef(0);

  const { isRecording } = useRecordingState();

  const pathname = usePathname();
  const router = useRouter();

  const fetchMeetings = React.useCallback(async () => {
    if (serverAddress) {
      try {
        const meetings = await invoke('api_get_meetings') as Array<{ id: string, title: string, created_at?: string }>;
        const transformedMeetings = meetings.map((meeting: any) => ({
          id: meeting.id,
          title: meeting.title,
          created_at: meeting.created_at,
        }));
        setMeetings(transformedMeetings);
        Analytics.trackBackendConnection(true);
      } catch (error) {
        console.error('Error fetching meetings:', error);
        setMeetings([]);
        Analytics.trackBackendConnection(false, error instanceof Error ? error.message : 'Unknown error');
      }
    }
  }, [serverAddress]);

  useEffect(() => {
    fetchMeetings();
  }, [serverAddress, fetchMeetings]);

  useEffect(() => {
    const fetchSettings = async () => {
      setServerAddress('http://localhost:5167');
      setTranscriptServerAddress('http://127.0.0.1:8178/stream');
    };
    fetchSettings();
  }, []);

  const baseItems: SidebarItem[] = [
    {
      id: 'meetings',
      title: 'Meeting Notes',
      type: 'folder' as const,
      children: [
        ...meetings.map(meeting => ({ id: meeting.id, title: meeting.title, type: 'file' as const }))
      ]
    },
  ];

  const toggleCollapse = () => {
    setIsCollapsed(!isCollapsed);
  };

  useEffect(() => {
    if (pathname === '/') {
      setCurrentMeeting({ id: 'intro-call', title: '+ New Call' });
    }
    setSidebarItems(baseItems);
  }, [pathname]);

  useEffect(() => {
    setSidebarItems(baseItems);
    searchContentCache.current.clear();
  }, [meetings]);

  const handleRecordingToggle = () => {
    if (!isRecording) {
      if (pathname === '/') {
        console.log('Triggering recording from sidebar (already on home page)');
        window.dispatchEvent(new CustomEvent('start-recording-from-sidebar'));
      } else {
        console.log('Navigating to home page with auto-start flag');
        sessionStorage.setItem('autoStartRecording', 'true');
        router.push('/');
      }

      Analytics.trackButtonClick('start_recording', 'sidebar');
    }
  };

  const loadMeetingSearchContent = async (
    meetingId: string,
  ): Promise<MeetingSearchContent> => {
    const cached = searchContentCache.current.get(meetingId);
    if (cached) return cached;

    let transcript = '';
    let summary = '';

    try {
      const detail = await invoke('api_get_meeting', { meetingId }) as
        { transcripts?: Array<{ text?: string }> } | null;
      if (detail?.transcripts?.length) {
        transcript = detail.transcripts.map((t) => t?.text || '').join(' ');
      }
    } catch (error) {
      console.error(`Search: failed to load transcript for ${meetingId}:`, error);
    }

    try {
      const summaryRes = await invoke('api_get_summary', { meetingId }) as
        { data?: any } | null;
      if (summaryRes?.data) summary = extractSummaryText(summaryRes.data);
    } catch (error) {
      console.error(`Search: failed to load summary for ${meetingId}:`, error);
    }

    const content: MeetingSearchContent = { transcript, summary };
    searchContentCache.current.set(meetingId, content);
    return content;
  };

  const searchTranscripts = async (query: string) => {
    const q = query.trim();
    const token = ++searchToken.current;

    if (!q) {
      setSearchResults([]);
      setIsSearching(false);
      return;
    }

    const needle = q.toLocaleLowerCase();
    setIsSearching(true);

    try {
      const snapshot = meetings;
      const results: TranscriptSearchResult[] = [];

      for (const meeting of snapshot) {
        if (token !== searchToken.current) return;

        const title = meeting.title || '';
        const titleHit = title.toLocaleLowerCase().includes(needle);

        let content: MeetingSearchContent = { transcript: '', summary: '' };
        try {
          content = await loadMeetingSearchContent(meeting.id);
        } catch {
        }

        const transcriptHit = content.transcript.toLocaleLowerCase().includes(needle);
        const summaryHit = content.summary.toLocaleLowerCase().includes(needle);

        if (!titleHit && !transcriptHit && !summaryHit) continue;

        const source = transcriptHit
          ? content.transcript
          : summaryHit
            ? content.summary
            : title;
        const matchContext = titleHit && !transcriptHit && !summaryHit
          ? ''
          : buildSnippet(source, needle);

        results.push({
          id: meeting.id,
          title,
          matchContext,
          timestamp: meeting.created_at || '',
          matchTerm: q,
        });
      }

      if (token !== searchToken.current) return;
      setSearchResults(results);
    } catch (error) {
      console.error('Error searching transcripts:', error);
      if (token === searchToken.current) setSearchResults([]);
    } finally {
      if (token === searchToken.current) setIsSearching(false);
    }
  };

  const startSummaryPolling = React.useCallback((
    meetingId: string,
    processId: string,
    onUpdate: (result: any) => void
  ) => {
    if (activeSummaryPolls.has(meetingId)) {
      clearInterval(activeSummaryPolls.get(meetingId)!);
    }

    console.log(`📊 Starting polling for meeting ${meetingId}, process ${processId}`);

    let pollCount = 0;
    const MAX_POLLS = 200;

    const pollInterval = setInterval(async () => {
      pollCount++;

      if (pollCount >= MAX_POLLS) {
        console.warn(`⏱️ Polling timeout for ${meetingId} after ${MAX_POLLS} iterations`);
        clearInterval(pollInterval);
        setActiveSummaryPolls(prev => {
          const next = new Map(prev);
          next.delete(meetingId);
          return next;
        });
        onUpdate({
          status: 'error',
          error: 'Summary generation timed out after 15 minutes. Please try again or check your model configuration.'
        });
        return;
      }
      try {
        const result = await invoke('api_get_summary', {
          meetingId: meetingId,
        }) as any;

        console.log(`📊 Polling update for ${meetingId}:`, result.status);

        onUpdate(result);

        if (result.status === 'completed' || result.status === 'error' || result.status === 'failed' || result.status === 'cancelled') {
          console.log(`Polling completed for ${meetingId}, status: ${result.status}`);
          clearInterval(pollInterval);
          setActiveSummaryPolls(prev => {
            const next = new Map(prev);
            next.delete(meetingId);
            return next;
          });
        } else if (result.status === 'idle' && pollCount > 1) {
          console.log(`Process completed or not found for ${meetingId}, stopping poll`);
          clearInterval(pollInterval);
          setActiveSummaryPolls(prev => {
            const next = new Map(prev);
            next.delete(meetingId);
            return next;
          });
        }
      } catch (error) {
        console.error(`Polling error for ${meetingId}:`, error);
        onUpdate({
          status: 'error',
          error: error instanceof Error ? error.message : 'Unknown error'
        });
        clearInterval(pollInterval);
        setActiveSummaryPolls(prev => {
          const next = new Map(prev);
          next.delete(meetingId);
          return next;
        });
      }
    }, 5000);

    setActiveSummaryPolls(prev => new Map(prev).set(meetingId, pollInterval));
  }, [activeSummaryPolls]);

  const stopSummaryPolling = React.useCallback((meetingId: string) => {
    const pollInterval = activeSummaryPolls.get(meetingId);
    if (pollInterval) {
      console.log(`⏹️ Stopping polling for meeting ${meetingId}`);
      clearInterval(pollInterval);
      setActiveSummaryPolls(prev => {
        const next = new Map(prev);
        next.delete(meetingId);
        return next;
      });
    }
  }, [activeSummaryPolls]);

  useEffect(() => {
    return () => {
      console.log('🧹 Cleaning up all summary polling intervals');
      activeSummaryPolls.forEach(interval => clearInterval(interval));
    };
  }, [activeSummaryPolls]);

  return (
    <SidebarContext.Provider value={{
      currentMeeting,
      setCurrentMeeting,
      sidebarItems,
      isCollapsed,
      toggleCollapse,
      meetings,
      setMeetings,
      isMeetingActive,
      setIsMeetingActive,
      handleRecordingToggle,
      searchTranscripts,
      searchResults,
      isSearching,
      setServerAddress,
      serverAddress,
      transcriptServerAddress,
      setTranscriptServerAddress,
      activeSummaryPolls,
      startSummaryPolling,
      stopSummaryPolling,
      refetchMeetings: fetchMeetings,

    }}>
      {children}
    </SidebarContext.Provider>
  );
}
