// Enable a debug trace for the Guest User to capture exception from CaseQuestionClarifierAgentService
List<DebugLevel> levels = [SELECT Id FROM DebugLevel ORDER BY CreatedDate DESC LIMIT 1];
if (levels.isEmpty()) {
    System.debug('No DebugLevel found — create one in Developer Console first');
    return;
}

// Remove any existing TraceFlags for this user to avoid conflicts
List<TraceFlag> existing = [
    SELECT Id FROM TraceFlag WHERE TracedEntityId = '005dN00000Bu4NZQAZ'
];
if (!existing.isEmpty()) delete existing;

TraceFlag tf = new TraceFlag();
tf.TracedEntityId  = '005dN00000Bu4NZQAZ';
tf.DebugLevelId    = levels[0].Id;
tf.LogType         = 'USER_DEBUG';
tf.StartDate       = System.now();
tf.ExpirationDate  = System.now().addMinutes(30);
insert tf;
System.debug('TraceFlag ID: ' + tf.Id);
System.debug('Trace active for 30 minutes — submit a question via the portal now.');
System.debug('Then run: sf apex log list --target-org gptfy-poc1 to find the log');
