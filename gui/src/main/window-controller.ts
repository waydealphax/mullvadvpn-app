import { BrowserWindow, Display, screen, Tray, WebContents } from 'electron';
import os from 'os';
import { IWindowShapeParameters } from '../shared/ipc-types';
import { Scheduler } from '../shared/scheduler';
import { IpcMainEventChannel } from './ipc-event-channel';

interface IPosition {
  x: number;
  y: number;
}

interface IWindowPositioning {
  getPosition(window: BrowserWindow): IPosition;
  getWindowShapeParameters(window: BrowserWindow): IWindowShapeParameters;
}

// Tray applications are positioned aproximately 10px from the tray in Windows 11. Windows 11 has
// the internal version 10.0.22000+.
const MARGIN =
  process.platform === 'win32' && parseInt(os.release().split('.').at(-1)!) >= 22000 ? 10 : 0;

class StandaloneWindowPositioning implements IWindowPositioning {
  public getPosition(window: BrowserWindow): IPosition {
    const windowBounds = window.getBounds();

    const primaryDisplay = screen.getPrimaryDisplay();
    const workArea = primaryDisplay.workArea;
    const maxX = workArea.x + workArea.width - windowBounds.width;
    const maxY = workArea.y + workArea.height - windowBounds.height;

    const x = Math.min(Math.max(windowBounds.x, workArea.x), maxX);
    const y = Math.min(Math.max(windowBounds.y, workArea.y), maxY);

    return { x, y };
  }

  public getWindowShapeParameters(_window: BrowserWindow): IWindowShapeParameters {
    return {};
  }
}

class AttachedToTrayWindowPositioning implements IWindowPositioning {
  private tray: Tray;

  constructor(tray: Tray) {
    this.tray = tray;
  }

  public getPosition(window: BrowserWindow): IPosition {
    const windowBounds = window.getBounds();
    const trayBounds = this.tray.getBounds();

    const activeDisplay = screen.getDisplayNearestPoint({
      x: trayBounds.x,
      y: trayBounds.y,
    });
    const workArea = activeDisplay.workArea;
    const placement = this.getTrayPlacement();
    const maxX = workArea.x + workArea.width - windowBounds.width;
    const maxY = workArea.y + workArea.height - windowBounds.height;

    let x = 0;
    let y = 0;

    switch (placement) {
      case 'top':
        x = trayBounds.x + (trayBounds.width - windowBounds.width) * 0.5;
        y = workArea.y + MARGIN;
        break;

      case 'bottom':
        x = trayBounds.x + (trayBounds.width - windowBounds.width) * 0.5;
        y = workArea.y + workArea.height - windowBounds.height - MARGIN;
        break;

      case 'left':
        x = workArea.x + MARGIN;
        y = trayBounds.y + (trayBounds.height - windowBounds.height) * 0.5;
        break;

      case 'right':
        x = workArea.width - windowBounds.width - MARGIN;
        y = trayBounds.y + (trayBounds.height - windowBounds.height) * 0.5;
        break;

      case 'none':
        x = workArea.x + (workArea.width - windowBounds.width) * 0.5;
        y = workArea.y + (workArea.height - windowBounds.height) * 0.5;
        break;
    }

    x = Math.min(Math.max(x, workArea.x), maxX);
    y = Math.min(Math.max(y, workArea.y), maxY);

    return {
      x: Math.round(x),
      y: Math.round(y),
    };
  }

  public getWindowShapeParameters(window: BrowserWindow): IWindowShapeParameters {
    const trayBounds = this.tray.getBounds();
    const windowBounds = window.getBounds();
    const arrowPosition = trayBounds.x - windowBounds.x + trayBounds.width * 0.5;
    return {
      arrowPosition,
    };
  }

  private getTrayPlacement() {
    switch (process.platform) {
      case 'darwin':
        // macOS has menubar always placed at the top
        return 'top';

      case 'win32': {
        // taskbar occupies some part of the screen excluded from work area
        const primaryDisplay = screen.getPrimaryDisplay();
        const displaySize = primaryDisplay.size;
        const workArea = primaryDisplay.workArea;

        if (workArea.width < displaySize.width) {
          return workArea.x > 0 ? 'left' : 'right';
        } else if (workArea.height < displaySize.height) {
          return workArea.y > 0 ? 'top' : 'bottom';
        } else {
          return 'none';
        }
      }

      default:
        return 'none';
    }
  }
}

export default class WindowController {
  private width: number;
  private height: number;
  private windowValue: BrowserWindow;
  private webContentsValue: WebContents;
  private windowPositioning: IWindowPositioning;

  private windowPositioningScheduler = new Scheduler();

  get window(): BrowserWindow | undefined {
    return this.windowValue.isDestroyed() ? undefined : this.windowValue;
  }

  get webContents(): WebContents | undefined {
    return this.webContentsValue.isDestroyed() ? undefined : this.webContentsValue;
  }

  constructor(windowValue: BrowserWindow, private tray: Tray, unpinnedWindow: boolean) {
    const [width, height] = windowValue.getSize();
    this.width = width;
    this.height = height;
    this.windowValue = windowValue;
    this.webContentsValue = windowValue.webContents;
    this.windowPositioning = unpinnedWindow
      ? new StandaloneWindowPositioning()
      : new AttachedToTrayWindowPositioning(tray);

    this.installDisplayMetricsHandler();
    this.installHideHandler();
  }

  public replaceWindow(windowValue: BrowserWindow, unpinnedWindow: boolean) {
    this.window?.destroy();

    const [width, height] = windowValue.getSize();
    this.width = width;
    this.height = height;
    this.windowValue = windowValue;
    this.webContentsValue = windowValue.webContents;

    this.windowPositioning = unpinnedWindow
      ? new StandaloneWindowPositioning()
      : new AttachedToTrayWindowPositioning(this.tray);

    this.installDisplayMetricsHandler();
    this.installHideHandler();
    this.updatePosition();
  }

  public show(whenReady = true) {
    if (whenReady) {
      this.executeWhenWindowIsReady(() => this.showImmediately());
    } else {
      this.showImmediately();
    }
  }

  public hide() {
    this.window?.hide();
  }

  public toggle() {
    if (this.window?.isVisible()) {
      this.hide();
    } else {
      this.show();
    }
  }

  public isVisible(): boolean {
    return this.window?.isVisible() ?? false;
  }

  public updatePosition() {
    if (this.window) {
      const { x, y } = this.windowPositioning.getPosition(this.window);
      this.window.setPosition(x, y, false);
    }

    this.notifyUpdateWindowShape();
  }

  private installHideHandler() {
    this.window?.addListener('hide', () => this.windowPositioningScheduler.cancel());
    this.window?.addListener('closed', () => this.windowPositioningScheduler.cancel());
  }

  private showImmediately() {
    const window = this.window;

    // When running with unpinned window on Windows there's a bug that causes the app to become
    // wider if opened from minimized if the updated position is set before the window is opened.
    // Unfortunately the order can't always be changed since this would cause the Window to "jump"
    // in other scenarios.
    if (
      process.platform === 'win32' &&
      this.windowPositioning instanceof StandaloneWindowPositioning
    ) {
      window?.show();
      window?.focus();

      this.updatePosition();
    } else {
      this.updatePosition();

      window?.show();
      window?.focus();
    }
  }

  private notifyUpdateWindowShape() {
    if (this.window) {
      const shapeParameters = this.windowPositioning.getWindowShapeParameters(this.window);

      IpcMainEventChannel.window.notifyShape(this.webContentsValue, shapeParameters);
    }
  }

  // Installs display event handlers to update the window position on any changes in the display or
  // workarea dimensions.
  private installDisplayMetricsHandler() {
    if (this.window) {
      screen.addListener('display-metrics-changed', this.onDisplayMetricsChanged);
      this.window.once('closed', () => {
        screen.removeListener('display-metrics-changed', this.onDisplayMetricsChanged);
      });
    }
  }

  private onDisplayMetricsChanged = (
    _event: Electron.Event,
    _display: Display,
    changedMetrics: string[],
  ) => {
    if (changedMetrics.includes('workArea') && this.window?.isVisible()) {
      this.onWorkAreaSizeChange();
      if (process.platform === 'win32') {
        this.windowPositioningScheduler.schedule(() => this.onWorkAreaSizeChange(), 500);
      }
    }

    // On linux, the window won't be properly rescaled back to it's original
    // size if the DPI scaling factor is changed.
    // https://github.com/electron/electron/issues/11050
    if (process.platform === 'linux' && changedMetrics.includes('scaleFactor')) {
      this.forceResizeWindow();
    }
  };

  private onWorkAreaSizeChange() {
    this.updatePosition();
  }

  private forceResizeWindow() {
    this.window?.setSize(this.width, this.height);
  }

  private executeWhenWindowIsReady(closure: () => void) {
    if (this.webContents?.isLoading() === false && this.webContents?.getURL() !== '') {
      closure();
    } else {
      this.webContents?.once('did-stop-loading', () => {
        closure();
      });
    }
  }
}
