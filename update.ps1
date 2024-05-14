#################################################
# HelloID-Conn-Prov-Target-Aura-Update
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions

function ConvertTo-ChallengeResponseCode {
    [OutputType([System.String])]
    [CmdletBinding()]
    param(
        [string]
        $challengeResult
    )
    try {
        $shaobj = [System.Security.Cryptography.SHA1CryptoServiceProvider]::new()
        $shaObj.Initialize();

        $encoder = [System.Text.ASCIIEncoding]::new()
        $hash = $shaObj.ComputeHash($encoder.GetBytes($challengeResult + "tools4ever" + $actionContext.Configuration.password))

        $shaobj.Clear()
        $challengeResponseCode = [System.String]::Concat(($hash | ForEach-Object {
                    $_.ToString('X2')
                }
            ))
        Write-Output $challengeResponseCode
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Add-CookieToWebRequestSession {
    [CmdletBinding()]
    [OutputType([Microsoft.PowerShell.Commands.WebRequestSession])]
    param(
        [string]
        $cookieResponse
    )
    try {

        $CookieNameValue = ($cookieResponse -split ';') | Select-Object -First 1
        if ([string]::IsNullOrWhiteSpace($CookieNameValue)) {
            throw 'Cookie Not Found, Please check you password'
        }
        $uri = [system.uri]::new($actionContext.Configuration.BaseUrl)

        $Cookie = [System.Net.Cookie]::new()
        $Cookie.Name = ($CookieNameValue -split '=') | Select-Object -First 1
        $Cookie.Value = ($CookieNameValue -split '=') | Select-Object -Last 1
        $Cookie.Domain = $uri.DnsSafeHost

        $WebSession = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
        $WebSession.Cookies.Add($Cookie)

        Write-Output  $WebSession
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Get-AuraAuthenticationCookie {
    [OutputType([System.String])]
    [CmdletBinding()]
    param()
    try {
        # Challenge Request
        [xml]$xmlChallenge = '<?xml version="1.0" encoding="utf-8"?>
        <soap12:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap12="http://www.w3.org/2003/05/soap-envelope">
        <soap12:Body>
                <Challenge xmlns="http://www.imsglobal.org/services/pms/wsdl/imsPersonManServiceSync_v1p0" />
        </soap12:Body>
        </soap12:Envelope>'

        $splatWebRequest = @{
            Method      = 'POST'
            Uri         = $actionContext.Configuration.BaseUrl
            ContentType = 'text/xml; charset=utf-8'
            Body        = $xmlChallenge.InnerXml
        }
        [xml]$Response = (Invoke-WebRequest @splatWebRequest -UseBasicParsing -Verbose:$false).Content
        $challengeResult = $Response.Envelope.Body.ChallengeResponse.ChallengeResult


        # Challenge Response Request
        [xml]$xmlResponse = '<?xml version="1.0" encoding="utf-8"?>
        <soap12:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap12="http://www.w3.org/2003/05/soap-envelope">
        <soap12:Body>
            <Response xmlns="http://www.imsglobal.org/services/pms/wsdl/imsPersonManServiceSync_v1p0">
                <respCode></respCode>
            </Response>
        </soap12:Body>
        </soap12:Envelope>'
        $xmlResponse.Envelope.Body.Response.respCode = "$(ConvertTo-ChallengeResponseCode $challengeResult)"
        $splatWebRequest['Body'] = $xmlResponse
        $responseChallenge = Invoke-WebRequest @splatWebRequest  -UseBasicParsing -Verbose:$false
        Write-Output  $responseChallenge.Headers['Set-Cookie']
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
function ConvertTo-AuraAccountFromXML {
    [OutputType([PSCustomObject])]
    param(
        [Parameter(
            Mandatory,
            ValueFromPipeline = $True,
            Position = 0)]
            [System.Xml.XmlElement]
         $Person
    )

    $AuraAccountObject = [PSCustomObject] @{
        LENERSCODE =        $Person.userId.userIdValue.'#Text'
        VOORN =             $null
        VOORV =             $null
        LENERSNAAM =        $null
        EMAILADRES =        $null
        PASNUMMER =         $null
        ADRES =             $null
        PLAATS  =           $null
        POSTCODE =          $null
        GEBDATUM =          $null
        GESLACHT =          $null
        TELEFOON =          $null
        GSM =               $null
        KAMERNR =           $null
        CC_EMAILADRES =     $null
        VESTIGING =         $null
        UserPricipName =    $null
        password       =    $null
    }


    if ($null -ne $Person.email){
        if (($Person.email.getType().Name) -eq "String"){
            $AuraAccountObject.EMAILADRES =$Person.email
        }
        elseif (($Person.email.getType()).name -eq "XmlElement") {
            $AuraAccountObject.EMAILADRES = $Person.email.'#text'
        }
    }

    if ($null -ne $Person.address.street){
        if (($Person.address.street.getType().Name) -eq "String")
        {
            $AuraAccountObject.ADRES =$Person.address.street
        }
    }
    if ($null -ne $Person.address.locality){
        if (($Person.address.locality.getType()).name -eq "String")
        {
            $AuraAccountObject.PLAATS = $Person.address.locality
        }
    }
    if ($null -ne $Person.address.postcode){
        if (($Person.address.postcode.getType().Name) -eq "String")
        {
            $AuraAccountObject.POSTCODE = $Person.address.postcode
        }
    }
    if ($null -ne $Person.demographics.bday){
        if (($Person.demographics.bday.getType()).Name -eq "String")
        {
            $AuraAccountObject.GEBDATUM = $Person.demographics.bday
        }
    }
    if ($null -ne $Person.demographics.gender){
        if (($Person.demographics.gender.getType()).Name -eq "String")
        {
            $AuraAccountObject.GESLACHT = $Person.demographics.gender
        }
    }
    if ($null -ne $Person.address.extadd){
        if ($Person.address.extadd.getType().Name -eq "String")
        {
            $AuraAccountObject.KAMERNR = $Person.address.extadd
        }
    }

    if ($null -ne $Person.name){
        if(($Person.Name.getType()).name -eq "XmlElement"){
            if ($Person.Name.HasChildNodes){
                foreach ($item in $Person.Name.ChildNodes){
                    if($item.name -eq "partName"){
                        switch($item.NamePartType){
                            'First'{
                                $AuraAccountObject.VOORN = $item.namePartValue
                                break
                            }
                            'Middle'{
                                $AuraAccountObject.VOORV = $item.namePartValue
                                break
                            }
                            'Last'{
                                $AuraAccountObject.LENERSNAAM = $item.namePartValue
                                break
                            }
                        }
                    }
                }
            }
        }
    }
    if ($null -ne $Person.extension){
        if(($Person.extension.getType()).name -eq "XmlElement"){
            if ($Person.extension.HasChildNodes){
                foreach ($item in $Person.Extension.ChildNodes){
                    if($item.name -eq "extensionField"){
                        switch ($Item.fieldName){

                            'rentalcode' {
                                $AuraAccountObject.PASNUMMER = $Item.fieldValue
                                break
                            }
                            'cc_emailadres'{
                                $AuraAccountObject.CC_EMAILADRES = $Item.fieldValue
                                break
                            }
                            'vestiging'{
                                $AuraAccountObject.VESTIGING = $Item.fieldValue
                                break
                            }
                            'userprincipalname'{
                                $AuraAccountObject.UserPrincipName = $Item.fieldValue
                                break
                            }
                        }
                    }
                }
            }
        }
    }
    foreach ($item in $Person.ChildNodes) {
        if($item.name -eq "tel"){
            switch ($Item.telType_) {
                'Item1' {
                    $AuraAccountObject.TELEFOON = $Item.telValue
                    break
                }
                'Voice' {
                    $AuraAccountObject.TELEFOON = $Item.telValue
                    break
                }
                'Mobile' {
                    $AuraAccountObject.GSM = $Item.telValue
                    break
                }
            }

        }
    }

    Write-Output $AuraAccountObject

}

function ConvertTo-ImsAccountUpdateObject {
    param(
        [Parameter(
            Mandatory,
            ValueFromPipeline = $True,
            Position = 0)]
        $AuraAccount,

        [Parameter(
            Mandatory)
            ]
        $AccountRef
    )

    $ImsAccountObject = [PSCustomObject] @{
        address = @{}
        demographics = @{}
        userId = @{}
        name = @()
        telArray = @()
        extension = @()
    }

    $ImsAccountObject.userId.Add("userIdValue", $AccountRef)

    if (-not [string]::IsNullOrEmpty($AuraAccount.VOORN))
    {
        $part = @{
            partName = @{
                namePartType  = 'First'
                namePartValue =$AuraAccount.VOORN
            }
        }
        $ImsAccountObject.name += $part
    }
    if (-not [string]::IsNullOrEmpty($AuraAccount.VOORV))
    {
        $part = @{
            partName = @{
                namePartType  = 'Middle'
                namePartValue =$AuraAccount.VOORV
            }
        }
        $ImsAccountObject.name += $part
    }

    if (-not [string]::IsNullOrEmpty($AuraAccount.LENERSNAAM))
    {
        $part = @{
            partName = @{
                namePartType  = 'Last'
                namePartValue =$AuraAccount.LENERSNAAM
            }
        }
        $ImsAccountObject.name += $part
    }

    if (-not [string]::IsNullOrEmpty($AuraAccount.EMAILADRES))
    {
        $ImsAccountObject |  Add-Member -MemberType NoteProperty  -Name "email" -Value  $AuraAccount.EMAILADRES
    }

    if (-not [string]::IsNullOrEmpty($AuraAccount.PASNUMMER))
    {
        $extensionItem = @{
            extensionField = @{
                fieldName  = 'rentalcode'
                fieldType  = 'String'
                fieldValue =$AuraAccount.PASNUMMER
            }
        }
        $ImsAccountObject.extension += $extensionItem
    }

    if (-not [string]::IsNullOrEmpty($AuraAccount.ADRES))
    {
        $ImsAccountObject.address.add("street",$AuraAccount.ADRES)
    }

    if (-not [string]::IsNullOrEmpty($AuraAccount.POSTCODE))
    {
        $ImsAccountObject.address.add("postcode",$AuraAccount.POSTCODE)
    }

    if (-not [string]::IsNullOrEmpty($AuraAccount.PLAATS ))
    {
        $ImsAccountObject.address.add("locality",$AuraAccount.PLAATS)
    }

    if (-not [string]::IsNullOrEmpty($AuraAccount.KAMERNR))
    {
        $ImsAccountObject.address.add("extadd",$AuraAccount.KAMERNR)
    }

    if (-not [string]::IsNullOrEmpty($AuraAccount.GEBDATUM))
    {
        $ImsAccountObject.demographics.add("bday",$AuraAccount.GEBDATUM)
    }

    if (-not [string]::IsNullOrEmpty($AuraAccount.GESLACHT))
    {
        $ImsAccountObject.demographics.add("gender",$AuraAccount.GESLACHT)
    }

    if (-not [string]::IsNullOrEmpty($AuraAccount.TELEFOON))
    {
        $telephoneItem = @{
            tel = @{
                telValue = $AuraAccount.TELEFOON
                telType_ = "Voice"
            }
        }
        $ImsAccountObject.telArray += $telephoneItem
    }

    if (-not [string]::IsNullOrEmpty($AuraAccount.GSM))
    {
        $telephoneItem = @{
            tel = @{
                telValue = $AuraAccount.GSM
                telType_ = "Mobile"
            }
        }
        $ImsAccountObject.telArray += $telephoneItem
    }
    #UITSDATUM is not used in the create/update actions

    if (-not [string]::IsNullOrEmpty($AuraAccount.CC_EMAILADRES))
    {
        $extensionItem = @{
            extensionField = @{
                fieldName  = 'cc_emailadres'
                fieldType  = 'String'
                fieldValue =$AuraAccount.CC_EMAILADRES
            }
        }
        $ImsAccountObject.extension += ($extensionItem)
    }


    if (-not [string]::IsNullOrEmpty($AuraAccount.VESTIGING))
    {
        $extensionItem = @{
            extensionField = @{
                fieldName  = 'vestiging'
                fieldType  = 'String'
                fieldValue =$AuraAccount.VESTIGING
            }
        }
        $ImsAccountObject.extension += ($extensionItem)
    }


    if (-not [string]::IsNullOrEmpty($AuraAccount.UserPrincipName))
    {
        $extensionItem = @{
            extensionField = @{
                fieldName  = 'UserPrincipalName'
                fieldType  = 'String'
                fieldValue =$AuraAccount.UserPrincipName
            }
        }
        $ImsAccountObject.extension += $extensionItem

    }

    if (-not [string]::IsNullOrEmpty($AuraAccount.password))
    {
        $ImsAccountObject.UserID.add("password",$AuraAccount.password)

    }
    write-output $ImsAccountObject
}

function Write-ToAuraXmlDocument {
    [Cmdletbinding()]
    param(
        [Parameter(
            Mandatory,
            ValueFromPipeline = $True,
            Position = 0)]
        $Properties,

        [Parameter(Mandatory)]
        [System.Xml.XmlDocument]
        $XmlDocument,

        [Parameter(Mandatory)]
        [System.Xml.XmlElement]
        $XmlParentElement
    )
    if ($Properties.GetType().Name -eq "PSCustomObject") {
        $ParameterList = @{ }
        foreach ($prop in $Properties.PSObject.Properties) {
            $ParameterList[$prop.Name] = $prop.Value
        }
    } else {
        $ParameterList = $Properties
    }
    try {
        foreach ($param in $ParameterList.GetEnumerator()) {
            $xmlns = $null
            $xmlns = switch ($param.name) {
                { @( 'address', 'formatName', 'name', 'photo', 'extension', 'recordInfo', 'tel', 'demographics' , 'userId') -contains $_ } {
                    'http://www.imsglobal.org/services/pms/xsd/imsPersonManDataSchema_v1p0'
                    break
                }
                { @('extensionField', 'email', 'dataSource', 'authenticationType', 'passWord', 'pwEncryptionType', 'userIdType', 'userIdValue', 'identifier') -contains $_ } {
                    'http://www.imsglobal.org/services/common/imsCommonSchema_v1p0'
                    break
                }
                { @('comments', 'URL') -contains $_ } {
                    'http://www.imsglobal.org/services/pms/xsd/imsCommonSchema_v1p0'
                    break
                }
                default { $null }
            }
            $xmlElement = $null
            if ([string]::IsNullOrEmpty($xmlns)) {
                Clear-Variable  xmlns
            }
            $xmlElement = $XmlDocument.CreateElement($param.Name, $xmlns)

            if ((($param.Value) -is [PSCustomObject] -or ($param.Value) -is [Hashtable]) -and $null -ne $param.Value) {
                $ParameterList[$param.Name] | Write-ToAuraXmlDocument -XmlDocument  $XmlDocument -XmlParentElement $xmlElement
                $null = $XmlParentElement.AppendChild($xmlElement)
            } elseif ($param.Value -is [System.Object[]]) {
                $childElement = $XmlDocument.CreateElement($param.Name, $xmlns)
                foreach ($paramValue in $param.value) {
                    $paramValue | Write-ToAuraXmlDocument -XmlDocument  $XmlDocument -XmlParentElement $childElement
                }
                $null = $XmlParentElement.AppendChild($childElement)

            } else {
                $null = $xmlElement.InnerText = "$($param.Value)"
                $null = $XmlParentElement.AppendChild($xmlElement)
            }
        }
    } catch {
        $_
    }
}

function Resolve-AuraError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
            # Make sure to inspect the error result object and add only the error message as a FriendlyMessage.
            # $httpErrorObj.FriendlyMessage = $errorDetailsObject.message
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails # Temporarily assignment
        } catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    $cookieResponse = Get-AuraAuthenticationCookie
    $WebSession = Add-CookieToWebRequestSession  $cookieResponse

    Write-Information "Verifying if a Aura account for [$($personContext.Person.DisplayName)] exists"

    [xml]$xmlGetUser =  '<?xml version="1.0" encoding="utf-8"?>
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
        <soap:Body>
            <readPersonRequest xmlns="http://www.imsglobal.org/services/pms/xsd/imsPersonManMessSchema_v1p0">
                <sourcedId>
                    <identifier xmlns="http://www.imsglobal.org/services/common/imsCommonSchema_v1p0"></identifier>
                </sourcedId>
            </readPersonRequest>
        </soap:Body>
    </soap:Envelope>'

    $xmlGetUser.Envelope.Body.readPersonRequest.sourcedId.identifier.InnerText = "$($actionContext.References.Account)"
    $splatWebRequest = @{
        Method      = 'POST'
        Uri         = $actionContext.Configuration.BaseUrl
        ContentType = 'text/xml; charset=utf-8'
        Body        = $xmlGetUser.InnerXml
        WebSession  = $WebSession
    }

    if (-not  [string]::IsNullOrEmpty($actionContext.Configuration.ProxyAddress)) {
        $splatWebRequest['Proxy'] = $actionContext.Configuration.ProxyAddress
    }

    $userResponse =Invoke-RestMethod @splatWebRequest -UseBasicParsing -Verbose:$false
    $userXmlObject = ([xml]$userResponse).Envelope.Body.readPersonResponse.person
    $correlatedAccountID = $userXmlObject.userId.userIdValue.'#text'

    # Always compare the account against the current account in target system
    if ($null -ne $correlatedAccountID) {

        $CorrelatedAccount =   $userXmlObject  | ConvertTo-AuraAccountFromXML
        $outputContext.PreviousData = $correlatedAccount


        $splatCompareProperties = @{
            ReferenceObject  = @($correlatedAccount.PSObject.Properties)
            DifferenceObject = @(([PSCustomObject]$actionContext.Data).PSObject.Properties)
        }
        $propertiesChanged = Compare-Object @splatCompareProperties -PassThru | Where-Object { $_.SideIndicator -eq '=>' }
        if ($propertiesChanged) {
            $action = 'UpdateAccount'
            $dryRunMessage = "Account property(s) required to update: $($propertiesChanged.Name -join ', ')"
        } else {
            $action = 'NoChanges'
            $dryRunMessage = 'No changes will be made to the account during enforcement'
        }
    } else {
        $action = 'NotFound'
        $dryRunMessage = "Aura account for: [$($personContext.Person.DisplayName)] not found. Possibly deleted."
    }


    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Information "[DryRun] $dryRunMessage"
    }

    # Process
    if (-not($actionContext.DryRun -eq $true)) {
        switch ($action) {
            'UpdateAccount' {
                Write-Information "Updating Aura account with accountReference: [$($actionContext.References.Account)]"

                $auraUpdateAccount =  [PSCustomObject]$actionContext.Data | Select-Object -Property $propertiesChanged.Name
                $ImsUpdateAccount = $auraUpdateAccount | ConvertTo-ImsAccountUpdateObject -AccountRef $($actionContext.References.Account)

                # Make sure to test with special characters and if needed; add utf8 encoding.

                [xml]$updateXML = '<?xml version="1.0" encoding="utf-8"?>
                <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
                    <soap:Body>
                        <updatePersonRequest xmlns="http://www.imsglobal.org/services/pms/xsd/imsPersonManMessSchema_v1p0">
                            <sourcedId>
                                <identifier xmlns="http://www.imsglobal.org/services/common/imsCommonSchema_v1p0"></identifier>
                            </sourcedId>
                        </updatePersonRequest>
                    </soap:Body>
                </soap:Envelope>'

                $updateXML.Envelope.Body.updatePersonRequest.sourcedId.identifier.InnerText = "$($actionContext.References.Account)"
                $parentXmlElementPerson = $updateXML.Envelope.Body.updatePersonRequest.AppendChild( $updateXML.CreateElement('person'))

                $ImsUpdateAccount |  Select-Object *  -ExcludeProperty telArray  | Write-ToAuraXmlDocument -XmlDocument $updateXML -XmlParentElement $parentXmlElementPerson
                foreach ($tel in $ImsUpdateAccount.telArray) {
                    $tel | Write-ToAuraXmlDocument -XmlDocument $updateXML -XmlParentElement $parentXmlElementPerson
                }

                $splatWebRequest = @{
                    Method      = 'POST'
                    Uri         = $actionContext.Configuration.BaseUrl
                    ContentType = 'text/xml; charset=utf-8'
                    Body        = $updateXML.InnerXml.Replace(' xmlns="">', '>') #Remove empty NameSpace
                    WebSession  = $WebSession
                }
                $userResponse = Invoke-RestMethod @splatWebRequest -UseBasicParsing -Verbose:$false

                if ($userResponse.Envelope.Header.syncResponseHeaderInfo.statusInfo.codeMajor -eq 'failure' -or
                    ($userResponse.Envelope.Header.syncResponseHeaderInfo.statusInfo.codeMajor -ne 'success' -and
                    $userResponse.Envelope.Header.syncResponseHeaderInfo.statusInfo.description.text.'#text' -ne 'alles Ok'  )
                ) {
                    Write-Verbose $userResponse.Envelope.Header.syncResponseHeaderInfo.InnerXml
                    throw $userResponse.Envelope.Header.syncResponseHeaderInfo.statusInfo.description.text.'#text'
                }

                $outputContext.data = $actionContext.Data
                $outputContext.Success = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Update account was successful, Account property(s) updated: [$($propertiesChanged.name -join ',')]"
                    IsError = $false
                })
                break
            }

            'NoChanges' {
                Write-Information "No changes to Aura account with accountReference: [$($actionContext.References.Account)]"

                $outputContext.data = $actionContext.Data
                $outputContext.Success = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = 'No changes will be made to the account during enforcement'
                    IsError = $false
                })
                break
            }

            'NotFound' {
                $outputContext.Success  = $false
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Aura account with accountReference: [$($actionContext.References.Account)] could not be found, possibly indicating that it could be deleted, or the account is not correlated"
                    IsError = $true
                })
                break
            }
        }
    }
} catch {
    $outputContext.Success  = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-AuraError -ErrorObject $ex
        $auditMessage = "Could not update Aura account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not update Aura account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}
