'use client';

import { useRef, useReducer, startTransition, useEffect } from "react";
import { useVirtualizer } from "@tanstack/react-virtual";
import { useAutoScroll } from "@/hooks/useAutoScroll";
import { useTranscriptStreaming } from "@/hooks/useTranscriptStreaming";
import { motion } from "framer-motion";
import { TranscriptSegmentData } from "@/types";
import { TranscriptRow } from "./transcript/TranscriptRow";
import { useTranslation } from "react-i18next";

export interface VirtualizedTranscriptViewProps {
    segments: TranscriptSegmentData[];
    isRecording?: boolean;
    isPaused?: boolean;
    isProcessing?: boolean;
    isStopping?: boolean;
    enableStreaming?: boolean;
    showConfidence?: boolean;
    disableAutoScroll?: boolean;

    hasMore?: boolean;
    isLoadingMore?: boolean;
    totalCount?: number;
    loadedCount?: number;
    onLoadMore?: () => void;
}

const VIRTUALIZATION_THRESHOLD = 10;

export const VirtualizedTranscriptView: React.FC<VirtualizedTranscriptViewProps> = ({
    segments,
    isRecording = false,
    isPaused = false,
    isProcessing = false,
    isStopping = false,
    enableStreaming = false,
    showConfidence = true,
    disableAutoScroll = false,
    hasMore = false,
    isLoadingMore = false,
    totalCount = 0,
    loadedCount = 0,
    onLoadMore,
}) => {
    const { t } = useTranslation('recording');
    const scrollRef = useRef<HTMLDivElement>(null);
    const loadMoreTriggerRef = useRef<HTMLDivElement>(null);

    const [, rerender] = useReducer((x: number) => x + 1, 0);

    const virtualizer = useVirtualizer({
        count: segments.length,
        getScrollElement: () => scrollRef.current,
        estimateSize: () => 60,
        overscan: 10,
        onChange: () => {
            startTransition(() => {
                rerender();
            });
        },
    });

    useAutoScroll({
        scrollRef,
        segments,
        isRecording,
        isPaused,
        virtualizer,
        virtualizationThreshold: VIRTUALIZATION_THRESHOLD,
        disableAutoScroll,
    });

    const { streamingSegmentId, getDisplayText } = useTranscriptStreaming(
        segments,
        isRecording,
        enableStreaming
    );

    useEffect(() => {
        if (!onLoadMore || !hasMore || isLoadingMore || isRecording || segments.length === 0) {
            return;
        }

        const triggerElement = loadMoreTriggerRef.current;
        if (!triggerElement) return;

        const observer = new IntersectionObserver(
            (entries) => {
                if (entries[0].isIntersecting && hasMore && !isLoadingMore) {
                    onLoadMore();
                }
            },
            {
                root: null,
                rootMargin: '100px',
                threshold: 0,
            }
        );

        observer.observe(triggerElement);

        return () => observer.disconnect();
    }, [hasMore, isLoadingMore, onLoadMore, isRecording, segments.length]);

    useEffect(() => {
        if (!onLoadMore || !hasMore || isLoadingMore || isRecording) return;

        const scrollElement = scrollRef.current;
        if (!scrollElement) return;

        let ticking = false;

        const handleScroll = () => {
            if (ticking || isLoadingMore || !hasMore) return;

            ticking = true;
            requestAnimationFrame(() => {
                const { scrollTop, scrollHeight, clientHeight } = scrollElement;
                const scrollBottom = scrollHeight - scrollTop - clientHeight;

                if (scrollBottom < 200 && hasMore && !isLoadingMore) {
                    onLoadMore();
                }
                ticking = false;
            });
        };

        scrollElement.addEventListener('scroll', handleScroll, { passive: true });
        return () => scrollElement.removeEventListener('scroll', handleScroll);
    }, [onLoadMore, hasMore, isLoadingMore, isRecording]);

    const useVirtualization = segments.length >= VIRTUALIZATION_THRESHOLD;

    return (
        <div ref={scrollRef} className="flex flex-col h-full min-h-0 overflow-y-auto">
            {}

            {}
            <div>
            {segments.length === 0 ? (
                isRecording ? null : (
                    <motion.div
                        initial={{ opacity: 0 }}
                        animate={{ opacity: 1 }}
                        className="text-center text-fg-muted mt-8"
                    >
                        <p className="font-sans text-[38px] font-light tracking-[-0.02em] text-fg leading-[1.1]">{t('ready')}</p>
                        <p className="font-sans text-[15px] leading-[1.6] mt-3.5 text-fg-muted">{t('emptyHint')}</p>
                    </motion.div>
                )
            ) : useVirtualization ? (
                <>
                    <div
                        style={{
                            height: virtualizer.getTotalSize(),
                            width: "100%",
                            position: "relative",
                        }}
                    >
                        {virtualizer.getVirtualItems().map((virtualRow) => {
                            const segment = segments[virtualRow.index];
                            const isStreaming = streamingSegmentId === segment.id;

                            return (
                                <div
                                    key={segment.id}
                                    data-index={virtualRow.index}
                                    ref={virtualizer.measureElement}
                                    style={{
                                        position: "absolute",
                                        top: 0,
                                        left: 0,
                                        width: "100%",
                                        transform: `translateY(${virtualRow.start}px)`,
                                    }}
                                >
                                    <TranscriptRow
                                        id={segment.id}
                                        timestamp={segment.timestamp}
                                        text={getDisplayText(segment)}
                                        confidence={segment.confidence}
                                        isStreaming={isStreaming}
                                        showConfidence={showConfidence}
                                        showCaret={isRecording && !isPaused && virtualRow.index === segments.length - 1}
                                    />
                                </div>
                            );
                        })}
                    </div>

                    {}
                    {(hasMore || isLoadingMore) && !isRecording && segments.length > 0 && (
                        <div ref={loadMoreTriggerRef} className="flex justify-center items-center py-4 mt-2">
                            {isLoadingMore ? (
                                <div className="flex items-center gap-2 text-fg-muted">
                                    <div className="w-4 h-4 border-2 border-line border-t-line-strong rounded-full animate-spin" />
                                    <span className="text-sm">{t('loadMore.loading')}</span>
                                </div>
                            ) : hasMore && totalCount > 0 ? (
                                <span className="text-sm text-fg-faint">
                                    {t('loadMore.showing', { count: totalCount, loaded: loadedCount, total: totalCount })}
                                </span>
                            ) : null}
                        </div>
                    )}
                    {}
                </>
            ) : (
                <>
                    <div className="space-y-1">
                        {segments.map((segment, index) => {
                            const isStreaming = streamingSegmentId === segment.id;

                            return (
                                <motion.div
                                    key={segment.id}
                                    initial={{ opacity: 0, y: 5 }}
                                    animate={{ opacity: 1, y: 0 }}
                                    transition={{ duration: 0.15 }}
                                >
                                    <TranscriptRow
                                        id={segment.id}
                                        timestamp={segment.timestamp}
                                        text={getDisplayText(segment)}
                                        confidence={segment.confidence}
                                        isStreaming={isStreaming}
                                        showConfidence={showConfidence}
                                        showCaret={isRecording && !isPaused && index === segments.length - 1}
                                    />
                                </motion.div>
                            );
                        })}
                    </div>

                    {}
                    {(hasMore || isLoadingMore) && !isRecording && segments.length > 0 && (
                        <div ref={loadMoreTriggerRef} className="flex justify-center items-center py-4 mt-2">
                            {isLoadingMore ? (
                                <div className="flex items-center gap-2 text-fg-muted">
                                    <div className="w-4 h-4 border-2 border-line border-t-line-strong rounded-full animate-spin" />
                                    <span className="text-sm">{t('loadMore.loading')}</span>
                                </div>
                            ) : hasMore && totalCount > 0 ? (
                                <span className="text-sm text-fg-faint">
                                    {t('loadMore.showing', { count: totalCount, loaded: loadedCount, total: totalCount })}
                                </span>
                            ) : null}
                        </div>
                    )}
                    {}
                </>
            )}
            </div>
        </div>
    );
};
