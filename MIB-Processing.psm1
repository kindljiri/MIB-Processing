#Input: content of MIB file
#Output: content of MIB file without comments (and blank lines)
function Remove-Comments($lines){
  $linesWithoutComments = @()
  $sa_state = 'init'
  #start with preprocessing
  $lines = $lines | Where-Object {$_.trim() -ne ''}
  #remove comments
  $debugMessage = "STARTING REMOVE-COMMENTS"
  Write-Debug $debugMessage
  foreach ($line in $lines) {
    $tmp = ''
    $line = $line -replace '\s+', ' '

    #unify comments because some stupids are able to use this --- Comment (as -- are opening the comment and next -- on the line are end it's valid comment)
    #ASN.1 comments commence with a pair of adjacent hyphens and end with the next pair of adjacent hyphens or at the end of the line, whichever occurs first.
    #As replace seems to be recursive removing 4 hyphens will remove all 
    $line = $line -replace '-{4}', ''
    #And then replacing 3 with 2
    $line = $line -replace '-{3}', '--'
    $line = $line -replace '--', ' -- '
    #And then finally (we have only -- marking beging and end of comment
    #by adding spaces around I can split based on the '--' and every 
    $line = $line -replace '"', ' " '
    #Adding space around " to make it token

    #foreach line do this littel state automata
    foreach ($token in $line.split(' ')) {
      $debugMessage = "REMOVE-COMMENTS: Status=$sa_state,Token=$token"
      Write-Debug $debugMessage
      if ($sa_state -eq 'init') {
        if ($token -eq '"'){
          $sa_state = 'text_processing'
          $tmp += " $token"
          continue 
        }
        elseif ($token -eq '--') {
          $sa_state = 'comment_processing'
          continue
        }
        else {
          $tmp += " $token"
          continue
        }
      }
      elseif ($sa_state -eq 'text_processing'){
        if ($token -eq '"') {
          $sa_state = 'init'
        }
        $tmp += " $token" 
      }    
    }
    #after finnishing the line if it's processing comment swithc back to init cause newline is end of comment
    if ($sa_state -eq 'comment_processing') {
      $sa_state = 'init'
    }
    if ($tmp.trim() -ne '') {
      $linesWithoutComments += $tmp.trim()
    }    
    
  }
  $linesWithoutComments = $linesWithoutComments | where-object {$_.trim() -ne ''}
  $debugMessage = "ENDING REMOVE-COMMENTS"
  Write-Debug $debugMessage
  return $linesWithoutComments
}

#Input: Content of MIB witout comment (use Remove-Comments)
#Output: MIB Tokens one token per line
function Get-Tokens($linesWithoutComments) {

  #this expects that re removed comments
  $tokens = @()
  $preprocessed_lines = @()
  $sa_state = 'init'
  # prepare text to recognize tokens as variables, keywords, arrays and quted text
  #let's use space as separator
  #first to make sure we will be able to recognize arrays and quoted string replace all '{' with '{ ' , '}' with ' }' and '"' with ' " '
  #also make sure we can recognize assignments by replacing '::=' with ' ::= ' because this is also valid: DEFINITIONS::= BEGINS
  Write-Verbose "Get-Tokens: Tokenizing"
  foreach ($line in $linesWithoutComments) {
    $line = $line -replace '{', '{ '
    $line = $line -replace '}', ' }'
    $line = $line -replace '"', ' " '
    $line = $line -replace '::=', ' ::= '
    #removing duplicat white spaces and spliting will prevent empty tokens 
    $line = $line -replace '\s+', ' '
    $preprocessed_lines += $line.split(' ')

  }

  $preprocessed_lines = $preprocessed_lines | Where-Object {$_.trim() -ne ''}
  
  foreach ($token in $preprocessed_lines) {
    $token = $token.trim()

    if ($sa_state -eq 'init'){
      if ($token -eq '{') {
        $array = '{'
        $sa_state = 'array_processing'
        continue
      }
      elseif ($token -eq '"') {
        $quoted_text = '"'
        $sa_state = 'quoted_text_processing'
        continue
      }
      else {
        $tokens += $token
        continue
      }
    }
    elseif($sa_state -eq 'array_processing') {
      if ("$token" -eq '}'){
        $array += ' }'
        $sa_state = 'init'
        $tokens += $array 
      }
      else {
        $array += " $token"
      }
      continue
    }
    elseif($sa_state -eq 'quoted_text_processing') {
      if ($token -eq '"') {
        $quoted_text = $quoted_text.trim() + '"'
        $sa_state = 'init'
        $tokens += $quoted_text
      }
      else {
        $quoted_text += "$token "
      }
      continue
    }
    else {
      Write-Verbose "Get to undefined state"
      continue
    }
  } 

  return $tokens
}

#Input: MIB tokens (use Get-Tokens)
#Output: Return MIB as list of powershell objects
function Parse-MIB($tokens) {
  #based on:
  # rfc2578 - SMIv2
  # rfc1215 - TRAP-TYPE
  # rfc2579 - TEXTAUL-CONVENTION
  # rfc2580 - OBJECT-GROUP and NOTIFICATION-GROUP
  $sa_status='init'
  ($object_name,$object_type,$object_syntax,$status,$description,$objects,$ID,$object_max_access,$object_units,$object_reference,$object_index,$object_augments,$object_defval,$notification_objects,$parent,$OID) = ('','','','','','','','','','','','','','','','')
  $imported_modules=''
  $counter = 0
  $currently_processing_macro = ''
  $mib = @()

  $debugMessage = "STARTING PARSING"
  Write-Debug $debugMessage
  $debugMessage = "PARSING: Number of objects in mib: " +$mib.Length 
  Write-Debug $debugMessage

  #below is not used yet (will see if I'll use it later
  $macro_tokens = ('MODULE-IDENTITY','OBJECT-TYPE','NOTIFICATION-TYPE','OBJECT IDENTIFIER','TEXTUAL-CONVENTION')
  $notification_type_tokens = ('OBJECTS','STATUS','DESCRIPTION','REFERENCE','::=')
  $object_type_tokens=('SYNTAX','UNITS','MAX-ACCESS','ACCESS','STATUS','DESCRIPTION','REFERENCE','INDEX','AUGMENTS','DEFVAL','::=')
  $trap_type_tokens = ('ENTERPRISE','VARIABLES','DESCRIPTION','REFERENCE')
  $textaul_convention_clauses = ('DISPLAY-HINT', 'STATUS', 'DESCRIPTION', 'REFERENCE', 'SYNTAX')
  
  #below is union of above arrays + MACRO
  $expected_type_tokens=('ENTERPRISE','VARIABLES','OBJECTS','SYNTAX','UNITS','MAX-ACCESS','ACCESS','DISPLAY-HINT','STATUS','DESCRIPTION','REFERENCE','INDEX','AUGMENTS','DEFVAL','::=','MACRO','OBJECT-GROUP','NOTIFICATION-GROUP','NOTIFICATIONS', 'MODULE-COMPLIANCE')

  foreach ($token in $tokens) {
    $debugMessage = "PARSING: Currently processing=$currently_processing_macro,Status=$sa_status,Token=$token,Counter=$counter"
    Write-Debug $debugMessage
    #just for sure
    $token = $token.trim()
    if ($sa_status -eq 'init') {
      if ($token -eq 'BEGIN') {
        if ($tokens[$counter-2]+$tokens[$counter-1]+$token -eq 'DEFINITIONS::=BEGIN') {
          $module_name = $tokens[$counter-3]
        }
      }
      #MACRO DEFINITIONS OF BASIC "OBJECTS PRIMITIVES" - SUCH AS OBJECT-TYPE, TRAP-TYPE ...
      elseif ($tokens[$counter+1] -eq 'MACRO') {
        $sa_status = 'MACRO'
        $object_name = $token
        $counter += 1
        continue
      }
      elseif ($token -eq 'IMPORTS') {
        $currently_processing_macro = $token
        $sa_status = 'IMPORTS'
        $imported_modules = '{ '
        $objects = '{ '
      }
      elseif ($token -eq 'MODULE-IDENTITY') {
        $currently_processing_macro = $token
        $sa_status = $token
        $object_type = $token
        $object_name = $tokens[$counter-1]
      }
      elseif ($token -eq 'MODULE-COMPLIANCE') {
        $currently_processing_macro = $token
        $sa_status = $token
        $object_type = $token
        $object_name = $tokens[$counter-1]
      }
      elseif ($token -eq 'IDENTIFIER' -and $tokens[$counter-1] -eq 'OBJECT') {
        $currently_processing_macro = 'OBJECT IDENTIFIER'
        $sa_status = 'OBJECT IDENTIFIER'
        $object_type = 'OBJECT IDENTIFIER'
        $object_name = $tokens[$counter-2]
      }
      elseif ($token -eq 'TEXTUAL-CONVENTION' -and $tokens[$counter-1] -eq '::=') {
        $currently_processing_macro = $token
        $sa_status = $token
        $object_type = $token
        $object_name = $tokens[$counter-2]
      }
      elseif ($token -eq 'OBJECT-IDENTITY') {
        $currently_processing_macro = 'OBJECT IDENTIFIER'
        $sa_status = 'OBJECT IDENTIFIER'
        $object_type = 'OBJECT IDENTIFIER'
        $object_name = $tokens[$counter-1]
      }
      elseif ($token -eq 'OBJECT-TYPE') {
        $currently_processing_macro = $token
        $sa_status = $token
        $object_type = $token
        $object_name = $tokens[$counter-1]
      }
      elseif ($token -eq 'OBJECT-GROUP') {
        $currently_processing_macro = $token
        $sa_status = $token
        $object_type = $token
        $object_name = $tokens[$counter-1]
      }      
      elseif ($token -eq 'NOTIFICATION-GROUP') {
        $currently_processing_macro = $token
        $sa_status = $token
        $object_type = $token
        $object_name = $tokens[$counter-1]
      }
      elseif ($token -eq 'NOTIFICATION-TYPE') {
        $currently_processing_macro = $token
        $sa_status = $token
        $object_type = $token
        $object_name = $tokens[$counter-1]
      }
      elseif ($token -eq 'TRAP-TYPE') {
        $currently_processing_macro = $token
        $sa_status = $token
        $object_type = $token
        $object_name = $tokens[$counter-1]
      }
      elseif ($token -eq 'SEQUENCE') {
        $currently_processing_macro = $token
        $sa_status = $token
        $object_type = $token
        $object_name = $tokens[$counter-2]
      }
      elseif ($token -eq '::=') {
        #it's TEXTUAL-CONVENTION with direct SYNTAX
        #hence $sa_status gonna be syntax
        #however need to check if 
        #  not DEFINITIONS ::= BEGIN
        #  or not proper 'TEXTUAL-CONVENTION' macro
        if ( ($tokens[$counter-1]+$token+$tokens[$counter+1] -ne 'DEFINITIONS::=BEGIN') -and ($tokens[$counter+1] -ne 'TEXTUAL-CONVENTION')){
          $sa_status ='SYNTAX'
          $currently_processing_macro = 'TEXTUAL-CONVENTION'
          $object_type = 'TEXTUAL-CONVENTION'
          $object_name = $tokens[$counter-1]
        }  
      }
      $object_name = $object_name.trim()
      $counter += 1
      continue

    }
    elseif ($sa_status -eq 'IMPORTS') {
      if ($token -eq 'FROM') {
        $sa_status = 'FROM'
        $counter += 1
        continue
      }
      else {
        $objects += $token
        $counter += 1
        continue
      }
    }
    elseif ($sa_status -eq 'FROM') {
      $module = $token
      $module = $module -replace ';', ''
      $sa_status = 'IMPORTS'
      $imported_modules += $module + ', '
      $objects += ' }'
      $objectProperties = @{ objectName = $module; objectType = 'IMPORT'; objectSyntax = $object_syntax; status = $status; defval = $object_defval; units = $object_units; augments = $object_augments; maxAccess = $object_max_access; reference = $object_reference; index = $object_index ; description = "Objects imported from Module: $module"; objects = $objects; ID = $ID; parent = $parent; OID = $OID; module = $module_name; objectFullName = "$module_name::" }
      $object = New-Object psobject -Property $objectProperties
      $mib += $object
      $debugMessage = "PARSING: Creating Object=$object"
      Write-Debug $debugMessage
      $debugMessage = "PARSING: Number of objects in mib: " +$mib.Length 
      Write-Debug $debugMessage
      ($object_name,$object_type,$object_syntax,$status,$description,$objects,$ID,$object_max_access,$object_units,$object_reference,$object_index,$object_augments,$object_defval,$notification_objects,$parent,$OID) = ('','','','','','','','','','','','','','','','')
      $objects = '{ '
      if ($token.endswith(';')) {
        $imported_modules += '}'
        $imported_modules = $imported_modules -replace ', }', ' }'
        $objectProperties = @{ objectName = 'IMPORTS'; objectType = 'IMPORTS'; objectSyntax = $object_syntax; status = $status; defval = $object_defval; units = $object_units; augments = $object_augments; maxAccess = $object_max_access; reference = $object_reference; index = $object_index ; description = $description; objects = $imported_modules; ID = $ID; parent = $parent; OID = $OID; module = $module_name; objectFullName = "$module_name::$object_name" }
        $object = New-Object psobject -Property $objectProperties
        $mib += $object
        $debugMessage = "PARSING: Creating Object=$object"
        Write-Debug $debugMessage
        $debugMessage = "PARSING: Number of objects in mib: " +$mib.Length 
        Write-Debug $debugMessage
        ($object_name,$object_type,$object_syntax,$status,$description,$objects,$ID,$object_max_access,$object_units,$object_reference,$object_index,$object_augments,$object_defval,$notification_objects,$parent,$OID) = ('','','','','','','','','','','','','','','','')
        $sa_status = 'init'
      }
      $counter += 1
      continue
    } 
    #MODULE-COMPLIANCE not fully implemented
    elseif ($sa_status -eq 'MODULE-COMPLIANCE') {
      if ($token -eq '::=') {
        $sa_status = '::='
        $counter += 1
        continue
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'MODULE-IDENTITY') {
      if ($token -eq '::=') {
        $sa_status = '::='
        $counter += 1
        continue
      }
      elseif ($token -eq 'DESCRIPTION') {
        #need to get just first descritption
        if ($description -eq '') {
          $description = $tokens[$counter+1]
        }
        $counter += 1
        continue
      }
      elseif ($token -eq 'MACRO') {
        $sa_status = 'MACRO'
        $object_name = 'DESCRIPTION'
        $counter += 1
        continue
      }
    }
    elseif ($sa_status -eq 'OBJECT IDENTIFIER') {
      if ($token -eq '::=') {
        $sa_status = '::='
        $counter += 1
        continue
      }
      #HERE THIS MUST BE BECAUSE IN INIT STATE IT LOOKS JUST ONE TOKEN AHEAD
      elseif ($token -eq 'MACRO') {
        $sa_status = 'MACRO'
        $object_name = 'OBJECT IDENTIFIER'
        $counter += 1
        continue
      }
      
    }
    elseif ($sa_status -eq 'OBJECT-TYPE') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token 
          break
        }
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'TEXTUAL-CONVENTION') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token 
          break
        }
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'NOTIFICATION-GROUP') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token
          break 
        }
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'OBJECT-GROUP') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token
          break 
        }
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'NOTIFICATION-TYPE') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token 
          break
        }
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'TRAP-TYPE') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token
          break 
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
          break 
        }
      }
      if ($currently_processing_macro -eq 'TEXTUAL-CONVENTION') {
        if (($tokens[$counter+1] -in ('MODULE-IDENTITY', '::=', 'OBJECT-IDENTITY', 'OBJECT-TYPE','NOTIFICATION-TYPE', 'MODULE-COMPLIANCE', 'OBJECT-GROUP','NOTIFICATION-GROUP','END')) -or ($tokens[$counter+3] -eq '::=' -and $tokens[$counter+2] -eq 'IDENTIFIER') ) {
          $sa_status = 'init'
          $object_syntax = $object_syntax.trim()
          $objectProperties = @{ objectName = $object_name; objectType = $object_type; objectSyntax = $object_syntax; status = $status; defval = $object_defval; units = $object_units; augments = $object_augments; maxAccess = $object_max_access; reference = $object_reference; index = $object_index ; description = $description; objects = $notification_objects; ID = $ID; parent = $parent; OID = $OID; module = $module_name; objectFullName = "$module_name::$object_name" }
          $object = New-Object psobject -Property $objectProperties
          $mib += $object
          $debugMessage = "PARSING: Creating Object=$object"
          Write-Debug $debugMessage
          $debugMessage = "PARSING: Number of objects in mib: " +$mib.Length 
          Write-Debug $debugMessage
          ($object_name,$object_type,$object_syntax,$status,$description,$objects,$ID,$object_max_access,$object_units,$object_reference,$object_index,$object_augments,$object_defval,$notification_objects,$parent,$OID) = ('','','','','','','','','','','','','','','','')
        }
      }
      if ($sa_status -eq 'SYNTAX') {
        $object_syntax += $token + " "
      }
      else {
        #unexpected token
        #$debugMessage = "UNEXPECTED STATE"
        #Write-Debug $debugMessage
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'UNITS') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token
          $object_units = $object_units.trim()
          break 
        }
      }
      if ($sa_status -eq 'UNITS') {
        $object_units += $token + " "
      }
      else {
        #unexpected token
        #$debugMessage = "UNEXPECTED STATE"
        #Write-Debug $debugMessage
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'MAX-ACCESS') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token
          $object_max_access = $object_max_access.trim()
          break 
        }
      }
      if ($sa_status -eq 'MAX-ACCESS') {
        $object_max_access += $token + " "
      }
      else {
        #unexpected token
        #$debugMessage = "UNEXPECTED STATE"
        #Write-Debug $debugMessage
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'ACCESS') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token
          $object_max_access = $object_max_access.trim()
          break 
        }
      }
      if ($sa_status -eq 'ACCESS') {
        $object_max_access += $token + " "
      }
      else {
        #unexpected token
        #$debugMessage = "UNEXPECTED STATE"
        #Write-Debug $debugMessage
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'STATUS') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token
          $status = $status.trim()
          break 
        }
      }
      if ($currently_processing_macro -eq 'TEXTUAL-CONVENTION') {
        if (($tokens[$counter+1] -in ('::=', 'OBJECT-IDENTITY', 'OBJECT-TYPE','NOTIFICATION-TYPE', 'MODULE-COMPLIANCE', 'OBJECT-GROUP','NOTIFICATION-GROUP')) -or ($tokens[$counter+2] -eq '::=' -and $tokens[$counter+1] -eq 'IDENTIFIER') ) {
          $sa_status = 'init'
          $status = $status.trim()
          $objectProperties = @{ objectName = $object_name; objectType = $object_type; objectSyntax = $object_syntax; status = $status; defval = $object_defval; units = $object_units; augments = $object_augments; maxAccess = $object_max_access; reference = $object_reference; index = $object_index ; description = $description; objects = $notification_objects; ID = $ID; parent = $parent; OID = $OID; module = $module_name; objectFullName = "$module_name::$object_name" }
          $object = New-Object psobject -Property $objectProperties
          $mib += $object
          $debugMessage = "PARSING: Creating Object=$object"
          Write-Debug $debugMessage
          $debugMessage = "PARSING: Number of objects in mib: " +$mib.Length 
          Write-Debug $debugMessage
          ($object_name,$object_type,$object_syntax,$status,$description,$objects,$ID,$object_max_access,$object_units,$object_reference,$object_index,$object_augments,$object_defval,$notification_objects,$parent,$OID) = ('','','','','','','','','','','','','','','','')
        }
      }
      if ($sa_status -eq 'STATUS') {
        $status += $token + " "
      }
      else {
        #unexpected token
        #$debugMessage = "UNEXPECTED STATE"
        #Write-Debug $debugMessage
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'DESCRIPTION') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token
          break
        }  
      }
      if ($currently_processing_macro -eq 'TEXTUAL-CONVENTION') {
        if (($tokens[$counter+1] -in ('::=', 'OBJECT-IDENTITY', 'OBJECT-TYPE','NOTIFICATION-TYPE', 'MODULE-COMPLIANCE', 'OBJECT-GROUP','NOTIFICATION-GROUP')) -or ($tokens[$counter+2] -eq '::=' -and $tokens[$counter+1] -eq 'IDENTIFIER') ) {
          $sa_status = 'init'
          $description = $description.trim()
          $objectProperties = @{ objectName = $object_name; objectType = $object_type; objectSyntax = $object_syntax; status = $status; defval = $object_defval; units = $object_units; augments = $object_augments; maxAccess = $object_max_access; reference = $object_reference; index = $object_index ; description = $description; objects = $notification_objects; ID = $ID; parent = $parent; OID = $OID; module = $module_name; objectFullName = "$module_name::$object_name" }
          $object = New-Object psobject -Property $objectProperties
          $mib += $object
          $debugMessage = "PARSING: Creating Object=$object"
          Write-Debug $debugMessage
          $debugMessage = "PARSING: Number of objects in mib: " +$mib.Length 
          Write-Debug $debugMessage
          ($object_name,$object_type,$object_syntax,$status,$description,$objects,$ID,$object_max_access,$object_units,$object_reference,$object_index,$object_augments,$object_defval,$notification_objects,$parent,$OID) = ('','','','','','','','','','','','','','','','')
        }
      }
      if ($sa_status -eq 'DESCRIPTION' -and $token.startswith('"')) {
        $description = $token
      }
      else {
        #unexpected token
        #$debugMessage = "UNEXPECTED STATE"
        #Write-Debug $debugMessage
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'REFERENCE') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token
          $object_reference = $object_reference.trim()
          break  
        }
      }
      if ($currently_processing_macro -eq 'TEXTUAL-CONVENTION') {
        if (($tokens[$counter+1] -in ('::=', 'OBJECT-IDENTITY', 'OBJECT-TYPE','NOTIFICATION-TYPE', 'MODULE-COMPLIANCE', 'OBJECT-GROUP','NOTIFICATION-GROUP')) -or ($tokens[$counter+2] -eq '::=' -and $tokens[$counter+1] -eq 'IDENTIFIER') ) {
          $sa_status = 'init'
          $object_reference = $object_reference.trim()
          $objectProperties = @{ objectName = $object_name; objectType = $object_type; objectSyntax = $object_syntax; status = $status; defval = $object_defval; units = $object_units; augments = $object_augments; maxAccess = $object_max_access; reference = $object_reference; index = $object_index ; description = $description; objects = $notification_objects; ID = $ID; parent = $parent; OID = $OID; module = $module_name; objectFullName = "$module_name::$object_name" }
          $object = New-Object psobject -Property $objectProperties
          $mib += $object
          $debugMessage = "PARSING: Creating Object=$object"
          Write-Debug $debugMessage
          $debugMessage = "PARSING: Number of objects in mib: " +$mib.Length 
          Write-Debug $debugMessage
          ($object_name,$object_type,$object_syntax,$status,$description,$objects,$ID,$object_max_access,$object_units,$object_reference,$object_index,$object_augments,$object_defval,$notification_objects,$parent,$OID) = ('','','','','','','','','','','','','','','','')
        }
      }
      if ($sa_status -eq 'REFERENCE') {
        $object_reference += $token + " "
      }
      else {
        #unexpected token
        #$debugMessage = "UNEXPECTED STATE"
        #Write-Debug $debugMessage
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'DISPLAY-HINT') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token
          $display_hint = $display_hint.trim()
          break 
        }
      }
      if ($currently_processing_macro -eq 'TEXTUAL-CONVENTION') {
        if (($tokens[$counter+1] -in ('::=', 'OBJECT-IDENTITY', 'OBJECT-TYPE','NOTIFICATION-TYPE', 'MODULE-COMPLIANCE', 'OBJECT-GROUP','NOTIFICATION-GROUP')) -or ($tokens[$counter+2] -eq '::=' -and $tokens[$counter+1] -eq 'IDENTIFIER') ) {
          $sa_status = 'init'
          $display_hint = $display_hint.trim()
          $objectProperties = @{ objectName = $object_name; objectType = $object_type; objectSyntax = $object_syntax; status = $status; defval = $object_defval; units = $object_units; augments = $object_augments; maxAccess = $object_max_access; reference = $object_reference; index = $object_index ; description = $description; objects = $notification_objects; ID = $ID; parent = $parent; OID = $OID; module = $module_name; objectFullName = "$module_name::$object_name" }
          $object = New-Object psobject -Property $objectProperties
          $mib += $object
          $debugMessage = "PARSING: Creating Object=$object"
          Write-Debug $debugMessage
          $debugMessage = "PARSING: Number of objects in mib: " +$mib.Length 
          Write-Debug $debugMessage
          ($object_name,$object_type,$object_syntax,$status,$description,$objects,$ID,$object_max_access,$object_units,$object_reference,$object_index,$object_augments,$object_defval,$notification_objects,$parent,$OID) = ('','','','','','','','','','','','','','','','')
        }
      }
      if ($sa_status -eq 'DISPLAY-HINT') {
        $display_hint += $token + ' '
      }
      else {
        #unexpected token
        #$debugMessage = "UNEXPECTED STATE"
        #Write-Debug $debugMessage
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'INDEX') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token
          $object_index = $object_index.trim() 
          break 
        }
      }
      if ($sa_status -eq 'INDEX') {
        $object_index += $token + " "
      }
      else {
        #unexpected token
        #$debugMessage = "UNEXPECTED STATE"
        #Write-Debug $debugMessage
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'AUGMENTS') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token
          $object_augments = $object_augments.trim()
          break
        }
      }
      if ($sa_status -eq 'AUGMENTS') {
        $object_augments += $token + " "
      }
      else {
        #unexpected token
        #$debugMessage = "UNEXPECTED STATE"
        #Write-Debug $debugMessage
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'DEFVAL') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token
          $object_defval = $object_defval.trim()
          break 
        }
      }
      if ($sa_status -eq 'DEFVAL') {
        $object_defval += $token + " "
      }
      else {
        #unexpected token
        #$debugMessage = "UNEXPECTED STATE"
        #Write-Debug $debugMessage
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'OBJECTS' -or $sa_status -eq 'VARIABLES' -or $sa_status -eq 'NOTIFICATIONS') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token
          $object_defval = $object_defval.trim() 
          break
        }
      }
      if ( ($sa_status -eq 'OBJECTS' -or $sa_status -eq 'VARIABLES' -or $sa_status -eq 'NOTIFICATIONS') -and $token.startswith('{')) {
        $notification_objects = $token
      }
      else {
        #unexpected token
        #$debugMessage = "UNEXPECTED STATE"
        #Write-Debug $debugMessage
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'ENTERPRISE') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token
          break
        }
      }
      if ($sa_status -eq 'ENTERPRISE') {
        $parent = $token
      }
      else {
        #unexpected token
        #$debugMessage = "UNEXPECTED STATE"
        #Write-Debug $debugMessage
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq '::=') {
      if ($object_type -eq 'TRAP-TYPE') {
        $ID = $token.trim()
      }
      elseif ($token.startswith('{')) {
        $token = $token -replace '{', ''
        $token = $token -replace '}', ''
        $token = $token.trim()
        $nodes = $token -split ' '
        #because OID assignment can be done as:
        #{ parent ID }
        # or
        #{ <subtree> ID } for example { netapp 0 777 }
        #we need to check it and separate ID and "parent" accordingly
        if ($nodes.Count -gt 2) {
          $ID = $nodes[-1]
          $ID = $ID.trim()
          foreach ($node in $nodes[0..($nodes.Count - 2)]) {
            #as there can be also OID assignments like below need to go through all nodes and get just numbers
            #{ iso(1) member-body(2) us(840) ieee802dot3(10006) snmpmibs(300) 43 } 
            if ($node -match '\(\d+\)'){
              $node = $node -replace ".*\(", ''
              $node = $node -replace "\)", '' 
            }
            $parent += $node.trim() + '.'
          }
          $parent = $parent.trim('.')
        }
        else {
          ($parent,$ID) = $nodes
          $parent = $parent.trim()
          $ID = $ID.trim()
        }
      }
      else {
        #unexpected
        $debugMessage = "UNEXPECTED STATE"
        Write-Debug $debugMessage
        $sa_status = 'init'
        $counter += 1
        continue
      }

      $OID = $parent + '.' + $ID
      $objectProperties = @{ objectName = $object_name; objectType = $object_type; objectSyntax = $object_syntax; status = $status; defval = $object_defval; units = $object_units; augments = $object_augments; maxAccess = $object_max_access; reference = $object_reference; index = $object_index ; description = $description; objects = $notification_objects; ID = $ID; parent = $parent; OID = $OID; module = $module_name; objectFullName = "$module_name::$object_name" }
      $object = New-Object psobject -Property $objectProperties
      $mib += $object
      $debugMessage = "PARSING: Creating Object=$object"
      Write-Debug $debugMessage
      $debugMessage = "PARSING: Number of objects in mib: " +$mib.Length 
      Write-Debug $debugMessage
      $sa_status = 'init'
      ($object_name,$object_type,$object_syntax,$status,$description,$objects,$ID,$object_max_access,$object_units,$object_reference,$object_index,$object_augments,$object_defval,$notification_objects,$parent,$OID) = ('','','','','','','','','','','','','','','','')
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'MACRO') {
      #just skip MACRO DEFINITION
      if ($token -eq 'END') {
        #but create and obejct, because of the IMPORT dependencies
        $objectProperties = @{ objectName = $object_name; objectType = 'MACRO'; objectSyntax = ''; status = ''; description = ''; objects = ''; ID = ''; parent = ''; OID = ''; module = $module_name; objectFullName = "$module_name::$object_name" }
        $object = New-Object psobject -Property $objectProperties
        $mib += $object
        $debugMessage = "PARSING: Creating Object=$object"
        Write-Debug $debugMessage
        $debugMessage = "PARSING: Number of objects in mib: " +$mib.Length 
        Write-Debug $debugMessage
        $sa_status = 'init'
        ($object_name,$object_type,$object_syntax,$status,$description,$objects,$ID,$object_max_access,$object_units,$object_reference,$object_index,$object_augments,$object_defval,$notification_objects,$parent,$OID) = ('','','','','','','','','','','','','','','','')
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'SEQUENCE') {
      if ($token.startswith('{')){
        $objectProperties = @{ objectName = $object_name; objectType = $object_type; objectSyntax = 'SEQUENCE'; status = ''; description = ''; objects = $token; ID = ''; parent = ''; OID = ''; module = $module_name; objectFullName = "$module_name::$object_name" }
        $object = New-Object psobject -Property $objectProperties
        $mib += $object
        $debugMessage = "PARSING: Creating Object=$object"
        Write-Debug $debugMessage
        $debugMessage = "PARSING: Number of objects in mib: " +$mib.Length 
        Write-Debug $debugMessage
        $sa_status = 'init'
        ($object_name,$object_type,$object_syntax,$status,$description,$objects,$ID,$object_max_access,$object_units,$object_reference,$object_index,$object_augments,$object_defval,$notification_objects,$parent,$OID) = ('','','','','','','','','','','','','','','','')
        $counter += 1
        continue
      }
      else {
        #unexpected state
        $debugMessage = "UNEXPECTED STATE"
        Write-Debug $debugMessage
      }
      $counter += 1
      continue
      
    }
    $counter += 1
  }
  $debugMessage = "PARSING: Number of objects in mib: " +$mib.Length 
  Write-Debug $debugMessage
  $debugMessage = "END PARSING" 
  Write-Debug $debugMessage
  return $mib
}

#Check OID if all "nodes" are numbers then return true
function Is-Full-OID($OID) {
  $is_Full_OID = $true
  foreach ($ID in $OID.split('.')){
    if (!($ID -match "^[\d\.]+$")) {
      $is_Full_OID = $false
    }
  }
  return $is_Full_OID
}

#TO BE EDITED IT SHALL BE STAND ALONE FUNTION??? REALLY? NOT SURE
function Update-OIDRepo($new_mib, $OIDrepo) {
  $new_updates = $false
  $mibrepo = Import-CSV $OIDrepo
  foreach ($new_object in $new_mib) {
    $newOID = $new_object.OID
    $newObjectFullName = $new_object.objectFullName
    #$module_name = $new_object.module
    $excluded_types = ('IMPORTS', 'IMPORT', 'SEQUENCE', 'TEXTUAL-CONVENTION', 'MACRO' )
    #if (!(Is-Full-OID $newOID) -and ($new_object.objectType -ne 'IMPORTS') -and ($new_object.objectType -ne 'IMPORT') -and ($new_object.objectType -ne 'SEQUENCE') -and ($new_object.objectType -ne 'TEXTUAL-CONVENTION') ) {
    if (!(Is-Full-OID $newOID) -and ($new_object.objectType -notin $excluded_types )) {
      Write-Output "ERROR: $newObjectFullName($newOID) is not fully resolved"
    }
    elseif (!($mibrepo| Where-Object {$_.objectFullName -ceq $newObjectFullName})) {
      $mibrepo += $new_object
      $new_updates = $true
      Write-verbose ($new_object.objectName + " added to $OIDrepo")
    }
    else {
      if ($newOID -ne '') {
        Write-Output "WARNING: adding $newOID record with same OID already exist in $OIDrepo."
      }
    }
  }
  if ($new_updates) {
    $mibrepo| Export-CSV -Path $OIDrepo -NoTypeInformation | Out-Null
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
    File with csv records generated, by Import-MIB (repo delivered with the module standard.csv contains standard MIBs ) 
    It helps to resolve the OID to full number without it you might get resolution to highest object in MIB. Like this:
    enterprises.6574.1
.PARAMETER UpdateOIDRepo
    This will udpate the OIDRepo file you provide as -OIDRepo parameter. 
.PARAMETER silent
    Used in combination with UpdateOIDRepo. In order to not print out the mib objects.      
    
.NOTES  
    Module Name    : MIB-Processing  
    Author         : Jiri Kindl; kindl_jiri@yahoo.com
    Prerequisite   : PowerShell V2 over Vista and upper.
    Version        : 20220508
    Copyright 2020 - Jiri Kindl
.LINK  
    
.EXAMPLE
    Import-MIB -Path .\SYNOLOGY-SYSTEM-MIB.mib
    Process the MIB and returns the as array of objects

.EXAMPLE 
    Import-MIB -Path .\SYNOLOGY-SYSTEM-MIB.mib -OIDrepo .\all.csv
    Process the MIB and returns the as array of objects. Use OIDrepo file to resolve OIDs 

.EXAMPLE
    Import-MIB -Path .\SYNOLOGY-SYSTEM-MIB.mib -OIDrepo .\all.csv -UpdateOIDRepo
    Process the MIB and returns the as array of objects. Use OIDrepo file to resolve OIDs and update the same OIDrepo file. 

.EXAMPLE
    Import-MIB -Path .\ThreeParMIB.mib -OIDrepo .\all.csv | Export-Csv -Path .\3PAR.csv            
    To get output into CSV file

.EXAMPLE
    Import-MIB -Path .\ThreeParMIB.mib -OIDrepo .\all.csv | Select-Object objectName,objectType,status,description,objects,ID,parent,OID | Export-Csv -Path .\3PAR.csv            
    To get complete output into CSV file

.EXAMPLE
    cat .\ThreeParMIB.mib | Import-MIB -OIDrepo .\all.csv | Select-Object objectName,objectType,status,description,objects,ID,parent,OID | Export-Csv -Path .\3PAR.csv            
    To get complete output into CSV file
.EXAMPLE
    foreach ($mib in ls *.mib) { $csv = $mib.basename + '.csv'; echo $csv ;Import-MIB $mib -OIDrepo .\cisco-mds-san.csv | export-csv -NoTypeInformation $csv }
    Convert all MIBs to CSV using OIDrepo     
#>

  #pars parametrs with param
  [CmdletBinding()]
  param([Parameter(Position=0)][string]$Path, [string]$OIDrepo, [switch]$UpdateOIDRepo, [switch]$HPConfig ,[switch]$silent,
  [parameter(ValueFromPipeline=$true)][string]$pipelineInput)

  BEGIN {
    $mib = @()
    #$OIDs = @()
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
    Write-verbose "Removing Comments"
    $noCommentLines = Remove-Comments $lines
    Write-verbose "Comments Removed"

    Write-Verbose "Parsing to tokens"
    $tokens = Get-Tokens $noCommentLines
    Write-verbose "MIB Parsed to tokens"
    
    Write-verbose "Starting parsing to objects"
    $mib = Parse-MIB $tokens
    Write-verbose "MIB Parsed to Powershell objects"

    Write-Verbose "Internal scope OID Expantion"

    $debugMessage = "Number of objects in mib: " + $mib.Length
    Write-Debug $debugMessage
    
    #Expand OID from parent.ID to full path in MIB scope
    $updated = $true
    while ($updated) {
      $updated = $false
      foreach ($object in $mib | Where-Object {$_.OID -ne ''}) {
        $verboseMessage = "Resolving " + $object.objectName
        Write-Verbose "$verboseMessage"
        Write-Debug "$object"
        if (!(($object.OID).split('.')[0] -match "^[\d\.]+$")) {
          $unresolvedObject = $mib | Where-Object {$_.objectName -ceq ($object.OID).split('.')[0]  -and  ($_.objectType -ne 'SEQUENCE' -and  $_.objectType -ne 'TEXTUAL-CONVENTION') }
          if ($unresolvedObject) {
            $verboseMessage = "Got parent " + $unresolvedObject.objectName
            Write-Verbose "$verboseMessage"
            $object.OID = $object.OID -replace ($object.OID).split('.')[0], $unresolvedObject.OID
            $verboseMessage = "Updated OID to " + $object.OID
            Write-Verbose "$verboseMessage"
            $updated = $true
          }
        }
      }
    }

   
    #resolve OIDs to numbers (using OID repo file) And Update OID repo if switch UpdateOIDRepo is used
    if ($OIDRepo) {
      Write-Verbose "OID Repository resolution"
      $mibrepo=Import-CSV $OIDrepo

      #Check if required imports are part of OID Repo:
      if ($UpdateOIDRepo) {
        $can_be_translated = $true
        $missingDependeincies = ''
        foreach ($import in $mib | Where-Object {$_.objectType -eq "IMPORT"}) {
          foreach ($imported_object in (($import.objects -replace '{ ', '') -replace ' }', '') -split ',' ){
            $imported_object_fn = $import.objectName + "::" + $imported_object
            $verboseMessage = "Checking if the imported object is in OIDrepo " + $imported_object_fn
            Write-Verbose "$verboseMessage"
            $repo_SearchResults = $mibrepo | Where-Object {$_.objectFullName -ceq $imported_object_fn}
            if (!$repo_SearchResults) {
              $can_be_translated = $false
              $verboseMessage = "Missing dependency: " + $imported_object_fn
              Write-Verbose "$verboseMessage"
              $missingDependeincies += "$imported_object_fn,"
            }
            if (!$can_be_translated) {
              $errorMessage = "Missing dependency for: $Path; Depencies: $missingDependeincies"
              Write-Error $errorMessage -ErrorAction Stop
            }
          }
        }
      }
      #Try to translate OID to absolute whole OID (numbers and dots only)
      foreach ($object in $mib | Where-Object {$_.OID -ne ''}) {
        $oid=$object.OID
        Write-Verbose "Resolving: $OID"
        $object_name_to_search = $oid.split('.')[0]
        Write-Verbose "Looking for: $object_name_to_search"
        $repo_SearchResults = $mibrepo | Where-Object {$_.objectName -ceq $object_name_to_search}
        $imported_objects = ($mib | Where-Object {$_.objectName -eq 'IMPORTS'}).objects
        $imported_objects = $imported_objects -replace '{', ''
        $imported_objects = $imported_objects -replace '}', ''
        $imported_objects = $imported_objects -replace ' ', ''
        if ($repo_SearchResults) {
          Write-Verbose "Got results from repo: $repo_SearchResults"
          foreach ($repo_SearchResult in $repo_SearchResults) {
            if ($imported_objects.split(',') -contains $repo_SearchResult.module){
              $resolvedOID = $repo_SearchResult.OID
              $newOID = $oid -replace $object_name_to_search, $resolvedOID
              $object.OID = $newOID
              Write-Verbose "Resolved to: $newOID"
              break
            }
          }
          #Because some MIB authors don't believe in IMPORT or IMPORT enterprises is too main stream they define whole structure in their MIB
          #Hence need to hardcode here iso to be 1
          if ($object_name_to_search -ceq 'iso') {
            Write-Verbose "Resolving iso"
            $resolvedOID = '1'
            $newOID = $oid -replace $object_name_to_search, $resolvedOID
            $object.OID = $newOID
          }
          Write-Verbose "Got results from repo: $repo_SearchResults"
        }
        else {
          Write-Verbose "ERROR: $object_name_to_search from $Path not found in $OIDrepo"
        }
      }
    }

    if ($UpdateOIDRepo) {
      #$mib_object | Export-Csv -Path $OIDrepo -NoTypeInformation -Append
      Update-OIDRepo $mib $OIDrepo
    }
    if (!$silent){
      return $mib
    }
  }
}

function ConvertTo-Snmptrap {
  <#  
.SYNOPSIS  
    Convert TRAP-TYPE or NOTIFYCATION-TYPE MIB Objects to snmptrap commands, which can be used for testing. 
.DESCRIPTION  
    Convert TRAP-TYPE or NOTIFYCATION-TYPE MIB Objects, generated by Improt-MIB to snmptrap commands, which can be used for testing.
    Use -OIDrepo to get resolved objects/varaibles and -OIDs to generate command with OID numbers rather the names. 
    Using OIDs rather the names let you use the command on device where MIB(s) not loaded
  
.PARAMETER Path
    The path and file name of CSV file generated by Import-MIB
    If you use the CSV as input make sure the CSV was generated with -UseCulture
.PARAMETER OIDrepo
    File with csv records generated, by Import-MIB (repo delivered with the module standard.csv contains standard MIBs ) 
    It helps to resolve the Objects which are in IMPORTS
.PARAMETER OIDs
    Use rather OIDs (number separated by dots) then Full Names of objects/varaibles.
    It's usefull to run test snmptrap from device/server where the relevant MIB(s) is not loaded.
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
    Version        : 20210128
    Copyright 2020 - Jiri Kindl
.LINK  
    
.EXAMPLE
    ConvertTo-Snmptrap -Path .\NIMBLE.csv
    Convert CSV file generated by Import-MIB. !NOTE: use | Export-Csv -UseCulture otherwise it will not work.

.EXAMPLE 
    Import-Csv -UseCulture -Path .\NIMBLE.csv | ConvertTo-Snmptrap 
    Convert CSV file generated by Import-MIB. !NOTE: you need to use -UseCUlture switch with Import-CSV if the CSV file was generated with -UseCulture

.EXAMPLE
    cat .\ThreeParMIB.mib | Import-MIB -OIDrepo .\myOIDrepo.csv | ConvertTo-Snmptrap
    To generate snmptrap commands for testing based on ThreeParMIB.mib file

.EXAMPLE
    cat .\ThreeParMIB.mib | Import-MIB -OIDrepo .\myOIDrepo.csv| ConvertTo-Snmptrap -OIDrepo .\myOIDrepo
    To generate snmptrap commands for testing based on ThreeParMIB.mib file and use OIDrepo to resolve objects which are not directly defined in this MIB

.EXAMPLE
    cat .\ThreeParMIB.mib | Import-MIB -OIDrepo .\myOIDrepo.csv | ConvertTo-Snmptrap -OIDrepo .\myOIDrepo -OIDs
    To generate snmptrap commands for testing based on ThreeParMIB.mib file and use OIDrepo to resolve objects which are not directly defined in this MIB.
    Also resolves objects/variable names to OIDs, so you can send test trap from device or server where relevant MIB(s) are not loaded.

.EXAMPLE
    cat .\ThreeParMIB.mib | Import-MIB -OIDrepo .\myOIDrepo.csv | ConvertTo-Snmptrap -SnmpVersion 2
    To generate snmptrap commands, with version 2 traps, for testing based on ThreeParMIB.mib file

.EXAMPLE
    foreach ($csv in ls *.csv) {if(Select-String -Quiet "NOTIFICATION-TYPE" $csv){$notif_file = $csv.basename + '.notifs';ConvertTo-Snmptrap -SnmpVersion 2 -OIDs -OIDrepo ..\..\myRepo.csv $csv > $notif_file}}
    The above command will generate files (.notifs) with SMIv2 snmptrap commands for all the csv files containing "NOTIFICATION-TYPE" 
.EXAMPLE
    foreach ($csv in ls *.csv) {if(Select-String -Quiet "TRAP-TYPE" $csv){$trap_file = $csv.basename + '.traps';ConvertTo-Snmptrap -OIDs -OIDrepo ..\..\myRepo.csv $csv > trap_file}}
    The above command will generate files (.traps) with SMIv1 snmptrap commands for all the csv files containing "TRAP-TYPE" 
  #>

  #pars parametrs with param
  [CmdletBinding()]
  param([Parameter(Position=0)][string]$Path, 
  [parameter(ValueFromPipeline=$true)]$pipelineInput,
  [string]$OIDrepo,
  [string]$SnmpVersion = '1',
  $TrapReciever = 'TrapRecieverIP',
  $Community = 'public',
  [switch]$OIDs
  )

  BEGIN {
    $mib = @()
    $test_string = 'Test string'
    $test_number = 3
    $test_ip = '10.10.10.10'
    $test_oid = '0.0'
    try {
      if ($Path) {
        $mib= Import-Csv -Path $Path -ErrorAction Stop
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
    if ($OIDrepo) {
      if (!(Test-Path -Path $OIDrepo)) {
        Write-Host "ERROR: $OIDrepo doesn't exist"
        Get-Help ConvertTo-Snmptrap
      } 
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
    if ($OIDRepo) {
      Write-Verbose "OID Repository resolution"
      $mibrepo=Import-CSV $OIDrepo
      
      $imported_modules = ($mib | Where-Object {$_.objectName -eq 'IMPORTS'}).objects
      $imported_modules = ((($imported_modules -replace '{', '') -replace '}', '') -replace ' ', '').split(',')
      #Write-Verbose "Importeds modules"
      #$imported_modules 
    }
    
    $traps = $mib | Where-Object {($_.objectType -EQ "TRAP-TYPE" -or $_.objectType -EQ "NOTIFICATION-TYPE")}
    if ($traps) {
      #$traps
      foreach ($trap in $traps) {
        #$trap.OID
        $object_names = (($trap.objects -replace "{") -replace "}") -split ","
        $objects_parameters = ''
        #default is v 1, and if unsupported version is used it falls back to v 1
        $snmp_command = "snmptrap -v 1 -c $Community $TrapReciever "
        if ($object_names -ne '') {
          foreach ($object_name in $object_names) {
            $object_name = $object_name.trim()
            $object = $mib | Where-Object {($_.objectName -EQ $object_name)}

            if (!$object) {
              if ($OIDrepo) {
                foreach ($module in $imported_modules) {
                  $object = $mibrepo | Where-Object {($_.objectName -EQ $object_name -and $_.module -EQ $module -and $_.objectType -NE 'TEXTUAL-CONVENTION')}
                  if ($object) {
                    break
                  }
                }
              if (!$object) {
                $errorMessage = "$object_name not resolved, checked the IMPORT section of MIB and update OIDrepo with corresponding MIBs for more details see Get-Help Import-MIB"
                Write-Error $errorMessage
              }
            }
            else {
              $errorMessage = "$object_name not found run with -OIDrepo see Get-Help ConvertTo-Snmptrap"
              write-error $errorMessage
            }
          }

            if ($OIDs) {
              $objects_parameters += $object.OID + '.0'
            }
            else {
              $objects_parameters += $object.objectFullName + '.0'
            }
            #Numbers
            if (($object.objectSyntax -match 'INTEGER') -or ($object.objectSyntax -match 'TimeTicks')) {
              $objects_parameters += ' i '
              $objects_parameters += "$test_number "
            }
            #more numbers
            elseif ($object.objectSyntax -match 'Unsigned') {
              $objects_parameters += ' u '
              $objects_parameters += "$test_number "
            }
            #more numbers
            elseif (($object.objectSyntax -match 'Counter') -or ($object.objectSyntax -match 'Gauge')) {
              $objects_parameters += ' c '
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
              $objects_parameters += '"' + $test_string + ' ' + $object.objectName + '" '
            }
            #OID
            elseif ($object.objectSyntax -match 'OBJECT IDENTIFIER') {
              $objects_parameters += ' o '
              $objects_parameters += "$test_oid "
            }
            #Whatever else
            else {
              #Most probably it TEXTUAL-CONVENTION so lets try to search it:
              $textual_convention = $mib | Where-Object {$_.objectName -eq $object.objectSyntax -and $_.objectType -eq 'TEXTUAL-CONVENTION'}
              if (!$textual_convention) {
                if ($OIDrepo) {
                  foreach ($module in $imported_modules) {
                    $textual_convention = $mibrepo | Where-Object {($_.objectName -EQ $object.objectSyntax -and $_.objectType -eq 'TEXTUAL-CONVENTION')}
                    if ($textual_convention) {
                      break
                    }
                  }
                }
              }
              #If we got textual convention let's try to use it's SYNTAX
              if ($textual_convention) {
                #Numbers
                if (($textual_convention.objectSyntax -match 'INTEGER') -or ($textual_convention.objectSyntax -match 'TimeTicks')) {
                  $objects_parameters += ' i '
                  $objects_parameters += "$test_number "
                }
                #more numbers
                elseif ($textual_convention.objectSyntax -match 'Unsigned') {
                  $objects_parameters += ' u '
                  $objects_parameters += "$test_number "
                }
                #more numbers
                elseif (($textual_convention.objectSyntax -match 'Counter') -or ($textual_convention.objectSyntax -match 'Gauge')) {
                  $objects_parameters += ' c '
                  $objects_parameters += "$test_number "
                }
                #Ips
                elseif (($textual_convention.objectSyntax -match 'NetworkAddress') -or ($textual_convention.objectSyntax -match 'IpAddress')) {
                  $objects_parameters += ' a '
                  $objects_parameters += "$test_ip "
                }
                #Strings
                elseif (($textual_convention.objectSyntax -match 'DisplayString') -or ($textual_convention.objectSyntax -match 'STRING')) {
                  $objects_parameters += ' s '
                  $objects_parameters += '"' + $test_string + ' ' + $object.objectName + '" '
                }
                #OIDs
                elseif ($textual_convention.objectSyntax -match 'OBJECT IDENTIFIER') {
                  $objects_parameters += ' o '
                  $objects_parameters += "$test_oid "
                }
                else {
                  #esle we stay at UNKNOWN
                  $verboseMessage = "TEXTUAL-CONVENTION: $textual_convention , have UNKNOWN SYNTAX: " + $textual_convention.objectSyntax
                  Write-Verbose $verboseMessage
                  $objects_parameters += ' s '
                  $objects_parameters += '"' + $test_string + ' ' + $object.objectName + ' ' + $object.objectSyntax + '" '
                }
              }  
              else {
                #esle we stay at UNKNOWN
                Write-Verbose "Unknown object SYNTAX:"
                $objects_parameters += ' s '
                $objects_parameters += '"' + $test_string + ' ' + $object.objectName + ' ' + $object.objectSyntax + '" '
              }
            }

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
        else {
          if ($SnmpVersion -notmatch '1') {
            Write-Verbose "Unsupported SnmpVersion setting v1"
          }

          $parent = $mib | Where-Object {$_.objectName -ceq $trap.parent} 
          #try to check the oidrepo if it's there
          if (!$parent) {
            if ($OIDrepo) {
              $parent = $mibrepo | Where-Object {$_.objectName -ceq $trap.parent} 
            }
          }
          #Just do fallback if it cannot find parent anywhere it's for cases like (parent = netapp.0)
          if ($parent) {
            $parent_oid = $parent.OID
            $parent_name = $parent.objectFullName
          }
          else {
            $parent_oid = $trap.parent
            $parent_name = $trap.parent
          }
          
          if ($OIDs) {
            $snmp_command += $parent_oid + ' localhost 6 '+ $trap.ID + ' "0" '
          }
          else {
            $snmp_command += $parent_name + ' localhost 6 '+ $trap.ID + ' "0" '
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
    Get basic Info from MIB File like, Module name, last updated and revision, description etc.
    It also includes hash of file to let you find duplicits.
    
.PARAMETER Path
    The path and file name of a mib file.
    
.NOTES  
    Module Name    : MIB-Processing  
    Author         : Jiri Kindl; kindl_jiri@yahoo.com
    Prerequisite   : PowerShell V2 over Vista and upper.
    Version        : 20210121
    Copyright 2020 - Jiri Kindl
.LINK  
    
.EXAMPLE
    Get-MIBInfo -Path .\SYNOLOGY-SYSTEM-MIB.mib
    Process the MIB and returns basic information, like Module name and revision if available.

.EXAMPLE
    $mibsInfo = @(); foreach ($mib in ls SYNOLOGY*.mib){$mibsInfo += Get-MIBInfo $mib}; $mibsInfo | Export-Csv -NoTypeInformation SynologyMibsInfo.csv
    Process all the SYNOLOGY MIBs and Export the info about them in CSV file for later analyses.

#>

  #parse parametrs with param
  [CmdletBinding()]
  param([Parameter(Position=0)][string]$Path)

  BEGIN {
    $lines = @()
    $sa_status='init'

    try {
      if ($Path) {
        $lines=get-content $Path -ErrorAction Stop
      }
    }
    catch [System.Management.Automation.ItemNotFoundException] {
      "No such file"
      ""
      get-help Get-MIBInfo
    }
    catch {
      $Error[0]
      get-help Get-MIBInfo
    }
  }

  END {
    $token_counter = 0
    $revision_number = ''
    $revision_description = ''
    $revisionProperties = @{}
    $last_updated = ''
    $organization = ''
    $contac_info = ''
    $description = ''
    $revisions = @()
    $revision_numbers = @()
    $latest_revision = ''
    $imports = @()

    Write-verbose "Removing Comments"
    $noCommentLines = Remove-Comments $lines
    Write-verbose "Comments Removed"

    Write-Verbose "Parsing to tokens"
    $tokens = Get-Tokens $noCommentLines
    Write-verbose "MIB Parsed to tokens"

    $fileInfo = Get-ChildItem $Path
    
    Foreach ($token in $tokens) {
      if ($sa_status -eq 'init') {
        if ( ($token -eq 'BEGIN') -and ($tokens[$token_counter -1] -eq '::=') -and ($tokens[$token_counter -2] -eq 'DEFINITIONS') ) {
          $module_name = $tokens[$token_counter -3]
          $token_counter += 1
          continue
        }
        elseif ($token -eq 'MODULE-IDENTITY') {
          $sa_status = 'process_module_identity'
          $token_counter += 1
          continue
        }
        elseif ($token -eq 'IMPORTS') {
          $imported_objects = ''
          $sa_status = 'process_imports'
          $token_counter += 1
          continue
        }
      }
      elseif ($sa_status -eq 'process_imports') {
        if ($token -eq 'FROM') {
          $sa_status = 'process_imports_from'
          $token_counter += 1
          continue
        }
        else {
          $imported_objects += $token
          $token_counter += 1
          continue
        }
      }
      elseif ($sa_status -eq 'process_imports_from') {
        if ($token.endswith(';')) {
          $sa_status = 'init'
          $imported_modul = $token -replace ';', ''
        }
        else {
          $sa_status = 'process_imports'
          $imported_modul = $token
        }
        foreach ($imported_object in $imported_objects -split ',' ){
          $imports += $imported_modul + '::' + $imported_object
        }
        $token_counter += 1
        $imported_objects = ''
        continue
      }
      elseif ($sa_status -eq 'process_module_identity') {
        if ($token -eq 'LAST-UPDATED') {
          $last_updated = $tokens[$token_counter + 1]
          $token_counter += 1
          continue
        }
        elseif ($token -eq 'ORGANIZATION') {
          $organization = $tokens[$token_counter + 1]
          $token_counter += 1
          continue
        
        }
		elseif ($token -eq 'CONTACT-INFO') {
          $contac_info = $tokens[$token_counter + 1]
          $token_counter += 1
          continue
        }
		elseif ($token -eq 'DESCRIPTION') {
          $description = $tokens[$token_counter + 1]
          $token_counter += 1
          continue
        }
        elseif ($token -eq 'REVISION') {
          $sa_status = 'process_revisions'
          $revision_number = $tokens[$token_counter + 1]
          $token_counter += 1
          continue
        }
        elseif ($token -eq '::='){
          break
        }
      }
      elseif ($sa_status -eq 'process_revisions') {
        if ($token -eq 'REVISION') {
          $revision_numbers += $revision_number
          $revisionProperties = @{revisionNumber = $revision_number; revisionDescription = $revision_description}
          $revision = New-Object psobject -Property $revisionProperties
          $revisions += $revision
          $revision_number = $tokens[$token_counter + 1]
          $token_counter += 1
          continue
        }
        elseif ($token -eq 'DESCRIPTION') {
          $revision_description = $tokens[$token_counter + 1]
          $token_counter += 1
          continue
        }
        elseif ($token -eq '::='){
          $revision_numbers += $revision_number
          $revisionProperties = @{revisionNumber = $revision_number; revisionDescription = $revision_description}
          $revision = New-Object psobject -Property $revisionProperties
          $revisions += $revision
          if ($revision_numbers.Length -gt 1) {
            $latest_revision = ($revision_numbers |Sort-Object)[-1]
          }
          elseif ($revision_numbers.Length -eq 1) {
            $latest_revision = $revision_numbers[0]
          }
          break

        }
      }
      $token_counter += 1
    }
    $file_hash = Get-FileHash $Path
    $imports_string = '{' + ($imports -join ',') + '}'
    $revisions_string = '{' + ($revisions -join ',') + '}'
    $objectProperties = @{ fileFullName = $fileInfo.FullName; fileName = $fileInfo.Name; fileSize = $fileInfo.Length; moduleName = $module_name; lastUpdated = $last_updated; revisions = $revisions_string; latestRevision = $latest_revision; description = $description; organization = $organization; contact = $contac_info; fileHash = $file_hash.Hash; imports = $imports_string }
    $MIBFileInfo = New-Object psobject -Property $objectProperties
    $MIBFileInfo  
    
  }
}

function Is-BackwardsCompatible {
<#  
.SYNOPSIS  
    Check if two MIBs, newer and older are bacwards compatible, return True if they are.
.DESCRIPTION  
    Check if two MIBs, newer and older, are backwards compatible, return True if they are and false if not.
    As there is no official criteria for compatibility it pretty much depends on the tool and purpose.
    Hence below in parametrs we define the Compatibility level.
    
.PARAMETER newer
    The path and file name of a newer mib file or csv (generated for that mib).

.PARAMETER older
    The path and file name of a newer mib file or csv (generated for that mib).

.PARAMETER DetailLevel
    Prints out detail info about results, so you know what's new in the MIB or what is missing, level 0 is default
    0 - No info, just True/False
    1 - Corresponding to Compatibility level 1  
    2 - Corresponding to Compatibility level 2  
    3 - Corresponding to Compatibility level 3
    4 - Print also newly added objects/traps/notifications   

.PARAMETER IgnoreSMIVersion
    If set it checks objectName (ignoring module name) instead of objectFullName

.PARAMETER CompatibilityLevel
    Level of compatibility defines what differencies we consider to be compatible, level 3 is default
    1 - We check just names of the objects/traps/notifications missing in newer MIB
    2 - We check the OIDs of object with same name is having also same OID
    3 - We check the Order of the objects/variables in traps/notifications are in same order
    
.PARAMETER Stats
    Prints out the statistick how much of the MIB is "same".  

.NOTES  
    Module Name    : MIB-Processing  
    Author         : Jiri Kindl; kindl_jiri@yahoo.com
    Prerequisite   : PowerShell V2 over Vista and upper.
    Version        : 20220328
    Copyright 2020 - Jiri Kindl
.LINK  
    
.EXAMPLE
    Is-BackwardsCompatible -Newer .\ocum-9_4.csv -Older .\ocum-6_2.csv
    Returns true if ocum-9_4.csv is backward compatible with ocum-6_2.csv 

#>

  #parse parametrs with param
  [CmdletBinding()]
  param([string]$Newer, [string]$Older, [int]$DetailLevel=0, [switch]$IgnoreSMIVersion, [int]$CompatibilityLevel=3, [switch]$Stats)

  BEGIN {
    $lines = @()
    $sa_status='init'

    try {
      if ($Newer) {
        $newerFile = Get-ChildItem $Newer -ErrorAction Stop
        if ($newerFile.Extension -eq '.mib') {
          $newerMib = Import-MIB $newerFile
        }
        elseif ($newerFile.Extension -eq '.csv') {
          $newerMib = Import-CSV $newerFile
        }
        else {
          "Make sure file is .csv or .mib"
          "" 
          get-help Is-BackwardsCompatible  
        }
      }
      else {
        "Need two files to compare newer and older"
        "" 
        get-help Is-BackwardsCompatible
      }
    }
    catch [System.Management.Automation.ItemNotFoundException] {
      "No such file $Newer"
      ""
      get-help Is-BackwardsCompatible
    }
    catch {
      $Error[0]
      get-help Is-BackwardsCompatible
    }
    try {
      if ($Older) {
        $olderFile = Get-ChildItem $Older -ErrorAction Stop
        if ($olderFile.Extension -eq '.mib') {
          $olderMib = Import-MIB $olderFile
        }
        elseif ($olderFile.Extension -eq '.csv') {
          $olderMib = Import-CSV $olderFile
        }
        else {
          "Make sure file is .csv or .mib"
          "" 
          get-help Is-BackwardsCompatible  
        }
      }
      else {
        "Need two files to compare newer and older"
        "" 
        get-help Is-BackwardsCompatible
      }
    }
    catch [System.Management.Automation.ItemNotFoundException] {
      "No such file $Older"
      ""
      get-help Is-BackwardsCompatible
    }
    catch {
      $Error[0]
      get-help Is-BackwardsCompatible
    }
  }
  PROCESS {
    $props=@("objectFullName")
    if ($IgnoreSMIVersion) {
      $props=@("objectName")
    }

    $compatible = $true
    $number_of_comon_objects=0

    foreach ($diffObject in compare-object $newerMib $olderMib -PassThru -Property $props -IncludeEqual -CaseSensitive) {
      #CHECK: if missing in new
      if ($diffObject.sideIndicator -eq '=>') {
        
        $compatible = $false
        if ($DetailLevel -gt 0) { 
          $newerObject = $newerMib | Where-Object {$_.OID -ne ''} |where-object {$_.objectType -ne 'MODULE-COMPLIANCE'} |Where-Object {$_.OID -eq $diffObject.OID }
          #CHECK: if there is object with same OID it might not be missing but it might be renamed
          if ($newerObject){
            $detailLevelName = 'ERROR: '
            $detailMessage = $detailLevelName + 'Object with same OID and diferent name(possibly name of object change): ' + $diffObject.objectFullName 
            Write-Output $detailMessage
            Write-Output "= Older object ======================================"
            $diffObject
            Write-Output ""
            Write-Output "= Newer object ======================================"
            $newerObject
            Write-Output "====================================================="
          }
          else {
            $detailLevelName = 'ERROR: '
            $detailMessage = $detailLevelName + 'Object missing in newer MIB: ' + $diffObject.objectFullName
            Write-Output $detailMessage
          }

        }
        
      }
      #OBJECT IS IN BOTH MIBs
      else {
        #Set comaprision critira for names Depending on SMI version
        if ($IgnoreSMIVersion) {
          $olderObject = $olderMib | Where-Object {$_.objectName -eq $diffObject.objectName -and $_.objectType -eq $diffObject.objectType}
        }
        else {
          $olderObject = $olderMib | Where-Object {$_.objectFullName -eq $diffObject.objectFullName  -and $_.objectType -eq $diffObject.objectType}
        }

        if ($olderObject) {
          $number_of_comon_objects++ 
          #CHECK IF OBJECTS WITH SAME NAME DO HAVE SAME OID:
          if ($olderObject.OID -eq $diffObject.OID) {
            #FOR SAME OIDS:
            if ($CompatibilityLevel -gt 2) {
              if ( -Not ((($diffObject.objects -replace '{', '') -replace '}', '') -replace '\s+', '').StartsWith(((($olderObject.objects -replace '{', '') -replace '}', '') -replace '\s+', '').toString()) ) {
                $compatible = $false
                if ($DetailLevel -gt 2) {
                  $detailLevelName = 'WARNING: '
                  $detailMessage = $detailLevelName + 'Odrer of objects/variables in trap have changed: ' + $diffObject.objectFullName
                  Write-Output $detailMessage
                  $detailMessage = "Newer: " + ($diffObject.objects -replace '{', '') -replace '}', ''
                  Write-Output $detailMessage
                  $detailMessage = "Older: " + ($olderObject.objects -replace '{', '') -replace '}', ''
                  Write-Output $detailMessage
                }
              }            
            }
          }
          else {
            #OIDs ARE DIFFERENT:
            if ($CompatibilityLevel -gt 1) {
              $compatible = $false
              if ($DetailLevel -gt 1)  {
                $detailLevelName = 'ERROR: '
                $detailMessage = $detailLevelName + 'OID changed: ' + $olderObject.OID + '(' + $olderObject.objectFullName + ') => ' + $diffObject.OID + '(' + $diffObject.objectFullName +')'
                # DEBUG BEGIN
                # Write-Output "= Older ======================================================"
                # $olderObject
                # $olderObject |measure
                # Write-Output ""
                # Write-Output "= Diff object ================================================"
                # $diffObject
                # Write-Output "=============================================================="
                # DBUGE END
                Write-Output $detailMessage 
              }
            }
          }
        }
        #NEW OBJECT - JUST INFO
        else {
          if ($DetailLevel -gt 3)  {
            $detailLevelName = 'INFO: '
            $detailMessage = $detailLevelName + 'New object added: ' + $diffObject.objectFullName + '(' + $diffObject.OID + ')'
            Write-Output $detailMessage
          }
        }
      }
    }
  }
  END {
    if ($stats) {
      $number_of_objects_in_newer=($newerMib |Measure-Object).count
      $number_of_objects_in_older=($olderMib |Measure-Object).count
      Write-Output "STATS: "
      Write-Output "Objects in newer : $number_of_objects_in_newer"
      Write-Output "Objects in older : $number_of_objects_in_older"
      Write-Output "Objects in both  : $number_of_comon_objects"
    }
    return $compatible
  }
}

function ConvertTo-SMIv1 {
  <#  
.SYNOPSIS  
    Convert MIB Objects (powershell objects) to SMIv1 (mainly NOTIFYCATION-TYPE to TRAP-TYPE). 
.DESCRIPTION  
    Convert MIB Objects (powershell objects) to SMIv1 (mainly NOTIFYCATION-TYPE to TRAP-TYPE).
    Even though it converts almost whole MIB (Objects, Notifications/Traps) it doesn't convert whole file.
    Hence you need to use original file and replace the Object definitions.
  
.PARAMETER Path
    The path and file name of CSV file generated by Import-MIB
    If you use the CSV as input make sure the CSV was generated with -UseCulture

.NOTES  
    Module Name    : MIB-Processing  
    Author         : Jiri Kindl; kindl_jiri@yahoo.com
    Prerequisite   : PowerShell V2 over Vista and upper.
    Version        : 20220331
    Copyright 2020 - Jiri Kindl
.LINK  
    
.EXAMPLE
    ConvertTo-SMIv1 -Path .\NIMBLE.csv
    Convert CSV file generated by Import-MIB. !NOTE: use | Export-Csv -UseCulture otherwise it will not work.

.EXAMPLE 
    Import-Csv -UseCulture -Path .\NIMBLE.csv | ConvertTo-SMIv1 
    Convert CSV file generated by Import-MIB. !NOTE: you need to use -UseCUlture switch with Import-CSV if the CSV file was generated with -UseCulture

.EXAMPLE
    cat .\ThreeParMIB.mib | Import-MIB -OIDrepo .\myOIDrepo.csv | ConvertTo-SMIv1     

.EXAMPLE
    Import-MIB .\ThreeParMIB.mib -OIDrepo .\myOIDrepo.csv| ConvertTo-SMIv1 

.EXAMPLE
    Import-MIB .\ThreeParMIB.mib -OIDrepo .\myOIDrepo.csv| ConvertTo-SMIv1 |Out-File -Encoding "ASCII" .\ThreeParMIB-SMIv1.mib

  #>

  #pars parametrs with param
  [CmdletBinding()]
  param([Parameter(Position=0)][string]$Path, 
  [parameter(ValueFromPipeline=$true)]$pipelineInput
  )

  BEGIN {
    $mib = @()
    try {
      if ($Path) {
        $mib= Import-Csv -Path $Path -ErrorAction Stop
      }
    }
    catch [System.Management.Automation.ItemNotFoundException] {
      "No such file"
      ""
      Get-Help ConvertTo-SMIv1
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
    $TextToPrint = '-- THIS MIB IS GENERATED AUTOMATICALLY BY ConvertTo-SMIv1'
    Write-Output $TextToPrint
    Write-Output ''
    
    $imports = $mib | Where-Object { $_.objectType -eq "IMPORTS"} 
    $TextToPrint = $imports.module + " DEFINITIONS ::= BEGIN"
    Write-Output $TextToPrint
    Write-Output ''

    foreach ($object in $mib) {
      if ($object.objectType -eq 'IMPORTS') {
        #not implemented and not possible yet in this version of Import-MIB
        Write-Output '-- IMPORT IS YET NOT IMPLEMENTED IN THI VERSION'
        Write-Output 'IMPORTS'
        #have to add TRAP-TYPE definition for proper traps definitions
        Write-Output '    TRAP-TYPE'
        Write-Output '        FROM RFC-1215'
        Write-Output '-- Add copy of import section from original MIB file'

        Write-Output ''
      }
      elseif ($object.objectType -eq 'MODULE-IDENTITY') {
        #MODULE-IDENTITY doesn' exist in SMIv1 but it can be emulated as OBJECT IDENTIFIER
        $TextToPrint = $object.objectName + ' OBJECT IDENTIFIER ::= { ' + $object.parent + ' ' + $object.ID + ' }'
        Write-Output $TextToPrint
        Write-Output ''
      }
      elseif ($object.objectType -eq 'NOTIFICATION-GROUP') {
        $TextToPrint = $object.objectName + ' NOTIFICATION-GROUP' 
        Write-Output $TextToPrint  
        $TextToPrint = '  NOTIFICATIONS ' + $object.objects  
        Write-Output $TextToPrint 
        $TextToPrint = '  STATUS ' + $object.status 
        Write-Output $TextToPrint
        $TextToPrint = '  DESCRIPTION ' + $object.description 
        Write-Output $TextToPrint
        $TextToPrint = '  ::= { ' + $object.parent + ' ' + $object.ID + ' }'
        Write-Output $TextToPrint
        Write-Output ''
      }
      elseif ($object.objectType -eq 'NOTIFICATION-TYPE') {
        #Printing Trap because translating to SMIv1
        $TextToPrint = $object.objectName + ' TRAP-TYPE' 
        Write-Output $TextToPrint
        $TextToPrint = '  ENTERPRISE ' + $object.parent
        Write-Output $TextToPrint
        $TextToPrint = '  VARIABLES ' + $object.objects
        Write-Output $TextToPrint
        $TextToPrint = '  DESCRIPTION ' + $object.description 
        Write-Output $TextToPrint
        $TextToPrint = '  ::= ' + $object.ID
        Write-Output $TextToPrint
        Write-Output ''
      }
      elseif ($object.objectType -eq 'OBJECT IDENTIFIER') {
        #netPMLmgmt			OBJECT IDENTIFIER ::= { netPML 2 }
        $TextToPrint = $object.objectName + ' OBJECT IDENTIFIER ::= { ' + $object.parent + ' ' + $object.ID + ' }'
        Write-Output $TextToPrint
        Write-Output ''
      }
      elseif ($object.objectType -eq 'OBJECT-GROUP') {
        $TextToPrint = $object.objectName + ' OBJECT-GROUP' 
        Write-Output $TextToPrint  
        $TextToPrint = '  OBJECTS ' + $object.objects  
        Write-Output $TextToPrint 
        $TextToPrint = '  STATUS ' + $object.status 
        Write-Output $TextToPrint
        $TextToPrint = '  DESCRIPTION ' + $object.description 
        Write-Output $TextToPrint
        $TextToPrint = '  ::= { ' + $object.parent + ' ' + $object.ID + ' }'
        Write-Output $TextToPrint
        Write-Output ''
      }
      elseif ($object.objectType -eq 'OBJECT-TYPE') {
        $TextToPrint = $object.objectName + ' OBJECT-TYPE' 
        Write-Output $TextToPrint  
        $TextToPrint = '  SYNTAX ' + $object.objectSyntax  
        Write-Output $TextToPrint 
        $TextToPrint = '  ACCESS ' + $object.maxAccess 
        Write-Output $TextToPrint 
        $TextToPrint = '  STATUS ' + $object.status 
        Write-Output $TextToPrint
        $TextToPrint = '  DESCRIPTION ' + $object.description 
        Write-Output $TextToPrint
        $TextToPrint = '  ::= { ' + $object.parent + ' ' + $object.ID + ' }'
        Write-Output $TextToPrint
        Write-Output ''
      }
      elseif ($object.objectType -eq 'SEQUENCE') {
        $TextToPrint = $object.objectName + ' ::= SEQUENCE ' + $object.objects
        Write-Output $TextToPrint
        Write-Output ''
      }
      elseif ($object.objectType -eq 'TEXTUAL-CONVENTION') {
        $TextToPrint = $object.objectName + ' ::= TEXTUAL-CONVENTION'
        Write-Output $TextToPrint
        $TextToPrint = '  STATUS ' + $object.status 
        Write-Output $TextToPrint
        $TextToPrint = '  DESCRIPTION ' + $object.description 
        Write-Output $TextToPrint
        $TextToPrint = '  SYNTAX ' + $object.objectSyntax  
        Write-Output $TextToPrint 
        Write-Output ''
      }
      elseif ($object.objectType -eq 'TRAP-TYPE') {
        $TextToPrint = $object.objectName + ' TRAP-TYPE' 
        Write-Output $TextToPrint
        $TextToPrint = '  ENTERPRISE ' + $object.parent
        Write-Output $TextToPrint
        $TextToPrint = '  VARIABLES ' + $object.objects
        Write-Output $TextToPrint
        $TextToPrint = '  DESCRIPTION ' + $object.description 
        Write-Output $TextToPrint
        $TextToPrint = '  ::= ' + $object.ID
        Write-Output $TextToPrint
        Write-Output ''      
      }
      else {
        #Unknown or not implemented ObjectType
      }

    }
  
    Write-Output 'END'
  }
}

function ConvertTo-SMIv2 {
  <#  
.SYNOPSIS  
    Convert MIB Objects (powershell objects) to SMIv2 (mainly TRAP-TYPE to NOTIFYCATION-TYPE). 
.DESCRIPTION  
    Convert MIB Objects (powershell objects) to SMIv2 (mainly TRAP-TYPE to NOTIFYCATION-TYPE).
    Even though it converts almost whole MIB (Objects, Notifications/Traps) it doesn't convert whole file.
    Hence you need to use original file and replace the Object definitions.
  
.PARAMETER Path
    The path and file name of CSV file generated by Import-MIB
    If you use the CSV as input make sure the CSV was generated with -UseCulture

.NOTES  
    Module Name    : MIB-Processing  
    Author         : Jiri Kindl; kindl_jiri@yahoo.com
    Prerequisite   : PowerShell V2 over Vista and upper.
    Version        : 20210124
    Copyright 2020 - Jiri Kindl
.LINK  
    
.EXAMPLE
    ConvertTo-SMIv1 -Path .\NIMBLE.csv
    Convert CSV file generated by Import-MIB. !NOTE: use | Export-Csv -UseCulture otherwise it will not work.

.EXAMPLE 
    Import-Csv -UseCulture -Path .\NIMBLE.csv | ConvertTo-SMIv2 
    Convert CSV file generated by Import-MIB. !NOTE: you need to use -UseCUlture switch with Import-CSV if the CSV file was generated with -UseCulture

.EXAMPLE
    cat .\ThreeParMIB.mib | Import-MIB -OIDrepo .\myOIDrepo.csv | ConvertTo-SMIv2     

.EXAMPLE
    Import-MIB .\ThreeParMIB.mib -OIDrepo .\myOIDrepo.csv| | ConvertTo-SMIv2 

.EXAMPLE
    Import-MIB .\ThreeParMIB.mib -OIDrepo .\myOIDrepo.csv| | ConvertTo-SMIv2 | Add-Content ThreeParMIB-v1.mib
    If you remove all the Definition Except IMPORTS and MODULE-IDENTITY (in example above ThreeParMIB-v1.mib) you can use above to append SMIv1 definitions into it.
    Then just add END at the end of the file and you are done.

  #>

  #pars parametrs with param
  [CmdletBinding()]
  param([Parameter(Position=0)][string]$Path, 
  [parameter(ValueFromPipeline=$true)]$pipelineInput
  )

  BEGIN {
    $mib = @()
    try {
      if ($Path) {
        $mib= Import-Csv -Path $Path -ErrorAction Stop
      }
    }
    catch [System.Management.Automation.ItemNotFoundException] {
      "No such file"
      ""
      Get-Help ConvertTo-SMIv2
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
    foreach ($object in $mib) {
      if ($object.objectType -eq 'IMPORTS') {
        #not implemented and not possible yet in this version of Import-MIB
      }
      elseif ($object.objectType -eq 'MODULE-IDENTITY') {
        #not implemented and not possible yet in this version of Import-MIB
      }
      elseif ($object.objectType -eq 'NOTIFICATION-GROUP') {
        $TextToPrint = $object.objectName + ' NOTIFICATION-GROUP' 
        Write-Output $TextToPrint  
        $TextToPrint = '  NOTIFICATIONS ' + $object.objects  
        Write-Output $TextToPrint 
        $TextToPrint = '  STATUS ' + $object.status 
        Write-Output $TextToPrint
        $TextToPrint = '  DESCRIPTION ' + $object.description 
        Write-Output $TextToPrint
        $TextToPrint = '  ::= { ' + $object.parent + ' ' + $object.ID + ' }'
        Write-Output $TextToPrint
        Write-Output ''
      }
      elseif ($object.objectType -eq 'NOTIFICATION-TYPE') {
        $TextToPrint = $object.objectName + ' NOTIFICATION-TYPE' 
        Write-Output $TextToPrint
        $TextToPrint = '  OBJECTS ' + $object.objects
        Write-Output $TextToPrint
        $TextToPrint = '  STATUS ' + $object.status 
        Write-Output $TextToPrint
        $TextToPrint = '  DESCRIPTION ' + $object.description 
        Write-Output $TextToPrint
        $TextToPrint = '  ::= { ' + $object.parent + ' ' + $object.ID + ' }'
        Write-Output $TextToPrint
        Write-Output ''
      }
      elseif ($object.objectType -eq 'OBJECT IDENTIFIER') {
        #netPMLmgmt			OBJECT IDENTIFIER ::= { netPML 2 }
        $TextToPrint = $object.objectName + ' OBJECT IDENTIFIER ::= { ' + $object.parent + ' ' + $object.ID + ' }'
        Write-Output $TextToPrint
        Write-Output ''
      }
      elseif ($object.objectType -eq 'OBJECT-GROUP') {
        $TextToPrint = $object.objectName + ' OBJECT-GROUP' 
        Write-Output $TextToPrint  
        $TextToPrint = '  OBJECTS ' + $object.objects  
        Write-Output $TextToPrint 
        $TextToPrint = '  STATUS ' + $object.status 
        Write-Output $TextToPrint
        $TextToPrint = '  DESCRIPTION ' + $object.description 
        Write-Output $TextToPrint
        $TextToPrint = '  ::= { ' + $object.parent + ' ' + $object.ID + ' }'
        Write-Output $TextToPrint
        Write-Output ''
      }
      elseif ($object.objectType -eq 'OBJECT-TYPE') {
        $TextToPrint = $object.objectName + ' OBJECT-TYPE' 
        Write-Output $TextToPrint  
        $TextToPrint = '  SYNTAX ' + $object.objectSyntax  
        Write-Output $TextToPrint 
        $TextToPrint = '  ACCESS ' + $object.maxAccess 
        Write-Output $TextToPrint 
        $TextToPrint = '  STATUS ' + $object.status 
        Write-Output $TextToPrint
        $TextToPrint = '  DESCRIPTION ' + $object.description 
        Write-Output $TextToPrint
        $TextToPrint = '  ::= { ' + $object.parent + ' ' + $object.ID + ' }'
        Write-Output $TextToPrint
        Write-Output ''
      }
      elseif ($object.objectType -eq 'SEQUENCE') {
        $TextToPrint = $object.objectName + ' ::= SEQUENCE ' + $object.objects
        Write-Output $TextToPrint
        Write-Output ''
      }
      elseif ($object.objectType -eq 'TEXTUAL-CONVENTION') {
        $TextToPrint = $object.objectName + ' ::= TEXTUAL-CONVENTION'
        Write-Output $TextToPrint
        $TextToPrint = '  STATUS ' + $object.status 
        Write-Output $TextToPrint
        $TextToPrint = '  DESCRIPTION ' + $object.description 
        Write-Output $TextToPrint
        $TextToPrint = '  SYNTAX ' + $object.objectSyntax  
        Write-Output $TextToPrint 
        Write-Output ''
      }
      elseif ($object.objectType -eq 'TRAP-TYPE') {
        #Printing NOTIFICATION because we are converting to SMIv2
        $TextToPrint = $object.objectName + ' NOTIFICATION-TYPE' 
        Write-Output $TextToPrint
        $TextToPrint = '  OBJECTS ' + $object.objects
        Write-Output $TextToPrint
        $TextToPrint = '  STATUS ' + $object.status 
        Write-Output $TextToPrint
        $TextToPrint = '  DESCRIPTION ' + $object.description 
        Write-Output $TextToPrint
        $TextToPrint = '  ::= { ' + $object.parent + ' ' + $object.ID + ' }'
        Write-Output $TextToPrint
        Write-Output ''      
      }
      else {
        #Unknown or not implemented ObjectType
      }

    }
  }
}

#VERSION HISTORY:
#Version,Comment
#20220326,CORRECTED: Is-BackwardsCompatible, was comparing the different types like OBJCET-TYPE with SEQUENCE
#20220328,CORRECTED: Is-BackwardsCompatible, was looking for OID changed based on name also for OID less objects like SEQUENCE
#20220331,ADDED: ConvertTo-SMIv1 now corretly generate BEGIN and END, and also conver MODULE-IDENTITY as OBJECT IDENTIFIER
#20220417,CORRECTED: changed all aliase like echo, where, ls to it's proper names like Write-Output, Where-Object, Get-Childitem
#20220508,CORRECTED: It seems that "object" names are Case sensitive hence must used -ceq instead of -eq when searching for objects during OID expantion/translation
#20220617,CORRECTED: TEXTUAL-CONVENTION with direct SYNTAX processing, like those FcNameId ::= OCTET STRING (SIZE(8)), ADDED: Processing of MODULE-COMPLIANCE, but not fully implemented
#20220620,CORRECTED: Is-BackwardsCompatible Condition for comparing(excluding) MODULE-COMPLIANCE
#20220630,ADDED: DESCRIPTION processing inside MODULE-IDENTITY
#20220704,ADDED: IMPORT record from each Module FROM which we import objects for easier dependecy check amd fatser compilation of multiple MIBs
#20220706,ADDED: MACRO records to have all objects (for example: OBJECT-TYPE is defined by MACRO and is in imports hence need have those to properly cover IMPORTS), CORRECTED: TEXTUAL-CONVENTION Processing, CORRECTED: Update-OIDRepo to use -ceq (case sensitive comparision)
#20220707,ADDED: In Import-MIB hardcoded iso = 1 cause for some IMPORTing standard object is too main stream, ADDED: info to debug output to know if running parsing or comment removal, CORRECTED: In Get-MIBInfo better more elegant imports output