# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Session Billing Calculator, Tax Allocation & Receipt Generator
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import math_ext as MathExt
import time_util as TimeUtil

class BillingCalculator
    var sales_tax_rate
    var currency

    def init(tax_rate, currency_str)
        self.sales_tax_rate = (tax_rate != nil) ? real(tax_rate) : 0.0825 # 8.25%
        self.currency = (currency_str != nil) ? str(currency_str) : "USD"
    end

    # Generate itemized invoice for completed charging session
    def generate_invoice(transaction_id, evse_id, id_token, kwh_consumed, rate_per_kwh, conn_fee, idle_fee, discount_voucher)
        kwh_consumed = real(kwh_consumed)
        rate_per_kwh = real(rate_per_kwh)
        conn_fee = (conn_fee != nil) ? real(conn_fee) : 0.0
        idle_fee = (idle_fee != nil) ? real(idle_fee) : 0.0
        discount_voucher = (discount_voucher != nil) ? real(discount_voucher) : 0.0

        var energy_subtotal = kwh_consumed * rate_per_kwh
        var raw_subtotal = energy_subtotal + conn_fee + idle_fee

        var discounted_subtotal = raw_subtotal - discount_voucher
        if discounted_subtotal < 0.0
            discounted_subtotal = 0.0
        end

        var tax_amount = discounted_subtotal * self.sales_tax_rate
        var grand_total = discounted_subtotal + tax_amount

        return {
            "invoice_id": "INV-" + str(transaction_id)[0 .. 7],
            "transaction_id": str(transaction_id),
            "evse_id": int(evse_id),
            "id_token": str(id_token),
            "currency": self.currency,
            "line_items": {
                "energy_kwh": MathExt.round_to(kwh_consumed, 3),
                "energy_rate": MathExt.round_to(rate_per_kwh, 4),
                "energy_subtotal": MathExt.round_to(energy_subtotal, 2),
                "connection_fee": MathExt.round_to(conn_fee, 2),
                "idle_fee": MathExt.round_to(idle_fee, 2),
                "discount_applied": MathExt.round_to(discount_voucher, 2),
                "subtotal": MathExt.round_to(discounted_subtotal, 2),
                "tax_amount": MathExt.round_to(tax_amount, 2),
                "grand_total": MathExt.round_to(grand_total, 2)
            }
        }
    end
end

return BillingCalculator
