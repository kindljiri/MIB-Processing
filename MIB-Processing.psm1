
#Recursion function to expand the OID from (and translate into numbers)
function Get-OID($object, $mib) {
  $parent_name = $object.parent
  $parent_object = $mib | where objectName -EQ $parent_name
  if ($parent_object) {
    $parentOID = Get-OID $parent_object $mib
    $OID = $parentOID + '.' + $object.ID
    return $OID
  }
  else {
    return $object.OID
  }
}

#Takes the lines from MIB file, and parse them into objects, returns the array of custom objects
function Parse-MIB($lines) {
  $sa_status="init"
  $object_name = ""
  $object_type = ""
  $object_syntax = ""
  $status = ""
  $description = ""
  $objects = ""
  $ID = ""
  $parent = ""

  $mib = @()
  
  Foreach ($line in $lines) {
    $line = $line.trim() 
    $line = $line -replace '\s+', " "
    #"DEBUG: $line"
    #ignore line containings only comment
    #"DEBUG: $sa_status"
    if ($line.startswith("--")) {
      continue
    }
    elseif ($sa_status -eq "init") {
      if ($line -cmatch "NOTIFICATION-TYPE"){
        $sa_status = "process_notification"
        $object_name = $line -replace "NOTIFICATION-TYPE"
        $object_name = $object_name.trim()
        $object_type = "NOTIFICATION-TYPE" 
        continue
      }
      elseif ($line.endswith(' DEFINITIONS ::= BEGIN')) {
        $module_name = $line -replace ' DEFINITIONS ::= BEGIN'
        $module_name = $module_name.trim()
      }
      elseif ($line -cmatch "IMPORTS") {
        $sa_status = "process_imports"
        continue
      }
      elseif ($line -cmatch "TRAP-TYPE") {
        $sa_status = "process_trap"
        $object_name = $line -replace "TRAP-TYPE"
        $object_name = $object_name.trim()
        $object_type = "TRAP-TYPE"
        continue
      }
      elseif ($line -cmatch "OBJECT-TYPE") {
        $sa_status = "process_object"
        $line = $line -replace "OBJECT-TYPE"
        $object_type = 'OBJECT-TYPE'
        if ($line -match "::=") {
          $line = $line -replace "::=", ""
          $line = $line -replace "{", "" 
          $line = $line -replace "}", ""
          $line = $line.trim()
          $line = $line -replace '\s+', " "
          ($object_name,$parent,$ID)  = ($line -split " ")
          $objectProperties = @{ objectName = $object_name; objectType = $object_type; objectSyntax = $object_syntax; status = $status; description = $description; objects = $objects; ID = $ID; parent = $parent; OID = "$parent.$ID"; module = $module_name; objectFullName = "$module_name::$object_name" }
          $object = New-Object psobject -Property $objectProperties
          $mib += $object
          $sa_status="init"
          $object_name = ""
          $object_type = ""
          $object_syntax = ""
          $status = ""
          $description = ""
          $objects = ""
          $ID = ""
          $parent = ""
          continue
        }
        else {
          $object_name = $line.trim()
        }
        continue
      } 
      elseif (($line -cmatch 'OBJECT IDENTIFIER') -or ($line -cmatch 'OBJECT-IDENTITY')) {
        $sa_status = "process_object_identifier"
        $line = $line -replace "OBJECT IDENTIFIER", ""
        $line = $line -replace "OBJECT-IDENTITY", ""
        $object_type = "OBJECT IDENTIFIER"
        if ($line -match "::=") {
          $line = $line -replace "::=", ""
          $line = $line -replace "{", "" 
          $line = $line -replace "}", ""
          $line = $line.trim()
          $line = $line -replace '\s+', " "
          ($object_name,$parent,$ID)  = ($line -split " ")
          $objectProperties = @{ objectName = $object_name; objectType = $object_type; objectSyntax = $object_syntax; status = $status; description = $description; objects = $objects; ID = $ID; parent = $parent; OID = "$parent.$ID"; module = $module_name; objectFullName = "$module_name::$object_name" }
          $object = New-Object psobject -Property $objectProperties
          $mib += $object
          $sa_status="init"
          $object_name = ""
          $object_type = ""
          $object_syntax = ""
          $status = ""
          $description = ""
          $objects = ""
          $ID = ""
          $parent = ""
          continue
        }
        else {
          $object_name = $line.trim()
        }
        continue
      }
      elseif ($line -cmatch "MODULE-IDENTITY") {
        $sa_status = "process_module_identity"
        $line = $line -replace "MODULE-IDENTITY", ""
        $object_name = $line.trim()
        $object_type = "MODULE-IDENTITY"
        continue
      } 
    }
    
    elseif ($sa_status -eq "process_trap"){
      if ($line -cmatch "DESCRIPTION"){
        $description = $description + $line
        $description = $description -replace "DESCRIPTION", ""
        $description = $description.trim()
        if (!($line.EndsWith('"'))){
          $sa_status = "process_trap_description"
        }
        continue
      }
      elseif ($line -cmatch "VARIABLES"){
        $objects = $objects + $line
        $objects = $objects -replace "VARIABLES", ""
        $objects = $objects -replace "{", ""
        $objects = '{' + $objects.trim()
        if (!($line.EndsWith('}'))){
          $sa_status = "process_variables"
        }
        continue
      }
      elseif ($line -cmatch "ENTERPRISE"){
        $parent = $line -replace "ENTERPRISE", ""
        $parent = $parent.trim()
        continue
      }
      elseif ($line -Match "::="){
        $ID = $line -replace "::=", ""
        $ID = $ID.trim()
        $OID = "$parent" + "." + "$ID"
        $objectProperties = @{ objectName = $object_name; objectType = $object_type; objectSyntax = $object_syntax; status = $status; description = $description; objects = $objects; ID = $ID; parent = $parent; OID = "$parent.$ID"; module = $module_name; objectFullName = "$module_name::$object_name" }
        $object = New-Object psobject -Property $objectProperties
        $mib += $object
        $sa_status="init"
        $object_name = ""
        $object_type = ""
        $object_syntax = ""
        $status = ""
        $description = ""
        $objects = ""
        $ID = ""
        $parent = ""
        continue
      }
    }
    elseif ($sa_status -eq "process_object"){
      if ($line -cmatch "DESCRIPTION"){
        $description = $description + $line
        $description = $description -replace "DESCRIPTION", ""
        $description = $description.trim()
        if (!($line.EndsWith('"'))){
          $sa_status = "process_object_description"
        }
        continue     
      }
      elseif ($line -cmatch "SYNTAX") {
        $object_syntax = $line -replace "SYNTAX", ""
        $object_syntax = $object_syntax.trim()
      }
      elseif ($line -Match "::="){
        $parent_and_id = $line -replace "::=", ""
        $parent_and_id = $parent_and_id -replace "{", "" 
        $parent_and_id = $parent_and_id -replace "}", ""
        $parent_and_id = $parent_and_id.trim()
        ($parent,$ID)  = ($parent_and_id -split " ")
        $OID = "$parent" + "." + "$ID"
        $objectProperties = @{ objectName = $object_name; objectType = $object_type; objectSyntax = $object_syntax; status = $status; description = $description; objects = $objects; ID = $ID; parent = $parent; OID = "$parent.$ID"; module = $module_name; objectFullName = "$module_name::$object_name" }
        $object = New-Object psobject -Property $objectProperties
        $mib += $object
        $sa_status="init"
        $object_name = ""
        $object_type = ""
        $object_syntax = ""
        $status = ""
        $description = ""
        $objects = ""
        $ID = ""
        $parent = ""
        continue
      }
    }
    elseif ($sa_status -eq "process_notification"){
      if ($line -cmatch "DESCRIPTION"){
        $description = $line -replace "DESCRIPTION", ""
        $description = $description.trim()
        if (!($line.EndsWith('"'))){
          $sa_status = "process_description"
        }
        continue
      }
      elseif ($line -cmatch "OBJECTS"){
        $objects = $line -replace "OBJECTS", ""
        $objects = $objects -replace "{", ""
        $objects = '{' + $objects.trim()
        if (!($line.EndsWith('}'))){
          $sa_status = "process_objects"
        }
        continue
      }
      elseif ($line -Match "::="){
        $parent_and_id = $line -replace "::=", ""
        $parent_and_id = $parent_and_id -replace "{", "" 
        $parent_and_id = $parent_and_id -replace "}", ""
        $parent_and_id = $parent_and_id.trim()
        ($parent,$ID)  = ($parent_and_id -split " ")
        $OID = "$parent" + "." + "$ID"
        $objectProperties = @{ objectName = $object_name; objectType = $object_type; objectSyntax = $object_syntax; status = $status; description = $description; objects = $objects; ID = $ID; parent = $parent; OID = "$parent.$ID"; module = $module_name; objectFullName = "$module_name::$object_name" }
        $object = New-Object psobject -Property $objectProperties
        $mib += $object
        $sa_status="init"
        $object_name = ""
        $object_type = ""
        $object_syntax = ""
        $status = ""
        $description = ""
        $objects = ""
        $ID = ""
        $parent = ""
        continue
      }
    }
    elseif ($sa_status -eq "process_description"){
      if ($line.EndsWith('"')){
        $description = $description + ' ' + $line
        $sa_status = "process_notification"
        continue
      }
      else {
        $description = $description + ' ' + $line
        continue
      }
    }
    elseif ($sa_status -eq "process_object_description"){
      if ($line.EndsWith('"')){
        $description = $description + ' ' + $line
        $sa_status = "process_object"
        continue
      }
      else {
        $description = $description + ' ' + $line
        continue
      }
    }
    elseif ($sa_status -eq "process_trap_description"){
      if ($line.EndsWith('"')){
        $description = $description + ' ' + $line
        $sa_status = "process_trap"
        continue
      }
      else {
        $description = $description + ' ' + $line
        continue
      }
    }
    elseif ($sa_status -eq "process_objects"){
      if ($line.EndsWith('}')){
        $objects = $objects + $line
        $sa_status = "process_notification"
        continue
      }
      else {
        $objects = $objects + ' ' + $line
        continue
      }
    }
    elseif ($sa_status -eq "process_variables"){
      if ($line.EndsWith('}')){
        $objects = $objects + $line
        $sa_status = "process_trap"
        continue
      }
      else {
        $objects = $objects + ' ' + $line
        continue
      }
    }
    elseif ($sa_status -eq "process_object_identifier") {
      if ($line -Match "::="){
        $parent_and_id = $line -replace "::=", ""
        $parent_and_id = $parent_and_id -replace "{", "" 
        $parent_and_id = $parent_and_id -replace "}", ""
        $parent_and_id = $parent_and_id.trim()
        ($parent,$ID)  = ($parent_and_id -split " ")
        $description = $description -replace ";", ","
        $description = $description -replace "`t", " "
        $object_type = "OBJECT IDENTIFIER"
        $objectProperties = @{ objectName = $object_name; objectType = $object_type; objectSyntax = $object_syntax; status = $status; description = $description; objects = $objects; ID = $ID; parent = $parent; OID = "$parent.$ID"; module = $module_name; objectFullName = "$module_name::$object_name" }
        $object = New-Object psobject -Property $objectProperties
        $mib += $object
        $sa_status="init"
        $object_name = ""
        $object_syntax = ""
        $parent = ""
        continue
      }
    }
    elseif ($sa_status -eq "process_imports"){
      if ($line.EndsWith(';')){
        $sa_status = "init"
        continue
      }
    }
    elseif ($sa_status -eq "process_module_identity") {
      if ($line -Match "::="){
        $parent_and_id = $line -replace "::=", ""
        $parent_and_id = $parent_and_id -replace "{", "" 
        $parent_and_id = $parent_and_id -replace "}", ""
        $parent_and_id = $parent_and_id.trim()
        ($parent,$ID)  = ($parent_and_id -split " ")
        $description = $description -replace ";", ","
        $description = $description -replace "`t", " "
        $objectProperties = @{ objectName = $object_name; objectType = $object_type; objectSyntax = $object_syntax; status = $status; description = $description; objects = $objects; ID = $ID; parent = $parent; OID = "$parent.$ID"; module = $module_name; objectFullName = "$module_name::$object_name" }
        $object = New-Object psobject -Property $objectProperties
        $mib += $object
        $sa_status="init"
        $parent = ""
        $object_syntax = ""
        continue
      }
    }
  }
  return $mib
}

#Takes object name and returns OID (in number format) or Null
function Select-OID($object_name, $OIDrepo) {
      $OIDrepo_SearchResult = select-string "^$object_name=" $OIDrepo
      if ($OIDrepo_SearchResult) {
        $OIDrepo_SearchResult = $OIDrepo_SearchResult.Line
        $oid = $OIDrepo_SearchResult.Split("=")[1]
        return $oid
      }
      else {
        return $OIDrepo_SearchResult       
      }
}

function Update-OIDRepo($object, $OIDrepo) {
  $OIDrepo_Update = $object.objectName + '=' + $object.OID
  $OIDrepo_SearchResult = select-string "^$OIDrepo_Update$" $OIDrepo
  if (!$OIDrepo_SearchResult) {
    $OIDrepo_SearchResult = select-string "=$newOID$" $OIDrepo
    if (!$OIDrepo_SearchResult) {
      $OIDrepo_Update >> $OIDrepo
      Write-verbose "$OIDrepo_Update added to $OIDrepo"
    }
    else {
      Write-Host "ERROR: adding $OIDrepo_Update record with same OID already exist in $OIDrepo. - $OIDrepo_SearchResult "
    }
  }
  else {
    Write-verbose "$OIDrepo_Update already exist in $OIDrepo"
  }
}

function Import-MIB {
<#  
.SYNOPSIS  
    Transform MIB file into objects.
.DESCRIPTION  
    Transform MIB file into objects.
    
.PARAMETER Path
    The path and file name of a mib file.
.PARAMETER OIDrepo
    File with list of pair OnjectName=OID, for example: synoSystem=1.3.6.1.4.1.6574.1
    This help to resolve the OID to full number without it you might get resolution to highest object in MIB. Like this:
    enterprises.6574.1
.PARAMETER UpdateOIDRepo
    This will udpate the OIDRepo file you provide as -OIDRepo parameter.       
    
.NOTES  
    Module Name    : MIB-Processing  
    Author         : Jiri Kindl; kindl_jiri@yahoo.com
    Prerequisite   : PowerShell V2 over Vista and upper.
    Version        : 20200305
    Copyright 2020 - Jiri Kindl
.LINK  
    
.EXAMPLE
    Import-MIB -Path .\SYNOLOGY-SYSTEM-MIB.mib
    Process the MIB and returns the as array of objects

.EXAMPLE 
    Import-MIB -Path .\SYNOLOGY-SYSTEM-MIB.mib -OIDrepo .\all.oids
    Process the MIB and returns the as array of objects. Use OIDrepo file to resolve OIDs 

.EXAMPLE
    Import-MIB -Path .\SYNOLOGY-SYSTEM-MIB.mib -OIDrepo .\all.oids -UpdateOIDRepo
    Process the MIB and returns the as array of objects. Use OIDrepo file to resolve OIDs and update the same OIDrepo file. 

.EXAMPLE
    Import-MIB -Path .\ThreeParMIB.mib -OIDrepo .\all.oids | Export-Csv -Path .\3PAR.csv            
    To get output into CSV file

.EXAMPLE
    Import-MIB -Path .\ThreeParMIB.mib -OIDrepo .\all.oids | Select-Object objectName,objectType,status,description,objects,ID,parent,OID | Export-Csv -Path .\3PAR.csv            
    To get complete output into CSV file

.EXAMPLE
    cat .\ThreeParMIB.mib | Import-MIB -OIDrepo .\all.oids | Select-Object objectName,objectType,status,description,objects,ID,parent,OID | Export-Csv -Path .\3PAR.csv            
    To get complete output into CSV file
#>

  #pars parametrs with param
  [CmdletBinding()]
  param([Parameter(Position=0)][string]$Path, [string]$OIDrepo, [switch]$UpdateOIDRepo, 
  [parameter(ValueFromPipeline=$true)][string]$pipelineInput)

  BEGIN {
    $mib = @()
    $OIDs = @()
    $lines = @()

    if ($OIDrepo) {
      if (!(Test-Path -Path $OIDrepo)) {
        Write-Host "ERROR: $OIDrepo doesn't exist"
        Get-Help Import-MIB
      } 
    }

    try {
      if ($Path) {
        $lines=get-content $Path -ErrorAction Stop
      }
    }
    catch [System.Management.Automation.ItemNotFoundException] {
      "No such file"
      ""
      get-help Import-MIB
    }
    catch {
      $Error[0]
    }
  }
  PROCESS {
    if (!$Path) { 
      foreach ($line in $pipelineInput) {
        $lines += "$line"
      }
    }
  }
  END {
    $mib = Parse-MIB $lines

    foreach ($object in $mib) {
      $OID = Get-OID $object $mib
      $objectProperties = @{ objectName = $object.ObjectName; OID = $OID }
      $new_object = New-Object psobject -Property $objectProperties
      $OIDs += $new_object
    }
  
    if ($OIDRepo) {
      foreach ($oid_record in $OIDs) {
        $oid=$oid_record.OID
        $object_name_to_search = $oid.split('.')[0]
        $OIDrepo_SearchResult = Select-OID $object_name_to_search $OIDrepo
        if ($OIDrepo_SearchResult) {
          $newOID = $oid -replace $object_name_to_search, $OIDrepo_SearchResult
          $oid_record.OID = $newOID
          if ($UpdateOIDRepo) {
            Update-OIDRepo $oid_record $OIDrepo
          }
        }
        else {
          if ($UpdateOIDRepo) {
            Write-Host "ERROR: $object_to_search from $Path not found in $OIDrepo"
          }
          else {
            Write-Verbose "ERROR: $object_to_search from $Path not found in $OIDrepo"
          }
        
        }
      }
    }

    foreach ($object in $OIDs) {
      $mib_object = $mib | where objectName -EQ $object.objectName
      $mib_object.OID = $object.OID
    }
    return $mib
  }
}

function ConvertTo-Snmptrap {
  <#  
.SYNOPSIS  
    Convert TRAP-TYPE ot NOTIFYCATION-TYPE MIB Objects to snmptrap commands, which can be used for testing. 
.DESCRIPTION  
    Convert TRAP-TYPE ot NOTIFYCATION-TYPE MIB Objects, generated by Improt-MIB to snmptrap commands, which can be used for testing.
  
.PARAMETER Path
    The path and file name of CSV file generated by Import-MIB
    If you use the CSV as input make sure the CSV was generated with -UseCulture
.PARAMETER SnmpVersion
    Version of SNMP trap to use. 1, 2. By default version 1 is used.
.PARAMETER TrapReciever
    Trap reciever IP. IP server to which you want to send traps. By default it use text "TrapRecieverIP", which you can replace later.       
.PARAMETER Community
    Snmp Community string to be used. By default public.
    
.NOTES  
    Module Name    : MIB-Processing  
    Author         : Jiri Kindl; kindl_jiri@yahoo.com
    Prerequisite   : PowerShell V2 over Vista and upper.
    Version        : 20200312
    Copyright 2020 - Jiri Kindl
.LINK  
    
.EXAMPLE
    ConvertTo-Snmptrap -Path .\NIMBLE.csv
    Convert CSV file generated by Import-MIB. !NOTE: use | Export-Csv -UseCulture otherwise it will not work.

.EXAMPLE 
    Import-Csv -UseCulture -Path .\NIMBLE.csv | ConvertTo-Snmptrap 
    Convert CSV file generated by Import-MIB. !NOTE: you need to use -UseCUlture switch with Import-CSV if the CSV file was generated with -UseCulture

.EXAMPLE
    cat .\ThreeParMIB.mib | Import-MIB -OIDrepo .\myOIDrepo.oids | ConvertTo-Snmptrap
    To generate snmptrap commands for testing based on ThreeParMIB.mib file

.EXAMPLE
    cat .\ThreeParMIB.mib | Import-MIB -OIDrepo .\myOIDrepo.oids | ConvertTo-Snmptrap -SnmpVersion 2
    To generate snmptrap commands, with version 2 traps, for testing based on ThreeParMIB.mib file
  #>

  #pars parametrs with param
  [CmdletBinding()]
  param([Parameter(Position=0)][string]$Path, 
  [parameter(ValueFromPipeline=$true)]$pipelineInput,
  [string]$SnmpVersion = '1',
  $TrapReciever = 'TrapRecieverIP',
  $Community = 'public',
  [switch]$OIDs
  )

  BEGIN {
    $mib = @()
    $test_string = '"Test string"'
    $test_number = 3
    $test_ip = "10.10.10.10"
    try {
      if ($Path) {
        $mib=Import-Csv -UseCulture -Path $Path -ErrorAction Stop
      }
    }
    catch [System.Management.Automation.ItemNotFoundException] {
      "No such file"
      ""
      Get-Help ConvertTo-Snmptrap
    }
    catch {
      $Error[0]
    }
  }
  PROCESS {
    if (!$Path) { 
      foreach ($object in $pipelineInput) {
        #$object = New-Object psobject -Property $objectProperties
        $mib += $object
      }
    }
  }
  END {
    $traps = $mib | where {($_.objectType -EQ "TRAP-TYPE" -or $_.objectType -EQ "NOTIFICATION-TYPE")}
    if ($traps) {
      #$traps
      foreach ($trap in $traps) {
        #$trap.OID
        $object_names = (($trap.objects -replace "{") -replace "}") -split ","
        $objects_parameters = ''
        #default is v 1, and if unsupported version is used it falls back to v 1
        $snmp_command = "snmptrap -v 1 -c $Community $TrapReciever "
        foreach ($object_name in $object_names) {
          $object_name = $object_name.trim()
          $object = $mib | where {($_.objectName -EQ $object_name)}
          if ($OIDs) {
            $objects_parameters += $object.OID
          }
          else {
            $objects_parameters += $object.objectFullName
          }
          #Numbers
          if (($object.objectSyntax -match 'INTEGER') -or ($object.objectSyntax -match 'Counter') -or ($object.objectSyntax -match 'Gauge') -or ($object.objectSyntax -match 'TimeTicks')) {
            $objects_parameters += ' i '
            $objects_parameters += "$test_number "
          }
          #Ips
          elseif (($object.objectSyntax -match 'NetworkAddress') -or ($object.objectSyntax -match 'IpAddress')) {
            $objects_parameters += ' a '
            $objects_parameters += "$test_ip "
          }
          #Strings
          elseif (($object.objectSyntax -match 'DisplayString') -or ($object.objectSyntax -match 'STRING')) {
            $objects_parameters += ' s '
            $objects_parameters += "$test_string "
          }
          else {
            Write-Verbose "Unknown object SYNTAX:"
          }
        }
        $objects_parameters = $objects_parameters.trim()
        #Write-Output "$objects_parameters"
        if ($SnmpVersion -match '2') {
          $snmp_command = "snmptrap -v 2c -c $Community $TrapReciever '0' "
          if ($OIDs) {
            $snmp_command += $trap.OID + ' '
          }
          else {
            $snmp_command += $trap.objectFullName + ' '
          }
        }
        elseif ($SnmpVersion -match '1') {
          $parent = $mib | where {($_.objectName -EQ $trap.parent)}
          if ($OIDs) {
            $snmp_command += $parent.OID + ' localhost 6 '+ $trap.ID + ' "0" '
          }
          else {
            $snmp_command += $parent.objectFullName + ' localhost 6 '+ $trap.ID + ' "0" '
          }
        }
        else {
          Write-Verbose "Unsupporte SnmpVersion setting v1"
          $parent = $mib | where {($_.objectName -EQ $trap.parnet)}  
          if ($OIDs) {
            $snmp_command += $parent.OID + ' localhost 6 '+ $trap.ID + ' "0" '
          }
          else {
            $snmp_command += $parent.objectFullName + ' localhost 6 '+ $trap.ID + ' "0" '
          }
        }
        $snmp_command += $objects_parameters
        Write-Output $snmp_command
        # objectName,objectType,status,description,objects,ID,parent,OID
        #snmptrap -v 1 -c public <IP of TrapReciever> 1.3.6.3.1.1.5 localhost 6 17 "0" 1.3.6.1.2.1.1.6 s "Location"
        #snmptrap -v 2 -c public <IP of TrapReciever> '0' 1.3.6.3.1.1.5 1.3.6.1.2.1.1.6 s "Location"
      }
    }
    else {
      Write-Verbose "No traps"
    }
  }
}

function Get-MIBInfo {
<#  
.SYNOPSIS  
    Get the MIB file basic Info.
.DESCRIPTION  
    Get basci Info from MIB File like, Module name and revision.
    
.PARAMETER Path
    The path and file name of a mib file.
    
.NOTES  
    Module Name    : MIB-Processing  
    Author         : Jiri Kindl; kindl_jiri@yahoo.com
    Prerequisite   : PowerShell V2 over Vista and upper.
    Version        : 20200305
    Copyright 2020 - Jiri Kindl
.LINK  
    
.EXAMPLE
    Get-MIB -Path .\SYNOLOGY-SYSTEM-MIB.mib
    Process the MIB and returns basic information, like Module name and revision if available.

#>

  #parse parametrs with param
  [CmdletBinding()]
  param([Parameter(Position=0)][string]$Path)

  BEGIN {
    $lines = @()
    $sa_status="init"

    try {
      if ($Path) {
        $lines=get-content $Path -ErrorAction Stop
      }
    }
    catch [System.Management.Automation.ItemNotFoundException] {
      "No such file"
      ""
      get-help Import-MIB
    }
    catch {
      $Error[0]
      get-help Import-MIB
    }
  }

  END {
    $fileInfo = ls $Path
    Foreach ($line in $lines) {
      #clean lines from extra spaces
      $line = $line.trim() 
      $line = $line -replace '\s+', " "
      #ignore comments
      if ($line.startswith("--")) {
        continue
      }
      if ($sa_status -eq "init") {
        if ($line.endswith(' DEFINITIONS ::= BEGIN')) {
          $moduleName = $line -replace ' DEFINITIONS ::= BEGIN'
          $moduleName = $moduleName.trim()
          continue
        }
        elseif ($line -cmatch "MODULE-IDENTITY") {
          $sa_status = "process_module_identity"
          $line = $line -replace "MODULE-IDENTITY", ""
          $object_name = $line.trim()
          $object_type = "MODULE-IDENTITY"
          continue
        } 
      }
      elseif ($sa_status -eq "process_module_identity") {
        if ($line -Match "LAST-UPDATED") {
          $revision = $line -replace "LAST-UPDATED"
          $revision = $revision.trim()
          continue
        }
        elseif ($line -Match "::="){
          $parent_and_id = $line -replace "::=", ""
          $parent_and_id = $parent_and_id -replace "{", "" 
          $parent_and_id = $parent_and_id -replace "}", ""
          $parent_and_id = $parent_and_id.trim()
          ($parent,$ID)  = ($parent_and_id -split " ")
          $description = $description -replace ";", ","
          $description = $description -replace "`t", " "
          break
        }
    }
    
    }
    $objectProperties = @{ fileFullName = $fileInfo.FullName; fileName = $fileInfo.Name; fileSize = $fileInfo.Length; ModuleName = $moduleName; revision = $revision }
    $MIBFileInfo = New-Object psobject -Property $objectProperties
    $MIBFileInfo  
    
  }
}