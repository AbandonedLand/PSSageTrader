
class Amount{
    [decimal]$amount
    [bool]$is_xch
    [UInt128]$mojo
    [UInt64]$denom

    Amount([decimal]$amount, [bool]$is_xch = $false) {
        if($is_xch){
            $this.denom = 1000000000000
            $this.amount = [Math]::round($amount,12)
            $this.mojo = [UInt128]([Math]::Round($this.amount * 1000000000000, 0))
        }
        else {
            $this.denom = 1000
            $this.amount = [Math]::round($amount,3)
            $this.mojo = [UInt128]([Math]::Round($this.amount * 1000, 0))
        }   
    }
}


class Asset{
    [string]$name
    [string]$code
    [string]$id
    [UInt64]$denom
    [string]$tibet_pair_id
    [string]$tibet_liquidity_asset_id
    [decimal]$amount
    [System.UInt128]$mojo
    
    Asset([string]$name, [string]$code, [string]$id, [UInt64]$denom, [string]$tibet_pair_id = $null, [string]$tibet_liquidity_asset_id = $null,[decimal]$amount){
        $this.name = $name
        $this.code = $code
        $this.id = $id
        $this.denom = $denom
        $this.tibet_pair_id = $tibet_pair_id
        $this.tibet_liquidity_asset_id = $tibet_liquidity_asset_id
        $this.amount = $amount
        $this.mojo = [System.Math]::Round($amount * $denom, 0)
    }
}

class XCHAmount{
    [decimal]$amount
    [UInt128]$mojo

    XCHAmount([decimal]$amount) {
        $this.amount = [Math]::round($amount, 12)
        $this.mojo = [UInt128]([Math]::Round($this.amount * 1000000000000, 0))
    }
}

class CATAmount{
    [decimal]$amount
    [UInt128]$mojo

    CATAmount([decimal]$amount) {
        $this.amount = [Math]::round($amount  , 3)
        $this.mojo = [UInt128]([Math]::Round($this.amount * 1000, 0))
    }
    
}



function Build-TokenList{
    $page = 1
    $assets = Get-DexieAssets -page_size 100 -page $page -cats
    $tokens = @{}
    $pairs = Invoke-RestMethod -uri "https://api.v2.tibetswap.io/pairs?skip=0&limit=10000" -Method Get
    $tokens.xch = @{}
    $tokens.xch.name = "XCH"
    $tokens.xch.code = "XCH"
    $tokens.xch.id = "xch"
    $tokens.xch.denom = 1000000000000

    while ($tokens.count -lt $assets.count){
        foreach ($asset in $assets.assets){
            $tokens.($asset.code) = @{}
            $tokens.($asset.code).name = $asset.name
            $tokens.($asset.code).code = $asset.code
            $tokens.($asset.code).id = $asset.id
            $tokens.($asset.code).denom = $asset.denom
            $pair = $pairs | Where-Object { $_.asset_id -eq $asset.id}
            if($pair){
                $tokens.($asset.code).tibet_pair_id = $pair.launcher_id
                $tokens.($asset.code).tibet_liquidity_asset_id = $pair.liquidity_asset_id
            }
        }
        
        $page++
        $assets = Get-DexieAssets -page_size 100 -page $page -cats
    }
    return $tokens

}


class GridBot{
    [bool]$stableX
    [string]$id
    $token_x
    $token_y
    [string]$token_x_id
    [string]$token_y_id
    [XCHAmount]$token_x_amount
    [CATAmount]$token_y_amount
    [decimal]$starting_price
    [decimal]$min_price
    [decimal]$max_price
    [int]$steps
    [decimal]$step_size
    [decimal]$step_amount
    [decimal]$percentage
    [array]$grid
    [array]$active_offers
    [array]$completed_offers
    $offer_structure
    [UInt64]$transaction_fee
    [string]$tibet_pair_id
    [string]$fingerprint
    [array]$cancelled_offers

    GridBot(){
        $this.id = (New-Guid).Guid
        $this.grid = @()
        $this.token_x = "xch"
        $this.transaction_fee = 0
    }

    [GridBot] static Load($file){
        if(-Not (Test-Path -Path $file)){
            write-host "File not found: $file"
            return $null
        }
        $json = Get-Content -Path $file | ConvertFrom-Json
        $bot = [GridBot]::new()
        $bot.id = $json.id
        $bot.tibet_pair_id = $json.tibet_pair_id
        $bot.token_x_id = $json.token_x_id
        $bot.token_y_id = $json.token_y_id
        $bot.token_x = $json.token_x
        $bot.token_y = $json.token_y
        $bot.token_x_amount = [XCHAmount]::new($json.token_x_amount.amount)
        $bot.token_y_amount = [CATAmount]::new($json.token_y_amount.amount)
        $bot.min_price = [decimal]$json.min_price
        $bot.max_price = [decimal]$json.max_price
        $bot.steps = [int]$json.steps
        $bot.percentage = [decimal]$json.percentage
        $bot.grid = @($json.grid | ForEach-Object {
            [pscustomobject]$_
        })
        $bot.active_offers = @($json.active_offers | ForEach-Object {
            [pscustomobject]$_
        })
        $bot.completed_offers = @($json.completed_offers | ForEach-Object {
            [pscustomobject]$_
        })
        return $bot
    }

    wizard(){
        $assets = get-content -Path 'assets.json' | ConvertFrom-Json
        
        $this.token_x_id = "xch"
        $this.token_y_id = Read-Host "Enter the ticker of the CAT you want to trade (e.g. 'wUSDC.b')"
        $this.token_x = $assets.($this.token_x_id)
        $this.token_y = $assets.($this.token_y_id)
        $amount_x = Read-Host "Enter the amount of XCH you want to use (e.g. 10)"
        $this.token_x_amount = [XCHAmount]::new($amount_x)
        #$bot.token_y_amount = [CATAmount]::new(500)
        Write-Host "The best way to operate this bot is to set the min or max price to the current price.   You'd create two different bots to trade from current price to min, and from current price to max."
        $this.min_price = Read-Host "Enter the minimum price you want to set (e.g. 10.00)"
        $this.max_price = Read-Host "Enter the maximum price you want to set (e.g. 12.00)"
        $this.steps = Read-Host "Enter the number of steps you want to create (e.g. 10)"
        write-host "Note: the percentage fee is applied to each side of the trade.  The spread will be double the percentage you set here."
        $this.percentage = Read-Host "Enter the percentage fee you want to set (e.g. 0.0025 for 0.25%)"

        $this.BuildGrid()
        $this.save()
        
    }

    [pscustomobject] MakeOfferFromGrid($index, $side,[boolean]$submit=$false,[boolean]$add_to_active = $false){


        if($index -lt 0 -or $index -ge $this.grid.count){
            write-host "Index out of range. Please provide a valid index."
            return $null
        }
        if($side -ne "bid" -and $side -ne "ask"){
            write-host "Invalid side specified. Use 'bid' or 'ask'."
            return $null
        }
        $addresses = Get-Sagederivations -limit 100 -offset 0 
        $send_to = $addresses[$index].address
        
        $json = $this.grid[$index].$side
        $json | Add-Member -MemberType NoteProperty -Name "receive_address" -Value $send_to
        
            $offer = Invoke-SageRPC -endpoint make_offer -json $json
            $details = @{
                offer_id = $offer.offer_id
                side = $side
                price = $this.grid[$index].price
                index = $index
            }
            if($submit){
                $this.SubmitOffer($offer.offer_id)
            }
            if($add_to_active){
                $this.active_offers += [pscustomobject]$details
                $this.save()
            }
           
            
            
        return [pscustomobject]$details
    }

    
    CancelOffers(){
        $this.active_offers | ForEach-Object {
            $offer_id = $_.offer_id
            $response = Revoke-SageOffer -offer_id $offer_id.offer_id
            if($response){
                write-host "Offer $offer_id cancelled successfully."
                $this.cancelled_offers += $_
            } else {
                write-host "Failed to cancel offer $offer_id."
            }
        }
        $this.save()
    }

    BuildGrid(){
        
        $this.step_size = ($this.max_price - $this.min_price) / ($this.steps-1)
        if($this.token_y_amount.amount -gt 0 -AND (-NOT $this.token_x_amount.amount -gt 0)){
            $this.step_amount = [Math]::round($this.token_y_amount.amount / $this.steps,3)
            $this.stableX=$false
        }
        elseif($this.token_x_amount.amount -gt 0 -AND (-NOT $this.token_y_amount.amount -gt 0)){
            $this.step_amount = [Math]::round($this.token_x_amount.amount / $this.steps,3)
            $this.stableX=$true
        }
        else {
            write-host "You must set either token_x_amount or token_y_amount to a value greater than 0"
            return
        }

        for ($i = 0; $i -lt $this.steps; $i++){
            $tmp_price = [CATAmount]::new($this.min_price + ($this.step_size * $i))
            if($this.stableX){
                $xch = [XCHAmount]::new($this.step_amount)
                $y_amount = [CATAmount]::new($this.step_amount * $tmp_price.amount)
                $y_fee = [CATAmount]::new($y_amount.amount * $this.percentage)
                $x_fee = [XCHAMount]::new(0)
            }
            else {
                $xch = [XCHAmount]::new($this.step_amount / $tmp_price.amount)
                $y_amount = [CATAmount]::new($this.step_amount)
                $y_fee = [CATAmount]::new(0)
                $x_fee = [XCHAmount]::new($xch.amount * $this.percentage)
            }

            

            $row = [pscustomobject]@{
                xch = [UInt64]$xch.mojo
                x_fee = [UInt64]$x_fee.mojo
                y_fee = [UInt64]$y_fee.mojo
                price = [decimal]$tmp_price.amount
                ask = [ordered]@{
                    requested_assets = [ordered]@{
                        xch = [UInt64]($xch.mojo + $x_fee.mojo)
                        cats= @()
                        nfts = @()
                    }
                    offered_assets = [ordered]@{
                        xch = 0
                        cats = @(
                            [ordered]@{
                                asset_id = ($this.token_y.id)
                                amount = [Uint64]($y_amount.mojo - $y_fee.mojo)
                            }
                        )
                        nfts = @()
                    }
                    fee=$this.transaction_fee
                }
                bid = [ordered]@{
                    requested_assets = [ordered]@{
                        xch = 0
                        cats= @(
                            [ordered]@{
                                asset_id = ($this.token_y.id)
                                amount = [Uint64]($y_amount.mojo + $y_fee.mojo)
                            }
                        )
                        nfts = @()
                    }
                    offered_assets = [ordered]@{
                        xch = [UInt64]($xch.mojo - $x_fee.mojo)
                        cats = @()
                        nfts = @()
                    }
                    fee=$this.transaction_fee
                }                
            }
            $this.grid += $row
        }
    }

    GetBotPnL(){
        $xch_total = 0
        $cat_total = 0
        $fee = 0
        foreach($offer in $this.completed_offers){
            if($offer){
                $sageoffer = Get-SageOffer -offer_id ($offer.offer_id)
                $xch_total -= $sageoffer.summary.maker.xch.amount
                $cat_total -= $sageoffer.summary.maker.cats.($this.token_y.id).amount
                $xch_total += $sageoffer.summary.taker.xch.amount
                $cat_total += $sageoffer.summary.taker.cats.($this.token_y.id).amount  
                $fee += $this.grid[$offer.index].x_fee + $this.grid[$offer.index].y_fee
            }
        }
        Write-Host "XCH Total: $($xch_total / 1000000000000) XCH"
        Write-Host "CAT Total: $($cat_total / 1000) $($this.token_y.code)"
        Write-Host "Total Fees: $([Math]::round($fee / 1000,3))"
        if($xch_total -ne 0 -and $cat_total -ne 0){
            $price = ([decimal]$cat_total / 1000)/([decimal]$xch_total / 1000000000000 )
            Write-Host "Average Price: $([Math]::Abs([Math]::round($price,3)))"
        }
        
        $null = $xch_total
        $null = $cat_total

    }

    BuildInitialOffers($side){
        if($side -ne "bid" -and $side -ne "ask"){
            write-host "Invalid side specified. Use 'bid' or 'ask'."
            return
        }
        if($this.grid.count -eq 0){
            write-host "Grid is empty. Please build the grid first."
            return
        }
        if($this.active_offers.count -gt 0){
            write-host "Active offers already exist. Please clear them before building new offers."
            return
        }
        
        foreach($grid in $this.grid){
            
            $this.MakeOfferFromGrid($this.grid.IndexOf($grid), $side,$true, $true)
            

        }
        $this.save()

    }



    [string]GetPairId(){
        if(-NOT $this.tibet_pair_id){
            $this.tibet_pair_id = (Get-TibetToken -asset_id $this.token_y.id  ).pair_id
            $this.save()
        }
        return $this.tibet_pair_id
    }

    SubmitAllOffers(){
        if($this.active_offers.count -eq 0){
            write-host "No active offers to submit."
            return
        }
        foreach($offer in $this.active_offers){
            $offer_data = Get-SageOffer -offer_id $offer.offer_id -ErrorAction SilentlyContinue
            if($offer_data -eq $null){
                write-host "Offer with ID $($offer.offer_id) not found. Skipping."
                continue
            }
            $this.SubmitOffer($offer_data.offer)
        }
     
    }

    SubmitOffer($offer){
        if(-NOT $offer.StartsWith("offer1")){
            $offer_data = Get-SageOffer -offer_id $offer
            $offer = $offer_data.offer
        }
        $uri = "https://api.dexie.space/v1/offers"
        $body = @{
            offer = $offer
            claim_rewards = $true
            drop_only = $true
        } | ConvertTo-Json -Depth 20
        Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType "application/json" | Out-Null
    }

    ClearAllOffers(){
        if($this.active_offers.count -eq 0){
            write-host "No active offers to clear."
            return
        }
        foreach($offer in $this.active_offers){
            Remove-SageOffer -offer_id $offer.offer_id
        }
        $this.active_offers = @()
        
    }

    [array] static LoadAll(){
        $files = Get-ChildItem -Path "./bots" -Filter "*.json"
        $bots = @()
        foreach($file in $files){
            $bot = [GridBot]::Load($file.FullName)
            if($bot){
                $bots += $bot
            }
        }
        return $bots
    }

    CheckOffers(){
        if($this.active_offers.count -eq 0){
            write-host "No active offers to check."
            return
        }
        foreach($offer in $this.active_offers){
            $details = Get-SageOffer -offer_id $offer.offer_id -ErrorAction SilentlyContinue
            if($details){
                if($details.status -eq "completed"){
                    $this.completed_offers += $offer
                    if($offer.side -eq "bid"){
                        $response = $this.MakeOfferFromGrid($offer.index, "ask",$true,$true) 
                        $this.active_offers = $this.active_offers | Where-Object { $_.offer_id -ne $offer.offer_id }
                        
                    }
                    if($offer.side -eq "ask"){
                        $response = $this.MakeOfferFromGrid($offer.index, "bid",$true,$true)                         
                        $this.active_offers = $this.active_offers | Where-Object { $_.offer_id -ne $offer.offer_id }
                        
                    }            
                    
                }

                elseif($details.status -eq "cancelled"){
                    $this.makeOfferFromGrid($offer.index, $offer.side, $true, $true)
                    $this.active_offers = $this.active_offers | Where-Object { $_.offer_id -ne $offer.offer_id }
                    $this.cancelled_offers += $offer
                }
            } else {
                Write-Host "Offer with ID $($offer.offer_id) not found. Rebuilding offer."
                    $this.makeOfferFromGrid($offer.index, $offer.side, $true, $true)
                    $this.active_offers = $this.active_offers | Where-Object { $_.offer_id -ne $offer.offer_id }
                    $this.cancelled_offers += $offer
            }
        }
        $this.save()
    }
    

    run(){
        while($true){
            Write-Host "Running bot with ID: $($this.id)"
            Write-Host "Checking active offers..."
            Write-Host "-----------------------------"
            $this.CheckOffers()
            $this.GetBotPnL()
            
            Write-Host "-----------------------------"
            

            Start-Sleep -Seconds 60
        }
    }

    save(){
        $file = "./bots/$($this.id).json"
        $this | ConvertTo-Json -Depth 20 | Out-File -FilePath $file -Encoding utf8
    }

}


function Get-Sum([array]$array){
    $sum = 0
    foreach($item in $array){
        $sum += $item
    }
    return $sum
}






