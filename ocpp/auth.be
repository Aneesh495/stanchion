# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Local Authorization Whitelist, Token Cache & Hierarchical RFID Verification
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import types as Types
import token_hash as TokenHash

class IdTokenEntry
    var id_token
    var token_hash_hex
    var parent_id_token
    var status
    var expiry_epoch_sec
    var user_group
    var max_power_kw_override

    def init(token, parent, status, expiry, group, power_override)
        self.id_token = str(token)
        self.token_hash_hex = TokenHash.hex_digest(self.id_token, "stanchion-whitelist")
        self.parent_id_token = (parent != nil) ? str(parent) : nil
        self.status = (status != nil) ? str(status) : Types.AUTH_ACCEPTED
        self.expiry_epoch_sec = (expiry != nil) ? int(expiry) : 0
        self.user_group = (group != nil) ? str(group) : "Standard"
        self.max_power_kw_override = (power_override != nil) ? real(power_override) : nil
    end

    def is_valid_at(current_time_sec)
        current_time_sec = int(current_time_sec)
        if self.status != Types.AUTH_ACCEPTED
            return false
        end
        if self.expiry_epoch_sec > 0 && current_time_sec > self.expiry_epoch_sec
            return false
        end
        return true
    end
end

class AuthManager
    var whitelist
    var auth_cache
    var cache_ttl_sec
    var salt

    def init(cache_ttl_sec)
        self.whitelist = {}
        self.auth_cache = {}
        self.cache_ttl_sec = (cache_ttl_sec != nil) ? int(cache_ttl_sec) : 86400
        self.salt = "stanchion-whitelist"
    end

    # Add or update an entry in the Local Authorization List
    def add_whitelist_entry(token, parent, status, expiry, group, power_override)
        var entry = IdTokenEntry(token, parent, status, expiry, group, power_override)
        self.whitelist[str(token)] = entry
    end

    # Clear all whitelist entries
    def clear_whitelist()
        self.whitelist = {}
    end

    # Cache an authorization decision received from Central System (CSMS)
    def cache_authorization(token, status, current_time_sec)
        var expiry = int(current_time_sec) + self.cache_ttl_sec
        self.auth_cache[str(token)] = {
            "status": str(status),
            "expiry_sec": expiry
        }
    end

    # Verify token locally against Whitelist and Cache
    def verify_token_locally(token, current_time_sec)
        token = str(token)
        current_time_sec = int(current_time_sec)

        # 1. Check permanent Local Authorization List (Whitelist)
        if self.whitelist.contains(token)
            var entry = self.whitelist[token]
            if entry.is_valid_at(current_time_sec)
                return {
                    "status": Types.AUTH_ACCEPTED,
                    "source": "Whitelist",
                    "group": entry.user_group,
                    "max_power_kw": entry.max_power_kw_override
                }
            else
                var st = (entry.expiry_epoch_sec > 0 && current_time_sec > entry.expiry_epoch_sec) ?
                         Types.AUTH_EXPIRED : entry.status
                return {"status": st, "source": "Whitelist"}
            end
        end

        # 2. Check temporary Auth Cache
        if self.auth_cache.contains(token)
            var cached = self.auth_cache[token]
            if current_time_sec <= cached["expiry_sec"]
                return {
                    "status": cached["status"],
                    "source": "Cache",
                    "group": "Standard"
                }
            else
                # Expired cache entry
                self.auth_cache.remove(token)
            end
        end

        # Not found locally
        return {"status": Types.AUTH_INVALID, "source": "NotFound"}
    end

    def whitelist_size()
        return self.whitelist.size()
    end

    def cache_size()
        return self.auth_cache.size()
    end
end

return AuthManager
