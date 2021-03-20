# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# ISO 15118 Plug & Charge (PnC) PKI Certificate & OCSP Verification Engine
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import string
import time_util as TimeUtil
import token_hash as TokenHash

# OCSP Certificate Status Codes (RFC 6960)
class OCSPCertStatus
    static var GOOD    = "Good"
    static var REVOKED = "Revoked"
    static var UNKNOWN = "Unknown"
end

# eMAID (e-Mobility Account Identifier) Parser & Validator (DIN 91286 / ISO 15118-2)
# Format: 2-char country code + 3-char provider ID + 1-char separator + 8-char instance ID + 1-char check digit
# Example: "US*STN*E00123456*8"
class EMAIDValidator
    static def validate_format(emaid_str)
        if emaid_str == nil return false end
        var s = str(emaid_str)
        if size(s) < 10 || size(s) > 22
            return false
        end
        # Must contain asterisks or hyphens as separators
        if string.find(s, "*") < 0 && string.find(s, "-") < 0
            return false
        end
        return true
    end

    static def extract_country_code(emaid_str)
        var s = str(emaid_str)
        if size(s) >= 2
            return s[0 .. 1]
        end
        return ""
    end
end

# Contract Certificate with eMAID and Elliptic Curve Public Key
class ContractCertificate
    var serial_number
    var emaid
    var issuer_ca_dn
    var valid_from_epoch
    var valid_to_epoch
    var public_key_fingerprint
    var ocsp_status

    def init(serial, emaid_str, issuer, not_before, not_after)
        self.serial_number = str(serial)
        self.emaid = str(emaid_str)
        self.issuer_ca_dn = str(issuer)
        self.valid_from_epoch = int(not_before)
        self.valid_to_epoch = int(not_after)
        self.public_key_fingerprint = TokenHash.hex_digest(self.serial_number + ":" + self.emaid, "PNC_PUBKEY")
        self.ocsp_status = OCSPCertStatus.GOOD
    end

    def is_valid_at(current_epoch)
        var t = int(current_epoch)
        if self.ocsp_status != OCSPCertStatus.GOOD
            return false
        end
        return (t >= self.valid_from_epoch && t <= self.valid_to_epoch)
    end

    def set_ocsp_status(status_str)
        self.ocsp_status = str(status_str)
    end
end

# ISO 15118 Plug and Charge (PnC) PKI Validator
class PlugAndChargePKI
    var trusted_root_cas
    var installed_contract_certs
    var ocsp_cache
    var ocsp_cache_ttl_sec

    def init()
        self.trusted_root_cas = {}
        self.installed_contract_certs = {}
        self.ocsp_cache = {}
        self.ocsp_cache_ttl_sec = 86400 # 24 hours OCSP response cache
        self._initialize_trusted_roots()
    end

    def _initialize_trusted_roots()
        self.trusted_root_cas["CN=V2GRootCA-1"] = {
            "subject": "CN=V2GRootCA-1,O=V2G PKI Consortium,C=US",
            "fingerprint": "8F3A2B1C9D8E7F01A2B3C4D5E6F70819"
        }
    end

    def install_contract_cert(contract_cert)
        if !EMAIDValidator.validate_format(contract_cert.emaid)
            return {"status": "Failed", "reason": "InvalidEMAIDFormat"}
        end
        self.installed_contract_certs[contract_cert.serial_number] = contract_cert
        return {"status": "Accepted", "reason": nil}
    end

    # Perform complete PnC validation: format, chain, validity window, and OCSP status
    def validate_pnc_authentication(serial_number, signature_token, current_epoch)
        var sn = str(serial_number)
        if !self.installed_contract_certs.contains(sn)
            return {"authenticated": false, "reason": "CertificateNotFound"}
        end

        var cert = self.installed_contract_certs[sn]

        # 1. Date window check
        if !cert.is_valid_at(current_epoch)
            var reason = "CertificateExpired"
            if cert.ocsp_status == OCSPCertStatus.REVOKED
                reason = "CertificateRevokedByOCSP"
            end
            return {"authenticated": false, "reason": reason}
        end

        # 2. Issuer chain check
        if !self.trusted_root_cas.contains(cert.issuer_ca_dn)
            return {"authenticated": false, "reason": "UntrustedIssuerCA"}
        end

        # 3. Cryptographic signature check on challenge token
        var expected_token = TokenHash.hex_digest(cert.public_key_fingerprint + ":" + str(current_epoch), "V2G_CHALLENGE")
        var is_sig_valid = TokenHash.secure_compare(str(signature_token), expected_token)
        if !is_sig_valid
            return {"authenticated": false, "reason": "InvalidCryptographicSignature"}
        end

        return {
            "authenticated": true,
            "emaid": cert.emaid,
            "serial": cert.serial_number,
            "reason": nil
        }
    end

    # Handle OCSP request check
    def query_ocsp_status(serial_number)
        var sn = str(serial_number)
        if self.ocsp_cache.contains(sn)
            return self.ocsp_cache[sn]
        end

        if self.installed_contract_certs.contains(sn)
            var cert = self.installed_contract_certs[sn]
            var res = {
                "serial": sn,
                "status": cert.ocsp_status,
                "thisUpdate": 1770000000,
                "nextUpdate": 1770000000 + self.ocsp_cache_ttl_sec
            }
            self.ocsp_cache[sn] = res
            return res
        end

        return {"serial": sn, "status": OCSPCertStatus.UNKNOWN}
    end

    # Revoke a certificate via OCSP push
    def revoke_certificate(serial_number)
        var sn = str(serial_number)
        if self.installed_contract_certs.contains(sn)
            var cert = self.installed_contract_certs[sn]
            cert.set_ocsp_status(OCSPCertStatus.REVOKED)
            self.ocsp_cache.remove(sn)
            return true
        end
        return false
    end
end

return {
    "OCSPCertStatus": OCSPCertStatus,
    "EMAIDValidator": EMAIDValidator,
    "ContractCertificate": ContractCertificate,
    "PlugAndChargePKI": PlugAndChargePKI
}
