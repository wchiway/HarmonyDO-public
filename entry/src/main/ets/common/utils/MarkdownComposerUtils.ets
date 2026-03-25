import { EmojiResolver } from './EmojiResolver';
import { ComposerPreviewOneboxCache } from './ComposerPreviewOneboxCache';
import { ComposerUploadUrlCache } from './ComposerUploadUrlCache';

function escapeHtmlText(text: string): string {
  const raw: string = text !== undefined && text !== null ? text : '';
  return raw
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function trimRightSpaces(text: string): string {
  return text.replace(/[\t\u00A0 ]+$/g, '');
}

function trimLeftSpaces(text: string): string {
  return text.replace(/^[\t\u00A0 ]+/g, '');
}

function clampTextIndex(value: number, max: number): number {
  if (isNaN(value) || value < 0) {
    return 0;
  }
  if (value > max) {
    return max;
  }
  return Math.floor(value);
}

function isInlineWhitespace(ch: string): boolean {
  return ch === ' ' || ch === '\n' || ch === '\t' || ch === '\u00A0';
}

function isWordLikeChar(ch: string): boolean {
  return /[A-Za-z0-9\u4E00-\u9FFF]/.test(ch);
}

function needsLeadingInlineSpace(ch: string): boolean {
  return isWordLikeChar(ch) || ch === ':' || ch === ')' || ch === ']' || ch === '}' || ch === '>';
}

function needsTrailingInlineSpace(ch: string): boolean {
  return isWordLikeChar(ch) || ch === ':' || ch === '(' || ch === '[' || ch === '{' || ch === '<';
}

function escapeMarkdownAlt(text: string): string {
  const raw: string = text !== undefined && text !== null ? text : '';
  return raw
    .replace(/\[/g, '\\[')
    .replace(/\]/g, '\\]');
}

export class MarkdownEditResult {
  text: string = '';
  selectionStart: number = 0;
  selectionEnd: number = 0;
}

class MarkdownPreviewImage {
  altText: string = '';
  url: string = '';
  width: number = 0;
  height: number = 0;
}

class MarkdownPreviewCallout {
  type: string = '';
  title: string = '';
}

class MarkdownPreviewLinkCard {
  url: string = '';
  title: string = '';
  description: string = '';
}

export class MarkdownComposerUtils {
  private static buildEditResult(text: string, selectionStart: number, selectionEnd: number): MarkdownEditResult {
    const result: MarkdownEditResult = new MarkdownEditResult();
    result.text = text;
    result.selectionStart = selectionStart;
    result.selectionEnd = selectionEnd;
    return result;
  }

  private static appendInlineToken(text: string, token: string): string {
    const base: string = text !== undefined && text !== null ? text : '';
    const trimmedBase: string = trimRightSpaces(base);
    if (trimmedBase.length === 0) {
      return token;
    }
    if (trimmedBase.endsWith('\n')) {
      return `${trimmedBase}${token}`;
    }
    return `${trimmedBase} ${token}`;
  }

  private static appendBlockToken(text: string, token: string): string {
    const base: string = text !== undefined && text !== null ? text : '';
    const trimmedBase: string = trimRightSpaces(base);
    if (trimmedBase.length === 0) {
      return token;
    }
    return `${trimmedBase}\n\n${token}`;
  }

  static appendEmoji(text: string): string {
    return MarkdownComposerUtils.appendInlineToken(text, ':smile:');
  }

  static insertInlineTextAtSelection(
    text: string,
    insertText: string,
    selectionStart: number,
    selectionEnd: number
  ): MarkdownEditResult {
    const base: string = text !== undefined && text !== null ? text : '';
    const token: string = insertText !== undefined && insertText !== null ? insertText : '';
    if (token.length === 0) {
      const caret: number = clampTextIndex(selectionEnd, base.length);
      return MarkdownComposerUtils.buildEditResult(base, caret, caret);
    }

    let start: number = clampTextIndex(selectionStart, base.length);
    let end: number = clampTextIndex(selectionEnd, base.length);
    if (start > end) {
      const tmp: number = start;
      start = end;
      end = tmp;
    }

    const before: string = base.substring(0, start);
    const after: string = base.substring(end);
    let prefix: string = '';
    let suffix: string = '';
    if (before.length > 0) {
      const prev: string = before.charAt(before.length - 1);
      if (!isInlineWhitespace(prev) && needsLeadingInlineSpace(prev)) {
        prefix = ' ';
      }
    }
    if (after.length > 0) {
      const next: string = after.charAt(0);
      if (!isInlineWhitespace(next) && needsTrailingInlineSpace(next)) {
        suffix = ' ';
      }
    }

    const nextText: string = `${before}${prefix}${token}${suffix}${after}`;
    const caret: number = before.length + prefix.length + token.length + suffix.length;
    return MarkdownComposerUtils.buildEditResult(nextText, caret, caret);
  }

  static insertBlockTextAtSelection(
    text: string,
    insertText: string,
    selectionStart: number,
    selectionEnd: number
  ): MarkdownEditResult {
    const base: string = text !== undefined && text !== null ? text : '';
    const token: string = insertText !== undefined && insertText !== null ? insertText.trim() : '';
    if (token.length === 0) {
      const caret: number = clampTextIndex(selectionEnd, base.length);
      return MarkdownComposerUtils.buildEditResult(base, caret, caret);
    }

    let start: number = clampTextIndex(selectionStart, base.length);
    let end: number = clampTextIndex(selectionEnd, base.length);
    if (start > end) {
      const temp: number = start;
      start = end;
      end = temp;
    }

    const rawBefore: string = base.substring(0, start);
    const rawAfter: string = base.substring(end);
    const before: string = trimRightSpaces(rawBefore);
    const after: string = rawAfter.replace(/^[\t\u00A0 ]+/g, '');

    let prefix: string = '';
    if (before.length > 0) {
      prefix = before.endsWith('\n\n') ? '' : (before.endsWith('\n') ? '\n' : '\n\n');
    }

    let suffix: string = '';
    if (after.length > 0) {
      suffix = after.startsWith('\n\n') ? '' : (after.startsWith('\n') ? '\n' : '\n\n');
    }

    const nextText: string = `${before}${prefix}${token}${suffix}${after}`;
    const caret: number = before.length + prefix.length + token.length + suffix.length;
    return MarkdownComposerUtils.buildEditResult(nextText, caret, caret);
  }

  static insertEmojiShortcode(
    text: string,
    emojiName: string,
    selectionStart: number,
    selectionEnd: number
  ): MarkdownEditResult {
    const rawName: string = emojiName !== undefined && emojiName !== null ? emojiName.trim() : '';
    if (rawName.length === 0) {
      const base: string = text !== undefined && text !== null ? text : '';
      const caret: number = clampTextIndex(selectionEnd, base.length);
      return MarkdownComposerUtils.buildEditResult(base, caret, caret);
    }
    let normalizedName: string = rawName;
    if (normalizedName.startsWith(':') && normalizedName.endsWith(':') && normalizedName.length > 2) {
      normalizedName = normalizedName.substring(1, normalizedName.length - 1);
    }
    return MarkdownComposerUtils.insertInlineTextAtSelection(
      text,
      `:${normalizedName}:`,
      selectionStart,
      selectionEnd
    );
  }

  static insertStickerMarkdown(
    text: string,
    markdown: string,
    selectionStart: number,
    selectionEnd: number
  ): MarkdownEditResult {
    return MarkdownComposerUtils.insertBlockTextAtSelection(
      text,
      markdown,
      selectionStart,
      selectionEnd
    );
  }

  static buildImageMarkdown(
    altText: string,
    url: string,
    width: number = 0,
    height: number = 0
  ): string {
    const safeUrl: string = url !== undefined && url !== null ? url.trim() : '';
    if (safeUrl.length === 0) {
      return '';
    }
    const safeAlt: string = escapeMarkdownAlt(altText.trim().length > 0 ? altText.trim() : 'image');
    if (width > 0 && height > 0) {
      return `![${safeAlt}|${width}x${height}](${safeUrl})`;
    }
    return `![${safeAlt}](${safeUrl})`;
  }

  static insertImageMarkdown(
    text: string,
    markdown: string,
    selectionStart: number,
    selectionEnd: number
  ): MarkdownEditResult {
    return MarkdownComposerUtils.insertBlockTextAtSelection(
      text,
      markdown,
      selectionStart,
      selectionEnd
    );
  }

  static insertImageMarkdowns(
    text: string,
    markdowns: string[],
    selectionStart: number,
    selectionEnd: number
  ): MarkdownEditResult {
    const normalized: string[] = [];
    for (let i: number = 0; i < markdowns.length; i++) {
      const item: string = markdowns[i] !== undefined && markdowns[i] !== null ? markdowns[i].trim() : '';
      if (item.length > 0) {
        normalized.push(item);
      }
    }
    let block: string = normalized.join('\n');
    if (MarkdownComposerUtils.shouldWrapImagesWithGrid(normalized.length)) {
      block = MarkdownComposerUtils.buildImageGridMarkdown(normalized);
    }
    return MarkdownComposerUtils.insertImageMarkdown(
      text,
      block,
      selectionStart,
      selectionEnd
    );
  }

  static shouldWrapImagesWithGrid(imageCount: number): boolean {
    return imageCount >= 3;
  }

  private static buildImageGridMarkdown(markdowns: string[]): string {
    return `[grid]\n${markdowns.join('\n')}\n[/grid]`;
  }

  private static replaceEmojiShortcodes(html: string): string {
    return html.replace(/:([a-z0-9_+\-.]+):/gi, (raw: string): string => {
      const url: string = EmojiResolver.resolveEmojiUrl(raw);
      if (url.length === 0) {
        return raw;
      }
      return `<img src="${escapeHtmlText(url)}" alt="${escapeHtmlText(raw)}" class="emoji">`;
    });
  }

  static insertImagePlaceholder(text: string): string {
    return MarkdownComposerUtils.appendBlockToken(text, '![图片描述](https://)');
  }

  static insertHeading(text: string): string {
    return MarkdownComposerUtils.appendBlockToken(text, '## 标题');
  }

  static insertBold(text: string): string {
    return MarkdownComposerUtils.appendInlineToken(text, '**粗体**');
  }

  static insertItalic(text: string): string {
    return MarkdownComposerUtils.appendInlineToken(text, '*斜体*');
  }

  static applyPanguSpacing(text: string): string {
    let next: string = text !== undefined && text !== null ? text : '';
    next = next.replace(/([\u4E00-\u9FFF])([A-Za-z0-9]+)/g, '$1 $2');
    next = next.replace(/([A-Za-z0-9]+)([\u4E00-\u9FFF])/g, '$1 $2');
    next = next.replace(/ {2,}/g, ' ');
    return next;
  }

  private static resolvePreviewUrl(url: string): string {
    const raw: string = ComposerUploadUrlCache.resolve(url);
    if (raw.length === 0) {
      return '';
    }
    if (raw.startsWith('http://') || raw.startsWith('https://') || raw.startsWith('/')) {
      return raw;
    }
    return '';
  }

  private static sanitizeUrl(url: string): string {
    const resolved: string = MarkdownComposerUtils.resolvePreviewUrl(url);
    return resolved.length > 0 ? escapeHtmlText(resolved) : '';
  }

  private static extractUrlHost(url: string): string {
    const raw: string = MarkdownComposerUtils.resolvePreviewUrl(url);
    if (raw.length === 0) {
      return '';
    }
    if (raw.startsWith('/')) {
      return raw;
    }
    const withoutScheme: string = raw.replace(/^https?:\/\//i, '');
    const slashIndex: number = withoutScheme.indexOf('/');
    const host: string = slashIndex >= 0 ? withoutScheme.substring(0, slashIndex) : withoutScheme;
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  private static parseCalloutHeader(line: string): MarkdownPreviewCallout | null {
    const raw: string = line !== undefined && line !== null ? line.trim() : '';
    const match: RegExpMatchArray | null = raw.match(/^\[!([a-z0-9_-]+)\]\s*(.*)$/i);
    if (match === null || match.length < 2) {
      return null;
    }
    const callout: MarkdownPreviewCallout = new MarkdownPreviewCallout();
    callout.type = match[1].trim().toLowerCase();
    callout.title = match.length > 2 ? match[2].trim() : '';
    return callout.type.length > 0 ? callout : null;
  }

  private static getCalloutFallbackTitle(type: string): string {
    const normalized: string = type !== undefined && type !== null ? type.trim().toLowerCase() : '';
    if (normalized === 'success') return '提示';
    if (normalized === 'warning') return '注意';
    if (normalized === 'danger' || normalized === 'error') return '警告';
    if (normalized === 'tip') return '技巧';
    if (normalized === 'note') return '备注';
    return '信息';
  }

  private static buildSyntheticCalloutHtml(type: string, title: string, contentMarkdown: string): string {
    const safeType: string = escapeHtmlText(type.trim().length > 0 ? type.trim().toLowerCase() : 'info');
    const displayTitle: string = title.trim().length > 0 ? title.trim() : MarkdownComposerUtils.getCalloutFallbackTitle(type);
    const safeTitle: string = escapeHtmlText(displayTitle);
    const contentHtml: string = contentMarkdown.trim().length > 0
      ? MarkdownComposerUtils.toPreviewHtml(contentMarkdown)
      : '<p></p>';
    return `<blockquote class="callout" data-callout-type="${safeType}">`
      + `<div class="callout-title"><span class="callout-title-inner">${safeTitle}</span></div>`
      + `<div class="callout-content">${contentHtml}</div>`
      + `</blockquote>`;
  }

  private static isCalloutBodyBoundary(line: string): boolean {
    const raw: string = line !== undefined && line !== null ? line.trim() : '';
    if (raw.length === 0) {
      return true;
    }
    if (raw.startsWith('```')) {
      return true;
    }
    if (MarkdownComposerUtils.tryBuildHeading(raw).length > 0) {
      return true;
    }
    if (MarkdownComposerUtils.parseCalloutHeader(raw) !== null) {
      return true;
    }
    if (raw.toLowerCase() === '[grid]') {
      return true;
    }
    if (/^!\[[^\]]*\]\([^)]+\)$/.test(raw)) {
      return true;
    }
    if (raw.startsWith('- ') || raw.startsWith('* ')) {
      return true;
    }
    if (MarkdownComposerUtils.isOrderedLine(raw)) {
      return true;
    }
    if (MarkdownComposerUtils.parseStandaloneLinkCard(raw) !== null) {
      return true;
    }
    if (raw.startsWith('>')) {
      const unquoted: string = raw.replace(/^>\s?/, '');
      if (MarkdownComposerUtils.parseCalloutHeader(unquoted) !== null) {
        return true;
      }
    }
    return false;
  }

  private static parseStandaloneMarkdownLink(line: string): MarkdownPreviewLinkCard | null {
    const raw: string = line !== undefined && line !== null ? line.trim() : '';
    const match: RegExpMatchArray | null = raw.match(/^\[([^\]]+)\]\(([^)]+)\)$/);
    if (match === null || match.length < 3) {
      return null;
    }
    const resolvedUrl: string = MarkdownComposerUtils.resolvePreviewUrl(match[2]);
    if (resolvedUrl.length === 0) {
      return null;
    }
    const card: MarkdownPreviewLinkCard = new MarkdownPreviewLinkCard();
    card.url = resolvedUrl;
    card.title = match[1].trim().length > 0 ? match[1].trim() : resolvedUrl;
    return card;
  }

  private static parseStandaloneBareUrl(line: string): MarkdownPreviewLinkCard | null {
    const raw: string = line !== undefined && line !== null ? line.trim() : '';
    if (!/^https?:\/\/\S+$/i.test(raw)) {
      return null;
    }
    const resolvedUrl: string = MarkdownComposerUtils.resolvePreviewUrl(raw);
    if (resolvedUrl.length === 0) {
      return null;
    }
    const card: MarkdownPreviewLinkCard = new MarkdownPreviewLinkCard();
    card.url = resolvedUrl;
    card.title = MarkdownComposerUtils.extractUrlHost(resolvedUrl);
    card.description = resolvedUrl;
    return card;
  }

  private static parseStandaloneLinkCard(line: string): MarkdownPreviewLinkCard | null {
    const markdownLink: MarkdownPreviewLinkCard | null = MarkdownComposerUtils.parseStandaloneMarkdownLink(line);
    if (markdownLink !== null) {
      return markdownLink;
    }
    return MarkdownComposerUtils.parseStandaloneBareUrl(line);
  }

  private static buildPreviewOneboxHtml(card: MarkdownPreviewLinkCard): string {
    const resolvedUrl: string = MarkdownComposerUtils.resolvePreviewUrl(card.url);
    const cachedHtml: string = ComposerPreviewOneboxCache.resolve(resolvedUrl.length > 0 ? resolvedUrl : card.url);
    if (cachedHtml.length > 0) {
      return cachedHtml;
    }
    if (resolvedUrl.length === 0) {
      return MarkdownComposerUtils.buildParagraphHtml([card.url]);
    }
    const safeUrl: string = escapeHtmlText(resolvedUrl);
    const titleText: string = card.title.trim().length > 0 ? card.title.trim() : resolvedUrl;
    const sourceText: string = MarkdownComposerUtils.extractUrlHost(resolvedUrl);
    const descriptionText: string = card.description.trim();
    const safeTitle: string = escapeHtmlText(titleText);
    const safeSource: string = escapeHtmlText(sourceText.length > 0 ? sourceText : resolvedUrl);
    const safeDescription: string = descriptionText.length > 0 ? escapeHtmlText(descriptionText) : '';
    return `<aside class="onebox" data-onebox-src="${safeUrl}">`
      + `<article class="onebox-body">`
      + `<div class="source"><a href="${safeUrl}">${safeSource}</a></div>`
      + `<h3><a href="${safeUrl}">${safeTitle}</a></h3>`
      + (safeDescription.length > 0 ? `<p>${safeDescription}</p>` : '')
      + `</article>`
      + `</aside>`;
  }

  private static parseImageMarkdown(line: string): MarkdownPreviewImage | null {
    const match: RegExpMatchArray | null = line.match(/^!\[([^\]]*)\]\(([^)]+)\)$/);
    if (match === null || match.length < 3) {
      return null;
    }

    const parsed: MarkdownPreviewImage = new MarkdownPreviewImage();
    const rawAlt: string = match[1];
    const pipeIndex: number = rawAlt.indexOf('|');
    if (pipeIndex >= 0) {
      parsed.altText = rawAlt.substring(0, pipeIndex);
      const sizeText: string = rawAlt.substring(pipeIndex + 1).trim();
      const sizeMatch: RegExpMatchArray | null = sizeText.match(/^(\d+)x(\d+)(?:,.*)?$/);
      if (sizeMatch !== null && sizeMatch.length >= 3) {
        const width: number = parseInt(sizeMatch[1], 10);
        const height: number = parseInt(sizeMatch[2], 10);
        parsed.width = isNaN(width) || width <= 0 ? 0 : width;
        parsed.height = isNaN(height) || height <= 0 ? 0 : height;
      }
    } else {
      parsed.altText = rawAlt;
    }
    parsed.url = match[2];
    return parsed;
  }

  private static buildPreviewImageTag(line: string): string {
    const parsed: MarkdownPreviewImage | null = MarkdownComposerUtils.parseImageMarkdown(line);
    if (parsed === null) {
      return '';
    }
    const safeUrl: string = MarkdownComposerUtils.sanitizeUrl(parsed.url);
    if (safeUrl.length === 0) {
      return '';
    }
    const safeAlt: string = escapeHtmlText(parsed.altText);
    let sizeAttrs: string = '';
    if (parsed.width > 0 && parsed.height > 0) {
      sizeAttrs = ` width="${parsed.width}" height="${parsed.height}"`;
    }
    return `<img src="${safeUrl}" alt="${safeAlt}"${sizeAttrs}>`;
  }

  private static resolveGridColumnCount(imageCount: number): number {
    if (imageCount >= 5) {
      return 3;
    }
    if (imageCount >= 3) {
      return 2;
    }
    return 1;
  }

  private static buildImageGridHtml(lines: string[]): string {
    const imageTags: string[] = [];
    for (let i: number = 0; i < lines.length; i++) {
      const current: string = lines[i] !== undefined && lines[i] !== null ? lines[i].trim() : '';
      if (current.length === 0) {
        continue;
      }
      const imageTag: string = MarkdownComposerUtils.buildPreviewImageTag(current);
      if (imageTag.length === 0) {
        return MarkdownComposerUtils.buildParagraphHtml(lines);
      }
      imageTags.push(imageTag);
    }
    if (imageTags.length === 0) {
      return '<p></p>';
    }
    const columns: number = MarkdownComposerUtils.resolveGridColumnCount(imageTags.length);
    return `<div class="d-image-grid" data-columns="${columns}">${imageTags.join('')}</div>`;
  }

  private static parseInline(markdown: string): string {
    let html: string = escapeHtmlText(markdown !== undefined && markdown !== null ? markdown : '');
    const codeTokens: string[] = [];
    html = html.replace(/`([^`]+)`/g, (_: string, code: string): string => {
      const token: string = `@@CODE_${codeTokens.length}@@`;
      codeTokens.push(`<code>${code}</code>`);
      return token;
    });
    html = html.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
    html = html.replace(/\*([^*]+)\*/g, '<em>$1</em>');
    html = html.replace(/~~([^~]+)~~/g, '<s>$1</s>');
    html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_: string, label: string, url: string): string => {
      const safeUrl: string = MarkdownComposerUtils.sanitizeUrl(url);
      if (safeUrl.length === 0) {
        return `[${label}](${url})`;
      }
      return `<a href="${safeUrl}">${label}</a>`;
    });
    html = MarkdownComposerUtils.replaceEmojiShortcodes(html);
    for (let i: number = 0; i < codeTokens.length; i++) {
      const token: string = `@@CODE_${i}@@`;
      html = html.replace(token, codeTokens[i]);
    }
    return html;
  }

  private static buildParagraphHtml(lines: string[]): string {
    const parts: string[] = [];
    for (let i: number = 0; i < lines.length; i++) {
      parts.push(MarkdownComposerUtils.parseInline(trimLeftSpaces(lines[i])));
    }
    return `<p>${parts.join('<br>')}</p>`;
  }

  private static buildListHtml(items: string[], ordered: boolean): string {
    const tag: string = ordered ? 'ol' : 'ul';
    const parts: string[] = [];
    for (let i: number = 0; i < items.length; i++) {
      parts.push(`<li>${MarkdownComposerUtils.parseInline(items[i])}</li>`);
    }
    return `<${tag}>${parts.join('')}</${tag}>`;
  }

  private static buildCodeHtml(code: string, language: string): string {
    const langClass: string = language.length > 0 ? ` class="lang-${escapeHtmlText(language)}"` : '';
    return `<pre><code${langClass}>${escapeHtmlText(code)}</code></pre>`;
  }

  private static buildImageHtml(line: string): string {
    const imageTag: string = MarkdownComposerUtils.buildPreviewImageTag(line);
    if (imageTag.length === 0) {
      return MarkdownComposerUtils.buildParagraphHtml([line]);
    }
    return `<p>${imageTag}</p>`;
  }

  private static tryBuildHeading(line: string): string {
    const match: RegExpMatchArray | null = line.match(/^(#{1,6})\s+(.+)$/);
    if (match === null || match.length < 3) {
      return '';
    }
    const level: number = match[1].length;
    const content: string = MarkdownComposerUtils.parseInline(match[2]);
    return `<h${level}>${content}</h${level}>`;
  }

  private static isOrderedLine(line: string): boolean {
    return /^\d+\.\s+/.test(line);
  }

  static collectPreviewUploadShortUrls(markdown: string): string[] {
    const source: string = markdown !== undefined && markdown !== null ? markdown.replace(/\r/g, '') : '';
    const urls: string[] = [];
    const regexp: RegExp = /upload:\/\/[^\s)]+/g;
    let matched: RegExpExecArray | null = regexp.exec(source);
    while (matched !== null) {
      const url: string = matched[0] !== undefined && matched[0] !== null ? matched[0].trim() : '';
      if (url.length > 0 && urls.indexOf(url) < 0) {
        urls.push(url);
      }
      matched = regexp.exec(source);
    }
    return urls;
  }

  static collectPreviewStandaloneUrls(markdown: string): string[] {
    const source: string = markdown !== undefined && markdown !== null ? markdown.replace(/\r/g, '') : '';
    const lines: string[] = source.split('\n');
    const urls: string[] = [];
    for (let i: number = 0; i < lines.length; i++) {
      const line: string = lines[i] !== undefined && lines[i] !== null ? lines[i].trim() : '';
      if (line.length === 0) {
        continue;
      }
      const card: MarkdownPreviewLinkCard | null = MarkdownComposerUtils.parseStandaloneLinkCard(line);
      if (card === null) {
        continue;
      }
      const url: string = card.url !== undefined && card.url !== null ? card.url.trim() : '';
      if (url.length > 0 && urls.indexOf(url) < 0) {
        urls.push(url);
      }
    }
    return urls;
  }

  static toPreviewHtml(markdown: string): string {
    const source: string = markdown !== undefined && markdown !== null ? markdown.replace(/\r/g, '') : '';
    if (source.trim().length === 0) {
      return '<p>暂无预览内容</p>';
    }

    const lines: string[] = source.split('\n');
    const blocks: string[] = [];
    const paragraphLines: string[] = [];

    const flushParagraph = (): void => {
      if (paragraphLines.length === 0) {
        return;
      }
      const copy: string[] = [];
      for (let i: number = 0; i < paragraphLines.length; i++) {
        copy.push(paragraphLines[i]);
      }
      blocks.push(MarkdownComposerUtils.buildParagraphHtml(copy));
      paragraphLines.length = 0;
    };

    let index: number = 0;
    while (index < lines.length) {
      const line: string = lines[index];
      const trimmedLine: string = line.trim();

      if (trimmedLine.startsWith('```')) {
        flushParagraph();
        const language: string = trimmedLine.substring(3).trim();
        const codeLines: string[] = [];
        index = index + 1;
        while (index < lines.length && !lines[index].trim().startsWith('```')) {
          codeLines.push(lines[index]);
          index = index + 1;
        }
        blocks.push(MarkdownComposerUtils.buildCodeHtml(codeLines.join('\n'), language));
        index = index + 1;
        continue;
      }

      if (trimmedLine.length === 0) {
        flushParagraph();
        index = index + 1;
        continue;
      }

      const headingHtml: string = MarkdownComposerUtils.tryBuildHeading(trimmedLine);
      if (headingHtml.length > 0) {
        flushParagraph();
        blocks.push(headingHtml);
        index = index + 1;
        continue;
      }

      if (trimmedLine.startsWith('>')) {
        const quotedHeader: string = trimmedLine.replace(/^>\s?/, '');
        const calloutHeader: MarkdownPreviewCallout | null = MarkdownComposerUtils.parseCalloutHeader(quotedHeader);
        if (calloutHeader !== null) {
          flushParagraph();
          index = index + 1;
          const contentLines: string[] = [];
          while (index < lines.length) {
            const nextLine: string = lines[index];
            const nextTrimmed: string = nextLine !== undefined && nextLine !== null ? nextLine.trim() : '';
            if (nextTrimmed.length === 0 || MarkdownComposerUtils.isCalloutBodyBoundary(nextTrimmed)) {
              break;
            }
            if (nextTrimmed.startsWith('>')) {
              contentLines.push(nextLine.replace(/^\s*>\s?/, ''));
            } else {
              contentLines.push(nextLine);
            }
            index = index + 1;
          }
          blocks.push(MarkdownComposerUtils.buildSyntheticCalloutHtml(
            calloutHeader.type,
            calloutHeader.title,
            contentLines.join('\n')
          ));
          continue;
        }

        flushParagraph();
        const quoteLines: string[] = [];
        while (index < lines.length) {
          const currentLine: string = lines[index].trim();
          if (!currentLine.startsWith('>')) {
            break;
          }
          quoteLines.push(currentLine.replace(/^>\s?/, ''));
          index = index + 1;
        }
        blocks.push(`<blockquote>${MarkdownComposerUtils.buildParagraphHtml(quoteLines)}</blockquote>`);
        continue;
      }

      const looseCallout: MarkdownPreviewCallout | null = MarkdownComposerUtils.parseCalloutHeader(trimmedLine);
      if (looseCallout !== null) {
        flushParagraph();
        const contentLines: string[] = [];
        index = index + 1;
        while (index < lines.length) {
          const nextTrimmed: string = lines[index] !== undefined && lines[index] !== null ? lines[index].trim() : '';
          if (nextTrimmed.length === 0 || MarkdownComposerUtils.isCalloutBodyBoundary(nextTrimmed)) {
            break;
          }
          if (nextTrimmed.startsWith('>')) {
            contentLines.push(lines[index].replace(/^\s*>\s?/, ''));
          } else {
            contentLines.push(lines[index]);
          }
          index = index + 1;
        }
        blocks.push(MarkdownComposerUtils.buildSyntheticCalloutHtml(
          looseCallout.type,
          looseCallout.title,
          contentLines.join('\n')
        ));
        continue;
      }

      if (trimmedLine.startsWith('- ') || trimmedLine.startsWith('* ')) {
        flushParagraph();
        const items: string[] = [];
        while (index < lines.length) {
          const currentLine: string = lines[index].trim();
          if (!(currentLine.startsWith('- ') || currentLine.startsWith('* '))) {
            break;
          }
          items.push(currentLine.substring(2).trim());
          index = index + 1;
        }
        blocks.push(MarkdownComposerUtils.buildListHtml(items, false));
        continue;
      }

      if (MarkdownComposerUtils.isOrderedLine(trimmedLine)) {
        flushParagraph();
        const items: string[] = [];
        while (index < lines.length) {
          const currentLine: string = lines[index].trim();
          if (!MarkdownComposerUtils.isOrderedLine(currentLine)) {
            break;
          }
          const dotIndex: number = currentLine.indexOf('.');
          items.push(currentLine.substring(dotIndex + 1).trim());
          index = index + 1;
        }
        blocks.push(MarkdownComposerUtils.buildListHtml(items, true));
        continue;
      }

      const linkCard: MarkdownPreviewLinkCard | null = MarkdownComposerUtils.parseStandaloneLinkCard(trimmedLine);
      if (linkCard !== null) {
        flushParagraph();
        blocks.push(MarkdownComposerUtils.buildPreviewOneboxHtml(linkCard));
        index = index + 1;
        continue;
      }

      if (trimmedLine.toLowerCase() === '[grid]') {
        flushParagraph();
        const gridLines: string[] = [];
        index = index + 1;
        let closed: boolean = false;
        while (index < lines.length) {
          const currentLine: string = lines[index];
          if (currentLine.trim().toLowerCase() === '[/grid]') {
            closed = true;
            index = index + 1;
            break;
          }
          gridLines.push(currentLine);
          index = index + 1;
        }

        if (closed) {
          blocks.push(MarkdownComposerUtils.buildImageGridHtml(gridLines));
          continue;
        }

        paragraphLines.push('[grid]');
        for (let i: number = 0; i < gridLines.length; i++) {
          paragraphLines.push(gridLines[i]);
        }
        continue;
      }

      if (/^!\[[^\]]*\]\([^)]+\)$/.test(trimmedLine)) {
        flushParagraph();
        blocks.push(MarkdownComposerUtils.buildImageHtml(trimmedLine));
        index = index + 1;
        continue;
      }

      paragraphLines.push(line);
      index = index + 1;
    }

    flushParagraph();
    return blocks.join('');
  }
}
