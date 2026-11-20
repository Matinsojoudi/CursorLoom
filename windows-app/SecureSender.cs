using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using InputBridge.Protocol;

namespace InputBridge.Windows;

/// <summary>
/// Experimental sender transport; not attached to the UI or input capture.
/// Connection and sends require an explicitly verified peer pin and consent by caller.
/// Callers must serialize sends and close the session on any input or transport failure.
/// </summary>
internal sealed class SecureSender : IAsyncDisposable
{
    private readonly TcpClient client;
    private readonly SslStream stream;
    private readonly SemaphoreSlim sendLock = new(1, 1);

    private SecureSender(TcpClient client, SslStream stream)
    {
        this.client = client;
        this.stream = stream;
    }

    public static async Task<SecureSender> ConnectAsync(string host, int port,
        X509Certificate2 identity, byte[] peerPin, CancellationToken cancellationToken)
    {
        if (peerPin.Length != 32) throw new ArgumentException("Expected SHA-256 certificate pin", nameof(peerPin));
        if (!identity.HasPrivateKey) throw new ArgumentException("Client certificate requires a private key", nameof(identity));
        byte[] expectedPin = (byte[])peerPin.Clone();
        var client = new TcpClient();
        SslStream? stream = null;
        try
        {
            await client.ConnectAsync(host, port, cancellationToken).ConfigureAwait(false);
            stream = new SslStream(client.GetStream(), leaveInnerStreamOpen: false,
                (_, peer, _, _) => peer is not null && CryptographicOperations.FixedTimeEquals(
                    SHA256.HashData(peer.GetRawCertData()), expectedPin));
            await stream.AuthenticateAsClientAsync(new SslClientAuthenticationOptions
            {
                TargetHost = host,
                ClientCertificates = new X509CertificateCollection { identity },
                EnabledSslProtocols = SslProtocols.Tls13,
                CertificateRevocationCheckMode = X509RevocationMode.NoCheck
            }, cancellationToken).ConfigureAwait(false);
            return new SecureSender(client, stream);
        }
        catch
        {
            if (stream is not null) await stream.DisposeAsync().ConfigureAwait(false);
            client.Dispose();
            throw;
        }
    }

    public async Task SendAsync(Envelope message, CancellationToken cancellationToken)
    {
        _ = InputValidator.Parse(message);
        byte[] frame = MessageCodec.Encode(message);
        await sendLock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try { await stream.WriteAsync(frame, cancellationToken).ConfigureAwait(false); }
        finally { sendLock.Release(); }
    }

    public async ValueTask DisposeAsync()
    {
        await stream.DisposeAsync().ConfigureAwait(false);
        client.Dispose();
        // The owner must await all sends before disposing this instance.
        sendLock.Dispose();
    }
}
