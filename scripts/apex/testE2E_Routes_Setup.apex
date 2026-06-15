/**
 * End-to-End Test — ALL 4 ROUTES — SETUP & TRIGGER
 *
 * Route 1: Customer asks → AI resolves → Customer says YES → Case closed
 * Route 2: Customer asks → AI resolves → Customer says NO  → Case stays open
 * Route 3: Agent resolves → Create KB = true → KB already exists → SKIP
 * Route 4: Agent resolves → Create KB = true → No KB match   → CREATE article
 *
 * Run FIRST. Then wait 5+ minutes and run testE2E_Routes_Verify.apex.
 */
String marker = 'cursor-test-' + Datetime.now().format('yyyyMMdd-HHmmss');
System.debug('========================================================');
System.debug('E2E SETUP — Marker: ' + marker);
System.debug('========================================================');

// ─── AI-like answer used for Routes 1 & 2 (simulates what CaseAgentResolutionService writes) ──
String htmlAnswer =
    '<p><strong>Browser Cache Issue — Resolution Steps</strong></p>' +
    '<p>1. Open your browser settings and navigate to Privacy / History.</p>' +
    '<p>2. Select "Clear browsing data" and include Cached images, Cookies, and Site data.</p>' +
    '<p>3. Restart your browser and attempt to log in again.</p>' +
    '<p>4. If the issue persists, try an Incognito/Private window to rule out extensions.</p>';

String plainAnswer =
    'Browser Cache Issue - Resolution Steps\n' +
    '1. Open your browser settings and navigate to Privacy / History.\n' +
    '2. Select Clear browsing data and include Cached images, Cookies, and Site data.\n' +
    '3. Restart your browser and attempt to log in again.\n' +
    '4. If the issue persists, try an Incognito/Private window to rule out extensions.';

// ═══════════════════════════════════════════════════════════════
// ROUTE 1 — Self-service: AI answer good → customer clicks YES → Case closes
// ═══════════════════════════════════════════════════════════════
System.debug('');
System.debug('--- ROUTE 1: Setting up self-service YES case ---');

Case route1 = new Case(
    Origin        = 'Web',
    Status        = 'New',
    Priority      = 'Medium',
    Subject       = marker + ' R1: Browser cache blocking login',
    SuppliedName  = 'E2E Test Customer',
    SuppliedEmail = 'e2etest@example.com',
    Summary__c    = htmlAnswer,
    Description   = plainAnswer
);
insert route1;

// Verify getRecommendation() returns the AI answer before resolving
String rec1 = CaseResolutionController.getRecommendation(route1.Id);
System.assert(String.isNotBlank(rec1),
    'Route 1 FAIL: getRecommendation() should return content after Summary__c is populated');
System.debug('Route 1 — getRecommendation() returned ' + rec1.length() + ' chars. PASS');

// Simulate customer clicking "Yes, resolved"
CaseResolutionController.resolveCase(route1.Id);
System.debug('Route 1 — resolveCase() published Case_Resolved__e for ' + route1.Id);
System.debug('Route 1 Case Id: ' + route1.Id + ' (verify Status=Closed after ~30s)');

// ═══════════════════════════════════════════════════════════════
// ROUTE 2 — Self-service: AI answer shown → customer clicks NO → Case stays open
// ═══════════════════════════════════════════════════════════════
System.debug('');
System.debug('--- ROUTE 2: Setting up self-service NO case ---');

Case route2 = new Case(
    Origin        = 'Web',
    Status        = 'New',
    Priority      = 'Medium',
    Subject       = marker + ' R2: Login page not loading at all',
    SuppliedName  = 'E2E Test Customer',
    SuppliedEmail = 'e2etest@example.com',
    Summary__c    = htmlAnswer,
    Description   = plainAnswer
);
insert route2;

// Verify getRecommendation() returns content (AI has answered)
String rec2 = CaseResolutionController.getRecommendation(route2.Id);
System.assert(String.isNotBlank(rec2),
    'Route 2 FAIL: getRecommendation() should return content');
System.debug('Route 2 — getRecommendation() returned ' + rec2.length() + ' chars. PASS');

// Customer clicks NO — do NOT call resolveCase(). Case stays open.
System.debug('Route 2 — resolveCase() NOT called (simulating customer said No)');
System.debug('Route 2 Case Id: ' + route2.Id + ' (verify Status=New/Open after ~30s)');

// ═══════════════════════════════════════════════════════════════
// ROUTE 3 — Agent resolve → Create KB = true → KB already exists → SKIP
// Subject aligned with existing KB "How to Disable Thumbnail Generation for PDF Files in Windows 11"
// ═══════════════════════════════════════════════════════════════
System.debug('');
System.debug('--- ROUTE 3: Setting up agent-resolve SKIP case ---');

String route3Resolution =
    'PDF file thumbnails are no longer appearing in Windows 11 File Explorer after installing Power PDF. ' +
    'Power PDF registers itself as the default PDF thumbnail provider during install, which can conflict with ' +
    'Windows 11 thumbnail cache. Fix: open Settings > Apps > Default Apps, search for PDF, confirm the thumbnail ' +
    'handler is set correctly. Then clear the thumbnail cache via Disk Cleanup > Thumbnails.';

Case route3 = new Case(
    Origin        = 'Web',
    Status        = 'New',
    Priority      = 'Medium',
    Subject       = marker + ' R3: PDF thumbnails missing in Windows 11 File Explorer after Power PDF install',
    SuppliedName  = 'E2E Test Agent',
    SuppliedEmail = 'agent@example.com',
    Description   = route3Resolution
);
insert route3;

// Agent saves resolution + requests KB creation
CaseResolveActionController.SaveResult result3 =
    CaseResolveActionController.saveResolution(route3.Id, route3Resolution, true);
System.assert(result3.caseClosed,
    'Route 3 FAIL: saveResolution() should set caseClosed=true');
System.assert(result3.articleQueued,
    'Route 3 FAIL: saveResolution() should set articleQueued=true when createKb=true');
System.debug('Route 3 — Case closed and KB job queued. ' +
    'KbMatchAgentService will find existing article and SKIP creation.');
System.debug('Route 3 Case Id: ' + route3.Id +
    ' (verify no KB_Article_Link__c and no CaseArticle after ~5 min)');

// ═══════════════════════════════════════════════════════════════
// ROUTE 4 — Agent resolve → Create KB = true → No KB match → CREATE new article
// Use a completely unique topic not present in the Knowledge Base.
// ═══════════════════════════════════════════════════════════════
System.debug('');
System.debug('--- ROUTE 4: Setting up agent-resolve CREATE case ---');

String uniqueTopic = 'cursor-test-R4-' + Datetime.now().format('HHmmss');
String route4Resolution =
    uniqueTopic + ': Configuring OAuth2 PKCE flow for mobile app deep-link redirect URIs. ' +
    'When a mobile app registers a custom URI scheme (e.g. myapp://oauth/callback), the ' +
    'authorization server must whitelist the exact scheme. Steps: ' +
    '1. Register the redirect URI in your OAuth2 provider under Mobile/Native app type. ' +
    '2. Generate a code_verifier (43-128 random chars) and derive code_challenge as BASE64URL(SHA256(verifier)). ' +
    '3. Include code_challenge and code_challenge_method=S256 in the /authorize request. ' +
    '4. Exchange the authorization code plus code_verifier at /token. ' +
    '5. Verify the id_token signature using the JWKS endpoint before trusting claims.';

Case route4 = new Case(
    Origin        = 'Web',
    Status        = 'New',
    Priority      = 'Medium',
    Subject       = marker + ' R4: ' + uniqueTopic + ' OAuth2 PKCE mobile',
    SuppliedName  = 'E2E Test Agent',
    SuppliedEmail = 'agent@example.com',
    Description   = route4Resolution
);
insert route4;

// Agent saves resolution + requests KB creation
CaseResolveActionController.SaveResult result4 =
    CaseResolveActionController.saveResolution(route4.Id, route4Resolution, true);
System.assert(result4.caseClosed,
    'Route 4 FAIL: saveResolution() should set caseClosed=true');
System.assert(result4.articleQueued,
    'Route 4 FAIL: saveResolution() should set articleQueued=true when createKb=true');
System.debug('Route 4 — Case closed and KB job queued. ' +
    'KbMatchAgentService should find NO match and chain KB Creation Prompt.');
System.debug('Route 4 Case Id: ' + route4.Id +
    ' (verify KB_Article_Link__c and CaseArticle after ~5 min)');

// ═══════════════════════════════════════════════════════════════
// SUMMARY
// ═══════════════════════════════════════════════════════════════
System.debug('');
System.debug('========================================================');
System.debug('SETUP COMPLETE — All 4 routes triggered.');
System.debug('Marker: ' + marker);
System.debug('Route 1 (YES → close)  : ' + route1.Id);
System.debug('Route 2 (NO  → open)   : ' + route2.Id);
System.debug('Route 3 (skip KB)      : ' + route3.Id);
System.debug('Route 4 (create KB)    : ' + route4.Id);
System.debug('');
System.debug('WAIT 5+ minutes, then run: testE2E_Routes_Verify.apex');
System.debug('Or query cases with: Subject LIKE \'%' + marker + '%\'');
System.debug('========================================================');
