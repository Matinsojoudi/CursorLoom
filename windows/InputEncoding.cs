using System.Text.Json;

namespace InputBridge.Protocol;

/// <summary>Maps validated operating-system-independent input to wire messages.</summary>
public static class InputEncoding
{
    public static Envelope Encode(RemoteInput input)
    {
        static JsonElement Value<T>(T value) => JsonSerializer.SerializeToElement(value);
        Envelope result = input switch
        {
            KeyInput key => new(1, "key", new() { ["usage"] = Value(key.Usage), ["down"] = Value(key.Down) }),
            PointerInput pointer => new(1, "pointer", new() { ["x"] = Value(pointer.X), ["y"] = Value(pointer.Y) }),
            ButtonInput button => new(1, "button", new() { ["index"] = Value(button.Index), ["down"] = Value(button.Down) }),
            ScrollInput scroll => new(1, "scroll", new() { ["vertical"] = Value(scroll.Vertical), ["horizontal"] = Value(scroll.Horizontal) }),
            ClipboardInput clipboard => new(1, "clipboard", new() { ["text"] = Value(clipboard.Text) }),
            ReleaseAllInput => new(1, "releaseAll", new()),
            _ => throw new InvalidDataException("Unsupported input")
        };
        _ = InputValidator.Parse(result);
        return result;
    }
}
