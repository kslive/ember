'use client';

import { memo } from 'react';
import { ConfidenceIndicator } from '@/components/ConfidenceIndicator';
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip';

export function formatRecordingTime(seconds: number | undefined): string {
    if (seconds === undefined) return '--:--';

    const totalSeconds = Math.floor(seconds);
    const minutes = Math.floor(totalSeconds / 60);
    const secs = totalSeconds % 60;

    return `${minutes.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
}

export function cleanStopWords(text: string): string {
    const stopWords = ['uh', 'um', 'er', 'ah', 'hmm', 'hm', 'eh', 'oh'];

    let cleanedText = text;
    stopWords.forEach(word => {
        const pattern = new RegExp(`\\b${word}\\b[,\\s]*`, 'gi');
        cleanedText = cleanedText.replace(pattern, ' ');
    });

    return cleanedText.replace(/\s+/g, ' ').trim();
}

export interface TranscriptRowProps {
    id: string;
    timestamp: number;
    text: string;
    confidence?: number;
    isStreaming: boolean;
    showConfidence: boolean;
    showCaret?: boolean;
}

export const TranscriptRow = memo(function TranscriptRow({
    id,
    timestamp,
    text,
    confidence,
    isStreaming,
    showConfidence,
    showCaret = false,
}: TranscriptRowProps) {
    const displayText = cleanStopWords(text) || (text.trim() === '' ? '[Silence]' : text);

    return (
        <div id={`segment-${id}`} className="flex gap-[16px] mb-[18px]">
            <Tooltip>
                <TooltipTrigger asChild>
                    {}
                    <span className="font-mono text-[12px] tabular-nums text-fg-faint pt-[2px] flex-none text-left">
                        {formatRecordingTime(timestamp)}
                    </span>
                </TooltipTrigger>
                <TooltipContent>
                    {confidence !== undefined && showConfidence && (
                        <ConfidenceIndicator confidence={confidence} showIndicator={showConfidence} />
                    )}
                </TooltipContent>
            </Tooltip>
            {}
            <p className={`select-text font-sans text-[15px] leading-[1.65] ${isStreaming ? 'text-fg-muted' : 'text-fg'}`}>
                {displayText}
                {showCaret && (
                    <span className="inline-block w-[2px] h-[16px] align-[-2px] ml-[1px] bg-accent animate-caret-blink" />
                )}
            </p>
        </div>
    );
});
