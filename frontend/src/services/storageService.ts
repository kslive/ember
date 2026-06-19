
import { invoke } from '@tauri-apps/api/core';
import { Transcript } from '@/types';

export interface SaveMeetingRequest {
  meetingTitle: string;
  transcripts: Transcript[];
  folderPath: string | null;
}

export interface SaveMeetingResponse {
  meeting_id: string;
}

export interface Meeting {
  id: string;
  title: string;
  [key: string]: any;
}

export class StorageService {
  async saveMeeting(
    meetingTitle: string,
    transcripts: Transcript[],
    folderPath: string | null
  ): Promise<SaveMeetingResponse> {
    return invoke<SaveMeetingResponse>('api_save_transcript', {
      meetingTitle,
      transcripts,
      folderPath,
    });
  }

  async getMeeting(meetingId: string): Promise<Meeting> {
    return invoke<Meeting>('api_get_meeting', { meetingId });
  }

  async getMeetings(): Promise<Meeting[]> {
    return invoke<Meeting[]>('api_get_meetings');
  }
}

export const storageService = new StorageService();
