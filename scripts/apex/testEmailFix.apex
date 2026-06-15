String marker = 'cursor-test-' + Datetime.now().format('yyyyMMdd-HHmmss');

// Create a closed case with a plain-text Description and a populated Resolution__c
Case c = new Case(
    Subject      = marker + ' email-html-fix verify',
    Status       = 'New',
    Origin       = 'Web',
    SuppliedEmail= 'kesavamoorthy@cloudcompliance.app',
    Description  = 'Step 1: Open the settings panel.\nStep 2: Select the output format.\nStep 3: Click Save.'
);
insert c;

// Simulate what CaseResolvedTrigger does: copy Description to Resolution__c, close the case
c.Resolution__c = c.Description;
c.Status = 'Closed';
update c;

System.debug('=== EMAIL FIX TEST ===');
System.debug('Case Id: ' + c.Id);
System.debug('Description (plain text, no HTML): ' + c.Description);
System.debug('Marker: ' + marker);
System.debug('The flow will fire on close and send email to kesavamoorthy@cloudcompliance.app');
