using System.Net;
using System.Net.Sockets;
using System.Text.Json;

namespace InputBridge.Windows;

internal sealed record DiscoveredDevice(string Id, string Name, string Address, string Fingerprint, ushort Port);

/// <summary>
/// Broadcast discovery matching the macOS beacon format. Beacons are unauthenticated
/// announcements; the TLS fingerprint of the peer is what the connection actually
/// verifies, and the user's consent prompt is what grants control.
/// </summary>
internal sealed class LanDiscovery : IDisposable
{
    private sealed record Beacon(int v, string id, string name, string fp, ushort port);

    public const int DiscoveryPort = 24_802;
    private readonly string selfId;
    private readonly string selfFingerprint;
    private readonly string selfName;
    private readonly ushort servicePort;
    private readonly CancellationTokenSource cancellation = new();
    private readonly Dictionary<string, (DiscoveredDevice Device, DateTime Seen)> peers = new(StringComparer.Ordinal);
    private readonly object gate = new();
    private UdpClient? client;
    private Task? receiveLoop;
    private Task? announceLoop;

    public event Action<IReadOnlyList<DiscoveredDevice>>? PeersChanged;

    public LanDiscovery(string selfId, string selfName, string selfFingerprint, ushort servicePort)
    {
        this.selfId = selfId; this.selfName = selfName;
        this.selfFingerprint = selfFingerprint; this.servicePort = servicePort;
    }

    public void Start()
    {
        var udp = new UdpClient();
        udp.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
        udp.Client.EnableBroadcast = true;
        udp.Client.Bind(new IPEndPoint(IPAddress.Any, DiscoveryPort));
        client = udp;
        receiveLoop = Task.Run(() => ReceiveAsync(udp, cancellation.Token));
        announceLoop = Task.Run(() => AnnounceAsync(udp, cancellation.Token));
    }

    private async Task AnnounceAsync(UdpClient udp, CancellationToken token)
    {
        byte[] payload = JsonSerializer.SerializeToUtf8Bytes(
            new Beacon(1, selfId, selfName, selfFingerprint, servicePort));
        while (!token.IsCancellationRequested)
        {
            foreach (IPAddress target in BroadcastTargets())
            {
                try { await udp.SendAsync(payload, new IPEndPoint(target, DiscoveryPort), token).ConfigureAwait(false); }
                catch (Exception error) when (error is SocketException or ObjectDisposedException or OperationCanceledException) { }
            }
            try { await Task.Delay(TimeSpan.FromSeconds(2), token).ConfigureAwait(false); }
            catch (OperationCanceledException) { return; }
        }
    }

    private static IEnumerable<IPAddress> BroadcastTargets()
    {
        yield return IPAddress.Loopback;
        yield return IPAddress.Broadcast;
        foreach (var address in Dns.GetHostAddresses(Dns.GetHostName()))
        {
            if (address.AddressFamily != AddressFamily.InterNetwork) continue;
            byte[] bytes = address.GetAddressBytes();
            bytes[3] = 255;
            yield return new IPAddress(bytes);
        }
    }

    private async Task ReceiveAsync(UdpClient udp, CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            UdpReceiveResult result;
            try { result = await udp.ReceiveAsync(token).ConfigureAwait(false); }
            catch (OperationCanceledException) { return; }
            catch (ObjectDisposedException) { return; }
            catch (SocketException) { continue; }

            if (result.Buffer.Length > 1024) continue;
            Beacon? beacon;
            try { beacon = JsonSerializer.Deserialize<Beacon>(result.Buffer); }
            catch (JsonException) { continue; }
            if (beacon is null || beacon.v != 1 || beacon.id == selfId || beacon.port == 0) continue;
            if (!Guid.TryParse(beacon.id, out _) || beacon.fp.Length != 64 || beacon.name.Length == 0) continue;

            var device = new DiscoveredDevice(beacon.id, beacon.name,
                result.RemoteEndPoint.Address.ToString(), beacon.fp, beacon.port);
            bool changed;
            lock (gate)
            {
                changed = !peers.TryGetValue(device.Id, out var prior) ||
                          prior.Device.Address != device.Address || prior.Device.Name != device.Name;
                peers[device.Id] = (device, DateTime.UtcNow);
            }
            if (changed) Publish();
        }
    }

    private void Publish()
    {
        IReadOnlyList<DiscoveredDevice> snapshot;
        lock (gate)
        {
            DateTime cutoff = DateTime.UtcNow.AddSeconds(-8);
            foreach (string stale in peers.Where(p => p.Value.Seen < cutoff).Select(p => p.Key).ToArray())
                peers.Remove(stale);
            snapshot = peers.Values.Select(p => p.Device)
                .OrderBy(d => d.Name, StringComparer.OrdinalIgnoreCase).ToArray();
        }
        PeersChanged?.Invoke(snapshot);
    }

    public void Dispose()
    {
        cancellation.Cancel();
        client?.Dispose();
        try { receiveLoop?.Wait(500); announceLoop?.Wait(500); } catch (AggregateException) { }
        cancellation.Dispose();
    }
}
