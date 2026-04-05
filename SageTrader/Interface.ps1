. .\SageTrader\GridBot.ps1

function Start-SageTrader {
    Clear-Host
    Write-SpectreFigletText -Text "Sage Trader v2" -Color Green -Alignment Center
    Write-SpectreRule -LineColor green
    $panel1 = "Welcome to the new and improved Sage Trader!" 
    $panel2 = [ChiaBot]::AllStats() | Format-SpectreTable -Expand -Color red
    $row1 = New-SpectreLayout -Name "Main" -Columns @($panel1,$panel2)
    
    $layout = New-SpectreLayout -Name "MainLayout" -Rows @($row1) -Ratio 1
    $layout | Out-SpectreHost
    
    $choices = @(
        [pscustomobject]@{
            Name = "Trading Bots"
            Action = { Show-CreateBot }
        }
        [pscustomobject]@{
            Name = "Circuit Dao"
            Action = { Write-Host "Circuit Dao selected" }
        }
        [pscustomobject]@{
            Name = "Exit"
            Action = { Write-Host "Exiting..."; exit }
        }
    )

    $choice = Read-SpectreSelection -Choices $choices -Prompt "Select an option:" -ChoiceLabelProperty Name -Color aqua
    &$choice.Action
}

function Start-SageBotJob{
    

    Start-Job -Name "SAGEBOT" -ScriptBlock {
        . /home/aaron/git/PSSageTrader/SageTrader/GridBot.ps1
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

function Show-CreateBot{
    $script:botCreationData = [ChiaBot]::new()
    Reset-BotScreen
    $message = Format-SpectreString("
    
    Types of bots:

    [green]Grid Bot[/] - Buys and sells between a price range with a specified number of trades in that range. 
    If selecting this bot, you will start with choosing a token you own and then the token you want.  You sent the starting price 
    which is usually the current price. Then you set the target price you want to trade to. 

    [grey]Example 1: If you Offer XCH and Request BYC with a starting price of 2.5 and target price of 3.0, you will sell your XCH for BYC.  
    Each Step will sell an equal amount of XCH until you reach your max allowed XCH to sell. [/]
    
    [green]Stable Bot[/] - This bot simply makes a spread around the current price. 

    [grey]Example 2: If you Offer USDC and Request BYC with a spread of 0.003, you'll create offers that request 0.003% more than you offer in each direction of the trade.[/]
    
    " )

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
    $script:botCreationData.name = Read-SpectreText -Message "Enter a name for your bot:"
    Reset-BotScreen
    Write-SpectreHost -Message "Choose the token to offer. This should be a token you own and want to trade away." 
    $script:botCreationData.offeredToken = Select-SageToken
    Reset-BotScreen
    Write-SpectreHost -Message "Enter the amount of [green]$($script:botCreationData.offeredToken.ticker)[/] you want to offer. (up to 2 decimal places, e.g. 100.00)"
    Write-SpectreHost -Message "$($Script:botCreationData.offeredToken.ticker) Balance: [yellow]$($script:botCreationData.offeredToken.DisplayBalance())[/]"
    $script:botCreationData.offeredTokenAmount = Read-SpectreDecimal
    Reset-BotScreen
    Write-SpectreHost -Message "Now choose the token you want to request in return." 
    $script:botCreationData.requestedToken = Read-SageToken
    Reset-BotScreen
    Write-SpectreHost -Message "Enter the [green]Starting price.[/]" 
    $script:botCreationData.startingPrice = Read-SpectreDecimal
    Reset-BotScreen
    if(-not $script:botCreationData.isStableCoinPair){
        Write-SpectreHost -Message "Enter the [green]Target Price.[/]" 
        $script:botCreationData.targetPrice = Read-SpectreDecimal
        Reset-BotScreen
    }
    Write-SpectreHost -Message "Enter the number of [green]Steps[/] for your bot."
    $steps = Read-SpectreInt
    $script:botCreationData.addSteps($steps)
    Reset-BotScreen
    $fps = (get-sagekeys).keys
    $fingerprint = Read-SpectreSelection -Message "Select a wallet fingerprint to use for this bot:" -Choices $fps -ChoiceLabelProperty fingerprint -Color aqua
    
    $script:botCreationData.fingerprint = $fingerprint.fingerprint
    Reset-BotScreen
    Write-SpectreHost -Message "Enter the spread you want to set for this bot (e.g. 0.005 for 0.05% fee):"
    $script:botCreationData.feePercentage = Read-SpectreDecimal
    Reset-BotScreen
    $script:botCreationData.BuildGrid()
    $script:botCreationData.Save()
    
    Write-SpectreHost -Message "Your Grid Bot has been created with the following parameters:" 
    $script:botCreationData.stats()
    
    Show-ManageBots
}

function Read-SpectreDecimal {
    $decimal = Read-SpectreText -Message "Enter a decimal number:"
    if ([decimal]::TryParse($decimal, [ref]$null)) {
        return [math]::Round([decimal]$decimal, 2)
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
    Write-SpectreRule -LineColor green

    
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
            if($confirm -eq "y"){
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
        $tokens += ($_)
    }
    $choice = Read-SpectreSelection -Choices $tokens -Prompt "Select a token:" -ChoiceLabelProperty ticker -Color aqua
    return $choice
}

function Format-SpectreString([string]$string){
    $process = $string.Split("`n")
    return ($process | ForEach-Object {$_.Trim()}) -join "`n"   
}
