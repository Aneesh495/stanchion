# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# HomePlug Green PHY PLC Modem & ISO 15118-3 SLAC Protocol Engine
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import math
import math_ext as MathExt

# SLAC State Machine (ISO 15118-3 Annex B)
class SLACState
    static var IDLE                     = "IDLE"
    static var PARAM_EXCHANGE           = "PARAM_EXCHANGE"
    static var SOUNDING_ACTIVE          = "SOUNDING_ACTIVE"
    static var ATTENUATION_VERIFIED     = "ATTENUATION_VERIFIED"
    static var MATCHED                  = "MATCHED"
    static var UNMATCHED                = "UNMATCHED"
end

# Qualcomm QCA7000 / QCA7005 HomePlug Green PHY Modem Simulator
class HomePlugGreenPHYModem
    var evse_mac_address
    var ev_mac_address
    var run_id
    var current_state
    var max_crosstalk_attenuation_db
    var received_sounding_packets
    var carrier_attenuation_profile # 58 carrier subband attenuation measurements
    var average_attenuation_db
    var network_membership_key # NMK (16-byte hex)
    var is_coupled

    def init(station_mac)
        self.evse_mac_address = (station_mac != nil) ? str(station_mac) : "00:01:87:AA:BB:CC"
        self.ev_mac_address = nil
        self.run_id = nil
        self.current_state = SLACState.IDLE
        self.max_crosstalk_attenuation_db = 42.0 # Attenuation > 42 dB considered cross-talk
        self.received_sounding_packets = []
        self.carrier_attenuation_profile = []
        self.average_attenuation_db = 0.0
        self.network_membership_key = "E85B9C34A1209F4D0862A1F5DE398401"
        self.is_coupled = false
    end

    # Handle CM_SLAC_PARM.REQ from EV
    def handle_slac_parm_req(ev_mac, run_id_hex)
        self.ev_mac_address = str(ev_mac)
        self.run_id = str(run_id_hex)
        self.current_state = SLACState.PARAM_EXCHANGE
        self.received_sounding_packets = []
        self.carrier_attenuation_profile = []

        return {
            "mme_type": "CM_SLAC_PARM.CNF",
            "evse_mac": self.evse_mac_address,
            "ev_mac": self.ev_mac_address,
            "run_id": self.run_id,
            "num_sounds": 10,
            "timeout_ms": 600,
            "status": "Success"
        }
    end

    # Handle CM_MNBC_SOUND.IND sounding packet arrival
    def record_sounding_packet(sound_index, raw_attenuation_db)
        if self.current_state != SLACState.PARAM_EXCHANGE && self.current_state != SLACState.SOUNDING_ACTIVE
            return false
        end

        self.current_state = SLACState.SOUNDING_ACTIVE
        var atten = real(raw_attenuation_db)
        self.received_sounding_packets.push(atten)
        return true
    end

    # Process CM_ATTEN_CHAR.IND: evaluate average signal attenuation
    def evaluate_attenuation()
        if size(self.received_sounding_packets) < 5
            self.current_state = SLACState.UNMATCHED
            return {"matched": false, "reason": "InsufficientSoundingPackets"}
        end

        # Calculate mean attenuation across all sounding packets
        var sum_db = 0.0
        var i = 0
        while i < size(self.received_sounding_packets)
            sum_db = sum_db + self.received_sounding_packets[i]
            i = i + 1
        end
        self.average_attenuation_db = sum_db / real(size(self.received_sounding_packets))

        # Check for cross-talk: if attenuation > 42 dB, reject
        if self.average_attenuation_db > self.max_crosstalk_attenuation_db
            self.current_state = SLACState.UNMATCHED
            self.is_coupled = false
            return {
                "matched": false,
                "average_attenuation_db": MathExt.round_to(self.average_attenuation_db, 1),
                "reason": "CrossTalkDetectedSignalTooWeak"
            }
        end

        self.current_state = SLACState.ATTENUATION_VERIFIED
        self.is_coupled = true
        return {
            "matched": true,
            "average_attenuation_db": MathExt.round_to(self.average_attenuation_db, 1),
            "reason": nil
        }
    end

    # Handle CM_SLAC_MATCH.REQ: finalize physical pairing and establish NMK
    def handle_slac_match_req(ev_mac, run_id_hex)
        if self.current_state != SLACState.ATTENUATION_VERIFIED
            return {
                "mme_type": "CM_SLAC_MATCH.CNF",
                "status": "Failure_UnverifiedAttenuation",
                "nmk": nil
            }
        end

        if str(ev_mac) != self.ev_mac_address || str(run_id_hex) != self.run_id
            return {
                "mme_type": "CM_SLAC_MATCH.CNF",
                "status": "Failure_MismatchIdentity",
                "nmk": nil
            }
        end

        self.current_state = SLACState.MATCHED
        return {
            "mme_type": "CM_SLAC_MATCH.CNF",
            "evse_mac": self.evse_mac_address,
            "ev_mac": self.ev_mac_address,
            "run_id": self.run_id,
            "nmk": self.network_membership_key,
            "status": "Success_Matched"
        }
    end

    def reset()
        self.current_state = SLACState.IDLE
        self.ev_mac_address = nil
        self.run_id = nil
        self.received_sounding_packets = []
        self.is_coupled = false
    end
end

return {
    "SLACState": SLACState,
    "HomePlugGreenPHYModem": HomePlugGreenPHYModem
}
