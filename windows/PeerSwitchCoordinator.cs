namespace InputBridge.Protocol;

/// <summary>
/// Experimental serialized active-peer coordinator. A successful release callback
/// MUST mean the receiver acknowledged release, not merely that a write was queued.
/// No current wire protocol acknowledgement exists, so never connect this coordinator
/// to live routing until that protocol is implemented and tested.
/// </summary>
public sealed class PeerSwitchCoordinator
{
    private readonly DeviceRouter router = new();
    private readonly Dictionary<string, Func<CancellationToken, Task<bool>>> release = new(StringComparer.Ordinal);
    private readonly SemaphoreSlim mutex = new(1, 1);

    public async Task AddAsync(string id, Func<CancellationToken, Task<bool>> releaseAcknowledged, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(releaseAcknowledged);
        await mutex.WaitAsync(cancellationToken).ConfigureAwait(false);
        try { router.Add(id); release.Add(id, releaseAcknowledged); }
        finally { mutex.Release(); }
    }

    public async Task<bool> SelectAsync(string? id, CancellationToken cancellationToken)
    {
        await mutex.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (id is not null && !router.Peers.Contains(id)) throw new ArgumentException("Unknown peer", nameof(id));
            string? previous = router.ActivePeer;
            if (previous == id) return true;
            if (previous is not null)
            {
                // Clear destination before awaiting to ensure no new input routes there.
                _ = router.Select(null, _ => true);
                bool acknowledged;
                try { acknowledged = await release[previous](cancellationToken).ConfigureAwait(false); }
                catch { router.Remove(previous); release.Remove(previous); throw; }
                if (!acknowledged) { router.Remove(previous); release.Remove(previous); return false; }
            }
            return router.Select(id, _ => throw new InvalidOperationException("Unexpected active peer"));
        }
        finally { mutex.Release(); }
    }

    public async Task RemoveAsync(string id, CancellationToken cancellationToken)
    {
        await mutex.WaitAsync(cancellationToken).ConfigureAwait(false);
        try { router.Remove(id); release.Remove(id); }
        finally { mutex.Release(); }
    }

    public async Task<string?> DestinationAsync(RemoteInput input, IReadOnlySet<string> clipboardAllowed, CancellationToken cancellationToken)
    {
        await mutex.WaitAsync(cancellationToken).ConfigureAwait(false);
        try { return router.Destination(input, clipboardAllowed); }
        finally { mutex.Release(); }
    }
}
