# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# ISO 15118-2 / ISO 15118-20 / DIN 70121 Vehicle-to-Grid (V2G) Message Codec
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import math
import math_ext as MathExt
import string
import string_util as StringUtil

# ISO 15118 V2G Transfer Protocol (V2GTP) Constants
class V2GTP
    static var PROTOCOL_VERSION        = 0x01
    static var INVERSE_PROTOCOL_VERSION = 0xFE
    static var PAYLOAD_TYPE_EXI         = 0x8001
    static var PAYLOAD_TYPE_SDP_REQ     = 0x9000
    static var PAYLOAD_TYPE_SDP_RES     = 0x9001
    static var HEADER_LENGTH            = 8 # 8 bytes V2GTP header
end

# ISO 15118 Response Codes
class V2GResponseCode
    static var OK                                = "OK"
    static var OK_NEW_SESSION_ESTABLISHED        = "OK_NewSessionEstablished"
    static var OK_OLD_SESSION_JOINED             = "OK_OldSessionJoined"
    static var OK_CERTIFICATE_EXPIRES_SOON       = "OK_CertificateExpiresSoon"
    static var FAILED                            = "FAILED"
    static var FAILED_SEQUENCE_ERROR             = "FAILED_SequenceError"
    static var FAILED_SERVICE_ID_INVALID         = "FAILED_ServiceIDInvalid"
    static var FAILED_PAYMENT_SELECTION_INVALID  = "FAILED_PaymentSelectionInvalid"
    static var FAILED_CERTIFICATE_EXPIRED        = "FAILED_CertificateExpired"
    static var FAILED_SIGNATURE_ERROR            = "FAILED_SignatureError"
    static var FAILED_NO_CHARGE_SERVICE_SELECTED = "FAILED_NoChargeServiceSelected"
    static var FAILED_WRONG_CHARGE_PARAMETER     = "FAILED_WrongChargeParameter"
    static var FAILED_POWER_TOLERANCE_NOT_CONF   = "FAILED_PowerToleranceNotConfirmed"
end

# ISO 15118 Energy Transfer Modes
class EnergyTransferMode
    static var AC_SINGLE_PHASE_CORE  = "AC_single_phase_core"
    static var AC_THREE_PHASE_CORE   = "AC_three_phase_core"
    static var DC_CORE               = "DC_core"
    static var DC_EXTENDED           = "DC_extended"
    static var DC_COMBO_CORE         = "DC_combo_core"
    static var DC_DUAL               = "DC_dual"
    static var DC_BPT                = "DC_bpt" # Bidirectional Power Transfer
end

# Physical Value structure: value * 10^multiplier
class PhysicalValue
    var value
    var multiplier
    var unit

    def init(val, mult, unit_str)
        self.value = (val != nil) ? int(val) : 0
        self.multiplier = (mult != nil) ? int(mult) : 0
        self.unit = (unit_str != nil) ? str(unit_str) : ""
    end

    def get_actual_value()
        return real(self.value) * math.pow(10.0, real(self.multiplier))
    end

    static def from_actual(float_val, unit_str)
        var f = real(float_val)
        var mult = 0
        while math.abs(f) >= 10000.0 && mult < 4
            f = f / 10.0
            mult = mult + 1
        end
        while math.abs(f) < 100.0 && f != 0.0 && mult > -4
            f = f * 10.0
            mult = mult - 1
        end
        return PhysicalValue(int(math.round(f)), mult, unit_str)
    end

    def to_map()
        return {
            "value": self.value,
            "multiplier": self.multiplier,
            "unit": self.unit,
            "actual": MathExt.round_to(self.get_actual_value(), 3)
        }
    end
end

# Vehicle-to-Grid Session State & Codec Engine
class ISO15118Session
    var session_id
    var evse_id
    var protocol_version
    var current_state
    var selected_payment_option
    var selected_service_id
    var energy_transfer_mode
    var ev_max_limits
    var ev_target_values
    var evse_max_limits
    var is_bpt_enabled
    var session_start_epoch
    var message_counter

    def init(station_evse_id)
        self.session_id = nil
        self.evse_id = (station_evse_id != nil) ? str(station_evse_id) : "US-STN-E01"
        self.protocol_version = "ISO15118-2:2014"
        self.current_state = "STATE_UNINITIALIZED"
        self.selected_payment_option = nil
        self.selected_service_id = 1 # 1 = EV Charging service
        self.energy_transfer_mode = EnergyTransferMode.AC_THREE_PHASE_CORE
        self.ev_max_limits = {}
        self.ev_target_values = {}
        self.evse_max_limits = {
            "max_current_a": 32.0,
            "max_voltage_v": 400.0,
            "max_power_w": 22000.0,
            "min_current_a": 6.0
        }
        self.is_bpt_enabled = false
        self.session_start_epoch = 0
        self.message_counter = 0
    end

    # Pack V2GTP header (8 bytes) with given payload
    static def pack_v2gtp_header(payload_type, payload_bytes_len)
        var b = []
        b.push(V2GTP.PROTOCOL_VERSION)
        b.push(V2GTP.INVERSE_PROTOCOL_VERSION)
        # Payload type 16-bit big endian
        b.push((payload_type >> 8) & 0xFF)
        b.push(payload_type & 0xFF)
        # Length 32-bit big endian
        b.push((payload_bytes_len >> 24) & 0xFF)
        b.push((payload_bytes_len >> 16) & 0xFF)
        b.push((payload_bytes_len >> 8) & 0xFF)
        b.push(payload_bytes_len & 0xFF)
        return b
    end

    # Parse V2GTP header from raw byte array
    static def parse_v2gtp_header(bytes_list)
        if bytes_list == nil || size(bytes_list) < V2GTP.HEADER_LENGTH
            return {"ok": false, "error": "Buffer shorter than 8 byte header"}
        end
        if bytes_list[0] != V2GTP.PROTOCOL_VERSION || bytes_list[1] != V2GTP.INVERSE_PROTOCOL_VERSION
            return {"ok": false, "error": "Invalid V2GTP protocol version sync bytes"}
        end

        var p_type = (bytes_list[2] << 8) | bytes_list[3]
        var p_len = (bytes_list[4] << 24) | (bytes_list[5] << 16) | (bytes_list[6] << 8) | bytes_list[7]

        return {
            "ok": true,
            "payload_type": p_type,
            "payload_length": p_len
        }
    end

    # Handle SupportedAppProtocolReq
    def handle_supported_app_protocol_req(supported_protocols_list)
        self.message_counter = self.message_counter + 1
        var matched_schema = nil
        var matched_priority = 999

        var i = 0
        while i < size(supported_protocols_list)
            var p = supported_protocols_list[i]
            var ns = p.find("protocolNamespace")
            var prio = p.find("priority")
            if (ns == "urn:iso:15118:2:2013:MsgDef" || ns == "urn:iso:15118:2:2010:MsgDef" || ns == "urn:din:70121:2012:MsgDef")
                if prio != nil && prio < matched_priority
                    matched_schema = ns
                    matched_priority = prio
                end
            end
            i = i + 1
        end

        if matched_schema != nil
            self.current_state = "STATE_SUPPORTED_APP_PROTOCOL_CONFIRMED"
            return {
                "response_code": "OK_SuccessfulNegotiation",
                "schema_id": 0,
                "negotiated_namespace": matched_schema
            }
        else
            return {
                "response_code": "FAILED_NoNegotiation",
                "schema_id": 255,
                "negotiated_namespace": nil
            }
        end
    end

    # Handle SessionSetupReq
    def handle_session_setup_req(requested_session_id, ev_ccid)
        self.message_counter = self.message_counter + 1
        var resp_code = V2GResponseCode.OK_NEW_SESSION_ESTABLISHED

        if requested_session_id == nil || requested_session_id == "" || requested_session_id == "0000000000000000"
            # Generate new 64-bit session ID
            self.session_id = "A1B2C3D4E5F60718"
            resp_code = V2GResponseCode.OK_NEW_SESSION_ESTABLISHED
        else
            self.session_id = requested_session_id
            resp_code = V2GResponseCode.OK_OLD_SESSION_JOINED
        end

        self.current_state = "STATE_SESSION_SETUP_CONFIRMED"
        return {
            "response_code": resp_code,
            "session_id": self.session_id,
            "evse_id": self.evse_id,
            "evse_timestamp": 1770000000
        }
    end

    # Handle ServiceDiscoveryReq
    def handle_service_discovery_req()
        self.message_counter = self.message_counter + 1
        if self.current_state != "STATE_SESSION_SETUP_CONFIRMED" && self.current_state != "STATE_SERVICE_DISCOVERY_CONFIRMED"
            return {"response_code": V2GResponseCode.FAILED_SEQUENCE_ERROR}
        end

        self.current_state = "STATE_SERVICE_DISCOVERY_CONFIRMED"
        return {
            "response_code": V2GResponseCode.OK,
            "payment_options": ["Contract", "ExternalPayment"],
            "charge_service": {
                "service_id": 1,
                "service_name": "AC_DC_Charging",
                "service_category": "EVCharging",
                "free_service": false,
                "energy_transfer_mode": [
                    EnergyTransferMode.AC_THREE_PHASE_CORE,
                    EnergyTransferMode.DC_EXTENDED,
                    EnergyTransferMode.DC_BPT
                ]
            }
        }
    end

    # Handle ServicePaymentSelectionReq
    def handle_payment_selection_req(selected_payment, selected_service_id)
        self.message_counter = self.message_counter + 1
        if self.current_state != "STATE_SERVICE_DISCOVERY_CONFIRMED"
            return {"response_code": V2GResponseCode.FAILED_SEQUENCE_ERROR}
        end

        if selected_payment != "Contract" && selected_payment != "ExternalPayment"
            return {"response_code": V2GResponseCode.FAILED_PAYMENT_SELECTION_INVALID}
        end

        self.selected_payment_option = selected_payment
        self.selected_service_id = int(selected_service_id)
        self.current_state = "STATE_PAYMENT_SELECTED"

        return {
            "response_code": V2GResponseCode.OK
        }
    end

    # Handle ChargeParameterDiscoveryReq (AC/DC limits negotiation)
    def handle_charge_parameter_discovery_req(ev_params_map)
        self.message_counter = self.message_counter + 1
        if self.current_state != "STATE_PAYMENT_SELECTED" && self.current_state != "STATE_AUTHORIZATION_CONFIRMED"
            return {"response_code": V2GResponseCode.FAILED_SEQUENCE_ERROR}
        end

        self.ev_max_limits = {
            "max_voltage_v": (ev_params_map.find("max_voltage_v") != nil) ? real(ev_params_map["max_voltage_v"]) : 400.0,
            "max_current_a": (ev_params_map.find("max_current_a") != nil) ? real(ev_params_map["max_current_a"]) : 32.0,
            "max_power_w": (ev_params_map.find("max_power_w") != nil) ? real(ev_params_map["max_power_w"]) : 22000.0
        }

        # Check for Bidirectional Power Transfer capability
        if ev_params_map.find("bpt_supported") == true
            self.is_bpt_enabled = true
        end

        self.current_state = "STATE_CHARGE_PARAMETERS_DISCOVERED"

        # EVSE offers the minimum of EV capability and station rating
        var agreed_current = (self.ev_max_limits["max_current_a"] < self.evse_max_limits["max_current_a"]) ?
            self.ev_max_limits["max_current_a"] : self.evse_max_limits["max_current_a"]
        var agreed_power = (self.ev_max_limits["max_power_w"] < self.evse_max_limits["max_power_w"]) ?
            self.ev_max_limits["max_power_w"] : self.evse_max_limits["max_power_w"]

        return {
            "response_code": V2GResponseCode.OK,
            "evse_max_current_a": agreed_current,
            "evse_min_current_a": self.evse_max_limits["min_current_a"],
            "evse_max_voltage_v": self.evse_max_limits["max_voltage_v"],
            "evse_max_power_w": agreed_power,
            "bpt_active": self.is_bpt_enabled
        }
    end

    # Handle PowerDeliveryReq (Start / Stop power transfer)
    def handle_power_delivery_req(charge_progress)
        self.message_counter = self.message_counter + 1
        if charge_progress == "Start"
            if self.current_state != "STATE_CHARGE_PARAMETERS_DISCOVERED" && self.current_state != "STATE_POWER_DELIVERY_CONFIRMED"
                return {"response_code": V2GResponseCode.FAILED_SEQUENCE_ERROR}
            end
            self.current_state = "STATE_CHARGING_ACTIVE"
            return {
                "response_code": V2GResponseCode.OK,
                "evse_status": "ReadyToDeliverPower"
            }
        elif charge_progress == "Stop"
            self.current_state = "STATE_POWER_STOPPED"
            return {
                "response_code": V2GResponseCode.OK,
                "evse_status": "PowerDeliveryStopped"
            }
        else
            return {"response_code": V2GResponseCode.FAILED}
        end
    end

    # Handle SessionStopReq
    def handle_session_stop_req(charging_complete)
        self.message_counter = self.message_counter + 1
        self.current_state = "STATE_SESSION_TERMINATED"
        return {
            "response_code": V2GResponseCode.OK,
            "session_id": self.session_id,
            "charging_complete": charging_complete
        }
    end
end

return {
    "V2GTP": V2GTP,
    "V2GResponseCode": V2GResponseCode,
    "EnergyTransferMode": EnergyTransferMode,
    "PhysicalValue": PhysicalValue,
    "ISO15118Session": ISO15118Session
}
