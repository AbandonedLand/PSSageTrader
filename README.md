# Sage-Trader
alpha release 

use at your own risk ( you should create another wallet in Sage to put trading funds into and only allow the bot access to that fingerprint.)


## Getting Started
```PowerShell
Install-Module -name PowerSage
Install-Module -name PowerDexie
Install-Module -name PwshSpectreConsole

Import-Module -name PowerSage
Import-Module -name PowerDexie
Import-Module -name PwshSpectreConsole

# creates a certificate to connect to SageWallet
New-SagePfxCertificate

# download the spectresage.ps1 file and load it into the terminal with dot sourcing (. ./file.ps1)
. ./spectresage.ps1


# Start TUI
Start-SageTrader

# As of now you'll have to manually Activate the bots after they are created in the TUI
$bots = Get-ChiaBots
$bots.activate()


# Start the bots running with 
Start-Bots


# NOTES:  This will update in the near future.
```

