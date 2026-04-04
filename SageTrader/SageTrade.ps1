using namespace Terminal.Gui
$module = (Get-Module Microsoft.PowerShell.ConsoleGuiTools -List).ModuleBase
Add-Type -Path (Join-path $module Terminal.Gui.dll)


function New-AppWindow{
    param(
        [string]$Title
        )
    $Window = [Window]::new()
    $Window.Title = $Title
    $Window.Height = [Dim]::Fill()
    $Window.Width = [Dim]::Fill()

    return $Window
}

function Get-MenuBar{
    $CircuitItem = [MenuItem]::new("_Circuit Vaults", "", {  Show-CircuitVault -VaultName 1de27bd3aefa5be386397de8478e0ecb50a53a3fa9b5fc828d1a3de3eec12849})
    $MenuItem = [MenuItem]::new("_About", "", { Show-ConfirmationBox -Title "About Sage Trader" -Message "Sage Trader is a terminal-based trading application built with PowerShell and Terminal.Gui. Created by The Mayor" -AffirmTitle "OK" })
    $MenuItemA = [MenuItem]::new("_Connect Sage", "", { Show-ConfirmationBox -Title "Connect Sage" -Message "Checking connection..." -AffirmTitle "yes" -DenyTitle "no" })
    $MenuItemB = [MenuItem]::new("_Exit", "", { [Application]::RequestStop() })
    $MenuBarItem = [MenuBarItem]::new("_File", @($MenuItem, $MenuItemA, $MenuItemB, $CircuitItem))
    return [MenuBar]::new(@($MenuBarItem))
}

function Show-MainWindow{

    $Window = New-AppWindow -Title "Sage Trader"

    $MenuBar = Get-MenuBar

    $Window.Add($MenuBar)

    [Application]::Top.Add($window)
    
}

function Show-CircuitVault {
    param(
        [string]$VaultName
    )
    $vault = Get-CDVault -vault $VaultName
    if (-not $vault) {
        Show-ConfirmationBox -Title "Vault Not Found" -Message "No vault found with the name '$($VaultName)'" -AffirmTitle "OK" -Callback {Show-MainWindow}
    }

    $window = New-AppWindow -Title "Vault: $($VaultName)"
    
    $list = [System.Collections.Generic.List[object]]::new()
    

    $vault.collateral = $vault.collateral / 1e12
    $vault.principal = $vault.principal / 1e3
    $vault.stability_fees = $vault.stability_fees / 1e3
    $vault.debt_owed_to_vault = $vault.debt_owed_to_vault / 1e3
    $vault.max_withdraw = $vault.max_withdraw / 1e12
    $vault.debt = $vault.debt / 1e3
    $vault.max_borrow = $vault.max_borrow / 1e3
    $vault.max_repay = $vault.max_repay / 1e3
    $list.Add("Collateral: $($vault.collateral)")
    $list.Add("Principal: $($vault.principal)")
    $list.Add("Stability Fees: $($vault.stability_fees)")
    $list.Add("Debt Owed to Vault: $($vault.debt_owed_to_vault)")
    $list.Add("Max Withdraw: $($vault.max_withdraw)")
    $list.Add("Debt: $($vault.debt)")
    $list.Add("Max Borrow: $($vault.max_borrow)")
    $list.Add("Max Repay: $($vault.max_repay)") 
    
    
    $ListView = [ListView]::new()
    $ListView.x = 2
    $ListView.Y = 2
    $listView.Width = [Dim]::Fill()
    $ListView.Height = [Dim]::Fill()
    $ListView.SetSource($list)
    $frame = [FrameView]::new()
    
    $frame.Width = [Dim]::Percent(35)
    $frame.Height = [Dim]::Fill()
    $frame.add($ListView)
    
    $window.Add($frame)
    

    [Application]::Top.Add($window)


}




function Show-ConfirmationBox {
    param(
        [string]$Title,
        [string]$Message,
        [string]$AffirmTitle = "OK",
        [string]$DenyTitle = "Cancel",
        [scriptblock]$Callback
    )

    $result = [MessageBox]::Query($Title, $Message, @($AffirmTitle, $DenyTitle)) 
    if ($result -eq 0) {
        if ($Callback) {
            & $Callback
        }
    }

}

function Start-SageTerminal {

    [Application]::Init()
    [Application]::QuitKey = 27
    
    Show-MainWindow
    
    
    [Application]::Run()

    # This makes it so it actually closes
    [Application]::Shutdown()
}

Start-SageTerminal

