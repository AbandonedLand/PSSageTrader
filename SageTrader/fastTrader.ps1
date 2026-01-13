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

    quoteCatGiven($amount){
            $response = Get-TibetQuote -pair_id ($this.pair_id) -amount_in ($amount | ConvertTo-CatMojo) 
            $response | Add-Member -MemberType NoteProperty -Name xch_is_input -value $false
            $response | Add-Member -MemberType NoteProperty -Name xch_is_wanted -value $true
        $this.quote = $response
    }

    quoteCatWanted($amount){
        $response = Get-TibetQuote -pair_id ($this.pair_id) -amount_out ($amount | ConvertTo-CatMojo) -xch_is_input
        $response | Add-Member -MemberType NoteProperty -Name xch_is_input -value $true
        $response | Add-Member -MemberType NoteProperty -Name xch_is_wanted -value $false
        $this.quote = $response
    }

    quoteXchGiven($amount){
        $response = Get-TibetQuote -pair_id ($this.pair_id) -amount_in ($amount | ConvertTo-XchMojo) -xch_is_input
        $response | Add-Member -MemberType NoteProperty -Name xch_is_input -value $true
        $response | Add-Member -MemberType NoteProperty -Name xch_is_wanted -value $false
        $this.quote = $response
    }

    quoteXchWanted($amount){
        $response = Get-TibetQuote -pair_id ($this.pair_id) -amount_out ($amount | ConvertTo-XchMojo)
        $response | Add-Member -MemberType NoteProperty -Name xch_is_input -value $false
        $response | Add-Member -MemberType NoteProperty -Name xch_is_wanted -value $true
        $this.quote = $response
    }


    buildOfferFromQuote(){
        $this.offer = Build-SageOffer
        if($this.quote.xch_is_wanted){
            $this.offer.requestXch($this.quote.amount_out)
            $this.offer.offercat($this.asset.asset_id,$this.quote.amount_in)
        } else {
            $this.requestCat($this.asset.asset_id,$this.quote.amount_out)
            $this.offeredxch($this.quote.amount_id)
        }

    }

}

