using namespace Terminal.Gui

if(-not $(Get-Module -Name Microsoft.PowerShell.ConsoleGuiTools -ListAvailable)) {
    Install-Module -Name Microsoft.PowerShell.ConsoleGuiTools
}

Import-Module Microsoft.PowerShell.ConsoleGuiTools 
$module = (Get-Module Microsoft.PowerShell.ConsoleGuiTools -List).ModuleBase
Add-Type -Path (Join-path $module Terminal.Gui.dll)

function New-MenuItem {
    param (
        [string]$Title,
        [string]$Description,
        [ScriptBlock]$Actionq
    )
    return [MenuItem]::new($Title, $Description, $Action)
}

Function New-StatusBarItem {
    param(
        [string]$Key,
        [string]$Title,
        [scriptblock]$Action
    )
    return [StatusItem]::new($Key, $Title, $Action)
}

function New-StatusBar {
    param(
        [array]$Items
    )
    return [StatusBar]::new($Items)
}

$assets = get-content -Path 'assets.json' | ConvertFrom-Json
$cats = @()

foreach ($cat in $assets.PSObject.Properties) {
    $cats += $cat.Name
    $cats += $cat.Value.id
}



# Initialize the application.
[Application]::Init()


$ColorScheme = [ColorScheme]::new()
$ColorScheme.Normal = [Terminal.Gui.Attribute]::new([Terminal.Gui.Color]::Blue, [Terminal.Gui.Color]::Black)
$ColorScheme.Focus = [Terminal.Gui.Attribute]::new([Terminal.Gui.Color]::Magenta, [Terminal.Gui.Color]::DarkGray)
$ColorScheme.HotNormal = [Terminal.Gui.Attribute]::new([Terminal.Gui.Color]::Cyan, [Terminal.Gui.Color]::Black)
$ColorScheme.Disabled = [Terminal.Gui.Attribute]::new([Terminal.Gui.Color]::DarkGray, [Terminal.Gui.Color]::Black)

$BTNColorScheme = [ColorScheme]::new()
$BTNColorScheme.Normal = [Terminal.Gui.Attribute]::new([Terminal.Gui.Color]::Blue, [Terminal.Gui.Color]::Black)
$BTNColorScheme.Focus = [Terminal.Gui.Attribute]::new([Terminal.Gui.Color]::Blue, [Terminal.Gui.Color]::Blue)
$BTNColorScheme.HotNormal = [Terminal.Gui.Attribute]::new([Terminal.Gui.Color]::BrightBlue, [Terminal.Gui.Color]::Black)
$BTNColorScheme.Disabled = [Terminal.Gui.Attribute]::new([Terminal.Gui.Color]::DarkGray, [Terminal.Gui.Color]::Black)
$BTNColorScheme.HotFocus = [Terminal.Gui.Attribute]::new([Terminal.Gui.Color]::White, [Terminal.Gui.Color]::BrightBlue)

# Main Window
$win_home = [Window] @{
    Title = "Sage Trader View"
    ColorScheme = $ColorScheme  
}





$MB = New-StatusBar -Items @(
    (New-StatusBarItem -Key h -Title "~H~ome" -Action {
        [Application]::Top.Add($win_home)
    })
    (New-StatusBarItem -Key d -Title "~D~exie.swap" -Action {
        [Application]::Top.Remove($win_home)
        [Application]::Top.Add($win_dexieswap)
    })
)

 

### DEXIE ###
$win_dexieswap = [Window] @{
}
$win_dexieswap.Border.BorderStyle = 'None'
$win_dexieswap.ColorScheme = $ColorScheme
$frm1 = [Terminal.Gui.FrameView] @{
    Title = "Dexie Swap"
    X = 0
    Y = 0
    Width = [Terminal.Gui.Dim]::Percent(50)
    Height = [Terminal.Gui.Dim]::Fill()
}

$frm1.ColorScheme = $ColorScheme

$frm2 = [Terminal.Gui.FrameView] @{
    X = [POS]::Right($frm1)
    Y = 0
    Width = [Terminal.Gui.Dim]::Percent(50)
    Height = [Terminal.Gui.Dim]::Fill()
    Title = "Dexie Quote"
}


$lbl_cat = [Terminal.Gui.Label] @{
    X = 3
    Y = 3
    Text = "Enter a CAT to swap: "
}

$txt_dexie = [Terminal.Gui.TextField]::new()
$txt_dexie.X = 30
$txt_dexie.Y = 3
$txt_dexie.Width = [DIM]::Percent(50)
$txt_dexie.Autocomplete.AllSuggestions = $cats
$txt_dexie.Autocomplete.MaxWidth = 70
$txt_dexie.Autocomplete.ColorScheme = $ColorScheme

$lbl_dexie_amount = [Terminal.Gui.Label] @{
    X = 3
    Y = 5
    
    Text = "Amount to swap: "
}

$txt_dexie_amount = [Terminal.Gui.TextField]::new()
$txt_dexie_amount.X = 30
$txt_dexie_amount.Y = 5
$txt_dexie_amount.Width = [DIM]::Percent(50)




$btn_swap = [Terminal.Gui.Button] @{
    Text = "Get Quote"
    X = [POS]::Bottom($txt_dexie)   
    Y = 7
}

$btn_swap.ColorScheme = $BTNColorScheme
$btn_swap.add_Clicked({
    $cat = $txt_dexie.Text.toString()
    $amount = $txt_dexie_amount.Text.toString()
    [MessageBox]::Query("Dexie Swap", "You are swapping $amount of $cat. Is this correct?", "Yes", "No")
    
})

$frm1.Add($lbl_cat)
$frm1.Add($txt_dexie)
$frm1.Add($lbl_dexie_amount)
$frm1.Add($txt_dexie_amount)
$frm1.Add($btn_swap)



$win_dexieswap.Add($frm1)
$win_dexieswap.Add($frm2)

### DEXIE END ###



$win_home.add($table)
[Application]::Top.Add($MB)
[Application]::Top.Add($win_home)

[Application]::Run()
[Application]::Shutdown()