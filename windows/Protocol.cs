using System.Text.Json;
using System.Text.Json.Serialization;

namespace InputBridge.Protocol;

public sealed record Envelope(
    [property: JsonPropertyName("version")] int Version,
    [property: JsonPropertyName("type")] string Type,
    [property: JsonPropertyName("payload")] Dictionary<string, JsonElement> Payload);

/// <summary>Framing only; use exclusively over authenticated encrypted transport.</summary>
public static class MessageCodec
{
    public const int MaximumBytes = 65_536;

    public static byte[] Encode(Envelope message)
    {
        Validate(message);
        byte[] json = JsonSerializer.SerializeToUtf8Bytes(message);
        if (json.Length + 1 > MaximumBytes) throw new InvalidDataException("Frame too large");
        byte[] frame = new byte[json.Length + 1];
        json.CopyTo(frame, 0);
        frame[^1] = (byte)'\n';
        return frame;
    }

    public static Envelope Decode(ReadOnlySpan<byte> frame)
    {
        if (frame.Length > MaximumBytes) throw new InvalidDataException("Frame too large");
        Envelope? message = JsonSerializer.Deserialize<Envelope>(frame);
        if (message is null) throw new InvalidDataException("Empty message");
        Validate(message);
        return message;
    }

    private static void Validate(Envelope message)
    {
        if (message.Version != 1) throw new InvalidDataException("Unsupported protocol version");
        if (message.Type is null || message.Payload is null) throw new InvalidDataException("Invalid message");
        foreach (JsonElement value in message.Payload.Values)
        {
            if (value.ValueKind is not (JsonValueKind.String or JsonValueKind.Number or JsonValueKind.True or JsonValueKind.False or JsonValueKind.Null))
                throw new InvalidDataException("Payload values must be primitive");
        }
    }
}

public sealed class FrameDecoder
{
    private readonly List<byte> pending = new();
    private bool failed;

    public IReadOnlyList<Envelope> Append(ReadOnlySpan<byte> bytes)
    {
        if (failed) throw new InvalidDataException("Decoder is closed");
        var result = new List<Envelope>();
        try
        {
            foreach (byte value in bytes)
            {
                if (value == (byte)'\n')
                {
                    if (pending.Count == 0) throw new InvalidDataException("Empty frame");
                    pending.Add(value);
                    result.Add(MessageCodec.Decode(pending.ToArray()));
                    pending.Clear();
                }
                else
                {
                    if (pending.Count >= MessageCodec.MaximumBytes - 1) throw new InvalidDataException("Frame too large");
                    pending.Add(value);
                }
            }
            return result;
        }
        catch
        {
            failed = true;
            pending.Clear();
            throw;
        }
    }

    public void Finish()
    {
        if (failed || pending.Count != 0)
        {
            failed = true;
            pending.Clear();
            throw new InvalidDataException("Truncated or failed frame");
        }
    }
}
