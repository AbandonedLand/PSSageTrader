$log = @{
                    bot_type = $dca.GetType().Name
                    bot_id = $dca.id
                    offered_asset_id = $dca.offered_asset.id
                    offered_asset_amount = [Int128]($dca.offered_asset.getFormattedAmount() * -1)
                    requested_asset_id =  $dca.requested_asset.id
                    requested_asset_amount = [Int128]($dca.requested_asset.getFormattedAmount())
                    status = "pending"
                    created_at = (Get-Date)
                    updated_at = (Get-Date)
                    offer_id = $quote.sageoffer.offer_data.offer_id
                    fingerprint = $dca.fingerprint
                    dexie_id = ($dexie.id)
                }
            New-ChiaOfferLog @log