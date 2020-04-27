
#Recursion function to expand the OID from (and translate into numbers)
function Get-OID($object, $mib) {
  #DEBUG
  #Write-Host $object.objectName
  $parent_name = $object.parent
  $parent_object = $mib | where objectName -EQ $parent_name
  if ($parent_object) {
    $parentOID = Get-OID $parent_object $mib
    $OID = $parentOID + '.' + $object.ID
    #Write-Host  $OID
    return $OID
  }
  else {
    #Write-Host $object.OID
    return $object.OID
  }
}

function Sanitize-MIB-Text($lines) {
  $status = 'init'
  $cleanMIBtext = @()
  $tokens = @()
  #Clean the lines, remove comments, parse strings and arrays
  foreach ($line in $lines) {
    #remove leading and tailing spaces 
    $line = $line.trim() 
    #remove duplicate white spaces (replace them with one space)
    $line = $line -replace '\s+', " "
    #unify comments because some stupids are able to use this --- Comment (as -- are opening the comment and next -- on the line are end it's valid comment)
    #ASN.1 comments commence with a pair of adjacent hyphens and end with the next pair of adjacent hyphens or at the end of the line, whichever occurs first.
    #As replace seems to be recursive removing 4 hyphens will remove all 
    $line = $line -replace '-{4}', ''
    #And then replacing 3 with 2
    $line = $line -replace '-{3}', '--'
    #And then finally
    #remove comments
    if ($line.startswith("--")) {
      if ($line.indexOf("--") -eq $line.lastIndexOf("--")){
        continue
      }
      else {
        $cleanMIBtext += $line.subString($line.lastIndexOf("--")+2,$line.Length-$line.lastIndexOf("--")-2)
      }
    }
    if ($line -match '--') {
      if ($line.indexOf("--") -eq $line.lastIndexOf("--")){
        $cleanMIBtext += $line.subString(0,$line.lastIndexOf("--"))
        continue
      }
      else {
        $cleanMIBtext += $line.subString(0,$line.lastIndexOf("--"))
        $cleanMIBtext += $line.subString($line.lastIndexOf("--")+2,$line.Length-$line.lastIndexOf("--")-2)
        continue
      }
    }
    #lets find and process strings, "arrays" (assignment is special array
    if ($status -eq 'init'){
      #processing string
      if ($line -match '"') {
        if ($line.indexOf('"') -gt 0) {
          $cleanMIBtext += $line.substring(0,($line.indexOf('"')))
          $text = $line.substring($line.indexOf('"'),$line.length-$line.indexOf('"'))
          if ($text.indexOf('"') -eq $text.lastIndexOf('"')) {
            $status = 'text_processing'
          }
          else {
            $cleanMIBtext += $text.substring(0,($text.lastIndexOf('"')+1))
            if ($text.lastIndexOf('"')+1 -lt $text.Length) {
              $cleanMIBtext += $text.substring($text.lastIndexOf('"'),$text.Length-$text.lastIndexOf('"'))
            }
            
          }
        }
        else {
          if ($line.indexOf('"') -eq $line.lastIndexOf('"')) {
            $text = $line
            $status = 'text_processing'
          }
          else {
            $cleanMIBtext += $line.substring(0,($line.lastIndexOf('"')+1))
            if ($line.lastIndexOf('"')+1 -lt $line.Length) {
              $cleanMIBtext += $line.substring($line.lastIndexOf('"'),$line.Length-$line.lastIndexOf('"'))
            }
          }
          
        }
        
      }
      #procesing "array"
      elseif ($line -match '{') {
        if ($line.indexOf('{') -gt 0) {
          $cleanMIBtext += $line.substring(0,($line.indexOf('{')))
          $array = $line.substring($line.indexOf('{'),$line.Length-$line.indexof('{'))
          if ($array -match '}') {
            $cleanMIBtext += $array.substring(0,$array.indexOf('}')+1)
            if ($array.indexOf('}')+1 -lt $array.Length) {
              $cleanMIBtext += $array.substring($array.indexOf('}'),$array.Length-$array.indexof('}'))
            }
          }
          else {
            $status = 'array_processing'
          }
        }
        else {
          if ($line -match '}') {
            $cleanMIBtext += $line.substring(0,$line.indexOf('}')+1)
            if ($line.indexOf('}')+1 -lt $line.Length) {
              $cleanMIBtext += $line.substring($line.indexOf('}'),$line.Length-$line.indexof('}'))
            }
          $array = $line
          $status = 'array_processing'
        }
      }
      }
      else {
        $cleanMIBtext += $line
      }
    }
    #processing multiline strings
    elseif ($status -eq 'text_processing') {
      if ($line -match '"') {
        if ($line.lastIndexOf('"')+1 -eq $line.length) {
          $text += $line
          $cleanMIBtext += $text
        }
        else {
          $text += " " + $line.substring(0,$line.lastIndexOf('"')+1)
          $cleanMIBtext += $text
          $cleanMIBtext += $line.substring($line.lastIndexOf('"'),$line.length-$line.lastIndexOf('"'))
        }
        $status = 'init'
      }
      else {
        $text += " $line"
      }
    }
    #processing multiline array
    elseif ($status -eq 'array_processing') {
      if ($line -match '}') {
        $array += " $line"
        $status = 'init'
        $cleanMIBtext += $array
      }
      else {
        $array +=" $line"
      }
    }
    
  }

  $lines = @()
  $lines = $cleanMIBtext
  $cleanMIBtext = @()

  #One more round of cleaning, left extra spaces and empty lines
  foreach ($line in $lines) {
    $line = $line.trim() 
    #remove duplicate white spaces (replace them with one space)
    $line = $line -replace '\s+', " "
    if ($line -eq '') {
      continue
    }
    $cleanMIBtext += $line
  }

  #tokenize: One token per line (string is one line, array is one line)
  foreach ($line in $cleanMIBtext) {
    if ($line.startswith('"')) {
      $tokens += $line
    }
    elseif ($line.startswith('{')) {
      $tokens += $line
    }
    else {
      $tokens += $line.split()
    }
  }

  $cleanMIBtext = @()
  $cleanMIBtext = $tokens 
  $tokens = @()
  
  #remove empty lines and extra spaces
  foreach ($line in $cleanMIBtext) {
    $line = $line.trim()
    if ($line -eq '') {
      continue
    }
    $tokens += $line
  }
  return $tokens
}

function New-Parse-MIB($tokens) {
  #based on:
  # rfc2578 - SMIv2
  # rfc1215 - TRAP-TYPE
  $sa_status="init"
  ($object_name,$object_type,$object_syntax,$status,$description,$objects,$ID,$parent,$object_max_access,$object_units,$object_reference,$object_index,$object_augments,$object_defval,$notification_objects,$parent,$ID) = ("","","","","","","","","","","","","","","","","")
  $counter = 0
  $mib = @()

  #below is not used yet (will see if I'll use it later
  $notification_type_tokens = ('OBJECTS','STATUS','DESCRIPTION','REFERENCE','::=')
  $object_type_tokens=('SYNTAX','UNITS','MAX-ACCESS','STATUS','DESCRIPTION','REFERENCE','INDEX','AUGMENTS','DEFVAL','::=')
  $trap_type_tokens = ('ENTERPRISE','VARIABLES','DESCRIPTION','REFERENCE')
  
  #below is union of above arrays
  $expected_type_tokens=('ENTERPRISE','VARIABLES','OBJECTS','SYNTAX','UNITS','MAX-ACCESS','STATUS','DESCRIPTION','REFERENCE','INDEX','AUGMENTS','DEFVAL','::=')

  foreach ($token in $tokens) {
    #just for sure
    $token = $token.trim()
    if ($sa_status -eq "init") {
      if ($token -eq 'BEGIN') {
        if ($tokens[$counter-2]+$tokens[$counter-1]+$token -eq 'DEFINITIONS::=BEGIN') {
          $module_name = $tokens[$counter-3]
        }
      }
      elseif ($token -eq 'IMPORT') {
        $sa_status = 'IMPORT'
      }
      elseif ($token -eq 'MODULE-IDENTITY') {
        $sa_status = 'MODULE-IDENTITY'
        $object_type = "MODULE-IDENTITY"
        $object_name = $tokens[$counter-1]
      }
      elseif ($token -eq 'IDENTIFIER' -and $tokens[$counter-1] -eq 'OBJECT') {
        $sa_status = 'OBJECT IDENTIFIER'
        $object_type = "OBJECT IDENTIFIER"
        $object_name = $tokens[$counter-2]
      }
      elseif ($token -eq 'OBJECT-IDENTITY') {
        $sa_status = 'OBJECT IDENTIFIER'
        $object_type = "OBJECT IDENTIFIER"
        $object_name = $tokens[$counter-1]
      }
      elseif ($token -eq 'OBJECT-TYPE') {
        $sa_status = 'OBJECT-TYPE'
        $object_type = "OBJECT-TYPE"
        $object_name = $tokens[$counter-1]
      }
      elseif ($token -eq 'NOTIFICATION-TYPE') {
        $sa_status = 'NOTIFICATION-TYPE'
        $object_type = "NOTIFICATION-TYPE"
        $object_name = $tokens[$counter-1]
      }
      elseif ($token -eq 'TRAP-TYPE') {
        $sa_status = 'TRAP-TYPE'
        $object_type = "TRAP-TYPE"
        $object_name = $tokens[$counter-1]
      }
      $object_name = $object_name.trim()
      $counter += 1
      continue 
    }
    elseif ($sa_status -eq 'IMPORT') {
      if ($token.endswith(';')) {
        $sa_status = 'init'
      }
    } 
    elseif ($sa_status -eq 'MODULE-IDENTITY') {
      if ($token -eq '::=') {
        $sa_status='::='
        $counter += 1
        continue
      }
    }
    elseif ($sa_status -eq 'OBJECT IDENTIFIER') {
      if ($token -eq '::=') {
        $sa_status='::='
        $counter += 1
        continue
      }
      
    }
    elseif ($sa_status -eq 'OBJECT-TYPE') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token 
        }
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'NOTIFICATION-TYPE') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token 
        }
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'SYNTAX') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token
          $object_syntax = $object_syntax.trim() 
        }
      }
      if ($sa_status -eq 'SYNTAX') {
        $object_syntax += $token + " "
      }
      else {
        #unexpected token
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'UNITS') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token
          $object_units = $object_units.trim() 
        }
      }
      if ($sa_status -eq 'UNITS') {
        $object_units += $token + " "
      }
      else {
        #unexpected token
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'MAX-ACCESS') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token
          $object_max_access = $object_max_access.trim() 
        }
      }
      if ($sa_status -eq 'MAX-ACCESS') {
        $object_max_access += $token + " "
      }
      else {
        #unexpected token
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'STATUS') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token
          $status = $status.trim() 
        }
      }
      if ($sa_status -eq 'STATUS') {
        $status += $token + " "
      }
      else {
        #unexpected token
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'DESCRIPTION') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token 
        }
      }
      if ($sa_status -eq 'DESCRIPTION' -and $token.startswith('"')) {
        $description = $token
      }
      else {
        #unexpected token
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'REFERENCE') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token
          $object_reference = $object_reference.trim() 
        }
      }
      if ($sa_status -eq 'REFERENCE') {
        $object_reference += $token + " "
      }
      else {
        #unexpected token
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'INDEX') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token
          $object_index = $object_index.trim() 
        }
      }
      if ($sa_status -eq 'INDEX') {
        $object_index += $token + " "
      }
      else {
        #unexpected token
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'AUGMENTS') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token
          $object_augments = $object_augments.trim() 
        }
      }
      if ($sa_status -eq 'AUGMENTS') {
        $object_augments += $token + " "
      }
      else {
        #unexpected token
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'DEFVAL') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token
          $object_defval = $object_defval.trim() 
        }
      }
      if ($sa_status -eq 'DEFVAL') {
        $object_defval += $token + " "
      }
      else {
        #unexpected token
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'OBJECTS' -or $sa_status -eq 'VARIABLES') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token
          $object_defval = $object_defval.trim() 
        }
      }
      if ($sa_status -eq 'OBJECTS' -and $token.startswith('{')) {
        $notification_objects = $token
      }
      else {
        #unexpected token
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'ENTERPRISE') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token
          $parent = $parent.trim() 
        }
      }
      if ($sa_status -eq 'ENTERPRISE') {
        $parent = $token
      }
      else {
        #unexpected token
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq '::=') {
      if ($token.startswith('{')) {
        $token = $token -replace '{', ''
        $token = $token -replace '}', ''
        $token = $token.trim()
        if ($object_type -eq 'TRAP-TYPE') {
          $ID = $ID.trim()
        }
        else {
          ($parent,$ID) = ($token -split " ")
        }
        $parent = $parent.trim()
        $ID = $ID.trim()
        $objectProperties = @{ objectName = $object_name; objectType = $object_type; objectSyntax = $object_syntax; status = $status; description = $description; objects = $notification_objects; ID = $ID; parent = $parent; OID = "$parent.$ID"; module = $module_name; objectFullName = "$module_name::$object_name" }
        $object = New-Object psobject -Property $objectProperties
        $mib += $object
        $sa_status="init"
        ($object_name,$object_type,$object_syntax,$status,$description,$objects,$ID,$parent,$object_max_access,$object_units,$object_reference,$object_index,$object_augments,$object_defval,$notification_objects,$parent,$ID) = ("","","","","","","","","","","","","","","","","")
        $counter += 1
        continue
      }
    }
    $counter += 1
  }
  return $mib
}

#Takes the lines from MIB file, and parse them into objects, returns the array of custom objects
function Old-Parse-MIB($lines) {
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
    #"DEBUG: $sa_status"
    #ignore line containings only comment
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
    Version        : 20200426
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
    #$mib = Old-Parse-MIB $lines
    $tokens = Sanitize-MIB-Text $lines
    $mib = New-Parse-MIB $tokens

    #expand OID from parent.ID to full path in MIB scope
    foreach ($object in $mib) {
      $OID = Get-OID $object $mib
      #DEBUG
      #$object.objectName
      #$OID
      #DEBUG
      $objectProperties = @{ objectName = $object.ObjectName; OID = $OID }
      $new_object = New-Object psobject -Property $objectProperties
      $OIDs += $new_object
    }

    #resolve OIDs to numbers (using OID repo file) And Update OID repo if switch UpdateOIDRepo is used
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

    #update find resolved OIDs to corresponding objects
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