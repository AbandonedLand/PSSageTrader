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

function New-ChiaSilentBot{

    $bot = [SilentBot]::new()

    
    Write-SpectreFigletText -Text SilentBot -Alignment Center -Color green -PassThru | Out-SpectreHost
   
"
A SilentBot will trade a Cat token against XCH by using market orders on dexie.

This bot uses the same formula as Uniswap V3.
(x virtual + x real)(y virtual + y real) = liquidity^2

This is a simpler bot because it does not require as much coin management as the grid bot.
" | Format-SpectrePadded -Padding 1 |Format-SpectrePanel -Header "SilentBot" -Border Square -Color blue -Expand | Out-Spectrehost


$bot.token_x = Get-sagetoken -id xch

$token_y = Select-SageToken

# return if none selected
if(-not $token_y){
    return
} else {
    $bot.token_y = $token_y
}
$p = Invoke-SpectreCommandWithStatus -Spinner Aesthetic -Title "Fetching Current Price" -ScriptBlock {
    
    $fromy = Get-DexieQuote -from $token_y.asset_id -to 'xch' -from_amount 1000 
    $p1 = ($fromy.quote.from_amount /1000) / ( $fromy.quote.to_amount / 1000000000000)
    $toy = Get-DexieQuote -from 'xch' -to $token_y.asset_id -from_amount 1000000000000
    $p2 = ($toy.quote.to_amount /1000) / ( $toy.quote.from_amount / 1000000000000)
    $avg_price = [math]::Round(($p1 + $p2) / 2, 3)
    return @{avg_price = $avg_price}

} 
$price = Get-SpectreNumber -message "Enter the current price of $($bot.token_y.ticker) in XCH" -DefaultAnswer ($p.avg_price) -numberOfDecimals 3


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
[yellow]Max assignable is $($bot.token_y.DisplayBalance()) $($bot.token_y.ticker)[/]
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

function Start-Bots{
    $run = $true
    while($run){
        clear-host  
        Write-SpectreFigletText -Text "SageTrader is Running" -Color Green -Alignment Center
        $data = @()
        $bots = @()
        [ChiaBot]::All() | ForEach-Object {
            $bots += $_
        }
        [SilentBot]::All() | ForEach-Object {
            $bots += $_
        }
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


class SilentBot {
    [string]$id
    [string]$fingerprint
    [string]$name
    $token_x
    $token_y
    [decimal]$pa # Mininum Price
    [decimal]$pb # Maximum Price
    [decimal]$spread_percentage 
    [boolean]$x_is_spread_token  = $true
    [boolean]$x_is_default = $true
    [boolean]$invert_price = $false
    [decimal]$starting_x_amount
    [decimal]$starting_y_amount
    [decimal]$xv
    [decimal]$yv
    [decimal]$xr
    [decimal]$yr 
    [decimal]$liquidity_squared
    [decimal]$liquidity
    [decimal]$fee_accumulated = 0
    [array]$attempts = @()
    [array]$trades = @()
    [bool]$active


    SilentBot(){
        $this.id = (New-Guid).Guid
        $this.active = $false
    }
    
    SilentBot([PSCustomobject]$props){
        $this.Init([PSCustomObject]$props)    
    }

    [void] Init([PSCustomobject]$props)  {
        $this.id = $props.id
        if($props.token_x){
            $this.token_x = (Get-SageToken -id ($props.token_x.ticker))
        }
        if($props.token_y){
            $this.token_y = (Get-SageToken -id ($props.token_y.ticker))
        }
        $this.name = $props.name
        $this.fingerprint = $props.fingerprint
        $this.pa = $props.pa
        $this.pb = $props.pb
        $this.starting_x_amount = $props.starting_x_amount
        $this.starting_y_amount = $props.starting_y_amount
        $this.spread_percentage = $props.spread_percentage
        $this.x_is_spread_token  = $props.x_is_spread_token    
        $this.x_is_default = $props.x_is_default
        $this.invert_price = $props.invert_price
        $this.xv = $props.xv
        $this.yv = $props.yv
        $this.xr = $props.xr
        $this.yr = $props.yr
        $this.liquidity_squared = $props.liquidity_squared
        $this.liquidity = $props.liquidity
        $this.fee_accumulated = $props.fee_accumulated
        $this.attempts = $props.attempts
        $this.trades = $props.trades
        $this.active = $props.active
    

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
2. Destroy Bot

9. Back to main menu
[/]

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
        2 {$this.destroy()
            $choice = 9
        }
        }}until ($choice -eq 9)
        
        (Show-Screen -name Home)
    }

    [void] deactivate(){
        $this.active = $false
        $this.save()
    }

    

    [void] destroy(){
        $path = Get-SageTraderPath("SilentBots")
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

    [void] activate(){
       
        $this.active = $true
        $this.save()
    }

    [void] GetQuoteToXCH($amount){
        if($this.yr -gt 0){
            $try = $this.Adjust_X_Amount($amount)
            if($try.newyr -gt 0){
                $dq = Get-DexieQuote -from ($this.token_y.ticker) -to xch -to_amount ($try.dx | ConvertTo-XchMojo)
                $y_bonus =($dq.quote.from_amount) - ([Math]::Abs(($try.dy | ConvertTo-catMojo)) )
                if(($dq.quote.from_amount) -le ([Math]::Abs(($try.dy | ConvertTo-catMojo)) )){
                    $offer = Build-SageOffer
                    $offer.requestXch(($dq.quote.to_amount))
                    $offer.offercat(($this.token_y.asset_id),([Math]::Abs($try.dy) | ConvertTo-CatMojo))
                    $offer.createoffer()
                    $this.attempts += @{
                        fee_available = ($try.fee | ConvertTo-XchMojo)
                        offer = ($offer)
                        buildStructure = $try
                        submitted = $false
                    }     
                    $this.save()                                   
                } else {
                    Write-Host "Should not take trade ( $($dq.quote.from_amount) is > $([Math]::Abs(($try.dy | ConvertTo-catMojo))))"
                }
            } else {
                Write-Host "Not enough $($this.token_y.ticker) available to take trade"
            }
        } else {
            Write-Host "Not enough $($this.token_y.ticker) available to take trade"
        }
    }

    [void] GetQuoteFromXCH($amount){
        if($this.xr -gt 0){
            $try = $this.Adjust_X_Amount(-$amount)
            if($try.newxr -gt 0){
                $dq = Get-DexieQuote -from xch -to ($this.token_y.ticker) -to_amount ($try.dy | ConvertTo-CatMojo)
                if(($dq.quote.from_amount) -le ([Math]::Abs(($try.dx | ConvertTo-xchMojo)) )){
                    $offer = Build-SageOffer
                    $offer.offerXch(($dq.quote.from_amount))
                    $offer.requestCat(($this.token_y.asset_id),($try.dy | ConvertTo-CatMojo))
                    $offer.createoffer()
                    $this.attempts += @{
                        fee_available = (([Math]::Abs(($try.dx))|  ConvertTo-XchMojo)-($dq.quote.from_amount ))
                        offer = ($offer)
                        buildStructure = $try
                        submitted = $false
                    }     
                    $this.save()                                   
                } else {
                    Write-Host "Should not take trade ( $($dq.quote.from_amount) is > $([Math]::Abs(($try.dx | ConvertTo-xchMojo))))"
                }
            } else {
                Write-Host "Not enough XCH available to take trade"
            }
        } else {
            Write-Host "Not enough XCH available to take trade"
        }
    }

    [void]SubmitAttempt(){
        
        $submit = Submit-DexieSwap -offer ($this.attempts[0].offer.offer_data.offer)
        
        if($submit.success){
            Write-Host "Submitted to DexieSwap"
            $this.attempts[0].submitted = $true
            $this.save()
        } else {
            Write-Host "Failed to submit to DexieSwap"
        }
        
    }


    [void]CheckOffer(){
            $offer_id = $this.attempts[0].offer.offer_data.offer_id
            $offer = get-sageoffer -offer_id $offer_id
            if($offer.status -eq 'completed'){
                 $this.trades += ($this.attempts[0])
            $this.fee_accumulated += ($this.attempts[0].fee_available)
            $this.xr = $this.attempts[0].buildStructure.newxr
            $this.yr = $this.attempts[0].buildStructure.newyr
            $this.attempts = @()
            $this.save()
            }
           
    }

    [void] Handle(){
        

        if($this.attempts.count -eq 0){
            $this.GetQuoteFromXCH(0.5)
            
        }
        if($this.attempts.count -eq 0){
            $this.GetQuoteToXCH(0.5)
        }

        if($this.attempts.count -eq 1 ){
            $this.CheckOffer()
            $this.SubmitAttempt()
        }
        $sleep = (Get-Random -Minimum 60 -Maximum 300)
        Write-SpectreHost -Message "
Name: $($this.name)
XCH : $($this.xr)
$($this.token_y.ticker): $($this.yr)
------------------------------------
Fees: $($this.fee_accumulated / 1000000000000)
Trades: $($this.trades.count)
------------------------------------

Sleeping for $sleep
        "
        
        start-sleep $sleep
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

    [decimal]Calculate_yv(){
        return ($this.liquidity * ([math]::Sqrt($this.pa)))
    }

    [decimal]Calculate_xv(){
        return ($this.liquidity / ([math]::Sqrt($this.pb)))
    }

    [void]save(){
        $path = Get-SageTraderPath("SilentBots")
        $file = Join-Path -Path $path -ChildPath "$($this.id).json"
        $this | ConvertTo-Json -Depth 20 | Out-File -FilePath $file -Encoding utf8
    }


    [void]Starting_Token_Amount($amount){
        if($this.xv -or $this.yv -or $this.xr -or $this.yr -or $this.liquidity -or $this.liquidity_squared){
            throw "Starting_Token_Amount can only be called once per instance."
        }
        if($this.x_is_default){
            $this.xr = $amount
            $solve = $amount / ((1/[math]::Sqrt($this.pa))-(1/[math]::Sqrt($this.pb)))
            $this.liquidity = $solve
            $this.liquidity_squared = $solve * $solve
            $this.xv = $this.Calculate_xv()
            $this.yv = $this.Calculate_yv()
            
        } else {
            $solve = $amount / (([math]::Sqrt($this.pb))-([math]::Sqrt($this.pa)))
            $this.yr = $amount
            $this.liquidity = $solve
            $this.liquidity_squared = $solve * $solve
            $this.xv = $this.Calculate_xv()
            $this.yv = $this.Calculate_yv()
            
        }
    }

    [decimal]Get_Price(){
        if($this.invert_price){
            $price = ($this.xv + $this.xr) / ($this.yv + $this.yr)
        } else {
            $price = ($this.yv + $this.yr) / ($this.xv + $this.xr)
        }
        return [math]::Round($price,3)
    }

    static [array]All(){
        $path = Get-SageTraderPath("SilentBots")
        if(-not (Test-Path -Path $path)){
            return @()
        }
        $files = Get-ChildItem -Path $path -Filter *.json
        $bots = @()
        foreach($file in $files){
            $content = Get-Content -Path $file.FullName -Raw
            $json = ConvertFrom-Json -InputObject $content
            $bot = [SilentBot]::new($json)
            $bots += $bot
        }
        return $bots
    }

    
    [ordered]Adjust_X_Amount([decimal]$amount){
        $_xr = $this.xr 
        $newxr = $_xr + $amount
        $_xv = $this.xv
        $_yv = $this.yv
        $_yr = $this.yr
        $_y = $this.liquidity_squared / ($newxr + $_xv)
        $newyr = [math]::round($_y - $_yv,3)
        
        if($this.x_is_spread_token){
            $fee_token = $this.token_x.ticker
            $dy = $newyr - $_yr
            $_fee = [math]::Abs([math]::Round($amount * ($this.spread_percentage / 2),12))
            if($amount -lt 0){
                $dx = $amount + $_fee
            } else {
                $dx = $amount + $_fee
            }
        } else {
            $fee_token = $this.token_y.ticker
            $dx = $newxr - $_xr
            $_fee = [math]::Abs([math]::Round(($newyr - $_yr) * ($this.spread_percentage / 2),12))
            if($amount -lt 0){
                $dy = $newyr - $_yr + $_fee
            } else {
                $dy = $newyr - $_yr + $_fee
            }
            
        }


        $trade = [ordered]@{
            'price' = [math]::Round(([math]::Abs($dy) / [math]::Abs($dx)),3)
            'fee_token' = $fee_token
            'fee' = ([math]::Abs($_fee))
            'newyr' = $newyr
            'newxr' = $newxr
            'amount' = $amount
            'yr' = $_yr
            'xr' = $_xr
            'dx' = $dx
            'dy' = $dy
        }

        return $trade
        
    }

    [ordered]Adjust_Y_Amount([decimal]$amount){
        $_yr = $this.yr 
        $newyr = $_yr + $amount
        $_xv = $this.xv
        $_yv = $this.yv
        $_xr = $this.xr
        $_x = $this.liquidity_squared / ($newyr + $_yv)
        $newxr = [math]::round($_x - $_xv,12)
        if(-not $this.x_is_spread_token){
            
            $fee_token = $this.token_y.ticker
            $dx = $newxr - $_xr
            $_fee = [math]::Abs([math]::Round($dx * ($this.spread_percentage / 2),3))
            if($amount -lt 0){
                $dy = $amount + $_fee
            } else {
                $dy = $amount + $_fee
            }
        } else {
            $fee_token = $this.token_x.ticker
            $dy = $newyr - $_yr
            $_fee = [math]::Abs([math]::Round(($newxr - $_xr) * ($this.spread_percentage / 2),3))
            if($amount -lt 0){
                $dx = $newxr - $_xr - $_fee
            } else {
                $dx = $newxr - $_xr - $_fee
            }
            
        }


        $trade = [ordered]@{
            'price' = [math]::Round(([math]::Abs($dy) / [math]::Abs($dx)),3)
            'fee_token' = $fee_token
            'fee' = ([math]::Abs($_fee))
            'newyr' = $newyr
            'newxr' = $newxr
            'amount' = $amount
            'yr' = $_yr
            'xr' = $_xr
            'dx' = $dx
            'dy' = $dy
            
        }

        return $trade
        
    }

    [PSCustomObject]Swap_From_X([decimal]$amount){
        $from = $this.token_x.ticker
        $to = $this.token_y.ticker
        $from_amount = [math]::round(($amount * [math]::Pow(10, $this.token_x.precision)),0)
        
        return Get-DexieQuote -from $from -to $to -from_amount $from_amount
        
    }

}

function Get-SageTraderPath($subfolder){
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

function Get-SilentBots{
    return [SilentBot]::All()
}

Export-ModuleMember -Function Start-SageTrader, Get-ChiaBots, Start-Bots
