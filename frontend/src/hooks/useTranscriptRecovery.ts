
import { useState, useCallback } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { indexedDBService, MeetingMetadata, StoredTranscript } from '@/services/indexedDBService';
import { storageService } from '@/services/storageService';

interface AudioRecoveryStatus {
  status: string;
  chunk_count: number;
  estimated_duration_seconds: number;
  audio_file_path?: string;
  message: string;
}

export interface UseTranscriptRecoveryReturn {
  recoverableMeetings: MeetingMetadata[];
  isLoading: boolean;
  isRecovering: boolean;
  checkForRecoverableTranscripts: () => Promise<void>;
  recoverMeeting: (meetingId: string) => Promise<{ success: boolean; audioRecoveryStatus?: AudioRecoveryStatus | null; meetingId?: string }>;
  loadMeetingTranscripts: (meetingId: string) => Promise<StoredTranscript[]>;
  deleteRecoverableMeeting: (meetingId: string) => Promise<void>;
}

export function useTranscriptRecovery(): UseTranscriptRecoveryReturn {
  const [recoverableMeetings, setRecoverableMeetings] = useState<MeetingMetadata[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [isRecovering, setIsRecovering] = useState(false);

  const checkForRecoverableTranscripts = useCallback(async () => {
    setIsLoading(true);
    try {
      const meetings = await indexedDBService.getAllMeetings();

      const cutoffTime = Date.now() - (7 * 24 * 60 * 60 * 1000);
      const secondsAgo = Date.now() - (15 * 1000);

      const recentMeetings = meetings.filter(m => {
        const isWithinRetention = m.lastUpdated > cutoffTime;
        const isOldEnough = m.lastUpdated < secondsAgo;
        return isWithinRetention && isOldEnough;
      });

      const meetingsWithAudioStatus = await Promise.all(
        recentMeetings.map(async (meeting) => {
          if (meeting.folderPath) {
            try {
              const hasAudio = await invoke<boolean>('has_audio_checkpoints', {
                meetingFolder: meeting.folderPath
              });

              return {
                ...meeting,
                folderPath: hasAudio ? meeting.folderPath : undefined
              };
            } catch (error) {
              console.warn('Failed to check audio for meeting:', error);
              return { ...meeting, folderPath: undefined };
            }
          }
          return meeting;
        })
      );

      setRecoverableMeetings(meetingsWithAudioStatus);
    } catch (error) {
      console.error('Failed to check for recoverable transcripts:', error);
      setRecoverableMeetings([]);
    } finally {
      setIsLoading(false);
    }
  }, []);

  const loadMeetingTranscripts = useCallback(async (meetingId: string): Promise<StoredTranscript[]> => {
    try {
      const transcripts = await indexedDBService.getTranscripts(meetingId);
      transcripts.sort((a, b) => (a.sequenceId || 0) - (b.sequenceId || 0));
      return transcripts;
    } catch (error) {
      console.error('Failed to load meeting transcripts:', error);
      return [];
    }
  }, []);

  const recoverMeeting = useCallback(async (meetingId: string): Promise<{ success: boolean; audioRecoveryStatus?: AudioRecoveryStatus | null; meetingId?: string }> => {
    setIsRecovering(true);
    try {
      const metadata = await indexedDBService.getMeetingMetadata(meetingId);
      if (!metadata) {
        throw new Error('Meeting metadata not found');
      }

      const transcripts = await loadMeetingTranscripts(meetingId);
      if (transcripts.length === 0) {
        throw new Error('No transcripts found for this meeting');
      }

      let folderPath = metadata.folderPath;

      if (!folderPath) {
        try {
          folderPath = await invoke<string>('get_meeting_folder_path');
        } catch (error) {
          folderPath = undefined;
        }
      }

      let audioRecoveryStatus: AudioRecoveryStatus | null = null;
      if (folderPath) {
        try {
          audioRecoveryStatus = await invoke<AudioRecoveryStatus>(
            'recover_audio_from_checkpoints',
            { meetingFolder: folderPath, sampleRate: 48000 }
          );
        } catch (error) {
          console.error('Audio recovery failed:', error);
          audioRecoveryStatus = {
            status: 'failed',
            chunk_count: 0,
            estimated_duration_seconds: 0,
            message: error instanceof Error ? error.message : 'Unknown error'
          };
        }
      } else {
        audioRecoveryStatus = {
          status: 'none',
          chunk_count: 0,
          estimated_duration_seconds: 0,
          message: 'No folder path available'
        };
      }

      const formattedTranscripts = transcripts.map((t, index) => ({
        id: t.id?.toString() || `${Date.now()}-${index}`,
        text: t.text,
        timestamp: t.timestamp,
        sequence_id: t.sequenceId || index,
        chunk_start_time: (t as any).chunk_start_time,
        is_partial: (t as any).is_partial || false,
        confidence: t.confidence,
        audio_start_time: (t as any).audio_start_time,
        audio_end_time: (t as any).audio_end_time,
        duration: (t as any).duration,
      }));

      const saveResponse = await storageService.saveMeeting(
        metadata.title,
        formattedTranscripts,
        folderPath ?? null
      );

      const savedMeetingId = saveResponse.meeting_id;

      await indexedDBService.markMeetingSaved(meetingId);

      if (folderPath) {
        try {
          await invoke('cleanup_checkpoints', { meetingFolder: folderPath });
        } catch (error) {
          console.warn('Checkpoint cleanup failed (non-fatal):', error);
        }
      }

      setRecoverableMeetings(prev => prev.filter(m => m.meetingId !== meetingId));

      return {
        success: true,
        audioRecoveryStatus,
        meetingId: savedMeetingId
      };
    } catch (error) {
      console.error('Failed to recover meeting:', error);
      throw error;
    } finally {
      setIsRecovering(false);
    }
  }, [loadMeetingTranscripts]);

  const deleteRecoverableMeeting = useCallback(async (meetingId: string): Promise<void> => {
    try {
      await indexedDBService.deleteMeeting(meetingId);
      setRecoverableMeetings(prev => prev.filter(m => m.meetingId !== meetingId));
    } catch (error) {
      console.error('Failed to delete meeting:', error);
      throw error;
    }
  }, []);

  return {
    recoverableMeetings,
    isLoading,
    isRecovering,
    checkForRecoverableTranscripts,
    recoverMeeting,
    loadMeetingTranscripts,
    deleteRecoverableMeeting
  };
}
