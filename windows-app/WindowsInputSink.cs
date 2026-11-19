using System.Runtime.InteropServices;
using InputBridge.Protocol;

namespace InputBridge.Windows;

/// <summary>Local input injection primitive. Never wire to an unauthenticated peer.</summary>
internal sealed class WindowsInputSink
{
    private const uint InputMouse = 0;
    private const uint InputKeyboard = 1;
    private const uint KeyUp = 0x0002;
    private const uint ScanCode = 0x0008;
    private const uint Extended = 0x0001;
    private readonly HashSet<int> pressedKeys = new();
    private readonly HashSet<int> pressedButtons = new();

    // USB HID usage -> PC set-1 scan code, E0 prefix marked with bit 8.
    private static readonly Dictionary<int, ushort> ScanCodes = new()
    {
        [4]=0x1e,[5]=0x30,[6]=0x2e,[7]=0x20,[8]=0x12,[9]=0x21,[10]=0x22,[11]=0x23,
        [12]=0x17,[13]=0x24,[14]=0x25,[15]=0x26,[16]=0x32,[17]=0x31,[18]=0x18,
        [19]=0x19,[20]=0x10,[21]=0x13,[22]=0x1f,[23]=0x14,[24]=0x16,[25]=0x2f,
        [26]=0x11,[27]=0x2d,[28]=0x15,[29]=0x2c,[30]=0x02,[31]=0x03,[32]=0x04,
        [33]=0x05,[34]=0x06,[35]=0x07,[36]=0x08,[37]=0x09,[38]=0x0a,[39]=0x0b,
        [40]=0x1c,[41]=0x01,[42]=0x0e,[43]=0x0f,[44]=0x39,[45]=0x0c,[46]=0x0d,
        [47]=0x1a,[48]=0x1b,[49]=0x2b,[51]=0x27,[52]=0x28,[53]=0x29,[54]=0x33,
        [55]=0x34,[56]=0x35,[57]=0x3a,[58]=0x3b,[59]=0x3c,[60]=0x3d,[61]=0x3e,
        [62]=0x3f,[63]=0x40,[64]=0x41,[65]=0x42,[66]=0x43,[67]=0x44,[68]=0x57,
        [69]=0x58,[73]=0x152,[74]=0x147,[75]=0x149,[76]=0x153,[77]=0x14f,[78]=0x151,
        [79]=0x14d,[80]=0x14b,[81]=0x150,[82]=0x148,[224]=0x1d,[225]=0x2a,
        [226]=0x38,[227]=0x15b,[228]=0x11d,[229]=0x36,[230]=0x138,[231]=0x15c
    };

    public bool Apply(RemoteInput input, bool allowClipboard = false)
    {
        switch (input)
        {
            case KeyInput key: return Key(key.Usage, key.Down);
            case PointerInput pointer: return Move(pointer.X, pointer.Y);
            case ButtonInput button: return Button(button.Index, button.Down);
            case ScrollInput scroll: return Scroll(scroll.Vertical, scroll.Horizontal);
            case ClipboardInput clipboard:
                if (!allowClipboard || System.Text.Encoding.UTF8.GetByteCount(clipboard.Text) > 48_000) return false;
                try { if (clipboard.Text.Length == 0) Clipboard.Clear(); else Clipboard.SetText(clipboard.Text); return true; }
                catch (ExternalException) { return false; }
            case ReleaseAllInput: ReleaseAll(); return true;
            default: return false;
        }
    }

    private bool Key(int usage, bool down)
    {
        if (!ScanCodes.TryGetValue(usage, out ushort scan)) return false;
        var input = new Input { Type = InputKeyboard, Data = new InputUnion { Keyboard = new KeyboardInput
        {
            Scan = (ushort)(scan & 0xff), Flags = ScanCode | ((scan & 0x100) != 0 ? Extended : 0) | (down ? 0 : KeyUp)
        } } };
        if (!Send(input)) return false;
        if (down) pressedKeys.Add(usage); else pressedKeys.Remove(usage);
        return true;
    }

    private static bool Move(double x, double y)
    {
        if (!double.IsFinite(x) || !double.IsFinite(y) || x < 0 || x > 1 || y < 0 || y > 1) return false;
        var input = new Input { Type = InputMouse, Data = new InputUnion { Mouse = new MouseInput
        {
            X = (int)Math.Round(x * 65535), Y = (int)Math.Round(y * 65535), Flags = 0x8001
        } } };
        return Send(input);
    }

    private bool Button(int index, bool down)
    {
        if (index is not (0 or 1)) return false;
        uint flags = index == 0 ? (down ? 0x0002u : 0x0004u) : (down ? 0x0008u : 0x0010u);
        if (!Mouse(flags, 0)) return false;
        if (down) pressedButtons.Add(index); else pressedButtons.Remove(index);
        return true;
    }

    private static bool Scroll(int vertical, int horizontal)
    {
        if (vertical is < -100 or > 100 || horizontal is < -100 or > 100) return false;
        if (vertical != 0 && !Mouse(0x0800, unchecked((uint)(vertical * 120)))) return false;
        if (horizontal != 0 && !Mouse(0x1000, unchecked((uint)(horizontal * 120)))) return false;
        return true;
    }

    private static bool Mouse(uint flags, uint data) => Send(new Input { Type = InputMouse,
        Data = new InputUnion { Mouse = new MouseInput { Flags = flags, MouseData = data } } });

    public void ReleaseAll()
    {
        foreach (int usage in pressedKeys.ToArray()) _ = Key(usage, false);
        foreach (int button in pressedButtons.ToArray()) _ = Button(button, false);
        // Failed releases stay tracked for a subsequent retry.
    }

    private static bool Send(Input input) => SendInput(1, new[] { input }, Marshal.SizeOf<Input>()) == 1;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint count, Input[] inputs, int size);

    [StructLayout(LayoutKind.Sequential)]
    private struct Input { public uint Type; public InputUnion Data; }
    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public MouseInput Mouse;
        [FieldOffset(0)] public KeyboardInput Keyboard;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct MouseInput { public int X, Y; public uint MouseData, Flags, Time; public nint ExtraInfo; }
    [StructLayout(LayoutKind.Sequential)]
    private struct KeyboardInput { public ushort VirtualKey, Scan; public uint Flags, Time; public nint ExtraInfo; }
}
