using System.Text.Json;

namespace InputBridge.Protocol;

/// <summary>Draft capability message; existing sessions do not negotiate it.</summary>
public sealed record ProtocolCapabilities(bool ReleaseAcknowledgements)
{
    public Envelope Envelope() => new(1, "capabilities", new() { ["releaseAck"] = JsonSerializer.SerializeToElement(ReleaseAcknowledgements) });
    public static ProtocolCapabilities Parse(Envelope message)
    {
        if (message.Version != 1 || message.Type != "capabilities" || message.Payload.Count != 1 ||
            !message.Payload.TryGetValue("releaseAck", out JsonElement value) ||
            value.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
            throw new InvalidDataException("Invalid capabilities");
        return new ProtocolCapabilities(value.GetBoolean());
    }
    public bool SupportsReleaseWith(ProtocolCapabilities peer) => ReleaseAcknowledgements && peer.ReleaseAcknowledgements;
}
