import { LightningElement, wire } from 'lwc';
import createSupportCase from '@salesforce/apex/CaseResolutionController.createSupportCase';
import getRecommendation from '@salesforce/apex/CaseResolutionController.getRecommendation';
import resolveCase from '@salesforce/apex/CaseResolutionController.resolveCase';
import getProductOptions from '@salesforce/apex/CaseResolutionController.getProductOptions';

const STATE = {
    INPUT: 'INPUT',
    LOADING: 'LOADING',
    RECOMMENDATION: 'RECOMMENDATION',
    RESOLVING: 'RESOLVING',
    RESOLVED: 'RESOLVED',
    CASE_CREATED: 'CASE_CREATED'
};

const POLL_INTERVAL_MS = 2500;
const MAX_POLL_ATTEMPTS = 36;
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
    questionHint = '';

    productOptions = [];

    recommendation = '';
    recommendationIsFallback = false;
    caseId = null;
    caseNumber = '';
    errorMessage = '';

    pollAttempts = 0;
    pollTimeoutId = null;

    // Speech-to-text
    isListening = false;
    interimTranscript = '';
    micError = '';
    _speechRecognition = null;

    @wire(getProductOptions)
    wiredProducts({ data }) {
        if (data) {
            this.productOptions = data;
        }
    }

    connectedCallback() {
        this.applyHostChrome();
    }

    renderedCallback() {
        this.applyHostChrome();
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
        if (this.questionError) {
            this.questionError = this.validateQuestion();
        }
        if (this.questionHint && !this.isQuestionThin()) {
            this.questionHint = '';
        }
    }
    handleProductChange(event) {
        this.product = event.target.value;
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

    isQuestionThin() {
        const words = (this.question || '').trim().split(/\s+/).filter(w => w.length > 0);
        return words.length < MIN_QUESTION_WORDS;
    }

    validateAll() {
        this.firstNameError = this.validateFirstName();
        this.lastNameError = this.validateLastName();
        this.emailError = this.validateEmail();
        this.questionError = this.validateQuestion();
        return !(
            this.firstNameError ||
            this.lastNameError ||
            this.emailError ||
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

    get inputClass() {
        return this.classFor(STATE.INPUT);
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

    async handleFindSolution() {
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
        this.currentState = STATE.LOADING;

        try {
            const result = await createSupportCase({
                firstName: this.firstName,
                lastName: this.lastName,
                email: this.email,
                subject: this.question,
                product: this.product
            });
            this.caseId = result.caseId;
            this.caseNumber = result.caseNumber;
            this.pollAttempts = 0;
            this.scheduleNextPoll();
        } catch (error) {
            this.errorMessage =
                (error && error.body && error.body.message) ||
                'Sorry, something went wrong submitting your question. Please try again.';
            this.currentState = STATE.INPUT;
        }
    }

    scheduleNextPoll() {
        this.pollTimeoutId = setTimeout(() => this.pollOnce(), POLL_INTERVAL_MS);
    }

    async pollOnce() {
        this.pollAttempts += 1;
        try {
            const description = await getRecommendation({ caseId: this.caseId });
            if (description) {
                this.recommendation = description;
                this.recommendationIsFallback = FALLBACK_MESSAGES.has(description);
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
        this.firstName = '';
        this.lastName = '';
        this.email = '';
        this.question = '';
        this.product = '';
        this.firstNameError = '';
        this.lastNameError = '';
        this.emailError = '';
        this.questionError = '';
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
        this.currentState = STATE.INPUT;

        // Force-clear DOM input/textarea/select values because LWC does not
        // always re-render native form elements when their bound property resets.
        // eslint-disable-next-line @lwc/lwc/no-template-children
        this.template.querySelectorAll('input, textarea, select').forEach(el => {
            el.value = '';
        });
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
        this._stopListening();
    }
}
