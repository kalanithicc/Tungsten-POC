import { LightningElement, api, wire } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecordNotifyChange, getRecord } from 'lightning/uiRecordApi';
import STATUS_FIELD from '@salesforce/schema/Case.Status';
import saveResolution from '@salesforce/apex/CaseResolveActionController.saveResolution';

const FIELDS = [STATUS_FIELD];

export default class CaseResolveAction extends LightningElement {
    @api recordId;

    resolutionText = '';
    errorMessage = '';
    isSaving = false;
    updateKnowledgeBase = false;
    _status = '';

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredCase({ data }) {
        if (data) {
            this._status = data.fields.Status.value;
        }
    }

    get isCaseClosed() {
        return this._status === 'Closed';
    }

    renderedCallback() {
        this.adjustTextareaHeight();
    }

    handleResolutionChange(event) {
        this.resolutionText = event.target.value;
        if (this.errorMessage) {
            this.errorMessage = '';
        }
        this.adjustTextareaHeight();
    }

    handleUpdateKbChange(event) {
        this.updateKnowledgeBase = event.target.checked;
    }

    adjustTextareaHeight() {
        const textarea = this.template.querySelector(
            '[data-id="resolution-textarea"]'
        );
        if (!textarea) {
            return;
        }

        textarea.style.height = 'auto';
        const maxHeightPx = 256;
        const nextHeight = Math.min(textarea.scrollHeight, maxHeightPx);
        textarea.style.height = `${nextHeight}px`;
        textarea.style.overflowY =
            textarea.scrollHeight > maxHeightPx ? 'auto' : 'hidden';
    }

    handleCancel() {
        this.closeModal();
    }

    async handleSave() {
        const trimmed = (this.resolutionText || '').trim();
        if (!trimmed) {
            this.errorMessage = 'Please enter a resolution before saving.';
            return;
        }

        this.errorMessage = '';
        this.isSaving = true;

        try {
            const result = await saveResolution({
                caseId: this.recordId,
                resolutionText: trimmed,
                createKb: this.updateKnowledgeBase
            });

            const kbQueued = this.updateKnowledgeBase && result && result.articleQueued;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: kbQueued ? 'Case resolved — KB article queued' : 'Case resolved',
                    message: kbQueued
                        ? 'Resolution saved. Check "KB Article Link" for a new article or "KB Update Scope" if an existing article was found (ready in ~1 min).'
                        : 'Resolution saved and case closed.',
                    variant: 'success',
                    mode: 'sticky'
                })
            );

            getRecordNotifyChange([{ recordId: this.recordId }]);
            // Delay close so the toast event propagates to the record page
            // before the quick-action screen is torn down.
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => this.closeModal(), 400);
        } catch (error) {
            this.isSaving = false;
            this.errorMessage =
                (error && error.body && error.body.message) ||
                'Sorry, we could not save the resolution. Please try again.';
        }
    }

    closeModal() {
        this.dispatchEvent(new CloseActionScreenEvent());
        this.dispatchEvent(new CustomEvent('close'));
    }
}
