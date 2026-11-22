param([Parameter(Mandatory=$true)][string]$StateDirectory)
$ErrorActionPreference = 'Stop'
$identity = Join-Path $StateDirectory 'tls.pem'
if (Test-Path -LiteralPath $identity) { return }
[void][System.IO.Directory]::CreateDirectory($StateDirectory)
# Keep the certificate and private key together so interrupted setup never mixes identities.
$rsa = [System.Security.Cryptography.RSACng]::new(2048)
try {
    $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
        'CN=NamiHub', $rsa, [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $names = [System.Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder]::new()
    $names.AddDnsName('localhost')
    $names.AddIPAddress([System.Net.IPAddress]::Loopback)
    foreach ($addr in [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName())) {
        if ($addr.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) { $names.AddIPAddress($addr) }
    }
    $request.CertificateExtensions.Add($names.Build())
    $now = [DateTimeOffset]::UtcNow
    $cert = $request.CreateSelfSigned($now.AddMinutes(-5), $now.AddYears(2))
    try {
        $der = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
        $keyBytes = $rsa.Key.Export([System.Security.Cryptography.CngKeyBlobFormat]::Pkcs8PrivateBlob)
        $cert64 = [Convert]::ToBase64String($der, 'InsertLineBreaks')
        $key64 = [Convert]::ToBase64String($keyBytes, 'InsertLineBreaks')
        $temporary = Join-Path $StateDirectory ([Guid]::NewGuid().ToString() + '.tmp')
        try {
            [IO.File]::WriteAllText($temporary, "-----BEGIN CERTIFICATE-----`n$cert64`n-----END CERTIFICATE-----`n-----BEGIN PRIVATE KEY-----`n$key64`n-----END PRIVATE KEY-----`n", [Text.Encoding]::ASCII)
            [IO.File]::Move($temporary, $identity)
        } finally {
            if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
        }
    } finally { $cert.Dispose() }
} finally { $rsa.Dispose() }
