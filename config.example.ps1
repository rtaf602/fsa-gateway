# Copy this file to config.ps1 (same folder) and adjust the values.
# config.ps1 is ignored by git. NEVER put passwords in this file.

$Config = @{
    # Name the iPads use to reach the Gateway (must not be an IP address).
    # Registered at Namecheap; A record "@" points to the Gateway LAN IP.
    Domain             = 'rtaf602fsagateway.com'

    # Wildfly installation folder used by the Flysmart+ Gateway
    WildflyPath        = 'C:\Airbus\Wildfly'

    # Windows service name of Wildfly
    WildflyServiceName = 'Wildfly'

    # HTTPS port configured in standalone.xml (default 8443)
    HttpsPort          = 8443

    # Working folder for keys and certificates (outside this git repository).
    WorkRoot           = 'C:\Airbus\ssl-work'

    # Unit root CA (created once, reused at every renewal so iPads keep trusting it)
    CaRoot             = 'C:\Airbus\ssl-work\ca'
    CaName             = 'RTAF602 EFB Root CA'
    CaValidityYears    = 10

    # Gateway certificate lifetime. iOS rejects TLS server certificates > 825 days.
    CertValidityDays   = 800

    # RSA key size and expiry warning used by the test script
    # Two-letter country code put in the certificate request (required by Namecheap)
    Country            = 'TH'

    KeySize            = 2048
    WarnDays           = 30
}
