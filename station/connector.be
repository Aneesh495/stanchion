# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Connector Model, Electrical Specifications & Operating Status
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import types as Types

class Connector
    var evse_id
    var connector_id
    var connector_type
    var max_voltage_v
    var max_current_a
    var operational_status
    var current_state

    def init(evse_id, connector_id, conn_type, max_v, max_a)
        self.evse_id = int(evse_id)
        self.connector_id = int(connector_id)
        self.connector_type = (conn_type != nil) ? str(conn_type) : Types.CONNECTOR_TYPE_TYPE2
        self.max_voltage_v = (max_v != nil) ? real(max_v) : 400.0
        self.max_current_a = (max_a != nil) ? real(max_a) : 32.0
        self.operational_status = "Operative"
        self.current_state = Types.STATE_AVAILABLE
    end

    def set_state(new_state)
        self.current_state = str(new_state)
    end

    def set_operational_status(status)
        self.operational_status = str(status)
        if self.operational_status == "Inoperative"
            self.current_state = Types.STATE_UNAVAILABLE
        end
    end

    def is_available()
        return self.operational_status == "Operative" && self.current_state == Types.STATE_AVAILABLE
    end

    def to_map()
        return {
            "evse_id": self.evse_id,
            "connector_id": self.connector_id,
            "type": self.connector_type,
            "max_voltage_v": self.max_voltage_v,
            "max_current_a": self.max_current_a,
            "operational_status": self.operational_status,
            "state": self.current_state
        }
    end
end

return Connector
