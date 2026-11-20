using System.Text.Json;

namespace InputBridge.Protocol;

/// <summary>Draft extension only; existing peers do not support these messages.</summary>
public static class ReleaseAcknowledgement
{
    public static Envelope Request(string id)
    {
        ValidateId(id);
        return new Envelope(1, "releaseRequest", new() { ["id"] = JsonSerializer.SerializeToElement(id) });
    }
    public static Envelope Response(string id, bool accepted)
    {
        ValidateId(id);
        return new Envelope(1, "releaseAck", new() { ["id"] = JsonSerializer.SerializeToElement(id), ["accepted"] = JsonSerializer.SerializeToElement(accepted) });
    }
    public static string ParseRequest(Envelope message)
    {
        if (message.Version != 1 || message.Type != "releaseRequest" || message.Payload.Count != 1 ||
            !message.Payload.TryGetValue("id", out JsonElement id) || id.ValueKind != JsonValueKind.String)
            throw new InvalidDataException("Invalid release request");
        string value = id.GetString() ?? throw new InvalidDataException("Invalid ID");
        ValidateId(value);
        return value;
    }
    public static (string Id, bool Accepted) ParseResponse(Envelope message)
    {
        if (message.Version != 1 || message.Type != "releaseAck" || message.Payload.Count != 2 ||
            !message.Payload.TryGetValue("id", out JsonElement id) || id.ValueKind != JsonValueKind.String ||
            !message.Payload.TryGetValue("accepted", out JsonElement accepted) || accepted.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
            throw new InvalidDataException("Invalid release acknowledgement");
        string value = id.GetString() ?? throw new InvalidDataException("Invalid ID");
        ValidateId(value);
        return (value, accepted.GetBoolean());
    }
    private static void ValidateId(string id)
    {
        if (id.Length != 36 || !Guid.TryParseExact(id, "D", out _)) throw new InvalidDataException("Invalid release ID");
    }
}
