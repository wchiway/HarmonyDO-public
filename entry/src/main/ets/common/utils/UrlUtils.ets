import { AppConstants } from '../constants/AppConstants';
import { PreloadedDataService } from '../../services/messagebus/PreloadedDataService';

/**
 * URL 工具类
 */
export class UrlUtils {
  private static normalizeBaseUrl(url: string): string {
    const raw: string = url !== undefined && url !== null ? url.trim() : '';
    if (raw.length === 0) {
      return '';
    }
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  private static rewritePrimaryCdn(url: string): string {
    const preloaded: PreloadedDataService = PreloadedDataService.getInstance();
    const cdnUrl: string | null = preloaded.getCdnUrl();
    if (cdnUrl === null || cdnUrl.trim().length === 0) {
      return url;
    }

    const primaryBase: string = UrlUtils.normalizeBaseUrl(AppConstants.BASE_URL);
    const targetBase: string = UrlUtils.normalizeBaseUrl(cdnUrl);
    if (primaryBase.length === 0 || targetBase.length === 0) {
      return url;
    }

    if (url.startsWith(primaryBase)) {
      return `${targetBase}${url.substring(primaryBase.length)}`;
    }
    return url;
  }

  private static rewriteS3Cdn(url: string): string {
    const preloaded: PreloadedDataService = PreloadedDataService.getInstance();
    const s3CdnUrl: string | null = preloaded.getS3CdnUrl();
    const s3BaseUrl: string | null = preloaded.getS3BaseUrl();
    if (s3CdnUrl === null || s3BaseUrl === null) return url;

    const s3BaseFull: string = UrlUtils.normalizeBaseUrl(s3BaseUrl.startsWith('//') ? `https:${s3BaseUrl}` : s3BaseUrl);
    const s3CdnFull: string = UrlUtils.normalizeBaseUrl(s3CdnUrl);
    if (s3BaseFull.length === 0 || s3CdnFull.length === 0) {
      return url;
    }

    if (url.startsWith(s3BaseFull)) {
      return `${s3CdnFull}${url.substring(s3BaseFull.length)}`;
    }
    return url;
  }

  private static rewriteAbsoluteUrl(url: string): string {
    const withPrimaryCdn: string = UrlUtils.rewritePrimaryCdn(url);
    return UrlUtils.rewriteS3Cdn(withPrimaryCdn);
  }

  /**
   * 解析相对 URL 为完整 URL
   */
  static resolveUrl(url: string | null): string {
    const raw: string = url !== undefined && url !== null ? url.trim() : '';
    if (raw.length === 0) {
      return '';
    }
    if (raw.startsWith('file://')) {
      return raw;
    }
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return UrlUtils.rewriteAbsoluteUrl(raw);
    }
    if (raw.startsWith('//')) {
      const fullUrl: string = `https:${raw}`;
      return UrlUtils.rewriteAbsoluteUrl(fullUrl);
    }

    const preloaded: PreloadedDataService = PreloadedDataService.getInstance();
    const cdnUrl: string | null = preloaded.getCdnUrl();
    const base: string = UrlUtils.normalizeBaseUrl(cdnUrl !== null ? (cdnUrl as string) : AppConstants.BASE_URL);
    if (raw.startsWith('/')) {
      return UrlUtils.rewriteAbsoluteUrl(`${base}${raw}`);
    }
    return UrlUtils.rewriteAbsoluteUrl(`${base}/${raw}`);
  }

  /**
   * 获取头像 URL
   * 替换 {size} 占位符并解析相对路径
   */
  static getAvatarUrl(template: string | null, size: number = 120): string {
    if (template === null || template.length === 0) {
      return '';
    }
    const url: string = template.replace('{size}', size.toString());
    return UrlUtils.resolveUrl(url);
  }
}
