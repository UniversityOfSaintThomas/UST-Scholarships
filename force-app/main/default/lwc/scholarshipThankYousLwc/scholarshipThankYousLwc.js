/**
 * scholarshipThankYousLwc.js
 *
 * Dual-mode LWC for the Scholarship Thank You feature.
 *
 * PORTAL MODE  — contactId @api prop populated (passed from VF Lightning Out)
 *   Shows a list of all TY requirements for the student, lets them write /
 *   save drafts / submit letters inline.
 *
 * RECORD PAGE MODE — recordId @api prop populated (Scholarship_Applicant__c)
 *   Shows a single TY item in read-only detail view for DR/admin staff.
 *
 * NOTE: ShowToastEvent does NOT fire in Lightning Out (VF context).
 * All user feedback uses the inline feedbackMessage banner instead.
 *
 * Created: 2026-03-26
 */
import { LightningElement, api, track } from 'lwc';
import getThankYouItems     from '@salesforce/apex/ScholarshipThankYouController.getThankYouItems';
import getThankYouItem      from '@salesforce/apex/ScholarshipThankYouController.getThankYouItem';
import saveThankYouDraft    from '@salesforce/apex/ScholarshipThankYouController.saveThankYouDraft';
import submitThankYouLetter from '@salesforce/apex/ScholarshipThankYouController.submitThankYouLetter';
import getPreviousLetters   from '@salesforce/apex/ScholarshipThankYouController.getPreviousLetters';

const MIN_LENGTH        = 100;
const STATUS_CLASS_MAP  = {
    'Not Started': 'slds-badge slds-badge_lightest ty-badge-not-started',
    'In Progress':  'slds-badge ty-badge-in-progress',
    'Submitted':    'slds-badge ty-badge-submitted',
    'Complete':     'slds-badge ty-badge-complete'
};
const EDITABLE_STATUSES = new Set(['Not Started', 'In Progress']);
const ACCEPTED_FORMATS  = ['.jpg', '.jpeg', '.png', '.gif', '.pdf'];

export default class ScholarshipThankYousLwc extends LightningElement {

    // ─── Public API Props ────────────────────────────────────────────────────
    @api recordId;    // Scholarship_Applicant__c Id — record page mode
    @api contactId;   // Contact Id — portal mode

    // ─── Tracked State ───────────────────────────────────────────────────────
    @track thankYouItems  = [];
    @track singleItem     = null;
    @track isLoading      = true;
    @track feedbackMessage = { visible: false, type: 'success', text: '' };

    // Previous-letter lookup cache: Map<applicantId, PreviousLetterOption[]>
    _prevLetterCache = {};

    // ─── Lifecycle ───────────────────────────────────────────────────────────

    connectedCallback() {
        if (this.contactId) {
            this._loadList();
        } else if (this.recordId) {
            this._loadSingle();
        } else {
            this.isLoading = false;
        }
    }

    // ─── Mode Getters ────────────────────────────────────────────────────────

    get isPortalMode()  { return !!this.contactId; }
    get isRecordMode()  { return !!this.recordId && !this.contactId; }
    get hasItems()      { return this.thankYouItems && this.thankYouItems.length > 0; }
    get acceptedFormats() { return ACCEPTED_FORMATS; }

    // ─── Feedback Banner ─────────────────────────────────────────────────────

    get feedbackClass() {
        const base = 'ty-feedback-banner slds-notify slds-notify_toast slds-m-bottom_small ';
        return base + (this.feedbackMessage.type === 'error'
            ? 'slds-theme_error'
            : 'slds-theme_success');
    }

    get feedbackIconName() {
        return this.feedbackMessage.type === 'error'
            ? 'utility:error'
            : 'utility:success';
    }

    _showFeedback(type, text) {
        this.feedbackMessage = { visible: true, type, text };
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.feedbackMessage = { ...this.feedbackMessage, visible: false };
        }, 5000);
    }

    // ─── Data Loading ────────────────────────────────────────────────────────

    _loadList() {
        this.isLoading = true;
        getThankYouItems({ contactId: this.contactId })
            .then(items => {
                this.thankYouItems = items.map(i => this._enrichItem(i));
            })
            .catch(err => {
                this._showFeedback('error', this._extractError(err));
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    _loadSingle() {
        this.isLoading = true;
        getThankYouItem({ applicantId: this.recordId })
            .then(item => {
                this.singleItem = this._enrichSingleItem(item);
            })
            .catch(err => {
                this._showFeedback('error', this._extractError(err));
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // ─── Item Enrichment ─────────────────────────────────────────────────────

    /**
     * Takes a raw ThankYouItem from Apex and adds UI-only computed properties
     * needed by the template (statusClass, actionLabel, IDs for form elements…).
     */
    _enrichItem(raw) {
        const status     = raw.thankYouStatus || 'Not Started';
        const isEditable = EDITABLE_STATUSES.has(status);
        const isReadOnly = !isEditable;
        return {
            ...raw,
            thankYouStatus:    status,
            statusClass:       STATUS_CLASS_MAP[status] || 'slds-badge',
            isEditable,
            isReadOnly,
            editorOpen:        false,
            showPreview:       false,
            showPhotoRights:   raw.photoRightsAccepted === true,
            draftText:         raw.thankYouLetter || '',
            previousLetters:   [],
            hasPreviousLetters: false,
            actionLabel:       this._actionLabel(status),
            previewLabel:      'Preview',
            showExample:       status === 'Not Started',
            charCountLabel:    this._charCountLabel(raw.thankYouLetter),
            textareaId:        `textarea-${raw.applicantId}`,
            previousSelectId:  `prev-${raw.applicantId}`,
            photoCheckboxId:   `photo-${raw.applicantId}`,
            formattedSubmittedDate: this._formatDate(raw.submittedDate),
            photoRightsLabel:  raw.photoRightsAccepted ? 'Accepted' : 'Not accepted'
        };
    }

    _enrichSingleItem(raw) {
        return {
            ...this._enrichItem(raw),
            photoRightsLabel: raw.photoRightsAccepted ? 'Accepted' : 'Not accepted'
        };
    }

    _updateSingleItem(changes) {
        this.singleItem = { ...this.singleItem, ...changes };
    }

    get recordToggleLabel() {
        if (!this.singleItem) return 'Edit';
        if (this.singleItem.editorOpen) return 'Close ↑';
        return this.singleItem.actionLabel || 'Edit';
    }

    _actionLabel(status) {
        if (status === 'Not Started')  return 'Start →';
        if (status === 'In Progress')  return 'Continue →';
        return 'View →';
    }

    _charCountLabel(text) {
        const len = (text || '').length;
        if (len === 0) return 'Minimum 100 characters required.';
        if (len < MIN_LENGTH) return `${len} / ${MIN_LENGTH} characters minimum.`;
        return `${len} characters ✓`;
    }

    _formatDate(dt) {
        if (!dt) return '—';
        try {
            return new Date(dt).toLocaleDateString('en-US', {
                year: 'numeric', month: 'short', day: 'numeric'
            });
        } catch (_e) {
            return dt;
        }
    }

    _extractError(err) {
        if (err && err.body && err.body.message) return err.body.message;
        if (err && err.message) return err.message;
        return 'An unexpected error occurred. Please try again.';
    }

    // ─── Helper: immutable update of one item in the list ───────────────────

    _updateItem(applicantId, changes) {
        this.thankYouItems = this.thankYouItems.map(i =>
            i.applicantId === applicantId ? { ...i, ...changes } : i
        );
    }

    _findItem(applicantId) {
        return this.thankYouItems.find(i => i.applicantId === applicantId);
    }

    // ─── Event Handlers ──────────────────────────────────────────────────────

    handleToggleEditor(event) {
        const id   = event.currentTarget.dataset.id;
        const item = this._findItem(id);
        if (!item) return;

        const opening = !item.editorOpen;

        // Close all others, open this one
        this.thankYouItems = this.thankYouItems.map(i => ({
            ...i,
            editorOpen: i.applicantId === id ? opening : false
        }));

        // Lazy-load previous letters when expanding
        if (opening && !this._prevLetterCache[id]) {
            getPreviousLetters({ contactId: this.contactId, excludeApplicantId: id })
                .then(prev => {
                    this._prevLetterCache[id] = (prev || []).map(p => ({
                        ...p,
                        formattedDate: this._formatDate(p.submittedDate)
                    }));
                    this._updateItem(id, {
                        previousLetters:    this._prevLetterCache[id],
                        hasPreviousLetters: this._prevLetterCache[id].length > 0
                    });
                })
                .catch(() => {
                    // Non-fatal — previous letters are a convenience feature
                });
        } else if (opening && this._prevLetterCache[id]) {
            this._updateItem(id, {
                previousLetters:    this._prevLetterCache[id],
                hasPreviousLetters: this._prevLetterCache[id].length > 0
            });
        }
    }

    handlePreviousLetterSelect(event) {
        const id         = event.currentTarget.dataset.id;
        const selectedId = event.target.value;
        if (!selectedId) return;

        const cached = (this._prevLetterCache[id] || []).find(p => p.applicantId === selectedId);
        if (cached) {
            this._updateItem(id, {
                draftText:     cached.letterText,
                charCountLabel: this._charCountLabel(cached.letterText)
            });
            // Update the real textarea value
            const textarea = this.template.querySelector(`textarea[data-id="${id}"]`);
            if (textarea) textarea.value = cached.letterText;
        }
    }

    handleLetterChange(event) {
        const id   = event.currentTarget.dataset.id;
        const text = event.target.value;
        this._updateItem(id, {
            draftText:      text,
            charCountLabel: this._charCountLabel(text)
        });
    }

    handleTogglePreview(event) {
        const id   = event.currentTarget.dataset.id;
        const item = this._findItem(id);
        if (!item) return;
        const nowShowing = !item.showPreview;
        this._updateItem(id, {
            showPreview:  nowShowing,
            previewLabel: nowShowing ? 'Hide Preview' : 'Preview'
        });
    }

    handleSaveDraft(event) {
        const id   = event.currentTarget.dataset.id;
        const item = this._findItem(id);
        if (!item) return;

        const textarea = this.template.querySelector(`textarea[data-id="${id}"]`);
        const text     = textarea ? textarea.value : item.draftText;

        this.isLoading = true;
        saveThankYouDraft({ applicantId: id, letterText: text })
            .then(updated => {
                this._updateItem(id, {
                    ...this._enrichItem(updated),
                    editorOpen:  true,
                    showPreview: item.showPreview,
                    previousLetters: item.previousLetters,
                    hasPreviousLetters: item.hasPreviousLetters
                });
                this._showFeedback('success', 'Draft saved successfully.');
            })
            .catch(err => {
                this._showFeedback('error', this._extractError(err));
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleSubmit(event) {
        const id   = event.currentTarget.dataset.id;
        const item = this._findItem(id);
        if (!item) return;

        const textarea = this.template.querySelector(`textarea[data-id="${id}"]`);
        const text     = textarea ? textarea.value : item.draftText;

        // Client-side length guard
        if (!text || text.trim().length < MIN_LENGTH) {
            this._showFeedback(
                'error',
                `Your letter must be at least ${MIN_LENGTH} characters. Current length: ${(text || '').length}.`
            );
            return;
        }

        this.isLoading = true;
        submitThankYouLetter({
            applicantId:         id,
            letterText:          text,
            photoRightsAccepted: item.photoRightsAccepted || false
        })
            .then(updated => {
                this._updateItem(id, {
                    ...this._enrichItem(updated),
                    editorOpen: true  // keep open so student can see confirmation
                });
                this._showFeedback('success', 'Thank-you letter submitted! Thank you for taking the time to write to your scholarship donor.');
            })
            .catch(err => {
                this._showFeedback('error', this._extractError(err));
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handlePhotoUpload(event) {
        const id = event.currentTarget.dataset.id;
        if (event.detail.files && event.detail.files.length > 0) {
            this._updateItem(id, { showPhotoRights: true });
            this._showFeedback('success', 'Photo uploaded successfully.');
        }
    }

    handlePhotoRightsChange(event) {
        const id      = event.currentTarget.dataset.id;
        const checked = event.target.checked;
        this._updateItem(id, { photoRightsAccepted: checked });
    }

    // ─── Record Page Mode Handlers ───────────────────────────────────────────

    handleRecordToggleEditor() {
        const opening = !this.singleItem.editorOpen;
        this._updateSingleItem({ editorOpen: opening });

        // Lazy-load previous letters when expanding
        if (opening && this.singleItem.contactId && !this._prevLetterCache['single']) {
            getPreviousLetters({
                contactId: this.singleItem.contactId,
                excludeApplicantId: this.recordId
            })
                .then(prev => {
                    this._prevLetterCache['single'] = (prev || []).map(p => ({
                        ...p,
                        formattedDate: this._formatDate(p.submittedDate)
                    }));
                    this._updateSingleItem({
                        previousLetters:    this._prevLetterCache['single'],
                        hasPreviousLetters: this._prevLetterCache['single'].length > 0
                    });
                })
                .catch(() => {
                    // Non-fatal
                });
        } else if (opening && this._prevLetterCache['single']) {
            this._updateSingleItem({
                previousLetters:    this._prevLetterCache['single'],
                hasPreviousLetters: this._prevLetterCache['single'].length > 0
            });
        }
    }

    handleRecordLetterChange(event) {
        const text = event.target.value;
        this._updateSingleItem({
            draftText:      text,
            charCountLabel: this._charCountLabel(text)
        });
    }

    handleRecordTogglePreview() {
        const nowShowing = !this.singleItem.showPreview;
        this._updateSingleItem({
            showPreview:  nowShowing,
            previewLabel: nowShowing ? 'Hide Preview' : 'Preview'
        });
    }

    handleRecordPreviousLetterSelect(event) {
        const selectedId = event.target.value;
        if (!selectedId) return;
        const cached = (this._prevLetterCache['single'] || []).find(p => p.applicantId === selectedId);
        if (cached) {
            this._updateSingleItem({
                draftText:      cached.letterText,
                charCountLabel: this._charCountLabel(cached.letterText)
            });
            const textarea = this.template.querySelector('.ty-record-textarea');
            if (textarea) textarea.value = cached.letterText;
        }
    }

    handleRecordSaveDraft() {
        const textarea = this.template.querySelector('.ty-record-textarea');
        const text     = textarea ? textarea.value : this.singleItem.draftText;

        this.isLoading = true;
        saveThankYouDraft({ applicantId: this.recordId, letterText: text })
            .then(updated => {
                this._updateSingleItem({
                    ...this._enrichSingleItem(updated),
                    editorOpen:        true,
                    showPreview:       this.singleItem.showPreview,
                    previousLetters:   this.singleItem.previousLetters,
                    hasPreviousLetters: this.singleItem.hasPreviousLetters
                });
                this._showFeedback('success', 'Draft saved successfully.');
            })
            .catch(err => {
                this._showFeedback('error', this._extractError(err));
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleRecordSubmit() {
        const textarea = this.template.querySelector('.ty-record-textarea');
        const text     = textarea ? textarea.value : this.singleItem.draftText;

        if (!text || text.trim().length < MIN_LENGTH) {
            this._showFeedback(
                'error',
                `Your letter must be at least ${MIN_LENGTH} characters. Current length: ${(text || '').length}.`
            );
            return;
        }

        this.isLoading = true;
        submitThankYouLetter({
            applicantId:         this.recordId,
            letterText:          text,
            photoRightsAccepted: this.singleItem.photoRightsAccepted || false
        })
            .then(updated => {
                this._updateSingleItem({
                    ...this._enrichSingleItem(updated),
                    editorOpen: true
                });
                this._showFeedback('success', 'Thank-you letter submitted! Thank you for taking the time to write to your scholarship donor.');
            })
            .catch(err => {
                this._showFeedback('error', this._extractError(err));
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleRecordPhotoUpload(event) {
        if (event.detail.files && event.detail.files.length > 0) {
            this._updateSingleItem({ showPhotoRights: true });
            this._showFeedback('success', 'Photo uploaded successfully.');
        }
    }

    handleRecordPhotoRightsChange(event) {
        this._updateSingleItem({ photoRightsAccepted: event.target.checked });
    }
}