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

export class MarkdownComposerUtils {
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
    return MarkdownComposerUtils.appendInlineToken(text, '😊');
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

  private static sanitizeUrl(url: string): string {
    const raw: string = url !== undefined && url !== null ? url.trim() : '';
    if (raw.length === 0) {
      return '';
    }
    if (raw.startsWith('http://') || raw.startsWith('https://') || raw.startsWith('/')) {
      return escapeHtmlText(raw);
    }
    return '';
  }

  private static parseInline(markdown: string): string {
    let html: string = escapeHtmlText(markdown !== undefined && markdown !== null ? markdown : '');
    html = html.replace(/`([^`]+)`/g, '<code>$1</code>');
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
    const match: RegExpMatchArray | null = line.match(/^!\[([^\]]*)\]\(([^)]+)\)$/);
    if (match === null || match.length < 3) {
      return MarkdownComposerUtils.buildParagraphHtml([line]);
    }
    const alt: string = escapeHtmlText(match[1]);
    const safeUrl: string = MarkdownComposerUtils.sanitizeUrl(match[2]);
    if (safeUrl.length === 0) {
      return MarkdownComposerUtils.buildParagraphHtml([line]);
    }
    return `<p><img src="${safeUrl}" alt="${alt}"></p>`;
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
