# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Security Event Logging, Audit Trails & Brute-Force Rate Limiting
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import collection as Col
import time_util as TimeUtil

var RingBuffer = Col["RingBuffer"]

class SecurityProfile
    static var PROFILE_1_UNSECURED = 1 # Basic Auth over HTTP/WS (deprecated)
    static var PROFILE_2_TLS_BASIC = 2 # TLS with Basic Auth username/password
    static var PROFILE_3_MUTUAL_TLS = 3 # Mutual TLS (mTLS) with Client Certificates
end

class SecurityEvent
    static var FIRMWARE_VERIFICATION_FAILED = "FirmwareVerificationFailed"
    static var INVALID_CENTRAL_SYSTEM_CERT  = "InvalidCentralSystemCertificate"
    static var TAMPER_DETECTION             = "TamperDetectionActivated"
    static var BRUTE_FORCE_AUTH_ATTEMPT     = "InvalidIdTokenScanBurst"
    static var REBOOT_UNEXPECTED            = "UnexpectedReboot"
end

class SecurityManager
    var active_profile
    var audit_log
    var failed_auth_attempts
    var rate_limit_window_sec
    var max_attempts_in_window
    var lock_until_epoch_sec

    def init(security_profile)
        self.active_profile = (security_profile != nil) ? int(security_profile) : SecurityProfile.PROFILE_2_TLS_BASIC
        self.audit_log = RingBuffer(128)
        self.failed_auth_attempts = []
        self.rate_limit_window_sec = 60
        self.max_attempts_in_window = 5
        self.lock_until_epoch_sec = 0
    end

    def log_security_event(event_type, tech_info, timestamp_sec)
        var record = {
            "type": str(event_type),
            "timestamp": TimeUtil.to_iso8601(timestamp_sec),
            "tech_info": str(tech_info)
        }
        self.audit_log.push(record)
        print("[SECURITY AUDIT] " + str(event_type) + ": " + str(tech_info))
    end

    # Record failed authorization attempt and enforce anti-brute-force rate limiting
    def record_failed_auth(token_str, timestamp_sec)
        timestamp_sec = int(timestamp_sec)
        self.failed_auth_attempts.push(timestamp_sec)

        # Evict attempts older than rate_limit_window_sec
        var cutoff = timestamp_sec - self.rate_limit_window_sec
        var filtered = []
        for t : self.failed_auth_attempts
            if t >= cutoff
                filtered.push(t)
            end
        end
        self.failed_auth_attempts = filtered

        if self.failed_auth_attempts.size() >= self.max_attempts_in_window
            self.lock_until_epoch_sec = timestamp_sec + 300 # Lockout for 5 minutes
            self.log_security_event(SecurityEvent.BRUTE_FORCE_AUTH_ATTEMPT,
                "Exceeded " + str(self.max_attempts_in_window) + " failures within window. Locked out.", timestamp_sec)
            return false # Rate limited!
        end
        return true
    end

    def is_rate_limited(current_time_sec)
        return int(current_time_sec) < self.lock_until_epoch_sec
    end

    def get_audit_trail()
        return self.audit_log.to_list()
    end
end

return SecurityManager
