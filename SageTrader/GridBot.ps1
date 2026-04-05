
class ChiaBot{
    [string]$id
    [string]$name
    $offeredToken
    $requestedToken
    [decimal]$offeredTokenAmount
    [decimal]$startingPrice
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
    [bool]$isStableCoinPair
    [array]$pendingCreateOffers
    [array]$addresses
    [datetime]$lastHandled
    [datetime]$LastTradedAt

    ChiaBot(){
        $this.id = (New-Guid).Guid
        $this.isActive = $false
        $this.isPrepped = $false
        $this.grid = @()
        $this.activeOffers = @()
        $this.completedOffers = @()
        $this.cancelledOffers = @()
        $this.isStableCoinPair = $false
        $this.pendingCreateOffers = @()
        $this.lastHandled = Get-Date
        $this.LastTradedAt = Get-Date
    }

    ChiaBot([PSCustomobject]$props){
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
        $this.makePendingOffers()
    }

    [void] makePendingOffers(){
        
        $poffers = $this.pendingCreateOffers 

        foreach($pof in $poffers){
            $this.CreateOfferFromGridIndex($pof.index,$pof.isAsk)
            $this.pendingCreateOffers = $this.pendingCreateOffers | Where-Object {$_.trigger_offer_id -ne $pof.trigger_offer_id}
            $this.save()
        }

    }

    [void] checkOffers(){
        $this.lastHandled = Get-Date
        if($this.isActive -and $this.isLoggedIn()){
            $actives = $this.activeOffers | Sort-Object {$_.index}
            foreach($active in $actives) {
                $offer = Get-SageOffer -offer_id $active.offer_id
                if($offer.status -eq "completed"){
                    $this.LastTradedAt = Get-Date
                    $this.updateLogOffer($active.offer_id,"completed")
                    
                    #remove this offer
                    $completed = @{
                        grid = $this.grid[($active.index)].($active.side)
                        offer_id = ($active.offer_id)
                    }

                    $this.completedOffers += $completed
                    $this.activeOffers = $this.activeOffers | Where-Object {$_.offer_id -ne $active.offer_id}
                    
                    # Determine Side of current offer
                    $isAsk = ($active.side -eq "ask") ? $true : $false
                    
                    # Flip side for new offer
                    $isAsk = (-not $isAsk)
                    $tmpside = ($isAsk) ? "ask" : "bid"

                    $this.pendingCreateOffers += @{                        
                        trigger_offer_id = $offer.offer_id
                        index = $active.index
                        side=$tmpside
                        grid = $this.grid[($active.index)].($tmpside)   
                        isAsk = $isAsk                                  
                    }    
                }
            }
            $this.save()
        }
    }

    static [array] All() {
        $tmp = [ChiaBot]::new()
        $path = $tmp.path()
        $files = Get-ChildItem -Path $path -Filter *.json -Recurse
        $bots = @()
        $files | ForEach-Object {
            $content = Get-Content -Path ($_.FullName) | ConvertFrom-Json
            $bots += [ChiaBot]::new($content)
        }
        return $bots
    }

    [void]addSteps($count){
        $this.addresses = (Get-SageDerivations -offset 0 -limit ($count*2)).derivations
        $this.steps = $count
        $this.save()
    }

    [void]refreshBalances(){
        if($this.isLoggedIn()){
            $this.offeredToken = Get-SageToken -id $this.offeredToken.asset_id
            $this.requestedToken = Get-SageToken -id $this.requestedToken.asset_id
        }
    }

    [PSCustomObject]stats(){
        $this.refreshBalances()
        
        $stats = [PSCustomObject]@{
            last_handled = $this.lastHandled
            last_traded_at = $this.LastTradedAt
            active_offers = $this.activeOffers.Count
            completed_offers = $this.completedOffers.Count
            pending_offers = $this.pendingCreateOffers.Count
            offered_token = $this.offeredToken.asset_id
            offered_token_balance = $this.offeredToken.balance
            requested_token = $this.requestedToken.asset_id
            requested_token_balance = $this.requestedToken.balance
        }
        return $stats
    }

    [array] getLog(){
        $path = $this.path()
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

    static [Array]AllStats(){
        $bots = [ChiaBot]::All()
        $allstats = @()
        foreach($bot in $bots){
            $stat = [PSCustomObject]@{
                'Name' = ($bot.name)
                'Offered Token' = ($bot.offeredToken.ticker)
                'Requested Token' = ($bot.requestedToken.ticker)
                'Is Active' = ($bot.isActive)
            }
            $allstats += $stat
        }
        return $allstats
    }

    [void] Init([PSCustomobject]$props)  {
        $this.id = $props.id
        $this.name = $props.name
        if($props.offeredToken){
            $this.offeredToken = Get-SageToken -id ($props.offeredToken.asset_id)
        }
        if($props.requestedToken){
            $this.requestedToken = Get-SageToken -id ($props.requestedToken.asset_id)
        }
        $this.startingPrice = $props.startingPrice
        $this.targetPrice = $props.targetPrice
        $this.steps = $props.steps
        $this.grid = $props.grid
        $this.activeOffers = $props.activeOffers
        $this.completedOffers = $props.completedOffers
        $this.fingerprint = $props.fingerprint
        $this.cancelledOffers = $props.cancelledOffers
        $this.feePercentage = $props.feePercentage
        $this.isActive = $props.isActive
        $this.isPrepped = $props.isPrepped
        $this.offeredTokenAmount = $props.offeredTokenAmount
        $this.isStableCoinPair = $props.isStableCoinPair
        $this.pendingCreateOffers = $props.pendingCreateOffers
        $this.addresses = $props.addresses
        $this.lastHandled = (Get-Date $props.lastHandled)
        $this.LastTradedAt = (Get-Date $props.LastTradedAt)
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
    
        
        $payments = Build-SageBulkPayments
        if($this.offeredToken.asset_id -eq 'xch' -and $this.offeredTokenAmount -gt 0){
            1..($this.steps) | ForEach-Object {
                $amt = ($this.offeredTokenAmount / $this.steps ) | ConvertTo-XchMojo
                $payments.addXchPayment($this.addresses[$_].address,$amt)
            }

        } elseif($this.offeredToken.asset_id -ne 'xch' -and $this.offeredTokenAmount -gt 0){
            $payments = Build-SageBulkPayments
            1..($this.steps) | ForEach-Object {
                $amt = ($this.offeredTokenAmount / $this.steps ) | ConvertTo-CatMojo
                $payments.addCatPayment($this.offeredToken.asset_id,$this.addresses[$_].address,$amt)
            }                        
        }

        $payments 
        pause
        $payments.submit()
        $array += ($payments.response )
        
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
        $file = Join-Path -Path $path -ChildPath "$($this.id).json"
        
        $check = Read-SpectreConfirm -Message "Are you sure you want to delete this bot?" -DefaultAnswer "n"
        
        if($check -eq $true){
            
                if(Test-Path -Path $file){
                    $this.CancelOffers()
                    Remove-Item -Path $file -Force
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

    [Array]getCoins($id,$amount){
        $endpoint = "get_coins"
        $json = @{
                ascending = $true
                filter_mode = 'selectable'
                offset = 0
                limit = 1000
                sort_mode = 'amount'
            }
        if($id -eq 'xch'){
            $json.add('asset_id', $null)
        } else {
            $json.add('asset_id',$id)
        }
        
        $coins = Invoke-SageRpc -endpoint $endpoint -json $json
        $possible_coins = ($coins.coins) | Where-Object {$_.amount -ge $amount}
        if($possible_coins.count -ge 1){
            return @($possible_coins[0].coin_id)
        } else {
            return @()
        }
    }

    [void]makeInitialOffers(){
        if($this.isLoggedIn() -and $this.activeOffers.Count -eq 0){
            $this.grid | ForEach-Object {
                $this.CreateOfferFromGridIndex($_.index,$false)
            }
        }
    }

    [void]CreateOfferFromGridIndex([UInt32]$index,[bool]$isAsk){
        
        if($isAsk -eq $true){
            $side = "ask"
        } else {
            $side = "bid"
        }
        
        $row = $this.grid | Where-Object {$_.index -eq $index}
        $buildData = $row.$side
        if($null -eq $buildData){
            Write-SpectreHost "[red]Failed to find data for bot[/]"
            return
        }
        $offer = Build-SageOffer
        $offer.coin_ids = $this.getCoins($buildData.offered_asset_id,$buildData.offered_asset_amount)
        
        ($buildData.requested_asset_id -eq "xch") ? $offer.requestXch($buildData.requested_asset_amount) : $offer.requestCat($buildData.requested_asset_id,$buildData.requested_asset_amount)
        ($buildData.offered_asset_id -eq "xch") ? $offer.offerXch($buildData.offered_asset_amount) : $offer.offerCat($buildData.offered_asset_id,$buildData.offered_asset_amount)
        ($this.transaction_fee -gt 0) ? $offer.setFee($this.transaction_fee) : $offer.setFee(0)
        $offer.setReceiveAddress($this.addresses[$index].address)
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
            $this.activeOffers += $active_offer
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
    
    CancelOffers(){
        try {
            if($this.isLoggedIn()){
            $this.activeOffers | ForEach-Object {
            
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
        # How much of Offered Token is applied to each run of the ladder
        $step_amount = $this.offeredTokenAmount / $this.steps

        # Amount to Increase/Decrease each time
        $step_size = ($this.targetPrice - $this.startingPrice) / ($this.steps-1)


        $invert = $false
        if($step_size -lt 0){
            $invert = $true
        }

        if($step_amount -eq 0 -OR $step_size -eq 0){
            throw "There are no steps"
        }

         if($this.isStableCoinPair){
            for ($i =0; $i -lt $this.steps; $i++){
                $tprice = 1                
                [UInt64]$offered_amount = (($step_amount * [System.Math]::Pow(10,($this.offeredToken.precision))))
                $fee_amount = [uint64]($offered_amount * $this.feePercentage)
                $row = [pscustomobject]@{
                    index = ($i)
                    price = [decimal]$tprice
                    fee_amount = $fee_amount
                    ask = [ordered]@{
                        requested_asset_id = $this.offeredToken.asset_id
                        requested_asset_amount = ($offered_amount + $fee_amount)
                        offered_asset_id = $this.requestedToken.asset_id
                        offered_asset_amount = $offered_amount
                    }
                    bid = [ordered]@{
                        requested_asset_id = $this.requestedToken.asset_id
                        requested_asset_amount = $offered_amount + $fee_amount
                        offered_asset_id = $this.offeredToken.asset_id
                        offered_asset_amount = $offered_amount
                    }
                }
                $this.grid += $row
            }
        } else {

            for ($i = 0; $i -lt $this.steps; $i++){



                if($invert){
                    $tPrice = [System.Math]::Round($this.targetPrice - ($step_size * $i),3)
                    [UInt64]$requested_amount = (($step_amount /$tprice)* [System.Math]::Pow(10,($this.requestedToken.precision)))
                } else {
                    $tPrice = [System.Math]::Round($this.startingPrice + ($step_size * $i),3)
                    [UInt64]$requested_amount = ($tPrice * $step_amount * [System.Math]::Pow(10,($this.requestedToken.precision)))
                }
                
                [UInt64]$offered_amount = (($step_amount * [System.Math]::Pow(10,($this.offeredToken.precision))))
                
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


function Show-HomeScreen{
    Clear-Host
    

}


$makeBot = $false
if($makeBot){

    $grid = [ChiaBot]::new()
    $grid.name = "Test Grid Bot"
    $grid.offeredToken = Get-SageToken -id xch
    $grid.requestedToken = Get-SageToken -id byc
    #$grid.isStableCoinPair = $true
    $grid.offeredTokenAmount = 20
    $grid.startingPrice = 2.50
    $grid.targetPrice = 2.70
    $grid.addSteps(20)
    $grid.fingerprint = 1763257157
    $grid.feePercentage = 0.003
    $grid.BuildGrid()
    $grid.save()
}
$bots = [ChiaBot]::All()
$bot = $bots[0]