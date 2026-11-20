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
foreach (RemoteInput item in expected)
{
    Envelope encoded = InputEncoding.Encode(item);
    Assert(InputValidator.Parse(MessageCodec.Decode(MessageCodec.Encode(encoded))) == item, "Input encoding mismatch");
}
Reject(() => InputEncoding.Encode(new PointerInput(-1, 0)));
var router = new DeviceRouter();
router.Add("a"); router.Add("b");
Assert(router.Select("a", _ => true), "First target selection failed");
Assert(router.Select("b", previous => previous == "a"), "Previous target release failed");
Assert(router.ActivePeer == "b", "Target selection mismatch");
Assert(router.Destination(new KeyInput(4, true), new HashSet<string>()) == "b", "Key routing mismatch");
Assert(router.Destination(new ClipboardInput("private"), new HashSet<string> { "a" }) is null, "Clipboard permission missing");
Assert(router.Destination(new ClipboardInput("ok"), new HashSet<string> { "b" }) == "b", "Clipboard routing mismatch");
Assert(!router.Select("a", _ => false) && router.ActivePeer is null && !router.Peers.Contains("b"), "Release failure must fail closed");
var layout = new DeviceLayout();
layout.Add("windows", new DeviceLayout.Position(1, 0));
layout.Add("mac", new DeviceLayout.Position(1, -1));
Assert(layout.Neighbor("local", DeviceLayout.Direction.Right) == "windows", "Layout right mismatch");
Assert(layout.Neighbor("windows", DeviceLayout.Direction.Up) == "mac", "Layout up mismatch");
layout.Remove("windows");
Assert(layout.Neighbor("local", DeviceLayout.Direction.Right) is null, "Removed device still routed");
var wheel = new WheelAccumulator();
Assert(wheel.Push(40) == 0 && wheel.Push(40) == 0 && wheel.Push(40) == 1, "Fine wheel delta lost");
Assert(wheel.Push(-60) == 0 && wheel.Push(-60) == -1, "Negative wheel delta lost");
wheel.Push(60); wheel.Reset(); Assert(wheel.Push(60) == 0, "Wheel reset failed");
var coordinator = new PeerSwitchCoordinator();
int released = 0;
await coordinator.AddAsync("a", _ => { released++; return Task.FromResult(true); }, CancellationToken.None);
await coordinator.AddAsync("b", _ => Task.FromResult(false), CancellationToken.None);
Assert(await coordinator.SelectAsync("a", CancellationToken.None), "Coordinator initial select failed");
Assert(await coordinator.SelectAsync("b", CancellationToken.None) && released == 1, "Coordinator failed to release previous");
Assert(!await coordinator.SelectAsync("a", CancellationToken.None), "Coordinator accepted failed release");
Assert(await coordinator.DestinationAsync(new KeyInput(4, true), new HashSet<string>(), CancellationToken.None) is null, "Failed switch must leave local active");
Console.WriteLine("Protocol and session checks passed.");
