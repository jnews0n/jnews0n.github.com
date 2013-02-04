import-csv clientcontacts.csv | ForEach
	{
		new-mailcontact -name $_.name -externalemailaddress $_.emailaddress;
set-contact -identity $_.name -office $_.office -department $_.department -OrganizationalUnit "Client_Contact_Test"
	}
	
	DN,
	objectClass,
	distinguishedName,
	name,
	objectCategory,
	cn,
	sn,
	givenName,
	displayName,
	telephoneNumber,
	mobile,
	company,
	mail,
	streetAddress,
	l,
	st,
	postalCode
	

	New-MailContact -ExternalEmailAddress 'SMTP:test.contact@nowhere.localdomain' -Name 'Test Contact' -Alias 'TestContact' -FirstName 'Test' -Initials '' -LastName 'Contact' 
