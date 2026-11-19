using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

namespace InputBridge.Windows;

/// <summary>
/// Experimental TLS listener. Does not apply input or accept connections automatically.
/// Both certificate pins must be verified out-of-band before starting a session.
/// Caller owns each accepted stream and must dispose it on any protocol error.
/// </summary>
internal sealed class SecureListener : IDisposable
{
    private readonly TcpListener listener;
    private readonly X509Certificate2 certificate;
    private readonly byte[] peerPin;

    public SecureListener(IPAddress address, int port, X509Certificate2 certificate, byte[] peerPin)
    {
        if (peerPin.Length != 32) throw new ArgumentException("Expected SHA-256 certificate pin", nameof(peerPin));
        if (!certificate.HasPrivateKey) throw new ArgumentException("Server certificate requires a private key", nameof(certificate));
        listener = new TcpListener(address, port);
        this.certificate = certificate;
        this.peerPin = (byte[])peerPin.Clone();
    }

    public void Start() => listener.Start(1);

    internal int LocalPort => ((IPEndPoint)listener.LocalEndpoint).Port;

    public async Task<SslStream> AcceptAsync(CancellationToken cancellationToken)
    {
        TcpClient client = await listener.AcceptTcpClientAsync(cancellationToken).ConfigureAwait(false);
        var stream = new SslStream(client.GetStream(), leaveInnerStreamOpen: false,
            userCertificateValidationCallback: (_, peer, _, _) =>
                peer is not null && CryptographicOperations.FixedTimeEquals(SHA256.HashData(peer.GetRawCertData()), peerPin));
        try
        {
            var options = new SslServerAuthenticationOptions
            {
                ServerCertificate = certificate,
                ClientCertificateRequired = true,
                EnabledSslProtocols = SslProtocols.Tls13,
                CertificateRevocationCheckMode = X509RevocationMode.NoCheck
            };
            await stream.AuthenticateAsServerAsync(options, cancellationToken).ConfigureAwait(false);
            return stream;
        }
        catch
        {
            await stream.DisposeAsync().ConfigureAwait(false);
            client.Dispose();
            throw;
        }
    }

    public void Dispose() => listener.Stop();
}
