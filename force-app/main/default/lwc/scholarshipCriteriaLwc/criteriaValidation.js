/**
 * Pure validation for Page 1 (criteria confirmation). Kept free of any LWC imports so it can be unit tested.
 *
 * Lower bounds match validateCriteria() in the scholarships static resource (scripts.js).
 * Upper bounds come from the Scholarship_Applicant__c field definitions
 * (Declared_GPA__c Number(3,2), Declared_ACT_SAT__c Number(4,0)).
 * ScholarshipAppPage1LwcController.validate() applies the same rules on the server.
 */
export const MIN_GPA = 1.0;
export const MAX_GPA = 9.99;
export const MIN_ACT_SAT = 10;
export const MAX_ACT_SAT = 9999;

export const GPA_ERROR = "Please enter a valid GPA (example 3.5).";
export const ACT_SAT_ERROR = "Please enter a valid ACT/SAT score (example 27).";
export const CONFIRM_ERROR = "You must confirm that you meet the eligibility criteria to continue.";

function toNumber(value) {
    if (value === null || value === undefined || String(value).trim() === "") {
        return null;
    }
    const number = Number(value);
    return Number.isNaN(number) ? null : number;
}

/**
 * @param {{confirmed: boolean, selfReportRequired: boolean, gpa: (string|number|null), actSat: (string|number|null)}} input
 * @returns {{isValid: boolean, errors: {gpa: (string|null), actSat: (string|null), confirmed: (string|null)}}}
 */
export function validateCriteria({confirmed, selfReportRequired, gpa, actSat}) {
    const errors = {gpa: null, actSat: null, confirmed: null};

    if (selfReportRequired) {
        const gpaNumber = toNumber(gpa);
        if (gpaNumber === null || gpaNumber < MIN_GPA || gpaNumber > MAX_GPA) {
            errors.gpa = GPA_ERROR;
        }

        const actSatNumber = toNumber(actSat);
        if (actSatNumber === null || actSatNumber < MIN_ACT_SAT || actSatNumber > MAX_ACT_SAT || !Number.isInteger(actSatNumber)) {
            errors.actSat = ACT_SAT_ERROR;
        }
    }

    if (!confirmed) {
        errors.confirmed = CONFIRM_ERROR;
    }

    return {
        isValid: !errors.gpa && !errors.actSat && !errors.confirmed,
        errors
    };
}

/**
 * Converts a field value from lightning-input into the number sent to Apex, or null when blank.
 */
export function parseNumber(value) {
    return toNumber(value);
}
