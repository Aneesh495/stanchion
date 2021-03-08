# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Full OCPP 2.0.1 Action Catalog & PDU Validation Dictionary
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import string

# Functional Block Taxonomy
class FunctionalBlock
    static var PROVISIONING     = "Provisioning"
    static var AUTHORIZATION    = "Authorization"
    static var TRANSACTIONS     = "Transactions"
    static var SMART_CHARGING   = "SmartCharging"
    static var DIAGNOSTICS      = "Diagnostics"
    static var FIRMWARE         = "Firmware"
    static var SECURITY         = "Security"
    static var RESERVATION      = "Reservation"
    static var AVAILABILITY     = "Availability"
    static var TARIFF_AND_COST  = "TariffAndCost"
    static var DISPLAY_MESSAGE  = "DisplayMessage"
    static var DATA_TRANSFER    = "DataTransfer"
end

# Initiator Role
class InitiatorRole
    static var CHARGING_STATION = "ChargingStation"
    static var CSMS             = "CSMS"
    static var BIDIRECTIONAL    = "Bidirectional"
end

# Action Definition Schema
class ActionDefinition
    var action_name
    var functional_block
    var initiator
    var req_required_fields
    var req_optional_fields
    var res_required_fields
    var res_optional_fields

    def init(name, fblock, init_role, req_req, req_opt, res_req, res_opt)
        self.action_name = str(name)
        self.functional_block = str(fblock)
        self.initiator = str(init_role)
        self.req_required_fields = (req_req != nil) ? req_req : []
        self.req_optional_fields = (req_opt != nil) ? req_opt : []
        self.res_required_fields = (res_req != nil) ? res_req : []
        self.res_optional_fields = (res_opt != nil) ? res_opt : []
    end

    def to_map()
        return {
            "action": self.action_name,
            "block": self.functional_block,
            "initiator": self.initiator,
            "req_required": self.req_required_fields,
            "req_optional": self.req_optional_fields,
            "res_required": self.res_required_fields,
            "res_optional": self.res_optional_fields
        }
    end
end

# Complete OCPP 2.0.1 Action Catalog Registry
class OCPP201ActionCatalog
    var catalog

    def init()
        self.catalog = {}
        self._populate_catalog()
    end

    def register(action_def)
        self.catalog[action_def.action_name] = action_def
    end

    def get_action(action_name)
        var name = str(action_name)
        if self.catalog.contains(name)
            return self.catalog[name]
        end
        return nil
    end

    def list_actions()
        var l = []
        for k : self.catalog.keys()
            l.push(k)
        end
        return l
    end

    def list_by_block(functional_block)
        var b = str(functional_block)
        var l = []
        for k : self.catalog.keys()
            var act = self.catalog[k]
            if act.functional_block == b
                l.push(k)
            end
        end
        return l
    end

    # Validate an inbound or outbound PDU payload against required schema fields
    def validate_pdu(action_name, is_request, payload_map)
        var act = self.get_action(action_name)
        if act == nil
            return {"valid": false, "reason": "UnknownAction", "missing_fields": []}
        end

        if !isinstance(payload_map, map)
            return {"valid": false, "reason": "PayloadMustBeMap", "missing_fields": []}
        end

        var required = is_request ? act.req_required_fields : act.res_required_fields
        var missing = []

        var i = 0
        while i < size(required)
            var req_key = required[i]
            if !payload_map.contains(req_key) || payload_map[req_key] == nil
                missing.push(req_key)
            end
            i = i + 1
        end

        if size(missing) > 0
            return {"valid": false, "reason": "MissingRequiredFields", "missing_fields": missing}
        end

        return {"valid": true, "reason": nil, "missing_fields": []}
    end

    # Populate standard OCPP 2.0.1 action dictionary
    def _populate_catalog()
        # 1. Provisioning Block
        self.register(ActionDefinition("BootNotification", FunctionalBlock.PROVISIONING, InitiatorRole.CHARGING_STATION,
            ["reason", "chargingStation"], [], ["currentTime", "interval", "status"], ["statusInfo"]))
        self.register(ActionDefinition("Heartbeat", FunctionalBlock.PROVISIONING, InitiatorRole.CHARGING_STATION,
            [], [], ["currentTime"], []))
        self.register(ActionDefinition("Reset", FunctionalBlock.PROVISIONING, InitiatorRole.CSMS,
            ["type"], ["evseId"], ["status"], ["statusInfo"]))
        self.register(ActionDefinition("SetVariables", FunctionalBlock.PROVISIONING, InitiatorRole.CSMS,
            ["setVariableData"], [], ["setVariableResult"], []))
        self.register(ActionDefinition("GetVariables", FunctionalBlock.PROVISIONING, InitiatorRole.CSMS,
            ["getVariableData"], [], ["getVariableResult"], []))
        self.register(ActionDefinition("GetBaseReport", FunctionalBlock.PROVISIONING, InitiatorRole.CSMS,
            ["requestId", "reportBase"], [], ["status"], ["statusInfo"]))
        self.register(ActionDefinition("SetNetworkProfile", FunctionalBlock.PROVISIONING, InitiatorRole.CSMS,
            ["configurationSlot", "connectionData"], [], ["status"], ["statusInfo"]))

        # 2. Authorization Block
        self.register(ActionDefinition("Authorize", FunctionalBlock.AUTHORIZATION, InitiatorRole.CHARGING_STATION,
            ["idToken"], ["certificate", "iso15118CertificateHashData"], ["idTokenInfo"], ["certificateStatus"]))
        self.register(ActionDefinition("ClearCache", FunctionalBlock.AUTHORIZATION, InitiatorRole.CSMS,
            [], [], ["status"], ["statusInfo"]))

        # 3. Transactions Block
        self.register(ActionDefinition("TransactionEvent", FunctionalBlock.TRANSACTIONS, InitiatorRole.CHARGING_STATION,
            ["eventType", "timestamp", "triggerReason", "seqNo", "transactionInfo"],
            ["meterValue", "idToken", "evse", "numberOfPhasesUsed", "cableMaxCurrent"],
            [], ["totalCost", "chargingPriority", "idTokenInfo", "updatedPersonalMessage"]))
        self.register(ActionDefinition("RequestStartTransaction", FunctionalBlock.TRANSACTIONS, InitiatorRole.CSMS,
            ["idToken", "remoteStartId"], ["evseId", "groupIdToken", "chargingProfile"],
            ["status"], ["statusInfo", "transactionId"]))
        self.register(ActionDefinition("RequestStopTransaction", FunctionalBlock.TRANSACTIONS, InitiatorRole.CSMS,
            ["transactionId"], [], ["status"], ["statusInfo"]))

        # 4. Availability Block
        self.register(ActionDefinition("StatusNotification", FunctionalBlock.AVAILABILITY, InitiatorRole.CHARGING_STATION,
            ["timestamp", "connectorStatus", "evseId", "connectorId"], [], [], []))
        self.register(ActionDefinition("ChangeAvailability", FunctionalBlock.AVAILABILITY, InitiatorRole.CSMS,
            ["operationalStatus"], ["evse"], ["status"], ["statusInfo"]))

        # 5. Smart Charging Block
        self.register(ActionDefinition("SetChargingProfile", FunctionalBlock.SMART_CHARGING, InitiatorRole.CSMS,
            ["evseId", "chargingProfile"], [], ["status"], []))
        self.register(ActionDefinition("ClearChargingProfile", FunctionalBlock.SMART_CHARGING, InitiatorRole.CSMS,
            [], ["chargingProfileId", "chargingProfileCriteria"], ["status"], []))
        self.register(ActionDefinition("GetChargingProfiles", FunctionalBlock.SMART_CHARGING, InitiatorRole.CSMS,
            ["requestId", "chargingProfile"], ["evseId"], ["status"], []))
        self.register(ActionDefinition("GetCompositeSchedule", FunctionalBlock.SMART_CHARGING, InitiatorRole.CSMS,
            ["duration", "evseId"], ["chargingRateUnit"], ["status"], ["schedule"]))
        self.register(ActionDefinition("NotifyChargingLimit", FunctionalBlock.SMART_CHARGING, InitiatorRole.CHARGING_STATION,
            ["chargingLimit"], ["chargingSchedulePeriod", "evseId"], [], []))

        # 6. Diagnostics & Firmware Blocks
        self.register(ActionDefinition("GetLog", FunctionalBlock.DIAGNOSTICS, InitiatorRole.CSMS,
            ["log", "logType", "requestId"], ["retries", "retryInterval"], ["status"], ["filename"]))
        self.register(ActionDefinition("LogStatusNotification", FunctionalBlock.DIAGNOSTICS, InitiatorRole.CHARGING_STATION,
            ["status"], ["requestId"], [], []))
        self.register(ActionDefinition("UpdateFirmware", FunctionalBlock.FIRMWARE, InitiatorRole.CSMS,
            ["requestId", "firmware"], ["retries", "retryInterval"], ["status"], []))
        self.register(ActionDefinition("PublishFirmware", FunctionalBlock.FIRMWARE, InitiatorRole.CSMS,
            ["location", "checksum", "requestId"], ["retries", "retryInterval"], ["status"], []))

        # 7. Security Block
        self.register(ActionDefinition("SecurityEventNotification", FunctionalBlock.SECURITY, InitiatorRole.CHARGING_STATION,
            ["type", "timestamp"], ["techInfo"], [], []))
        self.register(ActionDefinition("SignCertificate", FunctionalBlock.SECURITY, InitiatorRole.CHARGING_STATION,
            ["csr"], ["certificateType"], ["status"], []))
        self.register(ActionDefinition("CertificateSigned", FunctionalBlock.SECURITY, InitiatorRole.CSMS,
            ["certificateChain"], ["certificateType"], ["status"], []))
        self.register(ActionDefinition("InstallCertificate", FunctionalBlock.SECURITY, InitiatorRole.CSMS,
            ["certificateType", "certificate"], [], ["status"], []))
        self.register(ActionDefinition("DeleteCertificate", FunctionalBlock.SECURITY, InitiatorRole.CSMS,
            ["certificateHashData"], [], ["status"], []))

        # 8. Reservation Block
        self.register(ActionDefinition("ReserveNow", FunctionalBlock.RESERVATION, InitiatorRole.CSMS,
            ["id", "expiryDateTime", "idToken"], ["connectorType", "evseId", "groupIdToken"], ["status"], []))
        self.register(ActionDefinition("CancelReservation", FunctionalBlock.RESERVATION, InitiatorRole.CSMS,
            ["reservationId"], [], ["status"], []))

        # 9. Hardware & Display Blocks
        self.register(ActionDefinition("UnlockConnector", FunctionalBlock.AVAILABILITY, InitiatorRole.CSMS,
            ["evseId", "connectorId"], [], ["status"], []))
        self.register(ActionDefinition("TriggerMessage", FunctionalBlock.DIAGNOSTICS, InitiatorRole.CSMS,
            ["requestedMessage"], ["evse"], ["status"], []))
        self.register(ActionDefinition("DataTransfer", FunctionalBlock.DATA_TRANSFER, InitiatorRole.BIDIRECTIONAL,
            ["vendorId"], ["messageId", "data"], ["status"], ["data"]))
    end
end

return {
    "FunctionalBlock": FunctionalBlock,
    "InitiatorRole": InitiatorRole,
    "ActionDefinition": ActionDefinition,
    "OCPP201ActionCatalog": OCPP201ActionCatalog
}
