Case c = new Case(
    Origin        = 'Web',
    Status        = 'Open',
    Priority      = 'Medium',
    Subject       = 'How do I configure Power PDF Volume to enforce a document retention policy that automatically redacts and flattens fields before saving to a network share',
    SuppliedName  = 'Route4 Test',
    SuppliedEmail = 'route4@test.com'
);
insert c;
System.debug('Case ID: ' + c.Id);
System.debug('Case URL: https://gptfypoc-dev-ed.develop.my.salesforce.com/lightning/r/Case/' + c.Id + '/view');
