#Create a nightly scheduled task that runs shortly after midnight and execute this script to generate password expiration email reminders
# Will need the Quest Active Directory powershell extensions
Import-Module ActiveDirectory

#----- Configurable Settings ------------------------------------------------------------------------------------------------------------------------

# Set the $warningInterval array to change when password expiration email reminders go out. 
# The default below will email users at 30 days, 15 days, 7 days, 5 days, 3 days, 2 days, 1 day and the day of.
$warningIntervals = 15,7,5,4,3,2,1,0


# Set the $adminEmail to the email address that will receive password expiration reminders if the user does not have an associated mail address in AD
$adminEmail = 'someone@localhost'


# Set the $fromEmail to the email address that will be used to send out password expiration reminders
$fromEmail = 'maybe-someone-else@localhost'


# Set the SMTP server used for sending out password expiration reminders, no authentication is used
$smtpServer = "A MAIL SERVER"


# If $True, a summary will always be sent to $adminEmail. If $False, a summary will only be sent when there are user accounts that need attention.
$alwaysSendAdminSummary = $True

#----- End Configurable Settings -------------------------------------------------------------------------------------------------------------------


#Constant used to determine if password never expires flag is set
$ADS_UF_DONT_EXPIRE_PASSWD = 0x00010000

#Constant used to determine if user must change password at next login
$REQUIRED_PASSWORD_CHANGE_LASTSET = 0

$CurrentDate = [datetime]::Now.Date
$adminEmailContent = ""

$DefaultDomainPasswordPolicy = Get-ADDefaultDomainPasswordPolicy 
$smtp = new-object Net.Mail.SmtpClient($smtpServer)

function GetDaysToExpire([datetime] $expireDate)
{
    $date =  New-TimeSpan $CurrentDate $expireDate
    return $date.Days
}

function GetPasswordExpireDate($user)
{
    return [datetime]::FromFileTimeUTC($user.pwdLastSet+$DefaultDomainPasswordPolicy.MaxPasswordAge.Ticks)
}

function IsInWarningIntervals([int] $daysToExpire)
{
    foreach( $interval in $warningIntervals )
    {
       if ( $daysToExpire -eq $interval )
       {
        return $True
       }
    }
    return $False
}

function EmailUser($user)
{
    $pwdExpires = GetPasswordExpireDate $user
    $daysToExpire = GetDaysToExpire $pwdExpires 

    if( $daysToExpire -eq 0 )
    {
        $emailContent = $user.DisplayName + ", your password will expire today at " + $pwdExpires.ToShortTimeString() + " GMT"
    }
    else
    {
        $emailContent = $user.DisplayName + ", your password will expire in " + $daysToExpire + " days."
    }
    $smtp.Send($fromEmail, $user.mail, "Password Expiration Reminder", $emailContent)
}

function EmailAdmin($content) 
{
    if( [string]::IsNullOrEmpty($content) -and $alwaysSendAdminSummary )
    {
        $content = "There are no users with expired passwords or users that need to change their password."
    }
    if( [string]::IsNullOrEmpty($content) -ne $True )
    {
        $smtp.Send($fromEmail, $adminEmail, "Password Expiration Summary", $content)
    }
}

function AppendAdminEmailNoMail($user)
{
    $pwdExpires = GetPasswordExpireDate $user
    $daysToExpire = GetDaysToExpire $pwdExpires 

    return "The password for account """ + $user.samAccountName + """ will expire in " + $daysToExpire + " days at " + $pwdExpires + " and there is no associated email address to send a notification to" + [System.Environment]::NewLine + [System.Environment]::NewLine
}

function AppendAdminEmailExpiredAccount($user)
{
    $pwdExpires = GetPasswordExpireDate $user
    $daysToExpire = GetDaysToExpire $pwdExpires 

    if( $user.pwdLastSet -eq 0 )
    {
        return "The user account """ + $user.samAccountName + """ is set to require a password change at next logon and the user has not yet changed it" + [System.Environment]::NewLine + [System.Environment]::NewLine
    }
    else
    {
        return "The password for user account """ + $user.samAccountName + """ expired " + $daysToExpire + " days ago on " + $pwdExpires + [System.Environment]::NewLine + [System.Environment]::NewLine
    }
}


#get all users
$users = Get-AdUser -Filter * -Properties userAccountControl, pwdLastSet, userprincipalname, mail, DisplayName, samAccountName, accountExpires, enabled  #|
# FT -Property @{Label="UAC";Expression={"0x{0:x}" -f $_.userAccountControl}}, userAccountControl, pwdLastSet, @{Label="pwdLastChanged";Expression={[datetime]::FromFileTimeUTC($_.pwdLastSet)}}, @{Label="pwdExpires";Expression={[datetime]::FromFileTimeUTC($_.pwdLastSet+$DefaultDomainPasswordPoliy.MaxPasswordAge.Ticks)}}, userprincipalname, mail, DisplayName, samAccountName, accountExpires, enabled
#$users

foreach( $user in $users ) 
{  
    #if account is enabled and password never expire flag does not exist, then process user
    if ( ($user.enabled -eq $True) -and (($user.userAccountControl -band $ADS_UF_DONT_EXPIRE_PASSWD) -eq 0) ) 
    {        
        $pwdExpires = GetPasswordExpireDate $user 
        $daysToExpire = GetDaysToExpire $pwdExpires 

        #if day falls on warning interval
        if( IsInWarningIntervals $daysToExpire )
        {
            #if mail attribute is not found in AD, add to admin email
            if ( [string]::IsNullOrEmpty($user.mail) ) 
            {
                $adminEmailContent += AppendAdminEmailNoMail $user
                
            }
            #otherwise email user
            else
            {
                EmailUser $user 
                   
            }
        }

        #if days to expire is negative, password has expired. add to admin email
        if( $daysToExpire -lt 0 )
        {
            $adminEmailContent += AppendAdminEmailExpiredAccount  $user
            EmailUser $user
        }
    }
}

EmailAdmin $adminEmailContent