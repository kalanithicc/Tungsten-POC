String marker = 'cursor-test-' + Datetime.now().format('yyyyMMdd-HHmmss');

String subject = marker + ' How do I configure Power PDF Volume to enforce a document retention policy that automatically redacts and flattens fields before saving to a network share?';

String resolution = 'To enforce a document retention policy in Power PDF Volume, use the Auto-Save profile combined with the Redaction and Flatten features:\n\n'
    + '1. Open Tools > Options > Auto-Save and create a new profile named "Retention Policy".\n'
    + '2. Enable "Flatten form fields before save" in the profile settings to permanently embed all interactive fields.\n'
    + '3. Enable "Apply redaction marks on save" so any marked content is permanently removed before the file is written.\n'
    + '4. Under Output Folder, enter the UNC path to your network share (e.g., \\\\fileserver\\archive).\n'
    + '5. Set the retention trigger to "On document close" so every document is processed automatically.\n'
    + '6. In the Power PDF Volume License admin console, assign this profile to the relevant user group or department.\n'
    + '7. Save and distribute the updated configuration. All documents will now be automatically redacted, flattened, and saved to the network share on close.';

Case c = new Case(
    Origin        = 'Web',
    Status        = 'Open',
    Priority      = 'Medium',
    Subject       = subject,
    Description   = resolution,
    SuppliedName  = 'Route4 Test V3',
    SuppliedEmail = 'route4v3@test.com'
);
insert c;

// Simulate the Resolve quick-action: close the case and enqueue KB match check
CaseResolveActionController.SaveResult result =
    CaseResolveActionController.saveResolution(c.Id, resolution, true);

System.debug('=== ROUTE 4 CASE CREATED & RESOLVED ===');
System.debug('Case ID   : ' + c.Id);
System.debug('Marker    : ' + marker);
System.debug('KB queued : ' + result.articleQueued);
System.debug('Case URL  : https://gptfypoc-dev-ed.develop.lightning.force.com/lightning/r/Case/' + c.Id + '/view');
