Class FTToken{
    $asset
    $tibet_quote
    $pair_id
    $quote
    $offer

    FTToken($asset_id){
        $this.asset = Get-ChiaAsset -id $asset_id
        $this.pair_id = $this.asset.tibet_pair_id
    }

    tibetQuoteCatGiven($amount){
            $response = Get-TibetQuote -pair_id ($this.pair_id) -amount_in ($amount | ConvertTo-CatMojo) 
            $response | Add-Member -MemberType NoteProperty -Name xch_is_input -value $false
            $response | Add-Member -MemberType NoteProperty -Name xch_is_wanted -value $true
        $this.quote = $response
    }

    tibetQuoteCatWanted($amount){
        $response = Get-TibetQuote -pair_id ($this.pair_id) -amount_out ($amount | ConvertTo-CatMojo) -xch_is_input
        $response | Add-Member -MemberType NoteProperty -Name xch_is_input -value $true
        $response | Add-Member -MemberType NoteProperty -Name xch_is_wanted -value $false
        $this.quote = $response
    }

    tibetQuoteXchGiven($amount){
        $response = Get-TibetQuote -pair_id ($this.pair_id) -amount_in ($amount | ConvertTo-XchMojo) -xch_is_input
        $response | Add-Member -MemberType NoteProperty -Name xch_is_input -value $true
        $response | Add-Member -MemberType NoteProperty -Name xch_is_wanted -value $false
        $this.quote = $response
    }

    tibetQuoteXchWanted($amount){
        $response = Get-TibetQuote -pair_id ($this.pair_id) -amount_out ($amount | ConvertTo-XchMojo)
        $response | Add-Member -MemberType NoteProperty -Name xch_is_input -value $false
        $response | Add-Member -MemberType NoteProperty -Name xch_is_wanted -value $true
        $this.quote = $response
    }


    buildOfferFromQuote(){
        $this.offer = Build-SageOffer
        if($this.quote.xch_is_wanted){
            $this.offer.requestXch($this.quote.amount_out)
            $this.offer.offercat($this.asset.id,$this.quote.amount_in)
        } else {
            $this.requestCat($this.asset.id,$this.quote.amount_out)
            $this.offeredxch($this.quote.amount_id)
        }

    }

    dexieQuoteCatGiven($amount){
        $amount = ($amount | ConvertTo-CatMojo)
        $response = Get-DexieQuote -from ($this.asset.code) -from_amount $amount -to xch
        $response = $response.quote
        $this.quote = [pscustomobject]@{
            amount_in = $amount
            amount_out = ($response.to_amount)
            xch_is_input = $false
            xch_is_wanted = $true
        }
    }

    dexieQuoteCatWanted($amount){
        $amount = ($amount | ConvertTo-CatMojo)
        $response = Get-DexieQuote -from xch -to_amount $amount -to ($this.asset.code)
        $response = $response.quote
        $this.quote = [pscustomobject]@{
            amount_in = $amount
            amount_out = ($response.to_amount)
            xch_is_input = $true
            xch_is_wanted = $true
        }
    }

    dexieQuoteXchWanted($amount){
        $amount = ($amount | ConvertTo-XchMojo)
        $response = Get-DexieQuote -from ($this.asset.code) -to_amount $amount -to xch
        $response = $response.quote
        $this.quote = [pscustomobject]@{
            amount_in = $amount
            amount_out = ($response.to_amount)
            xch_is_input = $true
            xch_is_wanted = $true
        }
    }

    
    dexieQuoteXchGiven($amount){
        $amount = ($amount | ConvertTo-XchMojo)
        $response = Get-DexieQuote -from xch -from_amount $amount -to ($this.asset.code)
        $response = $response.quote
        $this.quote = [pscustomobject]@{
            amount_in = $amount
            amount_out = ($response.to_amount)
            xch_is_input = $true
            xch_is_wanted = $false
        }
    }

}


function trade-xchToByc{
    # xch -> byc -> usd % byc -> xch
    param(
        $xch_amount
    )
    [decimal]$gained_xch = 0
    $xch_to_sell = $xch_amount
    $offers_to_take = @()
    [decimal]$byc_temp =0
    [decimal]$usd_temp = 0
    $wusdc = [FTToken]::new('wusdc.b')
    $byc = [FTToken]::new('byc')
    Write-SpectreHost -Message "[green]Starting Arbitrage Run[/]"
    Write-SpectreHost -Message "[green]Checking Dexie Offers[/]"
    $dex_xchbyc_offers = Get-DexieOffers -requested xch -offered byc -results_only


    $dex_xchbyc_offers | ForEach-Object {
        if($xch_to_sell -gt 0 -AND ($_.requested[0].amount) -le $xch_to_sell ){
            $xch_to_sell -= ($_.requested[0].amount)
            $byc_temp += ($_.offered[0].amount)
            $offers_to_take += $_
        }
    }
    if($xch_amount -eq $xch_to_sell){
        Write-SpectreHost -Message "[red]No Offers available[/]"
        break
    }
    

    Write-SpectreHost -Message "[green]Can get $byc_temp BYC from $xch_amount with $xch_to_sell Left over[/]"
    

    $dex_bycusd_offers =  Get-DexieOffers -requested byc -offered wusdc.b -results_only
    $dex_bycusd_offers | ForEach-Object {
        if($byc_temp -gt 0 -AND ($_.requested[0].amount) -le $byc_temp ){
            $byc_temp -= ($_.requested[0].amount)
            $usd_temp += ($_.offered[0].amount)
            $offers_to_take += $_
        } 
        
    }
    
    Write-SpectreHost -Message "[green] BYC: $byc_temp   wUSDC.b: $usd_temp [/]"

    $usd_xch_offers = Get-DexieOffers -requested wusdc.b -offered xch -results_only
    $usd_xch_offers | ForEach-Object {
        if($usd_temp -gt 0 -AND ($_.requested.amount) -le $usd_temp ){
            $usd_temp -= ($_.requested[0].amount)
            $gained_xch += ($_.offered[0].amount)
            $offers_to_take += $_
        }
    }

    # Sell remaining on tibet
    if($usd_temp -gt 0){
        $wusdc.tibetQuoteCatGiven(($usd_temp))
        $gained_xch += (($wusdc.quote.amount_out) | ConvertFrom-XchMojo)
    }
    if($byc_temp -gt 0){
        $byc.tibetQuoteCatGiven(($byc_temp))
        $gained_xch += (($byc.quote.amount_out) | ConvertFrom-XchMojo)
    }


    Write-Host "Starting XCH: $xch_amount"
    Write-Host "Ending XCH: $gained_xch"
    
    return @{
        take = $offers_to_take
        usdc = $wusdc
        byc = $byc
    }

}

function trade-byc{
    param(
        $byc_amount
    )

    $offers_to_take = @()
    #byc->usd->xch->byc
    [decimal]$usdc_temp = 0
    [decimal]$gained_xch = 0
    $usd = [FTToken]::new('wusdc.b')
    $byc = [FTToken]::new('byc')

    $byc_to_usd = Get-DexieOffers -offered wusdc.b -requested byc -results_only -page_size 1
    if($byc_to_usd.requested[0].amount -ne $byc_amount){
        Write-Host "Price doesn't match"
        break
    }
    $usdc_temp = $byc_to_usd.offered[0].amount
    

    $xchOffers = Get-DexieOffers -offered xch -requested wusdc.b -results_only
    $xchOffers | ForEach-Object {
          if($usdc_temp -gt 0 -AND ($_.requested.amount) -le $usdc_temp ){
            $usdc_temp -= ($_.requested[0].amount)
            $gained_xch += ($_.offered[0].amount)
            $offers_to_take += $_
        }
    }
    if($usdc_temp -gt 0){
        $usd.tibetQuoteCatGiven($usdc_temp)
        $gained_xch += (($usd.quote.amount_out) | ConvertFrom-XchMojo)
    }

    $gained_xch
    $byc_offers = Get-DexieOffers -offered byc -requested xch -results_only

    $byc_offers | ForEach-Object {
          if($gained_xch -gt 0 -AND ($_.requested.amount) -le $gained_xch ){
            $gained_xch -= ($_.requested[0].amount)
            $byc_temp += ($_.offered[0].amount)
            $offers_to_take += $_
        }
    }
    if($gained_xch -gt 0){
        $byc = [FTToken]::new('byc')
        $byc.tibetQuoteXchGiven($gained_xch)
        $byc_temp += (($byc.quote.amount_out) | ConvertFrom-CatMojo)
    }

    $byc_temp

}


# Submit-TibetOffer -action SWAP -pair_id ($trades.byc.asset.tibet_pair_id) -offer ($trades.byc.offer.offer_data.offer)
# Submit-TibetOffer -action SWAP -pair_id ($trades.usdc.asset.tibet_pair_id) -offer ($trades.usdc.offer.offer_data.offer)
# $trades.take | ForEach-Object {
#     Complete-SageOffer -offer ($_.offer)
# }