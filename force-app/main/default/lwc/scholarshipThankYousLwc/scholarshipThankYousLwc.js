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
 * DEEP LINK / CROSS-WIDGET NAVIGATION (portal mode only):
 *   On load, a `?applicantId=<id>` query param opens that item's editor and
 *   scrolls it into view. The same happens live if a sibling widget (e.g.
 *   scholarshipThankYouListLwc used as secondary nav on this same page)
 *   dispatches a `window` CustomEvent named THANK_YOU_SELECT_EVENT with
 *   `detail.applicantId` — this is how two independently Lightning-Out-mounted
 *   components talk to each other, since neither is a DOM ancestor of the other.
 *
 * Created: 2026-03-26
 */
import { LightningElement, api, track } from 'lwc';
import getThankYouItems     from '@salesforce/apex/ScholarshipThankYouController.getThankYouItems';
import getThankYouItem      from '@salesforce/apex/ScholarshipThankYouController.getThankYouItem';
import saveThankYouDraft    from '@salesforce/apex/ScholarshipThankYouController.saveThankYouDraft';
import submitThankYouLetter from '@salesforce/apex/ScholarshipThankYouController.submitThankYouLetter';
import getPreviousLetters   from '@salesforce/apex/ScholarshipThankYouController.getPreviousLetters';
import uploadThankYouPhoto  from '@salesforce/apex/ScholarshipThankYouController.uploadThankYouPhoto';

const MIN_LENGTH        = 100;
const THANK_YOU_SELECT_EVENT = 'ustty_selectapplicant';
const STATUS_CLASS_MAP  = {
    'Not Started': 'slds-badge slds-badge_lightest ty-badge-not-started',
    'In Progress':  'slds-badge ty-badge-in-progress',
    'Submitted':    'slds-badge ty-badge-submitted',
    'Complete':     'slds-badge ty-badge-complete'
};
const EDITABLE_STATUSES = new Set(['Not Started', 'In Progress']);
const ACCEPTED_FORMATS  = ['.jpg', '.jpeg', '.png', '.gif', '.pdf'];
const DEFAULT_EXAMPLE_HTML = '<em>"Dear [Donor Name], I am writing to express my sincere gratitude for your generous scholarship support. '
    + 'Your gift has made it possible for me to pursue my education at the University of St. Thomas..."</em>';

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
            window.addEventListener(THANK_YOU_SELECT_EVENT, this._handleExternalSelect);
        } else if (this.recordId) {
            this._loadSingle();
        } else {
            this.isLoading = false;
        }
    }

    disconnectedCallback() {
        window.removeEventListener(THANK_YOU_SELECT_EVENT, this._handleExternalSelect);
    }

    // Bound as a class field so the same function reference can be removed on teardown.
    _handleExternalSelect = (event) => {
        this._openApplicantFromId(event && event.detail && event.detail.applicantId);
    };

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
                const deepLinkId = new URLSearchParams(window.location.search).get('applicantId');
                if (deepLinkId) this._openApplicantFromId(deepLinkId);
            })
            .catch(err => {
                this._showFeedback('error', this._extractError(err));
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // Opens one item's editor (closing any other open one) and scrolls its card into view.
    // Used for the ?applicantId= deep link and for cross-widget selection events.
    _openApplicantFromId(id) {
        if (!id || !this._findItem(id)) return;
        this._setEditorOpen(id, true);
        Promise.resolve().then(() => {
            const card = this.template.querySelector(`[data-card-id="${id}"]`);
            if (card && card.scrollIntoView) card.scrollIntoView({ behavior: 'smooth', block: 'start' });
        });
    }

    // Opens (or closes) one item's editor; opening always closes all others.
    // Lazy-loads previous letters for the item being opened.
    _setEditorOpen(id, opening) {
        this.thankYouItems = this.thankYouItems.map(i => {
            const editorOpen = i.applicantId === id ? opening : false;
            return { ...i, editorOpen, cardClass: this._cardClass(editorOpen) };
        });
        if (opening) this._loadPreviousLettersFor(id);
    }

    // Purple-outlines the card whose editor is currently open; others keep the default gray.
    _cardClass(editorOpen) {
        const base = 'ty-card slds-box slds-m-bottom_small';
        return editorOpen ? `${base} ty-card_active` : base;
    }

    _loadPreviousLettersFor(id) {
        if (this._prevLetterCache[id]) {
            this._updateItem(id, {
                previousLetters:    this._prevLetterCache[id],
                hasPreviousLetters: this._prevLetterCache[id].length > 0
            });
            return;
        }
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
            cardClass:         this._cardClass(false),
            showPreview:       false,
            showPhotoRights:   raw.photoRightsAccepted === true,
            draftText:         raw.thankYouLetter || '',
            previousLetters:   [],
            hasPreviousLetters: false,
            actionLabel:       this._actionLabel(status),
            previewLabel:      'Preview',
            showExample:       false,
            exampleToggleLabel: 'Show Example',
            exampleToggleIcon: 'utility:chevronright',
            exampleText:       raw.sampleLetter || DEFAULT_EXAMPLE_HTML,
            charCountLabel:    this._charCountLabel(raw.thankYouLetter),
            previousSelectId:  `prev-${raw.applicantId}`,
            photoCheckboxId:   `photo-${raw.applicantId}`,
            photoInputId:      `photo-input-${raw.applicantId}`,
            photoFileName:     '',
            photoUploading:    false,
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

    // Rich text is stored/transmitted as HTML — measure the visible text only,
    // so the 100-character minimum reflects what the student actually wrote.
    _plainTextLength(html) {
        return (html || '')
            .replace(/<[^>]*>/g, '')
            .replace(/&nbsp;/g, ' ')
            .trim().length;
    }

    _charCountLabel(html) {
        const len = this._plainTextLength(html);
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
        this._setEditorOpen(id, !item.editorOpen);
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
            // Update the real rich text editor value
            const editor = this.template.querySelector(`lightning-input-rich-text[data-id="${id}"]`);
            if (editor) editor.value = cached.letterText;
        }
    }

    handleLetterChange(event) {
        const id   = event.currentTarget.dataset.id;
        const text = event.detail.value;
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

        const editor = this.template.querySelector(`lightning-input-rich-text[data-id="${id}"]`);
        const text   = editor ? editor.value : item.draftText;

        this.isLoading = true;
        saveThankYouDraft({ applicantId: id, letterText: text })
            .then(updated => {
                this._updateItem(id, {
                    ...this._enrichItem(updated),
                    editorOpen:  true,
                    cardClass:   this._cardClass(true),
                    showPreview: item.showPreview,
                    showExample: item.showExample,
                    exampleToggleLabel: item.exampleToggleLabel,
                    exampleToggleIcon: item.exampleToggleIcon,
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

        const editor = this.template.querySelector(`lightning-input-rich-text[data-id="${id}"]`);
        const text   = editor ? editor.value : item.draftText;

        // Client-side length guard (measured on visible text, not HTML markup)
        const plainLength = this._plainTextLength(text);
        if (plainLength < MIN_LENGTH) {
            this._showFeedback(
                'error',
                `Your letter must be at least ${MIN_LENGTH} characters. Current length: ${plainLength}.`
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
                    editorOpen: true,  // keep open so student can see confirmation
                    cardClass:  this._cardClass(true)
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

    // lightning-file-upload never fires its upload request when embedded via
    // Lightning Out on this VF Site page, so the portal editor uses a plain
    // file input and sends the file to Apex as base64 instead.
    handlePhotoUpload(event) {
        const id   = event.currentTarget.dataset.id;
        const file = event.target.files && event.target.files[0];
        if (!file) return;

        this._updateItem(id, { photoUploading: true });
        this._readFileAsBase64(file)
            .then(base64Data => uploadThankYouPhoto({ applicantId: id, fileName: file.name, base64Data }))
            .then(() => {
                this._updateItem(id, {
                    showPhotoRights: true,
                    photoFileName:   file.name,
                    photoUploading:  false
                });
                this._showFeedback('success', 'Photo uploaded successfully.');
            })
            .catch(err => {
                this._updateItem(id, { photoUploading: false });
                this._showFeedback('error', this._extractError(err));
            });
    }

    _readFileAsBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload  = () => resolve(reader.result.split(',')[1]);
            reader.onerror = () => reject(reader.error);
            reader.readAsDataURL(file);
        });
    }

    handlePhotoRightsChange(event) {
        const id      = event.currentTarget.dataset.id;
        const checked = event.target.checked;
        this._updateItem(id, { photoRightsAccepted: checked });
    }

    handleToggleExample(event) {
        const id   = event.currentTarget.dataset.id;
        const item = this._findItem(id);
        if (!item) return;
        const nowShowing = !item.showExample;
        this._updateItem(id, {
            showExample: nowShowing,
            exampleToggleLabel: nowShowing ? 'Hide Example' : 'Show Example',
            exampleToggleIcon: nowShowing ? 'utility:chevrondown' : 'utility:chevronright'
        });
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
        const text = event.detail.value;
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
            const editor = this.template.querySelector('.ty-record-textarea');
            if (editor) editor.value = cached.letterText;
        }
    }

    handleRecordSaveDraft() {
        const editor = this.template.querySelector('.ty-record-textarea');
        const text   = editor ? editor.value : this.singleItem.draftText;

        this.isLoading = true;
        saveThankYouDraft({ applicantId: this.recordId, letterText: text })
            .then(updated => {
                this._updateSingleItem({
                    ...this._enrichSingleItem(updated),
                    editorOpen:        true,
                    showPreview:       this.singleItem.showPreview,
                    showExample:       this.singleItem.showExample,
                    exampleToggleLabel: this.singleItem.exampleToggleLabel,
                    exampleToggleIcon: this.singleItem.exampleToggleIcon,
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
        const editor = this.template.querySelector('.ty-record-textarea');
        const text   = editor ? editor.value : this.singleItem.draftText;

        const plainLength = this._plainTextLength(text);
        if (plainLength < MIN_LENGTH) {
            this._showFeedback(
                'error',
                `Your letter must be at least ${MIN_LENGTH} characters. Current length: ${plainLength}.`
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

    handleRecordToggleExample() {
        const nowShowing = !this.singleItem.showExample;
        this._updateSingleItem({
            showExample: nowShowing,
            exampleToggleLabel: nowShowing ? 'Hide Example' : 'Show Example',
            exampleToggleIcon: nowShowing ? 'utility:chevrondown' : 'utility:chevronright'
        });
    }
}