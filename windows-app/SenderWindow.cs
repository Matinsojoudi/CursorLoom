using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using InputBridge.Protocol;

namespace InputBridge.Windows;

/// <summary>Experimental passive sender; local input is not suppressed.</summary>
internal sealed class SenderWindow : Form
{
    private readonly TextBox host = new() { Width = 380 };
    private readonly NumericUpDown port = new() { Minimum = 1, Maximum = 65535, Value = 24800 };
    private readonly TextBox certificatePath = new() { Width = 300 };
    private readonly TextBox password = new() { Width = 200, UseSystemPasswordChar = true };
    private readonly TextBox pin = new() { Width = 420 };
    private readonly CheckBox consent = new() { AutoSize = true, Text = "Send my mouse and keyboard to this device" };
    private readonly Button start = new() { Text = "Connect and share", AutoSize = true };
    private readonly Button stop = new() { Text = "Stop", AutoSize = true, Enabled = false };
    private readonly Label status = new() { Text = "Stopped", AutoSize = true };
    private CancellationTokenSource? cancellation;
    private WindowsSenderSession? session;
    private WindowsInputCapture? capture;
    private bool closeWhenStopped;

    public SenderWindow()
    {
        Text = "CursorLoom — experimental Windows sender";
        Width = 600; Height = 520; StartPosition = FormStartPosition.CenterParent;
        var panel = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown,
            Padding = new Padding(18), WrapContents = false, AutoScroll = true };
        panel.Controls.Add(new Label { Text = "Local input remains active. Never type secrets while sharing.", AutoSize = true });
        panel.Controls.Add(new Label { Text = "Receiver host:", AutoSize = true }); panel.Controls.Add(host);
        panel.Controls.Add(new Label { Text = "Port:", AutoSize = true }); panel.Controls.Add(port);
        panel.Controls.Add(new Label { Text = "Client identity (.p12/.pfx):", AutoSize = true });
        var pathRow = new FlowLayoutPanel { AutoSize = true };
        var browse = new Button { Text = "Browse…", AutoSize = true };
        browse.Click += (_, _) => { using var dialog = new OpenFileDialog { Filter = "PKCS#12|*.p12;*.pfx|All files|*.*" }; if (dialog.ShowDialog(this) == DialogResult.OK) certificatePath.Text = dialog.FileName; };
        pathRow.Controls.Add(certificatePath); pathRow.Controls.Add(browse); panel.Controls.Add(pathRow);
        panel.Controls.Add(new Label { Text = "Identity password:", AutoSize = true }); panel.Controls.Add(password);
        panel.Controls.Add(new Label { Text = "Receiver certificate SHA-256 fingerprint:", AutoSize = true }); panel.Controls.Add(pin);
        panel.Controls.Add(consent);
        var buttons = new FlowLayoutPanel { AutoSize = true }; buttons.Controls.Add(start); buttons.Controls.Add(stop); panel.Controls.Add(buttons);
        panel.Controls.Add(status); Controls.Add(panel);
        start.Click += async (_, _) => await RunAsync();
        stop.Click += (_, _) => Stop();
        FormClosing += (_, args) => { if (cancellation is not null) { args.Cancel = true; closeWhenStopped = true; Stop(); } };
    }

    private async Task RunAsync()
    {
        if (cancellation is not null || !consent.Checked) return;
        CancellationTokenSource? cts = null;
        X509Certificate2? identity = null;
        SecureSender? sender = null;
        try
        {
            byte[] peerPin = Convert.FromHexString(new string(pin.Text.Where(c => c != ':' && !char.IsWhiteSpace(c)).ToArray()));
            if (peerPin.Length != 32 || string.IsNullOrWhiteSpace(host.Text)) throw new ArgumentException("Valid host and 32-byte pin required");
            identity = new X509Certificate2(certificatePath.Text, password.Text, X509KeyStorageFlags.UserKeySet);
            password.Clear();
            cts = new CancellationTokenSource(); cancellation = cts;
            start.Enabled = false; stop.Enabled = true; consent.Enabled = false;
            status.Text = "Connecting…";
            sender = await SecureSender.ConnectAsync(host.Text, (int)port.Value, identity, peerPin, cts.Token);
            var pump = new WindowsSenderSession(sender);
            sender = null; // ownership moved to pump
            session = pump;
            capture = new WindowsInputCapture(input =>
            {
                if (!pump.Offer(input)) { capture?.Dispose(); capture = null; }
            });
            capture.Start();
            status.Text = "Sharing input; local input remains active. Press Stop.";
            await pump.RunAsync(cts.Token);
            status.Text = "Stopped";
        }
        catch (OperationCanceledException) { status.Text = "Stopped"; }
        catch (Exception error) when (error is IOException or CryptographicException or ArgumentException or FormatException or InvalidOperationException or System.Net.Sockets.SocketException or System.Security.Authentication.AuthenticationException or UnauthorizedAccessException or System.ComponentModel.Win32Exception)
        { status.Text = "Stopped: " + error.Message; }
        finally
        {
            capture?.Dispose(); capture = null;
            session?.Abort(); session = null;
            if (sender is not null) await sender.DisposeAsync();
            identity?.Dispose(); password.Clear();
            cancellation = null; cts?.Dispose();
            consent.Checked = false; consent.Enabled = true;
            start.Enabled = true; stop.Enabled = false;
            if (closeWhenStopped) Close();
        }
    }

    private void Stop()
    {
        capture?.Dispose(); capture = null;
        session?.Abort();
        cancellation?.Cancel();
        status.Text = "Stopping…";
    }
}
