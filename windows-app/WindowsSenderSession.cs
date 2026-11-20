using System.Threading.Channels;
using InputBridge.Protocol;

namespace InputBridge.Windows;

/// <summary>
/// Bounded single-target sender pump. The owner must obtain consent before invoking
/// Start and must stop capture on completion/failure. This class is not connected to UI.
/// </summary>
internal sealed class WindowsSenderSession
{
    private readonly SecureSender sender;
    private readonly Channel<RemoteInput> queue = Channel.CreateBounded<RemoteInput>(new BoundedChannelOptions(512)
    {
        SingleReader = true,
        SingleWriter = false,
        FullMode = BoundedChannelFullMode.Wait
    });
    private int stopped;
    private readonly CancellationTokenSource abort = new();

    public WindowsSenderSession(SecureSender sender) => this.sender = sender;

    /// <summary>Never blocks a low-level input hook; queue overflow fails closed.</summary>
    public bool Offer(RemoteInput input)
    {
        if (Volatile.Read(ref stopped) != 0) return false;
        if (queue.Writer.TryWrite(input)) return true;
        Abort(new InvalidOperationException("Input queue overflow"));
        return false;
    }

    public void Abort(Exception? error = null)
    {
        if (Interlocked.Exchange(ref stopped, 1) == 0)
        {
            queue.Writer.TryComplete(error);
            abort.Cancel();
        }
    }

    private async Task SendQueuedAsync(CancellationToken cancellationToken)
    {
        await foreach (RemoteInput input in queue.Reader.ReadAllAsync(cancellationToken).ConfigureAwait(false))
            await sender.SendAsync(InputEncoding.Encode(input), cancellationToken).ConfigureAwait(false);
    }

    /// <summary>The caller must immediately stop local capture if this task completes.</summary>
    public async Task RunAsync(CancellationToken cancellationToken)
    {
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, abort.Token);
        Task monitor = sender.MonitorPeerAsync(linked.Token);
        Task sending = SendQueuedAsync(linked.Token);
        try
        {
            Task completed = await Task.WhenAny(monitor, sending).ConfigureAwait(false);
            await completed.ConfigureAwait(false);
        }
        finally
        {
            Abort();
            await sender.DisposeAsync().ConfigureAwait(false);
            try { await Task.WhenAll(monitor, sending).ConfigureAwait(false); }
            catch (Exception error) when (error is OperationCanceledException or IOException or ObjectDisposedException) { }
        }
    }
}
