# MIB-Processing
Powershell module for processing, analyzing and transforming SNMP MIB files

!! Not having finished some formalities so it's not really a module, you need to load it manually using file name

To get it work do those:

Import-Module .\MIB-Processing.psm1

List of functions:
* Import-MIB
* Get-MIBInfo
* Is-BackwardsCompatible
* ConvertTo-Snmptrap
* ConvertTo-SMIv1
* ConvertTo-SMIv2
