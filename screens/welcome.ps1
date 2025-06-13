
function Show-Cats {
    $cats = @()
    Get-SageCats | Sort-Object {$_.balance } -Descending | ForEach-Object {
        if($null -ne $_.name -and $_.balance -gt 0) {
            $cats += [ordered]@{
            ticker = $_.ticker
            balance = (($_.balance / 1000 ) -as [decimal])
            }
        }
    }
    $cats | Format-SpectreTable
}

function Show-Offers {
    param(
        [array]$offer_ids
    )

    $cats = Get-SageCats
    $formatted_offer = @()

    foreach($offer_id in $offer_ids) {
        
        $offer = Get-SageOffer -offer_id $offer_id        
        if($offer.summary.maker.cats.psobject.Properties.Name)
        {
            $asset_id = $offer.summary.maker.cats.psobject.Properties.Name
            $offered_asset = ($cats | Where-Object { $_.asset_id -eq $asset_id }).ticker
            $offered_amount = ($offer.summary.maker.cats.($asset_id).amount / 1000) -as [decimal]
            $requested_asset = "XCH"
            $requested_amount = ($offer.summary.taker.xch.amount / 1000000000000) -as [decimal]
            $formatted_offer += [ordered]@{
                
                offered_asset = $offered_asset
                offered_amount = $offered_amount
                requested_asset = $requested_asset
                requested_amount = $requested_amount
                
            }
        }
        else {
            $asset_id = $offer.summary.taker.cats.psobject.Properties.Name
            $offered_asset = "XCH"
            $offered_amount = ($offer.summary.maker.xch.amount / 1000000000000) -as [decimal]
            $requested_asset = ($cats | Where-Object { $_.asset_id -eq $asset_id }).ticker
            $requested_amount = ($offer.summary.maker.xch.amount / 1000) -as [decimal]
            $formatted_offer += [ordered]@{
            
                offered_asset = $offered_asset
                offered_amount = $offered_amount
                requested_asset = $requested_asset
                requested_amount = $requested_amount
            }

        }

        
    }
    $formatted_offer | Format-SpectreTable -Color Green
}
    


