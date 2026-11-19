using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using InputBridge.Protocol;

namespace InputBridge.Windows;

/// <summary>
/// Passive, opt-in low-level keyboard and mouse hooks. Construct, start, and dispose on
/// the UI thread with a running message pump. Callback must not block. Hooks neither
/// suppress local input nor distinguish hardware from every possible synthetic source.
/// Never activate without explicit consent; never log captured keyboard data.
/// </summary>
internal sealed class WindowsInputCapture : IDisposable
{
    private const int KeyboardHook = 13, MouseHook = 14;
    private readonly Action<RemoteInput> handler;
    private readonly HookProc keyboardCallback;
    private readonly HookProc mouseCallback;
    private nint keyboardHook, mouseHook;
    private bool disposed;

    public WindowsInputCapture(Action<RemoteInput> handler)
    {
        this.handler = handler;
        keyboardCallback = KeyboardCallback;
        mouseCallback = MouseCallback;
    }

    public void Start()
    {
        if (disposed) throw new ObjectDisposedException(nameof(WindowsInputCapture));
        if (keyboardHook != 0 || mouseHook != 0) throw new InvalidOperationException("Capture already active");
        using Process process = Process.GetCurrentProcess();
        using ProcessModule module = process.MainModule ?? throw new InvalidOperationException("Missing process module");
        nint instance = GetModuleHandle(module.ModuleName);
        keyboardHook = SetWindowsHookEx(KeyboardHook, keyboardCallback, instance, 0);
        if (keyboardHook == 0) throw new Win32Exception(Marshal.GetLastWin32Error());
        mouseHook = SetWindowsHookEx(MouseHook, mouseCallback, instance, 0);
        if (mouseHook == 0)
        {
            int error = Marshal.GetLastWin32Error();
            _ = UnhookWindowsHookEx(keyboardHook);
            keyboardHook = 0;
            throw new Win32Exception(error);
        }
    }

    private nint KeyboardCallback(int code, nint message, nint pointer)
    {
        if (code >= 0)
        {
            KeyboardData data = Marshal.PtrToStructure<KeyboardData>(pointer);
            bool injected = (data.Flags & 0x10) != 0;
            int msg = unchecked((int)message);
            bool down = msg is 0x0100 or 0x0104;
            bool up = msg is 0x0101 or 0x0105;
            int scan = (int)data.ScanCode | ((data.Flags & 1) != 0 ? 0x100 : 0);
            if (!injected && (down || up) && WindowsInputSink.UsageForScanCode(scan) is int usage)
                handler(new KeyInput(usage, down));
        }
        return CallNextHookEx(keyboardHook, code, message, pointer);
    }

    private nint MouseCallback(int code, nint message, nint pointer)
    {
        if (code >= 0)
        {
            MouseData data = Marshal.PtrToStructure<MouseData>(pointer);
            if ((data.Flags & 1) == 0)
            {
                int msg = unchecked((int)message);
                switch (msg)
                {
                    case 0x0200:
                        int width = GetSystemMetrics(0), height = GetSystemMetrics(1);
                        if (width > 1 && height > 1 && data.Point.X >= 0 && data.Point.Y >= 0 && data.Point.X < width && data.Point.Y < height)
                            handler(new PointerInput((double)data.Point.X / (width - 1), (double)data.Point.Y / (height - 1)));
                        break;
                    case 0x0201: handler(new ButtonInput(0, true)); break;
                    case 0x0202: handler(new ButtonInput(0, false)); break;
                    case 0x0204: handler(new ButtonInput(1, true)); break;
                    case 0x0205: handler(new ButtonInput(1, false)); break;
                    case 0x020A: handler(new ScrollInput(unchecked((short)(data.Mouse >> 16)) / 120, 0)); break;
                    case 0x020E: handler(new ScrollInput(0, unchecked((short)(data.Mouse >> 16)) / 120)); break;
                }
            }
        }
        return CallNextHookEx(mouseHook, code, message, pointer);
    }

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        if (keyboardHook != 0) _ = UnhookWindowsHookEx(keyboardHook);
        if (mouseHook != 0) _ = UnhookWindowsHookEx(mouseHook);
        keyboardHook = mouseHook = 0;
    }

    private delegate nint HookProc(int code, nint wParam, nint lParam);
    [StructLayout(LayoutKind.Sequential)] private struct Point { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] private struct MouseData { public Point Point; public uint Mouse, Flags, Time; public nint ExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] private struct KeyboardData { public uint VirtualKey, ScanCode, Flags, Time; public nint ExtraInfo; }
    [DllImport("user32.dll", SetLastError = true)] private static extern nint SetWindowsHookEx(int id, HookProc callback, nint module, uint threadId);
    [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool UnhookWindowsHookEx(nint hook);
    [DllImport("user32.dll")] private static extern nint CallNextHookEx(nint hook, int code, nint wParam, nint lParam);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern nint GetModuleHandle(string moduleName);
    [DllImport("user32.dll")] private static extern int GetSystemMetrics(int index);
}
