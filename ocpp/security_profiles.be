# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# OCPP 2.0.1 Security Profiles, PKI Certificate Store & TLS Handshake
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import string
import time_util as TimeUtil
import token_hash as TokenHash

# Security Profile Levels defined in OCPP 2.0.1 Part 2
class SecurityProfileLevel
    static var PROFILE_1_UNSECURED_TRANSPORT  = 1 # Plain WebSocket with HTTP Basic Auth
    static var PROFILE_2_TLS_WITH_BASIC_AUTH   = 2 # TLS WebSocket with HTTP Basic Auth
    static var PROFILE_3_MUTUAL_TLS           = 3 # TLS WebSocket with Client Certificates
end

# Certificate Types in OCPP 2.0.1
class CertificateType
    static var CSMS_ROOT_CERTIFICATE = "CSMSRootCertificate"
    static var V2G_ROOT_CERTIFICATE  = "V2GRootCertificate"
    static var MO_ROOT_CERTIFICATE   = "MORootCertificate"
    static var CHARGING_STATION_CERT = "ChargingStationCertificate"
    static var V2G_STATION_CERT      = "V2GChargingStationCertificate"
end

# Simulated X.509 Public Key Certificate representation
class X509Certificate
    var serial_number
    var subject_dn
    var issuer_dn
    var cert_type
    var valid_from_epoch
    var valid_to_epoch
    var fingerprint_hash
    var is_revoked

    def init(serial, subject, issuer, ctype, not_before, not_after)
        self.serial_number = str(serial)
        self.subject_dn = str(subject)
        self.issuer_dn = str(issuer)
        self.cert_type = str(ctype)
        self.valid_from_epoch = int(not_before)
        self.valid_to_epoch = int(not_after)
        self.fingerprint_hash = TokenHash.hex_digest(self.serial_number + ":" + self.subject_dn, "CERT_SALT")
        self.is_revoked = false
    end

    def is_valid_at(current_epoch)
        var t = int(current_epoch)
        if self.is_revoked
            return false
        end
        return (t >= self.valid_from_epoch && t <= self.valid_to_epoch)
    end

    def revoke()
        self.is_revoked = true
    end

    def to_map()
        return {
            "serialNumber": self.serial_number,
            "subject": self.subject_dn,
            "issuer": self.issuer_dn,
            "type": self.cert_type,
            "validFrom": TimeUtil.to_iso8601(self.valid_from_epoch),
            "validTo": TimeUtil.to_iso8601(self.valid_to_epoch),
            "fingerprint": self.fingerprint_hash,
            "revoked": self.is_revoked
        }
    end
end

# Certificate Trust Store and Security Supervisor
class SecuritySupervisor
    var current_security_profile
    var station_identity
    var basic_auth_password_hash
    var root_certificates
    var station_certificates
    var max_certificates
    var security_events_log

    def init(station_id, initial_profile)
        self.station_identity = str(station_id)
        self.current_security_profile = (initial_profile != nil) ? int(initial_profile) : SecurityProfileLevel.PROFILE_2_TLS_WITH_BASIC_AUTH
        self.basic_auth_password_hash = nil
        self.root_certificates = {}
        self.station_certificates = {}
        self.max_certificates = 16
        self.security_events_log = []
    end

    def set_basic_auth_credentials(password_str)
        self.basic_auth_password_hash = TokenHash.hex_digest(str(password_str), self.station_identity)
    end

    def verify_basic_auth(username, password)
        if self.basic_auth_password_hash == nil
            return false
        end
        if str(username) != self.station_identity
            self._log_security_event("InvalidUsername", "Attempted authentication with unknown username")
            return false
        end
        var candidate_hash = TokenHash.hex_digest(str(password), self.station_identity)
        var valid = TokenHash.secure_compare(self.basic_auth_password_hash, candidate_hash)
        if !valid
            self._log_security_event("InvalidPassword", "Failed basic auth password check")
        end
        return valid
    end

    # Install Root Certificate
    def install_root_certificate(cert_obj)
        var count = size(self.root_certificates)
        if count >= self.max_certificates
            return {"status": "Rejected", "reason": "CertificateStoreFull"}
        end
        self.root_certificates[cert_obj.serial_number] = cert_obj
        self._log_security_event("RootCertificateInstalled", "Installed root cert " + cert_obj.serial_number)
        return {"status": "Accepted", "reason": nil}
    end

    # Install Station Leaf Certificate
    def install_station_certificate(cert_obj)
        self.station_certificates[cert_obj.cert_type] = cert_obj
        self._log_security_event("StationCertificateInstalled", "Installed station cert type " + cert_obj.cert_type)
        return {"status": "Accepted", "reason": nil}
    end

    # Verify TLS Handshake suitability for current profile
    def verify_tls_handshake(current_epoch)
        if self.current_security_profile == SecurityProfileLevel.PROFILE_1_UNSECURED_TRANSPORT
            return {"tls_ok": true, "profile": 1, "cipher_suite": "None"}
        elif self.current_security_profile == SecurityProfileLevel.PROFILE_2_TLS_WITH_BASIC_AUTH
            # Requires valid CSMS Root Certificate to authenticate the server
            var has_csms_root = false
            for s : self.root_certificates.keys()
                var c = self.root_certificates[s]
                if c.cert_type == CertificateType.CSMS_ROOT_CERTIFICATE && c.is_valid_at(current_epoch)
                    has_csms_root = true
                    break
                end
            end
            if !has_csms_root
                self._log_security_event("TLSVerificationFailed", "No valid CSMS root certificate in trust store")
                return {"tls_ok": false, "error": "MissingCSMSRootCert"}
            end
            return {"tls_ok": true, "profile": 2, "cipher_suite": "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"}
        elif self.current_security_profile == SecurityProfileLevel.PROFILE_3_MUTUAL_TLS
            # Requires both valid CSMS Root Cert and valid Station Client Cert
            var has_csms_root = false
            for s : self.root_certificates.keys()
                var c = self.root_certificates[s]
                if c.cert_type == CertificateType.CSMS_ROOT_CERTIFICATE && c.is_valid_at(current_epoch)
                    has_csms_root = true
                    break
                end
            end
            if !has_csms_root
                return {"tls_ok": false, "error": "MissingCSMSRootCert"}
            end

            var stn_cert = self.station_certificates.find(CertificateType.CHARGING_STATION_CERT)
            if stn_cert == nil || !stn_cert.is_valid_at(current_epoch)
                self._log_security_event("MutualTLSFailed", "Charging station client cert missing or expired")
                return {"tls_ok": false, "error": "ClientCertificateInvalid"}
            end

            return {"tls_ok": true, "profile": 3, "cipher_suite": "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384"}
        end
        return {"tls_ok": false, "error": "UnknownSecurityProfile"}
    end

    # Generate Certificate Signing Request (CSR) specification map
    def generate_station_csr(common_name, organization, country)
        return {
            "commonName": (common_name != nil) ? str(common_name) : self.station_identity,
            "organization": (organization != nil) ? str(organization) : "Stanchion Power Systems",
            "country": (country != nil) ? str(country) : "US",
            "keyAlgorithm": "ECDSA_SECP256R1",
            "signatureAlgorithm": "SHA256withECDSA"
        }
    end

    def _log_security_event(event_type, details)
        self.security_events_log.push({
            "type": str(event_type),
            "details": str(details),
            "count": size(self.security_events_log) + 1
        })
    end
end

return {
    "SecurityProfileLevel": SecurityProfileLevel,
    "CertificateType": CertificateType,
    "X509Certificate": X509Certificate,
    "SecuritySupervisor": SecuritySupervisor
}
