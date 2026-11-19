using System.Net;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

namespace InputBridge.Windows;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new MainWindow());
    }
}

internal sealed class MainWindow : Form
{
    private readonly TextBox certificatePath = new() { Width = 330 };
    private readonly TextBox password = new() { Width = 200, UseSystemPasswordChar = true };
    private readonly TextBox peerPin = new() { Width = 420 };
    private readonly NumericUpDown port = new() { Minimum = 1, Maximum = 65535, Value = 24800 };
    private readonly CheckBox consent = new() { Text = "Allow this pinned device to control this computer", AutoSize = true };
    private readonly Button start = new() { Text = "Start receiver", AutoSize = true };
    private readonly Button stop = new() { Text = "Stop", AutoSize = true, Enabled = false };
    private readonly Label status = new() { Text = "Stopped", AutoSize = true };
    private CancellationTokenSource? cancellation;
    private SecureListener? listener;
    private bool closeWhenStopped;

    public MainWindow()
    {
        Text = "CursorLoom — experimental receiver";
        Width = 600;
        Height = 530;
        StartPosition = FormStartPosition.CenterScreen;
        var panel = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown,
            Padding = new Padding(18), WrapContents = false, AutoScroll = true };
        panel.Controls.Add(new Label { Text = "Experimental receiver — one-way only", AutoSize = true, Font = new Font(Font.FontFamily, 15, FontStyle.Bold) });
        panel.Controls.Add(new Label { Text = "Only use on a trusted test network. Clipboard is disabled.", AutoSize = true });
        panel.Controls.Add(new Label { Text = "Local PKCS#12 certificate (.p12 / .pfx):", AutoSize = true });
        var pathRow = new FlowLayoutPanel { AutoSize = true };
        var browse = new Button { Text = "Browse…", AutoSize = true };
        browse.Click += (_, _) => { using var dialog = new OpenFileDialog { Filter = "PKCS#12|*.p12;*.pfx|All files|*.*" }; if (dialog.ShowDialog(this) == DialogResult.OK) certificatePath.Text = dialog.FileName; };
        pathRow.Controls.Add(certificatePath); pathRow.Controls.Add(browse); panel.Controls.Add(pathRow);
        panel.Controls.Add(new Label { Text = "Certificate password:", AutoSize = true }); panel.Controls.Add(password);
        panel.Controls.Add(new Label { Text = "Peer certificate SHA-256 fingerprint (verify out-of-band):", AutoSize = true }); panel.Controls.Add(peerPin);
        panel.Controls.Add(new Label { Text = "TCP port:", AutoSize = true }); panel.Controls.Add(port);
        panel.Controls.Add(consent);
        var row = new FlowLayoutPanel { AutoSize = true }; row.Controls.Add(start); row.Controls.Add(stop); panel.Controls.Add(row);
        panel.Controls.Add(status); Controls.Add(panel);
        start.Click += async (_, _) => await RunReceiverAsync();
        stop.Click += (_, _) => StopReceiver();
        FormClosing += (_, eventArgs) =>
        {
            if (cancellation is null) return;
            eventArgs.Cancel = true;
            closeWhenStopped = true;
            StopReceiver();
        };
    }

    private async Task RunReceiverAsync()
    {
        if (cancellation is not null) return;
        if (!consent.Checked) { MessageBox.Show(this, "Explicit consent is required."); return; }
        X509Certificate2? certificate = null;
        CancellationTokenSource? cts = null;
        try
        {
            string normalizedPin = new string(peerPin.Text.Where(c => c != ':' && !char.IsWhiteSpace(c)).ToArray());
            byte[] pin = Convert.FromHexString(normalizedPin);
            if (pin.Length != 32) throw new ArgumentException("Fingerprint must contain 32 bytes.");
            certificate = new X509Certificate2(certificatePath.Text, password.Text, X509KeyStorageFlags.EphemeralKeySet);
            password.Clear();
            listener = new SecureListener(IPAddress.Any, (int)port.Value, certificate, pin);
            listener.Start();
            cts = new CancellationTokenSource();
            cancellation = cts;
            start.Enabled = false; stop.Enabled = true;
            status.Text = "Waiting for authenticated peer…";
            using var stream = await listener.AcceptAsync(cts.Token);
            listener.Dispose(); listener = null;
            status.Text = "Connected — remote input enabled. Press Stop to disconnect.";
            await SecureInputReceiver.RunAsync(stream, DispatchToUI, false, cts.Token);
            status.Text = "Peer disconnected";
        }
        catch (OperationCanceledException) { status.Text = "Stopped"; }
        catch (Exception error) when (error is IOException or CryptographicException or ArgumentException or InvalidOperationException or System.Net.Sockets.SocketException or System.Security.Authentication.AuthenticationException or UnauthorizedAccessException)
        { status.Text = "Stopped: " + error.Message; }
        finally
        {
            listener?.Dispose(); listener = null;
            cancellation = null; cts?.Dispose(); certificate?.Dispose(); password.Clear();
            start.Enabled = true; stop.Enabled = false;
            if (closeWhenStopped) Close();
        }
    }

    private Task DispatchToUI(Action action)
    {
        if (IsDisposed || Disposing || !IsHandleCreated) return Task.FromException(new ObjectDisposedException(nameof(MainWindow)));
        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        try
        {
            BeginInvoke(() => { try { action(); completion.SetResult(); } catch (Exception error) { completion.SetException(error); } });
        }
        catch (InvalidOperationException error) { completion.TrySetException(error); }
        return completion.Task;
    }

    private void StopReceiver()
    {
        cancellation?.Cancel();
        listener?.Dispose();
        status.Text = "Stopping…";
    }
}
