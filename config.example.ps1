# Copy this file to config.ps1 (same folder) and adjust the values.
# config.ps1 is ignored by git. NEVER put passwords in this file.

$Config = @{
    # Name the iPads use to reach the Gateway (must not be an IP address).
    # - If the office router/DNS can map a name to the Gateway IP:  'efb-gateway.rtaf602.com'
    # - If not, use sslip.io with the Gateway IP written with dashes, e.g. for 192.168.1.10:
    #       'efb-gateway-192-168-1-10.sslip.io'
    Domain             = 'efb-gateway.rtaf602.com'

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
    KeySize            = 2048
    WarnDays           = 30
}
