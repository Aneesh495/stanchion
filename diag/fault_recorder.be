# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Freeze-Frame Diagnostic Fault Recorder & Black-Box Incident Snapshot
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import collection as Col
import time_util as TimeUtil
import math_ext as MathExt

var RingBuffer = Col["RingBuffer"]

class FaultFreezeFrame
    var fault_id
    var evse_id
    var error_code
    var timestamp_iso
    var voltages_ln
    var currents_a
    var pilot_voltage_v
    var pilot_state
    var contactor_state
    var heatsink_temp_c
    var connector_temp_c
    var rcd_ac_ma
    var rcd_dc_ma

    def init(fid, evse_id, code, t_sec, v_list, i_list, p_v, p_state, c_state, t_sink, t_plug, rcd_ac, rcd_dc)
        self.fault_id = int(fid)
        self.evse_id = int(evse_id)
        self.error_code = str(code)
        self.timestamp_iso = TimeUtil.to_iso8601(t_sec)
        self.voltages_ln = (v_list != nil) ? v_list : [230.0, 230.0, 230.0]
        self.currents_a = (i_list != nil) ? i_list : [0.0, 0.0, 0.0]
        self.pilot_voltage_v = real(p_v)
        self.pilot_state = str(p_state)
        self.contactor_state = str(c_state)
        self.heatsink_temp_c = real(t_sink)
        self.connector_temp_c = real(t_plug)
        self.rcd_ac_ma = real(rcd_ac)
        self.rcd_dc_ma = real(rcd_dc)
    end

    def to_map()
        return {
            "fault_id": self.fault_id,
            "evse_id": self.evse_id,
            "error_code": self.error_code,
            "timestamp": self.timestamp_iso,
            "voltages_v": self.voltages_ln,
            "currents_a": self.currents_a,
            "pilot_voltage_v": MathExt.round_to(self.pilot_voltage_v, 2),
            "pilot_state": self.pilot_state,
            "contactor_state": self.contactor_state,
            "heatsink_temp_c": MathExt.round_to(self.heatsink_temp_c, 1),
            "connector_temp_c": MathExt.round_to(self.connector_temp_c, 1),
            "rcd_ac_ma": MathExt.round_to(self.rcd_ac_ma, 2),
            "rcd_dc_ma": MathExt.round_to(self.rcd_dc_ma, 2)
        }
    end
end

class FaultRecorder
    var records
    var next_fault_id
    var max_records

    def init(capacity)
        self.max_records = (capacity != nil) ? int(capacity) : 32
        self.records = RingBuffer(self.max_records)
        self.next_fault_id = 1
    end

    # Capture instantaneous diagnostic freeze-frame at trip moment
    def capture_freeze_frame(evse_id, code, t_sec, v_list, i_list, p_v, p_state, c_state, t_sink, t_plug, rcd_ac, rcd_dc)
        var frame = FaultFreezeFrame(self.next_fault_id, evse_id, code, t_sec, v_list, i_list, p_v, p_state, c_state, t_sink, t_plug, rcd_ac, rcd_dc)
        self.next_fault_id = self.next_fault_id + 1
        self.records.push(frame)
        print("[FAULT RECORDER] Freeze-frame #" + str(frame.fault_id) + " captured for EVSE " + str(evse_id) + " (" + code + ")")
        return frame.fault_id
    end

    def get_latest_fault()
        return self.records.latest()
    end

    def get_all_faults()
        return self.records.to_list()
    end

    def count()
        return self.records.size()
    end
end

var FaultRecorderModule = {
    "FreezeFrame": FaultFreezeFrame,
    "Recorder": FaultRecorder
}

return FaultRecorderModule
