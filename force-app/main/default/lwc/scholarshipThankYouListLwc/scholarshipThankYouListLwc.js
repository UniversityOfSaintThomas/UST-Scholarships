/**
 * scholarshipThankYouListLwc.js
 *
 * Lightweight nav list of a student's thank-you letter requirements: scholarship
 * name, status, and a progress bar. Clicking an item opens it for edit/review in
 * scholarshipThankYousLwc (portal mode).
 *
 * TWO USAGE MODES, controlled by the `inline` @api prop:
 *
 *  - inline = false (default) — standalone widget on any other portal page
 *    (e.g. ScholarshipHome). Clicking navigates the browser to `thankYouPageUrl`
 *    with `?applicantId=<id>` appended, which scholarshipThankYousLwc reads on
 *    load to auto-open that item.
 *
 *  - inline = true — dropped onto the ScholarshipThankYou page itself as a
 *    secondary nav alongside scholarshipThankYousLwc. Clicking updates the URL
 *    (via history.pushState, no reload) and dispatches a `window` CustomEvent
 *    that the sibling scholarshipThankYousLwc listens for, so the two
 *    independently Lightning-Out-mounted widgets can coordinate without a
 *    full page reload.
 *
 * Created: 2026-08-05
 */
import { LightningElement, api, track } from 'lwc';
import getThankYouItems from '@salesforce/apex/ScholarshipThankYouController.getThankYouItems';

const THANK_YOU_SELECT_EVENT = 'ustty_selectapplicant';

const STATUS_CLASS_MAP = {
    'Not Started': 'slds-badge slds-badge_lightest ty-badge-not-started',
    'In Progress':  'slds-badge ty-badge-in-progress',
    'Submitted':    'slds-badge ty-badge-submitted',
    'Complete':     'slds-badge ty-badge-complete'
};
const STATUS_PROGRESS_MAP = {
    'Not Started': 0,
    'In Progress': 50,
    'Submitted':   90,
    'Complete':    100
};

export default class ScholarshipThankYouListLwc extends LightningElement {

    // ─── Public API Props ────────────────────────────────────────────────────
    @api contactId;                            // Contact Id — passed from VF Lightning Out
    @api thankYouPageUrl = '/scholarshipthankyou'; // Used for non-inline (cross-page) navigation
    @api inline = false;                        // true when mounted alongside scholarshipThankYousLwc

    // ─── Tracked State ───────────────────────────────────────────────────────
    @track items = [];
    @track isLoading = true;
    activeApplicantId;
    errorMessage;

    connectedCallback() {
        this.activeApplicantId = new URLSearchParams(window.location.search).get('applicantId');
        this._loadItems();
    }

    get hasItems() { return this.items.length > 0; }
    get hasError() { return !!this.errorMessage; }

    _loadItems() {
        this.isLoading = true;
        getThankYouItems({ contactId: this.contactId })
            .then(items => {
                this.items = (items || []).map(i => this._enrich(i));
            })
            .catch(err => {
                this.errorMessage = this._extractError(err);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    _enrich(raw) {
        const status = raw.thankYouStatus || 'Not Started';
        return {
            ...raw,
            thankYouStatus: status,
            statusClass:    STATUS_CLASS_MAP[status] || 'slds-badge',
            progressValue:  STATUS_PROGRESS_MAP[status] ?? 0,
            rowClass:       this._rowClass(raw.applicantId)
        };
    }

    _rowClass(applicantId) {
        const base = 'ty-nav-row-wrap slds-m-bottom_xx-small';
        return applicantId === this.activeApplicantId ? `${base} ty-nav-row_active` : base;
    }

    handleSelect(event) {
        const id = event.currentTarget.dataset.id;
        if (!id) return;

        if (this.inline) {
            window.dispatchEvent(new CustomEvent(THANK_YOU_SELECT_EVENT, { detail: { applicantId: id } }));
            const url = new URL(window.location.href);
            url.searchParams.set('applicantId', id);
            // `null`, not `{}` — an object literal here gets Locker/LWS-proxy-wrapped
            // and pushState's DataCloneError on the proxy silently aborts everything
            // after this line, which is why the nav highlight never updated.
            window.history.pushState(null, '', url);
            this.activeApplicantId = id;
            this.items = this.items.map(i => ({ ...i, rowClass: this._rowClass(i.applicantId) }));
        } else {
            window.location.href = `${this.thankYouPageUrl}?applicantId=${id}`;
        }
    }

    _extractError(err) {
        if (err && err.body && err.body.message) return err.body.message;
        if (err && err.message) return err.message;
        return 'Unable to load your thank-you letters right now.';
    }
}
