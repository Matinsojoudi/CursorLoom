using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using InputBridge.Windows;
using InputBridge.Protocol;
using System.Text.Json;

static X509Certificate2 CreateIdentity(string name, string usage)
{
    using RSA key = RSA.Create(2048);
    var request = new CertificateRequest($"CN={name}", key, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
    var usages = new OidCollection { new Oid(usage) };
    request.CertificateExtensions.Add(new X509EnhancedKeyUsageExtension(usages, true));
    request.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.DigitalSignature, true));
    using X509Certificate2 generated = request.CreateSelfSigned(DateTimeOffset.UtcNow.AddMinutes(-5), DateTimeOffset.UtcNow.AddHours(1));
    return new X509Certificate2(generated.Export(X509ContentType.Pkcs12), (string?)null, X509KeyStorageFlags.UserKeySet);
}

static async Task CheckAsync(bool validClient, CancellationToken timeout)
{
    using X509Certificate2 server = CreateIdentity("server", "1.3.6.1.5.5.7.3.1");
    using X509Certificate2 trusted = CreateIdentity("trusted", "1.3.6.1.5.5.7.3.2");
    using X509Certificate2 other = CreateIdentity("other", "1.3.6.1.5.5.7.3.2");
    using var listener = new SecureListener(IPAddress.Loopback, 0, server, SHA256.HashData(trusted.RawData));
    listener.Start();
    Task<SslStream> accept = listener.AcceptAsync(timeout);
    using var socket = new TcpClient();
    await socket.ConnectAsync(IPAddress.Loopback, listener.LocalPort, timeout);
    await using var client = new SslStream(socket.GetStream(), false, (_, certificate, _, _) =>
        certificate is not null && CryptographicOperations.FixedTimeEquals(SHA256.HashData(certificate.GetRawCertData()), SHA256.HashData(server.RawData)));
    Exception? clientError = null;
    try
    {
        await client.AuthenticateAsClientAsync(new SslClientAuthenticationOptions
        {
            TargetHost = "server",
            EnabledSslProtocols = SslProtocols.Tls13,
            ClientCertificates = new X509CertificateCollection { validClient ? trusted : other },
            CertificateRevocationCheckMode = X509RevocationMode.NoCheck
        }, timeout);
    }
    catch (Exception error) when (error is AuthenticationException or IOException) { clientError = error; }
    try
    {
        await using SslStream received = await accept;
        if (!validClient) throw new Exception("Untrusted client certificate accepted");
        if (clientError is not null) throw new Exception("Trusted client rejected", clientError);
        await client.WriteAsync(new byte[] { 42 }, timeout);
        byte[] buffer = new byte[1];
        if (await received.ReadAsync(buffer, timeout) != 1 || buffer[0] != 42) throw new Exception("TLS stream data mismatch");
    }
    catch (Exception error) when (!validClient && error is (AuthenticationException or IOException))
    {
        return; // Expected: server must reject mismatched client pin.
    }
}

static async Task CheckSenderAsync(CancellationToken timeout)
{
    using X509Certificate2 server = CreateIdentity("server", "1.3.6.1.5.5.7.3.1");
    using X509Certificate2 client = CreateIdentity("client", "1.3.6.1.5.5.7.3.2");
    using var listener = new SecureListener(IPAddress.Loopback, 0, server, SHA256.HashData(client.RawData));
    listener.Start();
    Task<SslStream> accept = listener.AcceptAsync(timeout);
    await using SecureSender sender = await SecureSender.ConnectAsync("127.0.0.1", listener.LocalPort, client, SHA256.HashData(server.RawData), timeout);
    await using SslStream received = await accept;
    var payload = new Dictionary<string, JsonElement> { ["usage"] = JsonSerializer.SerializeToElement(4), ["down"] = JsonSerializer.SerializeToElement(true) };
    await sender.SendAsync(new Envelope(1, "key", payload), timeout);
    byte[] buffer = new byte[1024];
    var decoder = new FrameDecoder();
    IReadOnlyList<Envelope> messages = Array.Empty<Envelope>();
    while (messages.Count == 0)
    {
        int read = await received.ReadAsync(buffer, timeout);
        if (read == 0) throw new Exception("Connection closed before frame");
        messages = decoder.Append(buffer.AsSpan(0, read));
    }
    if (InputValidator.Parse(messages[0]) != new KeyInput(4, true)) throw new Exception("Sender frame mismatch");
    Task monitor = sender.MonitorPeerAsync(timeout);
    await received.DisposeAsync();
    bool disconnected = false;
    try { await monitor; }
    catch (IOException) { disconnected = true; }
    if (!disconnected) throw new Exception("Sender did not detect peer disconnect");
}

static async Task CheckSenderRejectsWrongServerPin(CancellationToken timeout)
{
    using X509Certificate2 server = CreateIdentity("server", "1.3.6.1.5.5.7.3.1");
    using X509Certificate2 client = CreateIdentity("client", "1.3.6.1.5.5.7.3.2");
    using var listener = new SecureListener(IPAddress.Loopback, 0, server, SHA256.HashData(client.RawData));
    listener.Start();
    Task<SslStream> accept = listener.AcceptAsync(timeout);
    bool rejected = false;
    try { await using var sender = await SecureSender.ConnectAsync("127.0.0.1", listener.LocalPort, client, new byte[32], timeout); }
    catch (Exception error) when (error is AuthenticationException or IOException) { rejected = true; }
    try { await using SslStream unexpected = await accept; }
    catch (Exception error) when (error is AuthenticationException or IOException) { }
    if (!rejected) throw new Exception("Sender accepted wrong server pin");
}

static async Task CheckStalledHandshakeAsync(CancellationToken timeout)
{
    using X509Certificate2 server = CreateIdentity("server", "1.3.6.1.5.5.7.3.1");
    using X509Certificate2 client = CreateIdentity("client", "1.3.6.1.5.5.7.3.2");
    using var listener = new SecureListener(IPAddress.Loopback, 0, server, SHA256.HashData(client.RawData));
    listener.Start();
    Task<SslStream> accept = listener.AcceptAsync(timeout);
    using var raw = new TcpClient();
    await raw.ConnectAsync(IPAddress.Loopback, listener.LocalPort, timeout);
    using var guard = new CancellationTokenSource(TimeSpan.FromSeconds(15));
    bool timedOut = false;
    try { await using SslStream unexpected = await accept.WaitAsync(guard.Token); }
    catch (OperationCanceledException) when (!guard.IsCancellationRequested && !timeout.IsCancellationRequested) { timedOut = true; }
    if (!timedOut) throw new Exception("Stalled TLS handshake did not time out");
}

using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(60));
await CheckStalledHandshakeAsync(timeout.Token);
await CheckSenderRejectsWrongServerPin(timeout.Token);
await CheckSenderAsync(timeout.Token);
await CheckAsync(true, timeout.Token);
await CheckAsync(false, timeout.Token);
Console.WriteLine("TLS pin acceptance and rejection passed.");
