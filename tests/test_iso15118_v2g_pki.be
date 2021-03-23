# Stanchion Test Suite: ISO 15118 Plug & Charge PKI & OCSP Client
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import iso15118_v2g_pki as PnCModule
import token_hash as TokenHash
import math
import string
import global

var OCSPCertStatus = PnCModule["OCSPCertStatus"]
var EMAIDValidator = PnCModule["EMAIDValidator"]
var ContractCertificate = PnCModule["ContractCertificate"]
var PlugAndChargePKI = PnCModule["PlugAndChargePKI"]

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

print(">>> Running test_iso15118_v2g_pki suite...")

# 1. eMAID Format Validator Tests
assert_true(EMAIDValidator.validate_format("US*STN*E00123456*8"), "Valid eMAID format accepted")
assert_true(EMAIDValidator.validate_format("DE-V2G-E99887766-1"), "Hyphenated eMAID format accepted")
assert_true(!EMAIDValidator.validate_format("SHORT"), "Short string rejected as invalid eMAID")
assert_equal(EMAIDValidator.extract_country_code("US*STN*E00123456*8"), "US", "Extracted country code US")

# 2. PKI Engine Setup & Contract Certificate Installation
var pki = PlugAndChargePKI()
var cert = ContractCertificate("CERT-PNC-001", "US*STN*E00123456*8", "CN=V2GRootCA-1", 1770000000, 1780000000)
var inst_res = pki.install_contract_cert(cert)
assert_equal(inst_res["status"], "Accepted", "Installed valid contract certificate")

# 3. Successful Plug and Charge Authentication
var t_now = 1775000000
var valid_sig = TokenHash.hex_digest(cert.public_key_fingerprint + ":" + str(t_now), "V2G_CHALLENGE")
var auth_ok = pki.validate_pnc_authentication("CERT-PNC-001", valid_sig, t_now)
assert_true(auth_ok["authenticated"], "PnC authentication succeeded")
assert_equal(auth_ok["emaid"], "US*STN*E00123456*8", "eMAID retrieved on authentication")

# 4. Invalid Signature Rejection
var bad_sig = TokenHash.hex_digest("WRONG_SIG", "V2G_CHALLENGE")
var auth_bad_sig = pki.validate_pnc_authentication("CERT-PNC-001", bad_sig, t_now)
assert_true(!auth_bad_sig["authenticated"], "Rejected invalid cryptographic signature")
assert_equal(auth_bad_sig["reason"], "InvalidCryptographicSignature", "Reported InvalidCryptographicSignature")

# 5. Untrusted Root CA Rejection
var unk_ca_cert = ContractCertificate("CERT-PNC-002", "US*STN*E99999999*1", "CN=RogueRootCA", 1770000000, 1780000000)
pki.install_contract_cert(unk_ca_cert)
var unk_sig = TokenHash.hex_digest(unk_ca_cert.public_key_fingerprint + ":" + str(t_now), "V2G_CHALLENGE")
var auth_bad_ca = pki.validate_pnc_authentication("CERT-PNC-002", unk_sig, t_now)
assert_true(!auth_bad_ca["authenticated"], "Rejected untrusted issuer root CA")
assert_equal(auth_bad_ca["reason"], "UntrustedIssuerCA", "Reported UntrustedIssuerCA")

# 6. OCSP Status Check & Dynamic Revocation
var ocsp_before = pki.query_ocsp_status("CERT-PNC-001")
assert_equal(ocsp_before["status"], OCSPCertStatus.GOOD, "OCSP status is Good before revocation")

# Revoke certificate via OCSP
pki.revoke_certificate("CERT-PNC-001")
var ocsp_after = pki.query_ocsp_status("CERT-PNC-001")
assert_equal(ocsp_after["status"], OCSPCertStatus.REVOKED, "OCSP status is Revoked after revocation")

# Subsequent PnC authentication fails immediately
var auth_revoked = pki.validate_pnc_authentication("CERT-PNC-001", valid_sig, t_now)
assert_true(!auth_revoked["authenticated"], "Revoked cert fails PnC authentication")
assert_equal(auth_revoked["reason"], "CertificateRevokedByOCSP", "Reported CertificateRevokedByOCSP")

print("test_iso15118_v2g_pki: " + str(test_passed) + " passed, " + str(test_failed) + " failed")
if test_failed > 0
    import os
    os.exit(1)
end
