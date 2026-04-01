import { hilog } from '@kit.PerformanceAnalysisKit';
import { ApiClient } from '../network/ApiClient';
import { AuthService } from '../auth/AuthService';

const TAG: string = 'ScreenTrack';

const FLUSH_INTERVAL: number = 60_000;
const MIN_RUSH_FLUSH_INTERVAL: number = 3_000;
const TICK_INTERVAL: number = 1_000;
const PAUSE_UNLESS_SCROLLED: number = 180_000;
const MAX_TRACKING_TIME: number = 360_000;
const AJAX_FAILURE_DELAYS: number[] = [5000, 10000, 20000, 40000];
const ALLOWED_AJAX_FAILURES: number[] = [405, 429, 500, 501, 502, 503, 504];

export type OnTimingsSent = (topicId: number, postNumbers: Set<number>, highestSeen: number) => void;
export type OnPostsRead = (postNumbers: Set<number>) => void;

const OPTIMISTIC_READ_THRESHOLD: number = 2_000; // 2s 即判定已读

class ConsolidatedTiming {
  topicId: number;
  topicTime: number;
  timings: Map<number, number>;
  highestSeen: number;

  constructor(topicId: number) {
    this.topicId = topicId;
    this.topicTime = 0;
    this.timings = new Map();
    this.highestSeen = 0;
  }
}

export class ScreenTrack {
  private topicId: number = 0;
  private onTimingsSent: OnTimingsSent | null = null;
  private onPostsRead: OnPostsRead | null = null;

  // tick timer
  private tickTimerId: number = -1;

  // current visible posts & timings
  private onscreenPostNumbers: Set<number> = new Set();
  private readOnscreenPostNumbers: Set<number> = new Set();
  private currentTimings: Map<number, number> = new Map();
  private highestSeen: number = 0;

  // optimistic read tracking
  private optimisticReadPosts: Set<number> = new Set();

  // scroll tracking
  private lastScrolledAt: number = 0;
  private hasFocus: boolean = true;

  // flush scheduling
  private lastFlushAt: number = 0;
  private rushFlushScheduled: boolean = false;
  private flushTimerId: number = -1;

  // consolidated timings queue
  private consolidatedTimings: ConsolidatedTiming[] = [];
  private isSending: boolean = false;
  private ajaxFailures: number = 0;
  private lastFailedAt: number = 0;

  constructor(onTimingsSent: OnTimingsSent | null = null, onPostsRead: OnPostsRead | null = null) {
    this.onTimingsSent = onTimingsSent;
    this.onPostsRead = onPostsRead;
  }

  start(topicId: number): void {
    if (topicId <= 0) {
      return;
    }
    this.stop();
    this.topicId = topicId;
    this.onscreenPostNumbers = new Set();
    this.readOnscreenPostNumbers = new Set();
    this.currentTimings = new Map();
    this.highestSeen = 0;
    this.optimisticReadPosts = new Set();
    this.lastScrolledAt = Date.now();
    this.hasFocus = true;
    this.lastFlushAt = 0;
    this.rushFlushScheduled = false;
    this.ajaxFailures = 0;
    this.lastFailedAt = 0;
    this.tickTimerId = setInterval(() => {
      this.tick();
    }, TICK_INTERVAL);
  }

  stop(): void {
    if (this.tickTimerId >= 0) {
      clearInterval(this.tickTimerId);
      this.tickTimerId = -1;
    }
    if (this.flushTimerId >= 0) {
      clearTimeout(this.flushTimerId);
      this.flushTimerId = -1;
    }
    if (this.topicId > 0) {
      this.tick();
      this.flush();
    }
    this.topicId = 0;
    this.onscreenPostNumbers = new Set();
    this.readOnscreenPostNumbers = new Set();
    this.currentTimings = new Map();
    this.highestSeen = 0;
    this.rushFlushScheduled = false;
    this.sendNextConsolidatedTiming();
  }

  getHighestSeen(): number {
    return this.highestSeen;
  }

  setOnscreen(postNumbers: Set<number>, readOnscreen: Set<number> | null = null): void {
    this.onscreenPostNumbers = postNumbers;
    if (readOnscreen !== null) {
      this.readOnscreenPostNumbers = readOnscreen;
    } else {
      this.readOnscreenPostNumbers = new Set<number>();
      postNumbers.forEach((pn: number) => {
        this.readOnscreenPostNumbers.add(pn);
      });
    }

    // Check for new unseen posts to trigger rush flush
    let hasNewUnseen: boolean = false;
    postNumbers.forEach((pn: number) => {
      if (!this.currentTimings.has(pn)) {
        hasNewUnseen = true;
      }
    });
    if (hasNewUnseen && !this.rushFlushScheduled && this.consolidatedTimings.length === 0) {
      this.scheduleRushFlush();
    }
  }

  scrolled(): void {
    this.lastScrolledAt = Date.now();
  }

  setHasFocus(hasFocus: boolean): void {
    this.hasFocus = hasFocus;
    if (!hasFocus) {
      this.tick();
      this.flush();
      this.sendNextConsolidatedTiming();
    }
  }

  private tick(): void {
    if (this.topicId <= 0) {
      return;
    }

    // Pause if not focused
    if (!this.hasFocus) {
      return;
    }

    // Pause if no scroll for 3 minutes
    const now: number = Date.now();
    if (this.lastScrolledAt > 0 && (now - this.lastScrolledAt) > PAUSE_UNLESS_SCROLLED) {
      return;
    }

    // Accumulate timings for visible posts
    this.readOnscreenPostNumbers.forEach((postNumber: number) => {
      if (postNumber <= 0) {
        return;
      }
      const existing: number = this.currentTimings.has(postNumber)
        ? this.currentTimings.get(postNumber) as number
        : 0;

      // Cap single post at 6 minutes
      if (existing >= MAX_TRACKING_TIME) {
        return;
      }

      this.currentTimings.set(postNumber, existing + TICK_INTERVAL);
    });

    // Update highest seen
    this.onscreenPostNumbers.forEach((postNumber: number) => {
      if (postNumber > this.highestSeen) {
        this.highestSeen = postNumber;
      }
    });

    // Optimistic read: after 2s of visible time, notify UI to mark post as read locally
    if (this.onPostsRead !== null) {
      const newlyRead: Set<number> = new Set<number>();
      this.currentTimings.forEach((duration: number, postNumber: number) => {
        if (duration >= OPTIMISTIC_READ_THRESHOLD && !this.optimisticReadPosts.has(postNumber)) {
          this.optimisticReadPosts.add(postNumber);
          newlyRead.add(postNumber);
        }
      });
      if (newlyRead.size > 0) {
        try {
          (this.onPostsRead as OnPostsRead)(newlyRead);
        } catch (e) {
          hilog.warn(0x0000, TAG, 'onPostsRead callback error: %{public}s', JSON.stringify(e));
        }
      }
    }

    // Check flush schedule
    const sinceLastFlush: number = this.lastFlushAt > 0 ? (now - this.lastFlushAt) : FLUSH_INTERVAL;
    if (sinceLastFlush >= FLUSH_INTERVAL) {
      this.flush();
    }
  }

  private scheduleRushFlush(): void {
    if (this.rushFlushScheduled) {
      return;
    }
    this.rushFlushScheduled = true;
    if (this.flushTimerId >= 0) {
      clearTimeout(this.flushTimerId);
    }
    this.flushTimerId = setTimeout(() => {
      this.flushTimerId = -1;
      this.rushFlushScheduled = false;
      this.flush();
    }, MIN_RUSH_FLUSH_INTERVAL);
  }

  private flush(): void {
    if (this.topicId <= 0) {
      return;
    }

    // Compute delta: only include timings that have changed since last flush
    const timingsToSend: Map<number, number> = new Map();
    let topicTime: number = 0;
    this.currentTimings.forEach((durationMs: number, postNumber: number) => {
      if (postNumber > 0 && durationMs > 0) {
        timingsToSend.set(postNumber, durationMs);
        topicTime = topicTime + durationMs;
      }
    });

    if (timingsToSend.size === 0) {
      return;
    }

    // Consolidate into queue
    this.consolidateTimings(this.topicId, topicTime, timingsToSend, this.highestSeen);

    // Reset current timings after flush
    this.currentTimings = new Map();
    this.lastFlushAt = Date.now();

    // Trigger send
    this.sendNextConsolidatedTiming();
  }

  private consolidateTimings(
    topicId: number,
    topicTime: number,
    timings: Map<number, number>,
    highestSeen: number
  ): void {
    // Find existing consolidated entry for this topic
    let existing: ConsolidatedTiming | null = null;
    for (let i = 0; i < this.consolidatedTimings.length; i++) {
      if (this.consolidatedTimings[i].topicId === topicId) {
        existing = this.consolidatedTimings[i];
        break;
      }
    }

    if (existing !== null) {
      // Merge into existing
      const ct: ConsolidatedTiming = existing as ConsolidatedTiming;
      ct.topicTime = ct.topicTime + topicTime;
      timings.forEach((durationMs: number, postNumber: number) => {
        const prev: number = ct.timings.has(postNumber) ? ct.timings.get(postNumber) as number : 0;
        ct.timings.set(postNumber, prev + durationMs);
      });
      if (highestSeen > ct.highestSeen) {
        ct.highestSeen = highestSeen;
      }
    } else {
      // Create new entry
      const ct: ConsolidatedTiming = new ConsolidatedTiming(topicId);
      ct.topicTime = topicTime;
      ct.timings = new Map();
      timings.forEach((v: number, k: number) => {
        ct.timings.set(k, v);
      });
      ct.highestSeen = highestSeen;
      this.consolidatedTimings.push(ct);
    }
  }

  private sendNextConsolidatedTiming(): void {
    if (this.isSending) {
      return;
    }
    if (this.consolidatedTimings.length === 0) {
      return;
    }

    // Check auth
    if (!AuthService.getInstance().getIsLoggedIn()) {
      this.consolidatedTimings = [];
      return;
    }

    // Check backoff
    if (this.ajaxFailures > 0 && this.lastFailedAt > 0) {
      const delayIndex: number = Math.min(this.ajaxFailures - 1, AJAX_FAILURE_DELAYS.length - 1);
      const delay: number = AJAX_FAILURE_DELAYS[delayIndex];
      const elapsed: number = Date.now() - this.lastFailedAt;
      if (elapsed < delay) {
        // Schedule retry after remaining delay
        const remaining: number = delay - elapsed;
        if (this.flushTimerId >= 0) {
          clearTimeout(this.flushTimerId);
        }
        this.flushTimerId = setTimeout(() => {
          this.flushTimerId = -1;
          this.sendNextConsolidatedTiming();
        }, remaining);
        return;
      }
    }

    const ct: ConsolidatedTiming = this.consolidatedTimings[0];
    this.isSending = true;

    const topicId: number = ct.topicId;
    const topicTime: number = ct.topicTime;
    const timings: Map<number, number> = ct.timings;
    const highestSeen: number = ct.highestSeen;
    const sentPostNumbers: Set<number> = new Set<number>();
    timings.forEach((_: number, pn: number) => {
      sentPostNumbers.add(pn);
    });

    ApiClient.getInstance().sendTopicTimings(topicId, topicTime, timings)
      .then((statusCode: number) => {
        this.isSending = false;

        if (statusCode >= 200 && statusCode < 300) {
          // Success
          this.ajaxFailures = 0;
          this.lastFailedAt = 0;

          // Remove from queue
          this.consolidatedTimings.splice(0, 1);

          // Notify callback
          if (this.onTimingsSent !== null) {
            try {
              (this.onTimingsSent as OnTimingsSent)(topicId, sentPostNumbers, highestSeen);
            } catch (e) {
              hilog.warn(0x0000, TAG, 'onTimingsSent callback error: %{public}s', JSON.stringify(e));
            }
          }

          // Send next if any
          this.sendNextConsolidatedTiming();
        } else {
          this.handleSendFailure(statusCode);
        }
      })
      .catch((err: Object) => {
        this.isSending = false;
        hilog.warn(0x0000, TAG, 'sendTopicTimings error: %{public}s', JSON.stringify(err));
        this.handleSendFailure(0);
      });
  }

  private handleSendFailure(statusCode: number): void {
    // Check if this is a retryable failure
    let isRetryable: boolean = statusCode === 0; // network error
    for (let i = 0; i < ALLOWED_AJAX_FAILURES.length; i++) {
      if (ALLOWED_AJAX_FAILURES[i] === statusCode) {
        isRetryable = true;
        break;
      }
    }

    if (isRetryable) {
      this.ajaxFailures = this.ajaxFailures + 1;
      this.lastFailedAt = Date.now();

      if (this.ajaxFailures <= AJAX_FAILURE_DELAYS.length) {
        // Schedule retry
        const delayIndex: number = Math.min(this.ajaxFailures - 1, AJAX_FAILURE_DELAYS.length - 1);
        const delay: number = AJAX_FAILURE_DELAYS[delayIndex];
        if (this.flushTimerId >= 0) {
          clearTimeout(this.flushTimerId);
        }
        this.flushTimerId = setTimeout(() => {
          this.flushTimerId = -1;
          this.sendNextConsolidatedTiming();
        }, delay);
      } else {
        // Too many failures, discard
        hilog.warn(0x0000, TAG, 'Too many ajax failures (%{public}d), discarding consolidated timings', this.ajaxFailures);
        this.consolidatedTimings = [];
        this.ajaxFailures = 0;
        this.lastFailedAt = 0;
      }
    } else {
      // Non-retryable (e.g. 403, 404) — discard this entry
      hilog.warn(0x0000, TAG, 'Non-retryable status %{public}d, discarding timing for topic %{public}d',
        statusCode, this.consolidatedTimings.length > 0 ? this.consolidatedTimings[0].topicId : 0);
      if (this.consolidatedTimings.length > 0) {
        this.consolidatedTimings.splice(0, 1);
      }
      this.sendNextConsolidatedTiming();
    }
  }
}
