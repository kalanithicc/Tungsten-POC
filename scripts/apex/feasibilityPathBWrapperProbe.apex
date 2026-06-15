// Compile probe: which RequestWrapper properties exist?
// Run once; comment/uncomment blocks to test.

ccai.AIAgenticWebService.RequestWrapper req = new ccai.AIAgenticWebService.RequestWrapper();
req.agentName = 'Question_Clarifier_Agent';
req.userMessage = 'probe';

// Uncomment ONE block at a time in separate deploy runs if needed.
// req.recordId = '500dN00000PNpEkQAL';
// req.userContextId = 'A-00706';
// req.threadId = 'resp_0328e74f5d904c9f006a2e7f9343ac819abc18bd4e46a6281a';
// req.contextId = 'A-00706';
// req.sessionId = 'A-00706';

System.debug('probe ok');
