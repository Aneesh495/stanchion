# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Transaction State Management, Meter Packaging & Session Persistence Log
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import uuid as UUID
import time_util as TimeUtil
import math_ext as MathExt

class Transaction
    var transaction_id
    var evse_id
    var connector_id
    var id_token
    var start_time_sec
    var end_time_sec
    var start_energy_kwh
    var end_energy_kwh
    var seq_no
    var charging_state
    var is_active
    var stopped_reason
    var total_cost

    def init(evse_id, connector_id, id_token, start_energy_kwh, start_time_sec)
        self.transaction_id = UUID.v4()
        self.evse_id = int(evse_id)
        self.connector_id = (connector_id != nil) ? int(connector_id) : 1
        self.id_token = str(id_token)
        self.start_time_sec = int(start_time_sec)
        self.end_time_sec = nil
        self.start_energy_kwh = real(start_energy_kwh)
        self.end_energy_kwh = real(start_energy_kwh)
        self.seq_no = 0
        self.charging_state = "Charging"
        self.is_active = true
        self.stopped_reason = nil
        self.total_cost = 0.0
    end

    def next_seq_no()
        var s = self.seq_no
        self.seq_no = self.seq_no + 1
        return s
    end

    def update_energy(current_total_kwh)
        self.end_energy_kwh = real(current_total_kwh)
    end

    def stop(end_time_sec, end_energy_kwh, stopped_reason)
        self.end_time_sec = int(end_time_sec)
        self.end_energy_kwh = real(end_energy_kwh)
        self.stopped_reason = (stopped_reason != nil) ? str(stopped_reason) : "Local"
        self.is_active = false
        self.charging_state = "Idle"
    end

    def get_energy_consumed_kwh()
        var diff = self.end_energy_kwh - self.start_energy_kwh
        return (diff >= 0.0) ? diff : 0.0
    end

    def get_duration_sec(current_time_sec)
        if self.end_time_sec != nil
            return self.end_time_sec - self.start_time_sec
        else
            return int(current_time_sec) - self.start_time_sec
        end
    end

    def to_map()
        return {
            "transaction_id": self.transaction_id,
            "evse_id": self.evse_id,
            "connector_id": self.connector_id,
            "id_token": self.id_token,
            "start_time_sec": self.start_time_sec,
            "end_time_sec": self.end_time_sec,
            "energy_consumed_kwh": MathExt.round_to(self.get_energy_consumed_kwh(), 4),
            "is_active": self.is_active,
            "stopped_reason": self.stopped_reason,
            "total_cost": MathExt.round_to(self.total_cost, 2)
        }
    end
end

return Transaction
