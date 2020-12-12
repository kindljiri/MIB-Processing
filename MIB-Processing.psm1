#Input: content of MIB file
#Output: content of MIB file without comments (and blank lines)
function Remove-Comments($lines){
  $linesWithoutComments = @()
  $sa_state = 'init'
  $line_counter = 0
  #start with preprocessing
  $lines = $lines | where {$_.trim() -ne ''}
  #remove comments
  $debugMessage = "STARTING REMOVE-COMMENTS"
  Write-Debug $debugMessage
  foreach ($line in $lines) {
   
    $line_counter = +1
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
    $sa_state = 'init'
    if ($line -match '--' -or $line -match '"') {
      $tmp=''
      foreach ($token in $line.split(' ')){
        Write-Debug $line
        $debugMessage = "Status=$sa_state,Token=$token,Counter=$line_counter"
        Write-Debug $debugMessage
        if ($sa_state -eq 'init') { 
          if ($token -eq '--'){
            $sa_state = 'comment_processing'
            $linesWithoutComments += $tmp.trim()
            $tmp = ''
            continue
          }
          elseif ($token.startsWith('"')) {
            $sa_state = 'text_processing'
            $tmp += " $token"
            continue
          }
          else {
            $tmp += " $token"
            continue
          }
        }
        elseif ($sa_state -eq 'text_processing') {
          if ($token.endswith('"')){
            $sa_state = 'init'
          }
          $tmp += " $token"
          continue
        }
        elseif($sa_state -eq 'comment_processing'){
          if ($token -eq '--') {
            $sa_state = 'init'
            continue
          }
          else {
            continue
          }
        }
        else{
          #unknown state
        }       
      }
      if ($sa_state -ne 'text_processing') {
        $sa_state = 'init'
      }
      if ($tmp -ne '') {
        $linesWithoutComments += $tmp.trim()
      }
      continue
    }
    else {
      $linesWithoutComments += $line
    }
  }
  $linesWithoutComments = $linesWithoutComments | where {$_.trim() -ne ''}
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

  $preprocessed_lines = $preprocessed_lines | where {$_.trim() -ne ''}
  
  foreach ($token in $preprocessed_lines) {
    $token = $token.trim()

    #skip of empty tokens
    #if ($token -eq '') {
    #  continue
    #}

    #$token.getType()
    #echo "DEBUG: State=$sa_state,Token=$token,"
    #as we removed oneline comments we can process following states
    #array: start with { and ends with }
    #quoted text: start with " and ends with "
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
  $sa_status='init'
  ($object_name,$object_type,$object_syntax,$status,$description,$objects,$ID,$object_max_access,$object_units,$object_reference,$object_index,$object_augments,$object_defval,$notification_objects,$parent,$OID) = ('','','','','','','','','','','','','','','','')
  $imported_modules=''
  $counter = 0
  $currently_processing_macro = ''
  $mib = @()

  $debugMessage = "STARTING PARSING"
  Write-Debug $debugMessage
  $debugMessage = "Number of objects in mib: " +$mib.Length 
  Write-Debug $debugMessage

  #below is not used yet (will see if I'll use it later
  $macro_tokens = ('MODULE-IDENTITY','OBJECT-TYPE','NOTIFICATION-TYPE','OBJECT IDENTIFIER','TEXTUAL-CONVENTION')
  $notification_type_tokens = ('OBJECTS','STATUS','DESCRIPTION','REFERENCE','::=')
  $object_type_tokens=('SYNTAX','UNITS','MAX-ACCESS','STATUS','DESCRIPTION','REFERENCE','INDEX','AUGMENTS','DEFVAL','::=')
  $trap_type_tokens = ('ENTERPRISE','VARIABLES','DESCRIPTION','REFERENCE')
  $textaul_convention_clauses = ('DISPLAY-HINT', 'STATUS', 'DESCRIPTION', 'REFERENCE', 'SYNTAX')
  
  #below is union of above arrays + MACRO
  $expected_type_tokens=('ENTERPRISE','VARIABLES','OBJECTS','SYNTAX','UNITS','MAX-ACCESS','DISPLAY-HINT','STATUS','DESCRIPTION','REFERENCE','INDEX','AUGMENTS','DEFVAL','::=','MACRO','OBJECT-GROUP','NOTIFICATION-GROUP','NOTIFICATIONS')

  foreach ($token in $tokens) {
    $debugMessage = "Currently processing=$currently_processing_macro,Status=$sa_status,Token=$token,Counter=$counter"
    Write-Debug $debugMessage
    #just for sure
    $token = $token.trim()
    if ($sa_status -eq 'init') {
      if ($token -eq 'BEGIN') {
        if ($tokens[$counter-2]+$tokens[$counter-1]+$token -eq 'DEFINITIONS::=BEGIN') {
          $module_name = $tokens[$counter-3]
        }
      }
      elseif ($token -eq 'IMPORTS') {
        $currently_processing_macro = $token
        $sa_status = 'IMPORTS'
        $imported_modules = '{ '
      }
      elseif ($token -eq 'MODULE-IDENTITY') {
        $currently_processing_macro = $token
        $sa_status = 'MODULE-IDENTITY'
        $object_type = 'MODULE-IDENTITY'
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
      $object_name = $object_name.trim()
      $counter += 1
      continue 
    }
    elseif ($sa_status -eq 'IMPORTS') {
      if ($token.endswith(';')) {
        $imported_modules += '}'
        $imported_modules = $imported_modules -replace ';, }', ' }'
        $objectProperties = @{ objectName = 'IMPORTS'; objectType = 'IMPORTS'; objectSyntax = 'IMPORTS'; status = $status; description = 'Other modules refered in this module'; objects = $imported_modules; ID = ''; parent = ''; OID = ''; module = $module_name; objectFullName = '' }
        $object = New-Object psobject -Property $objectProperties
        $mib += $object
        $debugMessage = "Creating Object=$object"
        Write-Debug $debugMessage
        $debugMessage = "Number of objects in mib: " +$mib.Length 
        Write-Debug $debugMessage
        ($object_name,$object_type,$object_syntax,$status,$description,$objects,$ID,$paren) = ('','','','','','','','','','','','','','','','','')
        $sa_status = 'init'
        $counter += 1
        continue
      }
      elseif ($token -eq 'FROM') {
        $imported_modules += $tokens[$counter+1] + ', '
        $counter += 1
        continue
      }
    } 
    elseif ($sa_status -eq 'MODULE-IDENTITY') {
      if ($token -eq '::=') {
        $sa_status = '::='
        $counter += 1
        continue
      }
      elseif ($token -eq 'MACRO') {
        $sa_status = 'MACRO'
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
      elseif ($token -eq 'MACRO') {
        $sa_status='MACRO'
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
      if ($currently_processing_macro -eq 'TEXTUAL-CONVENTION' -and ($tokens[$counter+1] -eq '::=' -or $token -eq 'END') ) {
        $sa_status = 'init'
        $object_syntax = $object_syntax.trim()
        $objectProperties = @{ objectName = $object_name; objectType = $object_type; objectSyntax = $object_syntax; status = $status; description = $description; objects = $notification_objects; ID = $ID; parent = $parent; OID = $OID; module = $module_name; objectFullName = "$module_name::$object_name" }
        $object = New-Object psobject -Property $objectProperties
        $mib += $object
        $debugMessage = "Creating Object=$object"
        Write-Debug $debugMessage
        $debugMessage = "Number of objects in mib: " +$mib.Length 
        Write-Debug $debugMessage
        ($object_name,$object_type,$object_syntax,$status,$description,$objects,$ID,$object_max_access,$object_units,$object_reference,$object_index,$object_augments,$object_defval,$notification_objects,$parent,$OID) = ('','','','','','','','','','','','','','','','')
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
    elseif ($sa_status -eq 'STATUS') {
      foreach ($ott in $expected_type_tokens) {
        if ($ott -eq $token) {
          $sa_status = $token
          $status = $status.trim()
          break 
        }
      }
      if ($currently_processing_macro -eq 'TEXTUAL-CONVENTION' -and ($tokens[$counter+1] -eq '::=' -or $token -eq 'END') ) {
        $sa_status = 'init'
        $status = $status.trim()
        $objectProperties = @{ objectName = $object_name; objectType = $object_type; objectSyntax = $object_syntax; status = $status; description = $description; objects = $notification_objects; ID = $ID; parent = $parent; OID = $OID; module = $module_name; objectFullName = "$module_name::$object_name" }
        $object = New-Object psobject -Property $objectProperties
        $mib += $object 
        $debugMessage = "Creating Object=$object"
        Write-Debug $debugMessage
        $debugMessage = "Number of objects in mib: " +$mib.Length 
        Write-Debug $debugMessage
        ($object_name,$object_type,$object_syntax,$status,$description,$objects,$ID,$object_max_access,$object_units,$object_reference,$object_index,$object_augments,$object_defval,$notification_objects,$parent,$OID) = ('','','','','','','','','','','','','','','','')
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
      if ($currently_processing_macro -eq 'TEXTUAL-CONVENTION' -and ($tokens[$counter+1] -eq '::=' -or $token -eq 'END') ) {
        $sa_status = 'init'
        $objectProperties = @{ objectName = $object_name; objectType = $object_type; objectSyntax = $object_syntax; status = $status; description = $description; objects = $notification_objects; ID = $ID; parent = $parent; OID = $OID; module = $module_name; objectFullName = "$module_name::$object_name" }
        $object = New-Object psobject -Property $objectProperties
        $mib += $object 
        $debugMessage = "Creating Object=$object"
        Write-Debug $debugMessage
        $debugMessage = "Number of objects in mib: " +$mib.Length 
        Write-Debug $debugMessage
        ($object_name,$object_type,$object_syntax,$status,$description,$objects,$ID,$object_max_access,$object_units,$object_reference,$object_index,$object_augments,$object_defval,$notification_objects,$parent,$OID) = ('','','','','','','','','','','','','','','','')
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
      if ($currently_processing_macro -eq 'TEXTUAL-CONVENTION' -and ($tokens[$counter+1] -eq '::=' -or $token -eq 'END') ) {
        $sa_status = 'init'
        $object_reference = $object_reference.trim() 
        $objectProperties = @{ objectName = $object_name; objectType = $object_type; objectSyntax = $object_syntax; status = $status; description = $description; objects = $notification_objects; ID = $ID; parent = $parent; OID = $OID; module = $module_name; objectFullName = "$module_name::$object_name" }
        $object = New-Object psobject -Property $objectProperties
        $mib += $object
        $debugMessage = "Creating Object=$object"
        Write-Debug $debugMessage
        $debugMessage = "Number of objects in mib: " +$mib.Length 
        Write-Debug $debugMessage
        ($object_name,$object_type,$object_syntax,$status,$description,$objects,$ID,$object_max_access,$object_units,$object_reference,$object_index,$object_augments,$object_defval,$notification_objects,$parent,$OID) = ('','','','','','','','','','','','','','','','')
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
      if ($currently_processing_macro -eq 'TEXTUAL-CONVENTION' -and ($tokens[$counter+1] -eq '::=' -or $token -eq 'END') ) {
        $sa_status = 'init'
        $display_hint = $display_hint.trim()
        $objectProperties = @{ objectName = $object_name; objectType = $object_type; objectSyntax = $object_syntax; status = $status; description = $description; objects = $notification_objects; ID = $ID; parent = $parent; OID = $OID; module = $module_name; objectFullName = "$module_name::$object_name" }
        $object = New-Object psobject -Property $objectProperties
        $mib += $object 
        $debugMessage = "Creating Object=$object"
        Write-Debug $debugMessage
        $debugMessage = "Number of objects in mib: " +$mib.Length 
        Write-Debug $debugMessage
        ($object_name,$object_type,$object_syntax,$status,$description,$objects,$ID,$object_max_access,$object_units,$object_reference,$object_index,$object_augments,$object_defval,$notification_objects,$parent,$OID) = ('','','','','','','','','','','','','','','','')
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
          $ID.trim()
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
      $objectProperties = @{ objectName = $object_name; objectType = $object_type; objectSyntax = $object_syntax; status = $status; description = $description; objects = $notification_objects; ID = $ID; parent = $parent; OID = $OID; module = $module_name; objectFullName = "$module_name::$object_name" }
      $object = New-Object psobject -Property $objectProperties
      $mib += $object
      $debugMessage = "Creating Object=$object"
      Write-Debug $debugMessage
      $debugMessage = "Number of objects in mib: " +$mib.Length 
      Write-Debug $debugMessage
      $sa_status = 'init'
      ($object_name,$object_type,$object_syntax,$status,$description,$objects,$ID,$object_max_access,$object_units,$object_reference,$object_index,$object_augments,$object_defval,$notification_objects,$parent,$OID) = ('','','','','','','','','','','','','','','','')
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'MACRO') {
      #just skip MACRO DEFINITION
      if ($token -eq 'END') {
        $sa_status = 'init'
      }
      $counter += 1
      continue
    }
    elseif ($sa_status -eq 'SEQUENCE') {
      if ($token.startswith('{')){
        $objectProperties = @{ objectName = $object_name; objectType = $object_type; objectSyntax = 'SEQUENCE'; status = ''; description = ''; objects = $token; ID = ''; parent = ''; OID = ''; module = $module_name; objectFullName = "$module_name::$object_name" }
        $object = New-Object psobject -Property $objectProperties
        $mib += $object
        $debugMessage = "Creating Object=$object"
        Write-Debug $debugMessage
        $debugMessage = "Number of objects in mib: " +$mib.Length 
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
  $debugMessage = "Number of objects in mib: " +$mib.Length 
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
    $module_name = $new_object.module
    if (!(Is-Full-OID $newOID) -and ($new_object.objectType -ne 'IMPORTS') -and ($new_object.objectType -ne 'SEQUENCE') -and ($new_object.objectType -ne 'TEXTUAL-CONVENTION') ) {
      echo "ERROR: $newObjectFullName($newOID) is not fully resolved"
    }
    elseif (!($mibrepo| where {$_.objectFullName -eq $newObjectFullName})) {
      $mibrepo += $new_object
      $new_updates = $true
      Write-verbose ($new_object.objectName + " added to $OIDrepo")
    }
    else {
      if ($newOID -ne '') {
        echo "WARNING: adding $newOID record with same OID already exist in $OIDrepo."
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
    
.NOTES  
    Module Name    : MIB-Processing  
    Author         : Jiri Kindl; kindl_jiri@yahoo.com
    Prerequisite   : PowerShell V2 over Vista and upper.
    Version        : 20201211
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
  param([Parameter(Position=0)][string]$Path, [string]$OIDrepo, [switch]$UpdateOIDRepo, [switch]$silent,
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
      foreach ($object in $mib | where {$_.OID -ne ''}) {
        $verboseMessage = "Resolving " + $object.objectName
        Write-Verbose "$verboseMessage"
        Write-Debug "$object"
        if (!(($object.OID).split('.')[0] -match "^[\d\.]+$")) {
          $unresolvedObject = $mib | where {$_.objectName -eq ($object.OID).split('.')[0]  -and  ($_.objectType -ne 'SEQUENCE' -and  $_.objectType -ne 'TEXTUAL-CONVENTION') }
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
      foreach ($object in $mib | where {$_.OID -ne ''}) {
        $oid=$object.OID
        $object_name_to_search = $oid.split('.')[0]
        $repo_SearchResults = $mibrepo | where {$_.objectName -eq $object_name_to_search}
        $imported_objects = ($mib | where {$_.objectName -eq 'IMPORTS'}).objects
        $imported_objects = $imported_objects -replace '{', ''
        $imported_objects = $imported_objects -replace '}', ''
        $imported_objects = $imported_objects -replace ' ', ''
        if ($repo_SearchResults) {
          foreach ($repo_SearchResult in $repo_SearchResults) {
            if ($imported_objects.split(',') -contains $repo_SearchResult.module){
              $resolvedOID = $repo_SearchResult.OID
              $newOID = $oid -replace $object_name_to_search, $resolvedOID
              $object.OID = $newOID
              break
            }
          }
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
    Version        : 20201212
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
    cat .\ThreeParMIB.mib | Import-MIB -OIDrepo .\myOIDrepo.oids | ConvertTo-Snmptrap -OIDrepo .\myOIDrepo
    To generate snmptrap commands for testing based on ThreeParMIB.mib file and use OIDrepo to resolve objects which are not directly defined in this MIB

.EXAMPLE
    cat .\ThreeParMIB.mib | Import-MIB -OIDrepo .\myOIDrepo.oids | ConvertTo-Snmptrap -OIDrepo .\myOIDrepo -OIDs
    To generate snmptrap commands for testing based on ThreeParMIB.mib file and use OIDrepo to resolve objects which are not directly defined in this MIB.
    Also resolves objects/variable names to OIDs, so you can send test trap from device or server where relevant MIB(s) are not loaded.

.EXAMPLE
    cat .\ThreeParMIB.mib | Import-MIB -OIDrepo .\myOIDrepo.oids | ConvertTo-Snmptrap -SnmpVersion 2
    To generate snmptrap commands, with version 2 traps, for testing based on ThreeParMIB.mib file
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
    $test_ip = "10.10.10.10"
    try {
      if ($Path) {
        $mib=Import-Csv  -Path $Path -ErrorAction Stop
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
      
      $imported_modules = ($mib | where {$_.objectName -eq 'IMPORTS'}).objects
      $imported_modules = ((($imported_modules -replace '{', '') -replace '}', '') -replace ' ', '').split(',')
      #Write-Verbose "Importeds modules"
      #$imported_modules 
    }
    
    $traps = $mib | where {($_.objectType -EQ "TRAP-TYPE" -or $_.objectType -EQ "NOTIFICATION-TYPE")}
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
            $object = $mib | where {($_.objectName -EQ $object_name)}

            if (!$object) {
              if ($OIDrepo) {
                foreach ($module in $imported_modules) {
                  $object = $mibrepo | where {($_.objectName -EQ $object_name -and $_.module -EQ $module)}
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

            #Whatever else
            else {
              #Most probably it TEXTUAL-CONVENTION so lets try to search it:
              $textual_convention = $mib | where {$_.objectName -eq $object.objectSyntax -and $_.objectType -eq 'TEXTUAL-CONVENTION'}
              if (!$textual_convention) {
                if ($OIDrepo) {
                  foreach ($module in $imported_modules) {
                    $textual_convention = $mibrepo | where {($_.objectName -EQ $object.objectSyntax -and $_.objectType -eq 'TEXTUAL-CONVENTION')}
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
          Write-Verbose "Unsupported SnmpVersion setting v1"
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
    Get basic Info from MIB File like, Module name, last updated and revision, description etc.
    It also includes hash of file to let you find duplicits.
    
.PARAMETER Path
    The path and file name of a mib file.
    
.NOTES  
    Module Name    : MIB-Processing  
    Author         : Jiri Kindl; kindl_jiri@yahoo.com
    Prerequisite   : PowerShell V2 over Vista and upper.
    Version        : 20201027
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
    $last_revision = ''


    Write-verbose "Removing Comments"
    $noCommentLines = Remove-Comments $lines
    Write-verbose "Comments Removed"

    Write-Verbose "Parsing to tokens"
    $tokens = Get-Tokens $noCommentLines
    Write-verbose "MIB Parsed to tokens"

    $fileInfo = ls $Path
    
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
            $latest_revision = ($revision_numbers |sort)[-1]
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
    $objectProperties = @{ fileFullName = $fileInfo.FullName; fileName = $fileInfo.Name; fileSize = $fileInfo.Length; moduleName = $module_name; lastUpdated = $last_updated; revisions = $revisions; latestRevision = $latest_revision; description = $description; organization = $organization; contact = $contac_info; fileHash = $file_hash.Hash }
    $MIBFileInfo = New-Object psobject -Property $objectProperties
    $MIBFileInfo  
    
  }
}

function Is-BackwardsCompatible {
<#  
.SYNOPSIS  
    Check if two MIBs, newer and older are bacwards compatible, return True if they are.
.DESCRIPTION  
    Check if two MIBs, newer and older are backwards compatible, return True if they are and false if not.
    Checks if all objects from older are in newer with same OID, if Trap/Notification also check that all Variables from older are in newer and in same order.
    Use rather csv exports of MIBs rahter then MIBs. It's quicker.
    
.PARAMETER newer
    The path and file name of a newer mib file or csv (generated for that mib).

.PARAMETER older
    The path and file name of a newer mib file or csv (generated for that mib).

.PARAMETER details
    Prints out detail info about results, so you know what's new in the MIB or what is missing.
    
.NOTES  
    Module Name    : MIB-Processing  
    Author         : Jiri Kindl; kindl_jiri@yahoo.com
    Prerequisite   : PowerShell V2 over Vista and upper.
    Version        : 202011111
    Copyright 2020 - Jiri Kindl
.LINK  
    
.EXAMPLE
    Is-BackwardsCompatible -Newer .\ocum-9_4.csv -Older .\ocum-6_2.csv
    Returns true if ocum-9_4.csv is backward compatible with ocum-6_2.csv 

#>

  #parse parametrs with param
  [CmdletBinding()]
  param([string]$Newer, [string]$Older, [switch]$Details)

  BEGIN {
    $lines = @()
    $sa_status='init'

    try {
      if ($Newer) {
        $newerFile = ls $Newer -ErrorAction Stop
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
        $olderFile = ls $Older -ErrorAction Stop
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
    $compatible = $true
    foreach ($diffObject in compare-object $newerMib $olderMib -PassThru) {
      if ($diffObject.sideIndicator -eq '=>') {
        $compatible = $false
        if ($Details) {
          $detailMessage = 'Object missing in newer MIB: ' + $diffObject.objectFullName
          Write-Output $detailMessage
        }
        Write-Verbose "$diffObject"
      }
      else {
        $olderObject = $olderMib | where {$_.objectFullName -eq $diffObject.objectFullName}
        if ($olderObject) {
          if ($olderObject.OID -eq $diffObject.OID) {
            if ( -Not ((($diffObject.objects -replace '{', '') -replace '}', '') -replace '\s+', '').StartsWith(((($olderObject.objects -replace '{', '') -replace '}', '') -replace '\s+', '').toString()) ) {
              $compatible = $false
              if ($Details) {
                $detailMessage = 'Odrer of objects/variables in trap have changed: ' + $diffObject.objectFullName
                Write-Output $detailMessage
                $detailMessage = ($diffObject.objects -replace '{', '') -replace '}', ''
                Write-Output $detailMessage
                $detailMessage = ($olderObject.objects -replace '{', '') -replace '}', ''
                Write-Output $detailMessage
              }
            }            
          }
          else {
            $compatible = $false
            if ($Details) {
              $detailMessage = 'OID changed: ' + $olderObject.OID + '(' + $olderObject.objectFullName + ') => ' + $diffObject.OID + '(' + $diffObject.objectFullName +')'
              Write-Output $detailMessage 
            }
          }
        }
        else {
          if ($Details) {
            $detailMessage = 'New object added: ' + $diffObject.objectFullName
            Write-Output $detailMessage
          }
        }
      }
    }
  }
  END {
    return $compatible
  }
}
