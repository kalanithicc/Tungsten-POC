import { LightningElement, wire } from 'lwc';
import submitForClarification from '@salesforce/apex/CaseResolutionController.submitForClarification';
import getClarification from '@salesforce/apex/CaseResolutionController.getClarification';
import confirmQuestion from '@salesforce/apex/CaseResolutionController.confirmQuestion';
import getRecommendation from '@salesforce/apex/CaseResolutionController.getRecommendation';
import resolveCase from '@salesforce/apex/CaseResolutionController.resolveCase';
import getProductOptions from '@salesforce/apex/CaseResolutionController.getProductOptions';
import getPortalUserContext from '@salesforce/apex/CaseResolutionController.getPortalUserContext';

const CLARIFY_AGENT_UNAVAILABLE_USER =
    'Our AI assistant is temporarily unavailable. Please try again in a moment, ' +
    'or edit your question below and confirm — our team can still help if needed.';

const CLARIFY_NO_MCQ_HINT =
    'We could not generate follow-up questions this time. You can still edit your question and confirm.';

const RESOLUTION_AGENT_UNAVAILABLE_USER =
    'We could not generate an AI answer right now. Please try submitting again shortly, ' +
    'or choose "No, still need help" and our support team will follow up.';

const STATE = {
    INPUT: 'INPUT',
    CLARIFYING: 'CLARIFYING',
    CLARIFICATION: 'CLARIFICATION',
    LOADING: 'LOADING',
    RECOMMENDATION: 'RECOMMENDATION',
    RESOLVING: 'RESOLVING',
    RESOLVED: 'RESOLVED',
    CASE_CREATED: 'CASE_CREATED'
};

const POLL_INTERVAL_MS    = 2500;
const MAX_POLL_ATTEMPTS   = 36;
const MAX_CLARIFY_ATTEMPTS = 20; // 50 s max wait for clarification prompt
// Keep in sync with CaseResolutionController
const NO_ANSWER_MESSAGE =
    'Thank you for your question. We could not find a specific answer in our knowledge base at this time. ' +
    'Our support team will review your case and follow up with you shortly.';
const TIMEOUT_MESSAGE =
    'Thank you for your patience. We are still processing your question. ' +
    'Our support team has your case and will follow up with you shortly.';
const FALLBACK_MESSAGES = new Set([NO_ANSWER_MESSAGE, TIMEOUT_MESSAGE]);

const MIN_QUESTION_WORDS = 10;
const THIN_QUESTION_HINT =
    'For better results, include more detail \u2014 for example, the product version, ' +
    'error message, or what you were doing when the issue occurred.';

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const BASE_INPUT_CLASS = 'cra-input';
const TEXTAREA_CLASS = 'cra-input cra-textarea';

export default class CaseResolutionAssistant extends LightningElement {
    currentState = STATE.INPUT;

    firstName = '';
    lastName = '';
    email = '';
    question = '';
    product = '';

    firstNameError = '';
    lastNameError = '';
    emailError = '';
    questionError = '';
    productError = '';
    questionHint = '';

    productOptions = [];

    recommendation = '';
    recommendationIsFallback = false;
    caseId = null;
    caseNumber = '';
    errorMessage = '';

    pollAttempts = 0;
    pollTimeoutId = null;

    // Clarification
    clarifyAttempts = 0;
    clarifyTimeoutId = null;
    clarifiedQuestion = '';
    clarifications = [];
    clarifyWarningMessage = '';

    // Portal session (A4) + profile prefill (B1)
    isGuestSession = true;
    sessionDisplayLabel = 'Browsing as guest — log in for full AI features';
    profileFirstName = '';
    profileLastName = '';
    profileEmail = '';

    // Speech-to-text
    isListening = false;
    interimTranscript = '';
    micError = '';
    _speechRecognition = null;
    showMicHint = true;

    @wire(getProductOptions)
    wiredProducts({ data }) {
        if (data) {
            this.productOptions = data;
        }
    }

    @wire(getPortalUserContext)
    wiredPortalUser({ data }) {
        if (!data) {
            return;
        }
        this.isGuestSession = data.isGuest === 'true';
        if (this.isGuestSession) {
            this.sessionDisplayLabel =
                'Browsing as guest — log in for full AI features';
        } else {
            const name = (data.displayName || '').trim();
            this.sessionDisplayLabel = name
                ? `Logged in as ${name}`
                : 'Logged in';
            this.profileFirstName = data.firstName || '';
            this.profileLastName = data.lastName || '';
            this.profileEmail = data.email || '';
            if (this.currentState === STATE.INPUT && !this.firstName && !this.lastName && !this.email) {
                this._applyProfilePrefill();
            }
        }
    }

    _applyProfilePrefill() {
        this.firstName = this.profileFirstName;
        this.lastName = this.profileLastName;
        this.email = this.profileEmail;
    }

    _syncInputFormDom() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            // eslint-disable-next-line @lwc/lwc/no-template-children
            const firstEl = this.template.querySelector('#firstName');
            // eslint-disable-next-line @lwc/lwc/no-template-children
            const lastEl = this.template.querySelector('#lastName');
            // eslint-disable-next-line @lwc/lwc/no-template-children
            const emailEl = this.template.querySelector('#email');
            // eslint-disable-next-line @lwc/lwc/no-template-children
            const questionEl = this.template.querySelector('#question');
            // eslint-disable-next-line @lwc/lwc/no-template-children
            const productEl = this.template.querySelector('#product');
            if (firstEl) firstEl.value = this.firstName || '';
            if (lastEl) lastEl.value = this.lastName || '';
            if (emailEl) emailEl.value = this.email || '';
            if (questionEl) questionEl.value = this.question || '';
            if (productEl) productEl.value = this.product || '';
        }, 0);
    }

    connectedCallback() {
        this.applyHostChrome();
    }

    renderedCallback() {
        this.applyHostChrome();
        // LWC doesn't always push reactive property changes into a <textarea>'s
        // DOM value when the containing div transitions from display:none to
        // visible. Force-sync the clarified question imperatively after every
        // render to guarantee the textarea shows the correct text.
        if (this.currentState === STATE.CLARIFICATION && this.clarifiedQuestion) {
            const el = this.template.querySelector('textarea[data-id="clarifiedQuestion"]');
            if (el && el.value !== this.clarifiedQuestion) {
                el.value = this.clarifiedQuestion;
            }
        }
    }

    applyHostChrome() {
        this.style.display = 'block';
        this.style.width = '100%';
        this.style.minHeight = '100vh';
        this.style.backgroundColor = '#2c5282';
        this.style.boxSizing = 'border-box';
    }

    handleFirstNameChange(event) {
        this.firstName = event.target.value;
        if (this.firstNameError) {
            this.firstNameError = this.validateFirstName();
        }
    }
    handleLastNameChange(event) {
        this.lastName = event.target.value;
        if (this.lastNameError) {
            this.lastNameError = this.validateLastName();
        }
    }
    handleEmailChange(event) {
        this.email = event.target.value;
        if (this.emailError) {
            this.emailError = this.validateEmail();
        }
    }
    handleQuestionChange(event) {
        this.question = event.target.value;
        if (this.showMicHint) {
            this.showMicHint = false;
        }
        if (this.questionError) {
            this.questionError = this.validateQuestion();
        }
        if (this.questionHint && !this.isQuestionThin()) {
            this.questionHint = '';
        }
    }
    handleProductChange(event) {
        this.product = event.target.value;
        if (this.productError) {
            this.productError = this.validateProduct();
        }
    }

    handleProductBlur() {
        this.productError = this.validateProduct();
    }

    handleFirstNameBlur() {
        this.firstNameError = this.validateFirstName();
    }
    handleLastNameBlur() {
        this.lastNameError = this.validateLastName();
    }
    handleEmailBlur() {
        this.emailError = this.validateEmail();
    }
    handleQuestionBlur() {
        this.questionError = this.validateQuestion();
    }

    validateFirstName() {
        if (!(this.firstName || '').trim()) {
            return 'First name is required.';
        }
        return '';
    }
    validateLastName() {
        if (!(this.lastName || '').trim()) {
            return 'Last name is required.';
        }
        return '';
    }
    validateEmail() {
        const value = (this.email || '').trim();
        if (!value) {
            return 'Email is required.';
        }
        if (!EMAIL_REGEX.test(value)) {
            return 'Please enter a valid email address.';
        }
        return '';
    }
    validateQuestion() {
        if (!(this.question || '').trim()) {
            return 'Please describe what you need help with.';
        }
        return '';
    }

    validateProduct() {
        if (!(this.product || '').trim()) {
            return 'Please select a product.';
        }
        return '';
    }

    isQuestionThin() {
        const words = (this.question || '').trim().split(/\s+/).filter(w => w.length > 0);
        return words.length < MIN_QUESTION_WORDS;
    }

    validateAll() {
        this.firstNameError = this.validateFirstName();
        this.lastNameError = this.validateLastName();
        this.emailError = this.validateEmail();
        this.productError = this.validateProduct();
        this.questionError = this.validateQuestion();
        return !(
            this.firstNameError ||
            this.lastNameError ||
            this.emailError ||
            this.productError ||
            this.questionError
        );
    }

    get firstNameInputClass() {
        return this.firstNameError
            ? `${BASE_INPUT_CLASS} cra-input--error`
            : BASE_INPUT_CLASS;
    }
    get lastNameInputClass() {
        return this.lastNameError
            ? `${BASE_INPUT_CLASS} cra-input--error`
            : BASE_INPUT_CLASS;
    }
    get emailInputClass() {
        return this.emailError
            ? `${BASE_INPUT_CLASS} cra-input--error`
            : BASE_INPUT_CLASS;
    }
    get questionInputClass() {
        return this.questionError
            ? `${TEXTAREA_CLASS} cra-input--error`
            : TEXTAREA_CLASS;
    }
    get productInputClass() {
        return this.productError
            ? 'cra-input cra-select cra-input--error'
            : 'cra-input cra-select';
    }

    get inputClass() {
        return this.classFor(STATE.INPUT);
    }
    get clarifyingClass() {
        return this.classFor(STATE.CLARIFYING);
    }
    get clarificationClass() {
        return this.classFor(STATE.CLARIFICATION);
    }
    get hasClarifications() {
        return this.clarifications && this.clarifications.length > 0;
    }
    get loadingClass() {
        return this.classFor(STATE.LOADING);
    }
    get recommendationClass() {
        return this.classFor(STATE.RECOMMENDATION);
    }
    get recommendationBadge() {
        return this.recommendationIsFallback
            ? 'WE\'LL FOLLOW UP'
            : 'KNOWLEDGE ARTICLE FOUND';
    }
    get recommendationBadgeClass() {
        return this.recommendationIsFallback
            ? 'cra-badge cra-badge--neutral'
            : 'cra-badge';
    }
    get recommendationTitle() {
        return this.recommendationIsFallback ? 'Next Steps' : 'Recommended Solution';
    }
    get resolvingClass() {
        return this.classFor(STATE.RESOLVING);
    }
    get resolvedClass() {
        return this.classFor(STATE.RESOLVED);
    }
    get caseCreatedClass() {
        return this.classFor(STATE.CASE_CREATED);
    }

    classFor(targetState) {
        return this.currentState === targetState
            ? 'cra-state'
            : 'cra-state cra-state--hidden';
    }

    get errorClass() {
        return this.errorMessage
            ? 'cra-error'
            : 'cra-error cra-error--hidden';
    }

    get questionHintClass() {
        return this.questionHint
            ? 'cra-hint'
            : 'cra-hint cra-hint--hidden';
    }

    get sessionBannerClass() {
        return this.isGuestSession
            ? 'cra-session cra-session--guest'
            : 'cra-session cra-session--member';
    }

    get clarifyWarningClass() {
        return this.clarifyWarningMessage
            ? 'cra-warning'
            : 'cra-warning cra-warning--hidden';
    }

    async handleSubmit() {
        const isValid = this.validateAll();
        if (!isValid) {
            this.errorMessage = 'Please correct the highlighted fields before submitting.';
            return;
        }
        if (this.isQuestionThin()) {
            this.questionHint = THIN_QUESTION_HINT;
            return;
        }
        this.questionHint = '';
        this.errorMessage = '';
        this.currentState = STATE.CLARIFYING;

        try {
            const result = await submitForClarification({
                firstName: this.firstName,
                lastName: this.lastName,
                email: this.email,
                subject: this.question,
                product: this.product
            });
            this.caseId = result.caseId;
            this.caseNumber = result.caseNumber;
            this.clarifyAttempts = 0;
            this.scheduleNextClarifyPoll();
        } catch (error) {
            this.errorMessage =
                (error && error.body && error.body.message) ||
                'Sorry, something went wrong submitting your question. Please try again.';
            this.currentState = STATE.INPUT;
        }
    }

    scheduleNextClarifyPoll() {
        this.clarifyTimeoutId = setTimeout(() => this.pollClarifyOnce(), POLL_INTERVAL_MS);
    }

    async pollClarifyOnce() {
        this.clarifyAttempts += 1;
        try {
            const json = await getClarification({ caseId: this.caseId });
            if (json) {
                this._applyClarification(json);
                return;
            }
        } catch (e) {
            // Swallow transient errors and keep polling.
        }

        if (this.clarifyAttempts >= MAX_CLARIFY_ATTEMPTS) {
            this.clarifiedQuestion = this.question;
            this.clarifications = [];
            this.clarifyWarningMessage = CLARIFY_AGENT_UNAVAILABLE_USER;
            this.currentState = STATE.CLARIFICATION;
            return;
        }
        this.scheduleNextClarifyPoll();
    }

    _applyClarification(jsonString) {
        try {
            const data = JSON.parse(jsonString);
            this.clarifiedQuestion = data.cleanedQuestion || this.question;
            this.clarifications = (data.clarifications || []).map((c, i) => ({
                id: i,
                question: c.question,
                options: (c.options || []).map((opt, j) => ({
                    id: `${i}-${j}`,
                    text: opt,
                    selected: false
                })),
                showOther: false,
                otherText: ''
            }));
            if (data._error) {
                this.clarifyWarningMessage = CLARIFY_AGENT_UNAVAILABLE_USER;
            } else if (!this.clarifications.length) {
                this.clarifyWarningMessage = CLARIFY_NO_MCQ_HINT;
            } else {
                this.clarifyWarningMessage = '';
            }
        } catch (e) {
            this.clarifiedQuestion = this.question;
            this.clarifications = [];
            this.clarifyWarningMessage = CLARIFY_AGENT_UNAVAILABLE_USER;
        }
        this.currentState = STATE.CLARIFICATION;

        // Belt-and-suspenders: LWC doesn't reliably push value changes into a
        // hidden-then-shown <textarea> DOM node. renderedCallback also covers
        // this, but a post-microtask sync guarantees the very first paint.
        const captured = this.clarifiedQuestion;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const el = this.template.querySelector('textarea[data-id="clarifiedQuestion"]');
            if (el && el.value !== captured) {
                el.value = captured;
            }
        }, 0);
    }

    handleClarifiedQuestionChange(event) {
        this.clarifiedQuestion = event.target.value;
    }

    handleOptionChange(event) {
        const clarId = parseInt(event.target.dataset.clarId, 10);
        const optId  = event.target.dataset.optId;
        const checked = event.target.checked;
        this.clarifications = this.clarifications.map(clar => {
            if (clar.id !== clarId) return clar;
            return {
                ...clar,
                options: clar.options.map(opt =>
                    opt.id === optId ? { ...opt, selected: checked } : opt
                )
            };
        });
    }

    handleOtherToggle(event) {
        const clarId  = parseInt(event.target.dataset.clarId, 10);
        const checked = event.target.checked;
        this.clarifications = this.clarifications.map(clar =>
            clar.id !== clarId ? clar : { ...clar, showOther: checked, otherText: checked ? clar.otherText : '' }
        );
    }

    handleOtherTextChange(event) {
        const clarId = parseInt(event.target.dataset.clarId, 10);
        this.clarifications = this.clarifications.map(clar =>
            clar.id !== clarId ? clar : { ...clar, otherText: event.target.value }
        );
    }

    handleBackToInput() {
        if (this.clarifyTimeoutId) {
            clearTimeout(this.clarifyTimeoutId);
            this.clarifyTimeoutId = null;
        }
        this.currentState = STATE.INPUT;
    }

    async handleConfirm() {
        const base = (this.clarifiedQuestion || this.question).trim();

        // Build a rich MCQ context block for the AI agent so it knows what the user answered.
        // Each line is "Question → answer(s)" for maximum clarity.
        const mcqLines = [];
        this.clarifications.forEach(clar => {
            const selected = clar.options
                .filter(opt => opt.selected)
                .map(opt => opt.text);
            if (clar.showOther && clar.otherText.trim()) {
                selected.push(clar.otherText.trim());
            }
            if (selected.length > 0) {
                mcqLines.push(`- ${clar.question}: ${selected.join(', ')}`);
            }
        });

        // Full message sent to the AI agent — no length limit.
        // MCQ answers are always included as a separate context block.
        const agentMessage = mcqLines.length > 0
            ? `${base}\n\nAdditional context provided by the user:\n${mcqLines.join('\n')}`
            : base;

        // Case.Subject is limited to 255 chars — truncate the base question only,
        // MCQ context is NOT appended here (it travels separately via agentMessage).
        const subjectQuestion = base.length <= 255 ? base : base.substring(0, 255);

        this.errorMessage = '';
        this.currentState = STATE.LOADING;

        try {
            await confirmQuestion({
                caseId: this.caseId,
                cleanedQuestion: subjectQuestion,
                agentMessage: agentMessage
            });
            this.pollAttempts = 0;
            this.scheduleNextPoll();
        } catch (error) {
            this.errorMessage =
                (error && error.body && error.body.message) ||
                'Sorry, something went wrong. Please try again.';
            this.currentState = STATE.CLARIFICATION;
        }
    }

    scheduleNextPoll() {
        this.pollTimeoutId = setTimeout(() => this.pollOnce(), POLL_INTERVAL_MS);
    }

    _isAgentSystemError(text) {
        const t = (text || '').trim();
        return t.startsWith('[AGENT ERROR]') || t.startsWith('[EXCEPTION]')
            || t.includes('invokeAgent returned');
    }

    async pollOnce() {
        this.pollAttempts += 1;
        try {
            const description = await getRecommendation({ caseId: this.caseId });
            if (description) {
                if (this._isAgentSystemError(description)) {
                    this.recommendation = RESOLUTION_AGENT_UNAVAILABLE_USER;
                    this.recommendationIsFallback = true;
                } else {
                    this.recommendation = description;
                    this.recommendationIsFallback = FALLBACK_MESSAGES.has(description);
                }
                this.currentState = STATE.RECOMMENDATION;
                return;
            }
        } catch (e) {
            // Silently swallow transient errors and keep polling.
        }

        if (this.pollAttempts >= MAX_POLL_ATTEMPTS) {
            this.recommendation = TIMEOUT_MESSAGE;
            this.recommendationIsFallback = true;
            this.currentState = STATE.RECOMMENDATION;
            return;
        }
        this.scheduleNextPoll();
    }

    async handleYes() {
        this.currentState = STATE.RESOLVING;
        try {
            await resolveCase({ caseId: this.caseId });
            this.currentState = STATE.RESOLVED;
        } catch (error) {
            this.errorMessage =
                (error && error.body && error.body.message) ||
                'Sorry, we could not close the case. Please try again.';
            this.currentState = STATE.RECOMMENDATION;
        }
    }

    handleNo() {
        this.currentState = STATE.CASE_CREATED;
    }

    handleReset() {
        this.firstName = this.profileFirstName || '';
        this.lastName = this.profileLastName || '';
        this.email = this.profileEmail || '';
        this.question = '';
        this.product = '';
        this.firstNameError = '';
        this.lastNameError = '';
        this.emailError = '';
        this.questionError = '';
        this.productError = '';
        this.questionHint = '';
        this.recommendation = '';
        this.recommendationIsFallback = false;
        this.caseId = null;
        this.caseNumber = '';
        this.errorMessage = '';
        this.pollAttempts = 0;
        if (this.pollTimeoutId) {
            clearTimeout(this.pollTimeoutId);
            this.pollTimeoutId = null;
        }
        this._stopListening();
        this.micError = '';
        this.showMicHint = true;
        this.clarifyAttempts = 0;
        if (this.clarifyTimeoutId) {
            clearTimeout(this.clarifyTimeoutId);
            this.clarifyTimeoutId = null;
        }
        this.clarifiedQuestion = '';
        this.clarifications = [];
        this.clarifyWarningMessage = '';
        this.currentState = STATE.INPUT;
        this._syncInputFormDom();
    }

    get micButtonClass() {
        return this.isListening
            ? 'cra-mic-btn cra-mic-btn--listening'
            : 'cra-mic-btn';
    }

    get micAriaLabel() {
        return this.isListening ? 'Stop recording' : 'Start voice input';
    }

    handleMicToggle() {
        this.showMicHint = false;
        if (this.isListening) {
            this._stopListening();
        } else {
            this._startListening();
        }
    }

    _startListening() {
        // eslint-disable-next-line no-undef
        const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
        if (!SpeechRecognition) {
            this.micError =
                'Voice input is not supported in this browser. Please use Google Chrome for this feature.';
            return;
        }

        this.micError = '';
        this._speechRecognition = new SpeechRecognition();
        this._speechRecognition.continuous = true;
        this._speechRecognition.interimResults = true;
        this._speechRecognition.lang = 'en-US';

        this._speechRecognition.onstart = () => {
            this.isListening = true;
            this.interimTranscript = '';
        };

        this._speechRecognition.onresult = (event) => {
            let interim = '';
            for (let i = event.resultIndex; i < event.results.length; i++) {
                const transcript = event.results[i][0].transcript;
                if (event.results[i].isFinal) {
                    const spacer = this.question.trim() ? ' ' : '';
                    this.question = (this.question.trim() + spacer + transcript.trim()).trim();
                    if (this.questionError) this.questionError = '';
                    if (this.questionHint && !this.isQuestionThin()) this.questionHint = '';
                } else {
                    interim += transcript;
                }
            }
            this.interimTranscript = interim;
            // Directly sync to textarea DOM — LWC reactive props don't always
            // update native textarea value in real-time from browser callbacks.
            // LWC scopes element IDs, so select by tag name only.
            // Show committed text + live interim words together.
            const textarea = this.template.querySelector('textarea');
            if (textarea) {
                const spacer = this.question.trim() && interim ? ' ' : '';
                textarea.value = this.question + spacer + interim;
            }
        };

        this._speechRecognition.onerror = (event) => {
            this.isListening = false;
            this.interimTranscript = '';
            if (event.error === 'not-allowed' || event.error === 'permission-denied') {
                this.micError =
                    'Microphone access denied. Please allow microphone permission in your browser and try again.';
            }
        };

        this._speechRecognition.onend = () => {
            this.isListening = false;
            this.interimTranscript = '';
            // Ensure textarea shows only the committed text after recording ends
            const textarea = this.template.querySelector('textarea');
            if (textarea) {
                textarea.value = this.question;
            }
        };

        try {
            this._speechRecognition.start();
        } catch (e) {
            this.isListening = false;
        }
    }

    _stopListening() {
        if (this._speechRecognition) {
            this._speechRecognition.stop();
            this._speechRecognition = null;
        }
        this.isListening = false;
        this.interimTranscript = '';
    }

    disconnectedCallback() {
        if (this.pollTimeoutId) {
            clearTimeout(this.pollTimeoutId);
            this.pollTimeoutId = null;
        }
        if (this.clarifyTimeoutId) {
            clearTimeout(this.clarifyTimeoutId);
            this.clarifyTimeoutId = null;
        }
        this._stopListening();
    }
}
