
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
        $cat = Get-SageCat -asset_id $this.id
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

    [void] Save(){
        $path = Get-SageTraderPath("DCABots")
        $file = Join-Path -Path $path -ChildPath "$($this.id).json"
        if(-not (Test-Path -Path $path)){
            New-Item -Path $path -ItemType Directory | Out-Null
        }
        
        $this | ConvertTo-Json -Depth 10 | Out-File -FilePath $file -Encoding utf8
    }

    [void] summary(){
        Write-SpectreHost -Message "
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
    Clear-Host
    Write-SpectreFigletText -Text "Create a New Chia Bot" -Color green Center
    Read-SpectreSelection -Message "What type of bot would you like to create?" -Choices @("Dollar Cost Averaging","Grid Trading") -EnableSearch | Select-ChiaBotAnswer
    
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
}

function New-ChiaGridBot {

    Clear-Host
    Write-SpectreFigletText -Text "New Grid Trading Bot" -Color green -Alignment Center
    $description = Write-SpectreHost -Message "

    This bot will trade between two assets in a grid trading strategy.
    It will buy and sell assets at predefined price levels, allowing you to profit from market fluctuations.
    It does this by creating trades on both sides of the trading pair with a spread between the buy and sell prices."

    @($title, $description) | Format-SpectreRows | Format-SpectrePanel
}




function New-ChiaDCABot{
    $bot = [ChiaDCABot]::new()
    $direction_choice = ''
    Clear-Host
    Write-SpectreFigletText -Text "New DCA Bot" -Color green Center
    Write-SpectreHost -Message "Select enter the asset you want to Dollar Cost Average.
    
    "
    $asset = Select-ChiaSwapAsset
    $direction = Read-SpectreSelection -Message "Do you want to [green]Buy (XCH->$($asset.code))[/] or [red]Sell ($($asset.code)->XCH)[/] this $($asset.name)?" -Choices @("[green]Buy[/]", "[red]Sell[/]") 
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
    $bot.summary()
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
    Start-SageTrader
}


function Get-ChiaFingerprint {
    $fingerprints = Get-SageKeys

    $fingerprint = Read-SpectreSelection -Message "Authorize Bot to access specific fingerprint." -Choices ($fingerprints.name) -EnableSearch -SearchHighlightColor purple
    return ($fingerprints | Where-Object { $_.name -eq $fingerprint }).fingerprint
}



function Connect-ChiaFingerprint {
    $fingerprints = Get-SageKeys

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
    $data = @()
    $xch = Get-SageSyncStatus
    if ($xch -and $xch.balance) {
        $xch_balance = [decimal]($xch.balance / 1000000000000)
        $data += [pscustomobject]@{
            Image = "https://icons.dexie.space/xch.webp"
            Asset = "XCH"
            Balance = $xch_balance
        }
    } 
    $cats = Get-SageCats | Sort-Object -Property balance -Descending
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


function Get-ChiaDefaultFee{
    $asset = Get-ChiaAsset -id "xch"
    [decimal]$fee = Get-SpectreNumber -Message "What is the default fee for this bot? (0 for no fee)" -DefaultAnswer "0.00005"
    
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
        Write-SpectreHost -Message "[red]No bots found.[/]"
        return
    }
    $files = Get-ChildItem -Path $path -Filter "*.json"
    if($files.Count -eq 0){
        Write-SpectreHost -Message "[red]No bots found.[/]"
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
        Write-SpectreHost -Message "[red]No bots found.[/]"
        return
    }
    $files = Get-ChildItem -Path $path -Filter "*.json"
    if($files.Count -eq 0){
        Write-SpectreHost -Message "[red]No bots found.[/]"
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
    while($true){
        Write-SpectreHost -Message "[purple] $(Get-Date) [/]"
        Write-SpectreRule -Color purple
        $bots = Get-ChiaBots
        if($null -eq $bots){
            Write-SpectreHost -Message "[red]No bots found.[/]"
            return
        }
        foreach ($bot in $bots) {
            Write-Information "Starting bot: $($bot.name)"
            $bot.Handle()
        }
        Write-SpectreHost -Message "[green]All bots have been processed. Waiting for the next cycle...[/]"
        Write-SpectreRule -Color purple
        Start-Sleep -Seconds 60 # Wait for 60 seconds before the next cycle 
    }
    
}

function Show-PanelMainMenu{

    param (
        $Item,
        $SelectedItem
    )
    $itemList = $Item | ForEach-Object {
        $name = $_.Name
        if ($_.Name -eq $SelectedItem.Name) {
            $name = "[green]$($name)[/]"
        } 
        return $name
    } | Out-String
    return Format-SpectrePanel -Header "[white]Main Menu[/]" -Data $itemList.Trim() -Expand -Color darkseagreen
}

function Get-PanelMainMenuItems{
    return @(
        [PSCustomObject]@{ 
            Name = "Create Chia Bot" 
            Description ="Create a new trading bot for Chia."
            Action = { 
                New-ChiaBot
            }
        },
        [PSCustomObject]@{ 
            Name = "Show Bots" 
            Description = "Show all existing Chia bots."
            Action = {
                Show-AppMenu -Item (Get-PanelBotMenuItems) -title "Chia Bots"
            }
        },
        [PSCustomObject]@{
            Name = "Run All Bots"
            Description = "Start up all the bots.  They will start to actively trade as long as Sage is running and logged in with the correct fingerprint."
            Action = {
                Start-Bots
            }
        }
        [PSCustomObject]@{ 
            Name = "Exit"
            Description = "Exit the Sage Trader application."
            Action = {
                return
            }
        }
    )

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





function Show-STWallet {
    Show-STHeader -title "Wallet Options"

    Write-SpectreHost -Message "
1. Main Menu
2. Show Balances
3. Show Offers
4. Select a Token

9. Exit

"
    $choices = @(1,2.3,4,9)
    $choice = Read-ValidMenu -choices $choices -message "Select an option:"
    switch ($choice) {
        1 { Start-SageTrader}
        2 { Show-STWalletBalances }
        3 { Show-STWalletOffers }
        4 { Select-STToken }
        
        9 { return }
        Default {  }
    }
    
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
    $bot = $bots | Where-Object { $_.name -eq $name }
    if ($null -eq $bot) {
        Write-SpectreHost -Message "[red]Bot with name '$name' not found.[/]"
        return $null
    }
    return $bot
}


function Start-SageTrader{
    Show-STHeader

    Write-SpectreHost -Message "
1. Wallet
2. Market Orders
3. Make Offer
4. Bots (Automated Trading)
5. Reports

9. Exit

"
    $choices = @(1,2,3,4,5,9)
    $choice = Read-ValidMenu -choices $choices -message "Select an option:"
    switch ($choice) {
        1 { Show-STWallet }
        2 { Show-STMarket }
        3 { Show-STOffer }
        4 { Show-STBots}
        5 { Show-STReports }
        9 { return }
        Default {  }
    }
    
}





Export-ModuleMember -Function *