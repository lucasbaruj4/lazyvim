using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Forms;

// Persistent background listener: registers several system-wide hotkeys
// (work no matter which app has focus -- browser, Alacritty, anything),
// replacing what used to be local-only Alacritty keybindings:
//   Shift+S            -> snip-style region-select screenshot
//   Ctrl+Alt+Up/Down    -> volume up/down
//   Ctrl+Shift+M        -> mute toggle
//   Alt+1 / Alt+2       -> focus Alacritty / Brave
// It also installs a low-level keyboard hook that swallows Alt+Tab, so app
// switching only ever happens through Alt+1 / Alt+2. Alt+Tab's switcher UI is
// part of explorer.exe, which this machine doesn't run, so leaving it enabled
// produces half-drawn/ghost windows.
class HotkeyListener : Form {
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr pid);
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

    const uint SWP_NOSIZE = 0x0001;
    const uint SWP_NOMOVE = 0x0002;
    const uint SWP_NOACTIVATE = 0x0010;

    [DllImport("user32.dll")] static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr hhk);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandle(string lpModuleName);

    delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    const int WH_KEYBOARD_LL = 13;
    const int WM_KEYDOWN = 0x0100;
    const int WM_SYSKEYDOWN = 0x0104;
    const int WM_KEYUP = 0x0101;
    const int WM_SYSKEYUP = 0x0105;
    const uint LLKHF_ALTDOWN = 0x20;
    const uint VK_TAB = 0x09;

    const uint MOD_ALT = 0x0001;
    const uint MOD_CONTROL = 0x0002;
    const uint MOD_SHIFT = 0x0004;
    const uint VK_UP = 0x26;
    const uint VK_DOWN = 0x28;
    const uint VK_S = 0x53;
    const uint VK_M = 0x4D;
    const uint VK_1 = 0x31;
    const uint VK_2 = 0x32;
    const int WM_HOTKEY = 0x0312;
    const int SW_RESTORE = 9;

    const int ID_SCREENSHOT = 1;
    const int ID_VOL_UP = 2;
    const int ID_VOL_DOWN = 3;
    const int ID_MUTE = 4;
    const int ID_FOCUS_TERM = 5;
    const int ID_FOCUS_BRAVE = 6;

    const string AUDIO_EXE = @"C:\Users\Admin\AppData\Local\AudioCtl.exe";
    const string BRAVE_EXE = @"C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe";

    // Kept in a field so the delegate isn't garbage-collected while the hook
    // is installed -- otherwise the callback address goes stale and the hook
    // silently dies.
    static LowLevelKeyboardProc hookProc;
    static IntPtr hookHandle = IntPtr.Zero;

    static readonly IntPtr HWND_TOP = IntPtr.Zero;
    static readonly IntPtr HWND_BOTTOM = new IntPtr(1);

    public HotkeyListener() {
        this.ShowInTaskbar = false;
        this.Opacity = 0;
        this.FormBorderStyle = FormBorderStyle.FixedToolWindow;
        this.StartPosition = FormStartPosition.Manual;
        this.Bounds = new Rectangle(-2000, -2000, 1, 1);
    }

    protected override void OnLoad(EventArgs e) {
        base.OnLoad(e);
        this.Hide();
        RegisterHotKey(this.Handle, ID_SCREENSHOT, MOD_SHIFT, VK_S);
        RegisterHotKey(this.Handle, ID_VOL_UP, MOD_CONTROL | MOD_ALT, VK_UP);
        RegisterHotKey(this.Handle, ID_VOL_DOWN, MOD_CONTROL | MOD_ALT, VK_DOWN);
        RegisterHotKey(this.Handle, ID_MUTE, MOD_CONTROL | MOD_SHIFT, VK_M);
        RegisterHotKey(this.Handle, ID_FOCUS_TERM, MOD_ALT, VK_1);
        RegisterHotKey(this.Handle, ID_FOCUS_BRAVE, MOD_ALT, VK_2);

        hookProc = AltTabBlocker;
        hookHandle = SetWindowsHookEx(WH_KEYBOARD_LL, hookProc, GetModuleHandle(null), 0);
    }

    // Swallows Tab (and Shift+Tab) while Alt is held, in both directions, so
    // no app ever sees an Alt+Tab keystroke.
    static IntPtr AltTabBlocker(int nCode, IntPtr wParam, IntPtr lParam) {
        if (nCode >= 0) {
            int msg = wParam.ToInt32();
            if (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN || msg == WM_KEYUP || msg == WM_SYSKEYUP) {
                uint vk = (uint)Marshal.ReadInt32(lParam, 0);
                uint flags = (uint)Marshal.ReadInt32(lParam, 8);
                if (vk == VK_TAB && (flags & LLKHF_ALTDOWN) != 0) {
                    return (IntPtr)1;
                }
            }
        }
        return CallNextHookEx(hookHandle, nCode, wParam, lParam);
    }

    // Alacritty is semi-transparent, so whatever sits directly beneath it in
    // z-order shows through -- without this you see Brave through the
    // terminal instead of the wallpaper.
    //
    // The wallpaper window can't simply be lifted above Brave: it rewrites
    // every z-order change of its own to HWND_BOTTOM (see the WM_WINDOWPOSCHANGING
    // handler in wallpaper-window.ps1), deliberately, so it can never float
    // over the browser. So push Brave to the bottom instead -- below the
    // wallpaper -- which leaves the wallpaper as the thing behind the terminal.
    // Alt+2 raises Brave back out of the basement.
    //
    // Done before activating the terminal, not after: sinking Brave doesn't
    // depend on where the terminal has got to, so there's nothing to wait for,
    // and waiting is exactly what made the switch flash Brave first.
    void SendBraveToBack() {
        foreach (Process p in Process.GetProcessesByName("brave")) {
            if (p.MainWindowHandle != IntPtr.Zero) {
                SetWindowPos(p.MainWindowHandle, HWND_BOTTOM, 0, 0, 0, 0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
                return;
            }
        }
    }

    void FocusProcess(string processName, string launchPath) {
        IntPtr target = IntPtr.Zero;
        foreach (Process p in Process.GetProcessesByName(processName)) {
            if (p.MainWindowHandle != IntPtr.Zero) {
                target = p.MainWindowHandle;
                break;
            }
        }

        if (target == IntPtr.Zero) {
            if (launchPath != null) {
                var psi = new ProcessStartInfo(launchPath);
                psi.UseShellExecute = true;
                try { Process.Start(psi); } catch { }
            }
            return;
        }

        if (IsIconic(target)) {
            ShowWindow(target, SW_RESTORE);
        }

        // Plain SetForegroundWindow is refused when the caller doesn't own the
        // foreground; attaching to the current foreground thread's input queue
        // lifts that restriction.
        uint fgThread = GetWindowThreadProcessId(GetForegroundWindow(), IntPtr.Zero);
        uint thisThread = GetCurrentThreadId();
        bool attached = fgThread != thisThread && AttachThreadInput(fgThread, thisThread, true);
        SetForegroundWindow(target);
        // Activation alone doesn't reorder the stack, so raise it explicitly.
        BringWindowToTop(target);
        SetWindowPos(target, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        if (attached) {
            AttachThreadInput(fgThread, thisThread, false);
        }
    }

    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_HOTKEY) {
            switch (m.WParam.ToInt32()) {
                case ID_SCREENSHOT: TakeSnip(); break;
                case ID_VOL_UP: RunAudioCtl("up"); break;
                case ID_VOL_DOWN: RunAudioCtl("down"); break;
                case ID_MUTE: RunAudioCtl("toggle"); break;
                case ID_FOCUS_TERM: SendBraveToBack(); FocusProcess("alacritty", null); break;
                case ID_FOCUS_BRAVE: FocusProcess("brave", BRAVE_EXE); break;
            }
        }
        base.WndProc(ref m);
    }

    void RunAudioCtl(string action) {
        var psi = new ProcessStartInfo(AUDIO_EXE, action);
        psi.CreateNoWindow = true;
        psi.UseShellExecute = false;
        Process.Start(psi);
    }

    void TakeSnip() {
        Rectangle bounds = Screen.PrimaryScreen.Bounds;
        Bitmap full = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(full)) {
            g.CopyFromScreen(bounds.Location, Point.Empty, bounds.Size);
        }

        using (var overlay = new SnipOverlay(full, bounds)) {
            overlay.ShowDialog();
        }
        full.Dispose();
    }

    protected override void Dispose(bool disposing) {
        UnregisterHotKey(this.Handle, ID_SCREENSHOT);
        UnregisterHotKey(this.Handle, ID_VOL_UP);
        UnregisterHotKey(this.Handle, ID_VOL_DOWN);
        UnregisterHotKey(this.Handle, ID_MUTE);
        UnregisterHotKey(this.Handle, ID_FOCUS_TERM);
        UnregisterHotKey(this.Handle, ID_FOCUS_BRAVE);
        if (hookHandle != IntPtr.Zero) {
            UnhookWindowsHookEx(hookHandle);
            hookHandle = IntPtr.Zero;
        }
        base.Dispose(disposing);
    }

    [STAThread]
    static void Main() {
        Application.EnableVisualStyles();
        Application.Run(new HotkeyListener());
    }
}

class SnipOverlay : Form {
    Bitmap fullImage;
    Point start;
    Rectangle selection;
    bool selecting = false;

    public SnipOverlay(Bitmap full, Rectangle bounds) {
        fullImage = full;
        this.FormBorderStyle = FormBorderStyle.None;
        this.Bounds = bounds;
        this.StartPosition = FormStartPosition.Manual;
        this.TopMost = true;
        this.Cursor = Cursors.Cross;
        this.DoubleBuffered = true;
        this.KeyPreview = true;
        this.BackgroundImage = full;
        this.BackgroundImageLayout = ImageLayout.None;
        this.ShowInTaskbar = false;
    }

    protected override void OnShown(EventArgs e) {
        base.OnShown(e);
        this.Activate();
        this.Focus();
    }

    protected override void OnMouseDown(MouseEventArgs e) {
        selecting = true;
        start = e.Location;
        selection = new Rectangle(start, Size.Empty);
        Invalidate();
    }

    protected override void OnMouseMove(MouseEventArgs e) {
        if (selecting) {
            int x = Math.Min(start.X, e.X);
            int y = Math.Min(start.Y, e.Y);
            int w = Math.Abs(e.X - start.X);
            int h = Math.Abs(e.Y - start.Y);
            selection = new Rectangle(x, y, w, h);
            Invalidate();
        }
    }

    protected override void OnMouseUp(MouseEventArgs e) {
        selecting = false;
        if (selection.Width > 2 && selection.Height > 2) {
            CopySelectionToClipboard();
        }
        this.Close();
    }

    protected override void OnKeyDown(KeyEventArgs e) {
        if (e.KeyCode == Keys.Escape) {
            this.Close();
        }
    }

    protected override void OnPaint(PaintEventArgs e) {
        base.OnPaint(e);
        using (var dim = new SolidBrush(Color.FromArgb(120, 0, 0, 0))) {
            using (Region r = new Region(this.ClientRectangle)) {
                if (selection.Width > 0 && selection.Height > 0) {
                    r.Exclude(selection);
                }
                e.Graphics.FillRegion(dim, r);
            }
        }
        if (selection.Width > 0 && selection.Height > 0) {
            using (var pen = new Pen(Color.DeepSkyBlue, 2)) {
                e.Graphics.DrawRectangle(pen, selection);
            }
        }
    }

    void CopySelectionToClipboard() {
        using (Bitmap cropped = fullImage.Clone(selection, fullImage.PixelFormat)) {
            Clipboard.SetImage(cropped);
        }
    }
}
