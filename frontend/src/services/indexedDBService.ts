
export interface MeetingMetadata {
  meetingId: string;
  title: string;
  startTime: number;
  lastUpdated: number;
  transcriptCount: number;
  savedToSQLite: boolean;
  folderPath?: string;
}

export interface StoredTranscript {
  id?: number;
  meetingId: string;
  text: string;
  timestamp: string;
  confidence: number;
  sequenceId: number;
  storedAt: number;
  audio_start_time?: number;
  audio_end_time?: number;
  duration?: number;
  [key: string]: any;
}

class IndexedDBService {
  private db: IDBDatabase | null = null;
  private readonly DB_NAME = 'EmberRecoveryDB';
  private readonly DB_VERSION = 1;
  private initPromise: Promise<void> | null = null;

  async init(): Promise<void> {
    if (this.initPromise) {
      return this.initPromise;
    }

    if (this.db) {
      return Promise.resolve();
    }

    this.initPromise = new Promise((resolve, reject) => {
      try {
        const request = indexedDB.open(this.DB_NAME, this.DB_VERSION);

        request.onerror = () => {
          console.error('Failed to open IndexedDB:', request.error);
          reject(request.error);
        };

        request.onsuccess = () => {
          this.db = request.result;
          resolve();
        };

        request.onupgradeneeded = (event) => {
          const db = (event.target as IDBOpenDBRequest).result;

          if (!db.objectStoreNames.contains('meetings')) {
            const meetingsStore = db.createObjectStore('meetings', { keyPath: 'meetingId' });
            meetingsStore.createIndex('lastUpdated', 'lastUpdated', { unique: false });
            meetingsStore.createIndex('savedToSQLite', 'savedToSQLite', { unique: false });
          }

          if (!db.objectStoreNames.contains('transcripts')) {
            const transcriptsStore = db.createObjectStore('transcripts', {
              keyPath: 'id',
              autoIncrement: true
            });
            transcriptsStore.createIndex('meetingId', 'meetingId', { unique: false });
            transcriptsStore.createIndex('storedAt', 'storedAt', { unique: false });
          }
        };
      } catch (error) {
        console.error('Exception during IndexedDB initialization:', error);
        reject(error);
      }
    });

    return this.initPromise;
  }

  async saveMeetingMetadata(metadata: MeetingMetadata): Promise<void> {
    try {
      if (!this.db) await this.init();

      const transaction = this.db!.transaction(['meetings'], 'readwrite');
      const store = transaction.objectStore('meetings');

      await new Promise<void>((resolve, reject) => {
        const request = store.put(metadata);
        request.onsuccess = () => resolve();
        request.onerror = () => reject(request.error);
      });
    } catch (error) {
      console.warn('Failed to save meeting metadata to IndexedDB:', error);
    }
  }

  async getMeetingMetadata(meetingId: string): Promise<MeetingMetadata | null> {
    try {
      if (!this.db) await this.init();

      const transaction = this.db!.transaction(['meetings'], 'readonly');
      const store = transaction.objectStore('meetings');

      return new Promise((resolve, reject) => {
        const request = store.get(meetingId);
        request.onsuccess = () => resolve(request.result || null);
        request.onerror = () => reject(request.error);
      });
    } catch (error) {
      console.error('Failed to get meeting metadata from IndexedDB:', error);
      return null;
    }
  }

  async getAllMeetings(): Promise<MeetingMetadata[]> {
    try {
      if (!this.db) await this.init();

      const transaction = this.db!.transaction(['meetings'], 'readonly');
      const store = transaction.objectStore('meetings');

      return new Promise((resolve, reject) => {
        const request = store.getAll();
        request.onsuccess = () => {
          const allMeetings = request.result as MeetingMetadata[];
          const unsavedMeetings = allMeetings.filter(m => m.savedToSQLite === false);

          unsavedMeetings.sort((a, b) => b.lastUpdated - a.lastUpdated);
          resolve(unsavedMeetings);
        };
        request.onerror = () => reject(request.error);
      });
    } catch (error) {
      console.error('Failed to get meetings from IndexedDB:', error);
      return [];
    }
  }

  async markMeetingSaved(meetingId: string): Promise<void> {
    try {
      if (!this.db) await this.init();

      const transaction = this.db!.transaction(['meetings'], 'readwrite');
      const store = transaction.objectStore('meetings');

      return new Promise((resolve, reject) => {
        const getRequest = store.get(meetingId);
        getRequest.onsuccess = () => {
          const meeting = getRequest.result;
          if (meeting) {
            meeting.savedToSQLite = true;
            meeting.lastUpdated = Date.now();
            const putRequest = store.put(meeting);
            putRequest.onsuccess = () => resolve();
            putRequest.onerror = () => reject(putRequest.error);
          } else {
            resolve();
          }
        };
        getRequest.onerror = () => reject(getRequest.error);
      });
    } catch (error) {
      console.warn('Failed to mark meeting as saved:', error);
    }
  }

  async deleteMeeting(meetingId: string): Promise<void> {
    try {
      if (!this.db) await this.init();

      const transaction = this.db!.transaction(['meetings', 'transcripts'], 'readwrite');
      const meetingsStore = transaction.objectStore('meetings');
      const transcriptsStore = transaction.objectStore('transcripts');

      await this.deleteTranscriptsForMeetingInternal(transcriptsStore, meetingId);

      await new Promise<void>((resolve, reject) => {
        const request = meetingsStore.delete(meetingId);
        request.onsuccess = () => resolve();
        request.onerror = () => reject(request.error);
      });
    } catch (error) {
      console.error('Failed to delete meeting from IndexedDB:', error);
      throw error;
    }
  }

  async saveTranscript(meetingId: string, transcript: any): Promise<void> {
    try {
      if (!this.db) await this.init();

      const storedTranscript: StoredTranscript = {
        ...transcript,
        meetingId,
        storedAt: Date.now()
      };

      const transaction = this.db!.transaction(['transcripts', 'meetings'], 'readwrite');
      const transcriptsStore = transaction.objectStore('transcripts');
      const meetingsStore = transaction.objectStore('meetings');

      await new Promise<void>((resolve, reject) => {
        const request = transcriptsStore.add(storedTranscript);
        request.onsuccess = () => resolve();
        request.onerror = () => reject(request.error);
      });

      const meeting = await new Promise<MeetingMetadata | null>((resolve, reject) => {
        const request = meetingsStore.get(meetingId);
        request.onsuccess = () => resolve(request.result || null);
        request.onerror = () => reject(request.error);
      });

      if (meeting) {
        meeting.lastUpdated = Date.now();
        meeting.transcriptCount += 1;
        await new Promise<void>((resolve, reject) => {
          const request = meetingsStore.put(meeting);
          request.onsuccess = () => resolve();
          request.onerror = () => reject(request.error);
        });
      }
    } catch (error) {
      console.warn('Failed to save transcript to IndexedDB:', error);
    }
  }

  async getTranscripts(meetingId: string): Promise<StoredTranscript[]> {
    try {
      if (!this.db) await this.init();

      const transaction = this.db!.transaction(['transcripts'], 'readonly');
      const store = transaction.objectStore('transcripts');
      const index = store.index('meetingId');

      return new Promise((resolve, reject) => {
        const request = index.getAll(meetingId);
        request.onsuccess = () => {
          const transcripts = request.result as StoredTranscript[];
          transcripts.sort((a, b) => a.sequenceId - b.sequenceId);
          resolve(transcripts);
        };
        request.onerror = () => reject(request.error);
      });
    } catch (error) {
      console.error('Failed to get transcripts from IndexedDB:', error);
      return [];
    }
  }

  async getTranscriptCount(meetingId: string): Promise<number> {
    try {
      if (!this.db) await this.init();

      const transaction = this.db!.transaction(['transcripts'], 'readonly');
      const store = transaction.objectStore('transcripts');
      const index = store.index('meetingId');

      return new Promise((resolve, reject) => {
        const request = index.count(meetingId);
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
      });
    } catch (error) {
      console.error('Failed to get transcript count from IndexedDB:', error);
      return 0;
    }
  }

  async deleteOldMeetings(daysOld: number): Promise<number> {
    try {
      if (!this.db) await this.init();

      const cutoffTime = Date.now() - (daysOld * 24 * 60 * 60 * 1000);
      const transaction = this.db!.transaction(['meetings', 'transcripts'], 'readwrite');
      const meetingsStore = transaction.objectStore('meetings');
      const transcriptsStore = transaction.objectStore('transcripts');

      const allMeetings = await new Promise<MeetingMetadata[]>((resolve, reject) => {
        const request = meetingsStore.getAll();
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
      });

      let deletedCount = 0;

      for (const meeting of allMeetings) {
        if (meeting.lastUpdated < cutoffTime) {
          await this.deleteTranscriptsForMeetingInternal(transcriptsStore, meeting.meetingId);

          await new Promise<void>((resolve, reject) => {
            const request = meetingsStore.delete(meeting.meetingId);
            request.onsuccess = () => resolve();
            request.onerror = () => reject(request.error);
          });

          deletedCount++;
        }
      }

      console.log(`Cleaned up ${deletedCount} old meetings`);
      return deletedCount;
    } catch (error) {
      console.error('Failed to delete old meetings:', error);
      return 0;
    }
  }

  async deleteSavedMeetings(hoursOld: number): Promise<number> {
    try {
      if (!this.db) await this.init();

      const cutoffTime = Date.now() - (hoursOld * 60 * 60 * 1000);
      const transaction = this.db!.transaction(['meetings', 'transcripts'], 'readwrite');
      const meetingsStore = transaction.objectStore('meetings');
      const transcriptsStore = transaction.objectStore('transcripts');

      const allMeetings = await new Promise<MeetingMetadata[]>((resolve, reject) => {
        const request = meetingsStore.getAll();
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
      });

      const savedMeetings = allMeetings.filter(m => m.savedToSQLite === true);

      let deletedCount = 0;

      for (const meeting of savedMeetings) {
        if (meeting.lastUpdated < cutoffTime) {
          await this.deleteTranscriptsForMeetingInternal(transcriptsStore, meeting.meetingId);

          await new Promise<void>((resolve, reject) => {
            const request = meetingsStore.delete(meeting.meetingId);
            request.onsuccess = () => resolve();
            request.onerror = () => reject(request.error);
          });

          deletedCount++;
        }
      }

      console.log(`Cleaned up ${deletedCount} saved meetings`);
      return deletedCount;
    } catch (error) {
      console.error('Failed to delete saved meetings:', error);
      return 0;
    }
  }

  private async deleteTranscriptsForMeetingInternal(
    transcriptsStore: IDBObjectStore,
    meetingId: string
  ): Promise<void> {
    const index = transcriptsStore.index('meetingId');

    return new Promise((resolve, reject) => {
      const request = index.openCursor(IDBKeyRange.only(meetingId));

      request.onsuccess = (event) => {
        const cursor = (event.target as IDBRequest<IDBCursorWithValue>).result;
        if (cursor) {
          cursor.delete();
          cursor.continue();
        } else {
          resolve();
        }
      };

      request.onerror = () => reject(request.error);
    });
  }
}

export const indexedDBService = new IndexedDBService();
