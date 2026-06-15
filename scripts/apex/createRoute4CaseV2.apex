String marker = 'cursor-test-' + Datetime.now().format('yyyyMMdd-HHmmss');
Case c = new Case(
    Origin        = 'Web',
    Status        = 'Open',
    Priority      = 'Medium',
    Subject       = marker + ' Power PDF USB token signing: SafeNet eToken not recognized by enterprise CA certificate',
    Description   = 'When attempting to digitally sign a PDF using a SafeNet eToken 5110 USB hardware token with a certificate from our internal enterprise CA, Power PDF Advanced does not list the token certificate in the signing dialog. Other applications (Adobe Acrobat, Outlook) can see and use the certificate without issues.',
    SuppliedName  = 'Route4 Test V2',
    SuppliedEmail = 'route4v2@test.com'
);
insert c;
System.debug('=== ROUTE 4 TEST CASE CREATED ===');
System.debug('Case ID: ' + c.Id);
System.debug('Marker: ' + marker);
System.debug('Case URL: https://gptfypoc-dev-ed.develop.lightning.force.com/lightning/r/Case/' + c.Id + '/view');
