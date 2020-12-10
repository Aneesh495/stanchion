# Stanchion Test Suite: OCPP 2.0.1 Security Profiles & Certificate Store
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import security_profiles as SecProfileModule
import math
import string
import global

var SecurityProfileLevel = SecProfileModule["SecurityProfileLevel"]
var CertificateType = SecProfileModule["CertificateType"]
var X509Certificate = SecProfileModule["X509Certificate"]
var SecuritySupervisor = SecProfileModule["SecuritySupervisor"]

var test_passed = 0
var test_failed = 0

def assert_true(cond, msg)
    if cond
        test_passed = test_passed + 1
    else
        test_failed = test_failed + 1
        print("FAIL: " + str(msg))
    end
end

def assert_equal(a, b, msg)
    if a == b
        test_passed = test_passed + 1
    else
        test_failed = test_failed + 1
        print("FAIL: " + str(msg) + " (expected " + str(b) + ", got " + str(a) + ")")
    end
end

print(">>> Running test_security_profiles suite...")

# 1. X.509 Certificate Representation & Validity
var t_start = 1770000000
var t_end = 1780000000
var cert = X509Certificate("CERT-SN-001", "CN=csms.network.com", "CN=RootCA", CertificateType.CSMS_ROOT_CERTIFICATE, t_start, t_end)

assert_equal(cert.serial_number, "CERT-SN-001", "Cert serial number matches")
assert_true(cert.fingerprint_hash != nil && size(cert.fingerprint_hash) > 0, "Fingerprint generated")
assert_true(cert.is_valid_at(1775000000), "Cert valid at midpoint")
assert_true(!cert.is_valid_at(1760000000), "Cert invalid before valid_from")
assert_true(!cert.is_valid_at(1790000000), "Cert invalid after valid_to")

# Revocation test
cert.revoke()
assert_true(!cert.is_valid_at(1775000000), "Revoked certificate is immediately invalid")

# 2. Security Supervisor & Basic Auth
var sec = SecuritySupervisor("STATION-001", SecurityProfileLevel.PROFILE_2_TLS_WITH_BASIC_AUTH)
sec.set_basic_auth_credentials("SuperSecretPass123!")

assert_true(sec.verify_basic_auth("STATION-001", "SuperSecretPass123!"), "Basic auth accepted correct password")
assert_true(!sec.verify_basic_auth("STATION-001", "WrongPassword!"), "Basic auth rejected wrong password")
assert_true(!sec.verify_basic_auth("WRONG-STATION", "SuperSecretPass123!"), "Basic auth rejected wrong username")

# 3. Security Profile 2 Handshake (Requires CSMS Root Cert)
var hs1 = sec.verify_tls_handshake(1775000000)
assert_true(!hs1["tls_ok"], "Profile 2 handshake fails without root cert")

var root_cert = X509Certificate("ROOT-001", "CN=GlobalRootCA", "CN=GlobalRootCA", CertificateType.CSMS_ROOT_CERTIFICATE, t_start, t_end)
var inst_res = sec.install_root_certificate(root_cert)
assert_equal(inst_res["status"], "Accepted", "Installed root cert")

var hs2 = sec.verify_tls_handshake(1775000000)
assert_true(hs2["tls_ok"], "Profile 2 handshake succeeds with valid CSMS root cert")
assert_equal(hs2["profile"], 2, "Negotiated profile 2")

# 4. Security Profile 3 Mutual TLS Handshake
sec.current_security_profile = SecurityProfileLevel.PROFILE_3_MUTUAL_TLS
var hs3 = sec.verify_tls_handshake(1775000000)
assert_true(!hs3["tls_ok"], "Profile 3 fails without station client certificate")

var client_cert = X509Certificate("CLIENT-001", "CN=STATION-001", "CN=GlobalRootCA", CertificateType.CHARGING_STATION_CERT, t_start, t_end)
sec.install_station_certificate(client_cert)

var hs4 = sec.verify_tls_handshake(1775000000)
assert_true(hs4["tls_ok"], "Profile 3 succeeds with both root cert and client cert")
assert_equal(hs4["profile"], 3, "Negotiated profile 3 mTLS")

# 5. Certificate Signing Request (CSR) Generator
var csr = sec.generate_station_csr("STATION-001", "Stanchion Power Systems", "US")
assert_equal(csr["commonName"], "STATION-001", "CSR CommonName matches")
assert_equal(csr["keyAlgorithm"], "ECDSA_SECP256R1", "CSR KeyAlgorithm is ECDSA")

# 6. Audit Trail Logging
assert_true(size(sec.security_events_log) >= 3, "Security audit log recorded events")

print("test_security_profiles: " + str(test_passed) + " passed, " + str(test_failed) + " failed")
if test_failed > 0
    import os
    os.exit(1)
end
