namespace InputBridge.Protocol;

/// <summary>Tracks one acknowledgement; owner serializes access and enforces timeout.</summary>
public sealed class ReleaseTracker
{
    public string? PendingId { get; private set; }

    public Envelope Begin(string id)
    {
        if (PendingId is not null) throw new InvalidOperationException("Release already pending");
        Envelope request = ReleaseAcknowledgement.Request(id);
        PendingId = id;
        return request;
    }

    public void Complete(Envelope message)
    {
        string expected = PendingId ?? throw new InvalidOperationException("No release pending");
        PendingId = null; // malformed or mismatched responses also fail closed
        var response = ReleaseAcknowledgement.ParseResponse(message);
        if (!string.Equals(expected, response.Id, StringComparison.OrdinalIgnoreCase) || !response.Accepted)
            throw new InvalidDataException("Release acknowledgement mismatch or failure");
    }

    public void Cancel() => PendingId = null;
}
