using System.Net.Security;
using InputBridge.Protocol;

namespace InputBridge.Windows;

/// <summary>
/// Processes one already mutually authenticated stream. Caller must obtain explicit
/// user consent first. Dispatch must execute synchronously on the Windows UI thread,
/// including cleanup; stream closure must never leave injected inputs pressed.
/// </summary>
internal static class SecureInputReceiver
{
    public static async Task RunAsync(SslStream stream, Func<Action, Task> dispatch,
        bool allowClipboard, CancellationToken cancellationToken)
    {
        var sink = new WindowsInputSink();
        var decoder = new FrameDecoder();
        byte[] buffer = new byte[8192];
        try
        {
            while (true)
            {
                int count = await stream.ReadAsync(buffer, cancellationToken).ConfigureAwait(false);
                if (count == 0)
                {
                    decoder.Finish();
                    break;
                }
                IReadOnlyList<Envelope> messages = decoder.Append(buffer.AsSpan(0, count));
                foreach (Envelope envelope in messages)
                {
                    RemoteInput input = InputValidator.Parse(envelope);
                    bool applied = false;
                    await dispatch(() => applied = sink.Apply(input, allowClipboard)).ConfigureAwait(false);
                    if (!applied) throw new InvalidDataException("Input rejected by OS or unsupported");
                }
            }
        }
        finally
        {
            try { await dispatch(sink.ReleaseAll).ConfigureAwait(false); }
            finally { await stream.DisposeAsync().ConfigureAwait(false); }
        }
    }
}
