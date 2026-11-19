using System.Text;
using System.Text.Json;

namespace InputBridge.Protocol;

public abstract record RemoteInput;
public sealed record KeyInput(int Usage, bool Down) : RemoteInput;
public sealed record PointerInput(double X, double Y) : RemoteInput;
public sealed record ButtonInput(int Index, bool Down) : RemoteInput;
public sealed record ScrollInput(int Vertical, int Horizontal) : RemoteInput;
public sealed record ClipboardInput(string Text) : RemoteInput;
public sealed record ReleaseAllInput : RemoteInput;

/// <summary>Reject unrecognized or malformed input before reaching platform APIs.</summary>
public static class InputValidator
{
    public static RemoteInput Parse(Envelope message)
    {
        if (message.Version != 1 || message.Payload is null)
            throw new InvalidDataException("Invalid input message");
        Dictionary<string, JsonElement> p = message.Payload;
        void Fields(params string[] names)
        {
            if (p.Count != names.Length || names.Any(name => !p.ContainsKey(name)))
                throw new InvalidDataException("Unexpected input fields");
        }
        int Integer(string name, int min, int max)
        {
            if (p[name].ValueKind != JsonValueKind.Number || !p[name].TryGetDouble(out double n) || !double.IsFinite(n) || n != Math.Truncate(n) || n < min || n > max)
                throw new InvalidDataException("Invalid integer");
            return (int)n;
        }
        bool Boolean(string name) => p[name].ValueKind switch
        {
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            _ => throw new InvalidDataException("Invalid boolean")
        };
        double Fraction(string name)
        {
            if (p[name].ValueKind != JsonValueKind.Number || !p[name].TryGetDouble(out double n) || !double.IsFinite(n) || n < 0 || n > 1)
                throw new InvalidDataException("Invalid fraction");
            return n;
        }
        switch (message.Type)
        {
            case "key":
                Fields("usage", "down"); return new KeyInput(Integer("usage", 0, 255), Boolean("down"));
            case "pointer":
                Fields("x", "y"); return new PointerInput(Fraction("x"), Fraction("y"));
            case "button":
                Fields("index", "down"); return new ButtonInput(Integer("index", 0, 1), Boolean("down"));
            case "scroll":
                Fields("vertical", "horizontal"); return new ScrollInput(Integer("vertical", -100, 100), Integer("horizontal", -100, 100));
            case "clipboard":
                Fields("text");
                if (p["text"].ValueKind != JsonValueKind.String) throw new InvalidDataException("Invalid text");
                string text = p["text"].GetString() ?? throw new InvalidDataException("Invalid text");
                if (Encoding.UTF8.GetByteCount(text) > 48_000) throw new InvalidDataException("Clipboard too large");
                return new ClipboardInput(text);
            case "releaseAll":
                Fields(); return new ReleaseAllInput();
            default: throw new InvalidDataException("Unsupported command");
        }
    }
}
