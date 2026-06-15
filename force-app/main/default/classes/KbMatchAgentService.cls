/**
 * KB match gate — invoked immediately after an agent saves a resolution with
 * "Create Knowledge Base article" checked.
 *
 * Uses the GPTfy KB_Match_Agent (RAG / vector store) to decide whether a
 * semantically similar Knowledge article already exists for this case.
 *
 * Decision logic (agent is the ONLY gate — no SOSL / no candidate pipeline):
 *
 *   Agent returns titles
 *     1. Exact SOQL: Title IN :agentTitles → match found → SKIP
 *     2. Fuzzy SOQL: LIKE keyword from each title → match found → SKIP
 *     3. No match confirmed → CREATE
 *
 *   Agent returns NONE, or call fails → CREATE
 *
 * GPTfy Agent: KB_Match_Agent (see docs/KB_Match_Agent_Prompt.md)
 */
public without sharing class KbMatchAgentService implements Queueable, Database.AllowsCallouts {

    @TestVisible
    static final String AGENT_NAME = 'KB_Match_Agent';

    private final Id caseId;

    public KbMatchAgentService(Id caseId) {
        this.caseId = caseId;
    }

    public void execute(QueueableContext ctx) {
        Case c;
        try {
            c = [SELECT Subject, Description FROM Case WHERE Id = :caseId LIMIT 1];
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'KbMatchAgentService: could not load Case ' + caseId +
                ' — ' + e.getMessage());
            return;
        }

        String userMessage =
            'Find existing knowledge base articles that are semantically similar to this support case:\n' +
            'Question: ' + c.Subject +
            (String.isNotBlank(c.Description)
                ? '\nContext: ' + c.Description.abbreviate(500)
                : '');

        try {
            ccai.AIAgenticWebService.RequestWrapper req = new ccai.AIAgenticWebService.RequestWrapper();
            req.agentName   = AGENT_NAME;
            req.userMessage = userMessage;

            ccai.AIAgenticWebService.ResponseWrapper resp = ccai.AIAgenticUtility.invokeAgent(req);

            if (resp == null || String.isBlank(resp.responseBody)) {
                System.debug(LoggingLevel.WARN,
                    'KbMatchAgentService: agent returned no response for Case ' + caseId +
                    ' — proceeding to create');
                chainCreation();
                return;
            }

            String normalizedBody = normalizeAgentResponse(resp.responseBody);
            List<String> titles = parseMatchTitles(normalizedBody);

            if (titles.isEmpty()) {
                System.debug(LoggingLevel.INFO,
                    'KbMatchAgentService: agent returned NONE for Case ' + caseId +
                    ' — proceeding to create');
                chainCreation();
                return;
            }

            // Agent found semantically similar articles — verify at least one exists in org.
            List<Knowledge__kav> articles = [
                SELECT Id, Title, PublishStatus
                FROM Knowledge__kav
                WHERE Title IN :titles
                  AND PublishStatus IN ('Draft', 'Online')
                LIMIT 5
            ];

            if (!articles.isEmpty()) {
                System.debug(LoggingLevel.INFO,
                    'KbMatchAgentService: existing article confirmed via SOQL for Case ' + caseId +
                    ' — skipping creation. Matched: ' + articles[0].Title);
                saveAndSkip(caseId, normalizedBody);
                return;
            }

            // Exact-title lookup failed — the agent paraphrases titles (e.g. long
            // customer-question titles become short summaries). Try a keyword LIKE
            // search using distinctive words extracted from the agent's returned titles.
            List<Knowledge__kav> fuzzy = fuzzyTitleSearch(titles);
            if (!fuzzy.isEmpty()) {
                System.debug(LoggingLevel.INFO,
                    'KbMatchAgentService: keyword LIKE match found "' + fuzzy[0].Title +
                    '" for Case ' + caseId + ' — skipping creation.');
                saveAndSkip(caseId, normalizedBody);
                return;
            }

            // No exact or fuzzy match — agent title is unconfirmed (likely hallucinated
            // or genuinely novel topic). Proceed to create.
            System.debug(LoggingLevel.INFO,
                'KbMatchAgentService: no article confirmed for ' + titles +
                ' (Case ' + caseId + ') — proceeding to create.');
            chainCreation();

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'KbMatchAgentService: agent call failed for Case ' + caseId +
                ' — ' + e.getTypeName() + ': ' + e.getMessage() +
                ' | Stack: ' + e.getStackTraceString() +
                ' — proceeding to create');
            chainCreation();
        }
    }

    // ─── Parsers ─────────────────────────────────────────────────────────────────

    /**
     * GPTfy agents often return HTML (<br>, <p>, entities). Normalise to plain
     * text before parsing structured blocks so titles split onto separate lines.
     */
    public static String normalizeAgentResponse(String responseBody) {
        if (String.isBlank(responseBody)) return responseBody;

        String normalized = responseBody
            .replaceAll('(?i)<br\\s*/?>', '\n')
            .replaceAll('(?i)</p>', '\n')
            .replaceAll('(?i)</div>', '\n');

        if (normalized.contains('<')) {
            normalized = normalized.stripHtmlTags();
        }

        normalized = normalized
            .replace('&nbsp;', ' ')
            .replace('&#39;', '\'')
            .replace('&apos;', '\'')
            .replace('&quot;', '"')
            .replace('&lt;', '<')
            .replace('&gt;', '>')
            .replace('&amp;', '&');

        return normalized.trim();
    }

    /**
     * Extracts article titles from the KB_MATCHES_START...KB_MATCHES_END block.
     * Returns empty list when the agent reports NONE or block is absent.
     */
    public static List<String> parseMatchTitles(String responseBody) {
        List<String> titles = new List<String>();
        if (String.isBlank(responseBody)) return titles;

        Pattern p = Pattern.compile('(?is)KB_MATCHES_START\\s*(.+?)\\s*KB_MATCHES_END');
        Matcher m = p.matcher(responseBody);
        if (!m.find()) return titles;

        String block = m.group(1).trim();
        if (String.isBlank(block) || block.equalsIgnoreCase('NONE')) return titles;

        for (String line : block.split('\r?\n')) {
            line = line.trim();
            if (String.isNotBlank(line) && !line.equalsIgnoreCase('NONE')) {
                titles.add(line);
            }
        }
        return titles;
    }

    /**
     * Extracts the KB_UPDATE_SCOPE_START...KB_UPDATE_SCOPE_END block verbatim.
     * Returns null when the block is absent (NONE path — no scope to record).
     */
    @TestVisible
    static String parseUpdateScope(String responseBody) {
        if (String.isBlank(responseBody)) return null;

        Pattern p = Pattern.compile(
            '(?is)KB_UPDATE_SCOPE_START\\s*(.+?)\\s*KB_UPDATE_SCOPE_END');
        Matcher m = p.matcher(responseBody);
        if (!m.find()) return null;

        String block = m.group(1).trim();
        return String.isBlank(block) ? null : block;
    }

    // ─── Fuzzy title search ───────────────────────────────────────────────────────

    /**
     * Extracts one distinctive keyword (≥6 chars, not a stop-word) from each
     * agent-returned title and runs a SOQL LIKE query against Knowledge__kav titles.
     *
     * This handles the common case where the agent paraphrases or abbreviates a
     * long customer-question title (e.g. "How to export PDF tables to a single
     * Excel worksheet" → actual title "How to Convert a PDF Document into an
     * Excel File on a Single Sheet"). A keyword like "Excel" or "worksheet" still
     * links them without requiring SOSL.
     */
    @TestVisible
    static List<Knowledge__kav> fuzzyTitleSearch(List<String> agentTitles) {
        // Common words that appear in many titles and would produce false positives.
        Set<String> stopWords = new Set<String>{
            'about', 'after', 'before', 'cannot', 'create', 'could', 'document',
            'during', 'error', 'fails', 'files', 'issue', 'issues', 'opening',
            'power', 'problem', 'single', 'should', 'their', 'there', 'these',
            'those', 'update', 'using', 'where', 'which', 'would'
        };

        List<String> likeConditions = new List<String>();
        for (String title : agentTitles) {
            for (String word : title.replaceAll('[^a-zA-Z0-9 ]', ' ').split('\\s+')) {
                String lower = word.toLowerCase();
                if (word.length() >= 6 && !stopWords.contains(lower)) {
                    likeConditions.add(
                        'Title LIKE \'%' + String.escapeSingleQuotes(word) + '%\''
                    );
                    break; // one keyword per agent title is enough
                }
            }
        }

        if (likeConditions.isEmpty()) return new List<Knowledge__kav>();

        String query =
            'SELECT Id, Title, PublishStatus FROM Knowledge__kav WHERE (' +
            String.join(likeConditions, ' OR ') +
            ') AND PublishStatus IN (\'Draft\', \'Online\') LIMIT 5';

        return Database.query(query);
    }

    // ─── Persistence ─────────────────────────────────────────────────────────────

    /** Skip KB creation and write scope analysis to Case if present. */
    private static void saveAndSkip(Id caseId, String responseBody) {
        String scope = parseUpdateScope(responseBody);
        if (String.isNotBlank(scope)) {
            // Agent returns HTML-wrapped responses — convert <br> to newlines and
            // strip remaining tags so the LongTextArea field renders clean plain text.
            if (scope.contains('<')) {
                scope = scope
                    .replaceAll('(?i)<br\\s*/?>', '\n')
                    .replaceAll('(?i)</p>', '\n')
                    .stripHtmlTags()
                    .replaceAll('(\r?\n){3,}', '\n\n')
                    .trim();
            }
            saveUpdateScope(caseId, scope);
        }
    }

    /**
     * Writes scope analysis to KB_Candidates__c (relabelled "KB Update Scope").
     * This field is blank in the CREATE path, so the GPTfy KB Creation Prompt
     * simply receives no candidates — which is correct. In the SKIP path (here),
     * creation is never invoked, so the scope content never reaches the prompt.
     */
    private static void saveUpdateScope(Id caseId, String scope) {
        try {
            update new Case(
                Id               = caseId,
                KB_Candidates__c = scope
            );
            System.debug(LoggingLevel.INFO,
                'KbMatchAgentService: KB Update Scope written to KB_Candidates__c for Case ' + caseId);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                'KbMatchAgentService: failed to save KB Update Scope for Case ' + caseId +
                ' — ' + e.getMessage());
        }
    }

    private void chainCreation() {
        System.enqueueJob(KbCreationService.forPromptPhase(caseId));
    }
}
