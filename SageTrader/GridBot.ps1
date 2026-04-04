class GridBot{
    [string]$id
    [string]$name
    [SageToken]$offeredToken
    [SageToken]$requestedToken
    [decimal]$offeredTokenAmount
    [decimal]$startingPrice
    [decimal]$currentPrice
    [decimal]$targetPrice
    [int]$steps
    [array]$grid
    [array]$activeOffers
    [array]$completedOffers    
    [string]$fingerprint
    [array]$cancelledOffers
    [decimal]$feePercentage
    [bool]$isPrepped
    [bool]$isActive
    
    
    

    GridBot(){
        $this.id = (New-Guid).Guid
        $this.isActive = $false
        $this.isPrepped = $false
        $this.grid = @()
        $this.activeOffers = @()
        $this.completedOffers = @()
        $this.cancelledOffers = @()

        
    }

    GridBot([PSCustomobject]$props){
        $this.Init([PSCustomObject]$props)
        
    }

    [bool] isLoggedIn(){
        $fp = (Invoke-SageRPC -endpoint get_key -json @{})
        if($null -eq $fp){
            return $false
        }
        if($fp.key.fingerprint -eq $this.fingerprint){
            return $true
        }
        return $false
    }

    [bool] isActive(){
        if($this.isActive -eq $true){
            return $true
        } else {
            return $false    
        }
        
    }


    [void] activate(){
        $this.isActive = $true
        $this.save()
    }

    [void] deactivate(){
        $this.isActive = $false
        $this.save()
    }

    [void] Handle(){
        $this.checkOffers()
    }

    [void] checkOffers(){
        
        if($this.isActive() -and $this.isLoggedIn()){
            $bids = $this.active_offers | Where-Object {$_.side -eq "bid"} | Sort-Object index -Descending
            $asks = $this.active_offers |  Where-Object {$_.side -eq "ask"} | Sort-Object {$_.index}
            #$actives = $this.active_offers | Sort-Object {$_.index}
            foreach($active in $bids) {
                $offer = Get-SageOffer -offer_id $active.offer_id
                if($offer.status -eq "completed"){
                    $this.updateLogOffer($active.offer_id,"completed")
                    
                    #remove this offer
                    $completed = @{
                        grid = $this.grid[($active.index)].($active.side)
                        offer_id = ($active.offer_id)
                    }
                    $this.x_fee_collected += $this.grid[($active.index)].x_fee_amount
                    $this.y_fee_collected += $this.grid[($active.index)].y_fee_amount
                    
                    $this.completed_offers += $completed
                    $this.active_offers = $this.active_offers | Where-Object {$_.offer_id -ne $active.offer_id}
                    $index = $active.index
                    $isAsk = ($active.side -eq "ask") ? $true : $false
                    try {
                        $this.CreateOfferFromGridIndex($index,(-not $isAsk))    
                    }
                    catch {
                        Write-SpectreHost -Message "[red]Failed to create new offer from grid index $index after completing offer $($active.offer_id). Error: $($_.Exception.Message)[/]"
                    }
                    
                }
                
            }
            foreach($active in $asks) {
                $offer = Get-SageOffer -offer_id $active.offer_id
                if($offer.status -eq "completed"){
                    $this.updateLogOffer($active.offer_id,"completed")
                    
                    #remove this offer
                    $completed = @{
                        grid = $this.grid[($active.index)].($active.side)
                        offer_id = ($active.offer_id)
                    }
                    $this.x_fee_collected += $this.grid[($active.index)].x_fee_amount
                    $this.y_fee_collected += $this.grid[($active.index)].y_fee_amount
                    
                    $this.completed_offers += $completed
                    $this.active_offers = $this.active_offers | Where-Object {$_.offer_id -ne $active.offer_id}
                    $index = $active.index
                    $isAsk = ($active.side -eq "ask") ? $true : $false
                    $this.CreateOfferFromGridIndex($index,(-not $isAsk))
                }
                
            }
        }
    }

    [array] getLog(){
        $path = Get-SageTraderPath("offerlogs")
        $file = Join-Path -Path $path -ChildPath "$($this.id).csv"
        
        if(-not (Test-Path -Path $file)){
            Write-SpectreHost -Message "[red]No logs found for this bot.[/]"
            return @()
        }
        $log = Import-Csv -Path $file
        if($null -eq $log){
            Write-SpectreHost -Message "[red]No logs found for this bot.[/]"
            return @()
        }
        if($log.count -eq 0){
            Write-SpectreHost -Message "[red]No logs found for this bot.[/]"
            return @()
        }
        return $log
    }

    [void] Init([PSCustomobject]$props)  {
        $this.id = $props.id
        $this.name = $props.name
        if($props.offeredToken){
            $this.offeredToken = [SageToken]::new($props.offeredToken)
        }
        if($props.requestedToken){
            $this.requestedToken = [SageToken]::new($props.requestedToken)
        }
        $this.startingPrice = $props.startingPrice
        $this.currentPrice = $props.currentPrice
        $this.maxPrice = $props.maxPrice
        $this.steps = $props.steps
        $this.grid = $props.grid
        $this.activeOffers = $props.activeOffers
        $this.completedOffers = $props.completedOffers
        $this.fingerprint = $props.fingerprint
        $this.fee_percentage = $props.fee_percentage
        $this.fee_token_id = $props.fee_token_id
        $this.cancelledOffers = $props.cancelledOffers
        $this.feePercentage = $props.feePercentage
        $this.isActive = $props.isActive
        $this.isPrepped = $props.isPrepped
        $this.offeredTokenAmount = $props.offeredTokenAmount

    }


    [array] forcePrep(){
        if($this.isPrepped){
            return $null
        }
        return $this._splitCoins()
    }

    [array] _splitCoins(){
        if($this.isPrepped){
            throw "Coins are already prepped for this bot."
            
        }
        if(-not $this.isLoggedIn()){
            
            throw "User is not logged in."
            
        }
        $array = @()
    
        
        $addresses = (Get-SageDerivations -offset 0 -limit ($this.steps*2)).derivations
        if($this.offeredToken.id -eq 'xch' -and $this.offeredTokenAmount -gt 0){
            
            $payments = Build-SageBulkPayments
            1..($this.steps) | ForEach-Object {
                $payments.addXchPayment($addresses[$_].address,($this.offeredTokenAmount/$this.steps))
                }
            $payments.submit()
            $array += ($payments.response )
        } elseif($this.offeredToken.id -ne 'xch' -and $this.offeredTokenAmount -gt 0){
            $payments = Build-SageBulkPayments
            1..($this.steps) | ForEach-Object {
                $payments.addCatPayment($this.offeredToken.id,$addresses[$_].address,($this.offeredTokenAmount/$this.steps))
            }
            $payments.submit()
            $array += ($payments.response )
        }
        if($array.count -gt 0){
            $this.isPrepped = $true
            $this.save()
        }
        return $array
    }

    [array] prepCoins(){
        if($this.isPrepped){
            throw "Coins are already prepped for this bot."
        }
        $confirm = Read-SpectreConfirm "Do you want to split your coins to run the bot?"
        if(-not $confirm){
            Write-SpectreHost -Message "[yellow]Coins not split.[/]"
            return $null
        }
        return $this._splitCoins()
        
    }

    [void] destroy(){
        $path = $this.path()
        $path = Join-Path -Path $path -ChildPath "$($this.id).json"
        
        $check = Read-SpectreConfirm -Message "Are you sure you want to delete this bot?" -DefaultAnswer "n"
        
        if($check -eq $true){
            
                if(Test-Path -Path $path){
                    $this.CancelOffers()
                    Remove-Item -Path $path -Force
                    Write-SpectreHost -Message "[green]Bot deleted successfully.[/]"
                    
                } else {
                    Write-SpectreHost -Message "[red]Bot not found.[/]"
                }
            
        } else {
            Write-SpectreHost -Message "[yellow]Bot deletion cancelled.[/]"
        
        }
        
    }

    [void] logOffer($log){
        $path = $this.path()
        $file = Join-Path -Path $path -ChildPath "$($this.id).csv"
        
        if(-not (Test-Path -Path $path)){
            New-Item -Path $path -ItemType Directory | Out-Null
        }
        if(-not (Test-Path -Path $file)){
            $log | Export-Csv -Path $file -NoTypeInformation
        } else {
            $log | Export-Csv -Path $file -NoTypeInformation -Append
        }

    }

    [void] updateLogOffer($offer_id,$status){
        $path = $this.path()
        $file = Join-Path -Path $path -ChildPath "$($this.id).csv"
        $offers = Import-Csv -Path $file
        $offer = $offers | Where-Object {$_.offer_id -eq $offer_id}
        if($offer){
            $offer.status = $status
            $offers | Export-Csv -Path $file -NoTypeInformation
        }
    }

    [void]makeInitialOffers(){
        if($this.isLoggedIn() -and $this.active_offers.Count -eq 0){
            $this.grid | ForEach-Object {
                $this.CreateOfferFromGridIndex($_.index,$true)
            }
        }
    }

    [void]CreateOfferFromGridIndex([UInt32]$index,[bool]$isAsk){
        
        if($isAsk -eq $true){
            $side = "ask"
        } else {
            $side = "bid"
        }
        
        $addresses = (Get-SageDerivations -offset 0 -limit ($this.steps*2)).derivations
        $row = $this.grid | Where-Object {$_.index -eq $index}
        $buildData = $row.$side
        if($null -eq $buildData){
            Write-SpectreHost "[red]Failed to find data for bot[/]"
            return
        }
        $offer = Build-SageOffer
        ($buildData.requested_asset_id -eq "xch") ? $offer.requestXch($buildData.requested_asset_amount) : $offer.requestCat($buildData.requested_asset_id,$buildData.requested_asset_amount)
        ($buildData.offered_asset_id -eq "xch") ? $offer.offerXch($buildData.offered_asset_amount) : $offer.offerCat($buildData.offered_asset_id,$buildData.offered_asset_amount)
        ($this.transaction_fee -gt 0) ? $offer.setFee($this.transaction_fee) : $offer.setFee(0)
        $offer.setReceiveAddress($addresses[$index].address)
        Write-SpectreHost -Message "

        GridBot with ID: [green]$($this.id)[/] is ATTEMPTING to create a(n) [green]$($side)[/] offer from Index: [green]$($index) [/]
        "
        
        $offer.createoffer()
        $offer.json | Format-SpectreJson
        
        if($offer.offer_data){
            Write-SpectreHost -Message "
        Offer Created Successfully.
            "
            $active_offer = [PSCustomObject]@{
                offer_id = $offer.offer_data.offer_id
                index = $index
                side = $side                
            }
            $this.active_offers += $active_offer
            $this.save()
            $dexie = Submit-DexieOffer -offer $offer.offer_data.offer -claim_rewards

            if(-not $null -eq $dexie){
                Write-SpectreHost -Message "[green]Offer [/][blue] - $($dexie.id) - [/][green] submitted to Dexie successfully.[/]"                
                
            }
            $log = [PSCustomObject]@{
                offer_id = $offer.offer_data.offer_id    
                bot_type = $this.GetType().Name
                bot_id = $this.id
                offered_asset_id = $buildData.offered_asset_id
                offered_asset_amount = $buildData.offered_asset_amount
                requested_asset_id =  $buildData.requested_asset_id
                requested_asset_amount = $buildData.requested_asset_amount
                fee_token_id = $this.fee_token_id
                status = "pending"
                created_at = (Get-Date)
                updated_at = (Get-Date)
                fingerprint = $this.fingerprint
                dexie_id = ($dexie.id)
            }

            $this.logOffer($log)


        }

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
        $addresses = (Get-SageDerivations -offset 0 -limit ($this.steps)).derivations
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
        try {
            if($this.isLoggedIn()){
            $this.active_offers | ForEach-Object {
            
                $offer_id = $_.offer_id
                $this.updateLogOffer($offer_id,"cancelled")
                $response = Revoke-SageOffer -offer_id $offer_id
                if($response){
                    write-host "Offer $offer_id cancelled successfully."
                    $this.cancelled_offers += $_
                } else {
                    write-host "Failed to cancel offer $offer_id."
                }
            
                }
            
            $this.save()
            }
        }
        catch {
            Write-SpectreHost -Message "[red]Failed to cancel offers. Please check your connection and try again.[/]"
            Write-SpectreHost -Message "[red]Error: $($_.Exception.Message)[/]"
        }
        
    }

    BuildGrid(){
        $step_amount = $this.offeredTokenAmount / $this.steps
        $step_size = ($this.targetPrice - $this.startingPrice) / ($this.steps-1)
        $invert = $false
        if($step_size -lt 0){
            $invert = $true
        }

        if($step_amount -eq 0 -OR $step_size -eq 0){
            return
        }
        for ($i = 0; $i -lt $this.steps; $i++){
            if($invert){
                $tPrice = [System.Math]::Round($this.targetPrice - ($step_size * $i),3)
            } else {
                $tPrice = [System.Math]::Round($this.startingPrice + ($step_size * $i),3)
            }
            
            [UInt64]$offered_amount = (($step_amount * [System.Math]::Pow(10,($this.offeredToken.precision))))
            [UInt64]$requested_amount = ($tPrice * $step_amount * [System.Math]::Pow(10,($this.requestedToken.precision)))
            $fee_amount = [UInt64]($requested_amount * $this.feePercentage)
            
            
            $row = [pscustomobject]@{
                index = ($i)
                price = [decimal]$tPrice
                fee_amount = $fee_amount
                ask = [ordered]@{
                    requested_asset_id = $this.offeredToken.asset_id
                    requested_asset_amount = $offered_amount
                    offered_asset_id = $this.requestedToken.asset_id
                    offered_asset_amount = $requested_amount
                }
                bid = [ordered]@{
                    requested_asset_id = $this.requestedToken.asset_id
                    requested_asset_amount = $requested_amount + $fee_amount
                    offered_asset_id = $this.offeredToken.asset_id
                    offered_asset_amount = $offered_amount
                }
            }
            $this.grid += $row
        }
    }


    
    [string] path(){
        $subfolder = "GridBots"
        if([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
            [System.Runtime.InteropServices.OSPlatform]::Windows
        )){
            if(-not (Test-Path -Path "$env:LOCALAPPDATA\SageTrader")){
                New-Item -Path "$env:LOCALAPPDATA\SageTrader" -ItemType Directory | Out-Null
            }
            if($null -eq $subfolder){
                return "$env:LOCALAPPDATA\SageTrader"
            }
            if(-not (Test-Path -Path "$env:LOCALAPPDATA\SageTrader\$subfolder")){
                New-Item -Path "$env:LOCALAPPDATA\SageTrader\$subfolder" -ItemType Directory | Out-Null
            }
            return "$env:LOCALAPPDATA\SageTrader\$subfolder"
        } 

        if([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
            [System.Runtime.InteropServices.OSPlatform]::Linux
        )){
            if(-not (Test-Path -Path "$([System.Environment]::GetFolderPath('UserProfile'))/.local/share/SageTrader")){
                New-Item -Path "$([System.Environment]::GetFolderPath('UserProfile'))/.local/share/SageTrader" -ItemType Directory | Out-Null
            }
            if($null -eq $subfolder){
                return "$([System.Environment]::GetFolderPath('UserProfile'))/.local/share/SageTrader"
            }
            if(-not (Test-Path -Path "$([System.Environment]::GetFolderPath('UserProfile'))/.local/share/SageTrader/$subfolder")){
                New-Item -Path "$([System.Environment]::GetFolderPath('UserProfile'))/.local/share/SageTrader/$subfolder" -ItemType Directory | Out-Null
            }
            return "$([System.Environment]::GetFolderPath('UserProfile'))/.local/share/SageTrader/$subfolder"
        }
        if([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
            [System.Runtime.InteropServices.OSPlatform]::OSX
        )){
            if(-not (Test-Path -Path "$([System.Environment]::GetFolderPath('UserProfile'))/Library/Application Support/SageTrader")){
                New-Item -Path "$([System.Environment]::GetFolderPath('UserProfile'))/Library/Application Support/SageTrader" -ItemType Directory | Out-Null
            }
            if($null -eq $subfolder){
                return "$([System.Environment]::GetFolderPath('UserProfile'))/Library/Application Support/SageTrader"
            }
            if(-not (Test-Path -Path "$([System.Environment]::GetFolderPath('UserProfile'))/Library/Application Support/SageTrader/$subfolder")){
                New-Item -Path "$([System.Environment]::GetFolderPath('UserProfile'))/Library/Application Support/SageTrader/$subfolder" -ItemType Directory | Out-Null
            }
            return "$([System.Environment]::GetFolderPath('UserProfile'))/Library/Application Support/SageTrader/$subfolder"
        }
        return ""
    
    }

    save(){
        $path = $this.path()
        $file = Join-Path -Path $path -ChildPath "$($this.id).json"
        $this | ConvertTo-Json -Depth 20 | Out-File -FilePath $file -Encoding utf8
    }

}

$grid = [GridBot]::new()
$grid.name = "Test Grid Bot"
$grid.offeredToken = [SageToken]::new("xch")
$grid.requestedToken = [SageToken]::new("byc")
$grid.offeredTokenAmount = 200
$grid.startingPrice = 2.40
$grid.targetPrice = 3.00
$grid.steps  = 100
$grid.fingerprint = 2591181559
$grid.feePercentage = 0.003
$grid.BuildGrid()