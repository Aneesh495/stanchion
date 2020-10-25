# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# OCPP 2.0.1 Device Model Repository & Component-Variable Schema Store
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

class VariableMutability
    static var READ_ONLY  = "ReadOnly"
    static var WRITE_ONLY = "WriteOnly"
    static var READ_WRITE = "ReadWrite"
end

class DeviceVariable
    var component
    var variable
    var value
    var mutability
    var data_type

    def init(comp, var_name, val, mut, dtype)
        self.component = str(comp)
        self.variable = str(var_name)
        self.value = val
        self.mutability = (mut != nil) ? str(mut) : VariableMutability.READ_WRITE
        self.data_type = (dtype != nil) ? str(dtype) : "string"
    end
end

class DeviceModel
    var variables

    def init()
        self.variables = {}
        self._initialize_standard_variables()
    end

    def _make_key(comp, var_name)
        return str(comp) + "." + str(var_name)
    end

    def _initialize_standard_variables()
        self.register("Controller", "HeartbeatInterval", 60, VariableMutability.READ_WRITE, "integer")
        self.register("Controller", "MeterValueSampleInterval", 10, VariableMutability.READ_WRITE, "integer")
        self.register("ChargingStation", "VendorName", "Stanchion Power Systems", VariableMutability.READ_ONLY, "string")
        self.register("ChargingStation", "Model", "Stanchion-HyperCharge-150", VariableMutability.READ_ONLY, "string")
        self.register("ChargingStation", "FirmwareVersion", "1.0.0", VariableMutability.READ_ONLY, "string")
        self.register("EVSE", "AllowReset", true, VariableMutability.READ_WRITE, "boolean")
        self.register("Connector", "SupplyPhases", 3, VariableMutability.READ_ONLY, "integer")
        self.register("SecurityCtrlr", "SecurityProfile", 2, VariableMutability.READ_WRITE, "integer")
        self.register("SmartChargingCtrlr", "Enabled", true, VariableMutability.READ_WRITE, "boolean")
    end

    def register(comp, var_name, val, mut, dtype)
        var key = self._make_key(comp, var_name)
        self.variables[key] = DeviceVariable(comp, var_name, val, mut, dtype)
    end

    def get_variable(comp, var_name)
        var key = self._make_key(comp, var_name)
        if self.variables.contains(key)
            return self.variables[key].value
        end
        return nil
    end

    def set_variable(comp, var_name, new_val)
        var key = self._make_key(comp, var_name)
        if self.variables.contains(key)
            var v = self.variables[key]
            if v.mutability == VariableMutability.READ_ONLY
                return {"status": "Rejected", "reason": "Variable is ReadOnly"}
            end
            v.value = new_val
            return {"status": "Accepted"}
        end
        return {"status": "UnknownComponent"}
    end

    def size()
        return self.variables.size()
    end
end

return DeviceModel
