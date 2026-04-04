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
    $silentBots = Get-SilentBots
    
    $dcabots | ForEach-Object {$bots += $_}
    $gridbots | ForEach-Object {$bots += $_}
    $silentBots | ForEach-Object {$bots += $_}
    

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
[yellow]We have changed the way we create the grid bot to make the process easier.[/]


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

function New-ChiaSilentBot{

    $bot = [SilentBot]::new()

    
    Write-SpectreFigletText -Text SilentBot -Alignment Center -Color green -PassThru | Out-SpectreHost
   
"
A SilentBot will trade a Cat token against XCH by using market orders on dexie.

This bot uses the same formula as Uniswap V3.
(x virtual + x real)(y virtual + y real) = liquidity^2

This is a simpler bot because it does not require as much coin management as the grid bot.
" | Format-SpectrePadded -Padding 1 |Format-SpectrePanel -Header "SilentBot" -Border Square -Color blue -Expand | Out-Spectrehost

Read-SpectrePause -Message "Select token to trade against XCH"

$bot.token_x = Get-sagetoken -id xch

$token_y = Select-ChiaAsset -cats_only -title "Select the token to trade"

# return if none selected
if(-not $token_y){
    return
} else {
    $bot.token_y = Get-SageToken -id $token_y.id
}
$p = Invoke-SpectreCommandWithStatus -Spinner Aesthetic -Title "Fetching Current Price" -ScriptBlock {
    
    return $token_y.getSimpleQuote()
} 
$price = Get-SpectreNumber -message "Enter the current price" -DefaultAnswer ($p.avg_price) -numberOfDecimals 2


Write-Spectrehost -Message"
The current price is [green]$($price)[/]

Do you want to set a:

[green]Max Price[/] [gray]Trade XCH for $($bot.token_y.ticker) by assigning up to[/] [green]$([Math]::Round(($bot.token_x.DisplayBalance()),3))[/] XCH
[yellow]Min Price[/] [gray]Trade $($bot.token_y.ticker) for XCH by assigning up to[/] [green]$($bot.token_y.DisplayBalance())[/] $($bot.token_y.ticker) 

If you want to trade with both tokens, you will need to create a second bot to trade the other direction.

" -PassThru | Format-SpectrePanel -Header "Price" -Border Square -Color blue -Expand

$choices = @(
    [pscustomobject]@{
        id = 0
        name = "Set Max Price - Assign XCH"
    }
    [pscustomobject]@{
        id = 1
        name = "Set Min Price - Assign $($bot.token_y.ticker)"
    }
) 


$assigned = Read-SpectreSelection -Message "Choose token to assign" -Choices $choices -ChoiceLabelProperty name

# exit if not chosen
if($null -eq $assigned){
    return
}

if($assigned.id -eq 0){
    <# 
    XCH is assigned.  
    Setting min price (pa) to current price
    Setting max price (pb) to chosen max price
    #>
    $bot.x_is_default = $true
    $amount_assigned = Get-SpectreNumber -message "
[yellow]Max assignable is $($bot.token_x.DisplayBalance()) XCH[/]
How much XCH do you want to assign to this bot?" -numberOfDecimals 12 
    
    $bot.pa = $price
    $bot.pb = Get-SpectreNumber -Message "[yellow]Must be above $($bot.pa)[/]
Set the max price of the bot.
    " -numberOfDecimals 2 -DefaultAnswer ([Math]::Round($bot.pa * 1.10,2))

    if($bot.pb -le $bot.pa){
        Write-SpectreHost "[red]Pricing error[/]"
        return
    }
     
    $bot.spread_percentage = Get-SpectreNumber -message "Enter the minimum XCH fee you want to collect on each trade" -numberOfDecimals 3 -DefaultAnswer 0.003
    
    $bot.x_is_spread_token = $true
    
    $bot.Starting_Token_Amount($amount_assigned)
    $bot.starting_x_amount = $amount_assigned
    $bot.save()

} else {
     <# 
    CAT is assigned.  
    Setting min price (pa) to current price
    Setting max price (pb) to chosen max price
    #>
    $bot.x_is_default = $false
    $amount_assigned = Get-SpectreNumber -message "
[yellow]Max assignable is $($bot.token_y.DisplayBalance()) XCH[/]
How much $($bot.token_y.ticker) do you want to assign to this bot?" -numberOfDecimals 3
    
    $bot.pb = $p.avg_price
    $bot.pa = Get-SpectreNumber -Message "[yellow]Must be below $($bot.pb)[/]
Set the max price of the bot.
    " -numberOfDecimals 2 -DefaultAnswer ([Math]::Round($bot.pb / 1.10,2))

    if($bot.pb -le $bot.pa){
        Write-SpectreHost "[red]Pricing error[/]"
        return
    }
    

    $bot.spread_percentage = Get-SpectreNumber -message "Enter the minimum fee you want to collect on each trade" -numberOfDecimals 3 -DefaultAnswer 0.003

    $bot.x_is_spread_token = $true
    
    $bot.Starting_Token_Amount($amount_assigned)
    $bot.starting_y_amount = $amount_assigned
    
}
$bot.name = Read-SpectreText -Message "Name the bot: " -DefaultAnswer "SilentBot $($bot.token_y.ticker)"
$bot.fingerprint = Get-ChiaFingerprint
$bot.save()
return $bot
}

Export-ModuleMember -Function *
