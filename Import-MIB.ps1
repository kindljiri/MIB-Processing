<#  
.SYNOPSIS  
    This script transform MIB file into csv (for better presentation to customer/manager ;-).
.DESCRIPTION  
    This script transform MIB file into csv (for better presentation to customer/manager ;-).
    
.PARAMETER Path
    The path and file name of a mib file.
.PARAMETER OIDrepo
    File with list of pair OnjectName=OID, for example: synoSystem=1.3.6.1.4.1.6574.1
    This help to resolve the OID to full number without it you might get resolution to highest object in MIB. Like this:
    enterprises.6574.1
.PARAMETER UpdateOIDRepo
    This will udpate the OIDRepo file you provide as -OIDRepo parameter.       
    
.NOTES  
    File Name      : Import-MIB.ps1  
    Author         : Jiri Kindl; kindl_jiri@yahoo.com
    Prerequisite   : PowerShell V2 over Vista and upper.
    Version        : 20200117
    Copyright 2020 - Jiri Kindl
.LINK  
    
.EXAMPLE
    .\Import-MIB.ps1  -Path .\SYNOLOGY-SYSTEM-MIB.mib
    Process the MIB and returns the as array of objects

.EXAMPLE 
    .\Import-MIB.ps1  -Path .\SYNOLOGY-SYSTEM-MIB.mib -OIDrepo .\all.oids
    Process the MIB and returns the as array of objects. Use OIDrepo file to resolve OIDs 

.EXAMPLE
    .\Import-MIB.ps1  -Path .\SYNOLOGY-SYSTEM-MIB.mib -OIDrepo .\all.oids -UpdateOIDRepo
    Process the MIB and returns the as array of objects. Use OIDrepo file to resolve OIDs and update the same OIDrepo file. 

.EXAMPLE
    .\Import-MIB.ps1 -Path .\ThreeParMIB.mib -OIDrepo .\all.oids | Export-Csv -Path .\3PAR.csv            
    To get output into CSV file

.EXAMPLE
    .\Import-MIB.ps1 -Path .\ThreeParMIB.mib -OIDrepo .\all.oids | Select-Object objectName,objectType,status,description,objects,ID,parent,OID | Export-Csv -Path .\3PAR.csv            
    To get complete output into CSV file

#>

#pars parametrs with param
[CmdletBinding()]
param([Parameter(Position=0)][string]$Path, [string]$OIDrepo, [switch]$UpdateOIDRepo)

$mib = @()
$OIDs = @()

function usage {
  "Import-MIB.ps1 -Path mib_file.mib [-OIDrepo file.oids]"
  "Path - MIB file"
  "OIDrepo - OID repository, file with records: Name=OID"
  exit
}

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
          $objectProperties = @{ objectName = $object_name; objectType = $object_type; status = $status; description = $description; objects = $objects; ID = $ID; parent = $parent; OID = "$parent.$ID" }
          $object = New-Object psobject -Property $objectProperties
          $mib += $object
          $sa_status="init"
          $object_name = ""
          $object_type = ""
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
      elseif ($line -cmatch "OBJECT IDENTIFIER") {
        $sa_status = "process_object_identifier"
        $line = $line -replace "OBJECT IDENTIFIER", ""
        $object_type = "OBJECT IDENTIFIER"
        if ($line -match "::=") {
          $line = $line -replace "::=", ""
          $line = $line -replace "{", "" 
          $line = $line -replace "}", ""
          $line = $line.trim()
          $line = $line -replace '\s+', " "
          ($object_name,$parent,$ID)  = ($line -split " ")
          $objectProperties = @{ objectName = $object_name; objectType = $object_type; status = $status; description = $description; objects = $objects; ID = $ID; parent = $parent; OID = "$parent.$ID" }
          $object = New-Object psobject -Property $objectProperties
          $mib += $object
          $sa_status="init"
          $object_name = ""
          $object_type = ""
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
        $objectProperties = @{ objectName = $object_name; objectType = $object_type; status = $status; description = $description; objects = $objects; ID = $ID; parent = $parent; OID = $OID; }
        $object = New-Object psobject -Property $objectProperties
        $mib += $object
        $sa_status="init"
        $object_name = ""
        $object_type = ""
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
      elseif ($line -Match "::="){
        $parent_and_id = $line -replace "::=", ""
        $parent_and_id = $parent_and_id -replace "{", "" 
        $parent_and_id = $parent_and_id -replace "}", ""
        $parent_and_id = $parent_and_id.trim()
        ($parent,$ID)  = ($parent_and_id -split " ")
        $OID = "$parent" + "." + "$ID"
        $objectProperties = @{ objectName = $object_name; objectType = $object_type; status = $status; description = $description; objects = $objects; ID = $ID; parent = $parent; OID = $OID; }
        $object = New-Object psobject -Property $objectProperties
        $mib += $object
        $sa_status="init"
        $object_name = ""
        $object_type = ""
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
        $objectProperties = @{ objectName = $object_name; objectType = $object_type; status = $status; description = $description; objects = $objects; ID = $ID; parent = $parent; OID = $OID; }
        $object = New-Object psobject -Property $objectProperties
        $mib += $object
        $sa_status="init"
        $object_name = ""
        $object_type = ""
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
        $objectProperties = @{ objectName = $object_name; objectType = $object_type; status = $status; description = $description; objects = $objects; ID = $ID; parent = $parent; OID = "$parent.$ID" }
        $object = New-Object psobject -Property $objectProperties
        $mib += $object
        $sa_status="init"
        $object_name = ""
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
        $objectProperties = @{ objectName = $object_name; ID = $ID; parent = $parent; OID = "$parent.$ID" }
        $object = New-Object psobject -Property $objectProperties
        $mib += $object
        $sa_status="init"
        $parent = ""
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


if ($OIDrepo) {
  if (!(Test-Path -Path $OIDrepo)) {
    Write-Host "ERROR: $OIDrepo doesn't exist"
    usage
  } 
}

try {
  $lines=get-content $Path -ErrorAction Stop

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


catch [System.Management.Automation.ItemNotFoundException] {
  "No such file"
  ""
  usage
}
catch {
  $Error[0]
}

