export interface Message {
  id: string;
  content: string;
  timestamp: string;
}

export interface Transcript {
  id: string;
  text: string;
  timestamp: string;
  sequence_id?: number;
  chunk_start_time?: number;
  is_partial?: boolean;
  confidence?: number;
  audio_start_time?: number;
  audio_end_time?: number;
  duration?: number;
}

export interface TranscriptUpdate {
  text: string;
  timestamp: string;
  source: string;
  sequence_id: number;
  chunk_start_time: number;
  is_partial: boolean;
  confidence: number;
  audio_start_time: number;
  audio_end_time: number;
  duration: number;
}

export interface Block {
  id: string;
  type: string;
  content: string;
  color: string;
}

export interface Section {
  title: string;
  blocks: Block[];
}

export interface Summary {
  [key: string]: Section;
}

export interface ApiResponse {
  message: string;
  num_chunks: number;
  data: any[];
}

export interface SummaryResponse {
  status: string;
  summary: Summary;
  raw_summary?: string;
  usage?: {
    prompt_tokens: number;
    completion_tokens: number;
    total_tokens: number;
  };
}

export type SummaryFormat = 'legacy' | 'markdown' | 'blocknote';

export interface BlockNoteBlock {
  id: string;
  type: string;
  props?: Record<string, any>;
  content?: any[];
  children?: BlockNoteBlock[];
}

export interface SummaryDataResponse {
  markdown?: string;
  summary_json?: BlockNoteBlock[];
  MeetingName?: string;
  _section_order?: string[];
  [key: string]: any;
}

export interface MeetingMetadata {
  id: string;
  title: string;
  created_at: string;
  updated_at: string;
  folder_path?: string;
}

export interface PaginatedTranscriptsResponse {
  transcripts: Transcript[];
  total_count: number;
  has_more: boolean;
}

export interface TranscriptSegmentData {
  id: string;
  timestamp: number;
  endTime?: number;
  text: string;
  confidence?: number;
}
