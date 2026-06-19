
export interface AnalyticsProperties { [key: string]: string }
export interface DeviceInfo { platform: string; os_version: string; architecture: string }
export interface UserSession {
  session_id: string; user_id: string; start_time: string; last_heartbeat: string; is_active: boolean;
}

const NOOP = async (): Promise<void> => {};

export class Analytics {
  static async init(): Promise<void> { return NOOP(); }
  static async disable(): Promise<void> { return NOOP(); }
  static async isEnabled(): Promise<boolean> { return false; }
  static async track(_e: string, _p?: AnalyticsProperties): Promise<void> { return NOOP(); }
  static async identify(_id: string, _p?: AnalyticsProperties): Promise<void> { return NOOP(); }
  static async startSession(_u: string): Promise<string | null> { return null; }
  static async endSession(): Promise<void> { return NOOP(); }
  static async trackDailyActiveUser(): Promise<void> { return NOOP(); }
  static async trackUserFirstLaunch(): Promise<void> { return NOOP(); }
  static async isSessionActive(): Promise<boolean> { return false; }
  static async getPersistentUserId(): Promise<string> { return 'local'; }
  static async checkAndTrackFirstLaunch(): Promise<void> { return NOOP(); }
  static async checkAndTrackDailyUsage(): Promise<void> { return NOOP(); }
  static getCurrentUserId(): string | null { return null; }
  static async getPlatform(): Promise<string> { return 'macos'; }
  static async getOSVersion(): Promise<string> { return ''; }
  static async getDeviceInfo(): Promise<DeviceInfo> { return { platform: 'macos', os_version: '', architecture: 'arm64' }; }
  static async calculateDaysSince(_k: string): Promise<number | null> { return null; }
  static async updateMeetingCount(): Promise<void> { return NOOP(); }
  static async getMeetingsCountToday(): Promise<number> { return 0; }
  static async hasUsedFeatureBefore(_f: string): Promise<boolean> { return false; }
  static async markFeatureUsed(_f: string): Promise<void> { return NOOP(); }
  static async trackSessionStarted(_s: string): Promise<void> { return NOOP(); }
  static async trackSessionEnded(_s: string): Promise<void> { return NOOP(); }
  static async trackMeetingCompleted(_id: string, _m: any): Promise<void> { return NOOP(); }
  static async trackFeatureUsedEnhanced(_f: string, _p?: any): Promise<void> { return NOOP(); }
  static async trackCopy(_t: 'transcript' | 'summary', _p?: any): Promise<void> { return NOOP(); }
  static async trackMeetingStarted(_id: string, _title: string): Promise<void> { return NOOP(); }
  static async trackRecordingStarted(_id: string): Promise<void> { return NOOP(); }
  static async trackRecordingStopped(_id: string, _d?: number): Promise<void> { return NOOP(); }
  static async trackMeetingDeleted(_id: string): Promise<void> { return NOOP(); }
  static async trackSettingsChanged(_t: string, _v: string): Promise<void> { return NOOP(); }
  static async trackFeatureUsed(_f: string): Promise<void> { return NOOP(); }
  static async trackPageView(_p: string): Promise<void> { return NOOP(); }
  static async trackButtonClick(_b: string, _loc?: string): Promise<void> { return NOOP(); }
  static async trackError(_t: string, _m: string): Promise<void> { return NOOP(); }
  static async trackAppStarted(): Promise<void> { return NOOP(); }
  static async cleanup(): Promise<void> { return NOOP(); }
  static reset(): void {}
  static async waitForInitialization(_t?: number): Promise<boolean> { return true; }
  static async trackBackendConnection(_ok: boolean, _e?: string): Promise<void> { return NOOP(); }
  static async trackTranscriptionError(_m: string): Promise<void> { return NOOP(); }
  static async trackTranscriptionSuccess(_d?: number): Promise<void> { return NOOP(); }
  static async trackSummaryGenerationStarted(..._a: any[]): Promise<void> { return NOOP(); }
  static async trackSummaryGenerationCompleted(..._a: any[]): Promise<void> { return NOOP(); }
  static async trackSummaryRegenerated(..._a: any[]): Promise<void> { return NOOP(); }
  static async trackModelChanged(..._a: any[]): Promise<void> { return NOOP(); }
  static async trackCustomPromptUsed(..._a: any[]): Promise<void> { return NOOP(); }
}

export default Analytics;
