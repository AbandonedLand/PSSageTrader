@{
    RootModule = 'SageTrader.psm1'
    ModuleVersion = '2.1.3'
    GUID = 'dfc0ed88-44b8-4f71-b169-c07b02d1109b'
    Author = 'MayorAbandoned'
    Copyright = '(c) MayorAbandoned. All rights reserved.'

    Description = 'Terminal application for trading Chia Blockchain assets using the Sage Wallet.'
    PowerShellVersion = '7.4'
    RequiredModules = @(
        @{ ModuleName = 'PowerSage'; ModuleVersion = '1.0.19' },
        @{ ModuleName = 'PowerDexie'; ModuleVersion = '1.0.0' },
        @{ ModuleName ='PwshSpectreConsole'; ModuleVersion = '2.6.3'},
        'CircuitSage'
        
    )

    FunctionsToExport = @('*')

    CmdletsToExport = @()


    VariablesToExport = '*'


    AliasesToExport = @()
    PrivateData = @{

        PSData = @{
            ProjectUri = 'https://github.com/AbandonedLand/PSSageTrader'
            IconUri = 'https://github.com/AbandonedLand/PSSageTrader/blob/main/st.png?raw=true'

        } 

    } 
}

