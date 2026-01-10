
Class ChiaAsset {
    [string]$name
    [string]$id
    [Uint64]$denom
    [string]$tibet_liquidity_asset_id
    [string]$tibet_pair_id
    [string]$code
    [UInt64]$amount
    [decimal]$formatted_amount
    [Uint16]$fee_tenthousandths
    [UInt64]$fee_collected

    
    ChiaAsset(){}

    ChiaAsset([PSCustomobject]$props) {
        $this.Init([PSCustomObject]$props)
    }


    [ordered]makeRequestJson(){
        $amt = $this.amount + $this.fee_collected
        if($this.id -eq "xch"){
            $json = [ordered]@{
                xch = $amt
                cats= @()
                nfts = @()
            }    
        } else {
            $json = [ordered]@{
                xch = 0
                cats = @(
                    [ordered]@{
                        asset_id = ($this.id)
                        amount = $amt
                    }
                )
                nfts = @()
            }
        }
        
        return $json
    }

    [PSCustomObject]makeOfferJson(){
        $amt = $this.amount - $this.fee_collected
        if($this.id -eq "xch"){
            $json = [ordered]@{
                xch = $amt
                cats= @()
                nfts = @()
            }    
        } else {
            $json = [ordered]@{
                xch = 0
                cats = @(
                    [ordered]@{
                        asset_id = ($this.id)
                        amount = $amt
                    }
                )
                nfts = @()
            }
        }
        
        return $json
    }
    

    [ChiaAsset] Clone(){
        $clone = Get-ChiaAsset -id $this.id
        $clone.amount = $this.amount
        $clone.fee_tenthousandths = $this.fee_tenthousandths
        $clone.fee_collected = $this.fee_collected
        
        return $clone
    }



    [Quote] Quote(){
        if(
        ($null -eq $this.amount) -OR 
        ($this.amount -eq 0) -OR 
        ($null -eq $this.tibet_pair_id) -OR
        ($this.id -eq "XCH"))
        {
            return $null
        }

        return [Quote]::new((Get-DexieQuote -from ($this.id) -to xch -from_amount ($this.amount)).quote)
    }

    [void] Init([PSCustomobject]$props) {
        if(-not $null -eq $props.name){
            $this.name = $props.name
        }

        $this.id = $props.id
        $this.denom = [UInt64]$props.denom
        if(-not $null -eq $props.tibet_liquidity_asset_id){
            $this.tibet_liquidity_asset_id = $props.tibet_liquidity_asset_id
        }
        if(-not $null -eq $props.tibet_pair_id){
            $this.tibet_pair_id = $props.tibet_pair_id
        }
        $this.code = $props.code
        $this.fee_tenthousandths = $props.fee_tenthousandths
        $this.fee_collected = $props.fee_collected
        $this.formatted_amount = $props.formatted_amount
        $this.amount = $props.amount
        
    }

    [void] setFee([decimal]$fee){
        if($this.amount -ge 1){
            $this.fee_tenthousandths = $fee * 10000
            $this.fee_collected = [UInt64]($this.amount * $fee)
        } else {
            Write-SpectreHost -Message "[red]Cannot set fee for asset with amount less than 1.[/]"
        }
    }

    [void] addFeeToAmount(){
        $this.amount += $this.fee_collected
    }
    [void] removeFeeFromAmount(){
        $this.amount -= $this.fee_collected
    }

    [PSCustomObject] getDexieDetails(){
        $uri = "https://dexie.space/v1/assets?type=all&filter=$($this.id)"
        try{
            $response = Invoke-RestMethod -Uri $uri -Method Get 
            if($response -and $response.assets){
                return $response.assets | Where-Object { ($_.id -eq $this.id) -or ($_.code -eq $this.code) 
                }
            } else {
                Write-SpectreHost -Message "[red]No asset details found for ID: $($this.id)[/]"
                return $null
            }
        }
        catch {
            Write-SpectreHost -Message "[red]Failed to fetch asset details from Dexie: $($_.Exception.Message)[/]"
            return $null
        }
    }

    [void] setAmount([decimal]$amt){
        $this.amount = $amt * $this.denom
    }

    [void] setAmountFromMojo([UInt64]$mojo){
        $this.amount = $mojo
    }

    [PSCustomObject] getSimpleQuote() {
        
        if($this.id -eq "XCH"){
            return $null
        }
        $buy = Get-DexieQuote -from ($this.id) -to xch -to_amount 1000000000000
        $sell = Get-DexieQuote -from xch -to ($this.id) -from_amount 1000000000000

        $qbuy = [Quote]::new($buy.quote)
        $qsell = [Quote]::new($sell.quote)
        $avg_price = [Math]::Round(($qbuy.price + $qsell.price) / 2, 3)
        return [PSCustomObject]@{
            buy_quote = $qbuy
            sell_quote = $qsell
            avg_price = $avg_price
        }
    }

    [decimal] getFormattedAmount() {
        if($this.amount -eq 0){
            return 0
        }
        $this.formatted_amount = $this.amount / $this.denom
        return $this.formatted_amount
    }

    [UInt64] getBalance() {
        if($this.id -eq "XCH"){
            $xch = Get-SageSyncStatus
            return $xch.balance
        }
        $cat = (Get-SageCat -asset_id $this.id).token
        return $cat.balance
    }

    [decimal] getFormattedBalance() { 
        return ($this.getBalance()/$this.denom)
    }

    [bool] canCoverAmount() {
        $balance = $this.getBalance()
        if($null -eq $balance) {
            Write-SpectreHost -Message "[red]Failed to retrieve balance for asset ID: $($this.id)[/]"
            return $false
        }
        if($this.amount -gt $balance) {
            Write-SpectreHost -Message "[red]Insufficient balance for asset ID: $($this.id). Required: $($this.getFormattedAmount()), Available: $([decimal]$balance / $this.denom)[/]"
            return $false
        }
        return $true
    }

    [void]setAmountInteractive(){
        $max = $this.getFormattedBalance()
        [decimal]$amt = Read-SpectreText -Message "Enter the amount of $($this.code) you want use? (max: $($max))"
        if($this.code -eq "XCH"){
            $match = '^\d+(\.\d{1,12})?$'
            $message = "[red]Invalid amount. Please enter a valid number with up to 12 decimal places.[/]"
        } else {
            $match = '^\d+(\.\d{1,3})?$'
            $message = "[red]Invalid amount. Please enter a valid number with up to 3 decimal places.[/]"
        }
        if($amt -gt $max){
                $message = "
[red] Insufficient funds available Please enter an amount equal to or lower than $($max).[/]"
            }
        
        if($amt -match $match -and $amt -le $max){
            
            $this.setAmount([decimal]$amt)
            Write-SpectreHost -Message "[green]Amount set to $($this.getFormattedAmount()) $($this.name)[/]"
        } else {
            Write-SpectreHost -Message $message
            $this.setAmountInteractive()
        }
    }
    
    [Quote] getQuote(){
        $tmp_asset = Get-ChiaSwapAssets -asset_id $this.id
        if($null -eq $tmp_asset){
            Write-SpectreHost -Message "[red]Asset cannot be swapped at dexie[/]"
            return $null
        }
        return [Quote]::new((Get-DexieQuote -from $this.id -to xch -from_amount $this.amount))
    }
}


Class Quote {
    [ChiaAsset]$from
    [ChiaAsset]$to
    [UInt64]$suggested_tx_fee
    [UInt64]$combination_fee
    [decimal]$price
    [PSObject]$sageoffer
    [UInt64]$transaction_fee

    Quote(){}

    Quote([PSCustomObject]$Props){
        $this.Init([PSCustomObject]$Props)
    }


    Build(){
        $offer = Build-SageOffer
        if($this.from.id -eq "xch"){
            $offer.offerXch($this.from.amount)
            $offer.requestCat($this.to.id, $this.to.amount)
        } else {
            $offer.offerCat($this.from.id, $this.from.amount)
            $offer.requestXch($this.to.amount)
        }
        $this.sageoffer = $offer
    }

    [void] summary(){
        Write-SpectreHost -Message "
        [green]Quote Summary[/]
        From:               [red]$($this.from.getFormattedAmount())[/] - $($this.from.name)
        To:                 [green]$($this.to.getFormattedAmount())[/] - $($this.to.name)
        

        Price:              $($this.price)
        
        "
    }



    [void] Init([PSCustomobject]$props) {
    
        $this.from = (Get-ChiaAsset -id ($props.from))
        $this.from.setAmountFromMojo([UInt64]$props.from_amount)
        $this.to = (Get-ChiaAsset -id ($props.to))
        $this.to.setAmountFromMojo([UInt64]$props.to_amount)
        
        if($props.from -eq "XCH"){
            $this.price = [Math]::Round($this.to.getFormattedAmount() / $this.from.getFormattedAmount(),3)
        } else {
            $this.price = [Math]::Round($this.from.getFormattedAmount() / $this.to.getFormattedAmount(),3)
        }

        $this.suggested_tx_fee = [UInt64]$props.suggested_tx_fee
        $this.combination_fee = [UInt64]$props.combination_fee
        
    }
    
}



Class ChiaDCABot{
    [string]$id
    [string]$name
    [ChiaAsset]$offered_asset
    [ChiaAsset]$requested_asset
    [UInt64]$minutes_between_trades
    [decimal]$minimum_price
    [decimal]$maximum_price
    [UInt64]$max_token_spend
    [UInt64]$current_token_spend
    [bool]$active
    [datetime]$last_trade_time
    [datetime]$last_attemted_trade_time
    [datetime]$next_trade_time
    [array]$trade_history
    [uint64]$default_fee
    [uint64]$fingerprint
    

    ChiaDCABot(){
        $this.id = [Guid]::NewGuid().ToString()
        $this.last_attemted_trade_time = Get-Date
        $this.last_trade_time = Get-Date
        $this.next_trade_time = Get-Date
        $this.active = $false
        $this.trade_history = @()   
        $this.default_fee = 0    
        $this.current_token_spend = 0 
    }



    ChiaDCABot([PSCustomobject]$props) {$this.Init([PSCustomObject]$props)}

    [void] destroy(){
        $path = Get-SageTraderPath("DCABots")
        $path = Join-Path -Path $path -ChildPath "$($this.id).json"
        
        $check = Read-SpectreConfirm -Message "Are you sure you want to delete this bot?" -DefaultAnswer "n"
        if($check -eq $true){
            if(Test-Path -Path $path){
                Remove-Item -Path $path -Force
                Write-SpectreHost -Message "[green]Bot deleted successfully.[/]"
            } else {
                Write-SpectreHost -Message "[red]Bot not found.[/]"
            }
        } else {
            Write-SpectreHost -Message "[yellow]Bot deletion cancelled.[/]"
        }
    }

    [void] Init([PSCustomobject]$props)  {
        $this.id = $props.id
        $this.name = $props.name
        $this.offered_asset = [ChiaAsset]::new($props.offered_asset)
        $this.requested_asset = [ChiaAsset]::new($props.requested_asset)
        $this.minutes_between_trades = [UInt64]$props.minutes_between_trades
        $this.minimum_price = [decimal]$props.minimum_price
        $this.maximum_price = [decimal]$props.maximum_price
        $this.active = $props.active
        $this.last_trade_time = [datetime]::Parse($props.last_trade_time)
        $this.last_attemted_trade_time = [datetime]::Parse($props.last_attemted_trade_time)
        $this.next_trade_time = [datetime]::Parse($props.next_trade_time)
        $this.default_fee = [UInt64]$props.default_fee
        $this.fingerprint = [UInt64]$props.fingerprint
        $this.max_token_spend = [UInt64]$props.max_token_spend
        $this.current_token_spend = [UInt64]$props.current_token_spend
    }



    [Quote] GetQuote(){
        $quote = Get-DexieQuote -from $this.offered_asset.id -to $this.requested_asset.id -from_amount $this.offered_asset.amount
        if ($null -eq $quote) {
            Write-SpectreHost -Message "[red]Failed to get a quote. Please check your assets and try again.[/]"
            return $null
        }
        return [Quote]::new($($quote.quote))
    }

    [bool] hasValidBalance(){
        if($this.max_token_spend -gt 0){
            Write-SpectreHost -message "[green]Bot [/][blue]$($this.name)[/][green] has spent [/][Magenta2_1]$($this.current_token_spend) / $($this.max_token_spend)[/]."
        } else {
            Write-SpectreHost -message "[green]Bot [/][blue]$($this.name)[/][green] has spent [/][Magenta2_1]$($this.current_token_spend)[/]."
        }
        
        $ballance = $this.offered_asset.getBalance()
        if($ballance -lt $this.offered_asset.amount){
            Write-SpectreHost -Message "[red]Insufficient balance for bot[/][blue] $($this.name)[/][red]. You need at least [/][green]$($this.offered_asset.getFormattedAmount()) $($this.offered_asset.name)[/][red] to run this bot.[/]"
            return $false
        }

        if(($this.max_token_spend -ne 0) -and (($this.current_token_spend + $this.offered_asset.amount) -gt $this.max_token_spend)){
            Write-SpectreHost -Message "
            [red]Bot [/][blue]$($this.name)[/][red] has reached the maximum token spend of [/][green]$($this.max_token_spend)[/].
            [red]Disabling the bot.[/]"
            $this.deactivate()
            return $false
        }

        return $true
    }

    [bool] isLoggedIn(){
        $fp = (Invoke-SageRPC -endpoint get_key -json @{})
        if($null -eq $fp){
            Write-SpectreHost -Message "[red]Bot [/][blue]$($this.name)[/][red] does not have access to this wallet. 
            Please log in with the fingerprint: [/][blue]$($this.fingerprint)[/]"
            return $false
        }
        if($fp.key.fingerprint -eq $this.fingerprint){
            return $true
        }
        Write-SpectreHost -Message "
        [red]Bot [/][blue]$($this.name)[/][red] does not have access to this wallet. 
        Please log in with the fingerprint: [/][blue]$($this.fingerprint)[/]"
        return $false
    }

    [void] activate(){
        $this.active = $true
        $this.save()
    }

    [void] deactivate(){
        $this.active = $false
        $this.save()
    }

    [void] runNow(){
        $this.next_trade_time = Get-Date
        $this.Handle()
    }

    [void] login(){
        if(-not $this.isLoggedIn()){
            try{
                    Connect-SageFingerprint -fingerprint ($this.fingerprint)    
                
            }
            catch {
                Write-SpectreHost -Message "[red]Failed to connect to Sage with fingerprint $($this.fingerprint). Please check your Sage configuration.[/]"
                return
            }
        } else {
            Write-SpectreHost -Message "[green]Already logged in with fingerprint $($this.fingerprint).[/]"
        }
    }

    [bool] hasValidTradeTime(){
        $now = Get-Date
        
        if($this.next_trade_time -gt $now){
            Write-SpectreHost -Message "[yellow]Bot [/][blue]$($this.name)[/][yellow] is not ready to trade yet. Next trade time is $($this.next_trade_time).[/]"
            return $false
        }
        return $true
    }

        [void] showMenu(){
        $choice = 0
        do{
                Write-SpectreHost -message ($this.summary())

        Write-SpectreHost -Message "
[cyan]BOT MENU        
---------------------------------
1. $($this.active ? "[red]Deactivate Bot[/]" : "[green]Activate Bot[/]")
2. Destroy Bot

9. Back to main menu
[/]

Choose an option
        "
$choices = @(1,2,9)
$choice = Read-ValidMenu -choices $choices -message "Select an option:"

    switch ($choice) {
        1 {
            if ($this.active) {
                $this.deactivate()
                Write-SpectreHost -Message "[red]Bot [/][blue]$($this.name)[/] [red]is now deactivated.[/]"
                
            } else {
                $this.activate()
                Write-SpectreHost -Message "[green]Bot [/][blue]$($this.name)[/] [green]is now active.[/]"
                
            }
        }
        2 {
            $this.destroy()
        }
    }
    } until ($choice -eq "9")

    Show-Screen -name Home

}


    [void] Save(){
        $path = Get-SageTraderPath("DCABots")
        $file = Join-Path -Path $path -ChildPath "$($this.id).json"
        if(-not (Test-Path -Path $path)){
            New-Item -Path $path -ItemType Directory | Out-Null
        }
        
        $this | ConvertTo-Json -Depth 10 | Out-File -FilePath $file -Encoding utf8
    }

[string] summary(){
    $summary = @"
[green]Grid Bot Summary[/]
Name:                       $($this.name)
ID:                         $($this.id)
Requested Asset:            $($this.requested_asset.code) - $($this.requested_asset.getFormattedAmount())
Offered Asset:              $($this.offered_asset.code) - $($this.offered_asset.getFormattedAmount())
Minimum Price:              $($this.minimum_price)
Maximum Price:              $($this.maximum_price)
Minutes Between Trades:     $($this.minutes_between_trades)
Last Trade Time:            $($this.last_trade_time)
Last Attempted Trade Time:  $($this.last_attempted_trade_time)
Next Trade Time:            $($this.next_trade_time)
Max Token Spend:            $($this.max_token_spend)
Current Token Spend:        $($this.current_token_spend)

Active:                     $($this.active ? "[green]Yes[/]" : "[red]No[/]")
"@
        return $summary
    }


    [void] minisummary(){
        write-SpectreHost -Message "
        This BOT spend $($this.offered_asset.getFormattedAmount()) $($this.offered_asset.name) to buy $($this.requested_asset.name) every $($this.minutes_between_trades) minutes.

        "
        if($this.minimum_price -ne 0){
            Write-SpectreHost -Message "This BOT will only trade if the price is above [green]$($this.minimum_price)[/]."
        }
        if($this.maximum_price -ne 0){
            Write-SpectreHost -Message "This BOT will only trade if the price is below [red]$($this.maximum_price)[/]."
        }
    }

    [void] InitialSave(){
        $check = Read-Spectreconfirm -Message "Do you want to save this bot?" -DefaultAnswer "y"
        if($check -eq $true){
            $this.Save()
            Write-SpectreHost -Message "[green]Bot saved successfully.[/]"
        } else {
            Write-SpectreHost -Message "[yellow]Bot not saved.[/]"
        }
    }

    [bool] quoteIsValid([Quote]$quote){
        if($null-eq $quote){
            Write-SpectreHost -Message "[red]Quote is null. Cannot validate.[/]"
            return $false
        }
        if($quote.price -lt $this.minimum_price -and $this.minimum_price -ne 0){
            Write-SpectreHost -Message "[red]Quote price is below the minimum price of $($this.minimum_price).[/]"
            return $false
        }
        if($quote.price -gt $this.maximum_price -and $this.maximum_price -ne 0){
            Write-SpectreHost -Message "[red]Quote price is above the maximum price of $($this.maximum_price).[/]"
            return $false
        }
        return $true
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

    [bool] isActive(){
        if($this.active -eq $true){
            Write-SpectreHost -Message "[green]Bot [/][blue]$($this.name)[/][green] is active.[/]"
            return $true
        } else {
            Write-SpectreHost -Message "[red]Bot [/][blue]$($this.name)[/][red] is not active.[/]"
            return $false    
        }
        
    }
    

    [void] Handle(){
        
        
        if($this.isActive() -and $this.isLoggedIn() -and $this.hasValidBalance() -and $this.hasValidTradeTime()){
            Write-SpectreHost -Message "[green]Retrieving Quote for Bot [/][blue]$($this.name)[/][green][/]"
            $quote = $this.GetQuote()
            if($null -eq $quote){
                return
            }
            if(-not $this.quoteIsValid($quote)){
                Write-SpectreHost -Message "[red]Quote is not valid for this bot. Skipping trade.[/]"
                return
            }
            Write-SpectreHost -Message "[gray]
            Offered: [/][green] $($quote.from.getFormattedAmount()) [/][blue]$($quote.from.name)[/]
            [gray]Requested: [/][green] $($quote.to.getFormattedAmount()) [/][blue]$($quote.to.name)[/]
            [gray]Price: [/][green]$($quote.price) [/]
            "
            $quote.Build()
            if($null -eq $quote.sageoffer){
                Write-SpectreHost -Message "[red]Failed to build the offer. Please check your assets and try again.[/]"
                return
            }
            # Adding Default Fee
            $quote.sageoffer.fee = $this.default_fee
            # Create the offer in sage.
            $quote.sageoffer.createoffer()
            write-spectrehost -Message "[green]Offer created successfully.[/]"
            $dexie = Submit-DexieSwap -offer $quote.sageoffer.offer_data.offer
            if(-not $null -eq $dexie){
                Write-SpectreHost -Message "[green]Offer [/][blue] - $($dexie.id) - [/][green] submitted to Dexie successfully.[/]"
                $this.current_token_spend += $quote.from.amount
                $this.last_trade_time = Get-Date
                $this.next_trade_time = $this.last_trade_time.AddMinutes($this.minutes_between_trades)
                $this.last_attemted_trade_time = Get-Date
                $this.save()
            }

            $log = [PSCustomObject]@{
                offer_id = $quote.sageoffer.offer_data.offer_id    
                bot_type = $this.GetType().Name
                bot_id = $this.id
                offered_asset_id = $quote.from.code
                offered_asset_amount = [decimal]($quote.from.getFormattedAmount() * -1)
                requested_asset_id =  $quote.to.code
                requested_asset_amount = [decimal]($quote.to.getFormattedAmount())
                status = "pending"
                created_at = (Get-Date)
                updated_at = (Get-Date)
                fingerprint = $this.fingerprint
                dexie_id = ($dexie.id)
                }
                $this.logOffer($log)

        } 
    }

    [array] showLog(){
        $path = Get-SageTraderPath("offerlogs")
        $file = Join-Path -Path $path -ChildPath "$($this.id).csv"

        if(-not (Test-Path -Path $file)){
            Write-SpectreHost -Message "[red]No logs found for this bot.[/]"
            return @()
        }
        $log = Import-Csv -Path $file
        if($log.count -eq 0){
            Write-SpectreHost -Message "[red]No logs found for this bot.[/]"
            return @()
        }
        return $log
    }

    [void] logOffer($log){
        $path = Get-SageTraderPath("offerlogs")
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
}


function Get-SageTraderPath() {
    [CmdletBinding()]
    param(
        [string]$subfolder = $null
    )
    <#
    .SYNOPSIS
    Get the path to the SageTrader folder.
    
    .DESCRIPTION
    Returns the path to the SageTrader folder, optionally including a subfolder.
    
    .PARAMETER subfolder
    The subfolder to include in the path. If not specified, returns the main SageTrader folder.
    
    .EXAMPLE
    Get-SageTraderPath -subfolder "DCABots"
    
    Returns the path to the DCABots subfolder within the SageTrader folder.
    
    #>
    
    if($isWindows){
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

    if($IsLinux){
        if(-not (Test-Path -Path "$HOME/.local/share/SageTrader")){
            New-Item -Path "$HOME/.local/share/SageTrader" -ItemType Directory | Out-Null
        }
        if($null -eq $subfolder){
            return "$HOME/.local/share/SageTrader"
        }
        if(-not (Test-Path -Path "$HOME/.local/share/SageTrader/$subfolder")){
            New-Item -Path "$HOME/.local/share/SageTrader/$subfolder" -ItemType Directory | Out-Null
        }
        return "$HOME/.local/share/SageTrader/$subfolder"
    }
    if($IsMacOS){
        if(-not (Test-Path -Path "$HOME/Library/Application Support/SageTrader")){
            New-Item -Path "$HOME/Library/Application Support/SageTrader" -ItemType Directory | Out-Null
        }
        if($null -eq $subfolder){
            return "$HOME/Library/Application Support/SageTrader"
        }
        if(-not (Test-Path -Path "$HOME/Library/Application Support/SageTrader/$subfolder")){
            New-Item -Path "$HOME/Library/Application Support/SageTrader/$subfolder" -ItemType Directory | Out-Null
        }
        return "$HOME/Library/Application Support/SageTrader/$subfolder"
    }

    
}

function Get-ChiaAsset {
    <#
    .SYNOPSIS
    Get a specific Chia Asset by code or id.
    .DESCRIPTION
    Retrieves a specific Chia Asset by its code or id.
    .PARAMETER id
    This can be either the code or the id of the asset.
    .EXAMPLE
    Get-ChiaAsset -Code "XCH"
    Retrieves the Chia Asset with the code "XCH".

    .EXAMPLE
    Get-ChiaAsset -Id "fa4a180ac326e67ea289b869e3448256f6af05721f7cf934cb9901baa6b7a99d"

    Retrieves the Chia Asset with the specified id ().
    .NOTES
    This function retrieves a Chia Asset from the local assets.json file.
    


    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [string]$id
    )

    $assets = Get-ChiaAssets
    return $assets | Where-Object { $_.id -eq $id -or $_.code -eq $id }
}

function Sync-ChiaAssets{
    
    $path = Get-SageTraderPath
    $file = Join-Path -Path $path -ChildPath "assets.json"


    $page = 1
    $assets = Get-DexieAssets -page_size 100 -page $page -cats
    $tokens = @()
    $pairs = Invoke-RestMethod -uri "https://api.v2.tibetswap.io/pairs?skip=0&limit=10000" -Method Get
    $xch = @{}
    $xch.name = "XCH"
    $xch.code = "XCH"
    $xch.id = "xch"
    $xch.denom = 1000000000000
    
    $assetarray = @()
    $assetarray += @($xch)

    
    while ($tokens.count -lt $assets.count){
        foreach ($asset in $assets.assets){
            $token= @{}
            $token.name = $asset.name
            $token.code = $asset.code
            $token.id = $asset.id
            $token.denom = $asset.denom
            $pair = $pairs | Where-Object { $_.asset_id -eq $asset.id}
            if($pair){
                $token.tibet_pair_id = $pair.launcher_id
                $token.tibet_liquidity_asset_id = $pair.liquidity_asset_id
            }
            $assetarray += @($token)
        }
        
        $page++
        $assets = Get-DexieAssets -page_size 100 -page $page -cats
    }
    $byc_test = $assetarray | Where-Object {$_.code -eq 'BYC'}
    if(-NOT $byc_test){
        $byc = @{
            name = "Bytecash"
            code = "BYC"
            id = "ae1536f56760e471ad85ead45f00d680ff9cca73b8cc3407be778f1c0c606eac"
            denom = 1000
            
        }
        $pair = $pairs | Where-Object { $_.asset_id -eq $byc.id}
        if($pair){
            $byc.tibet_pair_id = $pair.launcher_id
            $byc.tibet_liquidity_asset_id = $pair.liquidity_asset_id
        }
        $assetarray += $byc
    }
    $assetarray | ConvertTo-Json -Depth 10 | Out-File -FilePath $file -Encoding utf8

}

function Get-ChiaAssets {
    <#
    .SYNOPSIS
    Get a list of all Chia Assets.
    
    .DESCRIPTION
    Gets an array of all Chia Assets.     
    .EXAMPLE
    Get-ChiaAssets
    
    Retrieves and displays the list of Chia assets.
    
    
    #>
    $path = Get-SageTraderPath
    $file = Join-Path -Path $path -ChildPath "assets.json"
    
    if(-not (Test-Path -Path $file)){
        Sync-ChiaAssets
    }
    
    
    $assets = Get-Content -Path $file | ConvertFrom-Json
    $assetList = @()
    Foreach ($asset in $assets){
        $asset = [ChiaAsset]::new($asset)
        $assetList += $asset
    }

    return $assetList
}

function Sync-ChiaSwapAssets {
    <#
    .SYNOPSIS
    Sync Chia Swap Assets.
    
    .DESCRIPTION
    This function syncs the Chia Swap assets by fetching them from the API and saving them to a local file.
    
    .EXAMPLE
    Sync-ChiaSwapAssets
    
    Syncs the Chia Swap assets and saves them to a local file.
    
    #>
    $path = Get-SageTraderPath
    $file = Join-Path -Path $path -ChildPath "swapassets.json"
   
    Write-SpectreHost -Message "[green]Syncing Chia Swap Assets...[/]"

    
    $uri = 'https://api.dexie.space/v1/swap/tokens'

    $response = Invoke-RestMethod -Uri $uri -Method Get
    if ($response -and $response.tokens) {
        $tokens = $response.tokens 
        $tokens | ConvertTo-Json -Depth 10 | Out-File -FilePath $file -Encoding utf8
    } else {
        Write-Host "Failed to retrieve Chia Swap assets."
    } 
}

function Get-ChiaSwapAssets {
    <#
    .SYNOPSIS
    Get a list of all Chia Swap Assets.
    
    .DESCRIPTION
    Gets an array of all Chia Swap Assets.     
    .EXAMPLE
    Get-ChiaSwapAssets
    
    Retrieves and displays the list of Chia Swap assets.
    
    
    #>
    $path = Get-SageTraderPath
    $file = Join-Path -Path $path -ChildPath "swapassets.json"
    if(-not (Test-Path -Path $file)){
        Sync-ChiaSwapAssets
    }

    
    $assets = Get-Content -Path $file | ConvertFrom-Json
    $assetList = @()
    Foreach ($asset in $assets){
        $assetObj = [ChiaAsset]::new($asset)
        $assetList += $assetObj
    }

    return $assetList
}

function New-ChiaBot {
    do{
    Clear-Host
    Write-SpectreFigletText -Text "Create a New Chia Bot" -Color green Center
    
    Write-SpectreHost -message "
What type of bot do you want to create?

1. Dollar Cost Averaging
2. Grid Trading

9. Back to main menu
    "

$choice = Read-ValidMenu -choices @(1,2,9) -message "Select a bot type:"


    switch ($choice) {
        1 {
            New-ChiaDCABot
            $choice = 9 # Exit the loop after creating a DCA bot
        }
        2 {
            New-ChiaGridBot
            $choice = 9 # Exit the loop after creating a Grid Trading bot
        }
        
    }
} while ($choice -ne 9)
    Show-Screen -name Home
}

function Select-ChiaBotAnswer{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [string]$bot
    )
    switch ($bot) {
        "Dollar Cost Averaging" {
            New-ChiaDCABot
        }
        "Grid Trading" {
            New-ChiaGridBot
        }
        default {
            Write-Host "Invalid selection. Please choose a valid bot type."
        }
    }
    pause
}



function New-ChiaDCABot{
    $bot = [ChiaDCABot]::new()
    $direction_choice = ''
    Clear-Host
    Write-SpectreFigletText -Text "New DCA Bot" -Color green Center
    Write-SpectreHost -Message "Select enter the asset you want to Dollar Cost Average.
    
    "
    $asset = Select-ChiaSwapAsset
    $direction = Read-SpectreSelection -Message "Do you want to [green]BUY = (Offer: XCH -- Request: $($asset.code))[/] or [red]SELL = (Offer: $($asset.code) - - Request: XCH)[/] this $($asset.name)?" -Choices @("[green]Buy[/]", "[red]Sell[/]") 
    if ($direction -eq "[green]Buy[/]") {
        $direction_choice = 'buy'
        $requested_asset = $asset
        $offered_asset = (Get-ChiaAsset -id "xch")
    } else {
        $direction_choice = 'sell'
        $requested_asset = (Get-ChiaAsset -id "xch")
        $offered_asset = $asset
    }
    

    $amount = Read-SpectreText -Message "How much $($($offered_asset).name) do you want to spend each time?" -DefaultAnswer "0.1"
    $offered_asset.setAmount([decimal]$amount)
    
    $bot.offered_asset = $offered_asset
    $bot.requested_asset = $requested_asset



    $quote = Get-DexieQuote -from $offered_asset.id -to $requested_asset.id -from_amount $offered_asset.amount
    if ($null -eq $quote) {
        Write-SpectreHost -Message "[red]Failed to get a quote. Please check your assets and try again.[/]"
        return
    }
    $dexie_quote = [Quote]::new($($quote.quote))
    Clear-Host
    Write-SpectreHost -Message "The current price for [blue]$($offered_asset.name)[/] to [blue]$($requested_asset.name)[/] is [green]$($dexie_quote.price)[/].
    "
    $restrict = Read-SpectreConfirm -Message "Do you want to restrict this bot to a specific price range?" -DefaultAnswer "n"
    if($restrict -eq $true){
        Write-SpectreHost -Message "
        You are $($direction_choice)ing [blue]$($offered_asset.getFormattedAmount()) $($offered_asset.code)[/] for [blue]$($requested_asset.code)[/].

        If buying (receive CAT), you want to set a [red]minimum price[/].
        [gray]Example: If the price is 10 wUSDC.b/XCH, you want to sent a minimum of 10.0 so you don't send XCH when you don't receive as much CAT.[/]
        
        If selling (sending CAT), you want to set a [green]maximum price[/]
        [gray]Example: If the price is 10 wUSDC.b/XCH, you want to set a maximum of 10.0 so you don't send more CAT when you don't receive as much XCH.[/]

        THE CURRENT PRICE IS [green]$($dexie_quote.price)[/].
        "
        if($direction_choice -eq 'buy'){
            $bot.minimum_price = Get-MinPrice
            $bot.maximum_price = 0
        } else {
            $bot.minimum_price = 0
            $bot.maximum_price = Get-MaxPrice
        }
        
    } 

    $max_spend = Get-MaxTokenSpend -asset $offered_asset
    if ($max_spend -gt 0) {
        $bot.max_token_spend = $max_spend
        Write-SpectreHost -Message "This bot will not spend more than [purple]$($max_spend / $offered_asset.denom)[/] $($offered_asset.name) in total."
    } else {
        $bot.max_token_spend = 0
        Write-SpectreHost -Message "This bot will spend [purple]unlimited[/] $($offered_asset.name)."
    }

    $bot.minutes_between_trades = Get-MinutesBetweenTrades
    Clear-Host
    $bot.minisummary()
    $bot.name = Read-SpectreText -Message "What do you want to name this bot?" -DefaultAnswer "My DCA Bot"
    $bot.default_fee = Get-ChiaDefaultFee
    $bot.fingerprint = Get-ChiaFingerprint
    $bot.InitialSave()
    $act = Read-SpectreConfirm -Message "Do you want to activate this bot now?" -DefaultAnswer "y"
    if($act -eq $true){
        $bot.activate()
        Write-SpectreHost -Message "[green]Bot [/][blue]$($bot.name)[/] [green]is now active.[/]"
    } else {
        Write-SpectreHost -Message "[yellow]Bot [/][blue]$($bot.name)[/] [yellow]is not active. You can activate it later.[/]"
    }
    
}


function Get-ChiaFingerprint {
    $fingerprints = (Get-SageKeys).keys

    $fingerprint = Read-SpectreSelection -Message "Authorize Bot to access specific fingerprint." -Choices ($fingerprints.name) -EnableSearch -SearchHighlightColor purple
    return ($fingerprints | Where-Object { $_.name -eq $fingerprint }).fingerprint
}



function Connect-ChiaFingerprint {
    $fingerprints = (Get-SageKeys).keys

    $fingerprint = Read-SpectreSelection -Message "Select which wallet to log into." -Choices ($fingerprints.name) -EnableSearch -SearchHighlightColor purple
    $selected_fingerprint = ($fingerprints | Where-Object { $_.name -eq $fingerprint }).fingerprint
    if ($null -eq $selected_fingerprint) {
        Write-SpectreHost -Message "[red]No fingerprint selected. Please try again.[/]"
        return Connect-ChiaFingerprint
    }
    try {
        Connect-SageFingerprint -fingerprint $selected_fingerprint
        Write-SpectreHost -Message "[green]Successfully connected to fingerprint $selected_fingerprint.[/]"
    } catch {
        Write-SpectreHost -Message "[red]Failed to connect to fingerprint $selected_fingerprint. Please check your Sage configuration.[/]"
    }
}

function Format-ChiaAssetBalance {
    Get-SageBalances
}

function Get-SageBalances{
    param(
        [switch]$cats_only
    )
    $data = @()
    if(-not $cats_only.IsPresent){
         $xch = Get-SageSyncStatus
        if ($xch -and $xch.balance) {
            $xch_balance = [decimal]($xch.balance / 1000000000000)
            $data += [pscustomobject]@{
                Image = "https://icons.dexie.space/xch.webp"
                Asset = "XCH"
                Balance = $xch_balance
            }
        } 
    }
   
    $cats = (Get-SageCats).cats | Sort-Object -Property balance -Descending
    if ($cats -and $cats.Count -gt 0) {
        foreach ($cat in $cats) {
            if($cat.balance -gt 0) {
                $balance = [decimal]($cat.balance / 1000)
                $data += [pscustomobject]@{
                    Image = ($cat.icon_url)
                    Asset = $cat.ticker
                    Balance = $balance
                }
            } 
            
        }
    }
    return $data
}

function Show-SageBalanceTable{
    $fp = (Get-SageKey).key
    Get-SageBalances | Select-Object -Property Asset, Balance | Out-ConsoleGridView -Title "Sage Assets for fingerprint: $($fp.fingerprint)" -OutputMode Single
    
}

function Get-ChiaDefaultFee{
    $asset = Get-ChiaAsset -id "xch"
    [decimal]$fee = Get-SpectreNumber -Message "What is the default fee for this bot? (0 for no fee)" -DefaultAnswer "0.00005" -numberOfDecimals 12
    
    if ($fee -match '^\d+(\.\d{1,12})?$') {
        if($fee -gt 0.1){
            $confirm = Read-SpectreConfirm -Message "You are setting a high fee of $fee XCH. Are you sure you want to continue?" -DefaultAnswer "n"
            if($confirm -eq $false){
                return Get-ChiaDefaultFee
            }
        
        }
        
    } else {
        Write-SpectreHost -Message "[red]Invalid input. Please enter a valid number.[/]"
        return Get-ChiaDefaultFee 
    }
    return $asset.denom * $fee
}

function Get-MinutesBetweenTrades {

    $minutes = Read-SpectreText -Message "How many [blue]minutes[/] between trades?" 
    if ($minutes -match '^\d+$') {
        return [int]$minutes
    } else {
        Write-SpectreHost -Message "[red]Invalid input. Please enter a valid number.[/]"
        return Get-MinutesBetweenTrades 
    }
}

function Get-MaxTokenSpend {
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ChiaAsset]$asset
    )
    $max_spend = Read-SpectreText -Message "What is the maximum [blue]$($asset.code)[/] this bot can spend in total? (0 for no limit)" -DefaultAnswer "0"
    if ($max_spend -match '^\d+(\.\d{1,12})?$') {
        return ([UInt64]$max_spend * $asset.denom)
    } else {
        Write-SpectreHost -Message "[red]Invalid input. Please enter a valid number.[/]"
        return Get-MaxTokenSpend 
    }
}

function Get-MinPrice {
    $min_price = Read-SpectreText -Message "What is the [red]minimum price[/] you are willing to accept for this trade?" -AllowEmpty 
    if ($min_price -eq '') {
        return 0
    }
    if ($min_price -match '^\d+(\.\d{1,3})?$') {
        return [decimal]$min_price
    } else {
        Write-SpectreHost -Message "[red]Invalid input. Please enter a valid number.[/]"
        return Get-MinPrice 
    }
}

function Get-MaxPrice {
    $max_price = Read-SpectreText -Message "What is the [green]maximum price[/] you are willing to pay for this trade?" -AllowEmpty 
    if ($max_price -eq '') {
        return 0
    }
    if ($max_price -match '^\d+(\.\d{1,3})?$') {
        return [decimal]$max_price
    } else {
        Write-SpectreHost -Message "[red]Invalid input. Please enter a valid number.[/]"
        return Get-MaxPrice 
    }
}

function Get-XCHInput {
    $xch = Read-SpectreText -Message "How much [purple]XCH[/] do you want to spend per trade?" -DefaultAnswer "0.1"
    if ($xch -match '^\d+(\.\d{1,12})?$') {
        return [decimal]$xch
    } else {
        Write-SpectreHost -Message "[red]Invalid input. Please enter a valid number.[/]"
        return Get-XCHInput
    }
}

function Select-ChiaSwapAsset {
    $assets = Get-ChiaSwapAssets
    
    $result = Read-SpectreSelection -Message "Select a [purple]Chia Asset[/]" -Choices ($assets.code ) -EnableSearch -SearchHighlightColor purple
    $asset = Get-ChiaAsset -id $result
    return $asset
}

function Get-ChiaBots {
    $bots = @()
    $dcabots = Get-ChiaDCABots
    $gridbots = Get-ChiaGridbots
    
    $dcabots | ForEach-Object {$bots += $_}
    $gridbots | ForEach-Object {$bots += $_}

    

    return $bots
}
   
function Get-ChiaDCABots {
    $bots = @()
    
    $path = Get-SageTraderPath("DCABots")
    if(-not (Test-Path -Path $path)){
        
        return
    }
    $files = Get-ChildItem -Path $path -Filter "*.json"
    if($files.Count -eq 0){
        
        return
    }
    foreach ($file in $files) {
        $bot = Get-Content -Path $file.FullName | ConvertFrom-Json
        $bots += [ChiaDCABot]::new($bot)
    }
    return $bots
}

function Get-ChiaGridbots(){
    $bots = @()
    $path = Get-SageTraderPath("GridBots")
    if(-not (Test-Path -Path $path)){
        
        return
    }
    $files = Get-ChildItem -Path $path -Filter "*.json"
    if($files.Count -eq 0){
        return
    }
    foreach ($file in $files) {
        $bot = Get-Content -Path $file.FullName | ConvertFrom-Json
        $bots += [GridBot]::new($bot)
    }
    return $bots

}

function Get-ChiaOfferLog {
    <#
    .SYNOPSIS
    Get the Chia Offer Log.

    .DESCRIPTION
    Retrieves the Chia Offer Log from the local file.

    .EXAMPLE
    Get-ChiaOfferLog

    Retrieves and displays the Chia Offer Log.
    #>
    $path = Get-SageTraderPath("offerlogs")
    $file = Join-Path -Path $path -ChildPath "offers.csv"


    if(-not (Test-Path -Path $file)){
        Write-SpectreHost -Message "[red]No offer logs found.[/]"
        return @()
    }
    
    return Import-Csv -Path $file
}

function Update-ChiaOfferLog {
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [array]$logs
    )

}

function New-ChiaOfferLog{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [string]$bot_type,
        [Parameter(Mandatory = $true, Position = 1, ValueFromPipeline = $true)]
        [string]$bot_id,
        [Parameter(Mandatory = $true, Position = 2, ValueFromPipeline = $true)]
        [string]$offered_asset_id,
        [Parameter(Mandatory = $true, Position = 3, ValueFromPipeline = $true)]
        [Int128]$offered_asset_amount,
        [Parameter(Mandatory = $true, Position = 4, ValueFromPipeline = $true)]
        [string]$requested_asset_id,   
        [Parameter(Mandatory = $true, Position = 5, ValueFromPipeline = $true)]
        [Int128]$requested_asset_amount,
        [Parameter(Mandatory = $true, Position = 6, ValueFromPipeline = $true)]
        [string]$status,
        [Parameter(Mandatory = $true, Position = 7, ValueFromPipeline = $true)]
        [datetime]$created_at,
        [Parameter(Mandatory = $true, Position = 8, ValueFromPipeline = $true)]
        [datetime]$updated_at,
        [Parameter(Mandatory = $true, Position = 9, ValueFromPipeline = $true)]
        [string]$offer_id,
        [Parameter(Mandatory = $true, Position = 10, ValueFromPipeline = $true)]
        [string]$fingerprint,
        [Parameter(Mandatory = $true, Position = 11, ValueFromPipeline = $true)]
        [string]$dexie_id
    )

    $log = [PSCustomObject]@{
        bot_type = $bot_type
        bot_id = $bot_id
        offered_asset_id = $offered_asset_id
        offered_asset_amount = $offered_asset_amount
        requested_asset_id = $requested_asset_id
        requested_asset_amount = $requested_asset_amount
        status = $status
        created_at = $created_at
        updated_at = $updated_at
        offer_id = $offer_id
        fingerprint = $fingerprint
        dexie_id = $dexie_id
    }
    $path = Get-SageTraderPath("offerlogs")
    $file = Join-Path -Path $path -ChildPath "offers.csv"
    
    if(-not (Test-Path -Path $file)){
        $log | Export-Csv -Path $file -NoTypeInformation
    } else {
        $log | Export-Csv -Path $file -NoTypeInformation -Append
    }

}

function Start-Bots {
    $choice = 0
    do{
        Write-SpectreHost -Message "[purple] $(Get-Date) [/]"
        Write-SpectreRule -Color purple
        $bots = Get-ChiaBots
        if($null -eq $bots){
            Write-SpectreHost -Message "[red]No bots found.[/]"
            pause
            return
        }
        foreach ($bot in $bots) {
            Write-Information "Starting bot: $($bot.name)"
            $bot.Handle()
        }
        Write-SpectreHost -Message "[green]All bots have been processed. Waiting for the next cycle...[/]"
        Write-SpectreRule -Color purple
        $choice = Read-SpectreText -Message "To exit, press [red]Q ↲ [/]" -TimeoutSeconds 60
    } until ($choice -eq 'Q' -or $choice -eq 'q')
    Start-SageTrader
}


function Get-SageTraderConfig{
    $path = Get-SageTraderPath -subfolder config
    $file = Join-Path -Path $path -ChildPath "config.json"
    if(-not (Test-Path -Path $file)){
        $config = [PSCustomObject]@{
             colors = @{
                default = "cornsilk1"
                info = "aqua"
                warning = "yellow2"
                danger = "maroon"
                primary = "dodgerblue3"
             }
        } | ConvertTo-Json -Depth 20 | Out-File -FilePath $file
    } 
    $config = Get-Content -Path $file | ConvertFrom-Json 
    return $config
}






function Read-ValidMenu{
    param(
        [Int16[]]$choices,
        [string]$message
    )
    $choice = Read-SpectreText -Message $message
    if($null -ne ($choice -as [int16])){
        if([Int16]$choice -in $choices){
            return [Int16]$choice
        }
    }
    
    Read-ValidMenu -choices $choices -message $message
}



function Get-ChiaBot{
    param($name)
    $bots = Get-ChiaBots
    if ($null -eq $bots) {
        Write-SpectreHost -Message "[red]No Chia bots found.[/]"
        return $null
    }
    $bot = $bots | Where-Object { $_.name -eq $name -or $_.id -eq $name }
    if ($null -eq $bot) {
        Write-SpectreHost -Message "[red]Bot with name '$name' not found.[/]"
        return $null
    }
    return $bot
}

function Test-SageRunning(){
    try{
        Test-SageRPC
    } catch {
        Write-SpectreHost -Message "[red]Sage RPC is not running. Please start Sage first.[/]"
        return $false
    }
}

function Start-SageTrader{
    if(-not (Get-SagePfxCertificate)){
        New-SagePfxCertificate
    }

    Show-Screen -name Home
    
}

function Start-MarketOrder {
        do{
        Clear-Host
        $fp = (Get-SageKey).fingerprint
        Write-SpectreFigletText -Text "Market Orders" -Color "darkseagreen" 
        Write-SpectreRule -LineColor green -Title "[green]Fingerprint: [/]$($fp)" -Alignment Center

    Write-SpectreHost -Message "

1. Sell CAT for XCH
2. Buy CAT with XCH

9. Back to main menu

        "
        $choices = @(1,2,9)
        $choice = Read-ValidMenu -choices $choices -message "Select an option:"
        
        switch ($choice) {
            1 { Start-CatSellForXCH 
                $choice = 9 # Exit the loop after selling CAT for XCH}

            }
            2 { Start-CatBuyWithXCH
                $choice = 9 # Exit the loop after buying CAT with XCH
            }
            9 { Show-Screen -name Home }
            default { Write-SpectreHost -Message "[red]Invalid choice. Please try again.[/]" }
        }
    } while ($choice -ne 9)
    Clear-Host
}

function Start-CatBuyWithXCH {
    Clear-Host
    $myCats = Get-ChiaSwapAssets | Select-Object -Property @{Name="Asset";Expression={$_.code}}, name | Out-ConsoleGridView -Title "Select an Asset to Buy" -OutputMode Single
    if ($null -eq $myCats) {
        Write-SpectreHost -Message "[red]No assets found. Please create a CAT first.[/]"
        Pause
        return
    }
    $method = @(
        [pscustomobject]@{Name="Spend a fixed amount of XCH"; Value="fixed"},
        [pscustomobject]@{Name="Acquire a specific amount of CAT"; Value="specific"}
    ) | Out-ConsoleGridView -Title "Select a Method" -OutputMode Single

    if($method.Value -eq "fixed"){
        $xch = Get-ChiaAsset -id "xch"
        $amount = Get-SpectreNumber -message "How much [green]XCH[/] do you want to [red]Spend[/] to buy $($myCats.name)? (max: $($xch.getFormattedBalance()))" -numberOfDecimals 3
        if ($amount -le 0) {
            Write-SpectreHost -Message "[yellow]Cancelling the Buy.[/]"
            Pause
            return
        }
        $asset = Get-ChiaAsset -id $myCats.Asset
        
        $quote = Get-DexieQuote -from "xch" -to ($asset.id) -from_amount ($xch.denom * $amount)
    } else {
        $amount = Get-SpectreNumber -message "How much [purple]$($myCats.Asset)[/] do you want to buy?" -numberOfDecimals 3
        if ($amount -le 0) {
            Write-SpectreHost -Message "[yellow]Cancelling the Buy.[/]"
            Pause
            return
        }
        $asset = Get-ChiaAsset -id $myCats.Asset
        $quote = Get-DexieQuote -from "xch" -to $asset.id -to_amount ($asset.denom * $amount)
    }
    

    if ($null -eq $quote) {
        Write-SpectreHost -Message "[red]Failed to get a quote. Please check your assets and try again.[/]"
        return
    }
    $dexie_quote = [Quote]::new($($quote.quote))
    $dexie_quote.summary()
    $confirm = Read-SpectreConfirm -Message "Do you want to spend [purple]$($dexie_quote.from.getFormattedAmount())[/] [purple]$($dexie_quote.from.code)[/] for [green]$($dexie_quote.to.getFormattedAmount()) $($dexie_quote.to.code)[/] ?" -DefaultAnswer "n"

    if ($confirm -eq $true){
        Write-SpectreHost -message "Building Offer..."
        $dexie_quote.Build()
        Write-SpectreHost -Message "Submitting to Dexie..."
         $dexie_quote.sageoffer.createoffer()

        $submit = Submit-DexieSwap -offer $dexie_quote.sageoffer.offer_data.offer
        if($submit){
            Write-SpectreHost -Message "[green]Offer submitted successfully![/]"
            Write-SpectreHost -Message "[green]Offer ID: https://dexie.space/offers/$($submit.id)[/]"
            Pause
        }
    } else {
        Write-SpectreHost -Message "[yellow]Cancelled the Buy.[/]"
        Pause
        return
    }
}

function Start-CatSellForXCH {
    Clear-Host
    $myCats = Get-SageBalances -cats_only | Select-Object -Property Asset, Balance | Out-ConsoleGridView -Title "Select an Asset to Sell" -OutputMode Single
    if ($null -eq $myCats) {
        Write-SpectreHost -Message "[red]No assets found. Please create a CAT first.[/]"
        Pause
        return
    }
    $amount = Get-SpectreNumber -message "How much [purple]$($myCats.Asset)[/] do you want to sell? (max: $($myCats.Balance))" -numberOfDecimals 3
 
    if ($amount -le 0) {
        Write-SpectreHost -Message "[yellow]Cancelling the Sell.[/]"
        Pause
        return
    }
    $asset = Get-ChiaAsset -id $myCats.Asset
    $quote = Get-DexieQuote -from $asset.id -to "xch" -from_amount ($asset.denom * $amount)
    if ($null -eq $quote) {
        Write-SpectreHost -Message "[red]Failed to get a quote. Please check your assets and try again.[/]"
        return
    }
    $dexie_quote = [Quote]::new($($quote.quote))
    $dexie_quote.summary()
    $confirm = Read-SpectreConfirm -Message "Do you want to sell [purple]$($amount)[/] [purple]$($asset.code)[/] for [green]$($dexie_quote.to.getFormattedAmount())[/] XCH?" -DefaultAnswer "n"
    if ($confirm -eq $true){
        Write-SpectreHost -message "Building Offer..."
        $dexie_quote.Build()
        Write-SpectreHost -Message "Submitting to Dexie..."
        $dexie_quote.sageoffer.createoffer()

        $submit = Submit-DexieSwap -offer $dexie_quote.sageoffer.offer_data.offer
        if($submit){
            Write-SpectreHost -Message "[green]Offer submitted successfully![/]"
            Write-SpectreHost -Message "[green]Offer ID: https://dexie.space/offers/$($submit.id)[/]"
            Pause
        }
    } else {
        Write-SpectreHost -Message "[yellow]Cancelled the Sell.[/]"
        Pause
        return
    }
}



function Show-Bots{
    
    $bots = Get-ChiaBots
    if ($null -eq $bots) {
        Write-SpectreHost -Message "[yellow]No bots found.  Please Create a bot first.[/]"
        Pause
        return
    }
    $display = @()
    $bots | ForEach-Object {
        $disp = [PSCustomObject]@{
            type = ($_.GetType().Name)
            name = ($_.name)
            active = ($_.active)
            id = ($_.id)
        }
        $display += $disp
    }
    $display | Out-ConsoleGridView -Title Bots -OutputMode Single | Show-BotMenu
}

function Show-BotMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        $selection
    )
    Clear-Host
    $bot = Get-ChiaBot -name ($selection.id)
    if ($null -eq $bot) {
        Write-SpectreHost -Message "[red]Bot not found.[/]"
        return
    }
    $bot.showMenu()
    
}

function New-ChiaGridBot{

    clear-host
    Write-SpectreFigletText -Text "Grid Bot: Wizard" -Color "darkseagreen" 
    Write-SpectreHost -Message "
[darkturquoise]
A grid bot is a trading method where you create a spread between a two assets, 
and trade those assets between two price ranges.  This bot is designed to 
be asymetrical.  Meaning you can trade uneven amounts of each token.


Trading is done as an X/Y pair.  This bot is opinionated in what the price for
a trading pair is.  The bot will always use the following formulas for price:


[seagreen2]Y:     Token Y[/]
[deepskyblue1]X:     Token X[/]
[yellow]P:     Price[/]


[seagreen2]Y[/] [white]/[/] [deepskyblue1]X[/] [white]=[/] [yellow]P[/]
[yellow]P[/] [white]*[/] [deepskyblue1]X[/] [white]=[/] [seagreen2]Y[/]
[yellow]P[/] [white]/[/] [seagreen2]Y[/] [white]=[/] [deepskyblue1]X[/]
[/]
    "

    $type = Read-SpectreSelection -Message "
[darkturquoise]What trading pair type will you create?[/]" -Choices @("XCH-CAT","CAT-CAT") 
    
    if($type -eq "XCH-CAT"){

        $token_x = Get-ChiaAsset -id "xch"
        $token_y = Select-ChiaAsset -cats_only -title "SELECT A TOKEN TO TRADE"

    } else {
        $token_y = Select-ChiaAsset -cats_only -title "SELECT A TOKEN Y TO TRADE"
        $token_x = Select-ChiaAsset -cats_only -title "SELECT A TOKEN X TO TRADE"
        if($token_x.id -eq $token_y.id){
            Write-SpectreHost -Message "
[yellow]You cannot create a bot with the same token for both sides. Please try again.
[/]"
            return
        }
    }
    $token_y.setAmountInteractive()
    $token_x.setAmountInteractive()
    
    
    if($token_x.code -eq 'xch'){
        $current_price = $token_y.getSimpleQuote()
        
        if($null -eq $current_price){
            Write-SpectreHost "[red]Failed to fetch current price.[/]"
            $starting_price = Get-SpectreNumber -message "
            [green]
Price[/] = [yellow]$($token_y.code)[/] / [blue]$($token_x.code)[/]
Enter the current price of the pair:
" -numberOfDecimals 3     
            
            } else {
                Write-SpectreHost "Current price is for $($token_y.code) / $($token_x.code) is [green]$($current_price.avg_price)[/]"
                $starting_price = Get-SpectreNumber -message "
[green]
Price[/] = [yellow]$($token_y.code)[/] / [blue]$($token_x.code)[/]
Enter the current price of the pair:" -numberOfDecimals 3 -DefaultAnswer $current_price.avg_price
            }
    } else {
        $x_price = $token_x.getSimpleQuote()
        $y_price = $token_y.getSimpleQuote()
        if($null -eq $x_price -or $null -eq $y_price){
            Write-SpectreHost "[red]Failed to fetch current price.[/]"
            $starting_price = Get-SpectreNumber -message "
[green]
Price[/] = [yellow]$($token_y.code)[/] / [blue]$($token_x.code)[/]
Enter the current price of the pair:" -numberOfDecimals 3    
        } else {
            $avg_price = [Math]::Round(($y_price.avg_price / $x_price.avg_price),3)
            
            
            Write-SpectreHost -Message "
$($token_y.code): $($y_price.avg_price) per XCH
$($token_x.code): $($x_price.avg_price) per XCH
---------------------------------
price: $($avg_price)

"

$starting_price = Get-SpectreNumber -message "
[green]
Price[/] = [yellow]$($token_y.code)[/] / [blue]$($token_x.code)[/]
Enter the current price of the pair:" -numberOfDecimals 3 -DefaultAnswer $avg_price
            
        }
    }
    
    
    

    $min_price = Get-SpectreNumber -message "Enter the low price of range:" -numberOfDecimals 3 -DefaultAnswer $([Math]::round($starting_price *.9,3))
    $max_price = Get-SpectreNumber -message "Enter the high price of range:" -numberOfDecimals 3 -DefaultAnswer $([Math]::round($starting_price * 1.1,3))
    $step = Get-SpectreNumber -message "
[gray]
The more steps you have the more opportunities to trade
[/]

Enter the number of steps you want to create:" -numberOfDecimals 0
# Calculate amount of X needed.

    
    
$fee_percentage = Get-SpectreNumber -message "
[gray]
This is the fee's you'll collect for providing liquidity.
The fee is applied to each side of the spread.
[/]
Enter the spread percentage: (#.###)" -numberOfDecimals 3 -DefaultAnswer 0.003

    $fee_percentage = $fee_percentage / 2


    Write-SpectreHost -Message "
Token X: [blue]$($token_x.code)[/]
Token Y: [blue]$($token_y.code)[/]
"

$fee_token = Read-SpectreSelection -Message "What token will you pay the fee in?" -Choices @("token_x","token_y") 
    if($fee_token -eq "token_x"){
        $fee_id = $token_x.id
    } else {
        $fee_id = $token_y.id
    }

       

    $confirm = Read-SpectreConfirm -Message "
[green]Confirm Bot Details

Token X:    [blue]$($token_x.getFormattedAmount()) $($token_x.code)[/]
Token Y:    [blue]$($token_y.getFormattedAmount()) $($token_y.code)[/]
Steps:      [cyan1]$step[/]
Min Price:  [lightcoral]$min_price[/]
Current Price: [darkorange3]$starting_price[/]
Max Price:  [maroon]$max_price[/]
[/]
    "
    
    if(-NOT $confirm){
        Write-Host "Bot creation cancelled."
        Start-SageTrader
    }
    [decimal]$transaction_fee = Get-SpectreNumber -Message "Blockchain transaction fee? No fee is suggested as it complicates coin management." -DefaultAnswer 0 -numberOfDecimals 12
    $name = Read-SpectreText -Message "What name do you want to use for this bot?" -DefaultAnswer "$($token_x.code)->$($token_y.code)"
    $fingerprint = Get-ChiaFingerprint

    $bot = [GridBot]::new()
    $bot.name = $name
    $bot.token_x = $token_x
    $bot.token_y = $token_y
    $bot.starting_price = $starting_price
    $bot.min_price = $min_price
    $bot.max_price = $max_price
    $bot.steps = $step
    $bot.fee_percentage = $fee_percentage
    $bot.fee_token_id = $fee_id
    $bot.fingerprint = $fingerprint
    $bot.transaction_fee = $transaction_fee
    $bot.BuildYGrid()
    $bot.BuildXGrid()
    $bot.save()
    
    Write-SpectreHost -Message "
[green]Created bot with ID: $($bot.id)
 [/]   "
 Start-SageTrader
}

function Select-ChiaAsset{
    param(
        [string]$title = "Choose an asset",
        [switch]$cats_only
    )
    if($cats_only.IsPresent){
        $assets = Get-ChiaAssets | Where-Object {$_.id -ne 'xch'}
    } else {
        $assets = Get-ChiaAssets 
    }

    $choice = $assets | Select-Object -Property code,name,id | Out-ConsoleGridView -Title $title -OutputMode Single

    if($choice){
        return Get-ChiaAsset -id ($choice.id)
    } else {
        Select-ChiaAsset
    }

}

function Get-ValidChiaToken{
    param(

        [string]$message,
        [string]$DefaultAnswer
    )

    $token = Read-SpectreText -Message $message -DefaultAnswer $DefaultAnswer
    $asset = Get-ChiaAsset -id $token
    if($null -eq $asset){
        Write-Host "Invalid token ID. Please try again."
        return Get-ValidChiaToken
    }
    if($asset.count -gt 1){
        Write-Host "Multiple assets found with the same code. Please copy the ID of the asset you want and paste it below"
        Write-Host "----------------------"
        $asset | ForEach-Object {
            $_
            Write-Host "----------------------"
         }
        return Get-ValidChiaToken
    }
    return $asset
}

function Show-STHeader{
    param(
        [string]$title="Sage-Trader"
    )
    try{
        $fp = (Get-SageKey).fingerprint
        Clear-Host
        Write-SpectreFigletText -Text $title -Alignment Center -Color green
        Write-SpectreRule -LineColor green -Title "[green]Fingerprint: [/]$($fp)" -Alignment Center
        Write-SpectreHost -Message "
        
        "
    
    } 
    catch {
        Write-SpectreHost -Message "
[red]Could not retrieve Sage Fingerprint. [/]

[yellow]Make sure you have Sage Wallet Installed and the RPC is running.[/]
Visit: [blue]https://themayor.gitbook.io/xchplayground/[/] for more information.
        "
        break;
    }
   
    
}

function Get-SpectreNumber{
    param(
        [Parameter(Mandatory=$true)]
        [string]$message,
        
        [Parameter(Mandatory=$true)]
        [Int16]$numberOfDecimals,
        $DefaultAnswer
    )
    if($null -eq $DefaultAnswer){
        $dinput = Read-SpectreText -Message $message
    } else {
        $dinput = Read-SpectreText -Message $message -DefaultAnswer $DefaultAnswer
    }
    
    if($numberOfDecimals -lt 1){
        $match = '^\d+$'
    } else {
        $match = '^\d+(\.\d{1,'+"$($numberOfDecimals)"+'})?$'
    }
    
    if($dinput -match $match){
        return [decimal]$dinput
    } else {
        
        Write-Host "Invalid input. Please enter a valid number with up to $numberOfDecimals decimal places."
        return Get-SpectreNumber -message $message  -numberOfDecimals $numberOfDecimals
    }
}


class GridBot{
    [string]$id
    [string]$name
    [ChiaAsset]$token_x
    [ChiaAsset]$token_y
    [UInt64]$starting_x_amount
    [UInt64]$starting_y_amount
    [UInt64]$current_x_amount
    [UInt64]$current_y_amount
    [decimal]$starting_price
    [decimal]$min_price
    [decimal]$max_price
    [int]$steps
    [array]$grid
    [array]$active_offers
    [array]$completed_offers    
    [UInt64]$transaction_fee    
    [string]$fingerprint
    [array]$cancelled_offers
    [decimal]$fee_percentage
    [UInt64]$x_fee_collected
    [UInt64]$y_fee_collected
    [string]$fee_token_id
    [bool]$isPrepped
    [bool]$active
    
    
    

    GridBot(){
        $this.id = (New-Guid).Guid
        $this.active = $false
        $this.isPrepped = $false
        $this.grid = @()
        $this.starting_x_amount = 0
        $this.starting_y_amount = 0
        $this.current_x_amount = 0
        $this.current_y_amount = 0
        $this.x_fee_collected = 0
        $this.y_fee_collected = 0
    }

    GridBot([PSCustomobject]$props){
        $this.Init([PSCustomObject]$props)
        
    }

    [bool] isLoggedIn(){
        $fp = (Invoke-SageRPC -endpoint get_key -json @{})
        if($null -eq $fp){
            Write-SpectreHost -Message "[red]Bot [/][blue]$($this.name)[/][red] does not have access to this wallet. 
            Please log in with the fingerprint: [/][blue]$($this.fingerprint)[/]"
            return $false
        }
        if($fp.key.fingerprint -eq $this.fingerprint){
            return $true
        }
        Write-SpectreHost -Message "
        [red]Bot [/][blue]$($this.name)[/][red] does not have access to this wallet. 
        Please log in with the fingerprint: [/][blue]$($this.fingerprint)[/]"
        return $false
    }

    [bool] isActive(){
        if($this.active -eq $true){
            Write-SpectreHost -Message "[green]Bot [/][blue]$($this.name)[/][green] is active.[/]"
            return $true
        } else {
            Write-SpectreHost -Message "[red]Bot [/][blue]$($this.name)[/][red] is not active.[/]"
            return $false    
        }
        
    }

    [void] showMenu(){
    $choice=0
    do{
        Clear-Host
        
        Write-SpectreHost -message ($this.summary())

        Write-SpectreHost -Message "
[cyan]BOT MENU
---------------------------------
1. $($this.active ? "[red]Deactivate Bot[/]" : "[green]Activate Bot[/]")
2. $($this.isPrepped ?  "[green]Coins are prepped[/]" : "[yellow]Prepare Coins[/]")
3. Make Initial Offers
4. Cancel All Offers
5. Destroy Bot
9. Back to main menu
[/]

"

$choices = @(1,2,3,4,5,9)
$choice = Read-ValidMenu -choices $choices -message "Select an option:"

    switch ($choice) {
        1 {
            if ($this.active) {
                $this.deactivate()
                Write-SpectreHost -Message "[red]Bot [/][blue]$($this.name)[/] [red]is now deactivated.[/]"
                
            } else {
                $this.activate()
                Write-SpectreHost -Message "[green]Bot [/][blue]$($this.name)[/] [green]is now active.[/]"
                
            }
        }
        2 {
            try{
                $coins = $this._splitCoins()
                if($coins){
                    Write-SpectreHost -Message "[green]Coins split successfully. It may take up to 5 minutes before you can create the initial offer.[/]"
                    start-sleep 10
                    while($true){
                        Write-SpectreHost "[yellow]Transaction is PENDING please wait[/]"
                        $transaction = Invoke-SageRPC -endpoint get_pending_transactions -json @{}
                        if($transaction.transactions.count -eq 0){
                            break 
                        }   
                        start-sleep 10
                        }
                    
                } else {
                    Write-SpectreHost -Message "[red]Failed to split coins.[/]"
                }
                
            } catch {
                Write-SpectreHost -Message "[red]An error occurred while splitting coins: $($_.Exception.Message)[/]"
                pause
            }
        }
        3 {
            if($this.isPrepped){
                try{
                    $this.makeInitialOffers()
                } catch {
                    Write-SpectreHost -Message "[red]An error occurred while making initial offers: $($_.Exception.Message)[/]"
                    pause
                }
                
            } else {
                Write-SpectreHost -Message "[red]Coins are not prepped for this bot. Please prep them first.[/]"
                pause
            }
            
        }
        4 {
            if($this.active_offers.Count -gt 0){
                $this.CancelOffers()
                $choice = 9
            }
            
        }

        5 {$this.destroy()
            $choice = 9
        }
        }}until ($choice -eq 9)
        Write-SpectreHost -Message "[green]Returning to main menu...[/]"
        Show-Screen -name Home
    }


    [string] summary(){
        $summary = @"
[green]Grid Bot Summary[/]
Name:               $($this.name)
ID:                 $($this.id)
Fingerprint:        $($this.fingerprint)
Token X:            $($this.token_x.code) - $($this.token_x.getFormattedAmount())
Token Y:            $($this.token_y.code) - $($this.token_y.getFormattedAmount())
Starting Price:     $($this.starting_price)
Min Price:          $($this.min_price)
Max Price:          $($this.max_price)
X Fee Collected:    $($this.x_fee_collected) $($this.token_x.code)
Y Fee Collected:    $($this.y_fee_collected) $($this.token_y.code)
Steps:              $($this.steps)
Completed Trades:   $($this.completed_offers.Count)
Active Offers:      $($this.active_offers.Count)

Active:             $($this.active ? "[green]Yes[/]" : "[red]No[/]")
"@
        return $summary
    }

    [void] activate(){
        if(-not $this.isPrepped){
            $pre = Read-SpectreConfirm -Message "[yellow]Coins are not prepped for this bot. Do you want to prep them now?[/]" -DefaultAnswer "y"
            if ($pre) {
                $this.forcePrep() 
                Write-SpectreHost -Message "[green]Coins prepared for bot.[/]"
                
            }
        }
        $this.active = $true
        $this.save()
    }

    [void] deactivate(){
        $this.active = $false
        $this.save()
    }

    [void] Handle(){
        $this.checkOffers()
    }

    [void] checkOffers(){
        
        if($this.isActive() -and $this.isLoggedIn()){
            $actives = $this.active_offers | Sort-Object {$_.index}
            foreach($active in $actives) {
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
        if($props.token_x){
            $this.token_x = [ChiaAsset]::new($props.token_x)
        }
        if($props.token_y){
            $this.token_y = [ChiaAsset]::new($props.token_y)
        }
        $this.name = $props.name
        $this.starting_price = $props.starting_price
        $this.min_price = $props.min_price
        $this.max_price = $props.max_price
        $this.steps = $props.steps
        $this.transaction_fee = $props.transaction_fee
        $this.fingerprint = $props.fingerprint
        $this.fee_percentage = $props.fee_percentage
        $this.fee_token_id = $props.fee_token_id
        $this.active_offers = $props.active_offers
        $this.completed_offers = $props.completed_offers
        $this.grid = $props.grid
        $this.active = $props.active
        $this.starting_x_amount = $props.starting_x_amount
        $this.starting_y_amount = $props.starting_y_amount
        $this.current_x_amount = $props.current_x_amount
        $this.current_y_amount = $props.current_y_amount
        $this.x_fee_collected = $props.x_fee_collected
        $this.y_fee_collected = $props.y_fee_collected
        $this.isPrepped = $props.isPrepped

    }


    [array] forcePrep(){
        if($this.isPrepped){
            Write-SpectreHost -Message "[yellow]Coins are already prepped for this bot.[/]"
            return $null
        }
        return $this._splitCoins()
    }

    [array] _splitCoins(){
        if($this.isPrepped){
            Write-SpectreHost -Message "[yellow]Coins are already prepped for this bot.[/]"
            pause
            return $null
        }
        if(-not $this.isLoggedIn()){
            
            pause
            return $null
        }
        $array = @()
    
        
        $addresses = (Get-SageDerivations -offset 0 -limit ($this.steps*2)).derivations
        if($this.token_x.id -eq 'xch' -and $this.token_x.amount -gt 0){
            
            $payments = Build-SageBulkPayments
            1..($this.steps) | ForEach-Object {
                $payments.addXchPayment($addresses[$_].address,($this.token_x.amount/$this.steps))
                }
            $payments.submit()
            $array += ($payments.response )
        } elseif($this.token_x.id -ne 'xch' -and $this.token_x.amount -gt 0){
            $payments = Build-SageBulkPayments
            1..($this.steps) | ForEach-Object {
            $payments.addCatPayment($this.token_x.id,$addresses[$_].address,($this.token_x.amount/$this.steps))
            }
            $payments.submit()
            $array += ($payments.response )
        }
            if($this.token_y.id -eq 'xch' -and $this.token_y.amount -gt 0){
            $payments = Build-SageBulkPayments
            1..($this.steps) | ForEach-Object {
            $payments.addXchPayment($addresses[$_].address,($this.token_y.amount/$this.steps))
            }
            $payments.submit()
            $array += ($payments.response )
        } elseif($this.token_y.id -ne 'xch' -and $this.token_y.amount -gt 0) {
            $payments = Build-SageBulkPayments
            1..($this.steps) | ForEach-Object {
            $payments.addCatPayment($this.token_y.id,$addresses[$_].address,($this.token_y.amount/$this.steps))
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
            Write-SpectreHost -Message "[yellow]Coins are already prepped for this bot.[/]"
            return $null
        }
        $confirm = Read-SpectreConfirm "Do you want to split your coins to run the bot?"
        if(-not $confirm){
            Write-SpectreHost -Message "[yellow]Coins not split.[/]"
            return $null
        }
        return $this._splitCoins()
        
    }

    [void] destroy(){
        $path = Get-SageTraderPath("GridBots")
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
        $path = Get-SageTraderPath("offerlogs")
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
        $path = Get-SageTraderPath("offerlogs")
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
                if($_.index -lt $this.steps){
                    $this.CreateOfferFromGridIndex($_.index,$true)
                } else {
                    $this.CreateOfferFromGridIndex($_.index,$false)
                }
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
        $addresses = (Get-SageDerivations -offset 0 -limit ($this.steps*2)).derivations
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
        
        pause
    }

    BuildXGrid(){
        $step_amount = $this.token_x.getFormattedAmount() / $this.steps
        $step_size = ($this.max_price - $this.starting_price) / ($this.steps-1)
        if($step_amount -eq 0 -OR $step_size -eq 0){
            return
        }
        for ($i = 0; $i -lt $this.steps; $i++){
            $tPrice = [System.Math]::Round($this.starting_price + ($step_size * $i),3)
            [UInt64]$x_amount = (($step_amount * $this.token_x.denom))
            [UInt64]$y_amount = ($tPrice * $step_amount * $this.token_y.denom)
            $x_fee_percentage = (($this.fee_token_id -eq $this.token_x.id) ? ($this.fee_percentage) : 0)
            [UInt64]$x_fee_amount = ($x_fee_percentage * $x_amount)
            $y_fee_percentage = (($this.fee_token_id -eq $this.token_y.id) ? ($this.fee_percentage) : 0)
            [UInt64]$y_fee_amount = ($y_fee_percentage * $y_amount)
            
            $row = [pscustomobject]@{
                x_fee_percentage = $x_fee_percentage
                y_fee_percentage = $y_fee_percentage
                x_fee_amount = $x_fee_amount
                y_fee_amount = $y_fee_amount
                index = ($i+$this.steps)
                price = [decimal]$tPrice
                x_code = $this.token_x.code
                x_amount = $x_amount
                y_code = $this.token_y.code
                y_amount = $y_amount
                ask = [ordered]@{
                    requested_asset_id = $this.token_x.id
                    requested_asset_amount = ($x_amount + $x_fee_amount)
                    offered_asset_id = $this.token_y.id
                    offered_asset_amount = ($y_amount - $y_fee_amount)
                }
                bid = [ordered]@{
                    requested_asset_id = $this.token_y.id
                    requested_asset_amount = ($y_amount + $y_fee_amount)
                    offered_asset_id = $this.token_x.id
                    offered_asset_amount =  ($x_amount - $x_fee_amount)
                }
            }
            $this.grid += $row
        }
    }

    BuildYGrid(){
        $this.grid = @()
        $step_amount = $this.token_y.getFormattedAmount() / $this.steps
        $step_size = ($this.starting_price - $this.min_price) / ($this.steps-1)
        if($step_amount -eq 0 -OR $step_size -eq 0){
            return
        }
        for ($i = 0; $i -lt $this.steps; $i++){
            $x_fee_percentage = (($this.fee_token_id -eq $this.token_x.id) ? ($this.fee_percentage) : 0)
            $y_fee_percentage = (($this.fee_token_id -eq $this.token_y.id) ? ($this.fee_percentage) : 0)
            
            $tPrice = [System.Math]::Round($this.min_price + ($step_size * $i),3)
            [UInt64]$x_amount = (($step_amount / $tPrice)*$this.token_x.denom)
            [UInt64]$y_amount = ($step_amount*$this.token_y.denom)
            [UInt64]$x_fee_amount = ($x_fee_percentage * $x_amount)
            [UInt64]$y_fee_amount = ($y_fee_percentage * $y_amount)
            $row = [pscustomobject]@{
                x_fee_percentage = $x_fee_percentage
                y_fee_percentage = $y_fee_percentage
                x_fee_amount = $x_fee_amount
                y_fee_amount = $y_fee_amount
                x_code = $this.token_x.code
                x_amount = $x_amount
                y_code = $this.token_y.code
                y_amount = $y_amount
                index = $i
                price = [decimal]$tPrice
                ask = [ordered]@{      
                    requested_asset_id = $this.token_x.id
                    requested_asset_amount = ($x_amount + $x_fee_amount)
                    offered_asset_id = $this.token_y.id
                    offered_asset_amount = ($y_amount - $y_fee_amount)
                }
                bid = [ordered]@{
                    requested_asset_id = $this.token_y.id
                    requested_asset_amount = ($y_amount + $y_fee_amount)
                    offered_asset_id = $this.token_x.id
                    offered_asset_amount = ($x_amount - $x_fee_amount)
                }
            }
            $this.grid += $row
        }
        
    }

    
    save(){
        $path = Get-SageTraderPath("GridBots")
        $file = Join-Path -Path $path -ChildPath "$($this.id).json"
        $this | ConvertTo-Json -Depth 20 | Out-File -FilePath $file -Encoding utf8
    }

}


function Get-Screens{
    return @{
        Blank = @{
            title = ""
            breadcrumb = ""
            message = ""
            choices = @()
        }
        Home = @{
            title = "chia.term"
            breadcrumb = "Home"
            message = "Welcome to [Chartreuse1]chia.terminal[/]! 

                [Chartreuse1]chia.terminal[/] will help you execute trading strategies on the Chia Network.
                Please choose an option from the menu below to get started.
                
                "
            choices = @(
                [PSCustomObject]@{ Label = "Create Bot"; Action = { New-ChiaBot } },
                [PSCustomObject]@{ Label = "Manage Bots"; Action = { Show-Bots } },
                [PSCustomObject]@{ Label = "Start All Bots"; Action = { Start-Bots } },                
                [PSCustomObject]@{ Label = "Exit"; Action = {  } }
            )

        }
        CreateBot = @{
            title = "Create New Bot"
            breadcrumb = "Home > Bot > Create"
            message = "You can create the followint types of bots
            [Chartreuse1]Dollar Cost Averaging Bot[/]: This bot will place market orders for you using [blue]dexie.space[/] swap prices. 
            [Chartreuse1]Grid Bot[/]: This bot will create a grid trading strategy.  The offers will be created and managed by the bot.

            "
            choices = @(
                [PSCustomObject]@{ Label = "Dollar Cost Averaging Bot"; Action = { New-ChiaDCABot } },
                [PSCustomObject]@{ Label = "Grid Bots"; Action = { New-ChiaGridBot } }
            )
        }
        Settings = @{
            title = "Settings"
            breadcrumb = "Home > Settings"
            message = "Edit Settings for [Chartreuse1]chia.terminal[/]
            
            This can be used to edit the database.
            "
            choices = @(
                [PSCustomObject]@{ Label = "Back"; Action = { Show-Screen -name Home} },
                [PSCustomObject]@{ Label = "Settings"; Action = { Show-Screen -name Settings} }
            )
        }

    }
}


function Show-Screen{
    param(
        [string]$name
    )
    $screens= (Get-Screens)
    $Screen = $screens.$name
    Clear-Host
    Write-SpectreFigletText -Text ($Screen.title) -Alignment Center -Color Chartreuse1 
    $message = Format-SpectreString ($Screen.message)
    $message | Format-SpectreAligned -VerticalAlignment Top -HorizontalAlignment Left | Format-SpectrePanel -Height 16 -Expand -Border Square -Header ($Screen.breadcrumb)
    
    $choices = ($Screen.choices)


    $selection = Read-SpectreSelection -Choices $choices -ChoiceLabelProperty "Label" -Message "Selection:" -EnableSearch
    & $selection.Action

}

function Format-SpectreString([string]$string){
    $process = $string.Split("`n")
    return ($process | ForEach-Object {$_.Trim()}) -join "`n"   

}

Export-ModuleMember -Function *
