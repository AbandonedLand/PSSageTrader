function Get-SageTraderVersion{
    return @{
        Version = "2.1.3"
        Major = 2
        Minor = 1
        Patch = 3
    }
}

function Start-Bootstrap{

    Invoke-SpectreCommandWithStatus -Title "Fetching asset list from dexie.space" -ScriptBlock {
        if(-not $Global:assets){
            Get-xchAssets
        }
    } -Spinner Toggle10
    
}

function Start-STOfferDex{
    
    Show-OfferDexHeader
    Start-Bootstrap
    Show-OfferDexMenu
}

function Show-OfferDexHeader{
    Clear-Host
    Write-SpectreFigletText -Text "offerDEX" -Color green -Alignment Center
    Write-SpectreRule -Title "Combine offers from dexie" -LineColor green 
"Combine offers found on dexie to get the most for you trade!  offerDex will get upto 100 offers from dexie at a time that match your requirements.  

It will combine as many offers as it can together for you under your max spend amount and copy the offer file to your clipbord." |  Format-SpectrePanel -Expand -Color green -Height 4 

}

function Show-OfferDexMenu{
    
    $choices = @(
    @{
        message = "Get Quote"
        action = { Get-NewOffer}
    }
    @{
        message = "Back"
        action = { Start-SageTrader }
    }
    
    )
    
    $selection = Read-SpectreSelection -Message "Menu:" -Choices $choices -ChoiceLabelProperty message
    &($selection.action)
}

function Get-xchAssets {
    $uri = "https://api.dexie.space/v3/prices/tickers"
    $data = Invoke-RestMethod -Uri $uri
    $assets = @()
    $assets += @{
        asset_id = "xch"
        ticker = "XCH"
        name = "Chia"
        volume = 1000000000000
    }
    if($data.success){
        $data.tickers | ForEach-Object {
            $assets += @{
                asset_id = ($_.base_currency)
                ticker = ($_.base_code)
                name = ($_.base_name)
                volume = ($_.target_volume -as [Decimal])
            }
        }
        
    }
    $Global:assets = ( $assets | Sort-Object -Property volume -Descending)
}

function Read-SpectreNumber{
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
        return Read-SpectreNumber -message $message  -numberOfDecimals $numberOfDecimals
    }
}

function Get-NewOffer{
    Show-OfferDexHeader
    $offered = Read-SpectreSelection -Message "What asset are you offering?" -Choices ($Global:assets) -ChoiceLabelProperty ticker -EnableSearch -SearchHighlightColor blue -PageSize 10
    $offerAsset = (Get-SageToken -id $offered.ticker)
    if($offerAsset.balance -gt 0){
        $displayBal = $offerAsset.DisplayBalance()
    } else {
        $displayBal = 0
    }
    $requested = Read-SpectreSelection -Message "What asset do you want?" -Choices (($Global:assets | Where-Object {$_.asset_id -ne $offered.asset_id})) -ChoiceLabelProperty ticker -EnableSearch -SearchHighlightColor blue -PageSize 10
    $decimals = ($offered.ticker -eq "XCH") ? 12 : 3
    $offered_amount = Read-SpectreNumber -message "How much [red]$($offered.name)[/] do you want to spend on [green]$($requested.name)[/]" -numberOfDecimals $decimals
    $dexie_uri = "https://api.dexie.space/v1/offers?offered=$($requested.ticker)&requested=$($offered.ticker)&page_size=100"
    $offers = Invoke-SpectreCommandWithStatus -Title "Searching [blue]dexie.space[/]!" -ScriptBlock {
        $tmp_offers = Invoke-RestMethod -Uri $dexie_uri -Method Get
        $amount_spent = (($decimals -eq 12) ? 0.001 : 0.03)
        $collected = @()
        $amount_received = 0
        $tmp_offers.offers | ForEach-Object {
            $tmp_amt = $amount_spent + $_.requested[0].amount
            if($tmp_amt -le $offered_amount){
                $amount_spent = $tmp_amt
                $amount_received += $_.offered[0].amount
                
                $collected += @{
                    offered = $_.offered[0].code
                    offered_amount = $_.offered[0].amount
                    requested = $_.requested[0].code
                    requested_amount = $_.requested[0].amount
                    offer = $_.offer
                }
            }
        }
        start-sleep 1
        return [ordered]@{
            fee_asset_id = ($offered.asset_id)
            spent_asset = ($offered.ticker)
            spent_amount = $amount_spent
            received_asset = ($requested.ticker)
            received_amount = $amount_received
            offers = ($collected.offer)
            display = [PSCustomObject]@{
                "Id" = [System.DateTimeOffset]::Now.ToUnixTimeSeconds()
                "Spent Asset" = ($offered.ticker)
                "Spent Amount" = $amount_spent
                "Received Asset" = ($requested.ticker)
                "Received Amount" = $amount_received
                "# of Combined Offers"=($collected.offer.count)
                "Price S/R" = ([Math]::Round($amount_spent/$amount_received,3))
                "Price R/S" = ([Math]::Round($amount_received/$amount_spent,3))
            }
        }
    
    }
    if($offers){
        

        [PSCustomObject]$offers.display | Format-SpectreTable -Color green
        $response = Invoke-RestMethod -uri "https://offer.watch/api/combine" -body ($offers | ConvertTo-Json) -Method Post -ContentType "application/json"

        if($response){
            Write-SpectreHost "You have $($displayBal) $($offered.ticker) available."
            $take = Read-SpectreConfirm -message "Do you want to take this offer?" -DefaultAnswer n 
            if($take){
                Complete-SageOffer -offer $response
                    while($true){   
                        $transaction = Invoke-SageRPC -endpoint get_pending_transactions -json @{}
                        if($transaction.transactions.count -eq 0){
                            break 
                        } else {
                            Write-SpectreHost "[yellow]Transaction is PENDING please wait[/]"
                        }
                        start-sleep 10
                    }
            } else {
                Write-SpectreHost -Message "[red]Offer not accepted.[/]"   
                start-sleep 1
            }               
        }    
    }
    Clear-Host

    Start-STOfferDex
}
function Wait-PendingTransaction{
    while($true){
        
        $transaction = Invoke-SageRPC -endpoint get_pending_transactions -json @{}
        if($transaction.transactions.count -eq 0){
            break 
        } else {
            Write-SpectreHost "[yellow]Transaction is PENDING please wait[/]"
        }
        start-sleep 10
    }
}

function Get-MyLoanVault {
    Invoke-SpectreCommandWithStatus -Spinner Aesthetic -Title "Fetching Vault... " -ScriptBlock {
        $fetch = Get-CDMyVault
        return $fetch
    }
}

function Show-MyVault {
    Clear-Host
    $vault = Get-MyLoanVault
    if(-not $vault){
        
        $confirm = Read-SpectreConfirm -Message "No Vault found.  Would you like to deposit some XCH to start one?"
        if($confirm){
            Show-CircuitDeposit
        } else {
            Start-SageTrader
        }
        

    } else {
        $locked = [math]::round((($vault.collateral - $vault.max_withdraw) | ConvertFrom-XchMojo),2)
        $maxw = [math]::round(($vault.max_withdraw | ConvertFrom-XchMojo),2)
       
        $xchchart = @(
            New-SpectreChartItem -Label "Locked XCH" -Value $locked -Color red
            New-SpectreChartItem -Label "Withdrawable XCH" -Value $maxw -Color green
        ) | Format-SpectreBreakdownChart
 
        $bycchart = @(
            New-SpectreChartItem -Label "Debt Owed" -Value ($vault.debt_owed_to_vault | ConvertFrom-CatMojo) -Color blue
            New-SpectreChartItem -Label "Max Borrowable" -Value ($vault.max_borrow | ConvertFrom-CatMojo) -Color yellow
        ) | Format-SpectreBreakdownChart
 
        clear-host
        Write-SpectreFigletText -Text "Circuit Dao Vault"
        Write-SpectreHost -message "
Deposited XCH: $([math]::round(($vault.collateral | ConvertFrom-XchMojo),3))"
        $xchchart
        Write-SpectreHost -Message "
        
        
BYC Loan/Borrow"
        $bycchart

        $choices = @(
            [pscustomobject]@{
                Name = "Back"
                Action = {Start-SageTrader}
            }
            [pscustomobject]@{
                Name = "Borrow BYC"
                Action = {Show-CircuitBorrow}
            }
            [pscustomobject]@{
                Name = "Deposit XCH"
                Action = {Show-CircuitDeposit}
            }
            [pscustomobject]@{
                Name = "Repay BYC"
                Action = {Show-CircuitRepay}
            }
            [pscustomobject]@{
                Name = "Withdraw XCH"
                Action = {Show-CircuitWithdraw}
            }

        )
    }

    $select = Read-SpectreSelection -Message "
    
    
Interact with your vault:" -Choices $choices -ChoiceLabelProperty Name
&$select.Action


}

function Show-CircuitBorrow {
    Clear-Host
    $vault = Get-MyLoanVault
    $max = ($vault.max_borrow | ConvertFrom-CatMojo)

    "
    
    You have [green]$max BYC[/]  available to borrow.

    " | Format-SpectrePanel -Header "Circuit Dao - Borrow BYC" -Expand

    $response = Read-SpectreDecimal -message "How much BYC do you wish to borrow?" -precision 3
    $confirm = Read-SpectreConfirm -Message "Are you sure you want to borrow [green]$($response) BYC[/]"
    if($confirm){
        Invoke-CDVaultAction -operation borrow -amount ($response | ConvertTo-CatMojo) -submit
        Wait-PendingTransaction
        Show-MyVault
    } else {
        Show-MyVault
    }
}

function Show-CircuitDeposit {
    Clear-Host
    $max = (Get-SageToken -id xch).DisplayBalance()
    
    
    "
    
    You have [green]$max XCH[/]  available to deposit.

    " | Format-SpectrePanel -Header "Circuit Dao - Deposit XCH" -Expand

    $response = Read-SpectreDecimal -message "How much XCH do you wish to deposit?" -precision 12
    $confirm = Read-SpectreConfirm -Message "Are you sure you want to deposit [green]$($response) XCH[/]"
    if($confirm){
        Invoke-CDVaultAction -operation deposit -amount ($response | ConvertTo-XchMojo) -submit
        Wait-PendingTransaction
        Show-MyVault
    } else {
        Show-MyVault
    }
}

function Show-CircuitRepay {
    Clear-Host
    $max = (Get-SageToken -id byc).DisplayBalance()
    
    
    "
    
    You have [green]$max BYC[/]  available to repay loan.

    " | Format-SpectrePanel -Header "Circuit Dao - Repay BYC loan" -Expand

    $response = Read-SpectreDecimal -message "How much BYC do you wish to repay?" -precision 3 
    $confirm = Read-SpectreConfirm -Message "Are you sure you want to repay [green]$($response) BYC[/]"
    if($confirm){
        Invoke-CDVaultAction -operation repay -amount ($response | ConvertTo-CatMojo) -submit
        Wait-PendingTransaction
        Show-MyVault
    } else {
        Show-MyVault
    }
}

function Show-CircuitWithdraw {
Clear-Host
    $vault = Get-MyLoanVault    
    $max = ($vault.max_withdraw | ConvertFrom-XchMojo)
    
    "
    
    You have [green]$max XCH[/]  available to withdraw.

    " | Format-SpectrePanel -Header "Circuit Dao - Withdraw" -Expand

    $response = Read-SpectreDecimal -message "How much XCH do you wish to withdraw?" -precision 12
    $confirm = Read-SpectreConfirm -Message "Are you sure you want to withdraw [green]$($response) XCH[/]"
    if($confirm){
        Invoke-CDVaultAction -operation withdraw -amount ($response | ConvertTo-XchMojo) -submit
        Wait-PendingTransaction
        Show-MyVault
    } else {
        Show-MyVault
    }
}

function Start-SageTrader {
    
    
    Clear-Host
    Write-SpectreFigletText -Text "Sage Trader v2" -Color Green -Alignment Center
    $msg = Format-SpectreString("
    Welcome to the new Sage Trader interface! This program works with [green]Sage Wallet RPC[/]
    
    [green]Sage Trader[/] is a terminal interface that can help design different types of bots to provide liquidity to the Chia eco system.

    Join my [SlateBlue3_1]Discord Server[/] for assitance with this program.

    [link=https:/discord.com/invite/7TTSDfSYP2] [DodgerBlue2] XCHPlayground Discord Server [/] [/]
    

        
    ")

    $msg  | Format-SpectrePanel -Header "Home v" -Color Blue -Expand
     
    
    $choices = @(
        [pscustomobject]@{
            Name = "Trading Bots"
            Action = { Show-TradingBotMenu }
        }
        [pscustomobject]@{
            Name = "Circuit Dao Lending"
            Action = { Show-MyVault }
        }
        [PSCustomObject]@{
            Name = "Trade on Dexie"
            Action = { Start-STOfferDex }
        }
        [pscustomobject]@{
            Name = "Check for Update"
            Action = {
                Clear-Host
                Write-SpectreHost -Message "Checking for update..."
                # Get local version
                $localVersion = (Get-InstalledModule -Name "SageTrader").Version

                # Find latest online version
                $onlineVersion = (Find-Module -Name "SageTrader").Version

                if ($onlineVersion -ne $localVersion) {
                    Write-SpectreHost -Message "[green]Update available![/]"
                    
                    Write-SpectreHost -Message "
Type the following command to update:                    


[yellow]Update-Module -name SageTrader[/]

"
                } else {
                    Write-Host "You are up to date."
                    start-sleep 1
                    Start-SageTrader
                }

            }
        }
        [pscustomobject]@{
            Name = "Exit"
            Action = { Write-Host "Exiting..." }
        }
    )

    $choice = Read-SpectreSelection -Choices $choices -Prompt "Select an option:" -ChoiceLabelProperty Name -Color aqua
    &$choice.Action
}

function Start-SageBotJob{
    

    Start-Job -Name "SAGEBOT" -ScriptBlock {
        Import-Module SageTrader
        while($true){
            $bots = [ChiaBot]::all()
            $bots.handle()
            Start-Sleep -Seconds 30
        }
    }
}

function Stop-SageBotJob{
    Get-Job -Name "SAGEBOT" | Stop-Job | Remove-Job
}


function Show-TradingBotMenu{
    Clear-Host
    Write-SpectreFigletText -Text "Trading Bots" -Color Green -Alignment Center
    $choices = @(
        [pscustomobject]@{
            Name = "Create Bot"
            Action = { Show-CreateBot }
        }
        [pscustomobject]@{
            Name = "Manage Bots"
            Action = { Show-ManageBots }
        }
        [pscustomobject]@{
            Name = "Run Bots"
            Action = { Start-Bots }
        }
        [pscustomobject]@{
            Name = "Back"
            Action = { Start-SageTrader }   
        }
    )
    $choice = Read-SpectreSelection -Choices $choices -Prompt "Select an option:" -ChoiceLabelProperty Name -Color aqua
    &$choice.Action
}

function Show-CreateBot{
    $script:botCreationData = [ChiaBot]::new()
    Reset-BotScreen

    "Types of Bots:

[green]Grid Bot:[/] The most common option. This bot has a varies the price of each offer between two prices and is best for providing liqudity for dissimilar tokens.

[green]Stable Bot:[/] Best for tradding across different stable coins [[BYC, wUSDC.b, wUSDC ]].  It is best to set the price to 1 and then add the fee
    " | Format-SpectrePanel -Expand -Color blue


    $choice = Read-SpectreSelection -Choices @(
        [pscustomobject]@{
            Name = "Grid Bot"
            Action = { Show-CreateGridBot }
        }
        [pscustomobject]@{
            Name = "Stable Bot"
            Action = { Show-CreateStableBot }
        }
        [pscustomobject]@{
            Name = "Back"
            Action = { Start-SageTrader }
        }
    ) -Message "What type of bot would you like to create?" -ChoiceLabelProperty Name -Color aqua
    &$choice.Action
}

function Show-CreateStableBot{
    $script:botCreationData.isStableCoinPair = $true
    Show-ContinueCreateBot
}

function Show-CreateGridBot{
    $script:botCreationData.isStableCoinPair = $false
    Show-ContinueCreateBot
}

function Show-ContinueCreateBot{
    "
    Name your bot. This is just for your reference and can be anything you like.
    "  | Format-SpectrePanel -Header "Step 1" -Color Blue -Expand
    $script:botCreationData.name = Read-SpectreText -Message "Enter a name for your bot:"
    Reset-BotScreen
    "
    Choose the token to offer. This should be a token you own and want to trade away.
    "  | Format-SpectrePanel -Header "Step 2" -Color Blue -Expand
    if($Script:botCreationData.isStableCoinPair){
        $stableChoice = @("byc","wusdc.b","wusdc")
        $stableSelected = Read-SpectreSelection -Message "Select the your first stable coin in the pair" -Choices $stableChoice
        $script:botCreationData.offeredToken = (Get-SageToken -id $stableSelected)
        
    } else {
        $script:botCreationData.offeredToken = Select-SageToken
    }
    
    Reset-BotScreen
    "
    Enter the Max Amount of [green]$($script:botCreationData.offeredToken.ticker)[/] available to the Bot.
    " | Format-SpectrePanel -Header "Step 3" -Color Blue -Expand
    Write-SpectreHost -Message "$($Script:botCreationData.offeredToken.ticker) Balance: [yellow]$($script:botCreationData.offeredToken.DisplayBalance())[/]"
    $script:botCreationData.offeredTokenAmount = Read-SpectreDecimal -message "Max amount available to bot:" -precision 12
    Reset-BotScreen
    "
    Now choose the token you want to request in return.
    " | Format-SpectrePanel -Header "Step 4" -Color Blue -Expand
    if($Script:botCreationData.isStableCoinPair){
        $stableChoice = @("byc","wusdc.b","wusdc") | Where-Object {$_ -ne $Script:botCreationData.offeredToken.ticker}
        $stableSelected = Read-SpectreSelection -Message "Select the second stable coin" -Choices $stableChoice
        $script:botCreationData.requestedToken = (Get-SageToken -id $stableSelected)
        
    } else {
        $script:botCreationData.requestedToken = Read-SageToken
    }
    Reset-BotScreen
    "
Enter the [green]Starting price.[/] 

[yellow]INFO: There are two ways to think of price.  The example below explains:[/]

EXAMPLE: 
Offered:   [red]2.5 BYC   [/]
Requested: [green]1 XCH [/]

[Fuchsia]Price[/] : [red]2.5[/] / [green]1[/] = [Fuchsia]2.5[/]
or
[Purple_1]Price[/] : [green]1[/] / [red]2.5[/] = [Purple_1]0.4[/]



If you are offering BYC and Requesting XCH.  
[yellow]You can enter 2.5 as your starting price and 2.0 as your target price to get more XCH in each step.

OR

You can enter 0.4 as your starting price and 0.5 as your target price to get more XCH in each step.
[/]


    " | Format-SpectrePanel -Header "Step 6" -Color Blue -Expand

    if($Script:botCreationData.offeredToken.ticker -eq 'xch'){
        $qa = Get-DexieQuote -from xch -to ($Script:botCreationData.requestedToken.ticker) -from_amount 1000000000000
        $qb = Get-DexieQuote -from ($Script:botCreationData.requestedToken.ticker) -to xch -to_amount 1000000000000
        if($qa.success -and $qb.success){
            if($Script:botCreationData.requestedToken.ticker -eq 'xch') {
                $defaultStart = 1000 / ((($qa.quote.to_amount) + ($qb.quote.from_amount))/2)
            } else {
                $defaultStart = ((($qa.quote.to_amount) + ($qb.quote.from_amount))/2) /1000
            }
                
            Write-SpectreHost "Current Price from dexie is: $defaultStart"
        } else {
            $defaultStart = 0
        }
    }
    if($Script:botCreationData.requestedToken.ticker -eq 'xch'){
        $qa = Get-DexieQuote -from xch -to ($Script:botCreationData.offeredToken.ticker) -from_amount 1000000000000
        $qb = Get-DexieQuote -from ($Script:botCreationData.offeredToken.ticker) -to xch -to_amount 1000000000000
        if($qa.success -and $qb.success){
            if($Script:botCreationData.requestedToken.ticker -eq 'xch') {
                $defaultStart = 1000 / ((($qa.quote.to_amount) + ($qb.quote.from_amount))/2)
            } else {
                $defaultStart = ((($qa.quote.to_amount) + ($qb.quote.from_amount))/2) /1000
            }
                
            Write-SpectreHost "Current Price from dexie is: $defaultStart"
        } else {
            $defaultStart = 0
        }
    }
    

    $Script:botCreationData.startingPrice = Read-SpectreDecimal -message "Starting Price:" -precision 12

    if(-not $script:botCreationData.isStableCoinPair){
        Write-SpectreHost "Starting price is: $($Script:botCreationData.startingPrice) +5% = $($Script:botCreationData.startingPrice * 1.05)"
    $script:botCreationData.targetPrice = Read-SpectreDecimal -message "Target Price:" -precision 12
    Reset-BotScreen
    }
    
    
    
    "
Enter the number of [green]Steps[/] for your bot.

A STEP is a price level in the grid. The more steps you have, the more price levels your bot will have between the starting price and target price.  Each step you will offer [green]Max Offered Amount / Steps[/] of your offered token. 

For example, if you are offering 100 XCH with 20 steps, each step will offer 5 XCH.  If the starting price was 2.5 and target price was 3.0, then your pricing would look like this:
[blue]
Step 1: Offer 5 XCH at 2.5 for 12.5 BYC
Step 2: Offer 5 XCH at 2.525 for 12.625 BYC
Step 3: Offer 5 XCH at 2.55 for 12.75 BYC
...
Step 20: Offer 5 XCH at 3.0 for 15 BYC
[/]

" | Format-SpectrePanel -Header "Step 7" -Color Blue -Expand
    
    $steps = Read-SpectreInt
    $script:botCreationData.addSteps($steps)
    Reset-BotScreen
    $fps = (get-sagekeys).keys

    "
What wallet is authorized to use this bot?
    " | Format-SpectrePanel -Header "Step 8" -Color Blue -Expand

    $fp = (Get-SageKey).key[0].name
Write-SpectreHost -Message "
You are currently logged in with [green]$fp[/]


"
    $fingerprint = Read-SpectreSelection -Message "Select a wallet fingerprint to use for this bot:" -Choices $fps -ChoiceLabelProperty name -Color aqua 
    
    $script:botCreationData.fingerprint = $fingerprint.fingerprint
    Reset-BotScreen
"
This will make a spread between your selling and buying price to ensure you make a profit on the trade.

For example, if you are offering 100 XCH with 20 steps, each step will offer 5 XCH.  If the starting price was 2.5 and target price was 3.0 with a spread of 0.005, then your pricing would look like this:
[blue]
Step 1: Offer 5 XCH at 2.5 for [/][yellow](12.5 BYC * (1 + 0.005))[/][blue] = 12.5625 BYC
Step 2: Offer 5 XCH at 2.525 for [/][yellow](12.625 BYC * (1 + 0.005))[/][blue] = 12.688125 BYC
Step 3: Offer 5 XCH at 2.55 for [/][yellow](12.75 BYC * (1 + 0.005))[/][blue] = 12.81375 BYC
...
Step 20: Offer 5 XCH at 3.0 for [/][yellow](15 BYC * (1 + 0.005))[/][blue] = 15.075 BYC
[/]

But you you are offering BYC and requesting XCH with a Starting Price of 2.5 and a target price of 2.0 with a spread of 0.005, then your pricing would look like this:
[blue]
Step 1: Offer 12.5 BYC for 5 XCH
Step 2: Offer 12.625 BYC for 5 XCH
Step 3: Offer 12.75 BYC for 5 XCH
...
Step 20: Offer 15 BYC for 5 XCH
[/]


    " | Format-SpectrePanel -Header "Step 9" -Color Blue -Expand
    $script:botCreationData.feePercentage = Read-SpectreDecimal -message "Enter the spread you want to set for this bot (e.g. 0.005 for 0.05% fee):" -precision 3
    Reset-BotScreen
    $script:botCreationData.BuildGrid()
    
    Clear-Host
    Write-SpectreFigletText -Text "Review Bot" -Alignment Center -Color green

    "
    Your Grid Bot has been created with the following parameters:
    " | Format-SpectrePanel -Header "Bot Created" -Color Green -Expand
    $script:botCreationData.stats()

    $createbot = Read-SpectreConfirm -Message "Do you wish to save this bot?" 
    if($createbot){
        $script:botCreationData.Save()
        Show-BotManagementMenu -Bot $Script:botCreationData
    } else {

        Start-SageTrader
    }

    
}

function Show-ManageBots{
    Clear-Host
    Write-SpectreFigletText -Text "Manage Bots" -Color Green -Alignment Center
    "
    What bot would you like to manage?
    " | Format-SpectrePanel -Header "Manage Bots" -Color Blue -Expand
    $bots = [ChiaBot]::all()

    $choice = Read-SpectreSelection -Choices $bots -Prompt "Select a bot to manage:" -ChoiceLabelProperty Name -Color aqua
    Show-BotManagementMenu -Bot $choice
}

function Show-BotManagementMenu{
    param($Bot)
    
    Clear-Host
    Write-SpectreFigletText -Text "Manage Bot" -Color Green -Alignment Center
    if($bot){
       
    if(-not $Bot.isActive){
        Write-SpectreHost "[red]Not Active[/]"
    } else {
        Write-SpectreHost "[green]Active[/]"
    }

    if(-not $bot.isPrepped -or -not $bot.isValidated){
        Write-Spectrehost -Message '
[yellow]NOTE:

Prepare Bot:[/] will prep your wallet to run the bot by splitting the coins needed to create the offers and Creating offers in your wallet.

Once finished, please review Sage Wallet to make sure the offers look correct before you continue.

"[yellow]Verify Bot:[/] will send the created offers to dexie"
'
        

    }

    
    if($bot.isPrepped -and $bot.isValidated){
    $bot.stats()
}

    $choices = @(
        [pscustomobject]@{
            Name = $($bot.isActive ? "Deactivate Bot" : "Activate Bot")
            Action = { 
                if($Bot.isActive){
                    $Bot.Deactivate()
                } else {
                    $Bot.Activate()
                }
                Show-BotManagementMenu -Bot $Bot
            }
        }
    )
    if(-not $bot.isValidated -and $bot.isPrepped){
        $choices += [pscustomobject]@{
            Name = "Verify Bot"
            Action = { 
                $confirm = Read-SpectreConfirm -Message "I have checked the offers and everything looks correct to submit?" -DefaultAnswer n
                if($confirm){
                    ($Bot.ValidateBot())
                }
                Show-BotManagementMenu -Bot $Bot
            }
        }
    }

    if(-not $bot.isPrepped){
        $choices += [pscustomobject]@{
            Name = "Prepare Bot"
            Action = { 
                if($Bot.isPrepped){
                    Write-SpectreHost -Message "Bot is already prepped." 
                    Start-Sleep -Seconds 2
                    Show-BotManagementMenu -Bot $Bot
                } else {
                    $Bot.prepCoins()
                    while($true){
                        Write-SpectreHost "[yellow]Transaction is PENDING please wait[/]"
                        $transaction = Invoke-SageRPC -endpoint get_pending_transactions -json @{}
                        if($transaction.transactions.count -eq 0){
                            break 
                        }   
                        start-sleep 10
                        }
                    $Bot.makeInitialOffers()
                    Show-BotManagementMenu -Bot $Bot
                }
            }
        }
    }
    
    $choices += [pscustomobject]@{
        Name = "Delete Bot"
        Action = { 
            $confirm = Read-SpectreConfirm -Message "Are you sure you want to delete this bot? This action cannot be undone." 
            if($confirm){
                $Bot.destroy()
                Show-ManageBots
            } else {
                Show-BotManagementMenu -Bot $Bot
            }
        }
    }
    $choices += [pscustomobject]@{
        Name = "Back"
        Action = { Show-TradingBotMenu }
    }

    $choice = Read-SpectreSelection -Choices $choices -Prompt "Select an option:" -ChoiceLabelProperty Name -Color aqua
    &$choice.Action
 } else {
     Write-SpectreHost "No bots available.  Please create a bot"
     start-sleep 1
     Show-TradingBotMenu
        
    }
 

}


function Read-SpectreDecimal {
    param(
        $message = "Enter a decimal number:",
        $defaultAnswer = $null,
        $precision =3
    )
    if($defaultAnswer){
        $decimal = Read-SpectreText -Message $message -DefaultAnswer $defaultAnswer    
    }
    $decimal = Read-SpectreText -Message $message
    if ([decimal]::TryParse($decimal, [ref]$null)) {
        return [math]::Round([decimal]$decimal, $precision)
    } else {
        Write-SpectreHost -Message "Invalid input. Please enter a valid decimal number." 
        Read-SpectreDecimal
    }
}

function Read-SpectreInt {
    $int = Read-SpectreText -Message "Enter a whole number:"
    if ([int]::TryParse($int, [ref]$null)) {
        return [int]$int
    } else {
        Write-SpectreHost -Message "Invalid input. Please enter a valid whole number." 
        Read-SpectreInt
    }
}

function Reset-BotScreen{
    Clear-Host
    Write-SpectreFigletText -Text "Create Bot" -Color Green -Alignment Center
   
}


function Read-SageToken{
    $choice = Read-SpectreText -Message "Enter token ticker or id (e.g. byc, wusdc, etc):" 
    try {
        $token = Get-SageToken -id $choice
    if(-not $token){
            Write-SpectreHost -Message "Token not found. Please try again." 
            return Read-SageToken
        } else {
        
            
            $confirm = Read-SpectreConfirm -Message "You chose ([green]$($token.ticker)[/] - [yellow]$($token.asset_id)[/]). Is this correct?" 
            if($confirm){
                return $token
            } else {
                return Read-SageToken
            }
            
        }
    } catch {
        Write-SpectreHost -Message "Error: $_. Please try again." 
        return Read-SageToken
    }

}

function Select-SageToken{
    $tokens = @()
    $tokens += (Get-Sagetoken -id 'xch')
    ((Get-SageCats).cats) | Sort-object -Property ticker | ForEach-Object {
        if($_.visible -and $_.ticker -ne "" -and $_.balance -gt 0){
            $tokens += (Get-SageToken -id $_.asset_id)
        }
        
    }
    $tokens = $tokens | Where-Object {$_.ticker -ne ''}
    $choice = Read-SpectreSelection -Choices $tokens -Prompt "Select a token:" -ChoiceLabelProperty ticker -Color aqua
    return $choice
}

function Format-SpectreString([string]$string){
    $process = $string.Split("`n")
    return ($process | ForEach-Object {$_.Trim()}) -join "`n"   
}


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
    [bool]$isValidated
    [array]$pendingCreateOffers
    [array]$addresses
    [datetime]$lastHandled
    [datetime]$LastTradedAt

    ChiaBot(){
        $this.id = (New-Guid).Guid
        $this.isActive = $false
        $this.isPrepped = $false
        $this.isValidated = $false
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
                    #$this.updateLogOffer($active.offer_id,"completed")
                    
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
            'Name' = $this.name
            'Offered Token' = $this.offeredToken.ticker
            'Requested Token' = $this.requestedToken.ticker
            'Is Active' = $this.isActive
            'Offered Amount' = ($this.offeredTokenAmount)
            'Starting Price' = $this.startingPrice
            'Target Price' = $this.targetPrice
            'Steps' = $this.steps
            'Active Offers' = $this.activeOffers.Count
            'Completed Offers' = $this.completedOffers.Count
            'Pending Offers' = $this.pendingCreateOffers.Count
            'Last Checked' = $this.lastHandled
            'Last Traded' = $this.LastTradedAt
            
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
        if($props.isValidated){
            $this.isValidated = $props.isValidated
        } else {
            if($this.activeOffers.count -gt 0)
            {
                $this.isValidated = $true
            } else {
                $this.isValidated = $false
            }
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
        if($props.lastHandled){
            $this.lastHandled = (Get-Date $props.lastHandled)
        }
        if($props.LastTradedAt){
            $this.LastTradedAt = (Get-Date $props.LastTradedAt)
        }     
        
        
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
        
        if($check){
            
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
            if($this.isValidated){
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

    }
    
    [void]ValidateBot(){
        $this.activeOffers | ForEach-Object {
            $offer = get-sageoffer -offer_id $_.offer_id
            $dexie = Submit-DexieOffer -offer $offer.offer -claim_rewards

            if(-not $null -eq $dexie){
                Write-SpectreHost -Message "[green]Offer [/][blue] - $($dexie.id) - [/][green] submitted to Dexie successfully.[/]"                
                
            }
        }
        $this.isValidated = $true
        $this.save()
    }

    CancelOffers(){
        try {
            if($this.isLoggedIn()){
            $this.activeOffers | ForEach-Object {
            
                $offer_id = $_.offer_id
                #$this.updateLogOffer($offer_id,"cancelled")
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
                    $tPrice = [System.Math]::Round($this.targetPrice - ($step_size * $i),12)
                    [UInt64]$requested_amount = (($step_amount /$tprice)* [System.Math]::Pow(10,($this.requestedToken.precision)))
                } else {
                    $tPrice = [System.Math]::Round($this.startingPrice + ($step_size * $i),12)
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

function Get-ChiaBots{
    return [ChiaBot]::All()
}

function Start-Bots{
    $run = $true
    while($run){
        clear-host  
        Write-SpectreFigletText -Text "SageTrader is Running" -Color Green -Alignment Center
        $data = @()
        $bots = [ChiaBot]::All()
        foreach($bot in $bots){
            if($bot.isActive){
                $data += $bot.stats()    
                $bot.Handle()
            }
        }
        $data | Format-SpectreTable
        $key = Read-SpectreText -Message "
        [gray]Screen will refresh every 60 seconds.[/]
        Press [yellow]Q[/] to quit or any other key to refresh." -TimeoutSeconds 60
        if($key -eq "Q" -or $key -eq "q"){
            $run = $false
        }
    }
    Start-SageTrader
    
}

function Remove-AllBots(){
    $confirm = Read-SpectreConfirm -Message "Are you sure you want to delete all bot files?"
    if($confirm){
        $bot = [ChiaBot]::new()
        $path = $bot.path()
        $items = Get-ChildItem -Path $path -Filter *.json -Recurse
        $items | Remove-Item -Force
        Write-SpectreHost -Message "Deleted files $($items.FullName)"
    } else {
        Write-SpectreHost -Message "No files deleted"
    }
    
    
}

Export-ModuleMember -Function Start-SageTrader, Get-ChiaBots, Start-Bots
