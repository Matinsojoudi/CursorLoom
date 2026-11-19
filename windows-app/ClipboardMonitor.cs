namespace InputBridge.Windows;

/// <summary>
/// Explicit UI-thread clipboard listener. Caller must opt in, dispose on disconnect,
/// and avoid logging or persisting the text. Remote writes are marked to suppress echo.
/// </summary>
internal sealed class ClipboardMonitor : NativeWindow, IDisposable
{
    private const int ClipboardUpdate = 0x031D;
    private readonly Action<string> onText;
    private uint ignoredSequence;
    private bool disposed;

    public ClipboardMonitor(Action<string> onText)
    {
        this.onText = onText;
        CreateHandle(new CreateParams());
        if (!AddClipboardFormatListener(Handle))
        {
            DestroyHandle();
            throw new System.ComponentModel.Win32Exception(System.Runtime.InteropServices.Marshal.GetLastWin32Error());
        }
    }

    public bool ApplyRemote(string text)
    {
        if (disposed || System.Text.Encoding.UTF8.GetByteCount(text) > 48_000) return false;
        try
        {
            if (text.Length == 0) Clipboard.Clear(); else Clipboard.SetText(text);
            ignoredSequence = GetClipboardSequenceNumber();
            return true;
        }
        catch (System.Runtime.InteropServices.ExternalException) { return false; }
    }

    protected override void WndProc(ref Message message)
    {
        if (message.Msg == ClipboardUpdate && !disposed)
        {
            uint sequence = GetClipboardSequenceNumber();
            if (sequence != ignoredSequence)
            {
                try
                {
                    if (Clipboard.ContainsText())
                    {
                        string text = Clipboard.GetText();
                        if (System.Text.Encoding.UTF8.GetByteCount(text) <= 48_000) onText(text);
                    }
                }
                catch (System.Runtime.InteropServices.ExternalException) { /* Clipboard temporarily locked. */ }
            }
        }
        base.WndProc(ref message);
    }

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        _ = RemoveClipboardFormatListener(Handle);
        DestroyHandle();
    }

    [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
    private static extern bool AddClipboardFormatListener(nint hwnd);
    [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
    private static extern bool RemoveClipboardFormatListener(nint hwnd);
    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern uint GetClipboardSequenceNumber();
}
