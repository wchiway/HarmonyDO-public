export class ComposerPreviewOneboxCache {
  private static readonly htmlMap: Map<string, string> = new Map();

  static register(url: string, html: string): void {
    const key: string = url !== undefined && url !== null ? url.trim() : '';
    const value: string = html !== undefined && html !== null ? html.trim() : '';
    if (key.length === 0 || value.length === 0) {
      return;
    }
    ComposerPreviewOneboxCache.htmlMap.set(key, value);
  }

  static resolve(url: string): string {
    const key: string = url !== undefined && url !== null ? url.trim() : '';
    if (key.length === 0) {
      return '';
    }
    if (ComposerPreviewOneboxCache.htmlMap.has(key)) {
      return ComposerPreviewOneboxCache.htmlMap.get(key) as string;
    }
    return '';
  }
}
