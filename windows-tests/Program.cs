using System.Text;
using System.Text.Json;
using InputBridge.Protocol;

static void Assert(bool condition, string message)
{
    if (!condition) throw new Exception(message);
}
static void Reject(Action action)
{
    try { action(); }
    catch (Exception error) when (error is InvalidDataException or JsonException) { return; }
    throw new Exception("Expected malformed message to be rejected");
}
static Envelope Decode(string json) => MessageCodec.Decode(Encoding.UTF8.GetBytes(json));

// Swift-generated compatible frames and deliberately adversarial messages.
const string key = "{\"version\":1,\"type\":\"key\",\"payload\":{\"usage\":4,\"down\":true}}\n";
const string clipboard = "{\"version\":1,\"type\":\"clipboard\",\"payload\":{\"text\":\"سلام\\nworld\"}}\n";
var decoder = new FrameDecoder();
byte[] frames = Encoding.UTF8.GetBytes(key + clipboard);
int split = frames.Length / 2;
var messages = decoder.Append(frames.AsSpan(0, split)).Concat(decoder.Append(frames.AsSpan(split))).ToArray();
decoder.Finish();
Assert(messages.Length == 2, "Fragmented messages lost");
Assert(InputValidator.Parse(messages[0]) == new KeyInput(4, true), "Key mismatch");
Assert(InputValidator.Parse(messages[1]) == new ClipboardInput("سلام\nworld"), "Clipboard mismatch");
Assert(InputValidator.Parse(Decode("{\"version\":1,\"type\":\"releaseAll\",\"payload\":{}}")) is ReleaseAllInput, "Release mismatch");
Reject(() => InputValidator.Parse(Decode("{\"version\":1,\"type\":\"pointer\",\"payload\":{\"x\":-1,\"y\":0}}")));
Reject(() => InputValidator.Parse(Decode("{\"version\":1,\"type\":\"key\",\"payload\":{\"usage\":4.5,\"down\":true}}")));
Reject(() => InputValidator.Parse(Decode("{\"version\":1,\"type\":\"key\",\"payload\":{\"usage\":4,\"down\":true,\"extra\":null}}")));
Reject(() => MessageCodec.Decode(new byte[MessageCodec.MaximumBytes + 1]));
var oversized = new FrameDecoder();
Reject(() => oversized.Append(Enumerable.Repeat((byte)'x', MessageCodec.MaximumBytes).ToArray()));
Reject(() => oversized.Append(Encoding.UTF8.GetBytes(key)));
var truncated = new FrameDecoder();
_ = truncated.Append(Encoding.UTF8.GetBytes("{"));
Reject(truncated.Finish);
var session = new SessionState();
Assert(!session.Permits(new KeyInput(4, true)), "Initial state must deny input");
session.BeginConnection(); session.Authenticated(); session.BeginSharing(true, false);
Assert(session.Permits(new KeyInput(4, true)), "Sharing should allow key");
Assert(!session.Permits(new ClipboardInput("secret")), "Clipboard requires consent");
session.Disconnect();
Assert(!session.Permits(new KeyInput(4, true)), "Disconnected state must deny input");
byte[] shared = File.ReadAllBytes(Path.Combine("test-vectors", "input-messages.jsonl"));
var fixtureDecoder = new FrameDecoder();
RemoteInput[] fixture = fixtureDecoder.Append(shared).Select(InputValidator.Parse).ToArray();
fixtureDecoder.Finish();
RemoteInput[] expected = { new KeyInput(4, true), new PointerInput(0.25, 0.75), new ButtonInput(1, false),
    new ScrollInput(-3, 1), new ClipboardInput("سلام 🌍\nline"), new ReleaseAllInput() };
Assert(fixture.SequenceEqual(expected), "Shared protocol fixtures differ");
Console.WriteLine("Protocol and session checks passed.");
