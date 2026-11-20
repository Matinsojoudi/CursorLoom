namespace InputBridge.Protocol;

/// <summary>
/// Pure single-active-target routing state. Transport owners must execute effects in
/// order, stop local capture on any error, and disconnect on release failure.
/// Not thread-safe: serialize all operations on the controlling UI thread.
/// </summary>
public sealed class DeviceRouter
{
    public const int MaximumPeers = 4;
    private readonly HashSet<string> peers = new(StringComparer.Ordinal);
    public string? ActivePeer { get; private set; }
    public IReadOnlyCollection<string> Peers => Array.AsReadOnly(peers.ToArray());

    public void Add(string peer)
    {
        if (string.IsNullOrWhiteSpace(peer) || peer.Length > 128) throw new ArgumentException("Invalid peer ID", nameof(peer));
        if (peers.Contains(peer)) throw new InvalidOperationException("Duplicate peer ID");
        if (peers.Count >= MaximumPeers) throw new InvalidOperationException("Peer limit reached");
        peers.Add(peer);
    }

    /// <summary>
    /// Release prior peer before selecting a new one. On failed release, remove prior
    /// peer and leave local input active; never activate the new target in that call.
    /// </summary>
    public bool Select(string? next, Func<string, bool> release)
    {
        if (next is not null && !peers.Contains(next)) throw new ArgumentException("Unknown peer", nameof(next));
        string? previous = ActivePeer;
        if (previous == next) return true;
        ActivePeer = null;
        if (previous is not null)
        {
            bool released;
            try { released = release(previous); }
            catch { peers.Remove(previous); throw; }
            if (!released) { peers.Remove(previous); return false; }
        }
        ActivePeer = next;
        return true;
    }

    /// <summary>Only the active peer receives input; clipboard needs a separate grant.</summary>
    public string? Destination(RemoteInput input, IReadOnlySet<string> clipboardAllowed)
    {
        if (ActivePeer is null) return null;
        if (input is ClipboardInput && !clipboardAllowed.Contains(ActivePeer)) return null;
        return ActivePeer;
    }

    /// <summary>Call on disconnect; local input becomes active if this was selected.</summary>
    public void Remove(string peer)
    {
        peers.Remove(peer);
        if (ActivePeer == peer) ActivePeer = null;
    }
}
