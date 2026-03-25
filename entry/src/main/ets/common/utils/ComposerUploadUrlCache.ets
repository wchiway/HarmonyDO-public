import { PreferencesUtil } from '../../services/storage/PreferencesUtil';

export class ComposerUploadUrlCache {
  private static readonly CACHE_KEY: string = 'composer_upload_url_cache_v1';
  private static readonly shortUrlMap: Map<string, string> = new Map();
  private static hydratePromise: Promise<void> | null = null;

  static register(shortUrl: string, resolvedUrl: string): void {
    const shortKey: string = shortUrl !== undefined && shortUrl !== null ? shortUrl.trim() : '';
    const targetUrl: string = resolvedUrl !== undefined && resolvedUrl !== null ? resolvedUrl.trim() : '';
    if (shortKey.length === 0 || targetUrl.length === 0) {
      return;
    }
    if (ComposerUploadUrlCache.shortUrlMap.has(shortKey)) {
      ComposerUploadUrlCache.shortUrlMap.delete(shortKey);
    }
    ComposerUploadUrlCache.shortUrlMap.set(shortKey, targetUrl);
    ComposerUploadUrlCache.persist().catch(() => {
    });
  }

  static async hydrate(): Promise<void> {
    if (ComposerUploadUrlCache.hydratePromise !== null) {
      await ComposerUploadUrlCache.hydratePromise;
      return;
    }

    ComposerUploadUrlCache.hydratePromise = (async () => {
      await PreferencesUtil.ensureInit();
      const raw: string = await PreferencesUtil.getString(ComposerUploadUrlCache.CACHE_KEY, '');
      if (raw.trim().length === 0) {
        return;
      }

      const lines: string[] = raw.split('\n');
      for (let i: number = 0; i < lines.length; i++) {
        const line: string = lines[i] !== undefined && lines[i] !== null ? lines[i].trim() : '';
        if (line.length === 0) {
          continue;
        }
        const splitIndex: number = line.indexOf('\t');
        if (splitIndex <= 0 || splitIndex >= line.length - 1) {
          continue;
        }
        const shortKey: string = line.substring(0, splitIndex).trim();
        const targetUrl: string = line.substring(splitIndex + 1).trim();
        if (shortKey.length === 0 || targetUrl.length === 0) {
          continue;
        }
        if (!ComposerUploadUrlCache.shortUrlMap.has(shortKey)) {
          ComposerUploadUrlCache.shortUrlMap.set(shortKey, targetUrl);
        }
      }
    })();

    await ComposerUploadUrlCache.hydratePromise;
  }

  private static async persist(): Promise<void> {
    await PreferencesUtil.ensureInit();
    const entries: string[] = [];
    ComposerUploadUrlCache.shortUrlMap.forEach((value: string, key: string) => {
      const shortKey: string = key.trim();
      const targetUrl: string = value.trim();
      if (shortKey.length === 0 || targetUrl.length === 0) {
        return;
      }
      entries.push(`${shortKey}\t${targetUrl}`);
    });
    await PreferencesUtil.putString(ComposerUploadUrlCache.CACHE_KEY, entries.join('\n'));
  }

  static resolve(url: string): string {
    const raw: string = url !== undefined && url !== null ? url.trim() : '';
    if (raw.length === 0) {
      return '';
    }
    if (ComposerUploadUrlCache.shortUrlMap.has(raw)) {
      return ComposerUploadUrlCache.shortUrlMap.get(raw) as string;
    }
    return raw;
  }
}
