using module ".\SageTrader\SageTrader.psm1"
using module "..\powersage\PowerSage\PowerSage.psm1"
using module "..\dexiePowerShell\PowerDexie\PowerDexie.psm1"


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
        $token_y = Select-ChiaAsset -cats_only -title "SELECT A TOKEN X TO TRADE"
        if($token_x.id -eq $token_y.id){
            Write-SpectreHost -Message "
[yellow]You cannot create a bot with the same token for both sides. Please try again.
[/]"
            return New-ChiaGridBot
        }
    }
    $token_y.setAmountInteractive()
    $token_x.setAmountInteractive()
    
    
    if($token_x.code -eq 'xch'){
        $current_price = $token_y.getSimpleQuote()
        
        if($null -eq $current_price){
            Write-SpectreHost "[red]Failed to fetch current price."
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
            Write-SpectreHost "[red]Failed to fetch current price."
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
    
    
    

    $min_price = Get-SpectreNumber -message "Enter the low price of range:" -numberOfDecimals 3 -DefaultAnswer $($starting_price *.9)
    $max_price = Get-SpectreNumber -message "Enter the high price of range:" -numberOfDecimals 3 -DefaultAnswer $($starting_price * 1.1)
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
    $name = Read-SpectreText -Message "What name do you wnat to use for this bot?" -DefaultAnswer "$($token_x.code)->$($token_y.code)"
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
    "
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
    #Show-AppMenu -Item (Get-PanelMainMenuItems) -title "Sage-Trader"
    } 
    catch {
        Write-SpectreHost -Message "
[red]Could not retrieve Sage Fingerprint. [/]

[yellow]Make sure you have Sage Wallet Installed and the RPC is running.[/]
Visit: [blue]https://themayor.gitbook.io/xchplayground/[/] for more information.
        "
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
    [string]$fee_token_id
    [bool]$active
    

    GridBot(){
        $this.id = (New-Guid).Guid
        $this.active = $false
        $this.grid = @()
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

    [void] activate(){
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
            $actives = $this.active_offers
            foreach($active in $actives) {
                $offer = Get-SageOffer -offer_id $active.offer_id
                if($offer.status -eq "completed"){
                    #remove this offer
                    $completed = @{
                        grid = $this.grid[($active.index)].($active.side)
                        offer_id = ($active.offer_id)
                    }
                    $this.completed_offers += $completed
                    $this.active_offers = $this.active_offers | Where-Object {$_.offer_id -ne $active.offer_id}
                    $index = $active.index
                    $isAsk = ($active.side -eq "ask") ? $true : $false
                    $this.CreateOfferFromGridIndex($index,(-not $isAsk))
                }
                
            }
        }
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

    }


    [array] prepCoins(){
        $confirm = Read-SpectreConfirm "Do you want to split your coins to run the bot?"
        $array = @()
        if($confirm){
            
            $addresses = Get-SageDerivations -offset 0 -limit ($this.steps*2)
            if($this.token_x.id -eq 'xch'){
                $payments = Build-SageBulkPayments
                1..($this.steps) | ForEach-Object {
                    $payments.addXchPayment($addresses[$_].address,($this.token_x.amount/$this.steps))
                    }
                $payments.submit()
                $array += ($payments.response )
            } else {
                $payments = Build-SageBulkPayments
                1..($this.steps) | ForEach-Object {
                $payments.addCatPayment($this.token_x.id,$addresses[$_].address,($this.token_x.amount/$this.steps))
                }
                $payments.submit()
                $array += ($payments.response )
            }
             if($this.token_y.id -eq 'xch'){
                $payments = Build-SageBulkPayments
                1..($this.steps) | ForEach-Object {
                $payments.addXchPayment($addresses[$_].address,($this.token_y.amount/$this.steps))
                }
                $payments.submit()
                $array += ($payments.response )
            } else {
                $payments = Build-SageBulkPayments
                1..($this.steps) | ForEach-Object {
                $payments.addCatPayment($this.token_y.id,$addresses[$_].address,($this.token_y.amount/$this.steps))
                }
                $payments.submit()
                $array += ($payments.response )
            }
            
            
        }
        return $array
    }

    [void] destroy(){
        $path = Get-SageTraderPath("GridBots")
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

    [void]makeInitialOffers(){
        if($this.active_offers.Count -eq 0){
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
        
        $addresses = Get-SageDerivations -offset 0 -limit ($this.steps * 2)
        $buildData = $this.grid[$index].$side
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

