using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using InputBridge.Windows;

static X509Certificate2 CreateIdentity(string name, string usage)
{
    using RSA key = RSA.Create(2048);
    var request = new CertificateRequest($"CN={name}", key, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
    var usages = new OidCollection { new Oid(usage) };
    request.CertificateExtensions.Add(new X509EnhancedKeyUsageExtension(usages, true));
    request.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.DigitalSignature, true));
    return request.CreateSelfSigned(DateTimeOffset.UtcNow.AddMinutes(-5), DateTimeOffset.UtcNow.AddHours(1));
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

using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(30));
await CheckAsync(true, timeout.Token);
await CheckAsync(false, timeout.Token);
Console.WriteLine("TLS pin acceptance and rejection passed.");
