import { useState, useEffect, useRef } from 'react';
import { TranscriptSegmentData } from '@/types';

const INTERVAL_MS = 15;
const DURATION_MS = 800;
const INITIAL_CHARS = 5;

interface StreamingSegment {
  id: string;
  fullText: string;
  visibleText: string;
}

export function useTranscriptStreaming(
  segments: TranscriptSegmentData[],
  isRecording: boolean,
  enableStreaming: boolean
) {
  const [streamingSegment, setStreamingSegment] = useState<StreamingSegment | null>(null);
  const lastSegmentIdRef = useRef<string | null>(null);
  const streamingIntervalRef = useRef<NodeJS.Timeout | null>(null);

  useEffect(() => {
    if (!isRecording || !enableStreaming || segments.length === 0) {
      if (streamingIntervalRef.current) {
        clearInterval(streamingIntervalRef.current);
        streamingIntervalRef.current = null;
      }
      setStreamingSegment(null);
      lastSegmentIdRef.current = null;
      return;
    }

    const latestSegment = segments[segments.length - 1];

    if (latestSegment.id !== lastSegmentIdRef.current) {
      lastSegmentIdRef.current = latestSegment.id;

      if (streamingIntervalRef.current) {
        clearInterval(streamingIntervalRef.current);
        streamingIntervalRef.current = null;
      }

      const fullText = latestSegment.text;

      const initialText = fullText.substring(0, Math.min(INITIAL_CHARS, fullText.length));

      setStreamingSegment({
        id: latestSegment.id,
        fullText,
        visibleText: initialText,
      });

      if (fullText.length <= INITIAL_CHARS) {
        return;
      }

      const totalTicks = Math.floor(DURATION_MS / INTERVAL_MS);
      const remainingChars = fullText.length - INITIAL_CHARS;
      const charsPerTick = Math.max(2, Math.ceil(remainingChars / totalTicks));

      let charIndex = INITIAL_CHARS;

      streamingIntervalRef.current = setInterval(() => {
        charIndex += charsPerTick;

        if (charIndex >= fullText.length) {
          setStreamingSegment({
            id: latestSegment.id,
            fullText,
            visibleText: fullText,
          });

          if (streamingIntervalRef.current) {
            clearInterval(streamingIntervalRef.current);
            streamingIntervalRef.current = null;
          }
        } else {
          setStreamingSegment(prev => prev ? {
            ...prev,
            visibleText: fullText.substring(0, charIndex),
          } : null);
        }
      }, INTERVAL_MS);
    }

    return () => {
      if (streamingIntervalRef.current) {
        clearInterval(streamingIntervalRef.current);
        streamingIntervalRef.current = null;
      }
    };
  }, [segments, isRecording, enableStreaming]);

  const getDisplayText = (segment: TranscriptSegmentData): string => {
    if (streamingSegment && segment.id === streamingSegment.id) {
      return streamingSegment.visibleText;
    }
    return segment.text;
  };

  return {
    streamingSegmentId: streamingSegment?.id ?? null,
    getDisplayText,
  };
}
