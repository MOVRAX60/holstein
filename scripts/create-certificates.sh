#!/bin/bash

# =============================================================================
# MONITORING PORTAL - SSL CERTIFICATE CREATION SCRIPT
# =============================================================================
# This script creates SSL certificates for the monitoring portal:
# - Self-signed certificates for development/testing
# - Internal CA with signed certificates for production
# - Proper Subject Alternative Names (SAN) configuration
# - Secure key permissions
#
# Usage: ./create-certificates.sh [--domain DOMAIN] [--ca-only] [--self-signed]
# Options:
#   --domain DOMAIN: Specify domain (default from .env or monitor.domain.com)
#   --ca-only: Only create Certificate Authority
#   --self-signed: Create simple self-signed certificate (not recommended for production)

set -euo pipefail

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CERTS_DIR="$PROJECT_DIR/certs"
CA_DIR="$CERTS_DIR/ca"
LOG_FILE="$PROJECT_DIR/logs/cert-creation.log"

# Parse arguments
DOMAIN=""
CA_ONLY=false
SELF_SIGNED=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --ca-only)
            CA_ONLY=true
            shift
            ;;
        --self-signed)
            SELF_SIGNED=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--domain DOMAIN] [--ca-only] [--self-signed] [--force]"
            exit 1
            ;;
    esac
done

# Load environment variables if available
if [[ -f "$PROJECT_DIR/.env" ]]; then
    source "$PROJECT_DIR/.env"
fi

# Set domain from env or default
if [[ -z "$DOMAIN" ]]; then
    DOMAIN="${DOMAIN:-monitor.domain.com}"
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Certificate configuration
COUNTRY="US"
STATE="State"
CITY="City"
ORG="YourOrganization"
OU="IT Department"
CA_CN="Internal Monitoring CA"
CERT_CN="$DOMAIN"

# Key sizes and validity
RSA_KEY_SIZE=4096
CA_VALIDITY_DAYS=3650  # 10 years
CERT_VALIDITY_DAYS=365 # 1 year

# -----------------------------------------------------------------------------
# LOGGING FUNCTIONS
# -----------------------------------------------------------------------------
log() {
    echo "[$TIMESTAMP] $1" | tee -a "$LOG_FILE"
}

error() {
    echo "[$TIMESTAMP] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

success() {
    echo "[$TIMESTAMP] SUCCESS: $1" | tee -a "$LOG_FILE"
}

warn() {
    echo "[$TIMESTAMP] WARNING: $1" | tee -a "$LOG_FILE"
}

# -----------------------------------------------------------------------------
# VALIDATION FUNCTIONS
# -----------------------------------------------------------------------------
check_requirements() {
    log "Checking requirements..."

    # Check if OpenSSL is available
    if ! command -v openssl >/dev/null 2>&1; then
        error "OpenSSL is required but not found"
        exit 1
    fi

    local openssl_version
    openssl_version=$(openssl version | cut -d' ' -f2)
    success "OpenSSL version: $openssl_version"

    # Create directories
    mkdir -p "$CERTS_DIR" "$CA_DIR" "$(dirname "$LOG_FILE")"

    success "Requirements check passed"
}

validate_domain() {
    log "Validating domain: $DOMAIN"

    # Basic domain validation
    if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        error "Invalid domain format: $DOMAIN"
        exit 1
    fi

    success "Domain validation passed"
}

check_existing_certificates() {
    local cert_exists=false
    local ca_exists=false

    # Check if certificate already exists
    if [[ -f "$CERTS_DIR/${DOMAIN}.crt" ]]; then
        cert_exists=true
        warn "Certificate for $DOMAIN already exists"
    fi

    # Check if CA already exists
    if [[ -f "$CA_DIR/ca-cert.pem" ]]; then
        ca_exists=true
        warn "Certificate Authority already exists"
    fi

    if [[ "$cert_exists" == "true" || "$ca_exists" == "true" ]] && [[ "$FORCE" != "true" ]]; then
        echo
        echo "⚠️  Existing certificates found!"
        echo "Certificate: $([[ -f "$CERTS_DIR/${DOMAIN}.crt" ]] && echo "EXISTS" || echo "NOT FOUND")"
        echo "CA: $([[ -f "$CA_DIR/ca-cert.pem" ]] && echo "EXISTS" || echo "NOT FOUND")"
        echo

        read -p "Do you want to overwrite existing certificates? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log "Certificate creation cancelled by user"
            exit 0
        fi
    fi
}

# -----------------------------------------------------------------------------
# CERTIFICATE CREATION FUNCTIONS
# -----------------------------------------------------------------------------
create_ca_certificate() {
    log "Creating Certificate Authority..."

    # Generate CA private key
    log "Generating CA private key..."
    openssl genrsa -out "$CA_DIR/ca-key.pem" $RSA_KEY_SIZE
    chmod 600 "$CA_DIR/ca-key.pem"

    # Generate CA certificate
    log "Generating CA certificate..."
    openssl req -new -x509 -days $CA_VALIDITY_DAYS \
        -key "$CA_DIR/ca-key.pem" \
        -sha256 \
        -out "$CA_DIR/ca-cert.pem" \
        -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORG/OU=$OU/CN=$CA_CN"

    chmod 644 "$CA_DIR/ca-cert.pem"

    success "Certificate Authority created"
    log "CA certificate: $CA_DIR/ca-cert.pem"
    log "CA private key: $CA_DIR/ca-key.pem (SECURE)"
}

create_server_certificate() {
    log "Creating server certificate for $DOMAIN..."

    # Generate server private key
    log "Generating server private key..."
    openssl genrsa -out "$CERTS_DIR/${DOMAIN}.key" $RSA_KEY_SIZE
    chmod 600 "$CERTS_DIR/${DOMAIN}.key"

    # Create certificate signing request (CSR)
    log "Creating certificate signing request..."
    openssl req -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORG/OU=$OU/CN=$CERT_CN" \
        -sha256 -new \
        -key "$CERTS_DIR/${DOMAIN}.key" \
        -out "$CERTS_DIR/${DOMAIN}.csr"

    # Create extensions file for SAN
    log "Creating certificate extensions..."
    cat > "$CERTS_DIR/${DOMAIN}-extensions.cnf" << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $DOMAIN
DNS.2 = *.$DOMAIN
DNS.3 = localhost
DNS.4 = *.localhost
IP.1 = 127.0.0.1
IP.2 = ::1
IP.3 = 192.168.1.100
EOF

    # Generate server certificate signed by CA
    log "Signing server certificate with CA..."
    openssl x509 -req -days $CERT_VALIDITY_DAYS \
        -in "$CERTS_DIR/${DOMAIN}.csr" \
        -CA "$CA_DIR/ca-cert.pem" \
        -CAkey "$CA_DIR/ca-key.pem" \
        -out "$CERTS_DIR/${DOMAIN}.crt" \
        -extensions v3_req \
        -extfile "$CERTS_DIR/${DOMAIN}-extensions.cnf" \
        -CAcreateserial

    chmod 644 "$CERTS_DIR/${DOMAIN}.crt"

    # Create full certificate chain
    log "Creating certificate chain..."
    cat "$CERTS_DIR/${DOMAIN}.crt" "$CA_DIR/ca-cert.pem" > "$CERTS_DIR/${DOMAIN}-fullchain.crt"

    # Clean up temporary files
    rm -f "$CERTS_DIR/${DOMAIN}.csr" "$CERTS_DIR/${DOMAIN}-extensions.cnf"

    success "Server certificate created and signed"
    log "Server certificate: $CERTS_DIR/${DOMAIN}.crt"
    log "Server private key: $CERTS_DIR/${DOMAIN}.key (SECURE)"
    log "Certificate chain: $CERTS_DIR/${DOMAIN}-fullchain.crt"
}

create_self_signed_certificate() {
    log "Creating self-signed certificate for $DOMAIN..."

    # Generate private key
    log "Generating private key..."
    openssl genrsa -out "$CERTS_DIR/${DOMAIN}.key" $RSA_KEY_SIZE
    chmod 600 "$CERTS_DIR/${DOMAIN}.key"

    # Create extensions file
    cat > "$CERTS_DIR/self-signed-extensions.cnf" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = $COUNTRY
ST = $STATE
L = $CITY
O = $ORG
OU = $OU
CN = $CERT_CN

[v3_req]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $DOMAIN
DNS.2 = *.$DOMAIN
DNS.3 = localhost
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

    # Generate self-signed certificate
    log "Generating self-signed certificate..."
    openssl req -new -x509 -days $CERT_VALIDITY_DAYS \
        -key "$CERTS_DIR/${DOMAIN}.key" \
        -out "$CERTS_DIR/${DOMAIN}.crt" \
        -config "$CERTS_DIR/self-signed-extensions.cnf" \
        -extensions v3_req

    chmod 644 "$CERTS_DIR/${DOMAIN}.crt"

    # Clean up
    rm -f "$CERTS_DIR/self-signed-extensions.cnf"

    success "Self-signed certificate created"
    log "Certificate: $CERTS_DIR/${DOMAIN}.crt"
    log "Private key: $CERTS_DIR/${DOMAIN}.key (SECURE)"
}

verify_certificates() {
    log "Verifying created certificates..."

    # Verify certificate
    if [[ -f "$CERTS_DIR/${DOMAIN}.crt" ]]; then
        local cert_subject
        cert_subject=$(openssl x509 -subject -noout -in "$CERTS_DIR/${DOMAIN}.crt")
        log "Certificate subject: $cert_subject"

        local cert_issuer
        cert_issuer=$(openssl x509 -issuer -noout -in "$CERTS_DIR/${DOMAIN}.crt")
        log "Certificate issuer: $cert_issuer"

        local cert_dates
        cert_dates=$(openssl x509 -dates -noout -in "$CERTS_DIR/${DOMAIN}.crt")
        log "Certificate validity: $cert_dates"

        # Verify certificate against CA (if not self-signed)
        if [[ -f "$CA_DIR/ca-cert.pem" ]] && [[ "$SELF_SIGNED" != "true" ]]; then
            if openssl verify -CAfile "$CA_DIR/ca-cert.pem" "$CERTS_DIR/${DOMAIN}.crt" >/dev/null 2>&1; then
                success "Certificate verification against CA passed"
            else
                error "Certificate verification against CA failed"
            fi
        fi

        # Check SAN extensions
        local san_info
        san_info=$(openssl x509 -text -noout -in "$CERTS_DIR/${DOMAIN}.crt" | grep -A1 "Subject Alternative Name" | tail -1 || echo "None")
        log "Subject Alternative Names: $san_info"

    else
        error "Certificate file not found for verification"
        return 1
    fi

    success "Certificate verification completed"
}

create_acme_placeholder() {
    log "Creating acme.json placeholder for Let's Encrypt..."

    local acme_file="$CERTS_DIR/acme.json"

    if [[ ! -f "$acme_file" ]]; then
        echo "{}" > "$acme_file"
        chmod 600 "$acme_file"
        success "acme.json placeholder created"
    else
        log "acme.json already exists"
    fi
}

generate_install_instructions() {
    log "Generating installation instructions..."

    local instructions_file="$CERTS_DIR/INSTALL_INSTRUCTIONS.md"

    cat > "$instructions_file" << EOF
# SSL Certificate Installation Instructions

Generated: $(date)
Domain: $DOMAIN

## Files Created

### Certificate Files
- **${DOMAIN}.crt** - Server certificate (public)
- **${DOMAIN}.key** - Server private key (SECURE - protect this!)
$(if [[ "$SELF_SIGNED" != "true" ]]; then
echo "- **${DOMAIN}-fullchain.crt** - Certificate with CA chain"
echo "- **ca/ca-cert.pem** - Certificate Authority certificate"
echo "- **ca/ca-key.pem** - Certificate Authority private key (SECURE)"
fi)

### Security
- Private keys have 600 permissions (owner read/write only)
- Certificate files have 644 permissions (world readable)

## Installation

### 1. Docker Compose Configuration
The certificates are already in the correct location for Docker Compose:
\`\`\`yaml
# traefik/dynamic.yml
tls:
  certificates:
    - certFile: /certs/${DOMAIN}.crt
      keyFile: /certs/${DOMAIN}.key
\`\`\`

### 2. Client Trust $(if [[ "$SELF_SIGNED" != "true" ]]; then echo "(CA Certificate)"; else echo "(Self-Signed)"; fi)

$(if [[ "$SELF_SIGNED" != "true" ]]; then cat << 'EOFCA'
#### Windows
1. Copy \`ca/ca-cert.pem\` to client machine
2. Rename to \`ca-cert.crt\`
3. Double-click and install to "Trusted Root Certification Authorities"

#### Linux
\`\`\`bash
sudo cp ca/ca-cert.pem /usr/local/share/ca-certificates/monitoring-ca.crt
sudo update-ca-certificates
\`\`\`

#### macOS
\`\`\`bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ca/ca-cert.pem
\`\`\`

#### Browsers
- Chrome/Edge: Settings → Privacy → Manage certificates → Authorities → Import
- Firefox: Settings → Certificates → View Certificates → Authorities → Import
EOFCA
else cat << 'EOFSS'
#### Browser Trust (Self-Signed)
1. Visit https://${DOMAIN} in browser
2. Click "Advanced" → "Proceed to ${DOMAIN} (unsafe)"
3. Click the lock icon → Certificate → Details → "Copy to File"
4. Install to "Trusted Root Certification Authorities" (Windows) or equivalent

**Note**: Self-signed certificates will show security warnings. Consider using a proper CA for production.
EOFSS
fi)

## Testing

### 1. Verify Certificate
\`\`\`bash
openssl x509 -text -noout -in ${DOMAIN}.crt
openssl verify $(if [[ "$SELF_SIGNED" != "true" ]]; then echo "-CAfile ca/ca-cert.pem"; fi) ${DOMAIN}.crt
\`\`\`

### 2. Test SSL Connection
\`\`\`bash
openssl s_client -connect ${DOMAIN}:443 -servername ${DOMAIN}
\`\`\`

### 3. Test with curl
\`\`\`bash
curl -I https://${DOMAIN}
# Or skip verification for testing:
curl -k -I https://${DOMAIN}
\`\`\`

## Certificate Renewal

$(if [[ "$SELF_SIGNED" != "true" ]]; then cat << 'EOFRENEWAL'
### Automatic Renewal
Create a script to renew before expiration:

\`\`\`bash
#!/bin/bash
cd $(dirname "$0")
./create-certificates.sh --domain $DOMAIN --force
docker-compose restart traefik
\`\`\`

Add to crontab for monthly check:
\`\`\`
0 0 1 * * /path/to/monitoring-portal/scripts/create-certificates.sh --domain $DOMAIN --force && cd /path/to/monitoring-portal && docker-compose restart traefik
\`\`\`
EOFRENEWAL
else cat << 'EOFSELFRENEWAL'
### Manual Renewal
Re-run the certificate creation script before expiration:
\`\`\`bash
./create-certificates.sh --domain $DOMAIN --self-signed --force
docker-compose restart traefik
\`\`\`
EOFSELFRENEWAL
fi)

## Security Notes

1. **Protect Private Keys**: Never share .key files
2. **Backup Certificates**: Store securely offsite
3. **Monitor Expiration**: Set calendar reminders
4. **Regular Updates**: Keep OpenSSL updated
5. **Access Control**: Limit who can access certificate files

---
Generated by Monitoring Portal Certificate Creation Script
EOF

    chmod 644 "$instructions_file"
    success "Installation instructions created: $instructions_file"
}

# -----------------------------------------------------------------------------
# MAIN EXECUTION
# -----------------------------------------------------------------------------
main() {
    echo "🔐 SSL Certificate Creation for Monitoring Portal"
    echo "================================================"
    echo "Domain: $DOMAIN"
    echo "Mode: $(if [[ "$SELF_SIGNED" == "true" ]]; then echo "Self-signed"; elif [[ "$CA_ONLY" == "true" ]]; then echo "CA only"; else echo "CA + Server certificate"; fi)"
    echo

    # Pre-flight checks
    check_requirements
    validate_domain
    check_existing_certificates

    # Create certificates based on mode
    if [[ "$SELF_SIGNED" == "true" ]]; then
        create_self_signed_certificate
    else
        create_ca_certificate

        if [[ "$CA_ONLY" != "true" ]]; then
            create_server_certificate
        fi
    fi

    # Additional guides
    create_acme_placeholder
    verify_certificates
    generate_install_instructions

    success "Certificate creation completed successfully!"

    # Display summary
    echo
    echo "🎉 Certificates created successfully!"
    echo "📁 Location: $CERTS_DIR/"
    echo
    echo "📋 Files created:"
    ls -la "$CERTS_DIR/" | grep -E "\.(crt|key|pem)$" | while read -r line; do
        echo "   $line"
    done
    echo
    echo "📖 Next steps:"
    echo "   1. Review: $CERTS_DIR/INSTALL_INSTRUCTIONS.md"
    echo "   2. Trust the $(if [[ "$SELF_SIGNED" == "true" ]]; then echo "self-signed certificate"; else echo "CA certificate"; fi) on client machines"
    echo "   3. Start services: docker-compose up -d"
    echo "   4. Test: https://$DOMAIN"
    echo

    if [[ "$SELF_SIGNED" != "true" ]]; then
        echo "🔒 Security reminder:"
        echo "   - Protect the CA private key: $CA_DIR/ca-key.pem"
        echo "   - Set up certificate renewal before expiration"
        echo
    fi
}

# Handle script interruption
trap 'error "Certificate creation interrupted"; exit 1' INT TERM

# Run main function
main "$@"