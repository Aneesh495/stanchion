# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Visual Status LED Ring, HMI State Indicator & Color Animation
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

class DisplayPattern
    static var OFF           = "Off"
    static var SOLID_GREEN   = "SolidGreen"    # Ready / Available
    static var PULSING_GREEN = "PulsingGreen"  # Preparing / Cable Plugged
    static var PULSING_BLUE  = "PulsingBlue"   # Active Power Delivery
    static var SOLID_BLUE    = "SolidBlue"     # Charging Complete / Suspended EV
    static var SOLID_YELLOW  = "SolidYellow"   # Reserved / Authorization Pending
    static var FLASHING_RED  = "FlashingRed"   # Hardware Fault / Emergency Stop
end

class StationDisplay
    var evse_id
    var current_pattern
    var brightness_pct
    var active_color
    var message_text

    def init(evse_id)
        self.evse_id = int(evse_id)
        self.current_pattern = DisplayPattern.SOLID_GREEN
        self.brightness_pct = 100
        self.active_color = "Green"
        self.message_text = "Ready to Charge"
    end

    def set_available()
        self.current_pattern = DisplayPattern.SOLID_GREEN
        self.active_color = "Green"
        self.message_text = "Available - Plug In Cable"
    end

    def set_preparing()
        self.current_pattern = DisplayPattern.PULSING_GREEN
        self.active_color = "Green"
        self.message_text = "Vehicle Detected - Authorizing"
    end

    def set_charging(current_kw, soc_pct)
        self.current_pattern = DisplayPattern.PULSING_BLUE
        self.active_color = "Blue"
        var soc_str = (soc_pct != nil) ? (" | SoC: " + str(soc_pct) + "%") : ""
        self.message_text = "Charging: " + str(current_kw) + " kW" + soc_str
    end

    def set_suspended_ev()
        self.current_pattern = DisplayPattern.SOLID_BLUE
        self.active_color = "Blue"
        self.message_text = "Vehicle Paused / Battery Full"
    end

    def set_faulted(fault_code)
        self.current_pattern = DisplayPattern.FLASHING_RED
        self.active_color = "Red"
        self.message_text = "Station Fault: " + str(fault_code)
    end

    def get_status()
        return {
            "pattern": self.current_pattern,
            "color": self.active_color,
            "message": self.message_text
        }
    end
end

return StationDisplay
