using System.Net;
using InputBridge.Protocol;

namespace InputBridge.Windows;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        using var identity = DeviceIdentity.LoadOrCreate();
        Application.Run(new MainWindow(identity));
    }
}

/// <summary>Single simple screen: nearby devices, one allow switch, one share button.</summary>
internal sealed class MainWindow : Form
{
    private static readonly string[] PositionChoices = { "Not placed", "Left", "Right", "Above", "Below" };

    private readonly DeviceIdentity identity;
    private readonly CheckBox allowControl = new() { Text = "Let another device control this PC", AutoSize = true };
    private readonly Label status = new() { Text = "Starting…", AutoSize = true };
    private readonly FlowLayoutPanel deviceList = new()
    {
        FlowDirection = FlowDirection.TopDown, AutoSize = true, WrapContents = false,
        AutoScroll = true, Height = 210, Width = 520
    };
    private readonly Button shareButton = new() { Text = "Share mouse and keyboard", AutoSize = true, Enabled = false };
    private readonly Button stopButton = new() { Text = "Stop", AutoSize = true, Enabled = false };
    private readonly Dictionary<string, string> positions = new(StringComparer.Ordinal);

    private LanDiscovery? discovery;
    private SecureListener? listener;
    private CancellationTokenSource? receiveCts;
    private Task? acceptLoop;

    private SecureSender? sender;
    private WindowsSenderSession? pump;
    private WindowsInputCapture? capture;
    private CancellationTokenSource? sendCts;
    private string? connectedDevice;
    private bool closing;

    public MainWindow(DeviceIdentity identity)
    {
        this.identity = identity;
        Text = "CursorLoom";
        Width = 600; Height = 540;
        StartPosition = FormStartPosition.CenterScreen;

        var root = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown,
            Padding = new Padding(20), WrapContents = false, AutoScroll = true
        };
        root.Controls.Add(new Label { Text = "CursorLoom", AutoSize = true, Font = new Font(Font.FontFamily, 20, FontStyle.Bold) });
        root.Controls.Add(new Label { Text = $"This PC: {identity.Name}", AutoSize = true });
        root.Controls.Add(status);
        root.Controls.Add(allowControl);
        root.Controls.Add(new Label { Text = "Devices on this network", AutoSize = true, Font = new Font(Font.FontFamily, 11, FontStyle.Bold) });
        root.Controls.Add(deviceList);
        var buttons = new FlowLayoutPanel { AutoSize = true };
        buttons.Controls.Add(shareButton);
        buttons.Controls.Add(stopButton);
        root.Controls.Add(buttons);
        root.Controls.Add(new Label
        {
            AutoSize = true, ForeColor = SystemColors.GrayText,
            Text = "While sharing, everything you type also goes to the other computer.\r\nDo not enter passwords until this preview is finished."
        });
        Controls.Add(root);

        allowControl.CheckedChanged += (_, _) => { if (allowControl.Checked) StartReceiver(); else StopReceiver(); };
        shareButton.Click += async (_, _) => await StartSharingAsync();
        stopButton.Click += (_, _) => StopSharing();
        FormClosing += (_, _) => { closing = true; StopSharing(); StopReceiver(); discovery?.Dispose(); };
        Load += (_, _) => StartDiscovery();
    }

    private void StartDiscovery()
    {
        try
        {
            var lan = new LanDiscovery(identity.Id, identity.Name, identity.Fingerprint, DeviceIdentity.ServicePort);
            lan.PeersChanged += peers => BeginInvoke(() => RenderDevices(peers));
            lan.Start();
            discovery = lan;
            status.Text = "Searching for devices…";
        }
        catch (Exception error) when (error is System.Net.Sockets.SocketException or InvalidOperationException)
        {
            status.Text = "Cannot search the network: " + error.Message;
        }
    }

    private void RenderDevices(IReadOnlyList<DiscoveredDevice> peers)
    {
        if (deviceList.IsDisposed) return;
        deviceList.SuspendLayout();
        deviceList.Controls.Clear();
        foreach (var peer in peers)
        {
            var row = new FlowLayoutPanel { AutoSize = true, WrapContents = false };
            row.Controls.Add(new Label { Text = peer.Name, AutoSize = true, Width = 190, Padding = new Padding(0, 6, 0, 0) });
            var connect = new Button { Text = connectedDevice == peer.Id ? "Disconnect" : "Connect", AutoSize = true };
            connect.Click += async (_, _) =>
            {
                if (connectedDevice == peer.Id) { StopSharing(); Disconnect(); }
                else await ConnectAsync(peer);
            };
            connect.Enabled = connectedDevice is null || connectedDevice == peer.Id;
            row.Controls.Add(connect);
            var position = new ComboBox { Width = 110, DropDownStyle = ComboBoxStyle.DropDownList };
            position.Items.AddRange(PositionChoices);
            position.SelectedItem = positions.TryGetValue(peer.Id, out var stored) ? stored : PositionChoices[0];
            position.SelectedIndexChanged += (_, _) => positions[peer.Id] = position.SelectedItem as string ?? PositionChoices[0];
            row.Controls.Add(position);
            deviceList.Controls.Add(row);
        }
        if (peers.Count == 0)
            deviceList.Controls.Add(new Label { Text = "Searching…", AutoSize = true, ForeColor = SystemColors.GrayText });
        deviceList.ResumeLayout();
        if (!allowControl.Checked && connectedDevice is null) status.Text = "Searching for devices…";
    }

    private async Task ConnectAsync(DiscoveredDevice device)
    {
        try
        {
            byte[] pin = Convert.FromHexString(device.Fingerprint);
            var cts = new CancellationTokenSource();
            sendCts = cts;
            sender = await SecureSender.ConnectAsync(device.Address, device.Port,
                identity.Certificate, pin, cts.Token);
            connectedDevice = device.Id;
            shareButton.Enabled = true;
            stopButton.Enabled = false;
            status.Text = $"Connected to {device.Name} — press Share to start";
        }
        catch (Exception error) when (error is IOException or System.Net.Sockets.SocketException
            or System.Security.Authentication.AuthenticationException or ArgumentException or FormatException)
        {
            status.Text = "Connection failed: " + error.Message;
            Disconnect();
        }
    }

    private async Task StartSharingAsync()
    {
        if (sender is null || pump is not null) return;
        try
        {
            var session = new WindowsSenderSession(sender);
            sender = null;
            pump = session;
            capture = new WindowsInputCapture(input => { if (!session.Offer(input)) StopSharing(); });
            capture.Start();
            shareButton.Enabled = false;
            stopButton.Enabled = true;
            status.Text = "Sharing. Local input still works.";
            await session.RunAsync(sendCts?.Token ?? CancellationToken.None);
        }
        catch (Exception error) when (error is IOException or System.ComponentModel.Win32Exception
            or InvalidOperationException or System.Security.Authentication.AuthenticationException)
        {
            status.Text = "Sharing stopped: " + error.Message;
        }
        finally
        {
            StopSharing();
            if (!closing && connectedDevice is null) status.Text = "Searching for devices…";
        }
    }

    private void StopSharing()
    {
        capture?.Dispose(); capture = null;
        pump?.Abort(); pump = null;
        stopButton.Enabled = false;
        shareButton.Enabled = connectedDevice is not null;
        if (!closing) status.Text = "Connected — sharing off";
    }

    private void Disconnect()
    {
        StopSharing();
        sendCts?.Cancel(); sendCts?.Dispose(); sendCts = null;
        sender = null;
        connectedDevice = null;
        shareButton.Enabled = false;
        if (!closing) status.Text = "Searching for devices…";
    }

    private void StartReceiver()
    {
        if (listener is not null) return;
        try
        {
            var secure = new SecureListener(IPAddress.Any, DeviceIdentity.ServicePort, identity.Certificate);
            secure.Start();
            listener = secure;
            var cts = new CancellationTokenSource();
            receiveCts = cts;
            acceptLoop = Task.Run(() => AcceptLoopAsync(secure, cts.Token));
            status.Text = "Allowed — another device can ask to control this PC";
        }
        catch (Exception error) when (error is System.Net.Sockets.SocketException)
        {
            status.Text = "Cannot listen: " + error.Message;
            allowControl.Checked = false;
        }
    }

    private async Task AcceptLoopAsync(SecureListener secure, CancellationToken token)
    {
        var sink = new WindowsInputSink();
        while (!token.IsCancellationRequested)
        {
            System.Net.Security.SslStream stream;
            try { stream = await secure.AcceptAsync(token).ConfigureAwait(false); }
            catch (OperationCanceledException) { return; }
            catch (ObjectDisposedException) { return; }
            catch (Exception error) when (error is IOException or System.Net.Sockets.SocketException
                or System.Security.Authentication.AuthenticationException) { continue; }

            string peerPin = secure.LastPeerFingerprint is { } pin ? Convert.ToHexString(pin)[..12] : "unknown";
            bool allow = false;
            Invoke(() =>
            {
                allow = MessageBox.Show(this,
                    $"A device wants to control this PC (certificate {peerPin}…).\r\n\r\nOnly allow if you just started a connection from your own computer.",
                    "Allow control?", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes;
            });
            if (!allow)
            {
                await stream.DisposeAsync().ConfigureAwait(false);
                continue;
            }

            Invoke(() => status.Text = "Controlled by another device");
            try { await SecureInputReceiver.RunAsync(stream, DispatchToUi, false, token).ConfigureAwait(false); }
            catch (Exception error) when (error is IOException or InvalidDataException or OperationCanceledException) { }
            if (!closing) Invoke(() => status.Text = allowControl.Checked ? "Allowed — waiting for a device" : "Idle");
        }
    }

    private Task DispatchToUi(Action action)
    {
        if (IsDisposed || !IsHandleCreated) return Task.FromException(new ObjectDisposedException(nameof(MainWindow)));
        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        try
        {
            BeginInvoke(() =>
            {
                try { action(); completion.SetResult(); }
                catch (Exception error) { completion.SetException(error); }
            });
        }
        catch (InvalidOperationException error) { completion.TrySetException(error); }
        return completion.Task;
    }

    private void StopReceiver()
    {
        receiveCts?.Cancel(); receiveCts?.Dispose(); receiveCts = null;
        listener?.Dispose(); listener = null;
        try { acceptLoop?.Wait(500); } catch (AggregateException) { }
        acceptLoop = null;
        if (!closing && connectedDevice is null) status.Text = "Searching for devices…";
    }
}
