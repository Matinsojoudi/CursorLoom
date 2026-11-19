namespace InputBridge.Protocol;

/// <summary>Pure authorization state; does not establish a connection.</summary>
public sealed class SessionState
{
    public enum Phase { Stopped, Connecting, Connected, Sharing }
    public Phase Current { get; private set; } = Phase.Stopped;
    public bool ClipboardEnabled { get; private set; }

    public void BeginConnection()
    {
        if (Current != Phase.Stopped) throw new InvalidOperationException("Invalid transition");
        Current = Phase.Connecting;
    }

    public void Authenticated()
    {
        if (Current != Phase.Connecting) throw new InvalidOperationException("Invalid transition");
        Current = Phase.Connected;
    }

    public void BeginSharing(bool consent, bool clipboard)
    {
        if (Current != Phase.Connected) throw new InvalidOperationException("Invalid transition");
        if (!consent) throw new UnauthorizedAccessException("Explicit consent required");
        ClipboardEnabled = clipboard;
        Current = Phase.Sharing;
    }

    public bool Permits(RemoteInput input) => Current == Phase.Sharing &&
        (input is not ClipboardInput || ClipboardEnabled);

    public void StopSharing()
    {
        if (Current == Phase.Sharing) Current = Phase.Connected;
        ClipboardEnabled = false;
    }

    public void Disconnect()
    {
        ClipboardEnabled = false;
        Current = Phase.Stopped;
    }
}
