# Copy this file to config.ps1 (same folder) and adjust the values.
# config.ps1 is ignored by git. NEVER put passwords in this file.

$Config = @{
    # Domain name of the Gateway (must be covered by the certificate, no IP)
    Domain             = 'efb-gateway.rtaf602.com'

    # Wildfly installation folder used by the Flysmart+ Gateway
    WildflyPath        = 'C:\Airbus\Wildfly'

    # Windows service name of Wildfly
    WildflyServiceName = 'Wildfly'

    # HTTPS port configured in standalone.xml (default 8443)
    HttpsPort          = 8443

    # Working folder for keys, CSR and certificates.
    # Keep it OUTSIDE this git repository: it contains the private key.
    WorkRoot           = 'C:\Airbus\ssl-work'

    # RSA key size (2048 minimum, 3072 also fine)
    KeySize            = 2048

    # Warn when the certificate expires in less than N days (04-Test-Gateway.ps1)
    WarnDays           = 30

    # ---- Private CA (option A: VPN + internal CA) -------------------------
    # Folder holding the root CA keystore. Put it on a removable/encrypted drive,
    # NOT on the Gateway server and NOT in this repository.
    CaRoot             = 'E:\rtaf602-ca'
    CaName             = 'RTAF602 EFB Root CA'
    CaValidityYears    = 10
    # Gateway certificate lifetime. iOS rejects TLS server certificates > 825 days.
    CertValidityDays   = 800

    # ---- Firewall (05-Set-Firewall.ps1) -----------------------------------
    # Networks allowed to reach the Gateway HTTPS port: VPN client pool + office LAN.
    AllowedSubnets     = @('10.8.0.0/24', '192.168.1.0/24')
}
