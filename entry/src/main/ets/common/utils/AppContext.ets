import { common } from '@kit.AbilityKit';

/**
 * 全局 UIAbilityContext 持有者
 *
 * 说明：
 * - 用于在页面/服务层调用系统能力（分享、打开浏览器等）
 * - 由 EntryAbility 初始化写入
 */
export class AppContext {
  private static uiAbilityContext: common.UIAbilityContext | null = null;
  private static debugMode: boolean = false;
  private static appForeground: boolean = true;
  private static appForegroundListeners: ((isForeground: boolean) => void)[] = [];

  static setUIAbilityContext(ctx: common.UIAbilityContext): void {
    AppContext.uiAbilityContext = ctx;
    try {
      AppContext.debugMode = ctx.applicationInfo.debug;
    } catch (_) {
      AppContext.debugMode = false;
    }
  }

  static getUIAbilityContext(): common.UIAbilityContext | null {
    return AppContext.uiAbilityContext;
  }

  static isDebugMode(): boolean {
    return AppContext.debugMode;
  }

  static isAppForeground(): boolean {
    return AppContext.appForeground;
  }

  static setAppForeground(isForeground: boolean): void {
    if (AppContext.appForeground === isForeground) {
      return;
    }
    AppContext.appForeground = isForeground;
    const listeners: ((isForeground: boolean) => void)[] = [...AppContext.appForegroundListeners];
    setTimeout(() => {
      for (let i = 0; i < listeners.length; i++) {
        try {
          listeners[i](isForeground);
        } catch (_) {
        }
      }
    }, 0);
  }

  static addAppForegroundListener(listener: (isForeground: boolean) => void): void {
    for (let i = 0; i < AppContext.appForegroundListeners.length; i++) {
      if (AppContext.appForegroundListeners[i] === listener) {
        return;
      }
    }
    AppContext.appForegroundListeners.push(listener);
  }

  static removeAppForegroundListener(listener: (isForeground: boolean) => void): void {
    const next: ((isForeground: boolean) => void)[] = [];
    for (let i = 0; i < AppContext.appForegroundListeners.length; i++) {
      if (AppContext.appForegroundListeners[i] !== listener) {
        next.push(AppContext.appForegroundListeners[i]);
      }
    }
    AppContext.appForegroundListeners = next;
  }
}
