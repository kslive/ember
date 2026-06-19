import { useRef, useState, useEffect, useCallback, RefObject } from "react";
import { Virtualizer } from "@tanstack/react-virtual";

interface UseAutoScrollProps {
    scrollRef: RefObject<HTMLDivElement | null>;
    segments: any[];
    isRecording: boolean;
    isPaused: boolean;
    activeSegmentId?: string;
    virtualizer?: Virtualizer<HTMLDivElement, Element>;
    virtualizationThreshold?: number;
    disableAutoScroll?: boolean;
}

interface UseAutoScrollReturn {
    autoScroll: boolean;
    setAutoScroll: (value: boolean) => void;
    scrollToBottom: () => void;
}

const SCROLL_THRESHOLD = 100;

export function useAutoScroll({
    scrollRef,
    segments,
    isRecording,
    isPaused,
    activeSegmentId,
    virtualizer,
    virtualizationThreshold = 10,
    disableAutoScroll = false,
}: UseAutoScrollProps): UseAutoScrollReturn {
    const useVirtualization = virtualizer && segments.length >= virtualizationThreshold;
    const [autoScroll, setAutoScroll] = useState(true);
    const autoScrollRef = useRef(autoScroll);
    autoScrollRef.current = autoScroll;

    const userScrolledRef = useRef(false);
    const isProgrammaticScrollRef = useRef(false);
    const prevSegmentCountRef = useRef(segments.length);

    const isNearBottom = useCallback(() => {
        if (!scrollRef.current) return true;
        const { scrollTop, scrollHeight, clientHeight } = scrollRef.current;
        return scrollHeight - scrollTop - clientHeight <= SCROLL_THRESHOLD;
    }, [scrollRef]);

    const scrollToBottom = useCallback(() => {
        if (scrollRef.current) {
            isProgrammaticScrollRef.current = true;
            scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
            userScrolledRef.current = false;
            setAutoScroll(true);

            setTimeout(() => {
                isProgrammaticScrollRef.current = false;
            }, 50);
        }
    }, [scrollRef]);

    useEffect(() => {
        const container = scrollRef.current;
        if (!container) return;

        let scrollTimeout: ReturnType<typeof setTimeout> | null = null;

        const handleScroll = () => {
            if (isProgrammaticScrollRef.current) {
                return;
            }

            if (scrollTimeout) {
                clearTimeout(scrollTimeout);
            }

            scrollTimeout = setTimeout(() => {
                const nearBottom = isNearBottom();

                if (nearBottom) {
                    userScrolledRef.current = false;
                    setAutoScroll(true);
                } else {
                    userScrolledRef.current = true;
                    setAutoScroll(false);
                }
            }, 100);
        };

        container.addEventListener("scroll", handleScroll, { passive: true });

        return () => {
            container.removeEventListener("scroll", handleScroll);
            if (scrollTimeout) {
                clearTimeout(scrollTimeout);
            }
        };
    }, [isNearBottom, scrollRef]);

    useEffect(() => {
        if (disableAutoScroll) {
            return;
        }

        const segmentCount = segments.length;
        const prevCount = prevSegmentCountRef.current;
        const hasNewSegments = segmentCount > prevCount;

        prevSegmentCountRef.current = segmentCount;

        if (hasNewSegments && autoScrollRef.current && isRecording && !isPaused && segmentCount > 0) {
            const isCurrentlyAtBottom = isNearBottom();
            if (!isCurrentlyAtBottom) {
                return;
            }

            isProgrammaticScrollRef.current = true;

            if (useVirtualization && virtualizer) {
                const totalSize = virtualizer.getTotalSize();
                virtualizer.scrollToOffset(totalSize + 1000, { align: "end" });

                setTimeout(() => {
                    if (scrollRef.current) {
                        scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
                    }
                }, 50);
            } else if (scrollRef.current) {
                scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
            }

            setTimeout(() => {
                isProgrammaticScrollRef.current = false;
            }, 150);
        }
    }, [segments.length, isRecording, isPaused, useVirtualization, virtualizer, scrollRef, isNearBottom, disableAutoScroll]);

    useEffect(() => {
        if (activeSegmentId) {
            isProgrammaticScrollRef.current = true;

            if (useVirtualization && virtualizer) {
                const index = segments.findIndex((s: any) => s.id === activeSegmentId);
                if (index >= 0) {
                    virtualizer.scrollToIndex(index, { align: "center", behavior: "smooth" });
                }
            } else {
                const element = document.getElementById(`segment-${activeSegmentId}`);
                if (element) {
                    element.scrollIntoView({ behavior: "smooth", block: "center" });
                }
            }

            setTimeout(() => {
                isProgrammaticScrollRef.current = false;
            }, 500);
        }
    }, [activeSegmentId, useVirtualization, virtualizer, segments]);

    return {
        autoScroll,
        setAutoScroll,
        scrollToBottom,
    };
}
