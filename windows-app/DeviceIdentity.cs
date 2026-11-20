using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text.Json;

namespace InputBridge.Windows;

/// <summary>
/// Creates and persists this PC's device identity automatically so the user never
/// touches certificate files. The PFX lives in the per-user LocalAppData folder,
/// which is ACL-restricted to the current Windows account; this is alpha-grade
/// protection and must be replaced with DPAPI/CNG storage before a stable release.
/// </summary>
internal sealed class DeviceIdentity : IDisposable
{
    public string Id { get; }
    public string Name { get; }
    public X509Certificate2 Certificate { get; }
    public string Fingerprint { get; }
    public const ushort ServicePort = 24_800;

    private sealed record Metadata(string Id, string Name);

    private DeviceIdentity(string id, string name, X509Certificate2 certificate)
    {
        Id = id; Name = name; Certificate = certificate;
        Fingerprint = Convert.ToHexString(SHA256.HashData(certificate.RawData)).ToLowerInvariant();
    }

    private static string StorageDirectory => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CursorLoom");

    public static DeviceIdentity LoadOrCreate()
    {
        System.IO.Directory.CreateDirectory(StorageDirectory);
        string metadataPath = Path.Combine(StorageDirectory, "device.json");
        string pfxPath = Path.Combine(StorageDirectory, "identity.pfx");

        if (File.Exists(metadataPath) && File.Exists(pfxPath))
        {
            try
            {
                var metadata = JsonSerializer.Deserialize<Metadata>(File.ReadAllText(metadataPath));
                if (metadata is not null && Guid.TryParse(metadata.Id, out _))
                {
                    var existing = new X509Certificate2(File.ReadAllBytes(pfxPath), (string?)null,
                        X509KeyStorageFlags.UserKeySet);
                    return new DeviceIdentity(metadata.Id, metadata.Name, existing);
                }
            }
            catch (Exception error) when (error is CryptographicException or IOException or JsonException)
            {
                // Fall through and create a new identity rather than refusing to start.
            }
        }

        string id = Guid.NewGuid().ToString();
        string name = Environment.MachineName;
        using RSA key = RSA.Create(2048);
        var request = new CertificateRequest($"CN=CursorLoom {name}", key,
            HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        request.CertificateExtensions.Add(new X509BasicConstraintsExtension(false, false, 0, true));
        request.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.DigitalSignature, true));
        request.CertificateExtensions.Add(new X509EnhancedKeyUsageExtension(new OidCollection
        {
            new Oid("1.3.6.1.5.5.7.3.1"),
            new Oid("1.3.6.1.5.5.7.3.2")
        }, false));

        using X509Certificate2 generated = request.CreateSelfSigned(
            DateTimeOffset.UtcNow.AddDays(-1), DateTimeOffset.UtcNow.AddYears(2));
        byte[] pfx = generated.Export(X509ContentType.Pfx);
        File.WriteAllBytes(pfxPath, pfx);
        File.WriteAllText(metadataPath, JsonSerializer.Serialize(new Metadata(id, name)));

        var certificate = new X509Certificate2(pfx, (string?)null, X509KeyStorageFlags.UserKeySet);
        return new DeviceIdentity(id, name, certificate);
    }

    public void Dispose() => Certificate.Dispose();
}
