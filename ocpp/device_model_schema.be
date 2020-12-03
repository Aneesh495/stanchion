# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# OCPP 2.0.1 Standardized Device Model Schema & Variable Catalog
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import string

# Data types permitted in OCPP 2.0.1 Device Model
class DataTypeCode
    static var STRING        = "string"
    static var DECIMAL       = "decimal"
    static var INTEGER       = "integer"
    static var BOOLEAN       = "boolean"
    static var DATE_TIME     = "dateTime"
    static var OPTION_LIST   = "OptionList"
    static var SEQUENCE_LIST = "SequenceList"
    static var MEMBER_LIST   = "MemberList"
end

# Mutability flags
class Mutability
    static var READ_ONLY   = "ReadOnly"
    static var WRITE_ONLY  = "WriteOnly"
    static var READ_WRITE  = "ReadWrite"
end

# Variable Characteristic Definition
class VariableCharacteristic
    var data_type
    var mutability
    var unit
    var min_limit
    var max_limit
    var values_list
    var description

    def init(dt, mut, unit_s, min_l, max_l, vals, desc)
        self.data_type = (dt != nil) ? str(dt) : DataTypeCode.STRING
        self.mutability = (mut != nil) ? str(mut) : Mutability.READ_WRITE
        self.unit = unit_s
        self.min_limit = min_l
        self.max_limit = max_l
        self.values_list = vals
        self.description = desc
    end

    def to_map()
        return {
            "dataType": self.data_type,
            "mutability": self.mutability,
            "unit": self.unit,
            "minLimit": self.min_limit,
            "maxLimit": self.max_limit,
            "valuesList": self.values_list,
            "description": self.description
        }
    end
end

# OCPP 2.0.1 Device Model Catalog and Validator Engine
class DeviceModelCatalog
    var registry

    def init()
        self.registry = {}
        self._populate_standard_components()
    end

    def register(component_name, variable_name, characteristic)
        var c_name = str(component_name)
        var v_name = str(variable_name)
        if !self.registry.contains(c_name)
            self.registry[c_name] = {}
        end
        self.registry[c_name][v_name] = characteristic
    end

    def get_characteristic(component_name, variable_name)
        var c_name = str(component_name)
        var v_name = str(variable_name)
        if self.registry.contains(c_name)
            if self.registry[c_name].contains(v_name)
                return self.registry[c_name][v_name]
            end
        end
        return nil
    end

    def list_components()
        var l = []
        for k : self.registry.keys()
            l.push(k)
        end
        return l
    end

    def list_variables(component_name)
        var c_name = str(component_name)
        var l = []
        if self.registry.contains(c_name)
            for k : self.registry[c_name].keys()
                l.push(k)
            end
        end
        return l
    end

    # Validate value against characteristic schema
    def validate(component_name, variable_name, value)
        var char = self.get_characteristic(component_name, variable_name)
        if char == nil
            return {"valid": false, "reason": "UnknownComponentOrVariable"}
        end

        var dt = char.data_type
        if dt == DataTypeCode.INTEGER
            var iv = int(value)
            if char.min_limit != nil && iv < char.min_limit
                return {"valid": false, "reason": "ValueBelowMinimum"}
            end
            if char.max_limit != nil && iv > char.max_limit
                return {"valid": false, "reason": "ValueAboveMaximum"}
            end
        elif dt == DataTypeCode.DECIMAL
            var dv = real(value)
            if char.min_limit != nil && dv < char.min_limit
                return {"valid": false, "reason": "ValueBelowMinimum"}
            end
            if char.max_limit != nil && dv > char.max_limit
                return {"valid": false, "reason": "ValueAboveMaximum"}
            end
        elif dt == DataTypeCode.BOOLEAN
            if value != true && value != false && value != "true" && value != "false"
                return {"valid": false, "reason": "InvalidBooleanValue"}
            end
        elif dt == DataTypeCode.OPTION_LIST
            if char.values_list != nil
                var found = false
                var val_str = str(value)
                var i = 0
                while i < size(char.values_list)
                    if char.values_list[i] == val_str
                        found = true
                        break
                    end
                    i = i + 1
                end
                if !found
                    return {"valid": false, "reason": "ValueNotInOptionsList"}
                end
            end
        end

        return {"valid": true, "reason": nil}
    end

    # Populate full standardized OCPP 2.0.1 Appendices component catalog
    def _populate_standard_components()
        # 1. ChargingStation Component
        self.register("ChargingStation", "AvailabilityState",
            VariableCharacteristic(DataTypeCode.OPTION_LIST, Mutability.READ_ONLY, nil, nil, nil, ["Available", "Occupied", "Reserved", "Unavailable", "Faulted"], "Operating availability of charging station"))
        self.register("ChargingStation", "Model",
            VariableCharacteristic(DataTypeCode.STRING, Mutability.READ_ONLY, nil, nil, nil, nil, "Physical model identifier"))
        self.register("ChargingStation", "VendorName",
            VariableCharacteristic(DataTypeCode.STRING, Mutability.READ_ONLY, nil, nil, nil, nil, "Manufacturer vendor name"))
        self.register("ChargingStation", "FirmwareVersion",
            VariableCharacteristic(DataTypeCode.STRING, Mutability.READ_ONLY, nil, nil, nil, nil, "Currently installed firmware build"))
        self.register("ChargingStation", "SupplyPhases",
            VariableCharacteristic(DataTypeCode.INTEGER, Mutability.READ_ONLY, nil, 1, 3, nil, "Number of AC grid supply phases"))

        # 2. EVSE Component
        self.register("EVSE", "AvailabilityState",
            VariableCharacteristic(DataTypeCode.OPTION_LIST, Mutability.READ_ONLY, nil, nil, nil, ["Available", "Occupied", "Reserved", "Unavailable", "Faulted"], "Availability of EVSE channel"))
        self.register("EVSE", "Power",
            VariableCharacteristic(DataTypeCode.DECIMAL, Mutability.READ_ONLY, "W", 0.0, 350000.0, nil, "Instantaneous total power output"))
        self.register("EVSE", "CurrentLimit",
            VariableCharacteristic(DataTypeCode.DECIMAL, Mutability.READ_WRITE, "A", 0.0, 500.0, nil, "Active maximum current allocation"))
        self.register("EVSE", "MaxCurrent",
            VariableCharacteristic(DataTypeCode.DECIMAL, Mutability.READ_ONLY, "A", 6.0, 500.0, nil, "Hardware rated maximum current capacity"))

        # 3. ControlPilot Component
        self.register("ControlPilot", "State",
            VariableCharacteristic(DataTypeCode.OPTION_LIST, Mutability.READ_ONLY, nil, nil, nil, ["A", "B", "C", "D", "E", "F"], "IEC 61851-1 Control Pilot state"))
        self.register("ControlPilot", "DutyCycle",
            VariableCharacteristic(DataTypeCode.DECIMAL, Mutability.READ_WRITE, "percent", 0.0, 100.0, nil, "PWM 1kHz oscillator duty cycle percentage"))

        # 4. OCPPCommCtrl Component
        self.register("OCPPCommCtrl", "HeartbeatInterval",
            VariableCharacteristic(DataTypeCode.INTEGER, Mutability.READ_WRITE, "s", 1, 86400, nil, "Interval between periodic CSMS Heartbeat messages"))
        self.register("OCPPCommCtrl", "MessageTimeout",
            VariableCharacteristic(DataTypeCode.INTEGER, Mutability.READ_WRITE, "s", 5, 300, nil, "Timeout before unacknowledged CALL frame aborts"))
        self.register("OCPPCommCtrl", "RetryBackOffRepeatTimes",
            VariableCharacteristic(DataTypeCode.INTEGER, Mutability.READ_WRITE, nil, 0, 100, nil, "Max reconnection retry attempts before exponential backoff"))
        self.register("OCPPCommCtrl", "NetworkConfigurationPriority",
            VariableCharacteristic(DataTypeCode.STRING, Mutability.READ_WRITE, nil, nil, nil, nil, "Priority order of network profile slots"))

        # 5. SecurityCtrl Component
        self.register("SecurityCtrl", "SecurityProfile",
            VariableCharacteristic(DataTypeCode.INTEGER, Mutability.READ_WRITE, nil, 1, 3, nil, "OCPP security profile level: 1 (plain), 2 (TLS), 3 (mTLS)"))
        self.register("SecurityCtrl", "CertificateStoreMaxSize",
            VariableCharacteristic(DataTypeCode.INTEGER, Mutability.READ_ONLY, "bytes", 1024, 1048576, nil, "Maximum size in bytes of certificate trust store"))
        self.register("SecurityCtrl", "OrganizationName",
            VariableCharacteristic(DataTypeCode.STRING, Mutability.READ_WRITE, nil, nil, nil, nil, "Organization identifier for CSR generation"))

        # 6. SmartChargingCtrl Component
        self.register("SmartChargingCtrl", "Enabled",
            VariableCharacteristic(DataTypeCode.BOOLEAN, Mutability.READ_WRITE, nil, nil, nil, nil, "Enables or disables smart charging profile evaluation"))
        self.register("SmartChargingCtrl", "ProfileEntriesAvailable",
            VariableCharacteristic(DataTypeCode.INTEGER, Mutability.READ_ONLY, nil, 0, 1000, nil, "Capacity remaining in local composite charging profile store"))
        self.register("SmartChargingCtrl", "ChargingScheduleChargingRateUnit",
            VariableCharacteristic(DataTypeCode.OPTION_LIST, Mutability.READ_WRITE, nil, nil, nil, ["A", "W"], "Preferred unit for composite schedules"))
        self.register("SmartChargingCtrl", "LimitChangeSignificance",
            VariableCharacteristic(DataTypeCode.DECIMAL, Mutability.READ_WRITE, "percent", 0.0, 50.0, nil, "Percentage delta required to emit charging schedule notification"))

        # 7. SampledDataCtrl Component
        self.register("SampledDataCtrl", "TxUpdatedInterval",
            VariableCharacteristic(DataTypeCode.INTEGER, Mutability.READ_WRITE, "s", 1, 3600, nil, "Interval for periodic MeterValues reporting during active transaction"))
        self.register("SampledDataCtrl", "TxEndedInterval",
            VariableCharacteristic(DataTypeCode.INTEGER, Mutability.READ_WRITE, "s", 0, 3600, nil, "Interval for MeterValues after vehicle stop before unplug"))
        self.register("SampledDataCtrl", "SignReadings",
            VariableCharacteristic(DataTypeCode.BOOLEAN, Mutability.READ_WRITE, nil, nil, nil, nil, "Whether meter value samples require cryptographic signature"))

        # 8. TariffCostCtrl Component
        self.register("TariffCostCtrl", "Currency",
            VariableCharacteristic(DataTypeCode.STRING, Mutability.READ_WRITE, nil, nil, nil, nil, "ISO 4217 3-letter currency code for billing and tariff display"))
        self.register("TariffCostCtrl", "TotalCostWarranty",
            VariableCharacteristic(DataTypeCode.INTEGER, Mutability.READ_WRITE, "s", 0, 86400, nil, "Guaranteed duration of quoted session pricing"))
    end
end

return {
    "DataTypeCode": DataTypeCode,
    "Mutability": Mutability,
    "VariableCharacteristic": VariableCharacteristic,
    "DeviceModelCatalog": DeviceModelCatalog
}
