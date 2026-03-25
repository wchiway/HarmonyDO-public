import { ApiClient } from '../../services/network/ApiClient';
import { ComposerPreviewOneboxCache } from './ComposerPreviewOneboxCache';
import { ComposerUploadUrlCache } from './ComposerUploadUrlCache';
import { MarkdownComposerUtils } from './MarkdownComposerUtils';

export class ComposerPreviewResourceResolver {
  private static readonly oneboxPromiseMap: Map<string, Promise<boolean>> = new Map();

  static async ensureMarkdownResources(markdown: string): Promise<boolean> {
    let updated: boolean = false;
    const uploadUpdated: boolean = await ComposerPreviewResourceResolver.ensureUploadUrls(markdown);
    if (uploadUpdated) {
      updated = true;
    }
    const oneboxUpdated: boolean = await ComposerPreviewResourceResolver.ensureOneboxes(markdown);
    if (oneboxUpdated) {
      updated = true;
    }
    return updated;
  }

  private static async ensureUploadUrls(markdown: string): Promise<boolean> {
    const shortUrls: string[] = MarkdownComposerUtils.collectPreviewUploadShortUrls(markdown);
    if (shortUrls.length === 0) {
      return false;
    }

    await ComposerUploadUrlCache.hydrate();

    const missing: string[] = [];
    for (let i: number = 0; i < shortUrls.length; i++) {
      const shortUrl: string = shortUrls[i];
      if (ComposerUploadUrlCache.resolve(shortUrl) === shortUrl && missing.indexOf(shortUrl) < 0) {
        missing.push(shortUrl);
      }
    }
    if (missing.length === 0) {
      return false;
    }

    try {
      const resolved = await ApiClient.getInstance().lookupComposerUploadUrls(missing);
      return resolved.length > 0;
    } catch (_) {
      return false;
    }
  }

  private static async ensureOneboxes(markdown: string): Promise<boolean> {
    const urls: string[] = MarkdownComposerUtils.collectPreviewStandaloneUrls(markdown);
    let updated: boolean = false;
    for (let i: number = 0; i < urls.length; i++) {
      if (await ComposerPreviewResourceResolver.ensureOnebox(urls[i])) {
        updated = true;
      }
    }
    return updated;
  }

  private static async ensureOnebox(url: string): Promise<boolean> {
    const key: string = url !== undefined && url !== null ? url.trim() : '';
    if (key.length === 0) {
      return false;
    }
    if (ComposerPreviewOneboxCache.resolve(key).length > 0) {
      return false;
    }
    if (ComposerPreviewResourceResolver.oneboxPromiseMap.has(key)) {
      return await (ComposerPreviewResourceResolver.oneboxPromiseMap.get(key) as Promise<boolean>);
    }

    const promise: Promise<boolean> = (async (): Promise<boolean> => {
      try {
        const html: string = await ApiClient.getInstance().getComposerOneboxHtml(key);
        if (html.trim().length === 0) {
          return false;
        }
        ComposerPreviewOneboxCache.register(key, html);
        return true;
      } catch (_) {
        return false;
      } finally {
        ComposerPreviewResourceResolver.oneboxPromiseMap.delete(key);
      }
    })();
    ComposerPreviewResourceResolver.oneboxPromiseMap.set(key, promise);
    return await promise;
  }
}
