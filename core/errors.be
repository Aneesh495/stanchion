# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Error Classification, Severity Taxonomy & Hardware Diagnostic Codes
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

class ErrorSeverity
    static var MINOR     = "Minor"      # Recoverable automatically
    static var MODERATE  = "Moderate"   # EVSE suspended, requires cable replug
    static var SEVERE    = "Severe"     # EVSE locked out, requires manual reset
    static var CRITICAL  = "Critical"   # Station emergency shutdown, contactors open
end

class ErrorCode
    # Hardware & Safety Trips
    static var ERR_NONE                 = "NoError"
    static var ERR_GROUND_FAILURE       = "GroundFailure"
    static var ERR_OVER_CURRENT         = "OverCurrentFailure"
    static var ERR_OVER_VOLTAGE         = "OverVoltage"
    static var ERR_UNDER_VOLTAGE        = "UnderVoltage"
    static var ERR_OVER_TEMPERATURE     = "OverTemperature"
    static var ERR_CONTACTOR_WELDED     = "ContactorWelded"
    static var ERR_LOCK_FAILURE         = "ConnectorLockFailure"
    static var ERR_PILOT_FAULT          = "PilotSignalFault"
    static var ERR_POWER_SWITCH_FAILURE = "PowerSwitchFailure"

    # Communication & Protocol
    static var ERR_CSMS_DISCONNECTED    = "CSMSDisconnected"
    static var ERR_MESSAGE_TIMEOUT      = "MessageTimeout"
    static var ERR_INVALID_PAYLOAD      = "InvalidPayload"
    static var ERR_AUTH_REJECTED        = "AuthorizationRejected"
    static var ERR_CERTIFICATE_EXPIRED  = "CertificateExpired"

    # Grid & Energy Management
    static var ERR_GRID_LIMIT_EXCEEDED  = "GridCapacityExceeded"
    static var ERR_PHASE_UNBALANCE      = "PhaseUnbalanceExcessive"
    static var ERR_DLM_SATURATION       = "DynamicLoadSaturation"
end

class StationError
    var code
    var severity
    var description
    var evse_id
    var timestamp_sec
    var is_latched

    def init(code, severity, description, evse_id)
        self.code = str(code)
        self.severity = str(severity)
        self.description = (description != nil) ? str(description) : ""
        self.evse_id = (evse_id != nil) ? int(evse_id) : 0
        self.timestamp_sec = 0
        # Critical and Severe errors are latched until explicit technician clear
        self.is_latched = (self.severity == ErrorSeverity.SEVERE || self.severity == ErrorSeverity.CRITICAL)
    end

    def requires_immediate_power_cutoff()
        return self.code == ErrorCode.ERR_GROUND_FAILURE ||
               self.code == ErrorCode.ERR_CONTACTOR_WELDED ||
               self.code == ErrorCode.ERR_OVER_CURRENT ||
               self.code == ErrorCode.ERR_OVER_TEMPERATURE ||
               self.severity == ErrorSeverity.CRITICAL
    end

    def to_map()
        return {
            "code": self.code,
            "severity": self.severity,
            "description": self.description,
            "evse_id": self.evse_id,
            "is_latched": self.is_latched
        }
    end
end

var ErrorsModule = {
    "Severity": ErrorSeverity,
    "Code": ErrorCode,
    "StationError": StationError
}

return ErrorsModule
