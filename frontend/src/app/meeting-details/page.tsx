"use client"
import { useSidebar } from "@/components/Sidebar/SidebarProvider";
import { useState, useEffect, useCallback, Suspense } from "react";
import { Transcript, Summary } from "@/types";
import PageContent from "./page-content";
import { useRouter, useSearchParams } from "next/navigation";
import Analytics from "@/lib/analytics";
import { invoke } from "@tauri-apps/api/core";
import { LoaderIcon } from "lucide-react";
import { useConfig } from "@/contexts/ConfigContext";
import { usePaginatedTranscripts } from "@/hooks/usePaginatedTranscripts";

interface MeetingDetailsResponse {
  id: string;
  title: string;
  created_at: string;
  updated_at: string;
  transcripts: Transcript[];
  folder_path?: string;
}

function MeetingDetailsContent() {
  const searchParams = useSearchParams();
  const meetingId = searchParams.get('id');
  const source = searchParams.get('source');
  const { setCurrentMeeting, refetchMeetings, stopSummaryPolling } = useSidebar();
  const { isAutoSummary } = useConfig();
  const router = useRouter();
  const [meetingDetails, setMeetingDetails] = useState<MeetingDetailsResponse | null>(null);
  const [meetingSummary, setMeetingSummary] = useState<Summary | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [shouldAutoGenerate, setShouldAutoGenerate] = useState<boolean>(false);
  const [hasCheckedAutoGen, setHasCheckedAutoGen] = useState<boolean>(false);

  const {
    metadata,
    segments,
    transcripts,
    isLoading: isLoadingTranscripts,
    isLoadingMore,
    hasMore,
    totalCount,
    loadedCount,
    loadMore,
    refetch,
    error: transcriptError,
  } = usePaginatedTranscripts({ meetingId: meetingId || '' });

  const checkForGemmaModel = useCallback(async (): Promise<boolean> => {
    try {
      const models = await invoke('get_ollama_models', { endpoint: null }) as any[];
      const hasGemma = models.some((m: any) => m.name === 'gemma3:1b');
      console.log('🔍 Checked for gemma3:1b:', hasGemma);
      return hasGemma;
    } catch (error) {
      console.error('❌ Failed to check Ollama models:', error);
      return false;
    }
  }, []);

  const setupAutoGeneration = useCallback(async () => {
    if (hasCheckedAutoGen) return;

    if (source !== 'recording') {
      console.log('Not from recording navigation, skipping auto-generation');
      setHasCheckedAutoGen(true);
      return;
    }

    if (!isAutoSummary) {
      console.log('Auto-summary is disabled in settings');
      setHasCheckedAutoGen(true);
      return;
    }

    try {
      const currentConfig = await invoke('api_get_model_config') as any;

      if (currentConfig && currentConfig.model) {
        console.log('Using existing model from DB:', currentConfig.model);
        setShouldAutoGenerate(true);
        setHasCheckedAutoGen(true);
        return;
      }

      const hasGemma = await checkForGemmaModel();

      if (hasGemma) {
        console.log('💾 DB empty, using gemma3:1b as initial default');

        await invoke('api_save_model_config', {
          provider: 'ollama',
          model: '',
          whisperModel: 'large-v3',
          apiKey: null,
          ollamaEndpoint: null,
        });

        setShouldAutoGenerate(true);
      } else {
        console.log('⚠️ No model configured and gemma3:1b not found');
      }
    } catch (error) {
      console.error('❌ Failed to setup auto-generation:', error);
    }

    setHasCheckedAutoGen(true);
  }, [hasCheckedAutoGen, checkForGemmaModel, source, isAutoSummary]);

  useEffect(() => {
    if (metadata && (!meetingId || meetingId === 'intro-call')) {
      return;
    }

    if (metadata) {
      console.log('Meeting metadata loaded:', metadata);

      setMeetingDetails({
        id: metadata.id,
        title: metadata.title,
        created_at: metadata.created_at,
        updated_at: metadata.updated_at,
        transcripts: transcripts,
        folder_path: metadata.folder_path,
      });

      setCurrentMeeting({ id: metadata.id, title: metadata.title });
    }
  }, [metadata, transcripts, meetingId, setCurrentMeeting]);

  useEffect(() => {
    if (transcriptError) {
      console.error('Error loading transcripts:', transcriptError);
      setError(transcriptError);
    }
  }, [transcriptError]);

  const fetchMeetingDetails = useCallback(async () => {
    if (!meetingId || meetingId === 'intro-call') {
      return;
    }

    console.log('fetchMeetingDetails called - pagination hook will handle refetch');
  }, [meetingId]);

  useEffect(() => {
    setMeetingDetails(null);
    setMeetingSummary(null);
    setError(null);
    setIsLoading(true);
    setHasCheckedAutoGen(false);
    setShouldAutoGenerate(false);
  }, [meetingId]);

  useEffect(() => {
    return () => {
      if (meetingId) {
        console.log('Cleaning up: Stopping summary polling for meeting:', meetingId);
        stopSummaryPolling(meetingId);
      }
    };
  }, [meetingId, stopSummaryPolling]);

  useEffect(() => {
    console.log('MeetingDetails useEffect triggered - meetingId:', meetingId);

    if (!meetingId || meetingId === 'intro-call') {
      console.warn('No valid meeting ID in URL - meetingId:', meetingId);
      setError("No meeting selected");
      setIsLoading(false);
      Analytics.trackPageView('meeting_details');
      return;
    }

    console.log('Valid meeting ID found, fetching details for:', meetingId);

    setMeetingDetails(null);
    setMeetingSummary(null);
    setError(null);
    setIsLoading(true);

    const fetchMeetingSummary = async () => {
      try {
        const summary = await invoke('api_get_summary', {
          meetingId: meetingId,
        }) as any;

        console.log('FETCH SUMMARY: Raw response:', summary);

        if (summary.status === 'idle' || (!summary.data && summary.status === 'error')) {
          console.warn('Meeting summary not found or no summary generated yet:', summary.error || 'idle');
          setMeetingSummary(null);
          return;
        }

        const liveStatus = String(summary.status || '').toLowerCase();
        if (liveStatus === 'processing' || liveStatus === 'pending'
            || liveStatus === 'summarizing' || liveStatus === 'regenerating') {
          console.log('Summary generation in progress — not showing stale data');
          setMeetingSummary(null);
          return;
        }

        const summaryData = summary.data || {};

        let parsedData = summaryData;
        if (typeof summaryData === 'string') {
          try {
            parsedData = JSON.parse(summaryData);
          } catch (e) {
            parsedData = {};
          }
        }

        console.log('🔍 FETCH SUMMARY: Parsed data:', parsedData);

        if (parsedData.summary_json) {
          setMeetingSummary(parsedData as any);
          return;
        }

        if (parsedData.markdown) {
          setMeetingSummary(parsedData as any);
          return;
        }

        console.log('LEGACY FORMAT: Detected legacy format, applying section formatting');

        const { MeetingName, _section_order, ...restSummaryData } = parsedData;

        const formattedSummary: Summary = {};

        const sectionKeys = _section_order || Object.keys(restSummaryData);

        console.log('LEGACY FORMAT: Processing sections:', sectionKeys);

        for (const key of sectionKeys) {
          try {
            const section = restSummaryData[key];
            if (section &&
              typeof section === 'object' &&
              'title' in section &&
              'blocks' in section) {
              const typedSection = section as { title?: string; blocks?: any[] };

              if (Array.isArray(typedSection.blocks)) {
                formattedSummary[key] = {
                  title: typedSection.title || key,
                  blocks: typedSection.blocks.map((block: any) => ({
                    ...block,
                    color: 'default',
                    content: block?.content?.trim() || ''
                  }))
                };
              } else {
                console.warn(`LEGACY FORMAT: Section ${key} has invalid blocks:`, typedSection.blocks);
                formattedSummary[key] = {
                  title: typedSection.title || key,
                  blocks: []
                };
              }
            } else {
              console.warn(`LEGACY FORMAT: Skipping invalid section ${key}:`, section);
            }
          } catch (error) {
            console.warn(`LEGACY FORMAT: Error processing section ${key}:`, error);
          }
        }

        console.log('LEGACY FORMAT: Formatted summary:', formattedSummary);
        setMeetingSummary(formattedSummary);
      } catch (error) {
        console.error('FETCH SUMMARY: Error fetching meeting summary:', error);
        setMeetingSummary(null);
      }
    };

    const loadData = async () => {
      try {
        await fetchMeetingSummary();
      } finally {
        setIsLoading(false);
      }
    };

    loadData();
  }, [meetingId]);

  useEffect(() => {
    const checkAutoGen = async () => {
      if (
        meetingDetails &&
        meetingSummary === null &&
        meetingDetails.transcripts &&
        meetingDetails.transcripts.length > 0 &&
        !hasCheckedAutoGen
      ) {
        console.log('No summary found, checking for auto-generation...');
        await setupAutoGeneration();
      }
    };

    checkAutoGen();
  }, [meetingDetails, meetingSummary, hasCheckedAutoGen, setupAutoGeneration]);

  if (error) {
    return (
      <div className="flex items-center justify-center h-screen">
        <div className="text-center">
          <p className="text-red-500 mb-4">{error}</p>
          <button
            onClick={() => router.push('/')}
            className="px-4 py-2 bg-accent text-white rounded hover:bg-accent"
          >
            Go Back
          </button>
        </div>
      </div>
    );
  }

  if ((isLoading || isLoadingTranscripts) || !meetingDetails) {
    return <div className="flex items-center justify-center h-screen">
      <LoaderIcon className="animate-spin size-6 " />
    </div>;
  }

  return <PageContent
    meeting={meetingDetails}
    summaryData={meetingSummary}
    shouldAutoGenerate={shouldAutoGenerate}
    onAutoGenerateComplete={() => setShouldAutoGenerate(false)}
    onMeetingUpdated={async () => {
      await fetchMeetingDetails();
      await refetchMeetings();
    }}
    onRefetchTranscripts={refetch}
    segments={segments}
    hasMore={hasMore}
    isLoadingMore={isLoadingMore}
    totalCount={totalCount}
    loadedCount={loadedCount}
    onLoadMore={loadMore}
  />;
}

export default function MeetingDetails() {
  return (
    <Suspense fallback={
      <div className="flex items-center justify-center h-screen">
        <LoaderIcon className="animate-spin size-6" />
      </div>
    }>
      <MeetingDetailsContent />
    </Suspense>
  );
}
