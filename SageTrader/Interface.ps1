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
            Name = "Create Bot"
            Action = { Show-CreateBot }
        }
        [pscustomobject]@{
            Name = "View Bots"
            Action = { Write-Host "View Bots selected" }
        }
    )

    $choice = Read-SpectreSelection -Choices $choices -Prompt "Select an option:" -ChoiceLabelProperty Name -Color aqua
    &$choice.Action
}

function Show-CreateBot{
    $script:botCreationData = [ChiaBot]::new()
    Clear-Host
    Write-SpectreFigletText -Text "Create Bot" -Color Green -Alignment Center
    Write-SpectreRule -LineColor green
    
    Start-SageTrader
}

function Show-FunctionKeys{
     New-SpectreGridRow -Data @("[green]F1:[/] Help","[green]F2:[/] Create Bot","[green]F3:[/] View Bots","[green]F4:[/] View Offers","[green]F5:[/] Refresh") | Format-SpectreGrid | Format-SpectrePanel -Height 4 -Width ($Host.UI.RawUI.WindowSize.Width -2) -Color grey
}

function Show-HomeScreen{

}


function Format-SpectreString([string]$string){
    $process = $string.Split("`n")
    return ($process | ForEach-Object {$_.Trim()}) -join "`n"   
}
