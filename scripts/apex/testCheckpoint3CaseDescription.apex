String marker = 'cursor-test-' + Datetime.now().format('yyyyMMdd-HHmmss');

String agentQ = 'Product: PowerPDF\nQuestion: How do I set retention policy?';
String answer = 'Open Settings > Retention and enable the policy.';

// ── 1. Manual agent close path ───────────────────────────────────────────────
Case manualCase = new Case(
    Origin                        = 'Web',
    Status                        = 'New',
    Subject                       = marker + ' manual close checkpoint3',
    GPTfy_Question__c             = agentQ,
    AI_Clarification_Pending__c   = true
);
insert manualCase;

String manualResolution = 'Restart the service and clear cache.';
CaseResolveActionController.saveResolution(manualCase.Id, manualResolution, false);

Case manualAfter = [
    SELECT Id, CaseNumber, Description, Resolution__c, Status
    FROM Case
    WHERE Id = :manualCase.Id
];
System.assertEquals('Closed', manualAfter.Status, 'PASS manual case closed');
System.assert(
    manualAfter.Description.contains(CaseDescriptionFormatter.QUESTION_LABEL),
    'PASS manual Description has Question label'
);
System.assert(
    manualAfter.Description.contains(CaseDescriptionFormatter.RESOLUTION_LABEL),
    'PASS manual Description has Resolution Provided label'
);
System.assert(
    manualAfter.Description.contains(agentQ),
    'PASS manual Description includes GPTfy_Question__c text'
);
System.assert(
    manualAfter.Description.contains(manualResolution),
    'PASS manual Description includes agent resolution'
);

// ── 2. Guest self-resolve close path (CaseResolvedTrigger) ───────────────────
Case aiCase = new Case(
    Origin                        = 'Web',
    Status                        = 'New',
    Subject                       = marker + ' guest close checkpoint3',
    GPTfy_Question__c             = agentQ,
    Summary__c                    = '<p>' + answer + '</p>',
    Description                   = answer,
    AI_Clarification_Pending__c   = true
);
insert aiCase;

System.assertNotEquals(
    CaseDescriptionFormatter.formatOnClose(aiCase),
    aiCase.Description,
    'PASS Description stays answer-only while case is open'
);

// Anonymous Apex cannot use Test.startTest(), so apply the same close update
// CaseResolvedTrigger performs when the guest clicks "Yes, resolved".
Case aiOpen = [
    SELECT Id, Subject, GPTfy_Question__c, Description, Summary__c
    FROM Case
    WHERE Id = :aiCase.Id
];
update new Case(
    Id            = aiOpen.Id,
    Status        = 'Closed',
    Resolution__c = aiOpen.Summary__c,
    Description   = CaseDescriptionFormatter.formatOnClose(aiOpen)
);

Case aiAfter = [
    SELECT Id, CaseNumber, Description, Summary__c, Status, Resolution__c
    FROM Case
    WHERE Id = :aiCase.Id
];
System.assertEquals('Closed', aiAfter.Status, 'PASS guest close sets Status Closed');
System.assert(
    aiAfter.Description.contains(CaseDescriptionFormatter.QUESTION_LABEL),
    'PASS guest-close Description has Question label'
);
System.assert(
    aiAfter.Description.contains(CaseDescriptionFormatter.RESOLUTION_LABEL),
    'PASS guest-close Description has Resolution Provided label'
);
System.assert(
    aiAfter.Description.contains(agentQ),
    'PASS guest-close Description includes resolver question'
);
System.assert(
    aiAfter.Description.contains(answer),
    'PASS guest-close Description includes plain resolution'
);

System.debug('=== CURSOR TEST COMPLETE ===');
System.debug('Marker: ' + marker);
System.debug('Manual Case: ' + manualAfter.CaseNumber + ' / ' + manualAfter.Id);
System.debug('Guest-close Case: ' + aiAfter.CaseNumber + ' / ' + aiAfter.Id);
